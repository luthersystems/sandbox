# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# common.go.mk
#
# A base makefile for building golang applications and packaging them in docker
# containers.

PROJECT_REL_DIR ?= .
include ${PROJECT_REL_DIR}/common.mk
DOCKER_PROJECT_DIR:=$(call DOCKER_DIR, ${PROJECT_REL_DIR})

BIN_NAME=${PROJECT}-${SERVICE}
BIN=./build/bin/${BIN_NAME}
BUILD_IMAGE=${BUILD_IMAGE_GO}

BUILD_IMAGE_SERVICE_DIR=${SERVICE_ROOT_DIR}/${BIN_NAME}
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}
BUILD_WORKDIR=${BUILD_IMAGE_PROJECT_DIR}/${BUILD_IMAGE_SERVICE_DIR}

STATIC_IMAGE=${PROJECT}/${SERVICE}
STATIC_IMAGE_DUMMY=$(call IMAGE_DUMMY,${STATIC_IMAGE}/${VERSION})

GO_SOURCE_FILES=$(shell find ${PROJECT_REL_DIR} -name '*.go' | grep -v '/vendor/')

GO_MOD_ENV=-e "GOPROXY=${GOPROXY}" -e "GOPRIVATE=${GOPRIVATE}" -e "GONOPROXY=${GONOPROXY}" -e "GONOSUMDB=${GONOSUMDB}"

GO_PKG_DUMMY=${PROJECT_REL_DIR}/$(call DUMMY_TARGET,pkg,${GO_PKG_VOLUME})
GO_PKG_VOLUME_DUMMY=${PROJECT_REL_DIR}/$(call DUMMY_TARGET,volume,${GO_PKG_VOLUME})

#GO_TEST_BASE=${PROJECT_REL_DIR}/scripts/containerize.sh ${PROJECT_REL_DIR} "gotestsum --format=testname -- -parallel 8"
GO_TEST_BASE=${GO_HOST_EXTRA_ENV} go test
GO_TEST_TIMEOUT_10=${GO_TEST_BASE} -timeout 10m
GO_TEST_TIMEOUT_35=${GO_TEST_BASE} -timeout 35m

GO_HOST_OS=$(shell uname | tr '[:upper:]' '[:lower:]')
HOST_GO_ENV=SUBSTRATEHCP_FILE=${PWD}/$(call SUBSTRATE_PLUGIN_OS,${GO_HOST_OS})

SUBSTRATEHCP_MOUNT_PATH=/opt/substrate/$(notdir ${SUBSTRATE_PLUGIN_LINUX})
SUBSTRATEHCP_MOUNT=-v "${PWD}/${SUBSTRATE_PLUGIN_LINUX}:${SUBSTRATEHCP_MOUNT_PATH}" -e SUBSTRATEHCP_FILE=${SUBSTRATEHCP_MOUNT_PATH}

.PHONY: default
default: static
	@

.PHONY: static
static: ${STATIC_IMAGE_DUMMY}
	@

.PHONY: clean
clean:
	${RM} -rf build ${GO_ZONEINFO} ${GO_CERTS} ${GO_PKG_VOLUME_DUMMY}
	# docker volume rm will fail if the volume doesn't exist
	-${DOCKER} volume rm ${GO_PKG_VOLUME}
	# make sure it's really gone
	sh -c '! ${DOCKER} volume inspect ${GO_PKG_VOLUME}'

.PHONY: go-test
go-test:
	env "${HOST_GO_ENV}" ${GO_TEST_TIMEOUT_10} ./...

${STATIC_IMAGE_DUMMY}: ${GO_SOURCE_FILES} Makefile ${PROJECT_REL_DIR}/common.mk ${PROJECT_REL_DIR}/go.mod ${PROJECT_REL_DIR}/common.go.mk
	${MKDIR_P} $(dir $@)
	${TIME_P} ${DOCKER_RUN} \
		${DOCKER_IN_DOCKER_MOUNT} \
		${GO_PKG_MOUNT} \
		${SUBSTRATEHCP_MOUNT} \
		${GO_MOD_ENV} \
		-v ${DOCKER_PROJECT_DIR}:${BUILD_IMAGE_PROJECT_DIR} \
		-e "CGO_LDFLAGS_ALLOW=-Wl,--no-as-needed" \
		-e "BIN=${BIN}" \
		-e "VERSION=${VERSION}" \
		-e "STATIC_IMAGE=${STATIC_IMAGE}" \
		-w ${BUILD_WORKDIR} \
		${BUILD_IMAGE} static
	${TOUCH} $@

.PHONY: test
test: ${GO_PKG_DUMMY}
	${TIME_P} ${DOCKER_RUN} \
		${GO_PKG_MOUNT} \
		${SUBSTRATEHCP_MOUNT} \
		${GO_MOD_ENV} \
		-v ${DOCKER_PROJECT_DIR}:${BUILD_IMAGE_PROJECT_DIR} \
		-w  ${BUILD_WORKDIR} \
		${BUILD_IMAGE} test

${GO_PKG_DUMMY}:
	${DOCKER} volume inspect ${GO_PKG_VOLUME} || ${DOCKER} volume create ${GO_PKG_VOLUME}
	mkdir -p $(dir $@)
	touch $@

.PHONY: host-go-env
host-go-env:
	@echo export "${HOST_GO_ENV}"
