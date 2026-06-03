# Agent Notes

This repository is rooted at `/userdata` on host `linaro`.

## Rules

- Do not stage or commit VM images, kernels, initramfs files, SSH keys, Podman storage, downloads, or runtime data.
- Keep host `/etc` snapshots in `host/etc` as regular files, not symlinks.
- Run `scripts/sync-host-etc.sh` after changing `/etc/ankaios` or related systemd units.
- The Git pre-commit hook also runs that sync script and rejects staged symlinks under `host/etc`.

## QEMU Instances

- `qemu_1` uses SSH port `2201`.
- `qemu_2` uses SSH port `2202`.
- Both guests are Alpine arm64 VMs with Podman and Ankaios agents.
- Both use host-backed `/var/lib/containers`, `/etc/containers`, and `/etc/ankaios`.
- `/var/lib/containers` is mounted with virtiofs; `/etc/containers` and `/etc/ankaios` use 9p.

## Ankaios

- Host agent name: `linaro`
- VM agent names: `qemu_1`, `qemu_2`
- Host server startup manifest: `/etc/ankaios/state.yaml`
- CLI normally needs insecure mode: `ank -k ...`

Current workload split:

- `qemu_1`: `echo-server-40101`, `echo-server-40102`, `echo-server-40103`
- `qemu_2`: `echo-client-40101`, `echo-client-40102`, `echo-client-40103`

## Verification

Use these checks after changes:

```sh
ank -k get agents
ank -k get workloads
systemctl is-active qemu_1.service qemu_2.service ank-server.service ank-agent.service
git status --short --ignored
git diff --cached --name-only | grep -E '(\.img$|Image-|vmlinuz-|initramfs-|_ed25519|/storage/|/downloads/|\.tar\.gz$)' || true
git ls-files -s host/etc | awk '$1 == 120000 {print}'
```

The last two commands should print nothing.
