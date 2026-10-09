#!/bin/bash

# System Update Automation Script
# Description: Performs system updates across multiple package managers
# Created: 06-28-22
# Last Modified: 2026-09-30 # Added Claude Code update, per-step failure handling, sudo keepalive

set -o pipefail # Treat pipeline errors as command errors

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

FAILED_STEPS=()
SUDO_KEEPALIVE_PID=""

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

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Runs one step in a subshell with 'set -e' so a failure aborts only that step.
# Must be called as a plain command (not inside if/&&/||), or bash ignores 'set -e'.
run_step() {
    local name="$1"
    shift
    (
        set -e
        "$@"
    )
    local status=$?
    if [ "$status" -ne 0 ]; then
        print_error "$name failed (exit code $status), continuing..."
        FAILED_STEPS+=("$name")
    fi
    return 0
}

# Refreshes the sudo timestamp so long upgrades don't cause a re-prompt mid-run
start_sudo_keepalive() {
    (
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true 2>/dev/null || exit
            sleep 60
        done
    ) >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    fi
}

trap stop_sudo_keepalive EXIT
trap 'exit 130' INT TERM

# --- Update Functions ---
update_apt() {
    print_status "Updating APT package lists..."
    sudo apt-get update -qq
    print_success "APT package lists updated"

    print_status "Performing full APT system upgrade..."
    sudo apt-get dist-upgrade -y
    print_success "APT system upgrade completed"

    print_status "Removing unnecessary APT packages..."
    sudo apt-get autoremove -y
    print_success "Unnecessary APT packages removed"
}

update_flatpak() {
    if check_command flatpak; then
        print_status "Updating Flatpak applications..."
        flatpak update -y
        print_status "Cleaning up unused Flatpak runtimes..."
        flatpak uninstall --unused -y
        print_success "Flatpak applications updated and cleaned"
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

update_npm() {
    if check_command npm; then
        print_status "Updating Global NPM packages..."
        npm update -g
        print_success "Global NPM packages updated"
    else
        print_status "NPM not found, skipping."
    fi
}

update_antigravity() {
    if check_command update-antigravity; then
        print_status "Updating Google Antigravity 2.0 & CLI..."
        update-antigravity
        print_success "Antigravity update check completed"
    else
        print_status "update-antigravity not found, skipping."
    fi
}

update_claude() {
    if check_command claude; then
        print_status "Updating Claude Code..."
        claude update
        print_success "Claude Code update check completed"
    else
        print_status "Claude Code not found, skipping."
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
        print_error "This script requires sudo privileges"
        exit 1
    fi
    start_sudo_keepalive
fi

print_status "Starting system update process..."

run_step "APT update" update_apt
run_step "APT cleanup" cleanup_apt # Clean cache after updates/removals
run_step "Flatpak update" update_flatpak
run_step "Snap update" update_snap
run_step "NPM update" update_npm
run_step "Antigravity update" update_antigravity
run_step "Claude Code update" update_claude
run_step "Log cleanup" cleanup_logs

echo ""
if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
    print_success "All updates and cleanup completed successfully!"
else
    print_error "Finished with ${#FAILED_STEPS[@]} failed step(s):"
    for step in "${FAILED_STEPS[@]}"; do
        print_error "  - $step"
    done
fi

if [ -f /var/run/reboot-required ]; then
    print_warning "A system reboot is required to finish applying updates."
fi

print_status "Note: To check for hardware/BIOS firmware updates, run 'update-base'"

if [ "${#FAILED_STEPS[@]}" -ne 0 ]; then
    exit 1
fi
exit 0
