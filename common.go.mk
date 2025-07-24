# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# common.go.mk
#
# A base makefile for building golang applications and packaging them in docker
# containers.

PROJECT_REL_DIR ?= .
include ${PROJECT_REL_DIR}/common.mk

BUILD_IMAGE=${BUILD_IMAGE_GO_ALPINE}:${BUILDENV_TAG}
SERVICE_BASE_IMAGE=${SERVICE_BASE_IMAGE_ALPINE}:${BUILDENV_TAG}

BUILD_IMAGE_SERVICE_DIR=${SERVICE_ROOT_DIR}
BUILD_IMAGE_PROJECT_DIR=/go/src/${PROJECT_PATH}
BUILD_WORKDIR=${BUILD_IMAGE_PROJECT_DIR}/${BUILD_IMAGE_SERVICE_DIR}

DOCKER_IMAGE=${PROJECT}/${SERVICE}
DOCKER_IMAGE_DUMMY=$(call IMAGE_DUMMY,${DOCKER_IMAGE}/${VERSION})

FQ_STATIC_IMAGE=$(call FQ_DOCKER_IMAGE,${DOCKER_IMAGE},${SERVICE})
FQ_STATIC_IMAGE_DUMMY=$(call PUSH_DUMMY,${FQ_DOCKER_IMAGE}/${BUILD_VERSION}${TAG_SUFFIX})
FQ_MANIFEST_DUMMY=$(call MANIFEST_DUMMY,${FQ_STATIC_IMAGE}/${BUILD_VERSION}${TAG_SUFFIX})

GO_SOURCE_FILES=$(shell find ${PROJECT_REL_DIR} -name '*.go' | grep -v '/vendor/')

GO_PKG_DUMMY=${PROJECT_REL_DIR}/$(call DUMMY_TARGET,pkg,${GO_PKG_VOLUME})
GO_PKG_VOLUME_DUMMY=${PROJECT_REL_DIR}/$(call DUMMY_TARGET,volume,${GO_PKG_VOLUME})

GO_BUILD_TAGS ?= osusergo,netgo,cgo,timetzdata
GO_BUILD_FLAGS="-installsuffix ${GO_BUILD_TAGS} -tags ${GO_BUILD_TAGS} -buildvcs=false"

HOST_GO_ENV=SUBSTRATEHCP_FILE=${SUBSTRATEHCP_FILE}

.PHONY: default
default: docker-build
	@

.PHONY: docker-build
docker-build: ${DOCKER_IMAGE_DUMMY}
	@

.PHONY: clean
clean:
	${RM} -rf build ${GO_PKG_VOLUME_DUMMY}
	# docker volume rm will fail if the volume doesn't exist
	-${DOCKER} volume rm ${GO_PKG_VOLUME}
	# make sure it's really gone
	sh -c '! ${DOCKER} volume inspect ${GO_PKG_VOLUME}'

${DOCKER_IMAGE_DUMMY}: ${GO_SOURCE_FILES} Makefile ${PROJECT_REL_DIR}/common.mk ${PROJECT_REL_DIR}/go.mod ${PROJECT_REL_DIR}/common.go.mk ${PROJECT_REL_DIR}/Dockerfile
	${MKDIR_P} $(dir $@)
	@echo "Building image ${DOCKER_IMAGE}"
	${TIME_P} ${DOCKER} build \
		--build-arg "BUILD_IMAGE=${BUILD_IMAGE}" \
		--build-arg "SERVICE_BASE_IMAGE=${SERVICE_BASE_IMAGE}" \
		--build-arg "GONOSUMDB=${GONOSUMDB}" \
		--build-arg "GOPROXY=${GOPROXY}" \
		--build-arg "GO_BUILD_TAGS=${GO_BUILD_TAGS}" \
		--build-arg "VERSION=${VERSION}" \
		--build-arg "SERVICE_DIR=${SERVICE_DIR}" \
		-t ${DOCKER_IMAGE}:latest \
		-t ${DOCKER_IMAGE}:${VERSION} \
		-f ${PROJECT_REL_DIR}/Dockerfile ${PROJECT_REL_DIR}
	${TOUCH} $@

${GO_PKG_DUMMY}:
	${DOCKER} volume inspect ${GO_PKG_VOLUME} || ${DOCKER} volume create ${GO_PKG_VOLUME}
	mkdir -p $(dir $@)
	touch $@

.PHONY: host-go-env
host-go-env:
	@echo export "${HOST_GO_ENV}"

.PHONY: push
push: ${FQ_STATIC_IMAGE_DUMMY}
	@

# DOCKER_IMAGE exists with a tag VERSION and BUILD_VERSION but FQ_STATIC_IMAGE
# only has a BUILD_VERSION tag.  Ideally perhaps DOCKER_IMAGE would only have a
# BUILD_VERSION tag but the git hash in the BUILD_VERSION will blow makefile
# dependency caching for DUMMY targets and cause additional unnecessary builds
# during development.
${FQ_STATIC_IMAGE_DUMMY}: ${DOCKER_IMAGE_DUMMY}
	${DOCKER} tag ${DOCKER_IMAGE}:${VERSION} ${DOCKER_IMAGE}:${BUILD_VERSION}${TAG_SUFFIX}
	${DOCKER} tag ${DOCKER_IMAGE}:${VERSION} ${FQ_STATIC_IMAGE}:${BUILD_VERSION}${TAG_SUFFIX}
	${DOCKER} push ${FQ_STATIC_IMAGE}:${BUILD_VERSION}${TAG_SUFFIX}
	${MKDIR_P} $(dir $@)
	${TOUCH} $@

.PHONY: push-manifests
push-manifests: ${FQ_MANIFEST_DUMMY}
	@

${FQ_MANIFEST_DUMMY}:
	${DOCKER} buildx imagetools create \
		--tag ${FQ_STATIC_IMAGE}:latest \
		${FQ_STATIC_IMAGE}:${BUILD_VERSION}-arm64 \
		${FQ_STATIC_IMAGE}:${BUILD_VERSION}-amd64
	${DOCKER} buildx imagetools create \
		--tag ${FQ_STATIC_IMAGE}:${BUILD_VERSION} \
		${FQ_STATIC_IMAGE}:${BUILD_VERSION}-arm64 \
		${FQ_STATIC_IMAGE}:${BUILD_VERSION}-amd64
	${MKDIR_P} $(dir $@)
	${TOUCH} $@
