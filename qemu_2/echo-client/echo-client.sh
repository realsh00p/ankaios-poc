#!/bin/sh
set -eu

endpoint="${1:-}"
interval="${2:-10}"

if [ -z "$endpoint" ]; then
    echo "usage: echo-client <endpoint> [interval_seconds]" >&2
    exit 2
fi

case "$interval" in
    ''|*[!0-9]*)
        echo "interval must be a positive integer number of seconds" >&2
        exit 2
        ;;
    0)
        echo "interval must be greater than zero" >&2
        exit 2
        ;;
esac

while :; do
    curl --fail --silent --show-error --location --max-time 10 "$endpoint" >/dev/null
    sleep "$interval"
done
