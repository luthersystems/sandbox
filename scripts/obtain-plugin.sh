#!/usr/bin/env bash
# Copyright © 2024 Luther Systems, Ltd. All right reserved.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

# MAKEFLAGS is unset so the inner `make echo:...` calls print clean values, but
# that also drops a command-line override such as
# `make SUBSTRATE_VERSION=vX plugin`.  The plugin rule in the Makefile passes
# SUBSTRATE_VERSION in the environment; forward it explicitly to the inner make
# so the downloaded plugin matches the path the outer make expects.
unset MAKELEVEL MFLAGS MAKEFLAGS

export DOWNLOAD_ROOT="https://download.luthersystemsapp.com/substratehcp"

mkdir -p build

download-plugin() {
  local os_upper="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  local os_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  local plugin_path="$(make ${SUBSTRATE_VERSION:+"SUBSTRATE_VERSION=${SUBSTRATE_VERSION}"} echo:SUBSTRATE_PLUGIN_${os_upper})"
  local plugin_url="${DOWNLOAD_ROOT}/$(basename $plugin_path)"
  wget -O "${plugin_path}.tmp" "$plugin_url"
  mv "${plugin_path}.tmp" "$plugin_path"
  chmod +x "$plugin_path"
}

for os in linux darwin; do
  download-plugin $os
done

echo "+OK (obtain-plugin.sh)"
