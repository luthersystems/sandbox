# Copyright © 2021 Luther Systems, Ltd. All rights reserved.

# common.fabric.mk
#
# A base makefile for running fabric networks locally with docker-compose.
# Targets which are only used in the 'full' network,
# not in the in-memory network, are disabled within Codespaces.

.PHONY: clean
clean:
	rm -rf build

.PHONY: pristine
pristine: clean clean-generated
	rm -rf chaincodes/*.tar.gz

.PHONY: clean-generated
clean-generated:
	rm -rf \
		channel-artifacts \
		crypto-config

PROJECT_REL_DIR ?= ..
include ${PROJECT_REL_DIR}/common.mk

ifndef LOCAL_WORKSPACE_FOLDER # if not in codespace
# All the non-cleaning targets of Fabric do not work in the in-memory network and so are disabled in codespace

FABRIC_ORG ?= org1
FABRIC_DOMAIN ?= luther.systems
CHANNEL ?= luther
GENERATE_OPTS ?= --domain ${FABRIC_DOMAIN} --orderer-count=1 --org-count=1 --peer-count=1

# name of the chaincode
CC_NAME ?= com_luthersystems_chaincode_substrate01
# name of the chaincode package to install
CC_PKG_NAME ?= com_luthersystems_chaincode_substrate01
CC_FILE=${CC_PKG_NAME}-${CC_VERSION}.tar.gz
CC_PATH=chaincodes/${CC_FILE}
# path within cli docker container of chaincode
CC_MOUNT_PATH=/chaincodes/${CC_FILE}

FABRIC_DIR := ${DOCKER_PROJECT_DIR}/fabric

PHYLUM_VERSION_FILE=./build/phylum_version

# DOCKER_CHOWN_USER differs from CHOWN_USER because DOCKER_CHOWN_USER needs to
# use identifier numbers (insider docker there is no user defined with the
# proper name).
DOCKER_CHOWN_USER=$(shell id -u ${USER}):$(shell id -g ${USER})

# NETWORK_BUILDER is the entrypoint into the NETWORK_BUILDER_IMAGE for all
# commands.
NETWORK_BUILDER_TARGET ?= docker-pull/${NETWORK_BUILDER_IMAGE}\:${NETWORK_BUILDER_VERSION}
NETWORK_BUILDER=${NETWORK_BUILDER_IMAGE}:${NETWORK_BUILDER_VERSION} --chown "${DOCKER_CHOWN_USER}"

SHIROCLIENT_TARGET ?= docker-pull/${SHIROCLIENT_IMAGE}\:${SHIROCLIENT_VERSION}
SHIROCLIENT_FABRIC_CONFIG_BASENAME=shiroclient_fast
SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME=shiroclient_fast
# index.gateway_name[.msp_filter]...
PHYLA ?= phylum
GATEWAYS ?= 1.shiroclient_gw_phylum.phylum
START_GATEWAYS=$(addprefix start-gw-,${GATEWAYS})
NOTIFY_GATEWAYS=$(addprefix notify-gw-,${GATEWAYS})
FUNCTIONAL_TEST_PHYLA=$(addprefix functional-test-phylum-,${PHYLA})
SHIRO_INIT_PHYLA=$(addprefix shiro-init-phylum-,${PHYLA})

FABRIC_IMAGE_NAMES=peer orderer ccenv
FABRIC_IMAGE_NS=hyperledger
FABRIC_IMAGE_FQNS=$(patsubst %,${FABRIC_IMAGE_NS}/fabric-%,${FABRIC_IMAGE_NAMES})
FABRIC_CA_IMAGE_FQN=${FABRIC_IMAGE_NS}/fabric-ca
DBMODE ?= goleveldb

FABRIC_IMAGES=$(foreach fqn,${FABRIC_IMAGE_FQNS},${fqn}\:${FABRIC_IMAGE_TAG}) \
              ${FABRIC_CA_IMAGE_FQN}\:${FABRIC_CA_IMAGE_TAG}
FABRIC_IMAGE_TARGETS=$(addprefix docker-pull/,${FABRIC_IMAGES})

FABRIC_DOCKER_NETWORK=fnb_byfn

.PHONY: default all
default: ${CC_PATH}
	@

.PHONY: images
images: ${FABRIC_IMAGE_TARGETS} ${SHIROCLIENT_TARGET} ${NETWORK_BUILDER_TARGET}
	@

.PHONY: clean
clean: fabric-clean

.PHONY: fabric-clean
fabric-clean:
	rm -rf build

.PHONY: pristine
pristine: clean clean-generated

.PHONY: clean-generated
clean-generated: fabric-clean

.PHONY: install
all: install
install: ${NETWORK_BUILDER_TARGET} ${CC_PATH}
	${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force install \
			"${CC_NAME}" \
			"${CC_VERSION}" \
			"${PHYLA}" \
			"${CC_MOUNT_PATH}"

.PHONY: gateway-up
all: gateway-up
gateway-up: ${START_GATEWAYS}

start-gw-%: parts=$(subst ., ,$*)
start-gw-%: idx=$(word 1,${parts})
start-gw-%: name=$(word 2,${parts})
start-gw-%: ccname=$(word 3,${parts})
start-gw-%: filter=$(word 4,${parts})
start-gw-%: port=$$(( 8081 + ${idx} ))
start-gw-%: metrics_port=$$(( 9601 + ${idx} ))
start-gw-%: filter_args=$(if ${filter},-f ${filter})
start-gw-%: ${SHIROCLIENT_TARGET} build/volume/msp build/volume/enroll_user
	${DOCKER_RUN} -d --name ${name} \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-w "/tmp/fabric" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		--network ${FABRIC_DOCKER_NETWORK} \
		--publish 127.0.0.1:${port}:8082/tcp \
		--publish 127.0.0.1:${metrics_port}:9602/tcp \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_${ccname}.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_${ccname} \
			gateway ${filter_args}

.SECONDEXPANSION:
notify-gw-%: parts=$(subst ., ,$*)
notify-gw-%: name=$(word 2,${parts})
notify-gw-%: ccname=$(word 3,${parts})
notify-gw-%: ${SHIROCLIENT_TARGET} compile-phylum-$$(ccname) build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} --rm -it \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_${ccname}/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-w "/tmp/fabric" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_${ccname}.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_${ccname} \
			notify -g http://${name}:8082 "$(shell cat ${PHYLUM_VERSION_FILE})"

# oracle-up and oracle-down are declared as phony targets so they can be used as
# dependencies and ordered correctly when processing other phony targets.
.PHONY: oracle-up
.PHONY: oracle-down

.PHONY: down
down: oracle-down gateway-down fnb-down

.PHONY: fnb-down
fnb-down: ${NETWORK_BUILDER_TARGET}
	-rm -f "${PHYLUM_VERSION_FILE}"
	-${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" down

.PHONY: gateway-down
gateway-down: gw_names=$(foreach g,${GATEWAYS},$(word 2,$(subst ., ,${g})))
gateway-down:
	-docker stop ${gw_names}

.PHONY: ${PHYLUM_VERSION_FILE}
${PHYLUM_VERSION_FILE}:
	date +local-%s >${PHYLUM_VERSION_FILE}

.PHONY: ${PHYLUM_VERSION_FILE}_exists
${PHYLUM_VERSION_FILE}_exists:
	@test -f ${PHYLUM_VERSION_FILE}

shiro-init-phylum-%: ${SHIROCLIENT_TARGET} compile-phylum-% build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} -it \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_$*/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			init "$(shell cat ${PHYLUM_VERSION_FILE})" /tmp/phylum.zip

