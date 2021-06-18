#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

LICENSE_FILE=$(make echo:LICENSE_FILE)

if [ ! -f $LICENSE_FILE ]; then
    echo "File missing: $LICENSE_FILE"
fi

mkdir -p build

download-plugin() {
    local os="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    local path="$(make echo:SUBSTRATE_PLUGIN_$os)"
    echo "Using pre-signed URL for $os plugin:"
    PLUGIN_URL=$(cat $LICENSE_FILE | grep -i $os | awk '{print $2;}')
    wget -O "$path".tmp $PLUGIN_URL
    mv "$path"{.tmp,}
    chmod +x "$path"
}

for os in linux darwin
do
    download-plugin $os
done

echo "+OK (obtain-plugin.sh)"
