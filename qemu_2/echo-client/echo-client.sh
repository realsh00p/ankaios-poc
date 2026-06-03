#!/bin/sh
set -eu

endpoint="${1:-}"
interval="${2:-10}"
startup_timeout="${3:-180}"

if [ -z "$endpoint" ]; then
    echo "usage: echo-client <endpoint> [interval_seconds] [startup_timeout_seconds]" >&2
    exit 2
fi

validate_positive_integer() {
    name="$1"
    value="$2"

    case "$value" in
        ''|*[!0-9]*)
            echo "$name must be a positive integer number of seconds" >&2
            exit 2
            ;;
        0)
            echo "$name must be greater than zero" >&2
            exit 2
            ;;
    esac
}

validate_positive_integer "interval" "$interval"
validate_positive_integer "startup timeout" "$startup_timeout"

curl_endpoint() {
    curl --fail --silent --show-error --location --max-time 10 "$endpoint" >/dev/null
}

echo "Waiting up to ${startup_timeout}s for $endpoint"
deadline=$(( $(date +%s) + startup_timeout ))

while ! curl_endpoint; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
        echo "Endpoint did not become ready within ${startup_timeout}s: $endpoint" >&2
        exit 1
    fi
    sleep "$interval"
done

echo "Endpoint ready: $endpoint"

while :; do
    sleep "$interval"
    curl_endpoint
done
