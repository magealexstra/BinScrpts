#!/bin/bash

# System Update Automation Script
# Description: Performs system updates across multiple package managers
# Created: 06-28-22
# Last Modified: 2025-03-06

# Error handling
set -e
trap 'echo "Error occurred. Exiting..." >&2; exit 1' ERR

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Check if we have sudo privileges
if [ "$EUID" -ne 0 ]; then 
    if ! sudo -v; then
        echo "This script requires sudo privileges"
        exit 1
    fi
fi

print_status "Starting system update process..."

# APT updates
print_status "Updating package lists..."
if sudo apt update; then
    print_success "Package lists updated successfully"
fi

print_status "Upgrading packages..."
if sudo apt upgrade -y; then
    print_success "Packages upgraded successfully"
fi

# Check if there are any packages that can be removed
if apt list --auto-removable 2>/dev/null | grep -q "^"; then
    print_status "Removing unnecessary packages..."
    if sudo apt autoremove -y; then
        print_success "Unnecessary packages removed"
    fi
fi

# Optional: Update Flatpak if installed
if command -v flatpak >/dev/null 2>&1; then
    print_status "Updating Flatpak applications..."
    if flatpak update -y; then
        print_success "Flatpak applications updated"
    fi
fi

# Optional: Update Snap if installed
if command -v snap >/dev/null 2>&1; then
    print_status "Updating Snap packages..."
    if sudo snap refresh; then
        print_success "Snap packages updated"
    fi
fi

print_success "All updates completed successfully!"
exit 0