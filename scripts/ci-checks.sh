#!/usr/bin/env bash

# This script runs source code checking tools it can be called via a make
# target or can be run automatically during CI testing.

set -exuo pipefail

go vet ./...

#golint ./...

GOSEC_EXCLUSIONS="${GOSEC_EXCLUSIONS:-}"
#gosec -exclude="$GOSEC_EXCLUSIONS" ./...
