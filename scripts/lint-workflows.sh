#!/usr/bin/env bash
# Structural lint of every GitHub Actions workflow in this repo.
#
# Run locally as:
#   scripts/lint-workflows.sh
#
# Why this exists: GitHub does not fail a PR that adds an INVALID workflow
# file. It rejects the file at trigger time instead, so a broken scheduled
# workflow simply never runs, and the only trace is a 0-second "This run
# likely failed because of a workflow file issue" entry on each push that
# nobody reads. The triggering example: govulncheck-scheduled.yml declared the
# step id `releasego` twice from #110 on, so the daily govulncheck scan and its
# `govulncheck-drift` issue never fired once (the same bug silenced
# luthersystems/reliable's scheduled scan).
# actionlint flags that class of mistake (duplicate step ids, bad `needs`,
# unknown contexts/expressions, malformed `on:`) on the PR that introduces it.
#
# The embedded shellcheck/pyflakes passes are OFF: they flag style in existing
# `run:` blocks, which is a separate cleanup and would bury the structural
# errors this gate is for. Non-trivial shell belongs in scripts/, where it can
# be linted on its own.
set -euo pipefail

VERSION="${ACTIONLINT_VERSION:-v1.7.12}"

if ! command -v actionlint >/dev/null 2>&1; then
  for attempt in 1 2 3; do
    if timeout 240 go install "github.com/rhysd/actionlint/cmd/actionlint@${VERSION}"; then
      break
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "::error::could not install actionlint ${VERSION}"
      exit 1
    fi
    sleep $((attempt * 10))
  done
  PATH="$(go env GOPATH)/bin:${PATH}"
fi

actionlint -version | head -1
actionlint -shellcheck= -pyflakes=
