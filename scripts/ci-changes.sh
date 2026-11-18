#!/usr/bin/env bash
# Decide whether a CI run must run the build and test jobs.
#
# Why this exists: the main ruleset requires "CI (all required checks)", the
# gate job in sandbox.yml. A workflow-level paths or paths-ignore filter would
# skip the whole run on a docs-only PR, the gate would never report, and the
# PR would wait forever on a required check. So the run always starts, and
# this script tells the heavy jobs to skip instead.
#
# Rule: skip only when EVERY changed path is docs: a *.md file anywhere, or
# a file under docs/ or .claude/. Any other path, an empty diff or a git
# error means "run everything", so a mistake here costs CI minutes, never a
# missed test. Renames are listed as a delete plus an add (--no-renames), so
# moving code into docs/ is not docs-only.
#
# Usage: ci-changes.sh <base> <head>   (pull requests)
#        ci-changes.sh                 (any other event: run all)
# Prints "code=true" or "code=false" on stdout, for $GITHUB_OUTPUT, and the
# reason on stderr, so the run log says why the tests ran or skipped.
# scripts/ci-changes-test.sh tests it; the changes job runs that test.

set -euo pipefail

is_docs() {
  case "$1" in
    *.md | docs/* | .claude/*) return 0 ;;
    *) return 1 ;;
  esac
}

decide() {
  local base=$1 head=$2 files f
  if ! files=$(git diff --no-renames --name-only "$base...$head"); then
    echo "ci-changes: git diff $base...$head failed; running everything" >&2
    echo "code=true"
    return
  fi
  if [ -z "$files" ]; then
    echo "ci-changes: empty diff; running everything" >&2
    echo "code=true"
    return
  fi
  while IFS= read -r f; do
    if ! is_docs "$f"; then
      echo "ci-changes: $f is not docs; running everything" >&2
      echo "code=true"
      return
    fi
  done <<<"$files"
  echo "ci-changes: every changed path is docs; skipping build and test jobs" >&2
  echo "code=false"
}

if [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ]; then
  decide "$1" "$2"
else
  echo "ci-changes: not a pull request diff; running everything" >&2
  echo "code=true"
fi
