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
    
    # optional configuration
    echo "${CONFIG_RCLONE:-}" > rclone
    echo "${TUNNEL_SSH_KEY:-}" > key
    chmod 600 key

    ./supercronic /app/crontab 2>&1
}

main "$@"
