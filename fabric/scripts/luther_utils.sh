#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

script_dir=$(dirname "$0")
. ${script_dir}/variables.sh

# This is a collection of bash functions used by different scripts
ORDERER_CA="/crypto-config/ordererOrganizations/${DOMAIN_NAME}/orderers/orderer0.${DOMAIN_NAME}/msp/tlscacerts/tlsca.${DOMAIN_NAME}-cert.pem"

# verify the result of the end-to-end test
verifyResult() {
    if [ $1 -ne 0 ] ; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!" >&2
        echo "========= ERROR !!! FAILED to execute End-2-End Scenario ===========" >&2
        echo >&2
        exit 1
    fi
}

firstPeer() {
    echo "${PEER_INDICES[0]}"
}

firstOrg() {
    echo "${ORG_INDICES[0]}"
}

peerAddress() {
    PEER=$1
    ORG=$2
    echo "peer${PEER}.org${ORG}.${DOMAIN_NAME}:7051"
}

peerRootCert() {
    PEER=$1
    ORG=$2
    echo "/crypto-config/peerOrganizations/org${ORG}.${DOMAIN_NAME}/peers/peer${PEER}.org${ORG}.${DOMAIN_NAME}/tls/ca.crt"
}

peerArgs() {
    PEER=$1
    ORG=$2
    echo "--peerAddresses $(peerAddress "$PEER" "$ORG") --tlsRootCertFiles $(peerRootCert "$PEER" "$ORG")"
}

peerArgsEachOrg() {
    { set +x; } 2>/dev/null
    local peer_args=""
    local first_peer="$(firstPeer)"
    for orgIdx in "${ORG_INDICES[@]}"; do
        peer_args="${peer_args} $(peerArgs "$first_peer" "$orgIdx")"
    done
    echo "$peer_args"
}

setGlobals() {
    PEER=$1
    ORG=$2

    export CORE_PEER_LOCALMSPID="Org${ORG}MSP"
    export CORE_PEER_MSPCONFIGPATH="/crypto-config/peerOrganizations/org${ORG}.${DOMAIN_NAME}/users/Admin@org${ORG}.${DOMAIN_NAME}/msp"
    export CORE_PEER_TLS_CERT_FILE="/crypto-config/peerOrganizations/org${ORG}.${DOMAIN_NAME}/peers/peer${PEER}.org${ORG}.${DOMAIN_NAME}/tls/server.crt"
    export CORE_PEER_TLS_KEY_FILE="/crypto-config/peerOrganizations/org${ORG}.${DOMAIN_NAME}/peers/peer${PEER}.org${ORG}.${DOMAIN_NAME}/tls/server.key"
    export CORE_PEER_ADDRESS="$(peerAddress "$PEER" "$ORG")"
    export CORE_PEER_TLS_ROOTCERT_FILE="$(peerRootCert "$PEER" "$ORG")"
    export CORE_PEER_TLS_CLIENTCERT_FILE="${CORE_PEER_TLS_CERT_FILE}"
    export CORE_PEER_TLS_CLIENTKEY_FILE="${CORE_PEER_TLS_KEY_FILE}"
    export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true

    env |grep CORE >&2
}

updateAnchorPeers() {
    PEER=$1
    ORG=$2
    setGlobals $PEER $ORG

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel update -o orderer0."$DOMAIN_NAME":7050 -c $CHANNEL_NAME -f /channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
        res=$?
        set +x
    else
        set -x
        peer channel update -o orderer0."$DOMAIN_NAME":7050 -c $CHANNEL_NAME -f /channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA --clientauth --certfile $CORE_PEER_TLS_CERT_FILE --keyfile $CORE_PEER_TLS_KEY_FILE >&log.txt
        res=$?
        set +x
    fi
    cat log.txt
    verifyResult $res "Anchor peer update failed"
    echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$CHANNEL_NAME\" is updated successfully ===================== "
    sleep $DELAY
    echo
}

createChannel() {
    CHANNEL_NAME=$1
    DELAY=3
    setGlobals 0 1

    sleep $DELAY
    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel create -o orderer0."$DOMAIN_NAME":7050 -c $CHANNEL_NAME -f /channel-artifacts/channel.tx >&log.txt
        res=$?
        set +x
    else
        set -x
        peer channel create -o orderer0."$DOMAIN_NAME":7050 -c $CHANNEL_NAME -f /channel-artifacts/channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA --clientauth --certfile $CORE_PEER_TLS_CERT_FILE --keyfile $CORE_PEER_TLS_KEY_FILE >&log.txt
        res=$?
        set +x
    fi
    cat log.txt
    verifyResult $res "Channel creation failed"
    echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
    echo
}

