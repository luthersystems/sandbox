# Copyright © 2022 Luther Systems, Ltd. All right reserved.

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
up-clean: down-clean
	make up

.PHONY: down
down:
	- docker-compose down

.PHONY: down-clean
down-clean:
	docker-compose down -v
