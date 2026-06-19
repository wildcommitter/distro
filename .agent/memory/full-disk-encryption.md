# Full-disk encryption: LUKS2 btrfs root, FIDO2 + SSH unlock

## What's actually built here

- Root stays **btrfs**, now optionally LUKS2-encrypted, created at **install
  time** via an Anaconda kickstart (`iso/luks-btrfs.config.toml.tmpl` +
  `just iso-encrypted`) — not by the Containerfile. The image only carries
  the unlock *capability* (dracut modules, kernel args, baked SSH key); it
  doesn't and can't create the LUKS volume itself.
- Two independent unlock paths enrolled as separate keyslots on the same
  LUKS header:
  - **FIDO2** (`systemd-cryptenroll --fido2-device=auto`, run post-install
    via `files/usr/libexec/luks-enroll-fido2.sh` / `just enroll-fido2`) —
    physical-presence only, convenience for local boots.
  - **Passphrase over SSH** (`dracut-crypt-ssh`, dropbear sshd inside the
    initramfs, port 222) — the *only* remote-unlock option. FIDO2 cannot be
    forwarded over a network session, so remote unlock always means typing
    the original LUKS passphrase through the dropbear session, not the
    FIDO2 key. Don't conflate the two when explaining this to a user.

## Why not bootc's native `--block-setup tpm2-luks`

`bootc install to-disk --block-setup tpm2-luks` exists but is **TPM2-only**
(no FIDO2) and unreliable as of this writing: bootc-dev/bootc#421 reports
PCR-mismatch lockouts with no recovery key provisioned, and #477 reports
similar breakage. Not used here for either reason — wrong unlock mechanism
*and* known-broken.

## Why not the new `bootc` Anaconda kickstart command

Anaconda's new `bootc` kickstart command (Fedora Magazine, ~2026) is the
modern way to install a bootc image via kickstart, but it currently has **no
encryption support** (no `--encrypted` equivalent) and explicitly states it
lacks multi-disk/arbitrary-mountpoint support. The older **`ostreecontainer`**
command is what's documented (RHEL/redhat-cop examples) combined with normal
Anaconda partitioning — but it doesn't matter which one we'd pick, because
**bootc-image-builder auto-appends the `ostreecontainer` command itself** for
`[customizations.installer.kickstart]` — don't add either command to the
kickstart `contents`, BIB injects it.

## The actual encrypted-btrfs kickstart pattern

Plain `part / --fstype=btrfs --encrypted` does **not** work — pykickstart's
`part` command's `--fstype` doesn't accept `btrfs` directly. The real pattern
(same one Fedora Workstation's own installer uses for "encrypt my data"):

```
part btrfs.01 --fstype="btrfs" --grow --size=<N> --encrypted --passphrase="..."
btrfs / --label=root --data=single btrfs.01
```

`part` creates+encrypts the underlying partition; the separate `btrfs`
command formats the *decrypted* device as btrfs and mounts it at `/`.

## Dracut module requirements (the part that's easy to get silently wrong)

Both of these need an explicit `/etc/dracut.conf.d/*.conf` drop-in and an
actual `dracut -f --regenerate-all` of the **already-installed** kernel's
initramfs — adding the conf.d file alone does nothing until the initramfs is
rebuilt, and the base `fedora-bootc` image's initramfs was already built
before our `COPY files/ /` step ever runs:

- `fido2`: ships in Fedora's stock `dracut` + `libfido2` already, just
  disabled by default. Real-world Silverblue bug reports confirm this finds
  people who only set the kernel arg and never touched dracut.conf.d.
- `crypt-ssh` (from `dracut-crypt-ssh`): **not in Fedora's repos**, COPR
  `uriesk/dracut-crypt-ssh` only. No fc43-tagged build exists yet but the
  fc42 build installs cleanly on fc43 (verified — it's pure shell/dropbear,
  no compiled-against-fc43-headers dependency). Re-check this if upstream
  ever ships a real compiled binary with a libc version dependency.

The Containerfile verifies the regenerated initramfs actually contains
`crypt-ssh`/`fido2`/`dropbear` via `lsinitrd | grep` and fails the build if
not — this is the single most likely way this feature silently regresses
(e.g. someone reorders steps so the dracut conf.d files land *after* the
regenerate call), so don't remove that check. Check each piece
individually (dropbear binary, authorized_keys, libfido2.so) — a single
`grep -E 'a|b|c'` alternation passes as long as *any one* matches, which let
a real regression (crypt-ssh silently missing, only fido2 present) slip
through once already.

## `dracut --regenerate-all` ignores newly-added dracut.conf.d files

Verified directly: with the exact same `/etc/dracut.conf.d/{crypt-ssh,fido2}.conf`
drop-ins in place, `dracut -f --regenerate-all` produced an initramfs *missing*
crypt-ssh/dropbear/fido2 entirely (no error — `-v` even logged
`*** Including module: crypt-ssh ***`, but the files never actually landed
in the image), while an explicit
`dracut -f /usr/lib/modules/$KVER/initramfs.img $KVER` targeting the same
kernel produced a correct initramfs every time. `--regenerate-all` appears
to reuse whatever config/args the kernel's initramfs was *originally* built
with (i.e. from whenever upstream `fedora-bootc` baked it, before our
conf.d files ever existed) rather than re-reading the current
`/etc/dracut.conf.d` in full. **Always use the explicit
`dracut -f <path> <kver>` form after adding new dracut modules to an
already-installed kernel in a Containerfile** — `--regenerate-all` is not
a safe substitute for it, despite the name suggesting it would pick up
config changes.

## Debugging tip: `lsinitrd` only exists inside the image, not the host

Running `lsinitrd` directly on the build host silently does nothing useful
if it isn't installed there (`command not found` with stderr redirected
away looks identical to "no matches" — a real false negative hit once
during development). Always check initramfs contents via
`podman run --rm -v /path/to/initramfs.img:/tmp/x.img:ro <image> lsinitrd /tmp/x.img`,
not a bare host-side `lsinitrd`.

## SSH key for the initramfs dropbear session

`files/root/.ssh/authorized_keys` is baked into the image at build time —
it's read by dracut-crypt-ssh's `dropbear_acl` setting (default path, see
`files/etc/dracut.conf.d/crypt-ssh.conf`) *during the Containerfile build*,
not at runtime. To rotate the key: regenerate, replace this file, rebuild
the image. The matching private key on the maintainer's machine is
`~/.ssh/distro_initramfs_unlock` (generated without a passphrase for
automation — consider adding one manually via `ssh-keygen -p` if this
matters for your threat model). This key is scoped to initramfs unlock only
— it is deliberately not the same key used for normal post-boot SSH login.

## Networking in the initramfs

`rd.neednet=1 ip=dhcp` is baked via `files/usr/lib/bootc/kargs.d/` (the
current recommended bootc mechanism for default kernel args — TOML files
with a `kargs = [...]` array, applied at install time and on `bootc
upgrade`/`switch`). Static IP isn't configured; if DHCP isn't available
pre-boot on the target network, remote unlock won't be reachable and this
kargs file is where you'd add static `ip=` parameters instead.
