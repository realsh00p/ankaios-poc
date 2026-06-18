#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
overlay_root="/home/linaro/ota_overlay"

copy_file() {
    src="$1"
    dst="$repo_root/$2"
    mode="${3:-0644}"

    if [ ! -f "$src" ]; then
        echo "missing overlay file: $src" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cp -L "$src" "$dst"
    chmod "$mode" "$dst"
}

copy_file "$overlay_root/etc/ankaios/ank.conf" ota_overlay/etc/ankaios/ank.conf
copy_file "$overlay_root/etc/ankaios/ank-agent.conf" ota_overlay/etc/ankaios/ank-agent.conf
copy_file "$overlay_root/etc/ankaios/ank-server.conf" ota_overlay/etc/ankaios/ank-server.conf
copy_file "$overlay_root/etc/ankaios/state.yaml" ota_overlay/etc/ankaios/state.yaml

copy_file "$overlay_root/etc/symphony-api.json" ota_overlay/etc/symphony-api.json
copy_file "$overlay_root/etc/symphony/targets/linaro-ankaios.json" ota_overlay/etc/symphony/targets/linaro-ankaios.json

copy_file "$overlay_root/etc/systemd/system/ank-agent.service" ota_overlay/etc/systemd/system/ank-agent.service
copy_file "$overlay_root/etc/systemd/system/ank-server.service" ota_overlay/etc/systemd/system/ank-server.service
copy_file "$overlay_root/etc/systemd/system/qemu_1.service" ota_overlay/etc/systemd/system/qemu_1.service
copy_file "$overlay_root/etc/systemd/system/qemu_2.service" ota_overlay/etc/systemd/system/qemu_2.service
copy_file "$overlay_root/etc/systemd/system/opensovd-gateway.service" ota_overlay/etc/systemd/system/opensovd-gateway.service
copy_file "$overlay_root/etc/systemd/system/ankaios-rollback.service" ota_overlay/etc/systemd/system/ankaios-rollback.service
copy_file "$overlay_root/etc/systemd/system/ankaios-rollback-check.service" ota_overlay/etc/systemd/system/ankaios-rollback-check.service
copy_file "$overlay_root/etc/systemd/system/ankaios-rollback-check.timer" ota_overlay/etc/systemd/system/ankaios-rollback-check.timer
copy_file "$overlay_root/etc/systemd/system/ota-overlay-systemd-loader.service" ota_overlay/etc/systemd/system/ota-overlay-systemd-loader.service

copy_file "$overlay_root/etc/rollback-workload/update" ota_overlay/etc/rollback-workload/update 0755
copy_file "$overlay_root/etc/rollback-workload/previous-state.yaml" ota_overlay/etc/rollback-workload/previous-state.yaml
copy_file "$overlay_root/usr/local/sbin/ankaios-rollback-check" ota_overlay/usr/local/sbin/ankaios-rollback-check 0755
copy_file "$overlay_root/lib/systemd/system-generators/ota-overlay-systemd-generator" ota_overlay/lib/systemd/system-generators/ota-overlay-systemd-generator 0755

old_update="apply-with-"
old_update="${old_update}rollback.sh"
rm -f "$repo_root/ota_overlay/etc/rollback-workload/$old_update"
git rm --cached --ignore-unmatch "ota_overlay/etc/rollback-workload/$old_update" >/dev/null
git rm -r --cached --ignore-unmatch host >/dev/null
rm -rf "$repo_root/host"
git add ota_overlay scripts/sync-host-etc.sh .gitignore
