# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# Makefile
#
# The primary project makefile that should be run from the root directory and is
# able to build and run the entire application.

PROJECT_REL_DIR=.
include ${PROJECT_REL_DIR}/common.mk
DOCKER_PROJECT_DIR:=$(call DOCKER_DIR, ${PROJECT_REL_DIR})
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}

GO_SERVICE_PACKAGES=./oracleserv/... ./phylum/...
GO_API_PACKAGES=./api/...
GO_PACKAGES=${GO_SERVICE_PACKAGES} ${GO_API_PACKAGES}

.PHONY: default
default: all

.PHONY: ci-checks
ci-checks:
	bash ${PROJECT_REL_DIR}/scripts/ci-checks.sh

.PHONY: all push clean test

clean:
	rm -rf build

.PHONY: format
format:
	cd phylum && $(MAKE) format

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
push: phylumpush
phylumpush:
	cd phylum && $(MAKE) s3

all: oracle
.PHONY: oracle
oracle: plugin
	cd oracleserv/${PROJECT}-oracle && $(MAKE)
clean: oracleclean
.PHONY: oracleclean
oracleclean:
	cd oracleserv/${PROJECT}-oracle && $(MAKE) clean
push: oraclepush
oraclepush: plugin
	cd oracleserv/${PROJECT}-oracle && $(MAKE) push
.PHONY: oracletest
oracletest: plugin
	cd oracleserv/${PROJECT}-oracle && $(MAKE) test
test: oraclegotest
.PHONY: oraclegotest
oraclegotest: plugin
	cd oracleserv/${PROJECT}-oracle && $(MAKE) go-test

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
service-up: api oracle
	./${PROJECT}_compose.py local up -d

.PHONY: service-down
service-down:
	-./${PROJECT}_compose.py local down

.PHONY: up
up: all service-down storage-down storage-up service-up
	@

.PHONY: down
down: service-down storage-down
	@

.PHONY: init
init:
	-cd fabric && $(MAKE) init

.PHONY: upgrade
upgrade: all service-down init service-up
	@

.PHONY: mem-up
mem-up: all mem-down
	./${PROJECT}_compose.py mem up -d

.PHONY: mem-down
mem-down:
	-./${PROJECT}_compose.py mem down

# citest runs unit tests and integration tests within containers, like CI.
.PHONY: citest
citest: plugin lint gosec unit integrationcitest
	@

.PHONY: unit
unit: unit-oracle unit-other
	@echo "all tests passed"

.PHONY: unit-other
unit-other: phylumtest
	@echo "all tests passed"

.PHONY: unit-oracle
unit-oracle: oraclegotest
	@echo "all tests passed"


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
# It generates postman artifacts, protobuf artifacts and formats lisp code
.PHONY: pre-push
pre-push:
	$(MAKE) tests-api format
	cd api && $(MAKE)

download: ${SUBSTRATE_PLUGIN}
	cd fabric && $(MAKE) download
