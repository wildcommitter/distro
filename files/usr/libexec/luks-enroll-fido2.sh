#!/usr/bin/env bash
# ONE-TIME, MANUAL FIDO2 enrollment for the encrypted root. Run as root AFTER
# first boot, with the FIDO2 key plugged in. Adds FIDO2 as an *additional*
# LUKS keyslot — your original passphrase keeps working (it's also the only
# thing usable for the SSH remote-unlock path, since FIDO2 can't be done
# over a network session).
# Usage: luks-enroll-fido2.sh [luks-device]
# With no argument, the LUKS device backing the root filesystem is detected.
set -euo pipefail

DEV="${1:-}"
if [ -z "$DEV" ]; then
    ROOT_SRC="$(findmnt -no SOURCE /)"
    MAPPER_NAME="$(lsblk -no NAME "$ROOT_SRC" | head -1)"
    DEV="/dev/$(lsblk -no PKNAME "/dev/$MAPPER_NAME")"
fi

[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
cryptsetup isLuks "$DEV" || { echo "$DEV is not a LUKS device" >&2; exit 1; }

echo "Enrolling FIDO2 key into $DEV — touch the key when it blinks."
systemd-cryptenroll --fido2-device=auto "$DEV"
echo "Done. Existing passphrase keyslot is untouched."
