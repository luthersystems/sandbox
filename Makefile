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
tests-api:
	cd tests && $(MAKE)
.PHONY: tests-api-clean
tests-api-clean:
	cd tests && $(MAKE) clean

all: api
.PHONY: api
api:
	cd api && $(MAKE)

all: phylum
.PHONY: phylum
phylum:
	cd phylum && $(MAKE)
test: phylumtest
.PHONY: phylumtest
phylumtest:
	cd phylum && $(MAKE) test
clean: phylumclean
.PHONY: phylumclean
phylumclean:
	cd phylum && $(MAKE) clean

all: portal
.PHONY: portal
portal: plugin
	cd ${SERVICE_DIR} && $(MAKE)
clean: portalclean
.PHONY: portalclean
portalclean:
	cd ${SERVICE_DIR} && $(MAKE) clean

.PHONY: fabric
all: fabric
fabric:
	cd fabric && $(MAKE)
.PHONY: fabricclean
clean: fabricclean
fabricclean:
	cd fabric && $(MAKE) clean

.PHONY: storage-up
storage-up:
	cd fabric && $(MAKE) up install init

.PHONY: storage-down
storage-down:
	-cd fabric && $(MAKE) down

.PHONY: service-up
service-up: api portal
	./blockchain_compose.py local up -d

.PHONY: service-down
service-down:
	-./blockchain_compose.py local down

.PHONY: up
up: all service-down storage-down storage-up service-up
	@

.PHONY: down
down: explorer-down service-down storage-down
	@

.PHONY: init
init:
	-cd fabric && $(MAKE) init

.PHONY: upgrade
upgrade: all service-down init service-up
	@

.PHONY: mem-up
mem-up: all mem-down
	./blockchain_compose.py mem up -d

.PHONY: mem-down
mem-down: explorer-down
	-./blockchain_compose.py mem down

# citest runs all tests within containers, as in CI.
.PHONY: citest
citest: plugin unit integrationcitest
	@

.PHONY: unit-portal
unit-portal:
	go test -v ./...

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
	cd tests && $(MAKE) test-docker

.PHONY: repl
repl:
	cd phylum && $(MAKE) repl

# this target is called by git-hooks/pre-push. It's separated into its own target
# to allow us to update the git-hooks without having to reinstall the hook
# It generates postman artifacts and protobuf artifacts.
.PHONY: pre-push
pre-push:
	$(MAKE) tests-api
	cd api && $(MAKE)

.PHONY:
download: ${SUBSTRATE_PLUGIN}

.PHONY: print-export-path
print-export-path:
	echo "export SUBSTRATEHCP_FILE=${PWD}/${SUBSTRATE_PLUGIN_PLATFORM_TARGETED}"

${STATIC_PLUGINS_DUMMY}: ${PRESIGNED_PATH}
	${MKDIR_P} $(dir $@)
	./scripts/obtain-plugin.sh
	touch $@

${SUBSTRATE_PLUGIN}: ${STATIC_PLUGINS_DUMMY}
	@

.PHONY: explorer
explorer: explorer-up-clean

.PHONY: explorer-up
explorer-up:
	cd ${PROJECT_REL_DIR}/explorer && make up

.PHONY: explorer-up-clean
explorer-up-clean:
	cd ${PROJECT_REL_DIR}/explorer && make up-clean

.PHONY: explorer-down
explorer-down:
	cd ${PROJECT_REL_DIR}/explorer && make down

.PHONY: explorer-clean
explorer-clean:
	cd ${PROJECT_REL_DIR}/explorer && make down-clean

.PHONY: explorer-watch
explorer-watch:
	cd ${PROJECT_REL_DIR}/explorer && make watch
