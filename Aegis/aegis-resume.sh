#!/bin/bash
# Aegis Protocol: Resume Mode (Exit)
# Purpose: Remount drives and restart services when power returns.
# Design: Dark Forest / Verdant Archive Standard

# Load machine-specific settings from the repo-root .env (resolved through symlinks);
# copies installed to /usr/local/bin by install-aegis.sh read /etc/verdant/binscrpts.env
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
[ -f "$_ENV_FILE" ] || _ENV_FILE=/etc/verdant/binscrpts.env
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

STATE_FILE="/run/aegis-siege-active"
MEDIA_DRIVE_MOUNT="${MEDIA_DRIVE_MOUNT:?set MEDIA_DRIVE_MOUNT in .env}"

# Idempotency check
if [ ! -f "$STATE_FILE" ]; then
    echo "$(date): [AEGIS] Siege Mode is not active. Skipping resume routine."
    exit 0
fi

echo "$(date): [AEGIS] Power Restored. Exiting Siege Mode..."

# 1. Remount the External Archive
echo "$(date): [AEGIS] Remounting Hamingja and Mnemosyne..."
mount -a

# 2. Verify Mounts
if mountpoint -q "$MEDIA_DRIVE_MOUNT"; then
    echo "$(date): [AEGIS] Hamingja remounted successfully."
else
    echo "$(date): [AEGIS] ERROR: Hamingja failed to mount!"
    exit 1
fi

# 3. Restart Docker daemon
echo "$(date): [AEGIS] Starting Docker service daemon..."
systemctl start docker.service docker.socket

# Remove active state flag
rm -f "$STATE_FILE"

echo "$(date): [AEGIS] Archive Online. All systems nominal."
