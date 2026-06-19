# Justfile — convenience wrappers for the fedora-niri-zfs bootc image.
# Install just: https://github.com/casey/just  (dnf install just)
# List recipes: `just`  or  `just --list`

# ---- configuration (override on the CLI, e.g. `just IMAGE=foo build`) ----
IMAGE      := "localhost/fedora-niri-zfs:latest"
REGISTRY   := "ghcr.io"
OWNER      := "wildcommitter"
IMAGE_NAME := "fedora-niri-zfs"
OUTPUT     := "./output"
BIB        := "quay.io/centos-bootc/bootc-image-builder:latest"

# Default: show available recipes
default:
    @just --list

# Build the container image locally
build:
    podman build -t {{IMAGE}} .

# Build, tagging for GHCR as well
build-ghcr:
    podman build \
        -t {{IMAGE}} \
        -t {{REGISTRY}}/{{OWNER}}/{{IMAGE_NAME}}:latest \
        .

# Push the GHCR-tagged image (requires prior `podman login ghcr.io`)
push: build-ghcr
    podman push {{REGISTRY}}/{{OWNER}}/{{IMAGE_NAME}}:latest

# Lint the image with bootc's container linter
lint:
    podman run --rm {{IMAGE}} bootc container lint

# Generate a raw disk image via bootc-image-builder
raw: build
    mkdir -p {{OUTPUT}}
    sudo podman run --rm -it --privileged \
        --security-opt label=type:unconfined_t \
        -v {{OUTPUT}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{BIB}} --type raw --local {{IMAGE}}

# Generate an installable ISO via bootc-image-builder
iso: build
    mkdir -p {{OUTPUT}}
    sudo podman run --rm -it --privileged \
        --security-opt label=type:unconfined_t \
        -v {{OUTPUT}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{BIB}} --type iso --local {{IMAGE}}

# Install in place onto a target disk (DESTROYS it). Run from a booted bootc env.
# Usage: just install-to-disk DISK=/dev/sdX
install-to-disk DISK:
    @echo "This WIPES {{DISK}}. Ctrl-C within 5s to abort."; sleep 5
    sudo bootc install to-disk --wipe {{DISK}}

# One-time creation of the two ZFS data pools (run once, post-install).
# Usage: just zfs-create DISK0=/dev/disk/by-id/... DISK1=/dev/disk/by-id/...
zfs-create DISK0 DISK1:
    sudo /usr/libexec/zfs-create-pools.sh {{DISK0}} {{DISK1}}

# Show ZFS pool + dataset status
zfs-status:
    -zpool status
    -zpool list
    -zfs list

# Add the current user to the libvirt group (re-login afterwards)
enroll-libvirt:
    sudo usermod -aG libvirt $USER
    @echo "Log out and back in for group membership to take effect."

# Remove local build artifacts
clean:
    rm -rf {{OUTPUT}}

# Pull the latest published image from GHCR
pull:
    podman pull {{REGISTRY}}/{{OWNER}}/{{IMAGE_NAME}}:latest
