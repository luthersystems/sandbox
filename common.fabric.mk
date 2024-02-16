# This makefile provides targets for local fabric networks. It's meant to
# be re-usable across projects.
include ${PROJECT_REL_DIR}/common.mk

# name of the chaincode
CC_NAME ?= com_luthersystems_chaincode_substrate01
# name of the chaincode package to install
CC_PKG_NAME ?= com_luthersystems_chaincode_substrate01
CC_FILE=${CC_PKG_NAME}-${CC_VERSION}.tar.gz
CC_PATH=chaincodes/${CC_FILE}
# path within cli docker container of chaincode
CC_MOUNT_PATH=/chaincodes/${CC_FILE}
SUBSTRATE_VERSION ?= latest

PHYLUM_VERSION_FILE=./build/phylum_version

# DOCKER_CHOWN_USER differs from CHOWN_USER because DOCKER_CHOWN_USER needs to
# use identifier numbers (insider docker there is no user defined with the
# proper name).
DOCKER_CHOWN_USER=$(shell id -u ${USER}):$(shell id -g ${USER})

# NETWORK_BUILDER is the entrypoint into the NETWORK_BUILDER_IMAGE for all
# commands.
NETWORK_BUILDER_IMAGE ?= ${ECR_HOST}/luthersystems/fabric-network-builder
NETWORK_BUILDER_TARGET ?= docker-pull/${NETWORK_BUILDER_IMAGE}\:${NETWORK_BUILDER_VERSION}
NETWORK_BUILDER=${NETWORK_BUILDER_IMAGE}:${NETWORK_BUILDER_VERSION} --chown "${DOCKER_CHOWN_USER}"

SHIROCLIENT_IMAGE ?= luthersystems/shiroclient
SHIROCLIENT_TARGET ?= docker-pull/${SHIROCLIENT_IMAGE}\:${SHIROCLIENT_VERSION}
SHIROCLIENT_FABRIC_CONFIG_BASENAME=shiroclient
SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME=shiroclient_fast
# index.gateway_name[.msp_filter]...
PHYLA_GO ?=
CHAINCODE_GO ?= ${PHYLA_GO}
PHYLA_CCAAS ?=
PHYLA ?= ${PHYLA_GO} ${PHYLA_CCAAS}
GATEWAYS ?= 1.shiroclient_gw_a.a
START_GATEWAYS=$(addprefix start-gw-,${GATEWAYS})
NOTIFY_GATEWAYS=$(addprefix notify-gw-,${GATEWAYS})
FUNCTIONAL_TEST_PHYLA=$(addprefix functional-test-phylum-,${PHYLA})
SHIRO_INIT_PHYLA=$(addprefix shiro-init-phylum-,${PHYLA})
CHANNEL ?= luther
GENERATE_OPTS ?= --domain ${FABRIC_DOMAIN} --org-count=2 --peer-count=2
FABRIC_ORG ?= org1
FABRIC_DOMAIN ?= luther.systems

FABRIC_IMAGE_NAMES=peer orderer ccenv
#FABRIC_IMAGE_NS=${ECR_HOST}/luthersystems
FABRIC_IMAGE_NS=hyperledger
FABRIC_IMAGE_FQNS=$(patsubst %,${FABRIC_IMAGE_NS}/fabric-%,${FABRIC_IMAGE_NAMES})
FABRIC_CA_IMAGE_FQN=${FABRIC_IMAGE_NS}/fabric-ca
DBMODE ?= goleveldb

FABRIC_IMAGES=$(foreach fqn,${FABRIC_IMAGE_FQNS},${fqn}\:${FABRIC_IMAGE_TAG}) \
              ${FABRIC_CA_IMAGE_FQN}\:${FABRIC_CA_IMAGE_TAG}
FABRIC_IMAGE_TARGETS=$(addprefix docker-pull/,${FABRIC_IMAGES})

FABRIC_DOCKER_NETWORK=byfn

DOCKER_FABRIC_OPTS ?=

.PHONY: default
default: images
	@

.PHONY: images
images: ${FABRIC_IMAGE_TARGETS} ${SHIROCLIENT_TARGET} ${NETWORK_BUILDER_TARGET}
	@

