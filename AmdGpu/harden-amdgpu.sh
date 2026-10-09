#!/bin/bash
# Script to harden AMDGPU display configuration against pageflip timeouts.

GRUB_FILE="/etc/default/grub"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo."
  exit 1
fi

# New hardened command line parameters
TARGET_PARAMS="quiet splash amdgpu.gpu_recovery=1 amdgpu.dcdebugmask=0x50 amdgpu.sg_display=0 amdgpu.cwsr_enable=0"

echo "Updating GRUB cmdline default parameters..."
# Robust replacement that targets the GRUB_CMDLINE_LINUX_DEFAULT line
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$TARGET_PARAMS\"|g" "$GRUB_FILE"

if grep -q "amdgpu.dcdebugmask=0x50" "$GRUB_FILE" && grep -q "amdgpu.sg_display=0" "$GRUB_FILE"; then
  echo "Successfully updated $GRUB_FILE with new hardening parameters."
else
  echo "Error: Failed to update $GRUB_FILE automatically. Please check the file contents manually."
  exit 1
fi

echo "Updating GRUB bootloader configuration..."
update-grub
echo "Hardening complete! Please reboot your system for changes to take effect."

