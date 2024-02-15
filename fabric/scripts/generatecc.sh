#!/bin/bash

script_dir=$(dirname "$0")
. ${script_dir}/luther_utils.sh

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build your first network (BYFN) end-to-end test"
echo

CC_VERSION=$1
CC_NAMES=$2
CC_SRC_PATH=$3
shift 3

ccaas=""
if [ "$1" == "--ccaas" ]; then
   ccaas="True"
fi

REL_PATH=".${CC_SRC_PATH}"

echo "=============== Generating chaincodes ==============="
echo
echo "CHANNEL=$CHANNEL CC_VERSION=$CC_VERSION CC_NAMES=$CC_NAMES"
echo

for CC_NAME in $CC_NAMES
do
  generateChaincode ${REL_PATH} ${CC_NAME} ${CC_VERSION} ${ccaas}
done

echo
echo "=========== All GOOD, Chaincode generated =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
