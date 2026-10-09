#!/usr/bin/env bash
#
# Update script for Google Antigravity 2.0 and Antigravity CLI (agy)
#

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

MANIFEST_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-x64-linux.yml"
LOCAL_OPT="/home/magealexstra/.local/opt/antigravity"
TEMP_DIR="/tmp/antigravity-updater-$$"
TRASH_DIR="/home/magealexstra/TheWorkshop/_Temp_Trash"
BACKUP_DIR="/home/magealexstra/TheWorkshop/Backups"

mkdir -p "$TRASH_DIR" "$BACKUP_DIR"

# 1. Check Antigravity Desktop Client Version
print_status "Checking for Antigravity 2.0 Desktop updates..."

MANIFEST_CONTENT=$(curl -fsSL "$MANIFEST_URL" 2>/dev/null || true)
if [ -z "$MANIFEST_CONTENT" ]; then
    print_error "Failed to retrieve release manifest from $MANIFEST_URL"
    exit 1
fi

LATEST_VERSION=$(echo "$MANIFEST_CONTENT" | grep -E '^version:' | awk '{print $2}')
DEB_URL=$(echo "$MANIFEST_CONTENT" | grep -oE 'https://[^ ]+\.deb' | head -n 1)

CURRENT_VERSION="unknown"
if [ -f "$LOCAL_OPT/resources/app.asar" ]; then
    CURRENT_VERSION=$(python3 -c "
import mmap, re
try:
    with open('$LOCAL_OPT/resources/app.asar', 'rb') as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        m = re.search(rb'\"productName\":\s*\"Antigravity\",\s*\"version\":\s*\"([^\"]+)\"', mm)
        if m:
            print(m.group(1).decode('utf-8'))
        else:
            print('unknown')
except Exception:
    print('unknown')
")
fi

print_status "Installed Desktop Version: $CURRENT_VERSION"
print_status "Latest Desktop Version:    $LATEST_VERSION"

DEB_SAVED_PATH="$BACKUP_DIR/Antigravity-${LATEST_VERSION}.deb"

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ] || [ "${1:-}" == "--force" ]; then
    print_status "Updating Antigravity Desktop to $LATEST_VERSION..."
    mkdir -p "$TEMP_DIR"
    
    print_status "Downloading .deb package..."
    curl -fsSL -o "$TEMP_DIR/Antigravity.deb" "$DEB_URL"
    
    print_status "Extracting package contents..."
    mkdir -p "$TEMP_DIR/extracted"
    dpkg-deb -x "$TEMP_DIR/Antigravity.deb" "$TEMP_DIR/extracted"
    
    if [ -d "$LOCAL_OPT" ]; then
        BACKUP_DEST="$TRASH_DIR/antigravity_${CURRENT_VERSION}_$(date +%s)"
        print_status "Moving old installation to trash backup: $BACKUP_DEST"
        mv "$LOCAL_OPT" "$BACKUP_DEST"
    fi
    
    print_status "Installing new files to $LOCAL_OPT..."
    mkdir -p "$(dirname "$LOCAL_OPT")"
    cp -r "$TEMP_DIR/extracted/opt/Antigravity" "$LOCAL_OPT"
    chmod +x "$LOCAL_OPT/antigravity" "$LOCAL_OPT/chrome-sandbox" "$LOCAL_OPT/chrome_crashpad_handler" "$LOCAL_OPT/resources/bin/"* 2>/dev/null || true
    
    # Save a copy of the deb package for system-wide dpkg -i
    cp "$TEMP_DIR/Antigravity.deb" "$DEB_SAVED_PATH"
    
    mv "$TEMP_DIR" "$TRASH_DIR/antigravity-updater-temp-$(date +%s)"
    print_success "Antigravity Desktop successfully updated to $LATEST_VERSION!"
else
    print_success "Antigravity Desktop is already up to date ($CURRENT_VERSION)."
fi

# Upgrade system-wide package if sudo privileges are active and it is out of date
SYSTEM_DEB_VER=$(dpkg-query -W -f='${Version}' antigravity 2>/dev/null || echo "")
if [ -n "$SYSTEM_DEB_VER" ] && [ "$SYSTEM_DEB_VER" != "$LATEST_VERSION" ]; then
    if [ ! -f "$DEB_SAVED_PATH" ]; then
        print_status "Downloading deb package for system update..."
        curl -fsSL -o "$DEB_SAVED_PATH" "$DEB_URL"
    fi
    if sudo -n true 2>/dev/null; then
        print_status "Sudo credentials detected. Updating system package /opt/Antigravity from $SYSTEM_DEB_VER to $LATEST_VERSION..."
        sudo -n dpkg -i "$DEB_SAVED_PATH" || print_warning "System dpkg install failed; user installation remains functional."
        print_success "System package /opt/Antigravity updated to $LATEST_VERSION!"
    else
        print_status "Note: System package is at $SYSTEM_DEB_VER. Run with sudo to update /opt/Antigravity as well."
    fi
fi

# 2. Check and update Antigravity CLI
print_status "Checking Antigravity CLI (agy)..."
if command -v agy >/dev/null 2>&1; then
    CLI_INSTALLED=$(agy --version 2>/dev/null || echo "unknown")
    print_status "Installed CLI Version: $CLI_INSTALLED"
fi

print_status "Checking CLI update repository..."
CLI_MANIFEST=$(curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json 2>/dev/null || true)
CLI_LATEST=$(echo "$CLI_MANIFEST" | grep -oP '"version":\s*"\K[^"]+' || echo "")
print_status "Latest CLI Version:    $CLI_LATEST"

if [ -n "$CLI_LATEST" ] && [ "${CLI_INSTALLED:-}" != "$CLI_LATEST" ] || [ "${1:-}" == "--force" ]; then
    print_status "Updating CLI via official bootstrapper..."
    if [ -f "/home/magealexstra/.local/bin/agy" ]; then
        TEMP_AGY_BACKUP="$TRASH_DIR/agy_backup_$(date +%s)"
        mv "/home/magealexstra/.local/bin/agy" "$TEMP_AGY_BACKUP"
    fi
    curl -fsSL https://antigravity.google/cli/install.sh | bash
    CLI_NEW=$(/home/magealexstra/.local/bin/agy --version 2>/dev/null || echo "unknown")
    print_success "Antigravity CLI updated to $CLI_NEW!"
else
    print_success "Antigravity CLI is already up to date ($CLI_INSTALLED)."
fi

echo ""
print_success "All Antigravity components are up to date!"
