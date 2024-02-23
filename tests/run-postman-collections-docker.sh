# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# run-postman-collections-docker.sh
#
# This script executes martin in a docker container, running any test
# collection files it is given as argumont or running all tests if no arguments
# are given.
#
# NOTE:  This script can only accept paths that are relative to the tests/
# directory as the docker container will use that directory as the working
# directory.  Run `make integration` in the project's root directory to run
# tests from another directory.

#!/bin/bash

set -o errexit
set -o nounset

unset MAKELEVEL MFLAGS MAKEFLAGS

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

cd "$SOURCE_DIR"

MARTIN_NETWORK=$(make echo:RUN_MARTIN_NETWORK)
MARTIN=$(make echo:RUN_MARTIN)
MARTIN_BIND_SOURCE=$(make echo:MARTIN_BIND_SOURCE)
MARTIN_BIND_DEST=$(make echo:MARTIN_BIND_DEST)

if docker network inspect byfn 1>/dev/null 2>/dev/null; then
    cmd="$MARTIN_NETWORK"
else
    cmd="$MARTIN"
fi

echo ${cmd}
if ! ${cmd} ${MARTIN_BIND_DEST}/tests/run-postman-collections.sh "$@"; then
    set -x
    docker ps
    docker logs sandbox_oracle
    docker logs shiroclient_gw_sandbox
    docker logs fnb-sandbox-peer0-1
    exit 1
fi
