# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# common.mk
#
# A base makefile that is useful for writing other makefiles.  Outside of the
# root directory it is expected for makefiles to define PROJECT_REL_DIR as a
# relative path to the project root and use that to include common.mk:
#
#		PROJECT_REL_DIR=..
# 		include ${PROJECT_REL_DIR}/common.mk

# PROJECT_REL_DIR is the (relative) path to the repository's root directory.
# This facilitates cross-directory make dependencies.
PROJECT_REL_DIR ?= .
PROJECT_ABS_DIR=$(abspath ${PROJECT_REL_DIR})

include ${PROJECT_REL_DIR}/common.config.mk

PROJECT_PATH=$(shell awk '$$1 == "module" {print $$2};' ${PROJECT_REL_DIR}/go.mod)
LICENSE_FILE_ROOT=${DOCKER_PROJECT_DIR}/.luther-license.yaml
LICENSE_FILE=${PROJECT_ABS_DIR}/.luther-license.yaml
PRESIGNED_PATH=${PROJECT_REL_DIR}/build/presigned.json

BUILD_ID=$(shell git rev-parse --short HEAD)
BUILD_VERSION=${VERSION}$(if $(findstring SNAPSHOT,${VERSION}),-${BUILD_ID},)

BUILD_IMAGE_GO_ALPINE=luthersystems/build-go-alpine:${BUILDENV_TAG}
SERVICE_BASE_IMAGE_ALPINE=luthersystems/service-base-alpine:${BUILDENV_TAG}
BUILD_IMAGE_API=luthersystems/build-api:${BUILDENV_TAG}

SHIROCLIENT_IMAGE=luthersystems/shiroclient
NETWORK_BUILDER_IMAGE=luthersystems/fabric-network-builder
SHIROTESTER_IMAGE=luthersystems/shirotester:${SHIROTESTER_VERSION}
MARTIN_IMAGE=luthersystems/martin:${MARTIN_VERSION}

UNAME := $(shell uname)
SUBSTRATE_PLUGIN_OS=${PROJECT_REL_DIR}/build/substratehcp-$(1)-amd64-${SUBSTRATE_VERSION}
SUBSTRATE_PLUGIN_LINUX=$(call SUBSTRATE_PLUGIN_OS,linux)
SUBSTRATE_PLUGIN_DARWIN=$(call SUBSTRATE_PLUGIN_OS,darwin)
SUBSTRATE_PLUGIN=${SUBSTRATE_PLUGIN_DARWIN} ${SUBSTRATE_PLUGIN_LINUX}
ifeq ($(UNAME), Linux)
SUBSTRATE_PLUGIN_PLATFORM_TARGETED=${SUBSTRATE_PLUGIN_LINUX}
endif
ifeq ($(UNAME), Darwin)
SUBSTRATE_PLUGIN_PLATFORM_TARGETED=${SUBSTRATE_PLUGIN_DARWIN}
endif

GO_PKG_VOLUME=${PROJECT}-build-gopath-pkg
GO_PKG_PATH=/go/pkg
GO_PKG_MOUNT=--mount='type=volume,source=${GO_PKG_VOLUME},destination=${GO_PKG_PATH}' -e GOCACHE=${GO_PKG_PATH}/${PROJECT}-go-build

ifeq ($(OS),Windows_NT)
	IS_WINDOWS=1
endif

CP=cp
RM=rm
DOCKER=docker
DOCKER_RUN_OPTS=--rm
DOCKER_RUN=${DOCKER} run ${DOCKER_RUN_OPTS}
CHOWN=$(if $(CIRCLECI),sudo chown,chown)
CHOWN_USR=$(shell id -u)
DOCKER_USER=$(shell id -u):$(shell id -g)
CHOWN_GRP=$(if $(or $(IS_WINDOWS),$(CIRCLECI)),,$(shell id -g))
DOMAKE=cd $1 && $(MAKE) $2 # NOTE: this is not used for now as it does not work with -j for some versions of Make
MKDIR_P=mkdir -p
TOUCH=touch
GZIP=gzip
GUNZIP=gunzip
TIME_P=time -p
TAR=tar

# The Makefile determines whether to build a container or not by consulting a
# dummy file that is touched whenever the container is built.  The function,
# IMAGE_DUMMY, computes the path to the dummy file.
DUMMY_TARGET=build/$(1)/$(2)/.dummy
IMAGE_DUMMY=$(call DUMMY_TARGET,image,$(1))
PUSH_DUMMY=$(call DUMMY_TARGET,push,$(1))
PLUGIN_DUMMY=$(call DUMMY_TARGET,plugin,$(1))
PRESIGN_DUMMY=$(call DUMMY_TARGET,presign,$(1))
STATIC_PLUGINS_DUMMY=$(call PLUGIN_DUMMY,${SUBSTRATE_VERSION})
STATIC_PRESIGN_DUMMY=$(abspath ${PROJECT_REL_DIR}/$(call PRESIGN_DUMMY,${SUBSTRATE_VERSION}))

GIT_LS_FILES=$(shell git ls-files $(1))

DOCKER_WIN_DIR=$(shell cygpath -wm $(realpath $(1)))
DOCKER_NIX_DIR=$(realpath $(1))
DOCKER_DIR=$(if $(IS_WINDOWS),$(call DOCKER_WIN_DIR, $(1)),$(call DOCKER_NIX_DIR, $(1)))

CODESPACE_DOCKER_PROJECT_DIR:=$(abspath ${LOCAL_WORKSPACE_FOLDER})
STANDALONE_DOCKER_PROJECT_DIR:=$(call DOCKER_DIR, ${PROJECT_REL_DIR})
DOCKER_PROJECT_DIR:=$(if $(LOCAL_WORKSPACE_FOLDER),${CODESPACE_DOCKER_PROJECT_DIR},${STANDALONE_DOCKER_PROJECT_DIR})

# print out make variables, e.g.:
# make echo:VERSION
#
# NOTE:  Depending on the version of make you may want to `unset MAKELEVEL` if
# capturing variable values with `$(make echo:*)` in scripts (see the ./scripts
# directory for examples of this).  Failing to do so can cause script targets
# like `make plugin` fail.
echo\:%:
	@echo $($*)

# Check if the requested image exists locally then pull it if necessary.
# NOTE: The / is necessary to prevent automatic path splitting on the target
# names.
docker-pull/%: id=$(shell docker image inspect -f "{{.Id}}" $* 2>/dev/null)
docker-pull/%:
	@[ -n "${id}" ] || { echo "retrieving $*" && docker pull $*; }
