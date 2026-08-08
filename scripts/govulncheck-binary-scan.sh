#!/usr/bin/env bash
# Binary-mode govulncheck pass for the scheduled workflow.
#
# Extracted from .github/workflows/govulncheck-scheduled.yml. Run locally as:
#
#   GITHUB_OUTPUT=/dev/stdout scripts/govulncheck-binary-scan.sh
#
# ADDITIVE to the source scan, never a replacement: source mode reports
# vulnerabilities in imported packages even when the linker dropped the code,
# which binary mode cannot see. What binary mode adds is reflection-reached code
# (the govulncheck docs state such calls are not reported in source scan mode)
# and the standard library at the version the binary was BUILT with rather than
# the version the scanner runs under.
#
# Library modules have no main packages; there this is a no-op, not an error.
set -uo pipefail

REPORT_PATH="${REPORT_PATH:-/tmp/govulncheck.txt}"
BIN_DIR="${BIN_DIR:-/tmp/gv-bins}"

mains="$(go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... | grep -v '^$' || true)"
if [ -z "$mains" ]; then
  echo "No main packages in this module — binary mode does not apply."
  echo "exit=0" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

mkdir -p "$BIN_DIR"
status=0
for pkg in $mains; do
  out="${BIN_DIR}/$(echo "$pkg" | tr '/' '_')"
  go build -o "$out" "$pkg"
  echo "::group::govulncheck -mode=binary ${pkg}"
  # pipefail so the pipeline reports govulncheck's status rather than tee's;
  # `if !` so a finding does not abort the loop before later binaries are scanned.
  if ! govulncheck -mode=binary "$out" 2>&1 | tee -a "$REPORT_PATH"; then
    status=1
  fi
  echo "::endgroup::"
  rm -f "$out"
done

echo "exit=${status}" >> "${GITHUB_OUTPUT:-/dev/null}"
exit 0
