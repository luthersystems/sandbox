# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#!/bin/bash

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

MARTIN=$(cd ${SOURCE_DIR} && make martincmd)
${MARTIN} cat-postman-collections.sh "$@"
