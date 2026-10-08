#!/usr/bin/env bash
# Resolve the Go toolchain CI builds the oracle with, for the binary pass.
#
# Extracted from .github/workflows/govulncheck-scheduled.yml. Usage:
#
#   GITHUB_OUTPUT=/dev/stdout scripts/resolve-build-go.sh .github/workflows/sandbox.yml
#
# Why: the source scan deliberately runs under `stable` so the stdlib is checked
# at a current patch level. Binary mode checks the stdlib of whatever built the
# binary -- so building it with `stable` too would just re-check `stable` and say
# nothing about the toolchain the repo actually builds and tests with.
#
# sandbox publishes no release artifact, so the CI workflow's toolchain is the
# one that matters. Read from that workflow at run time rather than hardcoded so
# the two cannot silently drift apart. Hard-fails rather than falling back to
# `stable`, which would quietly reopen the gap it exists to close.
set -euo pipefail

src="${1:?usage: resolve-build-go.sh <path-to-ci-workflow>}"

if [ ! -f "$src" ]; then
  echo "::error::CI workflow not found: ${src}"
  exit 1
fi

version="$(grep -oE 'go-version: *"[^"]+"' "$src" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [ -z "$version" ]; then
  echo "::error::could not resolve the CI Go version from ${src}"
  exit 1
fi

echo "build toolchain: ${version}"
echo "version=${version}" >> "${GITHUB_OUTPUT:-/dev/null}"