call_cmd-%: ${PHYLUM_VERSION_FILE}_exists
	@echo ${DOCKER_RUN} \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e SHIROCLIENT_LOG_LEVEL \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call

enable_logging-%: ${PHYLUM_VERSION_FILE}_exists
	./logging-pbool-ctl.sh true \
		${DOCKER_RUN} \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call set_app_control_property

disable_logging-%: ${PHYLUM_VERSION_FILE}_exists
	./logging-pbool-ctl.sh false \
		${DOCKER_RUN} \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call set_app_control_property

metadump_cmd-%: ${PHYLUM_VERSION_FILE}_exists
	@echo ${DOCKER_RUN} -i \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			metadump

get_phyla-%: ${PHYLUM_VERSION_FILE}_exists
	${DOCKER_RUN} -i \
		-u ${DOCKER_USER} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${FABRIC_DIR}:/tmp/fabric:ro" \
		-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
		        --client.license-file=/tmp/license.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call get_phyla '{}'

build/volume/msp:
	mkdir -p $@
	chmod a+w $@

build/volume/enroll_user:
	mkdir -p $@
	chmod a+w $@

.SECONDEXPANSION:
compile-phylum-%: $$(shell find -L ../$$* -name "*.lisp" 2>/dev/null | grep -Fv /build)
	mkdir -p ./build/phylum_$*
	rm -rf   ./build/phylum_$*/src
	mkdir -p ./build/phylum_$*/src
	cp $^    ./build/phylum_$*/src/
	cd       ./build/phylum_$*/src && ls && rm -f ./../phylum.zip && zip ./../phylum.zip $(notdir $^)

