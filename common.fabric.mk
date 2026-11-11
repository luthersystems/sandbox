# This makefile provides targets for local fabric (distributed systems) 
# networks. It's meant to be re-usable across projects.
include ${PROJECT_REL_DIR}/common.mk

# name of the chaincode
CC_NAME ?= com_luthersystems_chaincode_substrate01
# name of the chaincode package to install
CC_PKG_NAME ?= com_luthersystems_chaincode_substrate01
CC_FILE=${CC_PKG_NAME}-${CC_VERSION}.tar.gz
CC_PATH=chaincodes/${CC_FILE}
# path within cli docker container of chaincode
CC_MOUNT_PATH=/chaincodes/${CC_FILE}

PHYLUM_VERSION_FILE=./build/phylum_version

# DOCKER_CHOWN_USER differs from CHOWN_USER because DOCKER_CHOWN_USER needs to
# use identifier numbers (insider docker there is no user defined with the
# proper name).
DOCKER_CHOWN_USER ?= $(shell id -u ${USER}):$(shell id -g ${USER})

# NETWORK_BUILDER is the entrypoint into the NETWORK_BUILDER_IMAGE for all
# commands. Every recipe passes it last, after its own docker run options.
NETWORK_BUILDER_IMAGE ?= luthersystems/fabric-network-builder
NETWORK_BUILDER_TARGET ?= docker-pull/${NETWORK_BUILDER_IMAGE}\:${NETWORK_BUILDER_VERSION}
NETWORK_BUILDER_FQN=${NETWORK_BUILDER_IMAGE}:${NETWORK_BUILDER_VERSION}
# The builder (v0.1.0 on) runs as nobody, not root. Run it as your own user,
# so the files it writes are yours, and add the group of the docker socket
# as the container sees it (on Docker Desktop it is not the group of the
# host's socket file). The image's own stat reads that group when the recipe
# runs.
NETWORK_BUILDER_USER=-u "${DOCKER_CHOWN_USER}" \
	--group-add "$$(${DOCKER_RUN} ${DOCKER_IN_DOCKER_MOUNT} --entrypoint stat ${NETWORK_BUILDER_FQN} -c %g /var/run/docker.sock)"
# NETWORK_BUILDER_ENV gives the builder (v0.1.1 on) the Fabric image
# namespace and tags from this project's config, so make pulls and the
# network runs the same images. Set FABRIC_IMAGE_NS to pull through a mirror,
# for example an ECR pull-through cache of Docker Hub:
#   make up FABRIC_IMAGE_NS=123456789012.dkr.ecr.us-east-1.amazonaws.com/docker-hub/hyperledger
NETWORK_BUILDER_ENV=-e FNB_IMAGENS="${FABRIC_IMAGE_NS}" \
	-e FNB_IMAGETAG="${FABRIC_IMAGE_TAG}" \
	-e FNB_CAIMAGETAG="${FABRIC_CA_IMAGE_TAG}" \
	-e FNB_BASEIMAGETAG="${BASE_IMAGE_TAG}"
NETWORK_BUILDER=${NETWORK_BUILDER_USER} ${NETWORK_BUILDER_ENV} ${NETWORK_BUILDER_FQN}

SHIROCLIENT_IMAGE ?= luthersystems/shiroclient
CONNECTORHUB_IMAGE ?= luthersystems/connectorhub

SHIROCLIENT_TARGET ?= docker-pull/${SHIROCLIENT_IMAGE}\:${SHIROCLIENT_VERSION}
CONNECTORHUB_TARGET ?= docker-pull/${CONNECTORHUB_IMAGE}\:${CONNECTORHUB_VERSION}

