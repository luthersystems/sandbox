#!/usr/bin/env bash
# Resolve the Go toolchain the RELEASE pipeline builds with, for the binary pass.
#
# Extracted from .github/workflows/govulncheck-scheduled.yml. Usage:
#
#   GITHUB_OUTPUT=/dev/stdout scripts/resolve-release-go.sh .github/workflows/<release>.yml
#
# Why: the source scan deliberately runs under `stable` so the stdlib is checked
# at a current patch level. Binary mode checks the stdlib of whatever built the
# binary -- so building it with `stable` too would just re-check `stable` and say
# nothing about the artifact we actually ship.
#
# Read from the release workflow at run time rather than hardcoded so the two
# cannot silently drift apart. Hard-fails rather than falling back to `stable`,
# which would quietly reopen the gap it exists to close.
set -euo pipefail

src="${1:?usage: resolve-release-go.sh <path-to-release-workflow>}"

if [ ! -f "$src" ]; then
  echo "::error::release workflow not found: ${src}"
  exit 1
fi

version="$(grep -oE 'go-version: *"[^"]+"' "$src" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [ -z "$version" ]; then
  echo "::error::could not resolve the release Go version from ${src}"
  exit 1
fi

echo "release toolchain: ${version}"
echo "version=${version}" >> "${GITHUB_OUTPUT:-/dev/null}"
