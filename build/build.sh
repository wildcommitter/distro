#!/usr/bin/env bash
# Build the bootc image and (optionally) generate an installable disk image.
set -euo pipefail

IMAGE="${IMAGE:-localhost/fedora-niri-zfs:latest}"

echo ">> Building container image: $IMAGE"
podman build -t "$IMAGE" .

cat <<EOF

>> Image built: $IMAGE

To produce an installable artifact, use bootc-image-builder (BIB).
You must first PUSH this image to a registry your target can pull from,
then reference it. Example producing a raw disk image:

  mkdir -p ./output
  sudo podman run --rm -it --privileged \\
    --security-opt label=type:unconfined_t \\
    -v ./output:/output \\
    -v /var/lib/containers/storage:/var/lib/containers/storage \\
    quay.io/centos-bootc/bootc-image-builder:latest \\
    --type raw \\
    --local "$IMAGE"

For an ISO instead, use: --type iso

To install onto an existing machine directly from the container (in-place,
destroys target root!):

  sudo bootc install to-disk --wipe /dev/sdX   # run from a booted bootc env

Then create your two ZFS data pools ONCE:

  sudo /usr/libexec/zfs-create-pools.sh /dev/disk/by-id/<disk0> /dev/disk/by-id/<disk1>

EOF
