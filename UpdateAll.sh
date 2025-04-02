#!/bin/bash

# System Update Automation Script
# Description: Performs system updates across multiple package managers
# Created: 06-28-22
# Last Modified: 2025-04-02 # Updated modification date

# Error handling
set -eo pipefail # Exit on error, treat pipeline errors as command errors
trap 'print_error "Error occurred on line $LINENO. Exiting..."; exit 1' ERR

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'  # Added Red color
NC='\033[0m' # No Color

# --- Helper Functions ---
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    # Print to stderr
    echo -e "${RED}[✗]${NC} $1" >&2
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# --- Update Functions ---
update_apt() {
    print_status "Updating APT package lists..."
    sudo apt update
    print_success "APT package lists updated"

    print_status "Performing full APT system upgrade..."
    sudo apt full-upgrade -y
    print_success "APT system upgrade completed"

    # Check if there are any packages that can be removed
    if sudo apt list --auto-removable 2>/dev/null | grep -q "."; then
        print_status "Removing unnecessary APT packages..."
        sudo apt autoremove -y
        print_success "Unnecessary APT packages removed"
    else
        print_status "No unnecessary APT packages to remove."
    fi
}

update_flatpak() {
    if check_command flatpak; then
        print_status "Updating Flatpak applications..."
        flatpak update -y
        print_success "Flatpak applications updated"
    else
        print_status "Flatpak not found, skipping."
    fi
}

update_snap() {
    if check_command snap; then
        print_status "Updating Snap packages..."
        sudo snap refresh
        print_success "Snap packages updated"
    else
        print_status "Snap not found, skipping."
    fi
}

update_pip() {
    if check_command pip3; then
        print_status "Updating global Python packages (pip3)..."
        # Get list of outdated packages
        outdated_packages=$(sudo pip3 list --outdated --format=freeze | cut -d'=' -f1)
        if [ -n "$outdated_packages" ]; then
            echo "Outdated pip packages found: $outdated_packages"
            # Update using xargs, handle potential errors per package
            echo "$outdated_packages" | xargs -n1 sudo pip3 install -U || print_status "Some pip packages might have failed to update."
            print_success "Global Python packages update attempt finished."
        else
            print_success "All global Python packages are up-to-date."
        fi
    else
        print_status "pip3 not found, skipping Python package update."
    fi
}


# --- Cleanup Functions ---
cleanup_apt() {
    print_status "Cleaning APT package cache..."
    sudo apt clean
    sudo apt autoclean
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
cleanup_apt # Clean cache after updates/removals
update_flatpak
update_snap
update_pip
cleanup_logs

print_success "All updates and cleanup completed successfully!"
exit 0