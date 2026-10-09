#!/bin/bash

# Script to clear Elegoo Slicer caches (Recent Files, Network, Locks, and Logs)
# Preserves printer settings, profiles, and filament configurations.
# Updated for ElegooSlicer v1.5.2.2 (AppImage)
#
# Usage: elegooclear [--dry-run] [--yes]
#   --dry-run   Show what would be cleaned without making any changes.
#   -y, --yes   Close a running Elegoo Slicer without asking.
#   -h, --help  Show this help.

set -uo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

CONF_DIR="$HOME/.config/ElegooSlicer"
ELEGOO_CONF="$CONF_DIR/ElegooSlicer.conf"
BACKUP_DIR="$CONF_DIR/backups"
LOG_DIR="$CONF_DIR/log"
MAX_BACKUPS=10

# Matches the AppImage, its 'elegoo-slicer' launcher/binary, and anything run from its mount point.
# Anchored to the start of the command line so shells or editors that merely mention the name are left alone.
SLICER_PATTERN='^([^ ]*/)?(elegoo-slicer|ElegooSlicer[^/ ]*\.AppImage)( |$)|(^| )/tmp/\.mount_Elegoo'

DRY_RUN=false
ASSUME_YES=false
FAILED_STEPS=()

# --- Helper Functions ---
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    # Print to stderr
    echo -e "${RED}[✗]${NC} $1" >&2
}

# Prints a step's success line; stays quiet in dry-run mode, where nothing was changed
print_done() {
    if [[ "$DRY_RUN" == false ]]; then
        print_success "$1"
    fi
}

usage() {
    echo "Usage: elegooclear [--dry-run] [--yes]"
    echo "  --dry-run   Show what would be cleaned without making any changes."
    echo "  -y, --yes   Close a running Elegoo Slicer without asking."
    echo "  -h, --help  Show this help."
}

slicer_running() {
    pgrep -f "$SLICER_PATTERN" >/dev/null 2>&1
}

# Removes each existing path given, or only lists it in dry-run mode. Returns non-zero if any removal fails.
remove_paths() {
    local target found=0 status=0
    for target in "$@"; do
        if [[ ! -e "$target" ]]; then
            continue
        fi
        found=1
        if [[ "$DRY_RUN" == true ]]; then
            print_status "  [dry-run] Would remove: $target"
        elif rm -rf -- "$target"; then
            print_status "  Removed: $target"
        else
            print_error "  Could not remove: $target"
            status=1
        fi
    done
    if (( found == 0 )); then
        print_status "  Nothing to remove."
    fi
    return "$status"
}

# Runs one step and records it as failed if it returns non-zero, so the remaining steps still run
run_step() {
    local name="$1"
    shift
    if ! "$@"; then
        print_error "$name failed, continuing..."
        FAILED_STEPS+=("$name")
    fi
}

# --- Cleanup Functions ---

# Closes the slicer if it is running to avoid file locking. Exits the script if the user declines.
close_slicer() {
    if ! slicer_running; then
        print_status "Elegoo Slicer is not running."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_status "[dry-run] Would close the running Elegoo Slicer"
        return 0
    fi

    if [[ "$ASSUME_YES" == false ]]; then
        print_warning "Elegoo Slicer is running. Closing it will lose any unsaved work."
        read -p "Close it and continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cancelled. Nothing was changed."
            exit 0
        fi
    fi

    print_status "Closing Elegoo Slicer..."
    pkill -f "$SLICER_PATTERN"
    for _ in 1 2 3 4 5; do
        if ! slicer_running; then
            break
        fi
        sleep 1
    done

    # Force kill if still hanging
    if slicer_running; then
        print_warning "Elegoo Slicer did not exit, forcing it to close..."
        pkill -9 -f "$SLICER_PATTERN"
        sleep 1
    fi

    if slicer_running; then
        print_error "Could not close Elegoo Slicer. Nothing was changed."
        exit 1
    fi
    print_success "Elegoo Slicer closed"
}

# Lock files are the primary cause of stale printer discovery
clear_locks() {
    print_status "Clearing lock and instance files..."
    remove_paths "$CONF_DIR/cache/elegoo_master_instance.lock" || return 1
    print_done "Lock and instance files cleared"
}

