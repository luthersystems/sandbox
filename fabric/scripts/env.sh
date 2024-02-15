#!/bin/bash

script_dir=$(dirname "$0")

set -o errexit
set -o nounset
set -o pipefail

envfile=${script_dir}/../.env

rm -f ${envfile}

for file in ${script_dir}/../chaincodes/*.id; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" ".id")
	chaincode_name=${filename%%-*}
        chaincode_id=$(cat "$file")
	uppercase_name=$(echo "$chaincode_name" | tr '[:lower:]-' '[:upper:]_')
        echo "CCID_${uppercase_name}=$chaincode_id" >> ${envfile}
    fi
done
