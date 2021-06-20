# Copyright © 2021 Luther Systems, Ltd. All right reserved.

PROJECT_REL_DIR=..
include ${PROJECT_REL_DIR}/common.mk

DOCKER_PROJECT_DIR:=$(call DOCKER_DIR, ../)

BUILD_IMAGE=${BUILD_IMAGE_API}

BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}
BUILD_WORKDIR=${BUILD_IMAGE_PROJECT_DIR}/tests

POSTMAN_JSON=e2e.postman_collection.json
POSTMAN_SOURCE_FILES=$(shell find . -name '*.postman_collection.json' -o -name '*.martin_collection.yaml' | grep -v '${POSTMAN_JSON}')

.PHONY: default
default: all

.PHONY: all
all:

.PHONY: clean
clean:
	${RM} -f ${POSTMAN_JSON}

.PHONY: build
all: build
build: ${POSTMAN_JSON}

${POSTMAN_JSON}: ${POSTMAN_SOURCE_FILES}
	cd ../ && ./tests/cat-postman-collections-docker.sh > tests/$@
