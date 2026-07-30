.PHONY: build release test test-down

VERSION=1.1

build:
	docker build . -t meshcloud/dumptruck

# Full backup -> encrypt -> upload -> retention -> restore cycle against real
# MariaDB and PostgreSQL containers. Same entrypoint CI uses.
test:
	docker build . -t dumptruck:integration
	docker compose -f test/docker-compose.yml run --rm tests; \
		status=$$?; \
		docker compose -f test/docker-compose.yml down -v --remove-orphans >/dev/null 2>&1; \
		exit $$status

test-down:
	docker compose -f test/docker-compose.yml down -v --remove-orphans

release: build
	git tag $(VERSION)
	docker tag meshcloud/dumptruck meshcloud/dumptruck:$(VERSION)
	docker push meshcloud/dumptruck 
	docker push meshcloud/dumptruck:$(VERSION)