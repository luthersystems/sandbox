# Copyright © 2021 Luther Systems, Ltd. All right reserved.

PROJECT_REL_DIR=..
include ${PROJECT_REL_DIR}/common.mk

TESTS_DIR=${PROJECT_ABS_DIR}/tests

LOCAL_POSTMAN_ENVIRONMENT=Docker.postman_environment.json

MARTIN_ENV_OPTS=
MARTIN_BIND_SOURCE=${PROJECT_ABS_DIR}
MARTIN_BIND_DEST=/etc/postman
MARTIN_BIND=${MARTIN_BIND_SOURCE}:${MARTIN_BIND_DEST}

MARTIN_COMMON_OPTS=-v ${MARTIN_BIND} -w ${MARTIN_BIND_DEST}/tests ${MARTIN_ENV_OPTS} --entrypoint sh
RUN_MARTIN=${DOCKER_RUN} ${MARTIN_COMMON_OPTS} ${MARTIN_IMAGE}
RUN_MARTIN_NETWORK=${DOCKER_RUN} ${MARTIN_COMMON_OPTS} --network fnb_byfn ${MARTIN_IMAGE}

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

.PHONY: test-docker
test-docker:
	${TESTS_DIR}/run-postman-collections-docker.sh ${LOCAL_POSTMAN_ENVIRONMENT}

${POSTMAN_JSON}: ${POSTMAN_SOURCE_FILES}
	cd ../ && ./tests/cat-postman-collections-docker.sh > tests/$@

.PHONY: martincmd
martincmd:
	@echo ${RUN_MARTIN}

