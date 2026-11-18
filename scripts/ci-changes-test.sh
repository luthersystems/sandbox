#!/usr/bin/env bash
# Tests for scripts/ci-changes.sh and for the CI gate's needs list.
#
# Why: ci-changes.sh decides whether the required build and test jobs run.
# A bug that prints code=false for a code change would skip every test while
# the required gate stays green, so the changes job runs this test before it
# decides. The second check fails when a job in sandbox.yml is missing
# from the gate's needs list, which would let that job fail without blocking
# the merge.
#
# Usage (from the repository root): scripts/ci-changes-test.sh

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/ci-changes.sh"
workflow="$root/.github/workflows/sandbox.yml"
fails=0

expect() {
  local want=$1 got=$2 name=$3
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    fails=$((fails + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
git config user.email ci@example.com
git config user.name ci
mkdir -p src docs .claude
echo a >src/main.go
echo a >src/notes.txt
git add -A
git commit -qm base
base=$(git rev-parse HEAD)

commit() {
  git add -A
  git commit -qm "$1"
  git rev-parse HEAD
}

run() { "$script" "$@" 2>/dev/null; }

git checkout -q -b docs "$base"
echo a >README.md
echo a >docs/guide.txt
echo a >.claude/skill
echo a >src/deep.md
h=$(commit docs)
expect code=false "$(run "$base" "$h")" "docs-only diff skips"

git checkout -q -b code "$base"
echo a >README.md
echo b >src/main.go
h=$(commit code)
expect code=true "$(run "$base" "$h")" "docs plus code runs"

git checkout -q -b move "$base"
mkdir -p docs
git mv src/notes.txt docs/notes.txt
h=$(commit move)
expect code=true "$(run "$base" "$h")" "moving code into docs/ runs"

git checkout -q -b tomd "$base"
git mv src/main.go src/main.md
h=$(commit tomd)
expect code=true "$(run "$base" "$h")" "renaming code to .md runs"

expect code=true "$(run "$base" "$base")" "empty diff runs"
expect code=true "$(run deadbeef "$h")" "bad base runs"
expect code=true "$(run "" "$h")" "empty base runs"
expect code=true "$(run)" "no arguments runs"

# Every job in the workflow, except the gate itself, must be in its needs.
jobs=$(awk '/^jobs:/{in_jobs=1; next} in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{sub(/^  /,""); sub(/:.*/,""); print}' "$workflow" | grep -vx ci-all | sort)
needs=$(awk '/^  ci-all:/{in_gate=1} in_gate && /^    needs:/{print; exit}' "$workflow" |
  sed -e 's/^ *needs: *\[//' -e 's/\].*//' | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort)
if [ -n "$jobs" ] && [ "$jobs" = "$needs" ]; then
  echo "ok   gate needs every job"
else
  echo "FAIL gate needs list differs from the workflow's jobs"
  diff <(echo "$jobs") <(echo "$needs") || true
  fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
  echo "$fails check(s) failed"
  exit 1
fi
