# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# Makefile
#
# The primary project makefile that should be run from the root directory and is
# able to build and run the entire application.

PROJECT_REL_DIR=.
include ${PROJECT_REL_DIR}/common.mk
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}

GO_SERVICE_PACKAGES=./portal/... ./phylum/...
GO_API_PACKAGES=./api/...
GO_PACKAGES=${GO_SERVICE_PACKAGES} ${GO_API_PACKAGES}

SUBSTRATEHCP_FILE ?= ${PWD}/${SUBSTRATE_PLUGIN_PLATFORM_TARGETED}

export SUBSTRATEHCP_FILE

.DEFAULT_GOAL := default
.PHONY: default
default: all

.PHONY: all push clean test

clean:
	rm -rf build

all: plugin
.PHONY: plugin plugin-linux plugin-darwin
plugin: ${SUBSTRATE_PLUGIN}

plugin-linux: ${SUBSTRATE_PLUGIN_LINUX}

plugin-darwin: ${SUBSTRATE_PLUGIN_DARWIN}

all: tests-api
.PHONY: tests-api
tests-api: make-C/tests/default
	@
.PHONY: tests-api-clean
tests-api-clean: make-C/tests/clean
	@

all: api
.PHONY: api
api: make-C/api/default
	@

all: phylum
.PHONY: phylum
phylum: make-C/phylum/default
	@
test: phylumtest unit-portal
.PHONY: phylumtest
phylumtest: make-C/phylum/test
	@
clean: phylumclean
.PHONY: phylumclean
phylumclean: make-C/phylum/clean
	@

all: portal
.PHONY: portal
portal: plugin make-C/portal/default
	@

clean: portalclean
.PHONY: portalclean
portalclean: make-C/portal/clean
	@

# portal-image builds only the oracle image. CI then checks it with the
# shared build-harden action (see harden-env in common.go.mk).
.PHONY: portal-image
portal-image: make-C/portal/docker-build
	@

docker-push: portal-push
.PHONY: portal-push
portal-push: make-C/portal/push
	@

docker-push-manifests: portal-push-manifests
.PHONY: portal-push-manifests
portal-push-manifests: make-C/portal/push-manifests
	@

.PHONY: fabric
all: fabric
fabric: make-C/fabric/default
	@
.PHONY: fabricclean
clean: fabricclean
fabricclean: make-C/fabric/clean
	@
.PHONY: storage-up
storage-up:
	cd fabric && $(MAKE) up install init

.PHONY: storage-down
storage-down:
	-cd fabric && $(MAKE) down

.PHONY: service-up
service-up: api portal
	SUBSTRATE_VERSION=${SUBSTRATE_VERSION} ./network_compose.py local up -d

.PHONY: service-down
service-down:
	-./network_compose.py local down

# Tracing is opt in. With TRACING=1, up and mem-up also start the tracing
# stack (compose/tracing.yaml: otelcol, Tempo, Grafana) and point the oracle,
# gateway and chaincode at it. Without it, no service gets an OTLP endpoint,
# so none of them makes or queues spans for a collector that is not there
# (a CI run without a collector must not hold spans in memory).
#
# The stack starts after the network that it joins (byfn): the services
# start first and their exporters retry until otelcol is up, a few seconds
# later. down and mem-down always stop it, with or without TRACING, so a
# stack left running never keeps byfn from being removed.
#
# An endpoint you export yourself (for example SANDBOX_ORACLE_OTLP_ENDPOINT
# to a collector of your own) wins over TRACING's default.
#
# Only 1, true, yes or on turn it on, so TRACING=0 or TRACING=false is off.
TRACING ?=
TRACING_ON=$(filter 1 true yes on,${TRACING})
TRACING_OTLP_ENDPOINT ?= http://otelcol:4317
ifneq (${TRACING_ON},)
SANDBOX_ORACLE_OTLP_ENDPOINT ?= ${TRACING_OTLP_ENDPOINT}
SHIROCLIENT_GATEWAY_OTLP_TRACER_ENDPOINT ?= ${TRACING_OTLP_ENDPOINT}
CHAINCODE_OTLP_TRACER_ENDPOINT ?= ${TRACING_OTLP_ENDPOINT}
SUBSTRATE_OTLP_ENDPOINT ?= ${TRACING_OTLP_ENDPOINT}
export SANDBOX_ORACLE_OTLP_ENDPOINT SHIROCLIENT_GATEWAY_OTLP_TRACER_ENDPOINT \
	CHAINCODE_OTLP_TRACER_ENDPOINT SUBSTRATE_OTLP_ENDPOINT
endif

