PROJECT_REL_DIR=..

PHYLA_CCAAS=sandbox

GATEWAYS=1.shiroclient_gw_sandbox.sandbox
CONNECTORHUBS=1.connectorhub_sandbox.sandbox

GENERATE_OPTS=--org-count 1 --peer-count 1

include ${PROJECT_REL_DIR}/common.fabric.mk

${PHYLUM_PATH}: make-C/../phylum

# fnb-smoke starts and stops the local Fabric network with the builder, as the
# CI job fabric-network does. It checks that the files the builder writes
# belong to you, since the builder runs as your user, not root.
.PHONY: fnb-smoke
fnb-smoke: generate-chaincodes
	$(MAKE) fnb-up
	test -O crypto-config
	$(MAKE) fnb-down