joinChannel() {
    CHANNEL_NAME=$1
    DELAY=3

    for i in "${ORG_INDICES[@]}"
    do
        for j in "${PEER_INDICES[@]}"
        do
            joinChannelWithRetry "$j" "$i" $CHANNEL_NAME $DELAY 1 5
            echo "===================== peer${j}.org${i} joined on the channel \"$CHANNEL_NAME\" ===================== "
            sleep $DELAY
            echo
        done
    done
}

## Sometimes Join takes time hence RETRY so this recursive function takes an
## iteration counter and a maximum number of iterations as its 5th and 6th
## arguments.
joinChannelWithRetry() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    DELAY=$4
    COUNTER=$5
    MAX_RETRY=$6
    setGlobals $PEER $ORG

    set -x
    peer channel join -b $CHANNEL_NAME.block >&log.txt
    res=$?
    set +x

    cat log.txt
    if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
        COUNTER=` expr $COUNTER + 1`
        echo "peer${PEER}.org${ORG} failed to join the channel, Retry after $DELAY seconds"
        sleep $DELAY
        joinChannelWithRetry $PEER $ORG $CHANNEL_NAME $DELAY $COUNTER $MAX_RETRY
    else
        verifyResult $res "After $MAX_RETRY attempts, peer${PEER}.org${ORG} has failed to Join the Channel"
    fi
}

generateChaincode() {
    echo "generateChaincode: ""$*"

    CC_SRC_PATH=$1
    CC_NAME=$2
    CC_VERSION=$3
    IS_EXTERNAL=$4

    TIMESTAMP="2016-01-01T00:00:00Z"
    CC_LABEL=${CC_NAME}-${CC_VERSION}
    CC_TYPE="golang"

    CC_SRC_DIR=$(dirname ${CC_SRC_PATH})
    CC_PATH=${CC_SRC_DIR}/${CC_LABEL}.tar.gz

    if [ "$IS_EXTERNAL" == "True" ]; then
        cat >/tmp/connection.json <<EOF
  {
    "address": "${CC_NAME}-peer{{.index}}:8080",
    "dial_timeout": "10s",
    "tls_required": false,
    "client_auth_required": false
  }
EOF
	tar -zcf /tmp/code.tar.gz -C /tmp --mtime=$TIMESTAMP connection.json

	CC_TYPE="ccaas"
    else
        tar -C /tmp -xf ${CC_SRC_PATH}
    fi

    echo '{"path":"main","type":"'"${CC_TYPE}"'","label":"'"${CC_LABEL}"'"}' >/tmp/metadata.json

    tar -zcf ${CC_PATH} -C /tmp --mtime=$TIMESTAMP metadata.json code.tar.gz
    md5sum ${CC_PATH}
    peer lifecycle chaincode calculatepackageid ${CC_PATH} | tee ${CC_SRC_DIR}/${CC_LABEL}.id
}

installChaincode() {
    echo "installChaincode: ""$*"

    PEER=$1
    ORG=$2
    CC_SRC_PATH=$3
    CC_NAME=$4
    CC_VERSION=$5

    queryChaincodePackage "$PEER" "$ORG" "$CC_NAME" "$CC_VERSION"
    if [ $? -eq 0 ]; then
        echo "===================== Chaincode ${CC_NAME}:${CC_VERSION} already installed on peer${PEER}.org${ORG} ===================== "
        echo
        return
    fi


    echo "Installing chaincode ${CC_NAME}:${CC_VERSION} on peer${PEER}.org${ORG}..."
    echo
    setGlobals $PEER $ORG
    set -x
    CC_SRC_DIR=$(dirname ${CC_SRC_PATH})
    CC_PATH=${CC_SRC_DIR}/${CC_NAME}-${CC_VERSION}.tar.gz

    peer lifecycle chaincode install ${CC_PATH} >&log.txt
    res=$?

    set +x
    cat log.txt
    verifyResult $res "Chaincode installation on peer${PEER}.org${ORG} has Failed"
    peer lifecycle chaincode queryinstalled -O json
    echo "===================== Chaincode is installed on peer${PEER}.org${ORG} ===================== "
    echo
}

