#!/bin/bash

# File Backup Script
# Description: Backs up files from a source location to a destination location
# Created: 2025-04-03
# Last Modified: 2025-04-03

# Error handling
set -eo pipefail # Exit on error, treat pipeline errors as command errors
trap 'print_error "Error occurred on line $LINENO. Exiting..."; exit 1' ERR

# Interrupt handling
trap 'print_warning "Backup interrupted by user (Ctrl+C). Cleaning up..."; exit 130' SIGINT
trap 'print_warning "Backup terminated. Cleaning up..."; exit 143' SIGTERM

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Terminal control
CURSOR_UP='\033[1A'
CURSOR_DOWN='\033[1B'
CLEAR_LINE='\033[2K'
CARRIAGE_RETURN='\r'

# --- Helper Functions ---

# Get terminal dimensions
get_terminal_size() {
    if command -v tput >/dev/null 2>&1; then
        TERM_ROWS=$(tput lines)
        TERM_COLS=$(tput cols)
    else
        # Default values if tput is not available
        TERM_ROWS=24
        TERM_COLS=80
    fi
}

# Draw progress bar
draw_progress_bar() {
    local percent=$1
    local label=$2
    local bar_size=50
    local filled=$(( percent * bar_size / 100 ))
    local empty=$(( bar_size - filled ))
    
    # Draw the progress bar
    printf "${CYAN}%s: [" "$label"
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%${NC}" $percent
    
    # Clear the rest of the line
    printf "${CLEAR_LINE}\n"
}

# Draw both progress bars (file and overall)
draw_progress_bars() {
    local file_percent=$1
    local overall_percent=$2
    local file_info=$3
    
    # Save cursor position and move to bottom of terminal
    get_terminal_size
    tput sc
    
    # Draw file info line
    tput cup $(( TERM_ROWS - 4 )) 0
    printf "${CLEAR_LINE}${BLUE}[*]${NC} Current file: %s" "${file_info:0:$(( TERM_COLS - 15 ))}"
    
    # Draw file progress bar
    tput cup $(( TERM_ROWS - 3 )) 0
    draw_progress_bar "$file_percent" "File progress"
    
    # Draw overall progress bar
    tput cup $(( TERM_ROWS - 2 )) 0
    draw_progress_bar "$overall_percent" "Overall progress"
    
    # Restore cursor position
    tput rc
}

# Update progress and file info based on rsync output
update_progress() {
    local line="$1"
    local file_percent=0
    local file_info=""
    local bytes_transferred=0
    
    # Extract progress percentage from rsync output
    if [[ "$line" =~ ([0-9]+)% ]]; then
        file_percent="${BASH_REMATCH[1]}"
        
        # Extract bytes transferred if available
        if [[ "$line" =~ ([0-9,]+)/([0-9,]+) ]]; then
            local current_bytes=$(echo "${BASH_REMATCH[1]}" | tr -d ',')
            local total_bytes=$(echo "${BASH_REMATCH[2]}" | tr -d ',')
            
            # Update transferred bytes for overall progress calculation
            bytes_transferred=$current_bytes
            
            # Update total bytes if this is a new file
            if [[ "$CURRENT_FILE" != "$line" ]]; then
                CURRENT_FILE="$line"
                CURRENT_FILE_TOTAL_BYTES=$total_bytes
            fi
        fi
        
        # Update overall progress
        TOTAL_BYTES_TRANSFERRED=$(( TOTAL_BYTES_TRANSFERRED + bytes_transferred - LAST_BYTES_TRANSFERRED ))
        LAST_BYTES_TRANSFERRED=$bytes_transferred
        
        # Calculate overall percentage
        local overall_percent=0
        if [[ $TOTAL_BYTES_TO_TRANSFER -gt 0 ]]; then
            overall_percent=$(( TOTAL_BYTES_TRANSFERRED * 100 / TOTAL_BYTES_TO_TRANSFER ))
        fi
        
        # Ensure overall percentage doesn't exceed 100%
        if [[ $overall_percent -gt 100 ]]; then
            overall_percent=100
        fi
        
        # Update both progress bars
        draw_progress_bars "$file_percent" "$overall_percent" "$file_info"
    fi
    
    # Extract file information
    if [[ "$line" =~ to\ send$ ]]; then
        # This is the initial calculation line, don't display
        return
    elif [[ "$line" =~ ^sending\ incremental ]]; then
        # This is the initial transfer line, don't display
        return
    elif [[ "$line" =~ ^sent\ [0-9]+ ]]; then
        # This is the summary line, don't display
        return
    elif [[ "$line" =~ ^total\ size ]]; then
        # This is the summary line, don't display
        return
    elif [[ "$line" =~ ^$|^\ *$ ]]; then
        # Empty line, don't display
        return
    else
        # This is likely a file being transferred
        file_info="$line"
        
        # Update file info in progress bars
        local overall_percent=0
        if [[ $TOTAL_BYTES_TO_TRANSFER -gt 0 ]]; then
            overall_percent=$(( TOTAL_BYTES_TRANSFERRED * 100 / TOTAL_BYTES_TO_TRANSFER ))
        fi
        
        # Ensure overall percentage doesn't exceed 100%
        if [[ $overall_percent -gt 100 ]]; then
            overall_percent=100
        fi
        
        # Extract file progress if available
        if [[ "$line" =~ ([0-9]+)% ]]; then
            file_percent="${BASH_REMATCH[1]}"
        else
            file_percent=0
        fi
        
        draw_progress_bars "$file_percent" "$overall_percent" "$file_info"
    fi
}

