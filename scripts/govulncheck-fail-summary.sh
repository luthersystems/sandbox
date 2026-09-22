#!/usr/bin/env bash
# Final gate step for the govulncheck workflows.
#
# The job goes red for more than one reason and the check name ("govulncheck")
# reads as "security finding" for all of them. This step exists so the LAST
# thing in the log, and the top of the job summary, names which condition
# actually tripped. It never decides anything and never softens anything: it
# fails whenever any condition is set.
#
# Inputs (env, all optional — an unset/empty value counts as "did not trip"):
#   SOURCE_SCAN_FAILED    steps.scan.outputs.scan_failed
#   SOURCE_VULNS_FOUND    steps.scan.outputs.vulns_found
#   SOURCE_SCAN_EXIT      steps.scan.outputs.exit      (aggregate; fallback only)
#   BINARY_BUILD_FAILED   steps.binscan.outputs.build_failed
#   BINARY_VULNS_FOUND    steps.binscan.outputs.vulns_found
#
# Both passes now report a load/compile failure separately from a finding, so
# neither one can announce a build break as a vulnerability. SOURCE_SCAN_EXIT is
# the pre-existing aggregate and is consulted ONLY when the two granular source
# inputs are absent -- in that case the condition is unattributable, so it is
# named as such rather than guessed to be a finding.
#
# Run locally as:
#   BINARY_BUILD_FAILED=1 scripts/govulncheck-fail-summary.sh
set -uo pipefail

SOURCE_SCAN_FAILED="${SOURCE_SCAN_FAILED:-0}"
SOURCE_VULNS_FOUND="${SOURCE_VULNS_FOUND:-0}"
SOURCE_SCAN_EXIT="${SOURCE_SCAN_EXIT:-0}"
BINARY_BUILD_FAILED="${BINARY_BUILD_FAILED:-0}"
BINARY_VULNS_FOUND="${BINARY_VULNS_FOUND:-0}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

reasons=()
if [ "$SOURCE_SCAN_FAILED" != "0" ] && [ -n "$SOURCE_SCAN_FAILED" ]; then
  reasons+=("SCAN FAILURE: the source-mode pass could not load or analyse the module, or govulncheck was killed (e.g. out of memory), so it was not scanned. This is NOT a vulnerability finding.")
fi
if [ "$SOURCE_VULNS_FOUND" != "0" ] && [ -n "$SOURCE_VULNS_FOUND" ]; then
  reasons+=("VULNERABILITY: the source-mode scan reported a finding against a tree that analysed fine.")
fi
# Fallback for a caller that passes only the aggregate: something tripped, but
# nothing here can say which. Do not call it a finding.
if [ "$SOURCE_SCAN_FAILED" = "0" ] && [ "$SOURCE_VULNS_FOUND" = "0" ] &&
   [ "$SOURCE_SCAN_EXIT" != "0" ] && [ -n "$SOURCE_SCAN_EXIT" ]; then
  reasons+=("SOURCE-MODE PASS FAILED: exit=${SOURCE_SCAN_EXIT} with no condition breakdown reported — could be a finding or a load failure. Read the scan log.")
fi
if [ "$BINARY_BUILD_FAILED" != "0" ] && [ -n "$BINARY_BUILD_FAILED" ]; then
  reasons+=("BUILD FAILURE: a main package did not compile, so the binary-mode pass could not scan it. This is NOT a vulnerability finding.")
fi
if [ "$BINARY_VULNS_FOUND" != "0" ] && [ -n "$BINARY_VULNS_FOUND" ]; then
  reasons+=("VULNERABILITY: the binary-mode pass reported a finding against a binary that built fine.")
fi

if [ "${#reasons[@]}" -eq 0 ]; then
  echo "No govulncheck condition tripped — nothing to fail."
  exit 0
fi

{
  echo "## govulncheck failed"
  echo
  for r in "${reasons[@]}"; do
    echo "- ${r}"
  done
  echo
} >>"$SUMMARY_FILE"

echo "govulncheck failed for the following reason(s):"
for r in "${reasons[@]}"; do
  echo "  - ${r}"
done

exit 1
