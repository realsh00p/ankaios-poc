#!/bin/sh
set -eu

state_file="${1:-/userdata/host/etc/rollback-workload/previous-state.yaml}"
poll_interval="${2:-5}"
startup_grace="${3:-30}"

case "$poll_interval" in
    ''|*[!0-9]*)
        echo "poll interval must be a positive integer number of seconds" >&2
        exit 2
        ;;
    0)
        echo "poll interval must be greater than zero" >&2
        exit 2
        ;;
esac

case "$startup_grace" in
    ''|*[!0-9]*)
        echo "startup grace must be a non-negative integer number of seconds" >&2
        exit 2
        ;;
esac

host_test() {
    nsenter -t 1 -m -u -i -n -p -r -- test "$@"
}

host_ank() {
    nsenter -t 1 -m -u -i -n -p -r -- /usr/local/bin/ank "$@"
}

failed_workloads() {
    host_ank -k get state workloadStates -o json \
        | jq -r '
            .workloadStates
            | to_entries[]
            | .key as $agent
            | .value
            | to_entries[]
            | select(.key != "rollback")
            | .key as $workload
            | .value
            | to_entries[]
            | select(
                .value.state == "Failed"
                or (.value.state == "Pending" and .value.subState == "StartingFailed")
              )
            | "\($agent)/\($workload): \(.value.state)(\(.value.subState)) \(.value.additionalInfo)"
        '
}

if ! host_test -r "$state_file"; then
    echo "rollback state file is not readable on the host: $state_file" >&2
    exit 2
fi

if [ "$startup_grace" -gt 0 ]; then
    echo "Waiting ${startup_grace}s before monitoring for failed workloads"
    sleep "$startup_grace"
fi

echo "Monitoring workloads; rollback state: $state_file"

while :; do
    failed="$(failed_workloads)"
    if [ -n "$failed" ]; then
        echo "Detected failed workload state:"
        echo "$failed"
        echo "Applying rollback state from $state_file"
        host_ank -k apply "$state_file"
        exit 0
    fi
    sleep "$poll_interval"
done
