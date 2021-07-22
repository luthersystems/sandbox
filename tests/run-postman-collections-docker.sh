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

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

cd "$SOURCE_DIR"

unset MAKELEVEL
MARTIN_NETWORK=$(make echo:RUN_MARTIN_NETWORK)
MARTIN=$(make echo:RUN_MARTIN)

docker network inspect fnb_byfn &> /dev/null
RESULT="$?"
if [ $RESULT -eq 0 ]; then
	echo ${MARTIN_NETWORK}
	${MARTIN_NETWORK} ${SOURCE_DIR}/run-postman-collections.sh "$@"
else
	echo ${MARTIN}
	${MARTIN} ${SOURCE_DIR}/run-postman-collections.sh "$@"
fi
