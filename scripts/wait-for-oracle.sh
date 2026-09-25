#!/usr/bin/env bash
# Wait for the oracle and phylum before running integration tests.
#
# Why this exists: health_check returns HTTP 200 even when the phylum is DOWN.
# Detached Compose startup does not wait for the gateway and chaincode to be
# ready, so check the reports in the response before starting the tests.
set -euo pipefail

ORACLE_HEALTH_URL="${ORACLE_HEALTH_URL:-http://localhost:8080/v1/sandbox/health_check}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
WAIT_INTERVAL="${WAIT_INTERVAL:-5}"

if [[ ! "$WAIT_TIMEOUT" =~ ^[1-9][0-9]*$ || ! "$WAIT_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: WAIT_TIMEOUT and WAIT_INTERVAL must be positive whole seconds" >&2
    exit 1
fi

deadline=$((SECONDS + WAIT_TIMEOUT))
attempt=0
last_response="No response received"
while (( SECONDS < deadline )); do
    attempt=$((attempt + 1))
    if response=$(curl -sS --max-time 10 -w $'\n%{http_code}' "$ORACLE_HEALTH_URL" 2>&1); then
        http_code="${response##*$'\n'}"
        body="${response%$'\n'*}"
        last_response="HTTP $http_code: $body"
        if [[ "$http_code" != 200 ]]; then
            reason="HTTP $http_code"
        elif reason=$(python3 -c '
import json
import sys

def fail(message):
    print(message)
    sys.exit(1)

try:
    data = json.load(sys.stdin)
except ValueError as exc:
    fail("Invalid JSON: " + str(exc))
if not isinstance(data, dict):
    fail("Expected a JSON object")
if data.get("exception"):
    fail("Response contains exception: " + str(data["exception"]))
reports = data.get("reports")
if not isinstance(reports, list) or len(reports) < 2:
    fail("Expected at least 2 health reports (phylum and oracle)")
unhealthy = []
for index, report in enumerate(reports):
    if not isinstance(report, dict):
        unhealthy.append("report {} is not an object".format(index + 1))
    elif str(report.get("status", "")).upper() != "UP":
        unhealthy.append("{}={}".format(
            report.get("service_name") or report.get("serviceName")
            or "report {}".format(index + 1),
            report.get("status", "missing status")))
if unhealthy:
    fail("Services not UP: " + ", ".join(unhealthy))
' <<< "$body" 2>&1); then
            echo "OK: Oracle ready at $ORACLE_HEALTH_URL (attempt $attempt)"
            exit 0
        fi
    else
        response="${response%$'\n'*}"
        last_response="$response"
        reason="Request failed: $response"
    fi
    printf 'Waiting for oracle (attempt %s): %s\n' "$attempt" "${reason//$'\n'/ }"
    remaining=$((deadline - SECONDS))
    if (( remaining <= 0 )); then
        break
    fi
    delay=$WAIT_INTERVAL
    if (( delay > remaining )); then
        delay=$remaining
    fi
    sleep "$delay"
done

printf 'ERROR: Oracle at %s not ready after %s seconds. Last response/error: %s\n' \
    "$ORACLE_HEALTH_URL" "$WAIT_TIMEOUT" "$last_response" >&2
exit 1
