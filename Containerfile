# =============================================================================
# Custom bootc image: Fedora bootc + KVM/libvirt/virt-manager + niri + noctalia
# + OpenZFS (data pools only; root stays btrfs) via prebuilt uBlue akmods.
#
# NOTE ON "IGNITION": Ignition is a Fedora CoreOS concept and does NOT run on
# bootc/Atomic images. First-boot provisioning here is done by systemd units
# baked into the image (see files/usr/lib/systemd/system/zfs-import-pools.service).
# If you genuinely need Ignition semantics, you must use plain FCOS instead,
# which cannot ship this desktop. This image is the desktop-capable route.
# =============================================================================

# ---- Single source of truth for the Fedora release ----
# Bump this ONE value to move releases; akmods tag and base image follow it.
# The uBlue akmods-zfs cache is published as <kernel_flavor>-<release>, e.g.
# coreos-stable-42. We track the newest published build for that release;
# there is no separate ZFS "version" to pin — the OpenZFS version is whatever
# uBlue ships for this kernel. Keep akmods and base on the SAME release or
# the kmod won't match the kernel and ZFS won't load.
ARG FEDORA_MAJOR=43
ARG AKMODS_KERNEL=coreos-stable
# Resolved tag: e.g. coreos-stable-43. Override AKMODS_TAG directly to pin a
# specific daily build if you ever need reproducibility.
# NOTE: coreos-testing's akmods cache stalled (no rebuild since 2026-05-23)
# while coreos-stable rebuilds daily and tracks the base image far more
# closely — stable is the better bet for an actually-loading ZFS module.
ARG AKMODS_TAG=${AKMODS_KERNEL}-${FEDORA_MAJOR}

# Prebuilt, signed ZFS akmod RPMs (kernel-matched). This is the reliable path,
# and it now tracks the latest uBlue daily build for the chosen release.
FROM ghcr.io/ublue-os/akmods-zfs:${AKMODS_TAG} AS akmods

# ---- Base image: official Fedora bootc, matched to the same release ----
FROM quay.io/fedora/fedora-bootc:${FEDORA_MAJOR}

ARG FEDORA_MAJOR=43

# -----------------------------------------------------------------------------
# 1) Bring in the prebuilt ZFS kmod + userland + uBlue signing/repo addons
# -----------------------------------------------------------------------------
COPY --from=akmods /rpms /tmp/akmods-rpms
RUN set -euxo pipefail; \
    find /tmp/akmods-rpms -type f -name '*.rpm' | sort; \
    # addons: signing key + repo definitions, when this flavor publishes one \
    dnf -y install /tmp/akmods-rpms/ublue-os/ublue-os-akmods-addons*.rpm 2>/dev/null || true; \
    # zfs kmod + zfs/libzfs userland all live under kmods/zfs/ \
    dnf -y install /tmp/akmods-rpms/kmods/zfs/*.rpm; \
    rm -rf /tmp/akmods-rpms

# Make sure the module is found and loaded at boot.
# Target the kernel the base image actually booted, not "whatever directory
# exists" — if the akmods cache is briefly out of sync with the base image
# (the weekly rebuild above is what re-syncs them), the zfs kmod can land
# under a kernel version that was never installed. depmod must still only
# run against the real installed kernel, or it errors out on the stub dir.
RUN set -eux; \
    echo zfs > /usr/lib/modules-load.d/zfs.conf; \
    KVER="$(rpm -q --qf '%{version}-%{release}.%{arch}' kernel)"; \
    depmod -a "$KVER"

# -----------------------------------------------------------------------------
# 2) Virtualization stack: KVM + libvirtd + virt-manager + virt-install
# -----------------------------------------------------------------------------
RUN dnf -y install \
        qemu-kvm libvirt libvirt-daemon-config-network \
        libvirt-daemon-driver-qemu libvirt-daemon-kvm \
        virt-manager virt-install virt-viewer \
        edk2-ovmf swtpm swtpm-tools \
        guestfs-tools libguestfs \
    && systemctl enable libvirtd.service

# -----------------------------------------------------------------------------
# 3) Wayland session: niri compositor + supporting bits + SDDM login
# -----------------------------------------------------------------------------
RUN dnf -y install dnf5-plugins; \
    dnf -y copr enable yalter/niri || true; \
    dnf -y install \
        niri xwayland-satellite \
        sddm \
        wl-clipboard grim slurp \
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
        pipewire pipewire-pulseaudio wireplumber \
        polkit \
        kitty \
    && systemctl enable sddm.service

# -----------------------------------------------------------------------------
# 4) noctalia-shell (Quickshell-based). Not in Fedora repos -> install Quickshell
#    from COPR and clone noctalia into the system config tree.
# -----------------------------------------------------------------------------
RUN dnf -y copr enable errornointernet/quickshell; \
    dnf -y install quickshell git \
        qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qt5compat \
        qt6-qtmultimedia qt6-qtwayland \
        google-noto-sans-fonts google-noto-color-emoji-fonts \
        jetbrains-mono-fonts

# Pull noctalia-shell into /usr/share so it's part of the image, not /home
RUN set -eux; \
    git clone --depth=1 https://github.com/noctalia-dev/noctalia-shell.git \
        /usr/share/noctalia-shell; \
    rm -rf /usr/share/noctalia-shell/.git

# -----------------------------------------------------------------------------
# 5) Overlay our config tree (systemd units, niri config, session files, etc.)
# -----------------------------------------------------------------------------
COPY files/ /

RUN set -eux; \
    systemctl enable zfs-import-pools.service; \
    systemctl enable zfs.target || true; \
    # zfs-mount / zfs-zed if present \
    systemctl enable zfs-mount.service 2>/dev/null || true; \
    systemctl enable zfs-zed.service 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6) bootc requires a clean container at the end
# -----------------------------------------------------------------------------
RUN dnf clean all && rm -rf /var/cache /var/log/dnf* /tmp/*

# bootc lint sanity (non-fatal if tool absent)
RUN bootc container lint || true
