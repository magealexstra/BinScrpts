#!/usr/bin/env bash

# Toggle Sunshine systemd user service and notify the user
SERVICE_NAME="app-dev.lizardbyte.app.Sunshine.service"

if systemctl --user is-active --quiet "${SERVICE_NAME}"; then
    systemctl --user stop "${SERVICE_NAME}"
    notify-send "Sunshine Stream" "Service STOPPED" \
        --icon=preferences-desktop-remote-desktop \
        --urgency=normal \
        --expire-time=3000
else
    systemctl --user start "${SERVICE_NAME}"
    notify-send "Sunshine Stream" "Service STARTED" \
        --icon=preferences-desktop-remote-desktop \
        --urgency=normal \
        --expire-time=3000
fi
