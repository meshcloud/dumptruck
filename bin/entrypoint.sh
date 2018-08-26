#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

main() {
	echo "$CRONTAB" > crontab
	echo "$CONFIG_JSON" > config.json

	./supercronic crontab 2>&1
}

main "$@"
