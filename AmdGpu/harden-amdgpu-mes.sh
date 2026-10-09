#!/bin/bash
# Script to disable AMDGPU Micro-Engine Scheduler (MES) for compute stability.

GRUB_FILE="/etc/default/grub"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo."
  exit 1
fi

if grep -q "amdgpu.mes=0" "$GRUB_FILE"; then
  echo "AMDGPU MES disabling parameter (amdgpu.mes=0) is already present in $GRUB_FILE."
else
  echo "Adding amdgpu.mes=0 to GRUB default cmdline..."
  # Locate the GRUB_CMDLINE_LINUX_DEFAULT line and insert amdgpu.mes=0 inside the quotes
  sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 amdgpu.mes=0"/' "$GRUB_FILE"
  if grep -q "amdgpu.mes=0" "$GRUB_FILE"; then
    echo "Successfully updated $GRUB_FILE."
  else
    echo "Error: Failed to update $GRUB_FILE automatically. Please check the file contents manually."
    exit 1
  fi
fi

echo "Updating GRUB bootloader configuration..."
update-grub
echo "MES hardening complete! Please reboot your system for changes to take effect."
