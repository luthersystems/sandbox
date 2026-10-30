# Copyright © 2021 Luther Systems, Ltd. All right reserved.

PHYLUM_NAME=${PROJECT}.zip

PROJECT_REL_DIR=..
include ${PROJECT_REL_DIR}/common.phylum.mk

# flows/ holds the state graph of each defflow, drawn by shirotester from the
# code. The test target checks it, so a change to a flow that is not
# reflected in the committed graph fails the build. Run make flow-graph to
# draw it again after you change a flow.
.PHONY: flow-graph
flow-graph:
	${DOCKER_RUN} --user ${DOCKER_USER} -v ${PHYLUMDIR}:/tmp -w /tmp ${SHIROTESTER_IMAGE}:${SHIROTESTER_VERSION} \
		flow-graph --format mermaid --out flows .

.PHONY: flow-graph-check
flow-graph-check:
	${SHIRO_TEST} flow-graph --format mermaid --check flows .

test: flow-graph-check