queryChaincodePackage() {
    PEER=$1
    ORG=$2
    CC_NAME=$3
    CC_VERSION=$4

    CC_LABEL=${CC_NAME}-${CC_VERSION}

    echo "Querying installed chaincodes on peer${PEER}.org${ORG}..." >&2
    echo >&2
    setGlobals $PEER $ORG &>/dev/null
    set -x
    peer lifecycle chaincode queryinstalled -O json >chaincodes.json
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        return 1
    fi
    query=$(cat <<EOF
.installed_chaincodes[]
  | select(.label == "${CC_LABEL}")
  | .package_id
EOF
    )
    set -x
    jq -er '. == {}' chaincodes.json >&2
    res=$?
    set +x
    if [ $res -eq 0 ]; then
        return 1
    fi
    set -x
    jq -er "$query" chaincodes.json
    res=$?
    set +x
    return $res
}

approveChaincode() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5
    SEQ_NO=$6
    shift 6

    package_id="$(queryChaincodePackage "$PEER" "$ORG" "$CC_NAME" "$CC_VERSION")"
    verifyResult $? "queryChaincodePackage on peer${PEER}.org${ORG} has Failed"
    echo package_id="$package_id"
    echo

    if chaincodeApprovedForOrg \
        "$PEER" "$ORG" \
        "$CHANNEL_NAME" \
        "$CC_NAME" "$CC_VERSION" \
        "$SEQ_NO" "$@"; then
        echo "===================== Chaincode already approved on peer${PEER}.org${ORG} ===================== "
        echo
        return
    fi

    echo
    echo "Approving chaincode on peer${PEER}.org${ORG}..."
    echo
    setGlobals $PEER $ORG
    set -x
    peer lifecycle chaincode approveformyorg \
         --channelID "$CHANNEL_NAME" --tls --cafile "$ORDERER_CA" \
         --orderer orderer0."$DOMAIN_NAME":7050 \
         --name "$CC_NAME" --version "$CC_VERSION" \
         --collections-config /collections.json \
         --signature-policy "$ENDORSEMENT_POLICY" \
         --sequence "$SEQ_NO" \
         --cafile $ORDERER_CA --clientauth --certfile $CORE_PEER_TLS_CERT_FILE --keyfile $CORE_PEER_TLS_KEY_FILE  \
         --package-id "$package_id" "$@" >&log.txt
    res=$?
    set +x
    cat log.txt
    verifyResult $res "Approving chaincode on peer${PEER}.org${ORG} has Failed"
    echo "===================== Chaincode is approved on peer${PEER}.org${ORG} ===================== "
    echo
}

chaincodeApprovedForOrg() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5
    SEQ_NO=$6
    shift 6

    setGlobals $PEER $ORG &>/dev/null
    msp="$CORE_PEER_LOCALMSPID"

    echo "Checking chaincode approval for $MSP..."
    echo
    checkChaincodeCommitReadiness \
        "$PEER" "$ORG" \
        "$CHANNEL_NAME" \
        "$CC_NAME" "$CC_VERSION" \
        "$SEQ_NO" "$@" > status.json
    res=$?
    if [ $res -ne 0 ]; then
        return 1
    fi

    set -x
    jq -er ".approvals.${msp} == true" status.json
    res=$?
    set +x
    return $res
}

waitForChaincodeCommitReadiness() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5
    SEQ_NO=$6
    shift 6

    DELAY=3
    MAX_RETRY=5

    echo "Waiting for chaincode commit readiness on peer${PEER}.org${ORG}..."
    echo
    setGlobals $PEER $ORG &>/dev/null
    counter=0
    while [ $counter -lt $MAX_RETRY ] ; do
        counter=$(expr $counter + 1)
        sleep $DELAY
        set -x
        checkChaincodeCommitReadiness \
            "$PEER" "$ORG" \
            "$CHANNEL_NAME" \
            "$CC_NAME" "$CC_VERSION" \
            "$SEQ_NO" "$@" > status.json
        res=$?
        set +x
        if [ $res -ne 0 ]; then
            continue
        fi
        set -x
        cat status.json | jq
        jq -e '.approvals | all' status.json
        res=$?
        set +x
        if [ $res -eq 0 ]; then
            echo "===================== Chaincode commit readiness confirmed on peer${PEER}.org${ORG} ===================== "
            echo
            return
        fi
    done
    verifyResult 1 "Chaincode commit readiness confirmation on peer${PEER}.org${ORG} has Failed"
}

