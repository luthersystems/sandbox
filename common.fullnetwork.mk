# Copyright © 2022 Luther Systems, Ltd. All rights reserved.

# common.fullnetwork.mk
#
# Portions of primary project makefile which are only used in the 'full' network,
# not in the in-memory network. Not used within Codespaces.

.PHONY: storage-up
storage-up:
	cd fabric && $(MAKE) up install init

.PHONY: storage-down
storage-down:
	-cd fabric && $(MAKE) down

.PHONY: service-up
service-up: api oracle storage-up
	./blockchain_compose.py local up -d

.PHONY: service-down
service-down:
	-./blockchain_compose.py local down

.PHONY: up
up: full-up

.PHONY: full-up
full-up: all storage-up service-up
	@

.PHONY: down
down: full-down

.PHONY: full-down
full-down: service-down storage-down
	@

.PHONY: init
init:
	-cd fabric && $(MAKE) init

.PHONY: upgrade
upgrade: all service-down init service-up
	@

# additional prerequisite assuming it exists
.PHONY: citest
citest: integrationcitest

# NOTE:  The `citest` target manages creating/destroying a compose network.  To
# run tests repeatedly execute the `integration` target directly.
.PHONY: integrationcitest
# The `down` wouldn't execute without this syntax
integrationcitest:
	$(MAKE) up
	$(MAKE) integration
	$(MAKE) down

.PHONY: integration
integration:
	cd tests && $(MAKE) test-docker
