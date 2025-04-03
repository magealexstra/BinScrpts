# BinScrpts

A collection of useful scripts for Linux system maintenance and automation.

## Backup Script

A flexible file backup script that uses rsync to backup files from one location to another.

### Features

- **Backup Capabilities**:
  - Backs up files and directories preserving permissions and timestamps
  - Supports powerful filter rules for fine-grained control over what gets backed up
  - Prevents creation of nested directories with duplicate names
  - Dry run mode for testing without making changes
  - YAML configuration for easier setup and maintenance

- **User Experience**:
  - Colorized output for better readability
  - Clear status messages
  - Error handling with informative messages
  - Real-time progress bar with current file display
  - Single-line file transfer display that updates in place
  - Graceful interruption handling (Ctrl+C)

### Color Coding

The script uses color-coded output for better readability:

- **Blue** `[*]`: Status/Information messages - Indicates an operation in progress or general information
- **Green** `[✓]`: Success messages - Indicates a successfully completed operation
- **Red** `[✗]`: Error messages - Indicates an error or failure
- **Yellow** `[!]`: Warning messages - Indicates a potential issue that doesn't stop execution or interruption notifications
- **Cyan**: Used for the progress bar

### Usage

```bash
./Backup.sh [options] <source_directory> <destination_directory>
```

Or using a YAML configuration file (recommended):

```bash
./Backup.sh --config <config_file.yaml>
```

#### Interrupting a Backup

You can safely interrupt a running backup at any time by pressing `Ctrl+C`. The script will handle the interruption gracefully, display a cleanup message, and exit with the appropriate status code. This is useful when:

- You need to stop a backup that's taking too long
- You realize you made a configuration mistake
- You need to free up system resources for another task
- The system needs to be shut down before the backup completes

When interrupted, the script will:
1. Display a warning message indicating the backup was interrupted
2. Show the time when the interruption occurred
3. Exit with status code 130 (standard for SIGINT interruption)

Note that any files already backed up before the interruption will remain in the destination directory.

#### Options:
- `-h, --help`: Show help message
- `-c, --config FILE`: Use YAML configuration file
- `-e, --exclude PATTERN`: Exclude files/directories matching PATTERN (can be used multiple times)
- `-d, --dry-run`: Perform a trial run with no changes made
- `-v, --verbose`: Increase verbosity
- `-o, --option OPTION`: Pass additional options directly to rsync (can be used multiple times)

#### Examples:
```bash
./Backup.sh /home/user/Documents /media/backup/Documents
./Backup.sh --exclude '*.tmp' --exclude '*.log' /home/user/Projects /media/backup/Projects
./Backup.sh --dry-run /home/user/Pictures /media/backup/Pictures
./Backup.sh --option '--no-delete' /home/user/Documents /media/backup/Documents  # Keep files in backup even if deleted from source
./Backup.sh --config configs/example.yaml  # Use YAML configuration file
```

### YAML Configuration

The script supports YAML configuration files, which provide a more user-friendly way to configure backups. Example configuration files are included in the `configs/` directory.

#### Example YAML Configuration:

```yaml
# Example Backup Configuration
name: "Example Backup"
description: "Example configuration for the Backup script"

# Destination settings
destination: "/path/to/your/backup/directory"  # Example: /media/backup/Documents

# Source directories to backup
sources:
  - path: "/path/to/your/source/directory"  # Example: /home/user/Documents
  
  - path: "/path/to/another/directory"      # Example: /home/user/Pictures
  
  - path: "/path/to/special/directory"      # Example: /home/user/.config
    name: "custom_name"                     # Custom name for the destination folder

# Filter rules (more powerful than include/exclude)
filter_rules:
  - "- *.tmp"       # Exclude temporary files
  - "- *.log"       # Exclude log files
  - "- node_modules/"  # Exclude node_modules directories
  - "- .git/"       # Exclude git repositories
  - "- .cache/"     # Exclude cache directories
  - "- *~"          # Exclude backup files

# Rsync options
options:
  preserve_deleted: true  # Keep files in backup even if deleted from source
  # compress: true        # Uncomment to enable compression during transfer
  # bandwidth_limit: 1000 # Uncomment to limit bandwidth usage (KB/s)

# Output settings
verbose: false      # Show detailed output (set to false for cleaner single-line display)
```

#### Filter Rules

The YAML configuration uses rsync's filter rules, which are more powerful than simple include/exclude patterns. Filter rules use the following syntax:

- `- PATTERN`: Exclude files/directories matching PATTERN
- `+ PATTERN`: Include files/directories matching PATTERN
- `P PATTERN`: Protect files/directories matching PATTERN (never delete)
- `H PATTERN`: Hide files/directories matching PATTERN (don't transfer)

Filter rules are processed in order, so you can create complex inclusion/exclusion patterns. For example:

```yaml
filter_rules:
  - "+ *.jpg"       # Include all JPG files
  - "+ *.png"       # Include all PNG files
  - "- *"           # Exclude everything else
```

This would only backup JPG and PNG files, excluding everything else.

#### Preventing Nested Directories

The script automatically adds a trailing slash to source directories to prevent the creation of nested directories with duplicate names. For example, if you backup `/home/user/Documents`, the files will be placed directly in the destination directory, not in a subdirectory called `Documents`.

#### To create your own YAML configuration:

1. Copy the example YAML file: `cp configs/example.yaml configs/my-backup.yaml`
2. Edit the file with your source and destination directories
3. Customize filter rules and other options as needed
4. Run the script with `./Backup.sh --config configs/my-backup.yaml`

This approach is more maintainable than creating separate shell scripts for each backup configuration.

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
  - Colorized output for better readability (status, success, errors)
  - Clear status messages
  - Error handling with informative messages (errors shown in red)

### Color Coding

The script uses color-coded output for better readability:

- **Blue** `[*]`: Status/Information messages - Indicates an operation in progress or general information
- **Green** `[✓]`: Success messages - Indicates a successfully completed operation
- **Red** `[✗]`: Error messages - Indicates an error or failure

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
