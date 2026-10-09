#!/bin/bash
# ==============================================================================
# Verdant Archive Nightly Backup
# Mirrors AppData, /Heimr and host configuration to the vault drive after taking
# consistent database dumps, then takes a read-only BTRFS snapshot of the whole
# backup tree. Runs as root from archive-backup.timer (see README).
#
# Vault layout:
#   Backups/                     BTRFS subvolume
#     Latest/AppData|Heimr|Host  rsync mirrors
#     Latest/Dumps/postgres      pg_dumpall per container (gzip)
#     Latest/Dumps/sqlite        online SQLite backups, same relative paths as AppData
#     History/                   manual one-off backups only; never touched here
#   .snapshots/snapshot-YYYY-MM-DD_HHMM   read-only, pruned after BACKUP_SNAPSHOT_KEEP_DAYS
# ==============================================================================

set -uo pipefail

# Load machine-specific settings from the repo-root .env (resolved through symlinks)
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

VAULT_MOUNT="${BACKUP_VAULT_MOUNT:?set BACKUP_VAULT_MOUNT in .env}"
LOG_FILE="${BACKUP_LOG_FILE:?set BACKUP_LOG_FILE in .env}"
APPDATA_DIR="${APPDATA_DIR:?set APPDATA_DIR in .env}"
HEIMR_DIR="${HEIMR_DIR:?set HEIMR_DIR in .env}"
PG_CONTAINERS="${BACKUP_PG_CONTAINERS:-}"
KUMA_PUSH_URL="${BACKUP_KUMA_PUSH_URL:-}"
KEEP_DAYS="${BACKUP_SNAPSHOT_KEEP_DAYS:-30}"

BACKUP_DIR="$VAULT_MOUNT/Backups"
LATEST="$BACKUP_DIR/Latest"
DUMPS="$LATEST/Dumps"
SNAP_ROOT="$VAULT_MOUNT/.snapshots"
LOG_MAX_BYTES=$((10 * 1024 * 1024))

declare -a FAILED=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
pass() { log "[OK] $1"; }
fail() { log "[FAIL] $1"; FAILED+=("$1"); }

# --- Pre-flight ---------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "archive_backup.sh must run as root (it reads every container's data)." >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

exec 9>/run/archive-backup.lock
if ! flock -n 9; then
    log "[FAIL] Another backup run is already in progress. Exiting."
    exit 1
fi

START=$(date +%s)
log "====================================================="
log "ARCHIVE BACKUP STARTING"
log "====================================================="

# Touch the vault so autofs mounts it, then insist on the real BTRFS volume:
# writing into an unmounted mountpoint would fill the root filesystem.
ls "$VAULT_MOUNT" >/dev/null 2>&1
if [ "$(stat -f -c %T "$BACKUP_DIR" 2>/dev/null)" != "btrfs" ]; then
    fail "Vault $BACKUP_DIR is not on a mounted BTRFS volume. Aborting."
    exit 1
fi
if ! btrfs subvolume show "$BACKUP_DIR" >/dev/null 2>&1; then
    fail "$BACKUP_DIR is not a BTRFS subvolume, so it cannot be snapshotted. Aborting."
    exit 1
fi

# An empty source (drive not mounted) would make rsync --delete wipe the mirror.
for src in "$APPDATA_DIR" "$HEIMR_DIR"; do
    if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
        fail "Source $src is missing or empty (drive not mounted?). Aborting."
        exit 1
    fi
done

log "[*] Vault: $VAULT_MOUNT ($(df -h --output=avail "$VAULT_MOUNT" | tail -1 | tr -d ' ') free)"
mkdir -p "$LATEST/AppData" "$LATEST/Heimr" "$LATEST/Host/etc" "$LATEST/Host/usr-local-bin" \
         "$LATEST/Host/crontabs" "$DUMPS/postgres" "$DUMPS/sqlite" "$SNAP_ROOT"

# --- 1. Database dumps (consistent copies; the rsync of live files may not be) --
log "[1/6] Postgres dumps ..."
for c in $PG_CONTAINERS; do
    if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
        fail "Postgres container $c is not running"
        continue
    fi
    pg_user=$(docker exec "$c" printenv POSTGRES_USER 2>/dev/null)
    out="$DUMPS/postgres/$c.sql.gz"
    if docker exec "$c" pg_dumpall -U "${pg_user:-postgres}" 2>>"$LOG_FILE" | gzip > "$out.tmp"; then
        mv -f "$out.tmp" "$out"
        pass "Postgres $c dumped ($(du -h "$out" | cut -f1))"
    else
        fail "Postgres $c dump failed"
    fi
done

