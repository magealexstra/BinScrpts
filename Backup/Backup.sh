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
CLEAR_LINE='\033[2K'    # Clear the entire line
CARRIAGE_RETURN='\r'    # Move cursor to beginning of line

# --- Helper Functions ---

# Draw the progress bar
# Simply updates the current line with the progress bar, no fragments
draw_progress_bar() {
    local percent=$1
    local label=$2
    
    # Calculate bar components
    local bar_size=50
    local filled=$(( percent * bar_size / 100 ))
    local empty=$(( bar_size - filled ))
    
    # Build the bar string first (more efficient than multiple echo calls)
    local bar_filled=""
    local bar_empty=""
    
    for ((i=0; i<filled; i++)); do
        bar_filled="${bar_filled}#"
    done
    
    for ((i=0; i<empty; i++)); do
        bar_empty="${bar_empty} "
    done
    
    # Use printf instead of echo for more consistent behavior across shells
    # \r moves cursor to beginning of line, \033[K clears the line
    printf "\r\033[K${CYAN}%s: [%s%s] %d%%${NC}" "$label" "$bar_filled" "$bar_empty" "$percent"
}

# Update progress based on rsync output
# Processes each line of rsync output to update the progress indicator
update_progress() {
    local line="$1"
    
    # Track if any progress was actually detected
    local progress_detected=false
    
    # Debug output if verbose is enabled
    if [ "$VERBOSE" = true ]; then
        # Print debug info on new lines
        echo
        echo "$line"
    fi
    
    # For rsync stats output, extract bytes transferred and total bytes
    if [[ "$line" =~ ([0-9,]+)/([0-9,]+) ]]; then
        local current=$(echo "${BASH_REMATCH[1]}" | tr -d ',')
        local total=$(echo "${BASH_REMATCH[2]}" | tr -d ',')
        
        if [[ "$current" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [ "$total" -gt 0 ]; then
            local percent=$(( current * 100 / total ))
            progress_detected=true
            
            # Save for final display and future reference
            FINAL_PROGRESS_PERCENTAGE=$percent
            CURRENT_PROGRESS_BAR="Overall Progress: [$percent%]"
            
            # Update the progress display (single line only)
            draw_progress_bar $percent "Overall Progress"
        fi
    # For simple percentage format like " 45%" or "45%"
    elif [[ "$line" =~ \ *([0-9]+)% ]]; then
        local percent="${BASH_REMATCH[1]}"
        if [[ "$percent" =~ ^[0-9]+$ ]]; then
            progress_detected=true
            
            # Save for final display
            FINAL_PROGRESS_PERCENTAGE=$percent
            
            # Update the progress display (single line only)
            draw_progress_bar $percent "Overall Progress"
        fi
    # For completed files (containing xfr# pattern)
    elif [[ "$line" =~ xfr#([0-9]+) ]]; then
        # Save overall progress - we've completed a file
        TRANSFERRED_FILES=$(( TRANSFERRED_FILES + 1 ))
        if [ "$TOTAL_FILES" -gt 0 ]; then
            local percent=$(( TRANSFERRED_FILES * 100 / TOTAL_FILES ))
            progress_detected=true
            
            # Save for final display
            FINAL_PROGRESS_PERCENTAGE=$percent
            
            # Update the progress display (single line only)
            draw_progress_bar $percent "Overall Progress"
        fi
    # If we're getting bytes information but couldn't calculate a percentage,
    # show an indeterminate progress
    elif ! $progress_detected && [[ "$line" =~ ([0-9,]+)\ +bytes ]]; then
        # Show pulsing progress bar
        PULSE_STATE=$(( (PULSE_STATE + 1) % 4 ))
        case $PULSE_STATE in
            0) PULSE_CHAR="|" ;;
            1) PULSE_CHAR="/" ;;
            2) PULSE_CHAR="-" ;;
            3) PULSE_CHAR="\\" ;;
        esac
        
        # Show the pulsing indicator (single line only)
        printf "\r\033[KTransferring... %s " "$PULSE_CHAR"
    fi
}

