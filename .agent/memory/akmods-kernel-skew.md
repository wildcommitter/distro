# akmods/kernel version skew

`ghcr.io/ublue-os/akmods-zfs:<flavor>-<release>` (flavor =
`coreos-stable`, `coreos-testing`, `longterm-*`, `centos-*`) and
`quay.io/fedora/fedora-bootc:<release>` are both **independently-updating
floating tags**. Matching the Fedora major release number does **not**
guarantee the ZFS kmod's target kernel version matches the base image's
actually-installed kernel.

Concretely observed on 2026-06-19, Fedora 43:

- `fedora-bootc:43` kernel: `7.0.12-101.fc43` (rebuilt that same day)
- `akmods-zfs:coreos-stable-43` kmod target: `7.0.9-105.fc43` (rebuilt that
  same day, ~daily cadence, one point release behind)
- `akmods-zfs:coreos-testing-43` kmod target: `7.0.8-100.fc43` (last
  rebuilt **2026-05-23** — testing had stalled for ~a month; it is *not*
  necessarily fresher than stable, despite the name)

**Why:** `coreos-stable`/`coreos-testing` track Fedora CoreOS's own
kernel-pinning cadence, not the generic Fedora bootc image's rolling
kernel updates. They're built by different pipelines on different
schedules. "Testing" being more bleeding-edge is not a safe assumption —
check actual freshness, don't infer it from the name.

**How to check before switching flavor or release:**

```bash
# kernel actually in the base image
podman run --rm quay.io/fedora/fedora-bootc:<N> rpm -q kernel

# kernel the akmods cache built its kmod for
cid=$(podman create ghcr.io/ublue-os/akmods-zfs:<flavor>-<N>)
podman cp "$cid:/rpms/kmods/zfs" /tmp/akmods-check && podman rm "$cid"
find /tmp/akmods-check -maxdepth 1 -iname 'kmod-zfs-*'

# freshness of each
podman inspect <image> --format '{{.Created}}'
```

**How this project handles it:** the Containerfile's depmod step targets
the kernel actually installed via `rpm -q --qf '%{version}-%{release}.%{arch}' kernel`
— not "whatever single directory exists under `/usr/lib/modules`" — so a
mismatch degrades gracefully (the build still succeeds; ZFS just doesn't
load until the caches resync) instead of crashing `depmod` outright. The
weekly cron in `.github/workflows/build.yml` is what's expected to close
the gap over time. If ZFS needs to work on the very next build with no
wait, the only real fix is pinning the base image to a specific digest
known to match an available akmods build — not chasing this with more
Containerfile logic.
