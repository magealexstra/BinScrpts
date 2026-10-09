#!/bin/bash
# Aegis Protocol: Siege Mode (Enter)
# Purpose: Gracefully stop services and unmount drives to save power and prevent corruption.
# Design: Dark Forest / Verdant Archive Standard

# Load machine-specific settings from the repo-root .env (resolved through symlinks);
# copies installed to /usr/local/bin by install-aegis.sh read /etc/verdant/binscrpts.env
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
[ -f "$_ENV_FILE" ] || _ENV_FILE=/etc/verdant/binscrpts.env
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

STATE_FILE="/run/aegis-siege-active"
MEDIA_DRIVE_MOUNT="${MEDIA_DRIVE_MOUNT:?set MEDIA_DRIVE_MOUNT in .env}"
SECONDARY_DRIVE_MOUNT="${SECONDARY_DRIVE_MOUNT:?set SECONDARY_DRIVE_MOUNT in .env}"

# Idempotency check
if [ -f "$STATE_FILE" ]; then
    echo "$(date): [AEGIS] Siege Mode already active. Skipping duplicate activation."
    exit 0
fi

# Set the active state
touch "$STATE_FILE"

echo "$(date): [AEGIS] Aegis Protocol: Entering Siege Mode..."

# 1. Stop all Docker containers via the daemon
echo "$(date): [AEGIS] Stopping Docker service daemon to freeze containers gracefully..."
systemctl stop docker.service docker.socket

# 2. Flush filesystem buffers
echo "$(date): [AEGIS] Flushing filesystem buffers..."
sync
sleep 5

# 3. Unmount the External Archive (BTRFS)
echo "$(date): [AEGIS] Unmounting Hamingja and Mnemosyne..."
if mountpoint -q "$MEDIA_DRIVE_MOUNT"; then
    umount "$MEDIA_DRIVE_MOUNT"
    echo "$(date): [AEGIS] $MEDIA_DRIVE_MOUNT unmounted."
else
    echo "$(date): [AEGIS] $MEDIA_DRIVE_MOUNT is not mounted."
fi

if mountpoint -q "$SECONDARY_DRIVE_MOUNT"; then
    umount "$SECONDARY_DRIVE_MOUNT"
    echo "$(date): [AEGIS] $SECONDARY_DRIVE_MOUNT unmounted."
else
    echo "$(date): [AEGIS] $SECONDARY_DRIVE_MOUNT is not mounted."
fi

echo "$(date): [AEGIS] Siege Mode successfully activated."
