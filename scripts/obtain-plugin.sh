#!/usr/bin/env bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

unset MAKELEVEL MFLAGS MAKEFLAGS
PRESIGNED_PATH=$(make echo:PRESIGNED_PATH)

if [ ! -f "$PRESIGNED_PATH" ]; then
    echo "File missing: $PRESIGNED_PATH"
fi

mkdir -p build

download-plugin() {
    local os_upper="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    local os_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    local path="$(make echo:SUBSTRATE_PLUGIN_${os_upper})"
    echo "Using pre-signed URL for ${os_upper} plugin:"
    local jq_path=".substrate_plugin_${os_lower}_url"
    local plugin_url=$(cat "$PRESIGNED_PATH" | jq -r "$jq_path")
    wget -O "$path".tmp "$plugin_url"
    mv "$path"{.tmp,}
    chmod +x "$path"
}

download-plugin $(uname)

echo "+OK (obtain-plugin.sh)"
