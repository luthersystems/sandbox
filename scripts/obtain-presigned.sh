#!/usr/bin/env bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

unset MAKELEVEL MFLAGS MAKEFLAGS
PRESIGNED_PATH=$(make echo:PRESIGNED_PATH)
PROJECT_REL_DIR=$(make echo:PROJECT_REL_DIR)
LICENSE_FILE=$(make echo:LICENSE_FILE)
SUBSTRATE_VERSION=$(make echo:SUBSTRATE_VERSION)
LICENSE_URL=https://license.luthersystemsapp.com/presign

if [ ! -f "$LICENSE_FILE" ]; then
    echo "File missing: $LICENSE_FILE"
fi

mkdir -p build

download-presigned() {
  echo -n "Downloading pre-signed URLs..."
  local license_b64=$(cat "$LICENSE_FILE" | base64 | tr -d "\n")
  local req_json='{"version":"'"$SUBSTRATE_VERSION"'","license":"'"$license_b64"'"}'
  curl -S -f -s -o "$PRESIGNED_PATH" \
      -X POST "$LICENSE_URL" \
      -H "Content-Type: application/json" \
      --data "$req_json"
  echo "OK"
}

download-presigned "$PRESIGNED_PATH"
