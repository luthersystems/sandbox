# Local Fabric Network

This directory contains the configuration to run a fabric network locally and
test your application in a realistic setup.

## Initial Setup

In order to run the network locally you need to generate cryptographic assets
(i.e. certs and private keys) for the various components in a fabric network:
the peers, orderers, and users.

    make generate-assets

This command only needs to be run once, assets will be placed in the
crypto-config/ and channel-artifacts/ directories.  These will persist, ignored
by git, until you run `make clean` or remove the directories.

## Running the network

To start all the fabric network components and install your application in the
network run `make all`, or simply `make` in this directory.

    make all
