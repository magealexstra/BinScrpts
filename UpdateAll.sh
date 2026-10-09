#!/bin/bash

# System Update Automation Script
# Description: Performs system updates across multiple package managers
# Created: 06-28-22
# Last Modified: 2026-09-18

# Error handling
set -eo pipefail # Exit on error, treat pipeline errors as command errors
trap 'print_error "Error occurred on line $LINENO. Exiting..."; exit 1' ERR

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[✗]${NC} $1" >&2
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# --- Update Functions ---
update_apt() {
    print_status "Updating APT package lists..."
    sudo apt-get -o DPkg::Lock::Timeout=60 update
    print_success "APT package lists updated"

    print_status "Performing full APT system upgrade..."
    # Using DEBIAN_FRONTEND=noninteractive prevents interactive prompts during upgrades
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 dist-upgrade -y
    print_success "APT system upgrade completed"

    print_status "Removing unnecessary APT packages..."
    sudo apt-get -o DPkg::Lock::Timeout=60 autoremove -y
    print_success "Unnecessary APT packages removed"
}

update_flatpak() {
    if check_command flatpak; then
        print_status "Updating Flatpak applications..."
        if flatpak update -y; then
            print_success "Flatpak applications updated"
        else
            print_warning "Flatpak update encountered issues."
        fi
    else
        print_status "Flatpak not found, skipping."
    fi
}

update_snap() {
    if check_command snap; then
        print_status "Updating Snap packages..."
        if sudo snap refresh; then
            print_success "Snap packages updated"
        else
            print_warning "Snap refresh encountered issues."
        fi
    else
        print_status "Snap not found, skipping."
    fi
}

update_npm() {
    if check_command npm; then
        print_status "Updating global npm packages..."
        # Update all global packages (avoids EBADENGINE from forcing unsupported npm major versions)
        if sudo npm update -g; then
            print_success "Global npm packages updated"
        else
            print_warning "npm update encountered warnings or non-fatal issues."
        fi
    else
        print_status "npm not found, skipping."
    fi
}

# --- Cleanup Functions ---
cleanup_apt() {
    print_status "Cleaning APT package cache..."
    sudo apt-get clean
    print_success "APT package cache cleaned"
}

cleanup_logs() {
    if check_command journalctl; then
        print_status "Clearing system logs older than 7 days..."
        sudo journalctl --vacuum-time=7d
        print_success "Old system logs cleared"
    else
        print_status "journalctl not found, skipping log cleanup."
    fi
}

# --- Main Script Logic ---

# Check sudo privileges
if [ "$EUID" -ne 0 ]; then
    if ! sudo -v; then
        echo "This script requires sudo privileges"
        exit 1
    fi
fi

print_status "Starting system update process..."

update_apt
cleanup_apt
update_flatpak
update_snap
update_npm
cleanup_logs

print_success "All updates and cleanup completed successfully!"
exit 0
