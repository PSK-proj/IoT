SHELL := /bin/bash

.PHONY: up down rebuild logs ps clean certs certs-mtls certs-clean

up:
	docker compose up -d --build

down:
	docker compose down

rebuild:
	docker compose build --no-cache

logs:
	docker compose logs -f --tail=200
	docker logs -f broker

ps:
	docker compose ps

clean:
	docker compose down -v
	rm -rf broker_data broker_log pcap/*.pcap pcap/*.pcapng certs/*.srl || true

certs:
	docker compose --profile tools -f docker-compose.yml -f docker-compose.tools.yml run --rm certgen

certs-mtls:
	docker compose --profile tools -f docker-compose.yml -f docker-compose.tools.yml run --rm -e CLIENT_CN_LIST="$(CLIENTS)" certgen

certs-clean:
	rm -f certs/*.crt certs/*.key certs/*.srl certs/openssl.server.cnf || true
