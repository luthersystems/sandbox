#!/bin/bash

SCRIPT="${BASH_SOURCE:-$0}"
SOURCE_DIR=$(dirname "$SCRIPT")

MARTIN=$(cd ${SOURCE_DIR}/.. && make martincmd)
${MARTIN} ${SOURCE_DIR}/cat-postman-collections.sh "$@"
