# userdata QEMU and Ankaios Lab

This repository tracks the text configuration for the `linaro` host QEMU/Ankaios setup under `/userdata`.

Binary artifacts and runtime state are intentionally not tracked. VM disk images, kernels, initramfs files, SSH keys, Podman storage, downloads, and recovery data are ignored by `.gitignore`.

## Layout

- `qemu_1/` - Alpine arm64 VM running Podman and the `qemu_1` Ankaios agent.
- `qemu_2/` - Alpine arm64 VM running Podman and the `qemu_2` Ankaios agent.
- `qemu_2/echo-client/` - small Alpine/curl container source used by the `qemu_2` workloads.
- `host/etc/` - regular-file snapshots of related host `/etc` files.
- `scripts/sync-host-etc.sh` - refreshes `host/etc` from the real host `/etc` files.

## Services

The host systemd services are:

- `ank-server.service`
- `ank-agent.service`
- `qemu_1.service`
- `qemu_2.service`

The tracked host service/config snapshots live under `host/etc`.

## Ports

- `qemu_1` SSH: host port `2201`
- `qemu_2` SSH: host port `2202`
- `qemu_1` echo servers: host and VM ports `40101`, `40102`, `40103`

## Ankaios Workloads

Current desired state is stored in `/etc/ankaios/state.yaml` and tracked as `host/etc/ankaios/state.yaml`.

- `echo-server-40101`, `echo-server-40102`, `echo-server-40103` run on agent `qemu_1`.
- `echo-client-40101`, `echo-client-40102`, `echo-client-40103` run on agent `qemu_2`.

The echo clients call:

- `http://192.168.10.240:40101`
- `http://192.168.10.240:40102`
- `http://192.168.10.240:40103`

## Useful Commands

```sh
systemctl status qemu_1.service qemu_2.service
ank -k get agents
ank -k get workloads
ssh -i /userdata/qemu_1/alpine-podman_ed25519 -p 2201 root@127.0.0.1
ssh -i /userdata/qemu_2/alpine-podman_ed25519 -p 2202 root@127.0.0.1
```

Build the `qemu_2` echo client image inside the VM:

```sh
cd /userdata/qemu_2/echo-client
tar cf - Dockerfile echo-client.sh |
  ssh -i /userdata/qemu_2/alpine-podman_ed25519 -p 2202 root@127.0.0.1 \
    'rm -rf /root/echo-client && mkdir -p /root/echo-client && cd /root/echo-client && tar xf -'
ssh -i /userdata/qemu_2/alpine-podman_ed25519 -p 2202 root@127.0.0.1 \
  'cd /root/echo-client && podman build -t localhost/echo-client:latest .'
```

## Git Notes

Before committing, the pre-commit hook runs `scripts/sync-host-etc.sh` so host `/etc` snapshots are stored as regular files, not symlinks.

Run the sync manually with:

```sh
cd /userdata
scripts/sync-host-etc.sh
```
