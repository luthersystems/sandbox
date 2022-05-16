# Copyright © 2022 Luther Systems, Ltd. All rights reserved.

.DEFAULT_GOAL := up-clean

.PHONY: up
up: down
	docker-compose up -d

.PHONY: watch
watch: up
	docker logs explorerdb.luther.systems
	docker logs explorer.luther.systems

.PHONY: up-clean
up-clean: down-clean
	docker-compose up -d

.PHONY: down
down:
	docker-compose down

.PHONY: down-clean
down-clean:
	docker-compose down -v
