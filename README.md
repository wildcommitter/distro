# fedora-niri-zfs — custom bootc image

A Fedora **bootc** (image-mode / OSTree) custom OS image with:

- **KVM / libvirtd / virt-manager / virt-install** (full local virtualization)
- **niri** scrollable-tiling Wayland compositor + **noctalia-shell** (Quickshell)
- **SDDM** graphical login
- **OpenZFS** for **two data pools** (`tank0`, `tank1`) from two disks
- Root filesystem stays **btrfs** (bootc default) — ZFS is data-only

## Important: "Ignition" does not apply here

Ignition is a **Fedora CoreOS-only** mechanism. It does not run on bootc /
Atomic images. You asked for FCOS + Ignition + a noctalia desktop — those two
requirements are mutually exclusive in practice, because stock FCOS has no
graphical stack and layering a full Wayland desktop onto it via rpm-ostree is
unsupported and brittle.

The desktop-capable equivalent of "provision at install" on bootc is:
1. **Image-time** config — everything baked into the Containerfile + `files/`.
2. **First-boot** systemd units — here, `zfs-import-pools.service`.
3. (Optional) cloud-init or Anaconda kickstart at install if you need
   per-machine values.

If you *must* keep literal Ignition, you cannot have noctalia on the same
image; you'd run plain FCOS and drop the desktop.

## ZFS strategy (why it's safe)

- ZFS is **not in the Fedora kernel** and source akmod builds are broken as
  root on F44+. We therefore **copy prebuilt, signed ZFS akmod RPMs** from the
  Universal Blue `akmods-zfs` cache (`ghcr.io/ublue-os/akmods-zfs:main-42`),
  matched to the baked kernel. Keep `FEDORA_MAJOR`, the base image tag, and
  `AKMODS_TAG` on the **same Fedora release**, or the kmod won't match the
  kernel and ZFS won't load.
- `zfs-import-pools.service` only ever **imports** pools by name. It never
  creates them, so a boot can't wipe a disk.
- You create the pools **once, by hand**, with
  `/usr/libexec/zfs-create-pools.sh`, passing stable `/dev/disk/by-id/...`
  paths. After that they auto-import every boot via the cachefile.

> SecureBoot: the uBlue kmods are signed with the uBlue key. On a SecureBoot
> machine you must enroll that key (MOK) or the module load will be blocked.
> `ublue-os-akmods-addons` ships the key; enroll it with `mokutil` or disable
> SecureBoot for testing.

## Layout

```
Containerfile                                  # the image definition
build/build.sh                                 # podman build + BIB instructions
files/
  usr/lib/systemd/system/zfs-import-pools.service
  usr/libexec/zfs-create-pools.sh              # one-time manual pool creation
  usr/share/wayland-sessions/niri.desktop      # SDDM session entry
  etc/sddm.conf.d/10-wayland.conf
  etc/polkit-1/rules.d/50-libvirt.rules        # passwordless libvirt for group
  etc/skel/.config/niri/config.kdl             # niri config (spawns noctalia)
```

## Build

```bash
cd fedora-niri-zfs
./build/build.sh                # builds localhost/fedora-niri-zfs:latest
```

Then turn it into an installable image (raw/iso) with
`bootc-image-builder` — see the printed instructions, or install in place with
`bootc install to-disk`.

## First boot

1. Log in via SDDM, pick the **"niri (noctalia)"** session.
2. Add your user to the `libvirt` group: `sudo usermod -aG libvirt $USER`,
   re-login. virt-manager then needs no password (polkit rule).
3. Create the two ZFS pools **once**:
   ```bash
   sudo /usr/libexec/zfs-create-pools.sh \
       /dev/disk/by-id/<disk-for-tank0> \
       /dev/disk/by-id/<disk-for-tank1>
   ```
   Subsequent boots auto-import them.

## Things you will likely need to tune

- **COPR names**: `yalter/niri`, `errornointernet/quickshell` — verify these
  still exist / are the ones you want at build time; COPRs move.
- **noctalia launch command**: noctalia is iterating fast. Confirm the exact
  `qs`/`quickshell` invocation and IPC verbs (`config.kdl` `Mod+D` binding)
  against the current noctalia README; adjust the `-c` path / ipc call.
- **Keyboard layout** is set to `es` in `config.kdl` — change if needed.
- **Pool names** `tank0`/`tank1` appear in the systemd unit and helper script.
- **SecureBoot / MOK** enrollment as noted above.
