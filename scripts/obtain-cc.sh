#!/usr/bin/env bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

unset MAKELEVEL MFLAGS MAKEFLAGS
PRESIGNED_PATH=$(make echo:PRESIGNED_PATH)
CC_PATH=$(make echo:CC_PATH)

if [ ! -f "$PRESIGNED_PATH" ]; then
    echo "File missing: $PRESIGNED_PATH"
fi

mkdir -p build

download-cc() {
  local cc_path=$1
  echo "Using pre-signed URL for chaincode:"
  local jq_path=".substrate_cc_url"
  local cc_url=$(cat "$PRESIGNED_PATH" | jq -r "$jq_path")
  wget -O "$cc_path" "$cc_url"
}

download-cc "$CC_PATH"

echo "+OK (obtain-cc.sh)"
