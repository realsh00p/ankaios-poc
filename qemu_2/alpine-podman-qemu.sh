#!/usr/bin/env bash
set -euo pipefail

ARCH="${ARCH:-aarch64}"
ALPINE_BRANCH="${ALPINE_BRANCH:-latest-stable}"
MIRROR="${MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
IMAGE_DIR="${IMAGE_DIR:-/userdata/qemu_2}"
WORK_DIR="${WORK_DIR:-/userdata/qemu_2/work}"
IMAGE_SIZE_MIB="${IMAGE_SIZE_MIB:-512}"
IMAGE="${IMAGE:-$IMAGE_DIR/alpine-podman-${ARCH}.img}"
BOOT_DIR="${BOOT_DIR:-$IMAGE_DIR/boot}"
MOUNT_DIR="${MOUNT_DIR:-$WORK_DIR/mnt}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$WORK_DIR/downloads}"
CONTAINERS_HOST_DIR="${CONTAINERS_HOST_DIR:-$IMAGE_DIR/var/lib/containers}"
CONTAINERS_MOUNT_TAG="${CONTAINERS_MOUNT_TAG:-qemu_2_var_lib_containers}"
VIRTIOFSD="${VIRTIOFSD:-/usr/lib/qemu/virtiofsd}"
VIRTIOFSD_SOCKET="${VIRTIOFSD_SOCKET:-/run/qemu_2-containers.sock}"
ETC_CONTAINERS_HOST_DIR="${ETC_CONTAINERS_HOST_DIR:-$IMAGE_DIR/etc/containers}"
ETC_CONTAINERS_MOUNT_TAG="${ETC_CONTAINERS_MOUNT_TAG:-qemu_2_etc_containers}"
ETC_ANKAIOS_HOST_DIR="${ETC_ANKAIOS_HOST_DIR:-$IMAGE_DIR/etc/ankaios}"
ETC_ANKAIOS_MOUNT_TAG="${ETC_ANKAIOS_MOUNT_TAG:-qemu_2_etc_ankaios}"
VM_MEMORY="${VM_MEMORY:-192M}"
VM_CPUS="${VM_CPUS:-2}"
SSH_HOST_PORT="${SSH_HOST_PORT:-2202}"
ECHO_HOST_PORTS="${ECHO_HOST_PORTS:-}"
SSH_KEY="${SSH_KEY:-/userdata/qemu_2/alpine-podman_ed25519}"

log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root." >&2
        exit 1
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

require_tools() {
    for cmd in wget tar mount umount chroot truncate mkfs.ext4 rsync findmnt awk sed grep; do
        need_cmd "$cmd"
    done
    need_cmd qemu-system-aarch64
}

latest_minirootfs() {
    wget -qO- "$MIRROR/$ALPINE_BRANCH/releases/$ARCH/" |
        grep -o "alpine-minirootfs-[^\"]*-${ARCH}\\.tar\\.gz" |
        sort -Vu |
        tail -n 1
}

cleanup_mounts() {
    set +e
    if findmnt -rn "$MOUNT_DIR" >/dev/null 2>&1; then
        findmnt -Rrn -o TARGET "$MOUNT_DIR" | sort -r | while IFS= read -r mp; do
            umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
        done
    fi
}

chroot_run() {
    chroot "$MOUNT_DIR" /bin/sh -lc "$*"
}

extract_raw_arm64_image() {
    local src="$1"
    local dst="$2"
    local offset

    need_cmd perl
    need_cmd gzip
    offset="$(perl -0777 -ne 'if (/\x1f\x8b\x08/g) { print pos() - 3; exit }' "$src")"
    if [ -z "$offset" ]; then
        echo "Could not find gzip payload in $src" >&2
        exit 1
    fi

    rm -f "$dst"
    local gzip_log="$WORK_DIR/kernel-extract-gzip.log"
    set +e
    tail -c +"$((offset + 1))" "$src" | gzip -dc >"$dst" 2>"$gzip_log"
    local statuses=("${PIPESTATUS[@]}")
    set -e
    if [ "${statuses[0]}" -ne 0 ] || { [ "${statuses[1]}" -ne 0 ] && [ "${statuses[1]}" -ne 2 ]; }; then
        cat "$gzip_log" >&2
        echo "Failed to extract raw ARM64 Image from $src" >&2
        exit 1
    fi

    local magic
    magic="$(dd if="$dst" bs=1 skip=$((0x38)) count=4 2>/dev/null)"
    if [ "$magic" != "ARMd" ]; then
        echo "Extracted kernel is not a raw ARM64 Image: $dst" >&2
        exit 1
    fi
}

