#!/usr/bin/env bash
# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# Common scripts for setting env variables for compose.

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

unset MAKELEVEL MFLAGS MAKEFLAGS

export DOCKER_UID="$(id -u)"
export DOCKER_GID="$(id -g)"

export VERSION="$(grep '^VERSION=' common.mk | awk -F= '{print $2}')"
export VERSION_SUBSTRATE="$(grep '^CC_VERSION=' common.mk | awk -F= '{print $2}')"
PHYLUM_VERSION_FILE="$(grep '^PHYLUM_VERSION_FILE=' common.fabric.mk | awk -F= '{print $2}')"
mkdir -p $(dirname ./fabric/"$PHYLUM_VERSION_FILE")
touch ./fabric/"$PHYLUM_VERSION_FILE"
export PHYLUM_VERSION="$(cat ./fabric/"$PHYLUM_VERSION_FILE")"
export SUBSTRATE_PLUGIN_LINUX=$(make -f ./common.go.mk echo:SUBSTRATE_PLUGIN_LINUX)
