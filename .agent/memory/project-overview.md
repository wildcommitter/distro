# Project overview

`fedora-niri-zfs` is a custom Fedora **bootc** (image-mode/OSTree) Linux
distro, built on the Universal Blue (uBlue) model. It layers ZFS support
onto Fedora bootc — something uBlue's own base images don't ship — plus a
niri/noctalia Wayland desktop and a full KVM/libvirt virtualization stack.
Root filesystem stays **btrfs**; ZFS is used only for two data pools
(`tank0`, `tank1`), imported (never created) at boot by
`zfs-import-pools.service`.

**Why this matters for agents:** this is an OS image build pipeline, not a
regular application repo. Changes to `Containerfile` / `files/` describe
what ends up baked into a bootable disk image — there's no "deploy and
roll back easily" safety net once an image is installed to a real disk via
`bootc install to-disk` (that's destructive and irreversible by design, see
`Justfile`'s `install-to-disk` recipe). Treat that recipe and
`zfs-create-pools.sh` as genuinely dangerous; everything else (building,
pushing, linting) is safe to iterate on freely.

Ignition (a Fedora CoreOS-only first-boot mechanism) does **not** apply to
bootc/Atomic images — first-boot provisioning here is done via systemd
units baked into the image instead. See the Containerfile's header comment
and `README.md`'s "Important: Ignition does not apply here" section if this
comes up — it's a real source of confusion since FCOS and bootc look
similar but aren't interchangeable.
