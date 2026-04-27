#!/bin/bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

MARTIN=$(cd ${SOURCE_DIR} && make --no-print-directory martincmd)
${MARTIN} cat-postman-collections.sh "$@"
