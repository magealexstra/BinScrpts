#!/bin/bash
# Aegis Protocol: UPS Monitor & Sentinel Installer 
# Description: Installs NUT, restores migration configurations, registers the Cold-Boot Sentinel, and deploys extraction scripts.

# Load machine-specific settings from the repo-root .env (resolved through symlinks);
# copies installed to /usr/local/bin by install-aegis.sh read /etc/verdant/binscrpts.env
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
[ -f "$_ENV_FILE" ] || _ENV_FILE=/etc/verdant/binscrpts.env
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi
# Design: Dark Forest / Verdant Archive Standard

# Strict error handling
set -eo pipefail
trap 'echo -e "\n\e[31m[FAIL] An error occurred. Aegis deployment halted!\e[0m"; exit 1' ERR

# Colors for output (Parchment & Sage Theme)
SAGE='\033[0;32m'
CANOPY='\033[1;32m'
MANA='\033[0;36m'
PARCHMENT='\033[0;37m'
EARTH='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

print_title() {
    echo -e "${CANOPY}"
    echo "======================================================================="
    echo "            AEGIS PROTOCOL: UPS MONITOR & SENTINEL INSTALLER   "
    echo "======================================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${MANA}[*]${NC} $1"
}

print_success() {
    echo -e "${SAGE}[OK]${NC} $1"
}

print_warning() {
    echo -e "${EARTH}[!]${NC} $1"
}

# --- 1. Root and Path Validation ---
print_title

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[FAIL] This ritual requires root privileges. Please run as root (sudo).${NC}"
    exit 1
fi

MIGRATION_DIR="${NUT_MIGRATION_DIR:?set NUT_MIGRATION_DIR in .env}"
SCRIPTS_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ENV="$SCRIPTS_DIR/../.env"

print_status "Validating source paths..."
if [ ! -d "$MIGRATION_DIR" ]; then
    print_warning "Migration backup folder not found at: $MIGRATION_DIR"
    # Check alternative location
    MIGRATION_DIR="$NUT_MIGRATION_DIR/nut"
    if [ ! -d "$MIGRATION_DIR" ]; then
        echo -e "${RED}[FAIL] Migration NUT configurations not found in Kattegat_Migration!${NC}"
        exit 1
    fi
fi
print_success "Migration source validated: $MIGRATION_DIR"

if [ ! -d "$SCRIPTS_DIR" ]; then
    echo -e "${RED}[FAIL] Aegis scripts directory not found at: $SCRIPTS_DIR${NC}"
    exit 1
fi
print_success "Scripts source validated: $SCRIPTS_DIR"


# --- 2. Install Network UPS Tools (NUT) ---
print_status "Installing Network UPS Tools (NUT) packages..."
apt-get update -qq
apt-get install -y nut nut-client nut-server
print_success "NUT packages installed successfully."


# --- 3. Deploy Host Configurations ---
print_status "Deploying customized NUT configuration files..."

# Backup current /etc/nut if it exists
if [ -d "/etc/nut" ]; then
    print_status "Backing up default NUT configs to /etc/nut.default.bak..."
    cp -r /etc/nut /etc/nut.default.bak
fi

# Copy the migration configurations
cp "$MIGRATION_DIR"/nut.conf /etc/nut/nut.conf
cp "$MIGRATION_DIR"/ups.conf /etc/nut/ups.conf
cp "$MIGRATION_DIR"/upsd.conf /etc/nut/upsd.conf
cp "$MIGRATION_DIR"/upsd.users /etc/nut/upsd.users
cp "$MIGRATION_DIR"/upsmon.conf /etc/nut/upsmon.conf
cp "$MIGRATION_DIR"/upssched.conf /etc/nut/upssched.conf

