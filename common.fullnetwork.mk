.PHONY: storage-up
storage-up:
	cd fabric && $(MAKE) up install init

.PHONY: storage-down
storage-down:
	-cd fabric && $(MAKE) down

.PHONY: service-up
service-up: api oracle
	./${PROJECT}_compose.py local up -d

.PHONY: service-down
service-down:
	-./${PROJECT}_compose.py local down

.PHONY: up
up: all service-down storage-down storage-up service-up
	@

.PHONY: down
down: service-down storage-down
	@

.PHONY: init
init:
	-cd fabric && $(MAKE) init

.PHONY: upgrade
upgrade: all service-down init service-up
	@