# Clear progress bars and file info
clear_progress_bars() {
    get_terminal_size
    tput sc
    # Clear file info line
    tput cup $(( TERM_ROWS - 4 )) 0
    printf "${CLEAR_LINE}\n"
    # Clear file progress bar line
    tput cup $(( TERM_ROWS - 3 )) 0
    printf "${CLEAR_LINE}\n"
    # Clear overall progress bar line
    tput cup $(( TERM_ROWS - 2 )) 0
    printf "${CLEAR_LINE}\n"
    tput rc
}

# Calculate total size of all files to be transferred
calculate_total_size() {
    local config_file="$1"
    local total_bytes=0
    local sources_count=$(yq -r '.sources | length' "$config_file")
    
    print_status "Calculating total size of files to transfer..."
    
    # Build rsync options for dry run
    local rsync_options="-a --stats --dry-run"
    
    # Add options from configuration
    local preserve_deleted=$(read_yaml "$config_file" ".options.preserve_deleted" "true")
    if [[ "$preserve_deleted" != "true" ]]; then
        rsync_options="$rsync_options --delete"
    fi
    
    # Process each source directory
    for (( i=0; i<$sources_count; i++ )); do
        local source_path=$(yq -r ".sources[$i].path" "$config_file")
        local source_name=$(yq -r ".sources[$i].name" "$config_file")
        
        # If source name is not specified, use the basename of the path
        if [[ "$source_name" == "null" || -z "$source_name" ]]; then
            source_name=$(basename "$source_path")
            
            # Handle special case for .config (remove the dot)
            if [[ "$source_name" == ".config" ]]; then
                source_name="config"
            fi
        fi
        
        # Create the full destination path
        local dest_dir="$destination/$source_name"
        
        # Add trailing slash to source directory to copy contents, not the directory itself
        local source_dir_with_slash="${source_path%/}/"
        
        # Build filter rules
        local filter_options=""
        while read -r filter_rule; do
            if [ -n "$filter_rule" ]; then
                filter_options="$filter_options --filter='$filter_rule'"
            fi
        done < <(read_yaml_array "$config_file" ".filter_rules")
        
        # Execute rsync in dry-run mode to get stats
        print_status "Analyzing: $source_path"
        local size_output=$(eval "rsync $rsync_options $filter_options \"$source_dir_with_slash\" \"$dest_dir\" 2>/dev/null")
        
        # Extract total bytes to be transferred
        local bytes=$(echo "$size_output" | grep "Total transferred file size:" | grep -o '[0-9,]*' | tr -d ',')
        if [[ -n "$bytes" ]]; then
            total_bytes=$(( total_bytes + bytes ))
        fi
    done
    
    echo "$total_bytes"
}

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    # Print to stderr
    echo -e "${RED}[✗]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_usage() {
    echo "Usage: $0 [options] <source_directory> <destination_directory>"
    echo "   or: $0 --config <config_file.yaml>"
    echo
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -c, --config FILE          Use YAML configuration file"
    echo "  -e, --exclude PATTERN      Exclude files/directories matching PATTERN (can be used multiple times)"
    echo "  -d, --dry-run              Perform a trial run with no changes made"
    echo "  -v, --verbose              Increase verbosity"
    echo "  -o, --option OPTION        Pass additional options directly to rsync (can be used multiple times)"
    echo
    echo "Examples:"
    echo "  $0 /home/user/Documents /media/backup/Documents"
    echo "  $0 --exclude '*.tmp' --exclude '*.log' /home/user/Projects /media/backup/Projects"
    echo "  $0 --dry-run /home/user/Pictures /media/backup/Pictures"
    echo "  $0 --option '--no-delete' /home/user/Documents /media/backup/Documents"
    echo "  $0 --config configs/example.yaml"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# --- YAML Configuration Functions ---

