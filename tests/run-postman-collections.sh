# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#!/bin/bash

POSTMAN_ENVIRONMENT_FILE="$1"
SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")
PASSED_COLLECTIONS="$2"
ALL_COLLECTIONS=`find "${SOURCE_DIR}" -name "*postman_collection.json" -o -name "*martin_collection.yaml" | sort | grep -v e2e.postman_collection.json`
FALSE_MATCHES=`find "${SOURCE_DIR}" -name "*.yaml" | sort | grep -v martin_collection.yaml | grep -v init.yaml`
COLLECTIONS=${PASSED_COLLECTIONS:-$ALL_COLLECTIONS}

if [ -z "$POSTMAN_ENVIRONMENT_FILE" ]; then
    echo "usage: $SCRIPT POSTMAN_ENVIRONMENT_PATH" 1>&2
    exit 1
fi

martin run -i 1 -e "$POSTMAN_ENVIRONMENT_FILE" --pre "${SOURCE_DIR}/init.yaml" $COLLECTIONS
EXIT_STATUS=$?

if [ -z "$PASSED_COLLECTIONS" ] && [ -n "$FALSE_MATCHES" ]; then
    echo
    echo "WARNING: found yaml files that are not collections -- possible file naming error?" 1>&2
    echo "$FALSE_MATCHES" | sed 's/^/  /' 1>&2
fi

exit $EXIT_STATUS
