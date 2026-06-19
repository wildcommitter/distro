#!/usr/bin/env bash
# ONE-TIME, MANUAL pool creation. Run as root AFTER first boot.
# Usage: zfs-create-pools.sh <disk-by-id-for-tank0> <disk-by-id-for-tank1>
# Example:
#   zfs-create-pools.sh /dev/disk/by-id/nvme-XXXX /dev/disk/by-id/ata-YYYY
set -euo pipefail
[ "$#" -eq 2 ] || { echo "need 2 disk by-id paths"; exit 1; }
D0="$1"; D1="$2"
zpool create -o ashift=12 -O compression=zstd -O atime=off \
  -O xattr=sa -O acltype=posixacl -O mountpoint=/tank0 tank0 "$D0"
zpool create -o ashift=12 -O compression=zstd -O atime=off \
  -O xattr=sa -O acltype=posixacl -O mountpoint=/tank1 tank1 "$D1"
# Persist import via cachefile so zfs-import-pools finds them fast
zpool set cachefile=/etc/zfs/zpool.cache tank0
zpool set cachefile=/etc/zfs/zpool.cache tank1
echo "Created tank0 and tank1. They will auto-import on subsequent boots."
