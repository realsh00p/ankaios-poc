#!/bin/sh
set -eu

incoming_state="${1:-}"
previous_state="${PREVIOUS_STATE:-/home/linaro/ota_overlay/etc/rollback-workload/previous-state.yaml}"
backup_dir="${ROLLBACK_BACKUP_DIR:-/home/linaro/ota_overlay/etc/rollback-workload/history}"
startup_state="${STARTUP_STATE:-/home/linaro/ota_overlay/etc/ankaios/state.yaml}"
repo_startup_state="${REPO_STARTUP_STATE:-/home/linaro/ota_overlay/etc/ankaios/state.yaml}"
ank="${ANK:-/usr/local/bin/ank}"

usage() {
    echo "usage: apply-with-rollback <incoming-state.yaml>" >&2
}

if [ -z "$incoming_state" ]; then
    usage
    exit 2
fi

if [ ! -r "$incoming_state" ]; then
    echo "incoming state is not readable: $incoming_state" >&2
    exit 2
fi

if ! grep -q '^apiVersion:' "$incoming_state" || ! grep -q '^workloads:' "$incoming_state"; then
    echo "incoming state must be a full Ankaios manifest with apiVersion and workloads" >&2
    exit 2
fi

if [ ! -x "$ank" ]; then
    echo "ank CLI is not executable: $ank" >&2
    exit 2
fi

mkdir -p "$backup_dir" "$(dirname "$previous_state")"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp_current="$(mktemp)"
tmp_previous="$(mktemp)"
cleanup() {
    rm -f "$tmp_current" "$tmp_previous"
}
trap cleanup EXIT

"$ank" -k get state desiredState -o yaml > "$tmp_current"

awk '
    NR == 1 && $0 == "desiredState:" { next }
    {
        if (substr($0, 1, 2) == "  ") {
            print substr($0, 3)
        } else {
            print
        }
    }
' "$tmp_current" > "$tmp_previous"

if ! grep -q '^apiVersion:' "$tmp_previous" || ! grep -q '^workloads:' "$tmp_previous"; then
    echo "refusing to overwrite previous state: current desiredState did not normalize to an Ankaios manifest" >&2
    exit 1
fi

if [ -e "$previous_state" ]; then
    cp -f "$previous_state" "$backup_dir/previous-state-before-$timestamp.yaml"
fi

cp -f "$tmp_previous" "$backup_dir/current-state-before-$timestamp.yaml"
cp -f "$tmp_previous" "$previous_state.tmp"
mv -f "$previous_state.tmp" "$previous_state"

echo "Saved previous state to $previous_state"
echo "Applying incoming state from $incoming_state"
"$ank" -k apply "$incoming_state"

cp -f "$incoming_state" "$startup_state.tmp"
mv -f "$startup_state.tmp" "$startup_state"

if [ -d "$(dirname "$repo_startup_state")" ]; then
    cp -f "$incoming_state" "$repo_startup_state.tmp"
    mv -f "$repo_startup_state.tmp" "$repo_startup_state"
fi

echo "Persisted incoming state to $startup_state"
