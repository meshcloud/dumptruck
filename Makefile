.PHONY: build release test test-down

VERSION=v1.4.1

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

# Images are built and pushed to ghcr.io by .github/workflows/build.yml, which
# triggers on v*.*.* tags. Pushing the tag is the whole release.
release: test
	git tag -a $(VERSION) -m "$(VERSION)"
	git push origin $(VERSION)