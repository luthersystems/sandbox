# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# config.mk
#
# General project configuration that configures make targets and tracks
# dependency versions.

# PROJECT and VERSION are attached to docker images and phylum deployment
# artifacts created during the build process.
PROJECT=sandbox
VERSION=0.1.0-SNAPSHOT
SERVICE_DIR=portal

# The makefiles use docker images to build artifacts in this project.  These
# variables configure the images used for builds.
BUILDENV_TAG=v0.0.92

# These variables control the version numbers for parts of the Luther platform
# and should be kept up-to-date to leverage the latest platform features.
# See release notes: https://docs.luthersystems.com/luther/platform/release-notes
#SUBSTRATE_VERSION=v2.205.6
#SUBSTRATE_VERSION=v2.205.11-SNAPSHOT.3-06e4528d
SUBSTRATE_VERSION=v2.205.11-SNAPSHOT.3-06e4528d
CC_VERSION=2.186.0-fabric2-SNAPSHOT-23cd393c-amd64
#CC_VERSION=v2.205.11-SNAPSHOT.3-06e4528d
CHAINCODE_VERSION=${CC_VERSION}
VERSION_SUBSTRATE=${CC_VERSION} # is this needed
SHIROCLIENT_VERSION=${SUBSTRATE_VERSION}
CONNECTORHUB_VERSION=${SUBSTRATE_VERSION}
SHIROTESTER_VERSION=${SUBSTRATE_VERSION}
NETWORK_BUILDER_VERSION=v0.0.2
MARTIN_VERSION=v0.1.0

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

# These variables configure the Hyperledger Fabric image versions for running
# the full test network.
FABRIC_IMAGE_TAG=2.5.9
FABRIC_CA_IMAGE_TAG=1.5.12
BASE_IMAGE_TAG=0.4.22
