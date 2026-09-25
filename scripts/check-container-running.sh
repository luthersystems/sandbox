#!/usr/bin/env bash
# Catch container startup failures that detached docker run cannot report.
#
# Connectorhub containers are kept after exit so startup errors and logs remain
# available for inspection. Fail make up if the container stops during a short
# grace period, and show its logs to explain the failure.
#
# Run locally as:
#   scripts/check-container-running.sh <container-name>
# Optional env: CONTAINER_STARTUP_GRACE (seconds, default 10), DOCKER (binary).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <container-name>" >&2
  exit 2
fi

name=$1
docker=${DOCKER:-docker}
grace=${CONTAINER_STARTUP_GRACE:-10}
if [[ ! $grace =~ ^[0-9]+$ ]]; then
  echo "ERROR: CONTAINER_STARTUP_GRACE must be a non-negative integer" >&2
  exit 2
fi
deadline=$((SECONDS + 10#$grace))

while true; do
  if ! running=$("$docker" inspect -f '{{.State.Running}}' "$name") || [[ $running != true ]]; then
    exit_code=$("$docker" inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null) || exit_code=unknown
    echo "ERROR: Container $name stopped or could not be inspected during startup (exit code: $exit_code)." >&2
    "$docker" logs "$name" >&2 2>&1 || true
    echo "Container $name was kept for inspection: docker logs $name; remove with: docker rm $name" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "OK: Container $name is running after ${grace}s startup grace period."
    exit 0
  fi
  sleep 1
done
