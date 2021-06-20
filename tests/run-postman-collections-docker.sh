# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#!/bin/bash

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

MARTIN_NETWORK=$(cd ${SOURCE_DIR}/.. && make martincmdnetwork)
MARTIN=$(cd ${SOURCE_DIR}/.. && make martincmd)

docker network inspect fnb_byfn &> /dev/null
RESULT="$?"
if [ $RESULT -eq 0 ]; then
	echo ${MARTIN_NETWORK}
	${MARTIN_NETWORK} ${SOURCE_DIR}/run-postman-collections.sh "$@"
else
	echo ${MARTIN}
	${MARTIN} ${SOURCE_DIR}/run-postman-collections.sh "$@"
fi
