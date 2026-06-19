# Build pipeline gotchas

Concrete fixes applied after the CI build (`.github/workflows/build.yml`)
turned out to be fully broken. Useful so these don't get "fixed" back to
the broken form, and so the same root causes get checked first if the
build breaks again.

## `ublue-os/akmods-zfs` no longer publishes a "main" flavor

Only `coreos-stable`, `coreos-testing`, `longterm-<ver>`, and `centos-<ver>`
exist now. A Containerfile referencing `<flavor>-<release>` with `flavor=main`
will fail at the very first `FROM` with "manifest unknown" — there's no
silent degradation, the whole build dies immediately.

## akmods RPM cache layout

The actual `/rpms` layout inside `ghcr.io/ublue-os/akmods-zfs:*` images is:

```
/rpms/kmods/zfs/kmod-zfs-*.rpm
/rpms/kmods/zfs/zfs-*.rpm
/rpms/kmods/zfs/libzfs*.rpm, libuutil*.rpm, libnvpair*.rpm, libzpool*.rpm
/rpms/kmods/zfs/python3-pyzfs-*.rpm
/rpms/kmods/zfs/{debug,devel,other,src}/...   (skip these — debuginfo/devel/test/src)
/rpms/ublue-os/...   (often EMPTY for non-ucore flavors — no addons RPM published)
```

It is **not** `/rpms/kmods/kmod-zfs-*.rpm` + `/rpms/zfs/zfs-*.rpm` (a
plausible-looking guess that doesn't match reality). A single
`dnf -y install /tmp/akmods-rpms/kmods/zfs/*.rpm` picks up everything needed
in one shot. Don't rely on a `**` glob as a "recursive" fallback — bash
`**` only behaves recursively with `shopt -s globstar`, which is off by
default, so it's equivalent to `*` and silently fails to find nested files.

## `dnf5` and COPR

Fedora 42/43's `dnf5` does not support `dnf copr enable` until the
`dnf5-plugins` package is installed (`dnf5-command(copr)` is the actual
plugin, shipped inside `dnf5-plugins`). Without it, `dnf copr enable ...`
fails with "Unknown argument copr for command dnf5" — and if that line is
wrapped in `|| true`, the failure is silent. This can look like the COPR
package "isn't available" when actually the repo was never enabled.

Corollary: niri's `copr enable yalter/niri || true` can fail silently and
the build still succeeds, because niri is already in Fedora's main repos —
the COPR was never actually needed. Don't take "the build passed" as proof
a COPR enable actually worked; check `dnf list installed <pkg>` is coming
from the COPR repo if it matters.

## Package naming

`jetbrains-mono-fonts` is the real Fedora package name —
`ttf-jetbrains-mono-fonts` does not exist and fails with "No match for
argument."