SHIROCLIENT_FABRIC_CONFIG_BASENAME=shiroclient
SHIROCLIENT_FABRIC_CONFIG_FAST_BASENAME=shiroclient_fast
# index.gateway_name[.msp_filter]...
PHYLA_GO ?=
CHAINCODE_GO ?= ${PHYLA_GO}
PHYLA_CCAAS ?=
PHYLA ?= ${PHYLA_GO} ${PHYLA_CCAAS}
GATEWAYS ?= 1.shiroclient_gw_a.a
CONNECTORHUBS ?= 1.connectorhub_a.a
START_GATEWAYS=$(addprefix start-gw-,${GATEWAYS})
START_CONNECTORHUBS=$(addprefix start-ch-,${CONNECTORHUBS})
NOTIFY_GATEWAYS=$(addprefix notify-gw-,${GATEWAYS})
FUNCTIONAL_TEST_PHYLA=$(addprefix functional-test-phylum-,${PHYLA})
SHIRO_INIT_PHYLA=$(addprefix shiro-init-phylum-,${PHYLA})
CHANNEL ?= luther
GENERATE_OPTS ?= --domain ${FABRIC_DOMAIN} --org-count=2 --peer-count=2
FABRIC_ORG ?= org1
FABRIC_DOMAIN ?= luther.systems

FABRIC_IMAGE_NAMES=peer orderer ccenv
FABRIC_IMAGE_NS ?= hyperledger
FABRIC_IMAGE_FQNS=$(patsubst %,${FABRIC_IMAGE_NS}/fabric-%,${FABRIC_IMAGE_NAMES})
FABRIC_CA_IMAGE_FQN=${FABRIC_IMAGE_NS}/fabric-ca
DBMODE ?= goleveldb

FABRIC_IMAGES=$(foreach fqn,${FABRIC_IMAGE_FQNS},${fqn}\:${FABRIC_IMAGE_TAG}) \
              ${FABRIC_CA_IMAGE_FQN}\:${FABRIC_CA_IMAGE_TAG}
FABRIC_IMAGE_TARGETS=$(addprefix docker-pull/,${FABRIC_IMAGES})

FABRIC_DOCKER_NETWORK=byfn

# The gateway and connectorhub images run as nobody. They read the private
# keys in crypto-config/, which the builder writes as your user with mode
# 0600, so they run as your user too.
FABRIC_CLIENT_USER=-u "${DOCKER_CHOWN_USER}"
# The gateway and the shiroclient commands need a Luther licence or demo
# mode. Demo mode needs no file, but stops the network after 1,500 blocks or
# 7 days, so long-lived or heavily tested networks want a real licence. Put
# yours at .luther-license.yaml in the repository root (git ignores it), or
# set LICENSE_FILE to its absolute path. With the file there, it is mounted at
# /tmp/license.yaml (not shiroclient's default /tmp/fabric/license.yaml,
# because /tmp/fabric is a read-only mount); without it, demo mode is used,
# so a fresh clone and CI run with no licence. license-check stops a run
# where LICENSE_FILE was set by hand and names no file, rather than fall back
# to demo mode without saying so.
LICENSE_FILE ?= ${PROJECT_ABS_DIR}/.luther-license.yaml
LICENSE_OPTS=$(if $(wildcard ${LICENSE_FILE}),-v "$(abspath ${LICENSE_FILE}):/tmp/license.yaml:ro" -e SHIROCLIENT_CLIENT_LICENSE_FILE=/tmp/license.yaml,-e SHIROCLIENT_CLIENT_DEMO_MODE=true)
DOCKER_FABRIC_OPTS ?= ${LICENSE_OPTS}

.PHONY: default
default: images
	@

.PHONY: images
images: ${FABRIC_IMAGE_TARGETS} ${SHIROCLIENT_TARGET} ${NETWORK_BUILDER_TARGET}
	@

