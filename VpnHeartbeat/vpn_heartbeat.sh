#!/bin/bash
# Verdant Archive: VPN Heartbeat Ritual 
# This script runs inside the Netshoot container (Gluetun Network)
# It verifies WAN connectivity via High Availability Ping (OR logic), 
# reports to Uptime Kuma, and optionally logs IP status.

# Load machine-specific settings from the repo-root .env (resolved through symlinks)
_ENV_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.env"
if [ -f "$_ENV_FILE" ]; then set -a; . "$_ENV_FILE"; set +a; fi

PUSH_URL="${KUMA_PUSH_URL:?set KUMA_PUSH_URL in .env}"
STATUS_FILE="${STATE_DIR:?set STATE_DIR in .env}/logs/vpn_status.json"

# The Sentinels (High Availability Ping Targets)
SENTINELS=("1.1.1.1" "8.8.8.8" "9.9.9.9")

while true; do
    NETWORK_UP=false

    # OR Logic Loop: Check Sentinels one by one
    for IP in "${SENTINELS[@]}"; do
        if ping -c 1 -W 5 "$IP" > /dev/null 2>&1; then
            NETWORK_UP=true
            # We only need one success to confirm the network is alive
            break
        fi
        echo "[$(date)] Sentinel $IP failed to respond..."
    done

    if [ "$NETWORK_UP" = true ]; then
        # If success, tell Kuma the Flame is burning
        curl -s "$PUSH_URL" > /dev/null
        
        # Optionally grab IP info for the status file (don't care if it fails)
        IP_DATA=$(curl -s --connect-timeout 10 https://ipinfo.io/json)
        if [ -n "$IP_DATA" ]; then
            echo "$IP_DATA" > "$STATUS_FILE"
        fi
        
        echo "[$(date)] Heartbeat sent to Kuma. Network is UP."
    else
        echo "[$(date)] ALL SENTINELS FAILED. WAN Unreachable. Silence falling..."
    fi
    
    # Rest for 2 minutes (120s) before the next check to reduce chatter
    sleep 120
done
