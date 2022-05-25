# Copyright © 2021 Luther Systems, Ltd. All right reserved.

PROJECT_REL_DIR=../
include ${PROJECT_REL_DIR}common.mk
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}

BUILD_IMAGE=${BUILD_IMAGE_API}:${BUILDENV_TAG}
PROTO_SOURCE_FILES=$(wildcard pb/*.proto) $(wildcard srvpb/*.proto)

BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}
BUILD_WORKDIR=${BUILD_IMAGE_PROJECT_DIR}/api

SWAGGER_JSON=swagger/oracle.swagger.json

GW_FILES=srvpb/oracle.pb.gw.go
PROTO_FILES=$(patsubst %.proto,%.pb.go,$(PROTO_SOURCE_FILES)) ${GW_FILES}
ARTIFACTS=${PROTO_FILES} ${SWAGGER_JSON}

.PHONY: default
default: all

.PHONY: all
all: ${ARTIFACTS}

.PHONY: clean
clean:
	${RM} -f ${ARTIFACTS} ${SWAGGER_JSON} build

${ARTIFACTS}: ${PROTO_SOURCE_FILES}
	@echo "Building api"
	${DOCKER_RUN} \
		-u ${DOCKER_USER} \
		-v ${DOCKER_PROJECT_DIR}:${BUILD_IMAGE_PROJECT_DIR} \
		-e PROJECT_PATH="${PROJECT_PATH}" \
		-e VERSION="${VERSION}" \
		-w ${BUILD_WORKDIR} \
		--init \
		--entrypoint make \
		${BUILD_IMAGE} -f /opt/Dockerfile.api.mk ${ARTIFACTS} ${SWAGGER_ARTIFACTS}

.PHONY: unit
unit:
	go test ./...
	@echo "all tests passed"

# redoc can be used for viewing generated oracle swagger file locally, you need
# to install redoc-cli manually: npm i -g redoc-cli
# path of the swagger file is defined by SWAGGER_JSON in api's makefile
.PHONY: redoc
redoc:
	npx redoc-cli serve -p 57505 ./${SWAGGER_JSON}