# Show final progress bar that persists
# This creates a static progress bar that remains visible after program exit
show_final_progress_bar() {
    local percent=$1
    
    # If percent is not provided, default to 100%
    if [ -z "$percent" ]; then
        percent=100
    fi
    
    # Print an empty line before the final progress bar
    echo
    
    # Calculate bar components
    local bar_size=50
    local filled=$(( percent * bar_size / 100 ))
    local empty=$(( bar_size - filled ))
    
    # Build the bar string first
    local bar_filled=""
    local bar_empty=""
    
    for ((i=0; i<filled; i++)); do
        bar_filled="${bar_filled}#"
    done
    
    for ((i=0; i<empty; i++)); do
        bar_empty="${bar_empty} "
    done
    
    # Print the entire progress bar on a single line
    echo -e "${CYAN}Final Overall Progress: [${bar_filled}${bar_empty}] ${percent}%${NC}"
    
    # Print an empty line after the final progress bar
    echo
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
        if [[ "$bytes" =~ ^[0-9]+$ ]]; then
            total_bytes=$(( total_bytes + bytes ))
        fi
    done
    
    # Make sure we return a number, even if it's 0
    if [[ ! "$total_bytes" =~ ^[0-9]+$ ]]; then
        total_bytes=1  # Default to 1 to avoid division by zero
    fi
    
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
        print_error "yq is not installed. Please install it."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            print_error "Please install it with 'sudo apt-get install -y yq' and try again."
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            print_error "Please install it with 'brew install yq' and try again."
        else
            print_error "Please install it and try again."
        fi
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
    destination=$(read_yaml "$config_file" ".destination" "")
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
    
    # Initialize global variables for progress tracking
    FINAL_PROGRESS_PERCENTAGE=0
    TOTAL_FILES=0
    TRANSFERRED_FILES=0
    CURRENT_PROGRESS_BAR=""
    
    # Calculate total size of all files to be transferred
    TOTAL_BYTES_TO_TRANSFER=$(calculate_total_size "$config_file")
    
    if [[ "$TOTAL_BYTES_TO_TRANSFER" =~ ^[0-9]+$ ]]; then
        print_status "Total size to transfer: $(numfmt --to=iec-i --suffix=B $TOTAL_BYTES_TO_TRANSFER)"
    else
        print_status "Total size to transfer: calculating..."
        TOTAL_BYTES_TO_TRANSFER=1  # Default to 1 to avoid division by zero
    fi
    
    # Build rsync options with enhanced progress display
    RSYNC_OPTIONS="-a --progress --info=progress2,stats"
    
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
        
        # Initialize progress display variables
        PULSE_STATE=0
        
        # Create a temporary file for rsync output
        local rsync_output=$(mktemp /tmp/rsync_output.XXXXXX)
        
        # Run rsync in the background, capturing its output to the temp file
        eval "$backup_cmd > \"$rsync_output\" 2>&1" &
        local rsync_pid=$!
        
        # Monitor the output file and update the progress bar
        while kill -0 $rsync_pid 2>/dev/null; do
            if [[ -s "$rsync_output" ]]; then
                # Get the latest line and process it
                local latest_line=$(tail -n 1 "$rsync_output")
                update_progress "$latest_line"
            fi
            # Sleep briefly to avoid hammering the CPU
            sleep 0.1
        done
        
        # Wait for rsync to finish and get its exit status
        wait $rsync_pid
        local rsync_status=$?
        
        # Process the output one more time to get the final status
        if [[ -s "$rsync_output" ]]; then
            local final_line=$(tail -n 1 "$rsync_output")
            update_progress "$final_line"
        fi
        
        # Clean up the temporary file
        rm -f "$rsync_output"
        
        # Display final progress bar after backup completes
        echo
        show_final_progress_bar $FINAL_PROGRESS_PERCENTAGE
        
        # Check if the backup was successful
        if [ $rsync_status -eq 0 ]; then
            echo "✓ Backup of $source_name completed successfully"
        else
            echo "✗ Backup of $source_name failed with error code $rsync_status"
        fi
        echo
    done
    
    echo "=========================================================="
    echo "  BACKUP PROCESS COMPLETED"
    echo "  Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================================="
    
    # Display final progress bar at 100% to indicate completion
    show_final_progress_bar 100
    
    exit 0
}

# --- Backup Function ---
perform_backup() {
    local source_dir="$1"
    local dest_dir="$2"
    local rsync_options="$3"
    
    # Initialize global variables for progress tracking
    FINAL_PROGRESS_PERCENTAGE=0
    TOTAL_FILES=0
    TRANSFERRED_FILES=0
    CURRENT_PROGRESS_BAR=""
    
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
    
    # Always add info flag for enhanced progress updates
    rsync_options="$rsync_options --info=progress2,stats"
    
    # If verbose is true, we'll still capture all output but display it differently
    if [ "$VERBOSE" = true ]; then
        rsync_options="$rsync_options -v"
    fi
    
    # Make sure we have progress info for the progress bar
    if [[ "$rsync_options" != *"--progress"* ]]; then
        rsync_options="$rsync_options --progress"
    fi
    
    # Initialize progress display variables
    PULSE_STATE=0
    
    # Create a temporary file for rsync output
    local rsync_output=$(mktemp /tmp/rsync_output.XXXXXX)
    
    # Run rsync in the background, capturing its output to the temp file
    eval "rsync $rsync_options \"$source_dir\" \"$dest_dir\" > \"$rsync_output\" 2>&1" &
    local rsync_pid=$!
    
    # Monitor the output file and update the progress bar
    while kill -0 $rsync_pid 2>/dev/null; do
        if [[ -s "$rsync_output" ]]; then
            # Get the latest line and process it
            local latest_line=$(tail -n 1 "$rsync_output")
            update_progress "$latest_line"
        fi
        # Sleep briefly to avoid hammering the CPU
        sleep 0.1
    done
    
    # Wait for rsync to finish and get its exit status
    wait $rsync_pid
    local rsync_status=$?
    
    # Process the output one more time to get the final status
    if [[ -s "$rsync_output" ]]; then
        local final_line=$(tail -n 1 "$rsync_output")
        update_progress "$final_line"
    fi
    
    # Clean up the temporary file
    rm -f "$rsync_output"
    
    # Display final progress bar after backup completes
    echo
    show_final_progress_bar $FINAL_PROGRESS_PERCENTAGE
    
    if [ $rsync_status -eq 0 ]; then
        print_success "Backup completed successfully!"
    else
        print_error "Backup failed with error code $rsync_status"
    fi
    
    # Return the rsync status
    return $rsync_status
}

# --- Main Script Logic ---

# Check if terminal has required capabilities for progress display
if ! check_command stty >/dev/null 2>&1; then
    print_warning "stty command not found. Progress bar may not display correctly."
    exit 1
fi

# Check if rsync is installed
if ! check_command rsync; then
    print_error "rsync is not installed. Please install it and try again."
    exit 1
fi

# Check if stdbuf is installed (needed for progress bar handling)
if ! check_command stdbuf; then
    print_warning "stdbuf command not found. Progress bar may not display correctly."
    print_warning "Install coreutils package to get stdbuf: 'sudo apt install coreutils' on Debian/Ubuntu"
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

# Display final progress bar at 100% to indicate completion
show_final_progress_bar 100

exit 0