${CC_PATH}: ${PRESIGNED_PATH}
	${PROJECT_REL_DIR}/scripts/obtain-cc.sh
	touch $@

.PHONY:
download: ${CC_PATH}
	@

.PHONY: init
all: init
init: ${SHIRO_INIT_PHYLA} ${NOTIFY_GATEWAYS}

.PHONY: up
all: up
up: fnb-up gateway-up

.PHONY: fnb-up
fnb-up: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS} channel-artifacts/genesis.block
	${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" up --log-spec debug

.PHONY: fnb-extend
fnb-extend: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS}
	${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" extend \
			--domain-name=${FABRIC_DOMAIN}

.PHONY: fnb-shell
fnb-shell: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS}
	${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		-e FABRIC_LOGGING_SPEC \
		-e CHANNEL=${CHANNEL} \
		-e FABRIC_DOMAIN=${FABRIC_DOMAIN} \
		-e FABRIC_DBMODE="${DBMODE}" \
		--entrypoint bash \
		${NETWORK_BUILDER_IMAGE}:${NETWORK_BUILDER_VERSION}

.PHONY: go-test
go-test:
	CGO_LDFLAGS_ALLOW=-I/usr/local/share/libtool go test -race -cover -v ./...
	$(MAKE) functional-tests

.PHONY: functional-tests
functional-tests: ${FUNCTIONAL_TEST_PHYLA}

functional-test-phylum-%: compile-phylum-%
	# NOTE: shirotester path must be relative to properly work within docker container.
	CGO_LDFLAGS_ALLOW=-I/usr/local/share/libtool go run ../lib/shiro/shirotester/main.go functional-tests --verbose phylum_$*/testfixtures/*.yaml
.PHONY: generate-assets
generate-assets: channel-artifacts/genesis.block

channel-artifacts/genesis.block: ${NETWORK_BUILDER_TARGET}
	rm -rf ./crypto-config ./channel-artifacts
	${DOCKER_RUN} -it \
	    -v /var/run/docker.sock:/var/run/docker.sock \
		-v "${FABRIC_DIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e DOCKER_PROJECT_DIR="${DOCKER_PROJECT_DIR}" \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force generate \
			--domain=${FABRIC_DOMAIN} \
			--cc-name="${CC_NAME}" \
			${GENERATE_OPTS} --no-template


endif
