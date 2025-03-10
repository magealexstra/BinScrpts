# System Update Script

A comprehensive Bash script for automating system updates on Linux systems. This script handles updates for:
- APT package manager
- Flatpak applications (if installed)
- Snap packages (if installed)
- Python packages via pip3 (if installed)
- Node.js global packages via npm (if installed)

## Features

- Colored output for better visibility
- Error handling and graceful exit
- Automatic privilege checking
- Smart package cleanup
- Progress indicators for each operation

## Usage

Simply run:
```bash
update-all
```

The script will automatically:
1. Check for sudo privileges
2. Update package lists
3. Upgrade installed packages
4. Remove unnecessary packages
5. Update Flatpak applications (if installed)
6. Update Snap packages (if installed)
7. Update Python packages via pip3 (if installed)
8. Update Node.js global packages via npm (if installed)

## Installation

The script is installed in `/usr/local/bin` for system-wide access.