ensure_ssh_key() {
    if [ ! -f "$SSH_KEY" ]; then
        need_cmd ssh-keygen
        ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY" -C "alpine-podman-qemu"
    fi
}

install_ank_agent() {
    if [ ! -x /usr/local/bin/ank-agent ]; then
        log "Host /usr/local/bin/ank-agent not found; skipping Ankaios agent install"
        return
    fi

    mkdir -p "$MOUNT_DIR/usr/local/bin" "$MOUNT_DIR/etc/ankaios" "$MOUNT_DIR/etc/init.d" "$MOUNT_DIR/var/log/ankaios"
    cp /usr/local/bin/ank-agent "$MOUNT_DIR/usr/local/bin/ank-agent"
    chmod 755 "$MOUNT_DIR/usr/local/bin/ank-agent"

    cat >"$MOUNT_DIR/etc/ankaios/ank-agent.conf" <<'EOF'
version = 'v1'
name = 'qemu_2'
server_url = 'http://10.0.2.2:25551'
run_folder = '/run/ankaios/'
insecure = true
runtimes = [ 'podman' ]
tags = { 'host' = 'linaro', 'vm' = 'qemu_2', 'arch' = 'aarch64' }
EOF

    cat >"$MOUNT_DIR/etc/init.d/ank-agent" <<'EOF'
#!/sbin/openrc-run

name="Ankaios agent"
description="Ankaios agent"
command="/usr/local/bin/ank-agent"
command_args="--agent-config /etc/ankaios/ank-agent.conf"
command_background="yes"
pidfile="/run/ankaios/ank-agent.pid"
output_log="/var/log/ankaios/ank-agent.log"
error_log="/var/log/ankaios/ank-agent.log"
start_stop_daemon_args="--env RUST_LOG=info --make-pidfile"

depend() {
    need net
    after cgroups
}

start_pre() {
    mkdir -p /run/ankaios /var/log/ankaios
}
EOF
    chmod 755 "$MOUNT_DIR/etc/init.d/ank-agent"
}

write_guest_config() {
    cat >"$MOUNT_DIR/etc/hostname" <<'EOF'
alpine-podman
EOF

    cat >"$MOUNT_DIR/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

    cat >"$MOUNT_DIR/etc/fstab" <<EOF
/dev/vda / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /run tmpfs mode=0755,nosuid,nodev 0 0
$CONTAINERS_MOUNT_TAG /var/lib/containers virtiofs rw,defaults 0 0
$ETC_CONTAINERS_MOUNT_TAG /etc/containers 9p trans=virtio,version=9p2000.L,msize=262144,rw 0 0
$ETC_ANKAIOS_MOUNT_TAG /etc/ankaios 9p trans=virtio,version=9p2000.L,msize=262144,rw 0 0
EOF

    cat >"$MOUNT_DIR/etc/motd" <<'EOF'
Alpine Linux with Podman.

Try:
  podman info
  podman run --rm docker.io/library/alpine:latest uname -a
EOF

    mkdir -p "$MOUNT_DIR/root/.ssh" "$MOUNT_DIR/etc/containers" "$MOUNT_DIR/etc/modules-load.d"
    chmod 700 "$MOUNT_DIR/root/.ssh"

    ensure_ssh_key
    cat "$SSH_KEY.pub" >"$MOUNT_DIR/root/.ssh/authorized_keys"
    if [ -f /root/.ssh/authorized_keys ]; then
        cat /root/.ssh/authorized_keys >>"$MOUNT_DIR/root/.ssh/authorized_keys"
    fi
    chmod 600 "$MOUNT_DIR/root/.ssh/authorized_keys"

    cat >"$MOUNT_DIR/etc/modules-load.d/podman.conf" <<'EOF'
overlay
br_netfilter
tun
9p
9pnet
9pnet_virtio
fuse
virtiofs
EOF

    cat >"$MOUNT_DIR/etc/containers/storage.conf" <<'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
    rm -rf "$MOUNT_DIR/var/lib/containers/storage"
    mkdir -p "$MOUNT_DIR/var/lib/containers/storage" "$MOUNT_DIR/run/containers/storage"
}

