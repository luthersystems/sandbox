#!/usr/bin/env bash
# Copyright © 2024 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

unset MAKELEVEL MFLAGS MAKEFLAGS

export DOWNLOAD_ROOT="https://download.luthersystemsapp.com/substratehcp"

mkdir -p build

download-plugin() {
  local os_upper="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  local os_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  local plugin_path="$(make echo:SUBSTRATE_PLUGIN_${os_upper})"
  local plugin_url="${DOWNLOAD_ROOT}/$(basename $plugin_path)"
  wget -O "${plugin_path}.tmp" "$plugin_url"
  mv "${plugin_path}.tmp" "$plugin_path"
  chmod +x "$plugin_path"
}

for os in linux darwin; do
  download-plugin $os
done

echo "+OK (obtain-plugin.sh)"