.PHONY: clean
clean:
	rm -rf build chaincodes/*.{tar.gz,id} .env

.PHONY: pristine
pristine: clean clean-generated

.PHONY: clean-generated
clean-generated:
	rm -rf \
		base \
		channel-artifacts \
		configtx.yaml \
		couchdb \
		crypto-config \
		crypto-config.yaml \
		docker-compose-cli.yaml \
		docker-compose-couch.yaml \
		docker-compose-e2e-template.yaml \
		docker-compose-e2e.yaml \
		fabric-client.yaml \
		fabric-client_fast.yaml \
		fabric-client_template.yaml \
		shiroclient.yaml \
		shiroclient_fast.yaml \
		scripts

.PHONY: go-test
go-test:
	go test -race -cover -v ./...
	$(MAKE) functional-tests

.PHONY: functional-tests
functional-tests: ${FUNCTIONAL_TEST_PHYLA}

functional-test-phylum-%: compile-phylum-%
	# NOTE: shirotester path must be relative to properly work within docker container.
	go run ${PROJECT_REL_DIR}/cmd/shirotester/main.go functional-tests --verbose phylum_$*/testfixtures/*.yaml

.PHONY: generate
generate: ${NETWORK_BUILDER_TARGET}
	rm -rf ./crypto-config ./channel-artifacts
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force generate \
			--domain=${FABRIC_DOMAIN} \
			--cc-name="${CC_NAME}" \
			${GENERATE_OPTS}

.PHONY: generate-template
generate-template: ${NETWORK_BUILDER_TARGET}
	rm -rf ./crypto-config ./channel-artifacts
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force generate \
			--domain=${FABRIC_DOMAIN} \
			--cc-name="${CC_NAME}" \
			${GENERATE_OPTS} --template

.PHONY: generate-assets
generate-assets: channel-artifacts/genesis.block

channel-artifacts/genesis.block: ${NETWORK_BUILDER_TARGET}
	rm -rf ./crypto-config ./channel-artifacts
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force generate \
			--domain=${FABRIC_DOMAIN} \
			--cc-name="${CC_NAME}" \
			${GENERATE_OPTS} --no-template

.PHONY: couchdb-up
couchdb-up: DBMODE = couchdb
couchdb-up: fnb-up gateway-up

.PHONY: up
up: generate-chaincodes .env fnb-up gateway-up
	@

.PHONY: fnb-up
fnb-up: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS} channel-artifacts/genesis.block
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		-e CHAINCODE_LOG_LEVEL \
		-e CHAINCODE_OTLP_TRACER_ENDPOINT \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" up \
			--log-spec debug \
			--cc-version "${SUBSTRATE_VERSION}"

.PHONY: fnb-extend
fnb-extend: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS}
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" extend \
			--domain-name=${FABRIC_DOMAIN}

.PHONY: fnb-shell
fnb-shell: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS}
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		-e CHANNEL=${CHANNEL} \
		-e FABRIC_DOMAIN=${FABRIC_DOMAIN} \
		-e FABRIC_DBMODE="${DBMODE}" \
		--entrypoint bash \
		${NETWORK_BUILDER_IMAGE}:${NETWORK_BUILDER_VERSION}

.PHONY: gateway-up
gateway-up: ${START_GATEWAYS}

start-gw-%: parts=$(subst ., ,$*)
start-gw-%: idx=$(word 1,${parts})
start-gw-%: name=$(word 2,${parts})
start-gw-%: ccname=$(word 3,${parts})
start-gw-%: filter=$(word 4,${parts})
start-gw-%: port=$$(( 8081 + ${idx} ))
start-gw-%: metrics_port=$$(( 9601 + ${idx} ))
start-gw-%: filter_args=$(if ${filter},-f ${filter})
ifdef EXPOSE_GATEWAY
start-gw-%: port_fw=-p "${port}:${port}"
endif
start-gw-%: ${SHIROCLIENT_TARGET} build/volume/msp build/volume/enroll_user
	${DOCKER_RUN} -d --name ${name} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-w "/tmp/fabric" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e SHIROCLIENT_GATEWAY_OTLP_TRACER_ENDPOINT \
		${port_fw} \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_${ccname}.yaml \
			--chaincode.version ${CC_VERSION}_${ccname} \
			gateway ${filter_args}

.SECONDEXPANSION:
notify-gw-%: parts=$(subst ., ,$*)
notify-gw-%: name=$(word 2,${parts})
notify-gw-%: ccname=$(word 3,${parts})
notify-gw-%: ${SHIROCLIENT_TARGET} compile-phylum-$$(ccname) build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} --rm -t \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_${ccname}/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-w "/tmp/fabric" \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_${ccname}.yaml \
			--chaincode.version ${CC_VERSION}_${ccname} \
			notify -g http://${name}:8082 "$(shell cat ${PHYLUM_VERSION_FILE})"

.PHONY: couchdb-down
couchdb-down: DBMODE = couchdb
couchdb-down: gateway-down fnb-down

# oracle-up and oracle-down are declared as phony targets so they can be used
# as dependencies and ordered correctly when processing other phony targets.
.PHONY: oracle-up
.PHONY: oracle-down

.PHONY: down
down: oracle-down gateway-down fnb-down

.PHONY: fnb-down
fnb-down: ${NETWORK_BUILDER_TARGET}
	-rm -f "${PHYLUM_VERSION_FILE}"
	-${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" down

.PHONY: gateway-down
gateway-down: gw_names=$(foreach g,${GATEWAYS},$(word 2,$(subst ., ,${g})))
gateway-down:
	-docker stop ${gw_names}

.PHONY: sleep-%
sleep-%:
	@sleep $*

.PHONY: install
install: ${NETWORK_BUILDER_TARGET} ${CC_PATH}
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force install \
			"${CC_NAME}" \
			"${CC_VERSION}" \
			"${PHYLA}" \
			"${CC_MOUNT_PATH}"

.PHONY: generate-chaincode
generate-chaincodes: generate-go-chaincodes generate-ccaas-chaincodes
	@

.PHONY: generate-go-chaincodes
generate-go-chaincodes: ${NETWORK_BUILDER_TARGET} ${CC_PATH}
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --force generatecc \
			"${CC_NAME}" \
			"${CC_VERSION}" \
			"${CHAINCODE_GO}" \
			"${CC_MOUNT_PATH}"

.PHONY: generate-ccaas-chaincodes
generate-ccaas-chaincodes: ${NETWORK_BUILDER_TARGET}
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --force generatecc --ccaas\
			"${CC_NAME}" \
			"${CC_VERSION}" \
			"${PHYLA_CCAAS}" \
			"${CC_MOUNT_PATH}"

.PHONY: ${PHYLUM_VERSION_FILE}
${PHYLUM_VERSION_FILE}:
	date +local-%s >${PHYLUM_VERSION_FILE}

.PHONY: ${PHYLUM_VERSION_FILE}_exists
${PHYLUM_VERSION_FILE}_exists:
	@test -f ${PHYLUM_VERSION_FILE}

.PHONY: init
init: ${SHIRO_INIT_PHYLA} ${NOTIFY_GATEWAYS}

shiro-init-phylum-%: ${SHIROCLIENT_TARGET} compile-phylum-% build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} -t \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_$*/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			init "$(shell cat ${PHYLUM_VERSION_FILE})" /tmp/phylum.zip

call_cmd-%:
	@echo ${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e SHIROCLIENT_LOG_LEVEL \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call

enable_logging-%:
	./logging-pbool-ctl.sh true \
		${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call set_app_control_property

disable_logging-%:
	./logging-pbool-ctl.sh false \
		${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call set_app_control_property

metadump_cmd-%:
	@echo ${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			metadump

get_phyla-%:
	${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} -v \
			--config ${SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME}_$*.yaml \
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
compile-phylum-%: $$(shell find -L phylum_$$* -name "*.lisp" 2>/dev/null)
	mkdir -p ./build/phylum_$*
	rm -rf   ./build/phylum_$*/src
	mkdir -p ./build/phylum_$*/src
	cp $^    ./build/phylum_$*/src/
	cd       ./build/phylum_$*/src && ls && rm -f ./../phylum.zip && zip ./../phylum.zip $(notdir $^)

chaincodes/:
	mkdir -p chaincodes/

CHAINCODE_ID_FILES := $(wildcard ./chaincodes/*.id)

.env: $(CHAINCODE_ID_FILES)
	@./scripts/env.sh
