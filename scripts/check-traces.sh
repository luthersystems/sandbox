#!/usr/bin/env bash
# Copyright © 2026 Luther Systems, Ltd. All right reserved.
#
# check-traces.sh checks that tracing works end to end, after a test run
# with the tracing stack (make up TRACING=1 and make integration):
#
# - the span file (build/otlp/traces.jsonl) has spans from every service
#   named in EXPECT_SERVICES, so each layer sent spans to the collector and
#   x-profile-request reached past the oracle;
# - Tempo returns traces for each of them, so the collector forwards them.
#
# Why a script: tracing fails quietly. A service with a wrong endpoint, a
# header the oracle does not forward, or a collector that cannot write its
# file still lets every test pass. This makes those failures visible.
#
# It waits up to WAIT_TIMEOUT seconds (default 60) for the spans, since the
# services export in batches a few seconds after the requests.
#
# Usage: scripts/check-traces.sh
#   EXPECT_SERVICES  default "oracle shiroclient substrate"; mem mode has no
#                    gateway, so use "oracle substrate" there.
#   SPAN_FILE        default build/otlp/traces.jsonl
#   TEMPO_URL        default http://localhost:3200

set -o errexit
set -o nounset
set -o pipefail

EXPECT_SERVICES="${EXPECT_SERVICES:-oracle shiroclient substrate}"
SPAN_FILE="${SPAN_FILE:-build/otlp/traces.jsonl}"
TEMPO_URL="${TEMPO_URL:-http://localhost:3200}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"

# batches prints each complete OTLP batch of the span file. otelcol may be
# writing its last line, so a line that is not yet JSON is skipped.
batches() {
    [ -s "$SPAN_FILE" ] || return 0
    jq -c -R 'fromjson? // empty' "$SPAN_FILE"
}

# services_in_file prints the service.name of every resource in the file.
services_in_file() {
    batches | jq -r '.resourceSpans[]?.resource.attributes[]?
                     | select(.key == "service.name") | .value.stringValue' |
        sort -u
}

missing_in_file() {
    local have
    have="$(services_in_file)"
    for s in $EXPECT_SERVICES; do
        grep -qx "$s" <<<"$have" || echo "$s"
    done
}

# tempo_traces prints how many traces Tempo finds for a service.
tempo_traces() {
    curl -sS --max-time 10 -G "$TEMPO_URL/api/search" \
        --data-urlencode "q={resource.service.name=\"$1\"}" \
        --data-urlencode "limit=20" | jq '.traces | length'
}

missing_in_tempo() {
    for s in $EXPECT_SERVICES; do
        n="$(tempo_traces "$s" 2>/dev/null || echo 0)"
        [ "${n:-0}" -gt 0 ] || echo "$s"
    done
}

deadline=$((SECONDS + WAIT_TIMEOUT))
while :; do
    file_missing="$(missing_in_file)"
    tempo_missing="$(missing_in_tempo)"
    if [ -z "$file_missing" ] && [ -z "$tempo_missing" ]; then
        break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "check-traces: after ${WAIT_TIMEOUT}s:" >&2
        [ -z "$file_missing" ] || echo "  no spans in $SPAN_FILE from: $(echo $file_missing)" >&2
        [ -z "$tempo_missing" ] || echo "  no traces in Tempo from: $(echo $tempo_missing)" >&2
        echo "  services in $SPAN_FILE: $(echo $(services_in_file))" >&2
        exit 1
    fi
    sleep 2
done

echo "check-traces: spans in $SPAN_FILE and Tempo from: $EXPECT_SERVICES"
batches | jq -r '.resourceSpans[]? as $r
       | ($r.resource.attributes[]? | select(.key == "service.name") | .value.stringValue) as $s
       | $r.scopeSpans[]?.spans[]? | $s' | sort | uniq -c |
    awk '{printf "  %-12s %s spans\n", $2, $1}'