build_image() {
    need_root
    require_tools
    mkdir -p "$IMAGE_DIR" "$BOOT_DIR" "$WORK_DIR" "$DOWNLOAD_DIR"
    mkdir -p "$CONTAINERS_HOST_DIR"
    mkdir -p "$ETC_CONTAINERS_HOST_DIR"
    mkdir -p "$ETC_ANKAIOS_HOST_DIR"
    cleanup_mounts
    trap cleanup_mounts EXIT

    local minirootfs
    minirootfs="$(latest_minirootfs)"
    if [ -z "$minirootfs" ]; then
        echo "Could not find Alpine minirootfs at $MIRROR/$ALPINE_BRANCH/releases/$ARCH/" >&2
        exit 1
    fi

    local minirootfs_path="$DOWNLOAD_DIR/$minirootfs"
    if [ ! -f "$minirootfs_path" ]; then
        log "Downloading $minirootfs"
        wget -O "$minirootfs_path" "$MIRROR/$ALPINE_BRANCH/releases/$ARCH/$minirootfs"
    fi

    log "Creating ${IMAGE_SIZE_MIB} MiB raw ext4 image at $IMAGE"
    rm -f "$IMAGE"
    truncate -s "${IMAGE_SIZE_MIB}M" "$IMAGE"
    mkfs.ext4 -F -L alpine-podman "$IMAGE" >/dev/null

    rm -rf "$MOUNT_DIR"
    mkdir -p "$MOUNT_DIR"
    mount -o loop "$IMAGE" "$MOUNT_DIR"

    log "Extracting Alpine minirootfs"
    tar -xzf "$minirootfs_path" -C "$MOUNT_DIR"
    cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"

    mount -t proc proc "$MOUNT_DIR/proc"
    mount -t sysfs sysfs "$MOUNT_DIR/sys"
    mount --rbind /dev "$MOUNT_DIR/dev"
    mount --make-rslave "$MOUNT_DIR/dev"

    local branch_path
    if [ "$ALPINE_BRANCH" = "latest-stable" ]; then
        branch_path="$(wget -qO- "$MIRROR/latest-stable/releases/$ARCH/latest-releases.yaml" |
            awk -F: '/^branch:/ { gsub(/[ "]/, "", $2); print $2; exit }')"
        branch_path="${branch_path:-latest-stable}"
    else
        branch_path="$ALPINE_BRANCH"
    fi

    cat >"$MOUNT_DIR/etc/apk/repositories" <<EOF
$MIRROR/$branch_path/main
$MIRROR/$branch_path/community
EOF

    log "Installing Alpine base, virt kernel, OpenRC, SSH, and Podman"
    chroot_run "apk update"
    chroot_run "apk add --no-cache alpine-base linux-virt openrc openssh-server iproute2 iptables e2fsprogs podman fuse-overlayfs slirp4netns crun"
    chroot_run "rm -rf /var/cache/apk/* /tmp/* /var/tmp/*"

    write_guest_config
    install_ank_agent

    chroot_run "rc-update add devfs sysinit"
    chroot_run "rc-update add procfs sysinit"
    chroot_run "rc-update add sysfs sysinit"
    chroot_run "rc-update add modules boot"
    chroot_run "rc-update add cgroups boot"
    chroot_run "rc-update add hostname boot"
    chroot_run "rc-update add bootmisc boot"
    chroot_run "rc-update add networking boot"
    chroot_run "rc-update add sshd default"
    chroot_run "rc-update add local default"
    if [ -x "$MOUNT_DIR/etc/init.d/ank-agent" ]; then
        chroot_run "rc-update add ank-agent default"
    fi
    chroot_run "ssh-keygen -A"
    chroot_run "passwd -d root >/dev/null"

    log "Copying boot kernel and initramfs to $BOOT_DIR"
    mkdir -p "$BOOT_DIR"
    cp "$MOUNT_DIR"/boot/vmlinuz-virt "$BOOT_DIR/vmlinuz-virt"
    cp "$MOUNT_DIR"/boot/initramfs-virt "$BOOT_DIR/initramfs-virt"
    extract_raw_arm64_image "$BOOT_DIR/vmlinuz-virt" "$BOOT_DIR/Image-virt"

    sync
    cleanup_mounts
    trap - EXIT

    local image_bytes
    image_bytes="$(stat -c %s "$IMAGE")"
    if [ "$image_bytes" -gt $((512 * 1024 * 1024)) ]; then
        echo "Image is larger than 512 MiB: $image_bytes bytes" >&2
        exit 1
    fi

    log "Build complete"
    status
}

