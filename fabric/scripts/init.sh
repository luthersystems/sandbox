#!/bin/bash

echo
echo ' ____    _____      _      ____    _____ '
echo '/ ___|  |_   _|    / \    |  _ \  |_   _|'
echo '\___ \    | |     / _ \   | |_) |   | |  '
echo ' ___) |   | |    / ___ \  |  _ <    | |  '
echo '|____/    |_|   /_/   \_\ |_| \_\   |_|  '
echo
echo 'Build your first network (BYFN) end-to-end test'
echo

CC_NAME="$1"
CHANNEL_NAME="$2"
CONSTRUCTOR="$3"

# import utils
. /scripts/luther_utils.sh

echo "CC_NAME=$CC_NAME CHANNEL_NAME=$CHANNEL_NAME CONSTRUCTOR=$CONSTRUCTOR"

set -x

peer chaincode invoke \
     $(peerArgsEachOrg) \
     -o "orderer0.${DOMAIN_NAME}:7050" \
     --tls --cafile $ORDERER_CA --clientauth --certfile $CORE_PEER_TLS_CERT_FILE --keyfile $CORE_PEER_TLS_KEY_FILE  \
     -C "$CHANNEL_NAME" -n "$CC_NAME" \
     --isInit -c "$CONSTRUCTOR" --waitForEvent
res="$?"
set +x
verifyResult "$res" 'Chaincode initialize failed'

echo
echo '========= All GOOD, Chaincode initialized =========== '
echo

echo
echo ' _____   _   _   ____   '
echo '| ____| | \ | | |  _ \  '
echo '|  _|   |  \| | | | | | '
echo '| |___  | |\  | | |_| | '
echo '|_____| |_| \_| |____/  '
echo

exit 0
