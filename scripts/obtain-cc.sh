#!/usr/bin/env bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

PROJECT_REL_DIR=$(make echo:PROJECT_REL_DIR)
LICENSE_FILE=$(make echo:LICENSE_FILE)

if [ ! -f $LICENSE_FILE ]; then
    echo "File missing: $LICENSE_FILE"
fi

mkdir -p build

download-cc() {
  echo "Using pre-signed URL for chaincode:"
  CC_URL=$(cat $LICENSE_FILE | grep cc_url | awk '{print $2;}')
  wget -O "$1" $CC_URL
}

download-cc $(make echo:CC_PATH)

echo "+OK (obtain-cc.sh)"
