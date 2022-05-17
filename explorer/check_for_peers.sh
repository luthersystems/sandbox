#!/usr/bin/env bash

PEERS_EXTANT=$(docker ps -a --format '{{.Names}}' -f "name=^peer[0-9]+\.org[0-9]+")
if [ -z "$PEERS_EXTANT" ]; then
    echo "Explorer cannot run without network to connect to."
    exit 1
fi
exit 0
