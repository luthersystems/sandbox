# Copyright © 2022 Luther Systems, Ltd. All rights reserved.

.DEFAULT_GOAL := up-clean

.PHONY: up
up: down
	./check_for_peers.sh
	docker-compose up -d

.PHONY: watch
watch: up
	docker logs explorerdb.luther.systems
	docker logs explorer.luther.systems

.PHONY: up-clean
up-clean: #this needs to be recipe, not a prereq, for ordering purposes
	make down-clean
	make up

.PHONY: down
down:
	docker-compose down

.PHONY: down-clean
down-clean:
	docker-compose down -v
