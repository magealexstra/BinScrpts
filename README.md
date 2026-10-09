# BinScrpts

Personal Linux maintenance and automation scripts. Each script lives in its own folder.

## Scripts

### UpdateAll
- `update_all.sh` - runs system updates across package managers (apt, flatpak, snap, npm globals, Claude Code) with per-step failure handling and a sudo keepalive. Usage: `update-all`.
- `update_base.sh` - checks for and applies firmware/BIOS updates through `fwupdmgr`. A restart is needed for BIOS/UEFI updates to apply. Usage: `update-base`.

### UpdateAntigravity
`update_antigravity.sh` - updates the Google Antigravity desktop client (from the update manifest) and the Antigravity CLI (`agy`). Old versions are moved to the trash directory. Usage: `update-antigravity`.

### HealthCheck
`healthcheck.sh` - desktop and server health report: uptime, CPU, GPU (rocm-smi), thermals, local and network drives, BTRFS errors, network, Docker, Ollama and failed systemd units, plus UPS power (when NUT is installed) and the Gluetun VPN tunnel (when a `gluetun` container exists). Usage: `healthcheck [-q|--quick] [-h|--help]`.

### HeadsetRestart
`headset-restart` - escalating PipeWire audio reset for the headset: soft (card profile cycle), wp (restart WirePlumber), full (restart PipeWire and bounce Chromium/Electron audio services). Each run logs a pre-reset snapshot. Usage: `headset-restart [--all | --soft | --wp | --full]`.

### ToggleSunshine
`toggle_sunshine.sh` - starts or stops the Sunshine game-stream systemd user service and shows a desktop notification.

### ElegooSlicerCache
`clear_elegoo_slicer_cache.sh` - clears Elegoo Slicer recent files, network caches, locks and logs while keeping printer, profile and filament settings. Usage: `elegooclear [--dry-run] [-y|--yes] [-h|--help]`.

### AmdGpu
Run as root, then reboot.
- `harden-amdgpu.sh` - rewrites the GRUB kernel command line with parameters that guard against AMDGPU pageflip timeouts.
- `harden-amdgpu-mes.sh` - disables the AMDGPU Micro-Engine Scheduler (MES) for compute stability.

### Backup
`Backup.sh` - rsync-based file backup with progress bar, exclude patterns, dry-run and optional YAML config (requires `yq`). Usage: `Backup/Backup.sh [-c FILE] [-e PATTERN] [-d] [-v] [-o OPTION] SOURCE DEST`.

### Aegis (server)
UPS power-loss protocol built on NUT. Run `sudo Aegis/install-aegis.sh` to install NUT, deploy the saved NUT configs, copy the scripts to `/usr/local/bin`, copy `.env` to `/etc/verdant/binscrpts.env`, and register the systemd units.
- `aegis-sentinel.sh` - at boot, waits for the external media drive (by UUID) before letting the mount and Docker continue.
- `aegis-siege.sh` / `aegis-resume.sh` - on battery: stop Docker and unmount the external drives; on power return: remount and restart Docker.
- `aegis-monitor.sh`, `upssched-cmd.sh`, `*.template` - battery monitor daemon, NUT timer hooks and config templates.

### VpnHeartbeat (server)
`vpn_heartbeat.sh` - runs inside the `netshoot` container on the Gluetun network; pings public resolvers and pushes a heartbeat to Uptime Kuma every 2 minutes. Writes the exit-IP info to `$STATE_DIR/logs/vpn_status.json`.

### ArchiveBackup (server)
`archive_backup.sh` - nightly two-layer backup to the vault drive: rsync with `--backup-dir` history for AppData, Projects and host configs, then a read-only BTRFS snapshot with 30-day retention.

## Configuration

Machine-specific values (install paths, trash and backup folders, log file, drive mounts, network interface) are read from a gitignored `.env` in the repo root. Copy `.env.example` to `.env` and adjust it. Every variable is optional; scripts fall back to `$HOME`-relative defaults. The server scripts (Aegis, VpnHeartbeat, ArchiveBackup) are the exception: their variables are required and the script exits naming any that are missing. Scripts resolve the `.env` from their real path, so it works through symlinks.

## Installation

Symlink the scripts you want into `~/.local/bin`, for example:

    ln -sfn "$PWD/UpdateAll/update_all.sh" ~/.local/bin/update-all
    ln -sfn "$PWD/UpdateAll/update_base.sh" ~/.local/bin/update-base
    ln -sfn "$PWD/UpdateAntigravity/update_antigravity.sh" ~/.local/bin/update-antigravity
    ln -sfn "$PWD/HealthCheck/healthcheck.sh" ~/.local/bin/healthcheck
    ln -sfn "$PWD/HeadsetRestart/headset-restart" ~/.local/bin/headset-restart
    ln -sfn "$PWD/ElegooSlicerCache/clear_elegoo_slicer_cache.sh" ~/.local/bin/elegooclear
