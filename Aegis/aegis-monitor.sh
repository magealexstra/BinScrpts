#!/bin/bash
# Aegis Protocol: Battery & State Monitor Daemon 
# Purpose: Continuously check battery level and status to trigger Siege Mode (50%) and Shutdown (25%).
# Design: Dark Forest / Verdant Archive Standard

STATE_FILE="/run/aegis-siege-active"
UPS_NAME="cyberpower"
INTERVAL=15 # Check every 15 seconds

echo "$(date): [MONITOR] Aegis Monitor Daemon started. Watching UPS '$UPS_NAME'..."

while true; do
    # Fetch UPS status and battery charge
    # Handle failures gracefully to avoid false alarms
    if ! UPS_STATUS=$(upsc "$UPS_NAME" ups.status 2>/dev/null) || ! BATTERY_CHARGE=$(upsc "$UPS_NAME" battery.charge 2>/dev/null); then
        echo "$(date): [MONITOR] WARNING: Failed to query upsc for $UPS_NAME. Retrying in $INTERVAL seconds..."
        sleep "$INTERVAL"
        continue
    fi

    # Clean inputs
    UPS_STATUS=$(echo "$UPS_STATUS" | tr -d ' \r\n')
    BATTERY_CHARGE=$(echo "$BATTERY_CHARGE" | tr -cd '0-9')

    # Ensure charge is a valid integer
    if [[ ! "$BATTERY_CHARGE" =~ ^[0-9]+$ ]]; then
        echo "$(date): [MONITOR] WARNING: Invalid battery charge value: '$BATTERY_CHARGE'. Retrying..."
        sleep "$INTERVAL"
        continue
    fi

    # Determine if system is on battery (status contains OB)
    ON_BATTERY=0
    if [[ "$UPS_STATUS" =~ OB ]]; then
        ON_BATTERY=1
    fi

    if [ "$ON_BATTERY" -eq 1 ]; then
        # 1. Immediate Shutdown check at 25%
        if [ "$BATTERY_CHARGE" -le 25 ]; then
            echo "$(date): [MONITOR] CRITICAL: Battery is at $BATTERY_CHARGE% (<= 25%). Initiating immediate emergency shutdown!" | tee /dev/kmsg
            /sbin/shutdown -h +0 "UPS battery critical at $BATTERY_CHARGE%. Aegis Protocol initiating emergency cold shutdown."
            exit 0
        fi

        # 2. Siege Mode check at 50%
        if [ "$BATTERY_CHARGE" -le 50 ]; then
            if [ ! -f "$STATE_FILE" ]; then
                echo "$(date): [MONITOR] WARNING: Battery is at $BATTERY_CHARGE% (<= 50%) on backup power. Triggering Siege Mode..." | tee /dev/kmsg
                /usr/local/bin/aegis-siege.sh
            fi
        fi
    else
        # System is ONLINE (utility power restored)
        if [ -f "$STATE_FILE" ]; then
            echo "$(date): [MONITOR] INFO: Utility power restored. Battery at $BATTERY_CHARGE%. Exiting Siege Mode..." | tee /dev/kmsg
            /usr/local/bin/aegis-resume.sh
        fi
    fi

    sleep "$INTERVAL"
done
