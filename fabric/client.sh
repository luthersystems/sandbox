#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

CMD=$(make --no-print-directory call_cmd-sandbox)

stderr_log=$(mktemp)
output_log=$(mktemp) # Temporary file to capture command output

# Function to run the command and handle its output
run_command() {
  if $CMD "$@" >"$output_log" 2>"$stderr_log"; then
    cat "$output_log" # Ensure the output is still displayed or processed
    return 0
  else
    local status=$?
    echo "Command failed with status $status, showing stderr log:" >&2
    cat "$stderr_log" >&2
    return $status
  fi
}

handle_jq() {
  sed '/\[fab/d' "$1" | jq '.' || {
    echo "jq parse error. Original output:" >&2
    cat "$1" >&2 # Show original output on jq parse error
    return 1
  }
}

if [ "$#" -ge 2 ]; then
  if ! output=$(run_command "$@"); then
    echo "run_command exit 1"
    exit 1
  fi
  if ! handle_jq "$output_log"; then
    exit 1
  fi
else
  echo "Invalid number of args" >&2
  exit 1
fi

rm -f "$stderr_log" "$output_log"
