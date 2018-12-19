#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

main() {
    # write config files for all *_CONFIG_JSON env vars
    ./configure.py

    # write crontab, mandatory
    echo "$CRONTAB" > crontab
    
    # rclone is optional
    echo "${CONFIG_RCLONE:-}" > rclone

    ./supercronic /app/crontab 2>&1
}

main "$@"