clear_recent_files() {
    local backup cleared

    print_status "Clearing Recent Files history..."
    if [[ ! -f "$ELEGOO_CONF" ]]; then
        print_status "  Config not found, skipping: $ELEGOO_CONF"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_status "  [dry-run] Would back up and clean: $ELEGOO_CONF"
        return 0
    fi

    backup="$BACKUP_DIR/ElegooSlicer.conf.bak.$(date +%Y%m%d_%H%M%S)"
    if ! { mkdir -p "$BACKUP_DIR" && cp "$ELEGOO_CONF" "$backup"; }; then
        print_error "  Could not back up the config; leaving it untouched."
        return 1
    fi
    print_status "  Backed up config to: $backup"

    # Edit the config as JSON (not with sed) so the file always stays valid; prints the number of entries cleared
    if ! cleared=$(python3 -c '
import json, os, sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    cleared = len(data.get("recent_projects") or {})
    if "recent_projects" in data:
        data["recent_projects"] = {}
    recent = data.get("recent")
    if isinstance(recent, dict):
        for key in ("last_opened_folder", "settings_folder"):
            if key in recent:
                recent[key] = ""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
except (OSError, ValueError) as err:
    sys.exit(f"{err}")
print(cleared)
' "$ELEGOO_CONF"); then
        print_error "  Could not update the config; it was left unchanged."
        return 1
    fi
    print_status "  Cleared $cleared recent project(s) and the last-opened folders"
    print_success "Recent Files history cleared"
}

clear_cache() {
    print_status "Clearing Network Cache and Local Storage..."
    remove_paths \
        "$HOME/.local/share/elegoo-slicer/hsts-storage.sqlite" \
        "$HOME/.local/share/elegoo-slicer/localstorage/" \
        "$HOME/.local/share/elegoo-slicer/storage/" \
        "$HOME/.cache/elegoo-slicer/" || return 1
    print_done "Network cache and local storage cleared"
}

clear_logs() {
    local count

    print_status "Clearing Slicer logs..."
    if [[ ! -d "$LOG_DIR" ]]; then
        print_status "  Log directory not found, skipping."
        return 0
    fi

    # Only the log files themselves; subdirectories in here are slicer data, not logs
    count=$(find "$LOG_DIR" -maxdepth 1 -type f | wc -l)
    if (( count == 0 )); then
        print_status "  Nothing to remove."
    elif [[ "$DRY_RUN" == true ]]; then
        print_status "  [dry-run] Would remove $count log file(s) from: $LOG_DIR"
    elif find "$LOG_DIR" -maxdepth 1 -type f -delete; then
        print_status "  Removed $count log file(s) from: $LOG_DIR"
    else
        print_error "  Could not remove all log files from: $LOG_DIR"
        return 1
    fi
    print_done "Slicer logs cleared"
}

# Keeps only the most recent $MAX_BACKUPS config backups (names end in a sortable timestamp)
rotate_backups() {
    local old_backups=()

    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi
    mapfile -t old_backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'ElegooSlicer.conf.bak.*' | sort -r | tail -n +$((MAX_BACKUPS + 1)))
    if (( ${#old_backups[@]} == 0 )); then
        return 0
    fi

    print_status "Rotating old config backups (keeping newest $MAX_BACKUPS)..."
    remove_paths "${old_backups[@]}" || return 1
    print_done "Old config backups rotated"
}

clean_stale_mounts() {
    local mounts=() stale=() mnt

    mapfile -t mounts < <(find /tmp -maxdepth 1 -name ".mount_Elegoo*" -type d 2>/dev/null)
    if (( ${#mounts[@]} == 0 )); then
        return 0
    fi

    print_status "Cleaning stale AppImage mount points..."
    for mnt in "${mounts[@]}"; do
        if mountpoint -q "$mnt"; then
            print_warning "  Still mounted, skipping: $mnt"
        else
            stale+=("$mnt")
        fi
    done
    if (( ${#stale[@]} > 0 )); then
        remove_paths "${stale[@]}" || return 1
    fi
    print_done "Stale AppImage mount points cleaned"
}

# --- Main Script Logic ---

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -y|--yes) ASSUME_YES=true ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $arg"
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$DRY_RUN" == true ]]; then
    print_warning "DRY RUN: no changes will be made."
fi
print_status "Starting Elegoo Slicer cache cleanup..."

close_slicer
run_step "Lock file cleanup" clear_locks
run_step "Recent Files cleanup" clear_recent_files
run_step "Network cache cleanup" clear_cache
run_step "Log cleanup" clear_logs
run_step "Backup rotation" rotate_backups
run_step "Mount point cleanup" clean_stale_mounts

echo ""
if [[ "$DRY_RUN" == true ]]; then
    print_warning "DRY RUN complete. Re-run without --dry-run to apply."
elif (( ${#FAILED_STEPS[@]} == 0 )); then
    print_success "Elegoo Slicer cache cleared successfully!"
else
    print_error "Finished with ${#FAILED_STEPS[@]} failed step(s):"
    for step in "${FAILED_STEPS[@]}"; do
        print_error "  - $step"
    done
    exit 1
fi
exit 0
