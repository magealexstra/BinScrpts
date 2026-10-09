#!/bin/bash

# ==============================================================================
# Dual-Layer Verdant Archive Backup Automation Script
# Strategy: rsync with --backup-dir history + BTRFS atomic read-only snapshots
# Target Vault: $BACKUP_VAULT_MOUNT
# ==============================================================================

set -eo pipefail

# Load machine-specific settings from the repo-root .env (resolved through symlinks)
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

LOG_FILE="${BACKUP_LOG_FILE:?set BACKUP_LOG_FILE in .env}"
VAULT_MOUNT="${BACKUP_VAULT_MOUNT:?set BACKUP_VAULT_MOUNT in .env}"
APPDATA_DIR="${APPDATA_DIR:?set APPDATA_DIR in .env}"
PROJECTS_DIR="${PROJECTS_DIR:?set PROJECTS_DIR in .env}"
BACKUP_DIR="${VAULT_MOUNT}/Backups"
LATEST_DIR="${BACKUP_DIR}/Latest"
DATE_STAMP=$(date +%Y-%m-%d)
TIME_STAMP=$(date +"%Y-%m-%d %H:%M:%S")
HISTORY_DIR="${BACKUP_DIR}/History/${DATE_STAMP}"
SNAPSHOT_DIR="${VAULT_MOUNT}/.snapshots/snapshot-${DATE_STAMP}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$TIME_STAMP] $1" | tee -a "$LOG_FILE"
}

log "====================================================="
log "STARTING DUAL-LAYER ARCHIVE BACKUP (Midnight Run)"
log "====================================================="

# 1. Pre-flight Check: Verify Geymsla is mounted
if ! findmnt -M "$VAULT_MOUNT" > /dev/null 2>&1; then
    log "[FAIL] ERROR: Vault drive $VAULT_MOUNT is not mounted! Aborting to protect root OS."
    exit 1
fi

AVAIL_SPACE=$(df -h "$VAULT_MOUNT" | awk 'NR==2 {print $4}')
log "[*] Target Vault: $VAULT_MOUNT ($AVAIL_SPACE free)"

# 2. Create Target Directories
mkdir -p "$LATEST_DIR/AppData"
mkdir -p "$LATEST_DIR/Projects"
mkdir -p "$LATEST_DIR/HostConfig"
mkdir -p "${VAULT_MOUNT}/.snapshots"

# 3. Layer 1: Sync AppData with --backup-dir history
log "[1/4] Syncing $APPDATA_DIR ..."
rsync -avh --delete \
    --backup --backup-dir="$HISTORY_DIR/AppData" \
    --exclude="*_temp_trash*" --exclude="*.cache*" \
    "$APPDATA_DIR/" "$LATEST_DIR/AppData/" >> "$LOG_FILE" 2>&1 || true

# 4. Sync Projects
log "[2/4] Syncing $PROJECTS_DIR ..."
rsync -avh --delete \
    --backup --backup-dir="$HISTORY_DIR/Projects" \
    --exclude="*_temp_trash*" --exclude="node_modules" --exclude=".venv" \
    "$PROJECTS_DIR/" "$LATEST_DIR/Projects/" >> "$LOG_FILE" 2>&1 || true

# 5. Sync Host Configurations (/etc and scripts)
log "[3/4] Syncing Host Configurations ..."
mkdir -p "$LATEST_DIR/HostConfig/etc"
mkdir -p "$LATEST_DIR/HostConfig/scripts"
rsync -avh --delete \
    /etc/samba/ /etc/nut/ /etc/fstab /etc/environment \
    "$LATEST_DIR/HostConfig/etc/" >> "$LOG_FILE" 2>&1 || true

rsync -avh --delete \
    /usr/local/bin/update-all \
    "$LATEST_DIR/HostConfig/scripts/" >> "$LOG_FILE" 2>&1 || true

# 6. Layer 2: BTRFS Read-Only Atomic Snapshot
log "[4/4] Creating BTRFS Read-Only Snapshot ..."
if [ -d "$SNAPSHOT_DIR" ]; then
    log "[*] Snapshot $SNAPSHOT_DIR already exists for today. Skipping creation."
else
    sudo btrfs subvolume snapshot -r "$BACKUP_DIR" "$SNAPSHOT_DIR" >> "$LOG_FILE" 2>&1 || true
    log "[OK] BTRFS Snapshot created: $SNAPSHOT_DIR"
fi

# 7. Retention Pruning (Clean BTRFS snapshots older than 30 days)
log "[*] Pruning snapshots older than 30 days ..."
find "${VAULT_MOUNT}/.snapshots" -maxdepth 1 -name "snapshot-*" -mtime +30 -exec sudo btrfs subvolume delete {} \; >> "$LOG_FILE" 2>&1 || true

FINAL_AVAIL=$(df -h "$VAULT_MOUNT" | awk 'NR==2 {print $4}')
log "[OK] SUCCESS: Dual-layer backup completed. Remaining free space: $FINAL_AVAIL"
log "====================================================="
echo "" >> "$LOG_FILE"
