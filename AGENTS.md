# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

`fedora-niri-zfs` — a custom Fedora **bootc** (image-mode/OSTree) Linux
distro: KVM/libvirt/virt-manager, the **niri** Wayland compositor +
**noctalia-shell** (Quickshell-based), SDDM graphical login, and **OpenZFS**
for two data pools (root filesystem stays btrfs — ZFS is data-only). The
entire image is defined by `Containerfile`; `files/` is overlaid onto the
image as a config tree (systemd units, niri config, session files).

## Key files

- `Containerfile` — the whole image definition, single source of truth.
  `FEDORA_MAJOR` and `AKMODS_KERNEL` ARGs near the top control which Fedora
  release and which uBlue `akmods-zfs` flavor (`coreos-stable`,
  `coreos-testing`, `longterm-*`, `centos-*`) get used. Both the base image
  and the akmods image are derived from these two ARGs — don't edit the
  `FROM` lines directly, bump the ARGs.
- `Justfile` — convenience recipes: `just build`, `just build-ghcr`,
  `just push`, `just raw`, `just iso`, `just install-to-disk DISK=...`,
  `just zfs-create DISK0=... DISK1=...`. Run `just --list` for all of them.
- `build/build.sh` — plain `podman build` + printed bootc-image-builder
  instructions. Older/simpler than the Justfile; both build the same image.
- `files/` — overlaid onto `/` via `COPY files/ /` in the Containerfile.
  Note: there is also a stray **empty** `{files` directory at repo root —
  an artifact, not referenced by anything; safe to ignore or delete.
- `.github/workflows/build.yml` — CI: builds + pushes to GHCR on push to
  `main`, on a weekly cron (Mon 05:00 UTC), and on manual dispatch. The
  weekly cron exists specifically to re-sync the ZFS kmod against
  kernel/akmods drift — see `.agent/memory/akmods-kernel-skew.md`.
- `README.md` — user-facing doc. **Can lag the Containerfile** after an ARG
  bump (e.g. it may still describe an old default). Treat the Containerfile
  as ground truth over the README when they disagree, and flag the drift
  to the user rather than silently trusting either one.
- `iso/luks-btrfs.config.toml.tmpl` — bootc-image-builder kickstart template
  for the LUKS2-encrypted btrfs root. `just iso-encrypted PASSPHRASE=...`
  materializes it under `./output` (gitignored) — never fill in
  `@@PASSPHRASE@@` in the committed template. See
  `.agent/memory/full-disk-encryption.md` for why this path was chosen over
  bootc's native `--block-setup tpm2-luks`.

## Local memory

`.agent/memory/` holds notes on non-obvious project behavior discovered
while working in this repo — registry/kernel version skew, upstream image
layout quirks, package-naming gotchas, etc. Read it before re-deriving
something that's already been debugged once; add to it when you discover
something surprising that isn't obvious from reading the code itself.

## Verifying changes to the Containerfile

There's no CI step faster than just building it:

```bash
podman build -t localhost/fedora-niri-zfs:latest .
```

To check whether the ZFS kmod actually matches the baked kernel (the most
common failure mode — see `.agent/memory/akmods-kernel-skew.md`):

```bash
podman run --rm localhost/fedora-niri-zfs:latest sh -c \
  "rpm -q kernel zfs kmod-zfs; find /usr/lib/modules -iname 'zfs.ko*'"
```

If the kernel version in the `zfs.ko*` path doesn't match `rpm -q kernel`,
the module won't load at boot. That's a real possibility this project
currently tolerates (the weekly cron is what's supposed to close the gap) —
it is not, by itself, a bug to chase by adding more fallback logic.

## Conventions

- Only bump `FEDORA_MAJOR` / `AKMODS_KERNEL` together, at the top of the
  Containerfile — that's the documented single source of truth.
- Don't swallow errors (`|| true`) around steps that are actually required
  for the build to mean anything (e.g. quickshell's COPR enable, since
  quickshell isn't in Fedora's repos). Reserve `|| true` for steps that are
  genuinely optional (e.g. niri's COPR enable — niri already ships in
  Fedora's main repo, so the COPR is just a fallback for older releases).
- `dnf5` requires the `dnf5-plugins` package installed before
  `dnf copr enable` works at all.
- Before changing which akmods flavor/release is tracked, check actual
  freshness and kernel match (don't assume same Fedora release number means
  matching kernel build) — see `.agent/memory/akmods-kernel-skew.md` for how.
