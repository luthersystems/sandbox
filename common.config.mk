# Copyright © 2021 Luther Systems, Ltd. All right reserved.

# config.mk
#
# General project configuration that configures make targets and tracks
# dependency versions.

# PROEJECT and VERSION are attached to docker images and phylum deployment
# artifacts created during the build process.
PROJECT=sandbox
VERSION=0.1.0-SNAPSHOT

# The makefiles use docker images to build artifacts in this project.  These
# variables configure the images used for builds.
BUILDENV_TAG=0.0.40

# These variables control the version numbers for parts of the LEIA platform
# and should be kept up-to-date to leverage the latest platform features.
SUBSTRATE_VERSION=2.159.0-plt131test-SNAPSHOT-9175e96
SHIROCLIENT_VERSION=2.159.0-fabric2-SNAPSHOT
SHIROTESTER_VERSION=2.159.0-fabric2-SNAPSHOT
CHAINCODE_VERSION=${SUBSTRATE_VERSION}
NETWORK_BUILDER_VERSION=2.159.0-fabric2-SNAPSHOT
MARTIN_VERSION=0.1.0-SNAPSHOT
