#!/usr/bin/env bash
# Install govulncheck, pinned, with timeout+retry.
#
# Ported from luthersystems/ui-core scripts/govulncheck-install.sh. Run locally as:
#   scripts/govulncheck-install.sh
#
# Four ui-core runs of this job died the same way: the install hung on
# `go: downloading golang.org/x/tools` for 15+ minutes until the runner was shut
# down mid-job, surfacing as a red govulncheck check with nothing to do with this
# module's vulnerabilities. Killing a stuck fetch at 4 minutes and retrying turns
# that into a few wasted seconds.
set -euo pipefail

VERSION="${GOVULNCHECK_VERSION:-v1.8.0}"

for attempt in 1 2 3; do
  if timeout 240 go install "golang.org/x/vuln/cmd/govulncheck@${VERSION}"; then
    exit 0
  fi
  echo "::warning::govulncheck install attempt ${attempt} stalled; retrying"
  sleep $((attempt * 10))
done

echo "::error::could not install govulncheck after 3 attempts"
exit 1
