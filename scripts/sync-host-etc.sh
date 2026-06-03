#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"

copy_file() {
    src="$1"
    dst="$repo_root/$2"

    if [ ! -f "$src" ]; then
        echo "missing host config: $src" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cp -L "$src" "$dst"
    chmod 0644 "$dst"
}

copy_file /etc/ankaios/ank.conf host/etc/ankaios/ank.conf
copy_file /etc/ankaios/ank-agent.conf host/etc/ankaios/ank-agent.conf
copy_file /etc/ankaios/ank-server.conf host/etc/ankaios/ank-server.conf
copy_file /etc/ankaios/state.yaml host/etc/ankaios/state.yaml

copy_file /etc/systemd/system/ank-agent.service host/etc/systemd/system/ank-agent.service
copy_file /etc/systemd/system/ank-server.service host/etc/systemd/system/ank-server.service
copy_file /etc/systemd/system/qemu_1.service host/etc/systemd/system/qemu_1.service
copy_file /etc/systemd/system/qemu_2.service host/etc/systemd/system/qemu_2.service

git add host/etc
