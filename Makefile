# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# Makefile
#
# The primary project makefile that should be run from the root directory and is
# able to build and run the entire application.

PROJECT_REL_DIR=.
include ${PROJECT_REL_DIR}/common.mk
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}

ifndef LOCAL_WORKSPACE_FOLDER # if not in codespace
  include ${PROJECT_REL_DIR}/common.fullnetwork.mk
endif

GO_SERVICE_PACKAGES=./oracleserv/... ./phylum/...
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

all: oracle
.PHONY: oracle
oracle: plugin
	cd ${SERVICE_DIR} && $(MAKE)
clean: oracleclean
.PHONY: oracleclean
oracleclean:
	cd ${SERVICE_DIR} && $(MAKE) clean
.PHONY: oraclestaticchecks
oraclestaticchecks:
	cd ${SERVICE_DIR} && $(MAKE) static-checks
.PHONY: oracletest
oracletest: plugin
	cd ${SERVICE_DIR} && $(MAKE) test
test: oraclegotest
.PHONY: oraclegotest
oraclegotest: plugin
	cd ${SERVICE_DIR} && $(MAKE) go-test

.PHONY: fabric
all: fabric
fabric:
	cd fabric && $(MAKE)
.PHONY: fabricclean
clean: fabricclean
fabricclean:
	cd fabric && $(MAKE) clean

.PHONY: up
up: all mem-down
ifndef LOCAL_WORKSPACE_FOLDER # if not in codespace
	make full-up
else
	$(error Target 'up' is for a full network, not supported in codespaces)
endif

.PHONY: down
down: mem-down
ifndef LOCAL_WORKSPACE_FOLDER # if not in codespace
	make full-down
endif
	@

.PHONY: mem-up
mem-up: all mem-down
	./${PROJECT}_compose.py mem up -d

.PHONY: mem-down
mem-down:
	-./${PROJECT}_compose.py mem down

# citest runs unit tests and integration tests within containers, like CI.
.PHONY: citest
citest: plugin unit
	@

.PHONY: unit
unit: unit-oracle unit-other
	@echo "all tests passed"

.PHONY: unit-other
unit-other: phylumtest
	@echo "phylum tests passed"

.PHONY: unit-oracle
unit-oracle: oraclegotest
	@echo "service tests passed"

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
	cd fabric && $(MAKE) download

.PHONY: print-export-path
print-export-path:
	echo "export SUBSTRATEHCP_FILE=${PWD}/${SUBSTRATE_PLUGIN_PLATFORM_TARGETED}"

${STATIC_PRESIGN_DUMMY}: ${LICENSE_FILE}
	${MKDIR_P} $(dir $@)
	./scripts/obtain-presigned.sh
	touch $@

${PRESIGNED_PATH}: ${STATIC_PRESIGN_DUMMY}
	@

${STATIC_PLUGINS_DUMMY}: ${PRESIGNED_PATH}
	${MKDIR_P} $(dir $@)
	./scripts/obtain-plugin.sh
	touch $@

${SUBSTRATE_PLUGIN}: ${STATIC_PLUGINS_DUMMY}
	@
