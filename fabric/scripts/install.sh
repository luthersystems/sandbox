#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build your first network (BYFN) end-to-end test"
echo

CHANNEL=$1
CC_VERSION=$2
CC_NAMES=$3
CC_SRC_PATH=$4
shift 4

initopt=""
if [ "$1" == "--init-required" ]; then
    initopt="--init-required"
fi

# import utils
. /scripts/luther_utils.sh

echo "=============== Installing chaincode on all peers ==============="
echo
echo "CHANNEL=$CHANNEL CC_VERSION=$CC_VERSION CC_NAMES=$CC_NAMES"
echo "CC_SRC_PATH=$CC_SRC_PATH"
echo

for CC_NAME in $CC_NAMES
do
  forEachPeer installChaincode "$CC_SRC_PATH" "$CC_NAME" "$CC_VERSION"
  seq_no="$(nextSequenceNumber "$CHANNEL" "$CC_NAME" "$CC_VERSION")"
  echo -e "next sequence number: ${seq_no}\n"
  forEachOrg approveChaincode "$CHANNEL" "$CC_NAME" "$CC_VERSION" "$seq_no" "$initopt"
  forEachOrg waitForChaincodeCommitReadiness "$CHANNEL" "$CC_NAME" "$CC_VERSION" "$seq_no" "$initopt"
  commitChaincode "$CHANNEL" "$CC_NAME" "$CC_VERSION" "$seq_no" "$initopt"
  forEachOrg waitForCommittedVersion "$CHANNEL" "$CC_NAME" "$CC_VERSION"
done

echo
echo "========= All GOOD, Chaincode installed on all peers =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
