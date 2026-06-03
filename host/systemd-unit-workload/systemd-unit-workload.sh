#!/bin/sh
set -eu

unit="${1:-}"
interval="${2:-5}"

if [ -z "$unit" ]; then
    echo "usage: systemd-unit-workload <unit> [poll_interval_seconds]" >&2
    exit 2
fi

case "$interval" in
    ''|*[!0-9]*)
        echo "poll interval must be a positive integer number of seconds" >&2
        exit 2
        ;;
    0)
        echo "poll interval must be greater than zero" >&2
        exit 2
        ;;
esac

host_systemctl() {
    nsenter -t 1 -m -u -i -n -p -r -- /bin/systemctl "$@"
}

stop_unit() {
    trap - TERM INT
    echo "Stopping $unit"
    host_systemctl stop "$unit"
    exit 0
}

trap stop_unit TERM INT

echo "Starting $unit"
host_systemctl start "$unit"

while :; do
    if ! host_systemctl is-active --quiet "$unit"; then
        echo "$unit is not active" >&2
        exit 1
    fi
    sleep "$interval"
done
