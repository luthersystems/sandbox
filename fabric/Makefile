PROJECT_REL_DIR=..

PHYLA_CCAAS=sandbox

GATEWAYS=1.shiroclient_gw_sandbox.sandbox

GENERATE_OPTS=--org-count 1 --peer-count 1

DOCKER_CHOWN_USER=65534:65534

include ${PROJECT_REL_DIR}/common.fabric.mk

${PHYLUM_PATH}: make-C/../phylum

fnb-up: channel-artifacts/genesis.block
