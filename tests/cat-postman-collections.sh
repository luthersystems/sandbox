# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#!/bin/bash

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")
PASSED_COLLECTIONS="$1"
ALL_COLLECTIONS=`find "${SOURCE_DIR}" -name "*postman_collection.json" -o -name "*martin_collection.yaml"  | grep -v e2e.postman_collection.json`
COLLECTIONS=${PASSED_COLLECTIONS:-$ALL_COLLECTIONS}

martin cat $COLLECTIONS
EXIT_STATUS=$?

exit $EXIT_STATUS