.PHONY: clean-chaincodes
# .env is no longer written (v0.1.x puts the CCaaS package IDs in the
# compose file), but the builder still reads one, so a .env left by an
# older builder is removed too.
clean-chaincodes:
	rm -rf chaincodes/*.{tar.gz,id} .env

.PHONY: clean
clean: clean-chaincodes
	rm -rf build

.PHONY: pristine
pristine: clean clean-generated

.PHONY: clean-generated
clean-generated:
	rm -rf \
		base \
		channel-artifacts \
		collections.json \
		configtx.yaml \
		core.yaml \
		couchdb \
		crypto-config \
		crypto-config.yaml \
		docker-compose-ccaas.yaml \
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

# crypto-config stands for every file the builder generates (clean-generated
# lists them). They are not kept in git: the first target that needs the
# network generates them, sized by GENERATE_OPTS.
crypto-config:
	$(MAKE) --no-print-directory generate

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
up: generate-chaincodes fnb-up gateway-up connectorhub-up

.PHONY: fnb-up
fnb-up: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS} crypto-config
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		-e CHAINCODE_LOG_LEVEL \
		-e CHAINCODE_OTLP_TRACER_ENDPOINT \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" up \
			--log-spec debug \
			--cc-version "${CC_VERSION}"

.PHONY: fnb-extend
fnb-extend: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS} crypto-config
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		${NETWORK_BUILDER} --channel ${CHANNEL} --force -s "${DBMODE}" extend \
			--domain-name=${FABRIC_DOMAIN}

.PHONY: fnb-shell
fnb-shell: ${NETWORK_BUILDER_TARGET} ${FABRIC_IMAGE_TARGETS} crypto-config
	${DOCKER_RUN} -t \
		${DOCKER_IN_DOCKER_MOUNT} \
		-v "${CURDIR}:${CURDIR}" \
		-w "${CURDIR}" \
		-e FABRIC_LOGGING_SPEC \
		-e CHANNEL=${CHANNEL} \
		-e FABRIC_DOMAIN=${FABRIC_DOMAIN} \
		-e FABRIC_DBMODE="${DBMODE}" \
		${NETWORK_BUILDER_USER} \
		${NETWORK_BUILDER_ENV} \
		--entrypoint sh \
		${NETWORK_BUILDER_FQN}

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
start-gw-%: port_fw=-p "127.0.0.1:${port}:${port}"
endif
start-gw-%: ${SHIROCLIENT_TARGET} license-check build/volume/msp build/volume/enroll_user
	${DOCKER_RUN} -d --name ${name} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${FABRIC_CLIENT_USER} \
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

.PHONY: connectorhub-up
connectorhub-up: ${START_CONNECTORHUBS}

start-ch-%: parts=$(subst ., ,$*)
start-ch-%: idx=$(word 1,${parts})
start-ch-%: name=$(word 2,${parts})
start-ch-%: ccname=$(word 3,${parts})
start-ch-%: port=$$(( 9091 + ${idx} ))
ifdef EXPOSE_CONNECTORHUB
start-ch-%: port_fw=-p "127.0.0.1:${port}:8080"
endif
# No --rm: `docker run -d` succeeds as soon as the container starts, so a
# connectorhub that crashes on startup would be deleted along with its logs.
# Check that it stays up, and keep it for inspection if it does not;
# connectorhub-down removes it.  Any other DOCKER_RUN_OPTS still apply.
start-ch-%: ${CONNECTORHUB_TARGET} build/volume/checkpoint
	${DOCKER} run $(filter-out --rm --rm=true --rm=1,${DOCKER_RUN_OPTS}) -d --name ${name} \
		-v "${CURDIR}:/tmp/fabric:ro" \
		-v "$(abspath build/volume/checkpoint):/tmp/checkpoint:rw" \
		${FABRIC_CLIENT_USER} \
		-w "/tmp/fabric" \
		${port_fw} \
		--network ${FABRIC_DOCKER_NETWORK} \
		${CONNECTORHUB_IMAGE}:${CONNECTORHUB_VERSION} \
			start -v \
			--config-file /tmp/fabric/connectorhub.yaml \
			--checkpoint-file /tmp/checkpoint/checkpoint.txt
	DOCKER=${DOCKER} ${PROJECT_REL_DIR}/scripts/check-container-running.sh ${name}

.SECONDEXPANSION:
notify-gw-%: parts=$(subst ., ,$*)
notify-gw-%: name=$(word 2,${parts})
notify-gw-%: ccname=$(word 3,${parts})
notify-gw-%: ${SHIROCLIENT_TARGET} license-check compile-phylum-$$(ccname) build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} --rm -t \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_${ccname}/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${FABRIC_CLIENT_USER} \
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
down: oracle-down connectorhub-down gateway-down fnb-down clean

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
	-${DOCKER} stop ${gw_names}

.PHONY: connectorhub-down
connectorhub-down: ch_names=$(foreach g,${CONNECTORHUBS},$(word 2,$(subst ., ,${g})))
connectorhub-down:
	-${DOCKER} stop ${ch_names}
	-${DOCKER} rm ${ch_names}

.PHONY: sleep-%
sleep-%:
	@sleep $*

.PHONY: install
install: ${NETWORK_BUILDER_TARGET}
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
generate-go-chaincodes: ${NETWORK_BUILDER_TARGET}
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

.PHONY: license-check
license-check:
	@$(if $(filter file,$(origin LICENSE_FILE)),true,test -f "${LICENSE_FILE}") || \
		{ echo "LICENSE_FILE=${LICENSE_FILE}: no such file. Unset LICENSE_FILE to use demo mode." >&2; exit 1; }
	@echo "Luther licence: $(if $(wildcard ${LICENSE_FILE}),${LICENSE_FILE},none, using demo mode)"

.PHONY: init
init: ${SHIRO_INIT_PHYLA} ${NOTIFY_GATEWAYS}

shiro-init-phylum-%: ${SHIROCLIENT_TARGET} license-check compile-phylum-% build/volume/msp build/volume/enroll_user ${PHYLUM_VERSION_FILE}
	${DOCKER_RUN} -t \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "$(abspath build/phylum_$*/phylum.zip):/tmp/phylum.zip:ro" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${FABRIC_CLIENT_USER} \
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
		${FABRIC_CLIENT_USER} \
		${DOCKER_FABRIC_OPTS} \
		-e ORG="${FABRIC_ORG}" \
		-e DOMAIN_NAME="${FABRIC_DOMAIN}" \
		-e SHIROCLIENT_LOG_LEVEL \
		-w "/tmp/fabric" \
		--network ${FABRIC_DOCKER_NETWORK} \
		${SHIROCLIENT_IMAGE}:${SHIROCLIENT_VERSION} \
			--config ${SHIROCLIENT_FABRIC_CONFIG_BASENAME}_$*.yaml \
			--chaincode.version ${CC_VERSION}_$* \
			--phylum.version latest \
			call \
			--seed

enable_logging-%:
	./logging-pbool-ctl.sh true \
		${DOCKER_RUN} \
		-v "$(abspath build/volume/msp):/tmp/msp:rw" \
		-v "$(abspath build/volume/enroll_user):/tmp/state-store:rw" \
		-v "${CURDIR}:/tmp/fabric:ro" \
		${FABRIC_CLIENT_USER} \
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
		${FABRIC_CLIENT_USER} \
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
		${FABRIC_CLIENT_USER} \
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
		${FABRIC_CLIENT_USER} \
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

build/volume/checkpoint:
	mkdir -p $@
	chmod a+w $@

.SECONDEXPANSION:
compile-phylum-%: $$(shell find -L phylum_$$* -name "*.lisp" -not -path "*/build/*" 2>/dev/null)
	mkdir -p ./build/phylum_$*
	rm -rf   ./build/phylum_$*/src
	mkdir -p ./build/phylum_$*/src
	cp $^    ./build/phylum_$*/src/
	cd       ./build/phylum_$*/src && ls && rm -f ./../phylum.zip && zip ./../phylum.zip $(notdir $^)

chaincodes/:
	mkdir -p chaincodes/
