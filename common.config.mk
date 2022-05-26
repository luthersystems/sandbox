# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# config.mk
#
# General project configuration that configures make targets and tracks
# dependency versions.

# PROJECT and VERSION are attached to docker images and phylum deployment
# artifacts created during the build process.
PROJECT=sandbox
VERSION=0.1.0-SNAPSHOT
SERVICE_DIR=oracleserv/sandbox-oracle

# The makefiles use docker images to build artifacts in this project.  These
# variables configure the images used for builds.
BUILDENV_TAG=0.0.51-SNAPSHOT

# These variables control the version numbers for parts of the LEIA platform
# and should be kept up-to-date to leverage the latest platform features.
# See release notes: https://docs.luthersystems.com/luther/platform/release-notes
SUBSTRATE_VERSION=2.170.0-fabric2
SHIROCLIENT_VERSION=${SUBSTRATE_VERSION}
SHIROTESTER_VERSION=${SUBSTRATE_VERSION}
CHAINCODE_VERSION=${SUBSTRATE_VERSION}
NETWORK_BUILDER_VERSION=${SUBSTRATE_VERSION}
MARTIN_VERSION=0.1.0-SNAPSHOT

# A golang module proxy server can greatly help speed up docker builds but the
# official proxy at https://proxy.golang.org only works for public modules.
# When your application needs private go module dependencies consider running a
# local athens-proxy server with an ssh/http configuration which can access
# private source repositories, otherwise set GOPRIVATE (or GONOPROXY and
# GONOSUMDB) if private modules are needed.  Though be aware that GOPRIVATE
# requires credentials (e.g. for github ssh) be available during builds which
# complicates things considerably.
# 		https://docs.gomods.io/
# 		https://golang.org/ref/mod#private-modules
GOPROXY ?= https://proxy.golang.org
GOPRIVATE ?=
GONOPROXY ?= ${GOPRIVATE}
GONOSUMDB ?= ${GOPRIVATE}
