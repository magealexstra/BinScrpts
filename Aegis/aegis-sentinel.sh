#!/bin/bash
# Aegis Protocol: Cold-Boot Sentinel
# Purpose: Wait for the manual power-on of the external drive bay before allowing Docker to start.

# Load machine-specific settings from the repo-root .env (resolved through symlinks);
# copies installed to /usr/local/bin by install-aegis.sh read /etc/verdant/binscrpts.env
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
[ -f "$_ENV_FILE" ] || _ENV_FILE=/etc/verdant/binscrpts.env
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

TARGET_UUID="${MEDIA_DRIVE_UUID:?set MEDIA_DRIVE_UUID in .env}"
MOUNT_POINT="${MEDIA_DRIVE_MOUNT:?set MEDIA_DRIVE_MOUNT in .env}"

echo "$(date): [SENTINEL] Archive boot detected. Waiting for External Drive (UUID: $TARGET_UUID)..."

# Loop until the drive UUID appears in /dev/disk/by-uuid/
while [ ! -L "/dev/disk/by-uuid/$TARGET_UUID" ]; do
    echo "$(date): [SENTINEL] Drive not found. Please power on the External Drive Bay now."
    sleep 10
done

echo "$(date): [SENTINEL] Drive detected! Mounting filesystems..."

# Mount everything in fstab
mount -a

# Verify mount success
if mountpoint -q "$MOUNT_POINT"; then
    echo "$(date): [SENTINEL] $MOUNT_POINT is ONLINE."
    
    # Optional: If you want the sentinel to manually trigger docker restart
    # systemctl start docker
    # docker start $(docker ps -a -q)
    
    echo "$(date): [SENTINEL] Archive is ready. Sentinel standing down."
    exit 0
else
    echo "$(date): [SENTINEL] ERROR: Drive detected but mount failed!"
    exit 1
fi
