PROJECT_REL_DIR=..

PHYLA_CCAAS=sandbox

DOCKER_FABRIC_OPTS= \
	-v "${LICENSE_FILE_ROOT}:/tmp/license.yaml:ro" \
	-e SHIROCLIENT_CLIENT_LICENSE_FILE=/tmp/license.yaml

GATEWAYS=1.shiroclient_gw_sandbox.sandbox

GENERATE_OPTS=--org-count 1 --peer-count 1

include ${PROJECT_REL_DIR}/common.fabric.mk

${PHYLUM_PATH}: make-C/../phylum

${CC_PATH}: ${PRESIGNED_PATH}
	${PROJECT_REL_DIR}/scripts/obtain-cc.sh
	touch $@

.PHONY:
download: ${CC_PATH}
	@