log "[2/6] SQLite online backups ..."
if sqlite_summary=$(python3 - "$APPDATA_DIR" "$DUMPS/sqlite" 2>&1 <<'PYEOF'
import os, sqlite3, sys, urllib.parse
src, dst = sys.argv[1], sys.argv[2]
ok, failed = 0, []
for root, dirs, files in os.walk(src):
    dirs[:] = [d for d in dirs if d != '_temp_trash']
    for name in files:
        if not name.endswith(('.db', '.sqlite', '.sqlite3')):
            continue
        path = os.path.join(root, name)
        try:
            with open(path, 'rb') as f:
                if f.read(16) != b'SQLite format 3\x00':
                    continue
        except OSError:
            continue
        out = os.path.join(dst, os.path.relpath(path, src))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + '.tmp'
        try:
            source = sqlite3.connect('file:' + urllib.parse.quote(path) + '?mode=ro', uri=True, timeout=60)
            target = sqlite3.connect(tmp)
            source.backup(target)
            target.close()
            source.close()
            os.replace(tmp, out)
            ok += 1
        except Exception as e:
            failed.append(f'{os.path.relpath(path, src)}: {e}')
for line in failed:
    print('  FAILED', line)
print(f'{ok} databases copied, {len(failed)} failed')
sys.exit(1 if failed else 0)
PYEOF
); then
    pass "SQLite: $(echo "$sqlite_summary" | tail -1)"
else
    echo "$sqlite_summary" | tee -a "$LOG_FILE"
    fail "SQLite: $(echo "$sqlite_summary" | tail -1)"
fi

# --- 2. Mirrors ---------------------------------------------------------------
# rsync exit 24 means files vanished mid-copy, which is normal for live data.
mirror() {
    local name="$1"; shift
    local output rc
    output=$(rsync -aHAX --numeric-ids --delete --delete-excluded --stats "$@" 2>&1)
    rc=$?
    echo "$output" | grep -E '^(Number of regular files transferred|Total transferred file size|rsync:|rsync error)' \
        | head -20 | sed 's/^/    /' | tee -a "$LOG_FILE"
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 24 ]; then
        pass "$name (rsync exit $rc)"
    else
        fail "$name (rsync exit $rc)"
    fi
}

log "[3/6] Mirroring $APPDATA_DIR ..."
mirror "AppData mirror" \
    --exclude='_temp_trash/' --exclude='logs/' --exclude='transcodes/' \
    --exclude='/jellyfin/cache/' --exclude='/jellyfin/log/' \
    "$APPDATA_DIR/" "$LATEST/AppData/"

log "[4/6] Mirroring $HEIMR_DIR ..."
mirror "Heimr mirror" \
    --exclude='_temp_trash/' --exclude='node_modules/' --exclude='venv/' --exclude='.venv/' \
    --exclude='__pycache__/' --exclude='*.pyc' \
    "$HEIMR_DIR/" "$LATEST/Heimr/"

log "[5/6] Mirroring host configuration ..."
mirror "Host /etc" /etc/ "$LATEST/Host/etc/"
mirror "Host /usr/local/bin" /usr/local/bin/ "$LATEST/Host/usr-local-bin/"
if [ -d /var/spool/cron/crontabs ]; then
    mirror "Host crontabs" /var/spool/cron/crontabs/ "$LATEST/Host/crontabs/"
fi

# --- 3. Snapshot and retention ------------------------------------------------
log "[6/6] Snapshot and retention ..."
SNAP="$SNAP_ROOT/snapshot-$(date +%Y-%m-%d_%H%M)"
if btrfs subvolume snapshot -r "$BACKUP_DIR" "$SNAP" >>"$LOG_FILE" 2>&1; then
    pass "Read-only snapshot $SNAP"
else
    fail "Snapshot $SNAP could not be created"
fi

cutoff=$(date -d "-$KEEP_DAYS days" +%Y-%m-%d)
for s in "$SNAP_ROOT"/snapshot-*; do
    [ -d "$s" ] || continue
    snap_date="${s##*/snapshot-}"
    snap_date="${snap_date:0:10}"
    if [[ "$snap_date" < "$cutoff" ]]; then
        if btrfs subvolume delete "$s" >>"$LOG_FILE" 2>&1; then
            log "[*] Pruned $s (older than $KEEP_DAYS days)"
        else
            fail "Could not prune $s"
        fi
    fi
done

# --- Summary ------------------------------------------------------------------
ELAPSED=$(( $(date +%s) - START ))
log "[*] Duration: $((ELAPSED / 60))m $((ELAPSED % 60))s | Vault free: $(df -h --output=avail "$VAULT_MOUNT" | tail -1 | tr -d ' ')"
if [ "${#FAILED[@]}" -eq 0 ]; then
    log "[OK] PASS: archive backup completed with no failures"
    if [ -n "$KUMA_PUSH_URL" ]; then
        curl -fsS -m 15 -o /dev/null "$KUMA_PUSH_URL" || log "[!] Uptime Kuma push failed"
    fi
    log "====================================================="
    exit 0
else
    log "[FAIL] FAIL: ${#FAILED[@]} step(s) failed:"
    for f in "${FAILED[@]}"; do log "    - $f"; done
    log "====================================================="
    exit 1
fi
