#!/usr/bin/env bash
# Source-mode govulncheck scan, shared by the PR gate (govulncheck.yml) and the
# daily scheduled run (govulncheck-scheduled.yml) so the two cannot drift apart.
#
# Ported from luthersystems/ui-core scripts/govulncheck-scan.sh (the fleet's
# most complete version). Run locally exactly as CI does:
#
#   GITHUB_OUTPUT=/dev/stdout scripts/govulncheck-scan.sh
#
# Writes the full report to $REPORT_PATH (the drift-issue body reads it) and
# three step outputs to $GITHUB_OUTPUT. It deliberately does NOT fail the step
# itself: the workflow decides, after the binary pass has also run, so a
# condition in one mode cannot mask the other.
#
# ---------------------------------------------------------------------------
# SCAN FAILURE vs VULNERABILITY FINDING
# ---------------------------------------------------------------------------
# govulncheck exits non-zero for two unrelated reasons, and they call for
# completely different responses:
#
#   vulns_found=1   exit 3, govulncheck's documented "vulnerabilities found"
#                   code. This IS a security finding.
#   scan_failed=1   any other non-zero exit. govulncheck could not load or
#                   analyse the module (it does not compile, a dep is missing)
#                   or the process was killed (137 = SIGKILL, usually the
#                   kernel OOM killer; 143 = SIGTERM). NOT a security finding,
#                   but nothing was scanned.
#
# BOTH still fail, deliberately: an unscanned module is not a clean module.
# What changes is only diagnosability -- each condition gets its own
# `::error::`, job-summary line and step output, so a reader (and the
# tracking-issue writer in scripts/govulncheck-drift.cjs) can tell them apart.
# Triggering examples: ui-core#477/#478, where a module that failed to load was
# reported as "VULNERABILITY: the source-mode scan reported a finding", and the
# previous version of this script, which folded every non-zero exit into one
# `exit=N` output.
#
# ---------------------------------------------------------------------------
# MEMORY
# ---------------------------------------------------------------------------
# govulncheck builds SSA and a whole-program call graph in memory. This module
# is small today (2026-09, go1.26.8, govulncheck v1.8.0: ~1.6 GiB peak RSS,
# ~11 s), but the same script runs fleet-wide and a larger module's scan can
# exhaust the runner: luthersystems/reliable peaks at ~8 GiB unconstrained, and
# insideout-mcp was killed with exit 143 at ~13.9 GB. When the kernel
# OOM-kills the process the step reports exit 137 -- or, if the whole box is
# exhausted, the runner is lost ("The runner has received a shutdown signal"),
# which reads like a CI flake. GOMEMLIMIT gives the GC a ceiling under the
# box's real memory so it collects harder instead of being killed.
#
# Sized from /proc/meminfo at run time, NOT hardcoded, so the same script is
# right on a 16 GiB public-repo runner, a 7-8 GiB private one, and a laptop:
# total memory minus max(1 GiB, 1/8 of total) of headroom for the non-heap RSS
# and the `go list` children. Do not size it much tighter than the live heap:
# reliable's scan was still running after 10 minutes at GOMEMLIMIT=5000MiB
# (+GOGC=50), against ~2 minutes unconstrained. A caller-supplied GOMEMLIMIT
# wins, for local experiments.
#
# If the scan is killed anyway, it surfaces as scan_failed with an explicit
# "killed -- likely out of memory" error, and a lost runner is caught by the
# `report-incomplete` job in govulncheck-scheduled.yml -- never as silence.
#
# `set -o pipefail` below is load-bearing: without it the `govulncheck | tee`
# pipeline would report tee's status, which always succeeds, and every finding
# would be swallowed. The status is captured with `|| gv_status=$?` on the
# pipeline itself, never via ${PIPESTATUS[0]} -- PIPESTATUS is clobbered by ANY
# subsequent command and reading it late silently passes the gate.
set -uo pipefail

REPORT_PATH="${REPORT_PATH:-/tmp/govulncheck.txt}"
OUT_FILE="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -z "${GOMEMLIMIT:-}" ]; then
  mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if [ -n "$mem_kb" ]; then
    headroom_kb=$((mem_kb / 8))
    if [ "$headroom_kb" -lt 1048576 ]; then
      headroom_kb=1048576
    fi
    export GOMEMLIMIT="$((mem_kb - headroom_kb))KiB"
  fi
fi
echo "MemTotal=${mem_kb:-unknown}KiB GOMEMLIMIT=${GOMEMLIMIT:-unset} GOGC=${GOGC:-100}"

# emit_outputs <scan_failed> <vulns_found>
#
# `exit` is the aggregate the workflows gate on; scan_failed / vulns_found are
# the separately-readable conditions and mirror the binary pass's
# build_failed / vulns_found.
emit_outputs() {
  local aggregate=0
  if [ "$1" != "0" ] || [ "$2" != "0" ]; then
    aggregate=1
  fi
  {
    echo "scan_failed=$1"
    echo "vulns_found=$2"
    echo "exit=${aggregate}"
  } >>"$OUT_FILE"
}

: >"$REPORT_PATH"

echo "::group::govulncheck ./..."
gv_status=0
govulncheck ./... 2>&1 | tee -a "$REPORT_PATH" || gv_status=$?
echo "::endgroup::"
echo "govulncheck exit status: ${gv_status}"

case "$gv_status" in
  0)
    emit_outputs 0 0
    ;;
  3)
    echo "::error title=govulncheck source pass: vulnerability found::govulncheck reported a reachable vulnerability in ./... . The module analysed fine -- this IS a security finding."
    {
      echo "### govulncheck source pass: findings"
      echo
      echo 'govulncheck exited 3 (vulnerabilities found). See the report in the step log.'
      echo
    } >>"$SUMMARY_FILE"
    emit_outputs 0 1
    ;;
  *)
    why="it could not load or analyse the module -- most often a compile or module error"
    if [ "$gv_status" -eq 137 ] || [ "$gv_status" -eq 143 ]; then
      why="the process was KILLED (exit ${gv_status}) -- most likely out of memory (GOMEMLIMIT=${GOMEMLIMIT:-unset})"
    fi
    echo "::error title=govulncheck source pass: SCAN FAILURE (not a vulnerability)::govulncheck exited ${gv_status}, which is not its vulnerabilities-found code (3): ${why}. The module was NOT scanned -- an unscanned module is not a clean one."
    {
      echo "=== SCAN FAILURE: ./... (govulncheck exit ${gv_status}) ==="
      echo "Source-mode govulncheck did not complete: ${why}."
      echo "NOT a vulnerability finding, but nothing was scanned."
    } >>"$REPORT_PATH"
    {
      echo "### govulncheck source pass: SCAN FAILURE (not a vulnerability)"
      echo
      echo "govulncheck exited ${gv_status}: ${why}. The module was **not scanned**."
      echo
    } >>"$SUMMARY_FILE"
    emit_outputs 1 0
    ;;
esac
exit 0