# Enforce secure ownership and permissions
print_status "Securing NUT configuration permissions..."
chown root:nut /etc/nut/*.conf /etc/nut/upsd.users
chmod 640 /etc/nut/*.conf /etc/nut/upsd.users

print_success "NUT configurations successfully deployed and secured."


# --- 4. Deploy Aegis Execution Scripts ---
print_status "Deploying Aegis execution scripts to /usr/local/bin/..."

# Copy to /usr/local/bin
cp "$SCRIPTS_DIR/upssched-cmd.sh" /usr/local/bin/upssched-cmd
cp "$SCRIPTS_DIR/aegis-siege.sh" /usr/local/bin/aegis-siege.sh
cp "$SCRIPTS_DIR/aegis-resume.sh" /usr/local/bin/aegis-resume.sh
cp "$SCRIPTS_DIR/aegis-sentinel.sh" /usr/local/bin/aegis-sentinel.sh
cp "$SCRIPTS_DIR/aegis-monitor.sh" /usr/local/bin/aegis-monitor.sh

# Make them executable
chmod +x /usr/local/bin/upssched-cmd
chmod +x /usr/local/bin/aegis-siege.sh
chmod +x /usr/local/bin/aegis-resume.sh
chmod +x /usr/local/bin/aegis-sentinel.sh
chmod +x /usr/local/bin/aegis-monitor.sh

if [ -f "$REPO_ENV" ]; then
    mkdir -p /etc/verdant
    install -m 600 -o root -g root "$REPO_ENV" /etc/verdant/binscrpts.env
    print_success "Host settings deployed to /etc/verdant/binscrpts.env"
else
    print_warning "No .env next to the repo; installed scripts need /etc/verdant/binscrpts.env"
fi

print_success "Aegis execution scripts successfully deployed."


# --- 5. Deploy & Register the Aegis Services ---
print_status "Registering the Aegis Cold-Boot Sentinel Service..."
cp "$SCRIPTS_DIR/aegis-sentinel.service.template" /etc/systemd/system/aegis-sentinel.service
chmod 644 /etc/systemd/system/aegis-sentinel.service

print_status "Registering the Aegis Battery Monitor Daemon Service..."
cp "$SCRIPTS_DIR/aegis-monitor.service.template" /etc/systemd/system/aegis-monitor.service
chmod 644 /etc/systemd/system/aegis-monitor.service

systemctl daemon-reload
systemctl enable aegis-sentinel.service
systemctl enable aegis-monitor.service
systemctl restart aegis-monitor.service || true
print_success "Aegis Sentinel and Monitor services registered, enabled, and initiated."


# --- 6. Enable and Start NUT Services ---
print_status "Activating NUT monitoring services..."

# Restart services to apply configurations
systemctl restart nut-server.service
systemctl restart nut-client.service
systemctl restart nut-monitor.service || true # Some distros use nut-monitor, others nut-client

systemctl enable nut-server.service
systemctl enable nut-client.service
systemctl enable nut-monitor.service || true

print_success "NUT services restarted and enabled on boot."


# --- 7. Validation Scrying ---
echo -e "\n${MANA}=======================================================================${NC}"
echo -e "                    AEGIS PROTOCOL ACTIVATION VERIFICATION   "
echo -e "${MANA}=======================================================================${NC}\n"

# Verify communication with UPS
print_status "Querying UPS status over USB..."
if upsc cyberpower 2>/dev/null | grep -i "status" > /dev/null; then
    echo -e "${SAGE}Status: ONLINE and Communicating${NC}"
    upsc cyberpower | grep -E "device.model|ups.status|ups.delay.shutdown|battery.charge|battery.runtime" || true
else
    print_warning "Unable to query 'cyberpower' UPS status directly. Let's list available devices:"
    nut-scanner -U || true
fi

echo -e "\n${CANOPY}[OK] Aegis Protocol successfully deployed and activated.${NC}"
echo -e "${PARCHMENT}The Cold-Boot Sentinel stands guard, and the Siege Mode extraction is primed.${NC}"
echo -e "${PARCHMENT}You can verify logs at any time using: ${MANA}journalctl -u aegis-sentinel -u nut-server${NC}\n"
