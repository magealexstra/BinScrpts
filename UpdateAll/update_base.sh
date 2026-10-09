#!/bin/bash

# System Firmware Update Script
# Description: Safely checks for and applies hardware and BIOS updates via fwupdmgr.
# Requires system restart for BIOS/UEFI updates to apply.

set -eo pipefail
trap 'echo -e "\033[0;31m[✗]\033[0m Error occurred on line $LINENO. Exiting..." >&2; exit 1' ERR

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

UPDATES_APPLIED=0
UPDATES_FAILED=0

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Lists devices with pending updates as "device-id<TAB>name<TAB>current<TAB>new", one per line.
# Prints nothing if the list cannot be built, in which case only all-or-nothing is offered.
list_updatable_devices() {
    sudo fwupdmgr get-updates --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for dev in data.get("Devices", []):
    releases = dev.get("Releases") or []
    if not releases or not dev.get("DeviceId"):
        continue
    print("\t".join([
        dev["DeviceId"],
        dev.get("Name") or "Unknown device",
        dev.get("Version") or "?",
        releases[0].get("Version") or "?",
    ]))
' 2>/dev/null || true
}

# Applies updates for one device ($1 = device id, $2 = display name), or for all devices if no id is given.
# --no-reboot-check stops '-y' from also answering yes to fwupdmgr's "Restart now?" prompt.
apply_update() {
    local dev_id="$1"
    local label="${2:-all devices}"
    print_status "Applying firmware update for $label..."
    if sudo fwupdmgr update ${dev_id:+"$dev_id"} -y --no-reboot-check; then
        print_success "Firmware update applied for $label"
        UPDATES_APPLIED=1
    else
        print_error "Firmware update failed for $label"
        UPDATES_FAILED=1
    fi
}

if [ "$EUID" -ne 0 ]; then
    if ! sudo -v; then
        echo "This script requires sudo privileges"
        exit 1
    fi
fi

if ! command -v fwupdmgr >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] fwupdmgr is not installed. Firmware updates cannot be processed.${NC}"
    exit 1
fi

print_status "Refreshing firmware metadata from LVFS..."
sudo fwupdmgr refresh --force

print_status "Checking for available firmware updates..."
# fwupdmgr get-updates exits 0 when updates exist and 2 when there is nothing to do; anything else is a real failure.
updates_status=0
sudo fwupdmgr get-updates -q || updates_status=$?

if [ "$updates_status" -eq 0 ]; then
    print_warning "Firmware updates are available!"
    echo "------------------------------------------------------"
    echo "WARNING: BIOS/Firmware updates carry inherent risks."
    echo "Ensure your system is plugged into reliable power."
    echo "Do NOT interrupt the update process."
    echo "------------------------------------------------------"

    mapfile -t devices < <(list_updatable_devices)

    if [ "${#devices[@]}" -gt 1 ]; then
        echo "Devices with pending updates:"
        for entry in "${devices[@]}"; do
            IFS=$'\t' read -r _ dev_name dev_current dev_new <<< "$entry"
            echo "  - $dev_name: $dev_current -> $dev_new"
        done
        read -p "Install [a]ll, [s]elect per device, or [N]one? (a/s/N) " -n 1 -r
        echo
    else
        read -p "Do you want to proceed with installing these updates? (y/N) " -n 1 -r
        echo
        # With one device (or no per-device list) there is nothing to select, so yes means all
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            REPLY="a"
        fi
    fi

    if [[ $REPLY =~ ^[Aa]$ ]]; then
        apply_update ""
    elif [[ $REPLY =~ ^[Ss]$ ]]; then
        for entry in "${devices[@]}"; do
            IFS=$'\t' read -r dev_id dev_name dev_current dev_new <<< "$entry"
            read -p "Update $dev_name ($dev_current -> $dev_new)? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                apply_update "$dev_id" "$dev_name"
            else
                print_status "Skipped $dev_name."
            fi
        done
    else
        print_status "Firmware update cancelled by user."
    fi

    if [ "$UPDATES_APPLIED" -eq 1 ]; then
        print_warning "NOTE: Most firmware updates require a full system REBOOT to take effect."
    fi
    if [ "$UPDATES_FAILED" -eq 1 ]; then
        exit 1
    fi
elif [ "$updates_status" -eq 2 ]; then
    print_success "No firmware updates available at this time."
else
    print_error "Could not check for firmware updates (fwupdmgr exit code $updates_status)."
    exit 1
fi

exit 0