# The stack has its own compose project, so the network's own compose down
# (project fnb) neither removes it nor reports it as orphans.
TRACING_COMPOSE=DOCKER_UID=$$(id -u) DOCKER_GID=$$(id -g) \
	docker compose -p sandbox-tracing -f compose/tracing.yaml
TRACING_SPAN_FILE=build/otlp/traces.jsonl

.PHONY: tracing-up
# tracing-up joins the byfn network, so it stops with a clear message when
# no network is running. It stops a running stack first and starts a new
# span file, so a running otelcol never keeps writing to a deleted file, and
# the file, like Tempo, holds only the spans of the new stack.
tracing-up: tracing-down
	@docker network inspect byfn >/dev/null 2>&1 || \
		{ echo "tracing-up: no byfn network. Run make up or make mem-up first, or use TRACING=1 with them." >&2; exit 1; }
	mkdir -p $(dir ${TRACING_SPAN_FILE})
	rm -f $(dir ${TRACING_SPAN_FILE})traces*.jsonl
	${TRACING_COMPOSE} up -d
	@echo "Tracing: Grafana http://localhost:3000, spans in ${TRACING_SPAN_FILE}"

.PHONY: tracing-down
tracing-down:
	-${TRACING_COMPOSE} down --volumes

.PHONY: up
up: all service-down tracing-down storage-down storage-up $(if ${TRACING_ON},tracing-up) service-up
	@

.PHONY: down
down: service-down tracing-down storage-down
	@

# up-tracing and mem-up-tracing are short for up and mem-up with TRACING=1.
.PHONY: up-tracing
up-tracing:
	$(MAKE) up TRACING=1

.PHONY: mem-up-tracing
mem-up-tracing:
	$(MAKE) mem-up TRACING=1

.PHONY: init
init:
	-cd fabric && $(MAKE) init

.PHONY: upgrade
upgrade: all service-down init service-up
	@

.PHONY: mem-up
mem-up: all mem-down
	SUBSTRATE_VERSION=${SUBSTRATE_VERSION} ./network_compose.py mem up -d
	$(if ${TRACING_ON},$(MAKE) tracing-up)

.PHONY: mem-down
mem-down: tracing-down
	-./network_compose.py mem down

# citest runs all tests within containers, as in CI.
.PHONY: citest
citest: plugin unit integrationcitest
	@

# unit-portal runs the Go tests (oracle functional tests and API tests) on the
# host against the downloaded substrate plugin; it does not need Docker.
# -count=1 disables the Go test cache: the plugin loads the phylum's .lisp
# files itself, so go test cannot see phylum edits and would report a stale
# cached pass.
.PHONY: unit-portal
unit-portal: plugin
	go test -count=1 -v ./...

# oraclegotest is an alias for unit-portal.
.PHONY: oraclegotest
oraclegotest: unit-portal
	@

.PHONY: unit
unit: unit-portal unit-other
	@echo "all tests passed"

.PHONY: unit-other
unit-other: phylumtest
	@echo "phylum tests passed"

# NOTE:  The `citest` target manages creating/destroying a compose network.  To
# run tests repeatedly execute the `integration` target directly.
.PHONY: integrationcitest
# The `down` wouldn't execute without this syntax
integrationcitest:
	$(MAKE) up
	$(MAKE) integration
	$(MAKE) down

.PHONY: integration
integration:
	./scripts/wait-for-oracle.sh
	@cd tests && $(MAKE) test-docker

.PHONY: repl
repl: make-C/phylum/repl
	@

# this target is called by git-hooks/pre-push. It's separated into its own target
# to allow us to update the git-hooks without having to reinstall the hook
# It generates postman artifacts and protobuf artifacts.
.PHONY: pre-push
pre-push:
	$(MAKE) tests-api
	cd api && $(MAKE)

.PHONY:
download: plugin
	@

${STATIC_PLUGINS_DUMMY}:
	${MKDIR_P} $(dir $@)
	SUBSTRATE_VERSION=${SUBSTRATE_VERSION} ./scripts/obtain-plugin.sh
	touch $@

${SUBSTRATE_PLUGIN}: ${STATIC_PLUGINS_DUMMY}
	@

# observability-up and observability-down are the old names of tracing-up
# and tracing-down.
.PHONY: observability-up observability-down
observability-up: tracing-up
observability-down: tracing-down

.PHONY: init-docs
init-docs:
	git submodule update --init --recursive --remote docs

.PHONY: setup
setup: init-docs download
	@echo "Running project setup..."

.PHONY: publish-docker
publish-docker: docker-push
	@

.PHONY: publish-docker-manifests
publish-docker-manifests: docker-push-manifests
	@

.PHONY: publish
publish: publish-docker
	@

.PHONY:
docker-push: all
	@