checkChaincodeCommitReadiness() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5
    SEQ_NO=$6
    shift 6

    setGlobals $PEER $ORG &>/dev/null
    set -x
    peer lifecycle chaincode checkcommitreadiness \
         --channelID "$CHANNEL_NAME" \
         --name "$CC_NAME" --version "$CC_VERSION" \
         --collections-config /collections.json \
         --signature-policy "$ENDORSEMENT_POLICY" \
         --sequence "$SEQ_NO" \
         --output json "$@"
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        return 1
    fi
}

commitChaincode() {
    CHANNEL_NAME=$1
    CC_NAME=$2
    CC_VERSION=$3
    SEQ_NO=$4
    shift 4

    echo "Committing chaincode definition..."
    echo
    set -x
    peer lifecycle chaincode commit \
         $(peerArgsEachOrg) \
         --channelID "$CHANNEL_NAME" --tls --cafile "$ORDERER_CA" \
         --orderer orderer0."$DOMAIN_NAME":7050 \
         --collections-config /collections.json \
         --signature-policy "$ENDORSEMENT_POLICY" \
         --sequence "$SEQ_NO" \
         --name "$CC_NAME" --version "$CC_VERSION" \
         --cafile $ORDERER_CA --clientauth --certfile $CORE_PEER_TLS_CERT_FILE --keyfile $CORE_PEER_TLS_KEY_FILE  \
         "$@" >&log.txt
    res=$?
    set +x
    cat log.txt
    verifyResult $res "Committing chaincode definition failed"
    echo "===================== Chaincode definition committed ===================== "
    echo
}

waitForCommittedVersion() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5

    DELAY=3
    MAX_RETRY=5

    echo "Waiting for chaincode version $CC_VERSION (for $CC_NAME) to be committed on peer${PEER}.org${ORG}..." >&2
    echo >&2
    counter=0
    while [ $counter -lt $MAX_RETRY ] ; do
        counter=$(expr $counter + 1)
        sleep $DELAY
        queryCommitted "$PEER" "$ORG" "$CHANNEL_NAME" "$CC_NAME" "$CC_VERSION" > committed.json
        res=$?
        if [ $res -ne 0 ]; then
            continue
        fi
        set -x
        installed_ver="$(jq -er '.version' committed.json)"
        res=$?
        set +x
        if [ $res -ne 0 ]; then
            continue
        fi
        if [ "$installed_ver" == "$CC_VERSION" ]; then
            echo "===================== Query chaincode definition successful on peer${PEER}.org${ORG} ===================== " >&2
            echo >&2
            return
        fi
    done
    verifyResult 1 "Query chaincode definition failed on peer${PEER}.org${ORG} has Failed"
}

nextSequenceNumber() {
    CHANNEL_NAME=$1
    CC_NAME=$2
    CC_VERSION=$3

    PEER="$(firstPeer)"
    ORG="$(firstOrg)"

    queryCommitted "$PEER" "$ORG" "$CHANNEL_NAME" "$CC_NAME" "$CC_VERSION" > committed.json
    res=$?
    if [ $res -ne 0 ]; then
        echo 1
        return
    fi
    set -x
    seq_num="$(jq -er 'select(.version = "$CC_VERSION") | .sequence' committed.json)"
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        echo 1
        return
    fi

    echo $(($seq_num + 1))
}

queryCommitted() {
    PEER=$1
    ORG=$2
    CHANNEL_NAME=$3
    CC_NAME=$4
    CC_VERSION=$5

    echo "Querying chaincode ${CC_NAME}:${CC_VERSION} committed status on peer${PEER}.org${ORG}..." >&2
    echo >&2
    setGlobals $PEER $ORG &>/dev/null
    set -x
    peer lifecycle chaincode querycommitted \
         --channelID "$CHANNEL_NAME" \
         --name "$CC_NAME" \
         --output json
}

forEachOrg() {
    local command=$1
    shift
    for orgIdx in "${ORG_INDICES[@]}"
    do
        "${command}" "$(firstPeer)" "${orgIdx}" "$@"
    done
}

forEachPeer() {
    local command=$1
    shift
    for orgIdx in "${ORG_INDICES[@]}"
    do
        for peerIdx in "${PEER_INDICES[@]}"
        do
            "${command}" "${peerIdx}" "${orgIdx}" "$@"
        done
    done

}