# Check if yq is installed
check_yq() {
    if ! check_command yq; then
        print_error "yq is not installed. Please install it with 'sudo apt-get install -y yq' and try again."
        exit 1
    fi
}

# Read a value from YAML file
read_yaml() {
    local file="$1"
    local key="$2"
    local default="$3"
    
    local value
    value=$(yq -r "$key" "$file" 2>/dev/null)
    
    # Check if value is null or empty
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Read an array from YAML file
read_yaml_array() {
    local file="$1"
    local key="$2"
    
    yq -r "$key[]" "$file" 2>/dev/null
}

# Process YAML configuration file
process_config() {
    local config_file="$1"
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        exit 1
    fi
    
    print_status "Reading configuration from: $config_file"
    
    # Read configuration values
    local name=$(read_yaml "$config_file" ".name" "Backup")
    local description=$(read_yaml "$config_file" ".description" "")
    local destination=$(read_yaml "$config_file" ".destination" "")
    local verbose=$(read_yaml "$config_file" ".verbose" "false")
    
    # Print configuration header
    echo "=========================================================="
    echo "  $name"
    if [ -n "$description" ]; then
        echo "  $description"
    fi
    echo "  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================================="
    echo
    
    # Set verbose flag
    if [[ "$verbose" == "true" ]]; then
        VERBOSE=true
    else
        VERBOSE=false
    fi
    
    # Check if destination is set
    if [ -z "$destination" ]; then
        print_error "Destination directory not specified in configuration file."
        exit 1
    fi
    
    # Process each source directory
    local sources_count=$(yq -r '.sources | length' "$config_file")
    if [ "$sources_count" -eq 0 ]; then
        print_error "No source directories specified in configuration file."
        exit 1
    fi
    
    # Calculate total size of all files to be transferred
    TOTAL_BYTES_TO_TRANSFER=$(calculate_total_size "$config_file")
    TOTAL_BYTES_TRANSFERRED=0
    LAST_BYTES_TRANSFERRED=0
    CURRENT_FILE=""
    CURRENT_FILE_TOTAL_BYTES=0
    
    print_status "Total size to transfer: $(numfmt --to=iec-i --suffix=B $TOTAL_BYTES_TO_TRANSFER)"
    
    # Build rsync options
    RSYNC_OPTIONS="-a --progress"
    
    # Add options from configuration
    local preserve_deleted=$(read_yaml "$config_file" ".options.preserve_deleted" "true")
    if [[ "$preserve_deleted" == "true" ]]; then
        # Don't add --delete option
        :
    else
        RSYNC_OPTIONS="$RSYNC_OPTIONS --delete"
    fi
    
    local compress=$(read_yaml "$config_file" ".options.compress" "false")
    if [[ "$compress" == "true" ]]; then
        RSYNC_OPTIONS="$RSYNC_OPTIONS --compress"
    fi
    
    local bandwidth_limit=$(read_yaml "$config_file" ".options.bandwidth_limit" "")
    if [ -n "$bandwidth_limit" ]; then
        RSYNC_OPTIONS="$RSYNC_OPTIONS --bwlimit=$bandwidth_limit"
    fi
    
    # Process each source directory
    for (( i=0; i<$sources_count; i++ )); do
        local source_path=$(yq -r ".sources[$i].path" "$config_file")
        local source_name=$(yq -r ".sources[$i].name" "$config_file")
        
        # If source name is not specified, use the basename of the path
        if [[ "$source_name" == "null" || -z "$source_name" ]]; then
            source_name=$(basename "$source_path")
            
            # Handle special case for .config (remove the dot)
            if [[ "$source_name" == ".config" ]]; then
                source_name="config"
            fi
        fi
        
        # Create the full destination path
        local dest_dir="$destination/$source_name"
        
        echo "------------------------------------------------------------"
        echo "Backing up: $source_path"
        echo "To: $dest_dir"
        if [[ "$preserve_deleted" == "true" ]]; then
            echo "Files deleted from source will be KEPT in the backup"
        else
            echo "Files deleted from source will be DELETED from the backup"
        fi
        
        # Add trailing slash to source directory to copy contents, not the directory itself
        local source_dir_with_slash="${source_path%/}/"
        
        # Build filter rules
        local filter_options=""
        while read -r filter_rule; do
            if [ -n "$filter_rule" ]; then
                filter_options="$filter_options --filter='$filter_rule'"
            fi
        done < <(read_yaml_array "$config_file" ".filter_rules")
        
        # Execute the backup for this source directory
        local backup_cmd="rsync $RSYNC_OPTIONS $filter_options \"$source_dir_with_slash\" \"$dest_dir\""
        
        # Create space for the file info line and progress bars
        echo
        echo
        echo
        echo
        
        # Initialize progress bars and file info line
        get_terminal_size
        tput sc
        tput cup $(( TERM_ROWS - 4 )) 0
        printf "${BLUE}[*]${NC} Current file: Preparing..."
        tput rc
        draw_progress_bars 0 0 "Preparing..."
        
        # Execute rsync with the constructed options and capture output for progress bar
        eval "$backup_cmd 2>&1" | while IFS= read -r line; do
            # Update progress bar and file info
            update_progress "$line"
        done
        
        # Clear progress bars and file info, then show completion
        clear_progress_bars
        
        # Check if the backup was successful
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "✓ Backup of $source_name completed successfully"
        else
            echo "✗ Backup of $source_name failed with error code ${PIPESTATUS[0]}"
        fi
        echo
    done
    
    echo "=========================================================="
    echo "  BACKUP PROCESS COMPLETED"
    echo "  Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================================="
    
    exit 0
}

# --- Backup Function ---
perform_backup() {
    local source_dir="$1"
    local dest_dir="$2"
    local rsync_options="$3"
    
    # Create destination directory if it doesn't exist
    if [ ! -d "$dest_dir" ]; then
        print_status "Creating destination directory: $dest_dir"
        mkdir -p "$dest_dir"
    fi
    
    # Perform the backup
    print_status "Starting backup from '$source_dir' to '$dest_dir'..."
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No files will be modified"
        rsync_options="$rsync_options --dry-run"
    fi
    
    # Always add info flag for progress updates, but don't print each file on a new line
    rsync_options="$rsync_options --info=progress2"
    
    # If verbose is true, we'll still capture all output but display it differently
    if [ "$VERBOSE" = true ]; then
        rsync_options="$rsync_options -v"
    fi
    
    # Make sure we have progress info for the progress bar
    if [[ "$rsync_options" != *"--progress"* ]]; then
        rsync_options="$rsync_options --progress"
    fi
    
    # Create space for the file info line and progress bars
    echo
    echo
    echo
    echo
    
    # Initialize progress bars and file info line
    get_terminal_size
    tput sc
    tput cup $(( TERM_ROWS - 4 )) 0
    printf "${BLUE}[*]${NC} Current file: Preparing..."
    tput rc
    draw_progress_bars 0 0 "Preparing..."
    
    # Execute rsync with the constructed options and capture output for progress bar
    eval "rsync $rsync_options \"$source_dir\" \"$dest_dir\" 2>&1" | while IFS= read -r line; do
        # Update progress bar and file info
        update_progress "$line"
    done
    
    # Clear progress bars and file info, then show completion
    clear_progress_bars
    print_success "Backup completed successfully!"
}

# --- Main Script Logic ---

# Check if terminal supports cursor movement
if ! check_command tput >/dev/null 2>&1; then
    print_warning "tput command not found. Progress bar may not display correctly."
fi

# Check if rsync is installed
if ! check_command rsync; then
    print_error "rsync is not installed. Please install it and try again."
    exit 1
fi

# Default values
CONFIG_FILE=""
DRY_RUN=false
VERBOSE=false
EXCLUDE_PATTERNS=()
ADDITIONAL_OPTIONS=()

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -e|--exclude)
            EXCLUDE_PATTERNS+=("$2")
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -o|--option)
            ADDITIONAL_OPTIONS+=("$2")
            shift 2
            ;;
        -*|--*)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# Check if config file is specified
if [ -n "$CONFIG_FILE" ]; then
    # Check if yq is installed
    check_yq
    
    # Process configuration file
    process_config "$CONFIG_FILE"
    exit 0
fi

# Check if source and destination directories are provided
if [ $# -ne 2 ]; then
    print_error "Source and destination directories must be specified."
    print_usage
    exit 1
fi

SOURCE_DIR="$1"
DEST_DIR="$2"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    print_error "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Build rsync options
RSYNC_OPTIONS="-a --progress"

# Add exclude patterns to rsync options
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    RSYNC_OPTIONS="$RSYNC_OPTIONS --exclude=\"$pattern\""
done

# Add additional options to rsync options
for option in "${ADDITIONAL_OPTIONS[@]}"; do
    RSYNC_OPTIONS="$RSYNC_OPTIONS $option"
done

# Add timestamp to backup
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
print_status "Backup started at: $TIMESTAMP"

# Perform the backup
perform_backup "$SOURCE_DIR" "$DEST_DIR" "$RSYNC_OPTIONS"

# Print completion message with timestamp
COMPLETION_TIME=$(date +"%Y-%m-%d %H:%M:%S")
print_success "Backup completed at: $COMPLETION_TIME"

exit 0
