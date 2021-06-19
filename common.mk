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

include ${PROJECT_REL_DIR}/common.config.mk

PROJECT_PATH=$(shell awk '$$1 == "module" {print $$2};' ${PROJECT_REL_DIR}/go.mod)
LICENSE_FILE=${HOME}/.luther-license.yaml

BUILD_ID=$(shell git rev-parse --short HEAD)
BUILD_VERSION=${VERSION}$(if $(findstring SNAPSHOT,${VERSION}),-${BUILD_ID},)

BUILD_IMAGE_GO=luthersystems/build-go:${BUILDENV_TAG}
BUILD_IMAGE_API=luthersystems/build-api:${BUILDENV_TAG}

SHIROCLIENT_IMAGE=luthersystems/shiroclient
NETWORK_BUILDER_IMAGE=luthersystems/fabric-network-builder
SHIROTESTER_IMAGE=luthersystems/shirotester:${SHIROTESTER_VERSION}
MARTIN_IMAGE=luthersystems/martin:${MARTIN_VERSION}

SUBSTRATE_PLUGIN_OS=${PROJECT_REL_DIR}/build/substratehcp-$(1)-amd64-${SUBSTRATE_VERSION}
SUBSTRATE_PLUGIN_LINUX=$(call SUBSTRATE_PLUGIN_OS,linux)
SUBSTRATE_PLUGIN_DARWIN=$(call SUBSTRATE_PLUGIN_OS,darwin)
SUBSTRATE_PLUGIN=${SUBSTRATE_PLUGIN_DARWIN} ${SUBSTRATE_PLUGIN_LINUX}

# FIXME: replace with optional GOPROXY?
GO_PKG_VOLUME=${PROJECT}-build-gopath-pkg
GO_PKG_PATH=/go/pkg
GO_PKG_MOUNT=$(if $(CI),-v $(PWD)/build/pkg:${GO_PKG_PATH},--mount='type=volume,source=${GO_PKG_VOLUME},destination=${GO_PKG_PATH}')

#DOCKER_IN_DOCKER_MOUNT=-v /var/run/docker.sock:/var/run/docker.sock -v "${HOME}/.docker:/root/.docker"
DOCKER_IN_DOCKER_MOUNT=-v /var/run/docker.sock:/var/run/docker.sock

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

UNAME := $(shell uname)
GIT_LS_FILES=$(shell git ls-files $(1))

DOCKER_WIN_DIR=$(shell cygpath -wm $(realpath $(1)))
DOCKER_NIX_DIR=$(realpath $(1))
DOCKER_DIR=$(if $(IS_WINDOWS),$(call DOCKER_WIN_DIR, $(1)),$(call DOCKER_NIX_DIR, $(1)))

# print out make variables, e.g.:
# make echo:VERSION
echo\:%:
	@echo $($*)


# Check if the requested image exists locally then pull it if necessary.
# NOTE: The / is necessary to prevent automatic path splitting on the target
# names.
docker-pull/%: id=$(shell docker image inspect -f "{{.Id}}" $* 2>/dev/null)
docker-pull/%:
	@[[ -n "${id}" ]] || { echo "retrieving $*" && docker pull $*; }
