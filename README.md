# BinScrpts

A collection of useful scripts for Linux system maintenance and automation.

## UpdateAll Script

A comprehensive system update automation script that handles multiple package managers and performs system maintenance.

### Features

- **Package Management**:
  - APT package updates and upgrades
  - Flatpak updates (if installed)
  - Snap package updates (if installed)
  - Python packages updates via pip3 (if installed)
  - Automatic detection of installed package managers

- **System Maintenance**:
  - Removal of unnecessary/auto-removable packages
  - Package cache cleaning
  - System log cleanup (journalctl)
  - Enhanced error handling and reporting

- **User Experience**:
  - Colorized output for better readability
  - Clear status messages
  - Error handling with informative messages

### Installation

1. Make the script executable:
   ```bash
   chmod +x ~/Documents/VSProjects/BinScrpts/UpdateAll.sh
   ```

2. Add to PATH for system-wide access as `update-all`:
   ```bash
   mkdir -p ~/.local/bin
   ln -s ~/Documents/VSProjects/BinScrpts/UpdateAll.sh ~/.local/bin/update-all
   ```

3. Ensure ~/.local/bin is in your PATH:
   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

### Usage

Simply run:
```bash
update-all
```

## Contributing

Feel free to submit pull requests with improvements or additional scripts!

## License

MIT License