run_vm() {
    require_tools
    if [ ! -f "$IMAGE" ] || [ ! -f "$BOOT_DIR/Image-virt" ] || [ ! -f "$BOOT_DIR/initramfs-virt" ]; then
        echo "Missing VM image or boot files. Run: $0 build" >&2
        exit 1
    fi

    if [ ! -x "$VIRTIOFSD" ]; then
        echo "Missing virtiofsd: $VIRTIOFSD" >&2
        exit 1
    fi
    rm -f "$VIRTIOFSD_SOCKET"
    "$VIRTIOFSD" --socket-path="$VIRTIOFSD_SOCKET" -o "source=$CONTAINERS_HOST_DIR" -o cache=always &
    local virtiofsd_pid=$!
    trap 'kill "$virtiofsd_pid" 2>/dev/null || true; rm -f "$VIRTIOFSD_SOCKET"' EXIT
    local i
    for i in $(seq 1 50); do
        [ -S "$VIRTIOFSD_SOCKET" ] && break
        sleep 0.1
    done

    local netdev="user,id=net0,hostfwd=tcp::${SSH_HOST_PORT}-:22"
    local port
    for port in $ECHO_HOST_PORTS; do
        netdev="${netdev},hostfwd=tcp::${port}-:${port}"
    done

    exec qemu-system-aarch64 \
        -machine virt,accel=kvm:tcg \
        -cpu host \
        -smp "$VM_CPUS" \
        -m "$VM_MEMORY" \
        -object "memory-backend-file,id=mem,size=$VM_MEMORY,mem-path=/dev/shm,share=on" \
        -numa node,memdev=mem \
        -nographic \
        -kernel "$BOOT_DIR/Image-virt" \
        -initrd "$BOOT_DIR/initramfs-virt" \
        -append "console=ttyAMA0 root=/dev/vda rw rootfstype=ext4 modules=ext4,virtio_blk,virtio_net" \
        -drive "if=none,file=$IMAGE,format=raw,id=hd0,cache=writeback" \
        -device virtio-blk-device,drive=hd0 \
        -chardev "socket,id=char_containers,path=$VIRTIOFSD_SOCKET" \
        -device "vhost-user-fs-pci,chardev=char_containers,tag=$CONTAINERS_MOUNT_TAG" \
        -virtfs "local,path=$ETC_CONTAINERS_HOST_DIR,mount_tag=$ETC_CONTAINERS_MOUNT_TAG,security_model=none,multidevs=remap" \
        -virtfs "local,path=$ETC_ANKAIOS_HOST_DIR,mount_tag=$ETC_ANKAIOS_MOUNT_TAG,security_model=none,multidevs=remap" \
        -netdev "$netdev" \
        -device virtio-net-device,netdev=net0
}

status() {
    echo "Script: $0"
    echo "Image:  $IMAGE"
    if [ -f "$IMAGE" ]; then
        du -h "$IMAGE"
        stat -c 'raw bytes: %s' "$IMAGE"
    else
        echo "image status: missing"
    fi
    echo "Boot:   $BOOT_DIR"
    if [ -f "$BOOT_DIR/Image-virt" ]; then
        du -h "$BOOT_DIR/Image-virt" "$BOOT_DIR/initramfs-virt"
    else
        echo "boot status: missing"
    fi
    echo "Share:  $CONTAINERS_HOST_DIR -> guest /var/lib/containers (virtiofs)"
    echo "        $ETC_CONTAINERS_HOST_DIR -> guest /etc/containers"
    echo "        $ETC_ANKAIOS_HOST_DIR -> guest /etc/ankaios"
    echo "Ports:  $ECHO_HOST_PORTS -> host and guest same ports"
    echo "Run:    $0 run"
    echo "SSH:    ssh -i $SSH_KEY -p $SSH_HOST_PORT root@127.0.0.1"
}

clean() {
    need_root
    cleanup_mounts
    rm -rf "$WORK_DIR"
    rm -f "$IMAGE"
    rm -f "$IMAGE_DIR/alpine-podman-efi.img"
    rm -rf "$BOOT_DIR"
    log "Removed build workspace, image, and boot files"
}

usage() {
    cat <<EOF
Usage: $0 [build|run|status|clean]

Environment overrides:
  IMAGE_DIR=$IMAGE_DIR
  IMAGE_SIZE_MIB=$IMAGE_SIZE_MIB
  CONTAINERS_HOST_DIR=$CONTAINERS_HOST_DIR
  VM_MEMORY=$VM_MEMORY
  VM_CPUS=$VM_CPUS
  SSH_HOST_PORT=$SSH_HOST_PORT
  ALPINE_BRANCH=$ALPINE_BRANCH
EOF
}

case "${1:-status}" in
    build) build_image ;;
    run) run_vm ;;
    status) status ;;
    clean) clean ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
