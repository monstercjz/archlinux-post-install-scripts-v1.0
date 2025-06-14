#!/usr/bin/env bash

# arch_backup.sh - Advanced Arch Linux System Backup and Restore Script
# Version: 1.0.0
# Author: Your Name/AI
# License: MIT

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# === Script Information ===
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# === Global Variables (Defaults, will be overridden by config) ===
CONF_BACKUP_ROOT_DIR=""
CONF_LOG_FILE="/tmp/${SCRIPT_NAME}.log"
CONF_LOG_LEVEL="INFO" # DEBUG, INFO, WARN, ERROR

CONF_BACKUP_SYSTEM_CONFIG="true"
CONF_BACKUP_USER_DATA="true"
CONF_BACKUP_PACKAGES="true"
CONF_BACKUP_LOGS="true"
CONF_BACKUP_CUSTOM_PATHS="true"

CONF_USER_HOME_INCLUDE=(".config" ".local/share" ".ssh" ".gnupg" ".bashrc")
CONF_USER_HOME_EXCLUDE=("*/.cache/*" "*/Cache/*")

CONF_CUSTOM_PATHS_INCLUDE=()
CONF_CUSTOM_PATHS_EXCLUDE=()

CONF_SYSTEM_LOG_FILES=("pacman.log" "Xorg.0.log")
CONF_BACKUP_JOURNALCTL="true"
CONF_JOURNALCTL_ARGS=""

CONF_INCREMENTAL_BACKUP="true"
CONF_COMPRESSION_ENABLE="true"
CONF_COMPRESSION_METHOD="xz"
CONF_COMPRESSION_LEVEL="6"
CONF_COMPRESSION_EXT="tar.xz"

CONF_RETENTION_UNCOMPRESSED_COUNT="3"
CONF_RETENTION_COMPRESSED_COUNT="10"
CONF_RETENTION_COMPRESSED_DAYS="90"

CONF_PARALLEL_JOBS="1"
CONF_PROMPT_FOR_CONFIRMATION="true"
CONF_MIN_FREE_DISK_SPACE_PERCENT="10"

# Runtime variables
CURRENT_TIMESTAMP=""
BACKUP_TARGET_DIR_UNCOMPRESSED="" # Full path to current uncompressed backup destination
BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES="" # Directory for compressed archives
EFFECTIVE_UID=$(id -u)
EFFECTIVE_USER=$(id -un)
ORIGINAL_USER="${SUDO_USER:-$USER}"
ORIGINAL_UID="${SUDO_UID:-$UID}"
ORIGINAL_GID="${SUDO_GID:-$GID}"
ORIGINAL_HOME=""

# For parallel execution
PARALLEL_CMD=""

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
declare -A LOG_LEVEL_NAMES=([0]="DEBUG" [1]="INFO" [2]="WARN" [3]="ERROR")
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} # Default, will be set by config

# Colors for terminal output
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

# === Helper Functions ===

# Logging function
# Usage: log_msg INFO "This is an info message"
#        log_msg ERROR "This is an error message"
log_msg() {
    local level_name="$1"
    local message="$2"
    local level_num

    case "$level_name" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO  ;;
        WARN)  level_num=$LOG_LEVEL_WARN  ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *)     level_num=$LOG_LEVEL_INFO; message="[INVALID LOG LEVEL] $message" ;;
    esac

    if [[ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]]; then
        local color="$COLOR_RESET"
        [[ "$level_name" == "ERROR" ]] && color="$COLOR_RED"
        [[ "$level_name" == "WARN" ]]  && color="$COLOR_YELLOW"
        [[ "$level_name" == "INFO" ]]  && color="$COLOR_GREEN" # Or just default
        [[ "$level_name" == "DEBUG" ]] && color="$COLOR_CYAN"

        # Terminal output
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${color}${level_name}${COLOR_RESET}] $message" | tee -a "$CONF_LOG_FILE"
    else
        # Still log to file if it's DEBUG and current level is INFO, for example.
        # This part ensures all messages go to file if file logging is generally on.
        # For simplicity now, let's just use the above check for both.
        # If fine-grained control is needed, this could be expanded.
        :
    fi
}

# Confirmation prompt
# Usage: confirm_action "Delete old backups?" && echo "Deleting..."
confirm_action() {
    local prompt_message="$1"
    if [[ "$CONF_PROMPT_FOR_CONFIRMATION" != "true" ]]; then
        log_msg INFO "Auto-confirming action due to CONF_PROMPT_FOR_CONFIRMATION=false: $prompt_message"
        return 0 # True (yes)
    fi

    while true; do
        read -r -p "$prompt_message [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;; # True
            [nN][oO]|[nN]|"") return 1 ;; # False
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# Check for required dependencies
# Usage: check_dependencies rsync tar gzip xz
check_dependencies() {
    local missing_deps=0
    for dep in "$@"; do
        if ! command -v "$dep" &>/dev/null; then
            log_msg ERROR "Required dependency '$dep' is not installed."
            missing_deps=1
        else
            # Optional: version check (more complex, add if critical)
            # local version=$(rsync --version | head -n1)
            # log_msg DEBUG "'$dep' found. Version: $version"
            :
        fi
    done
    if [[ "$missing_deps" -eq 1 ]]; then
        log_msg ERROR "Please install missing dependencies and try again."
        log_msg INFO "On Arch Linux, you can typically install them with: sudo pacman -S <package_name>"
        exit 1
    fi
    log_msg DEBUG "All core dependencies present: $@"
}

# Get original user's home directory
get_original_user_home() {
    if [[ -n "$SUDO_USER" ]]; then
        ORIGINAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        ORIGINAL_HOME="$HOME"
    fi
    if [[ ! -d "$ORIGINAL_HOME" ]]; then
        log_msg ERROR "Could not determine or access original user's home directory: $ORIGINAL_HOME"
        exit 1
    fi
}

# === Configuration Loading ===
load_config() {
    local config_file_paths=(
        "${HOME}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
        "${HOME}/.config/arch_backup.conf" # For this specific request
        "/etc/$(basename "$SCRIPT_NAME" .sh).conf"
        "/etc/arch_backup.conf"
    )
    local loaded_config_file=""

    get_original_user_home # Ensure ORIGINAL_HOME is set

    # Adjust home-based path if running with sudo
    if [[ -n "$SUDO_USER" ]]; then
      config_file_paths=(
          "${ORIGINAL_HOME}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
          "${ORIGINAL_HOME}/.config/arch_backup.conf"
          "/etc/$(basename "$SCRIPT_NAME" .sh).conf"
          "/etc/arch_backup.conf"
      )
    fi


    for cf_path in "${config_file_paths[@]}"; do
        if [[ -f "$cf_path" ]]; then
            log_msg INFO "Loading configuration from: $cf_path"
            # shellcheck source=/dev/null
            source "$cf_path"
            loaded_config_file="$cf_path"
            break
        fi
    done

    if [[ -z "$loaded_config_file" ]]; then
        log_msg WARN "No configuration file found. Using default settings. Searched in:"
        for cf_path in "${config_file_paths[@]}"; do
             log_msg WARN "  - $cf_path"
        done
    fi

    # Set log level from config
    case "${CONF_LOG_LEVEL^^}" in # Convert to uppercase
        DEBUG) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        INFO)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO  ;;
        WARN)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN  ;;
        ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *)     log_msg WARN "Invalid CONF_LOG_LEVEL '${CONF_LOG_LEVEL}'. Defaulting to INFO."
               CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac

    # Ensure log file dir exists and set permissions if we created it
    local log_dir
    log_dir=$(dirname "$CONF_LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
        if [[ "$EFFECTIVE_UID" -eq 0 && -n "$SUDO_USER" ]]; then
            chown "$ORIGINAL_UID:$ORIGINAL_GID" "$log_dir"
        fi
    fi
    # Touch log file and set permissions
    touch "$CONF_LOG_FILE"
    if [[ "$EFFECTIVE_UID" -eq 0 && -n "$SUDO_USER" ]]; then
        chown "$ORIGINAL_UID:$ORIGINAL_GID" "$CONF_LOG_FILE"
    fi

    # Validate critical configurations
    if [[ -z "$CONF_BACKUP_ROOT_DIR" ]]; then
        log_msg ERROR "CONF_BACKUP_ROOT_DIR is not set. Please configure it."
        exit 1
    fi
    mkdir -p "$CONF_BACKUP_ROOT_DIR" # Ensure base backup dir exists
    BACKUP_TARGET_DIR_UNCOMPRESSED="${CONF_BACKUP_ROOT_DIR}/snapshots"
    BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES="${CONF_BACKUP_ROOT_DIR}/archives"
    mkdir -p "$BACKUP_TARGET_DIR_UNCOMPRESSED"
    mkdir -p "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES"

    # Set compression extension based on method if not explicitly set right
    case "$CONF_COMPRESSION_METHOD" in
        gzip) CONF_COMPRESSION_EXT="tar.gz" ;;
        bzip2) CONF_COMPRESSION_EXT="tar.bz2" ;;
        xz) CONF_COMPRESSION_EXT="tar.xz" ;;
        *) log_msg WARN "Unknown compression method '$CONF_COMPRESSION_METHOD'. Archiving might fail.";;
    esac

    # Check for GNU Parallel if jobs > 1
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 ]]; then
        if command -v parallel &>/dev/null; then
            PARALLEL_CMD="parallel --no-notice --jobs $CONF_PARALLEL_JOBS --halt soon,fail=1"
            log_msg INFO "GNU Parallel found. Will use $CONF_PARALLEL_JOBS parallel jobs."
        else
            log_msg WARN "GNU Parallel not found, but CONF_PARALLEL_JOBS > 1. Falling back to sequential execution."
            CONF_PARALLEL_JOBS=1 # Force sequential
            PARALLEL_CMD=""
        fi
    else
        PARALLEL_CMD="" # Sequential execution
    fi
}

# Check disk space
check_disk_space() {
    local path_to_check="$1"
    local required_percent="$2"
    local available_space
    available_space=$(df --output=pcent "$path_to_check" | tail -n 1 | sed 's/%//' | xargs) # Get used percentage
    local free_space_percent=$((100 - available_space))

    if [[ "$free_space_percent" -lt "$required_percent" ]]; then
        log_msg ERROR "Insufficient free disk space on '$path_to_check'. Available: ${free_space_percent}%, Required: ${required_percent}%."
        exit 1
    else
        log_msg INFO "Disk space check passed for '$path_to_check'. Available: ${free_space_percent}%."
    fi
}


# === Backup Functions ===

# Generic rsync backup function
# $1: Backup task name (for logging)
# $2: Destination sub-directory name (e.g., "etc", "home_user")
# $3: Link-dest option string (e.g., "--link-dest=../previous_backup/") or empty
# $4+: Array of source paths
_perform_rsync_backup() {
    local task_name="$1"
    local dest_subdir_name="$2"
    local link_dest_opt="$3"
    shift 3
    local sources=("$@")
    local rsync_dest_path="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/${dest_subdir_name}/"

    mkdir -p "$rsync_dest_path"

    local rsync_opts=(
        "-aH"  # archive mode, hard links
        "--delete" # delete files in dest that are not in source
        "--numeric-ids" # preserve UIDs/GIDs numerically
        "--info=progress2" # Show progress
        # Consider adding: --exclude-from=FILE or more --exclude patterns if needed per task
    )
    [[ -n "$link_dest_opt" ]] && rsync_opts+=("$link_dest_opt")

    log_msg INFO "Starting backup for: $task_name"
    # Create exclude file for user home if needed
    local user_exclude_file=""
    if [[ "$task_name" == "User Data" && ${#CONF_USER_HOME_EXCLUDE[@]} -gt 0 ]]; then
        user_exclude_file=$(mktemp)
        printf "%s\n" "${CONF_USER_HOME_EXCLUDE[@]}" > "$user_exclude_file"
        rsync_opts+=("--exclude-from=$user_exclude_file")
    fi
    
    local custom_exclude_file=""
    if [[ "$task_name" == "Custom Paths" && ${#CONF_CUSTOM_PATHS_EXCLUDE[@]} -gt 0 ]]; then
        custom_exclude_file=$(mktemp)
        printf "%s\n" "${CONF_CUSTOM_PATHS_EXCLUDE[@]}" > "$custom_exclude_file"
        rsync_opts+=("--exclude-from=$custom_exclude_file")
    fi

    if rsync "${rsync_opts[@]}" "${sources[@]}" "$rsync_dest_path"; then
        log_msg INFO "Successfully backed up: $task_name"
    else
        log_msg ERROR "Failed to back up: $task_name (rsync exit code: $?)"
        # Depending on PARALLEL_CMD, this error might be handled by GNU Parallel's --halt
        # If not using GNU Parallel, we should consider exiting or marking failure.
        # For now, GNU Parallel handles this if used. Otherwise, it logs and continues.
        # This could be made stricter to exit immediately on any rsync failure.
        return 1 # Signal failure
    fi

    [[ -n "$user_exclude_file" ]] && rm -f "$user_exclude_file"
    [[ -n "$custom_exclude_file" ]] && rm -f "$custom_exclude_file"
    return 0
}

backup_system_config() {
    if [[ "$CONF_BACKUP_SYSTEM_CONFIG" != "true" ]]; then log_msg INFO "Skipping system config backup."; return 0; fi
    if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
        log_msg WARN "Skipping system config backup: root privileges required to backup /etc."
        return 1
    fi
    _perform_rsync_backup "System Config (/etc)" "etc" "$1" "/etc/"
}

backup_user_data() {
    if [[ "$CONF_BACKUP_USER_DATA" != "true" ]]; then log_msg INFO "Skipping user data backup."; return 0; fi
    if [[ ${#CONF_USER_HOME_INCLUDE[@]} -eq 0 ]]; then
        log_msg WARN "Skipping user data backup: CONF_USER_HOME_INCLUDE is empty."
        return 0
    fi

    local user_sources=()
    for item in "${CONF_USER_HOME_INCLUDE[@]}"; do
        user_sources+=("${ORIGINAL_HOME}/${item}")
    done
    _perform_rsync_backup "User Data" "home_${ORIGINAL_USER}" "$1" "${user_sources[@]}"
}

backup_packages() {
    if [[ "$CONF_BACKUP_PACKAGES" != "true" ]]; then log_msg INFO "Skipping package list backup."; return 0; fi
    log_msg INFO "Backing up package lists..."
    local pkg_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/packages/"
    mkdir -p "$pkg_dest_dir"

    pacman -Qqe > "${pkg_dest_dir}/packages_official.list"
    pacman -Qqm > "${pkg_dest_dir}/packages_aur_foreign.list"
    # Optional: Full package info with versions
    pacman -Q > "${pkg_dest_dir}/packages_all_versions.list"

    log_msg INFO "Package lists backed up to $pkg_dest_dir"
}

backup_logs() {
    if [[ "$CONF_BACKUP_LOGS" != "true" ]]; then log_msg INFO "Skipping system logs backup."; return 0; fi
    log_msg INFO "Backing up system logs..."
    local logs_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/logs/"
    mkdir -p "$logs_dest_dir"

    if [[ "$CONF_BACKUP_JOURNALCTL" == "true" ]]; then
        if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
            log_msg WARN "Skipping journalctl backup: root privileges may be required for full journal access."
        fi
        # shellcheck disable=SC2086 # Allow word splitting for CONF_JOURNALCTL_ARGS
        journalctl ${CONF_JOURNALCTL_ARGS} > "${logs_dest_dir}/journal.log" \
            || log_msg WARN "Failed to backup journalctl (non-critical)."
    fi

    if [[ "$EFFECTIVE_UID" -ne 0 && ${#CONF_SYSTEM_LOG_FILES[@]} -gt 0 ]]; then
         log_msg WARN "Skipping /var/log/* backup: root privileges required."
    elif [[ ${#CONF_SYSTEM_LOG_FILES[@]} -gt 0 ]]; then
        for log_file in "${CONF_SYSTEM_LOG_FILES[@]}"; do
            if [[ -e "/var/log/${log_file}" ]]; then
                cp -a "/var/log/${log_file}" "${logs_dest_dir}/" || log_msg WARN "Failed to copy log ${log_file} (non-critical)."
            else
                log_msg WARN "Log file /var/log/${log_file} not found."
            fi
        done
    fi
    log_msg INFO "System logs backed up to $logs_dest_dir"
}

backup_custom_paths() {
    if [[ "$CONF_BACKUP_CUSTOM_PATHS" != "true" ]]; then log_msg INFO "Skipping custom paths backup."; return 0; fi
    if [[ ${#CONF_CUSTOM_PATHS_INCLUDE[@]} -eq 0 ]]; then
        log_msg WARN "Skipping custom paths backup: CONF_CUSTOM_PATHS_INCLUDE is empty."
        return 0
    fi

    # Check if any custom path requires root
    local needs_root=0
    for path in "${CONF_CUSTOM_PATHS_INCLUDE[@]}"; do
        if [[ ! -r "$path" ]]; then # Simple readability check
             if sudo -n true 2>/dev/null; then # Can we sudo without password?
                if ! sudo test -r "$path"; then
                    log_msg WARN "Custom path '$path' might be unreadable even with sudo."
                fi
             elif [[ "$EFFECTIVE_UID" -ne 0 ]]; then
                needs_root=1
                break
             fi
        fi
    done

    if [[ "$needs_root" -eq 1 && "$EFFECTIVE_UID" -ne 0 ]]; then
        log_msg WARN "Skipping some/all custom paths: root privileges required for unreadable paths and not running as root."
        # Optionally, could try to backup accessible paths only
        return 1
    fi
    _perform_rsync_backup "Custom Paths" "custom" "$1" "${CONF_CUSTOM_PATHS_INCLUDE[@]}"
}

# === Compression and Cleanup ===

compress_and_verify_backup() {
    local uncompressed_dir_path="$1"
    local uncompressed_dir_name
    uncompressed_dir_name=$(basename "$uncompressed_dir_path")
    local archive_path="${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}/${uncompressed_dir_name}.${CONF_COMPRESSION_EXT}"

    if [[ ! -d "$uncompressed_dir_path" ]]; then
        log_msg WARN "Cannot compress: uncompressed directory '$uncompressed_dir_path' not found."
        return 1
    fi
    if [[ -f "$archive_path" ]]; then
        log_msg INFO "Archive '$archive_path' already exists. Skipping compression for '$uncompressed_dir_name'."
        return 0 # Or 2 if we want to signal it existed
    fi

    log_msg INFO "Compressing backup: $uncompressed_dir_name to $archive_path"
    local tar_opts=""
    local comp_cmd=""
    local comp_test_cmd=""

    case "$CONF_COMPRESSION_METHOD" in
        gzip)  tar_opts="-czf"; comp_cmd="gzip -${CONF_COMPRESSION_LEVEL}"; comp_test_cmd="gzip -t" ;;
        bzip2) tar_opts="-cjf"; comp_cmd="bzip2 -${CONF_COMPRESSION_LEVEL}"; comp_test_cmd="bzip2 -t" ;;
        xz)    tar_opts="-cJf"; comp_cmd="xz -${CONF_COMPRESSION_LEVEL} -T0"; comp_test_cmd="xz -t" ;; # -T0 for auto threads
        *) log_msg ERROR "Unsupported compression method: $CONF_COMPRESSION_METHOD"; return 1 ;;
    esac

    # Using tar's built-in compression for simplicity and atomicity
    # We cd into parent of dir_to_compress to avoid full paths in tar archive
    if (cd "$(dirname "$uncompressed_dir_path")" && tar "$tar_opts" "$archive_path" "$uncompressed_dir_name"); then
        log_msg INFO "Successfully compressed: $uncompressed_dir_name"

        log_msg INFO "Verifying archive: $archive_path"
        if $comp_test_cmd "$archive_path"; then
            log_msg INFO "Archive '$archive_path' verified successfully."
            if confirm_action "Delete uncompressed directory '$uncompressed_dir_path' after compression?"; then
                log_msg INFO "Deleting uncompressed directory: $uncompressed_dir_path"
                rm -rf "$uncompressed_dir_path"
            else
                log_msg INFO "Keeping uncompressed directory: $uncompressed_dir_path"
            fi
        else
            log_msg ERROR "Archive verification FAILED for '$archive_path'. Keeping uncompressed directory."
            rm -f "$archive_path" # Delete corrupted archive
            return 1
        fi
    else
        log_msg ERROR "Compression FAILED for '$uncompressed_dir_name'."
        rm -f "$archive_path" # Delete potentially partial archive
        return 1
    fi
    return 0
}

cleanup_backups() {
    log_msg INFO "Starting backup cleanup..."

    # 1. Cleanup Uncompressed Snapshots (Retain N newest)
    if [[ "$CONF_RETENTION_UNCOMPRESSED_COUNT" -gt 0 ]]; then
        log_msg INFO "Cleaning up uncompressed snapshots. Retaining last $CONF_RETENTION_UNCOMPRESSED_COUNT."
        local uncompressed_snapshots
        uncompressed_snapshots=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr)

        local count=0
        local snapshots_to_compress_or_delete=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local snap_path
            snap_path=$(echo "$line" | cut -d' ' -f2-)
            count=$((count + 1))
            if [[ "$count" -gt "$CONF_RETENTION_UNCOMPRESSED_COUNT" ]]; then
                snapshots_to_compress_or_delete+=("$snap_path")
            fi
        done <<< "$uncompressed_snapshots"

        for snap_path_to_process in "${snapshots_to_compress_or_delete[@]}"; do
            if [[ "$CONF_COMPRESSION_ENABLE" == "true" ]]; then
                log_msg INFO "Snapshot '$snap_path_to_process' is older than retention count. Attempting compression."
                compress_and_verify_backup "$snap_path_to_process" # This function handles deletion if successful
            else
                if confirm_action "CONF_COMPRESSION_ENABLE is false. Delete old uncompressed snapshot '$snap_path_to_process' permanently?"; then
                    log_msg INFO "Deleting old uncompressed snapshot: $snap_path_to_process"
                    rm -rf "$snap_path_to_process"
                else
                    log_msg INFO "Keeping old uncompressed snapshot: $snap_path_to_process"
                fi
            fi
        done
    else
        log_msg INFO "Skipping cleanup of uncompressed snapshots (CONF_RETENTION_UNCOMPRESSED_COUNT is 0 or less)."
    fi

    # 2. Cleanup Compressed Archives
    log_msg INFO "Cleaning up compressed archives..."
    local archives_to_delete=()

    # By Age
    if [[ "$CONF_RETENTION_COMPRESSED_DAYS" -gt 0 ]]; then
        log_msg INFO "Looking for compressed archives older than $CONF_RETENTION_COMPRESSED_DAYS days."
        # find ... -mtime +N means files modified more than N*24 hours ago.
        # N should be CONF_RETENTION_COMPRESSED_DAYS - 1 for "older than X days"
        local days_for_find=$((CONF_RETENTION_COMPRESSED_DAYS -1))
        if [[ $days_for_find -lt 0 ]]; then days_for_find=0; fi # ensure non-negative

        while IFS= read -r archive_file; do
            [[ -z "$archive_file" ]] && continue
            archives_to_delete+=("$archive_file")
            log_msg DEBUG "Marked for deletion (by age): $archive_file"
        done < <(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -mtime "+${days_for_find}")
    fi

    # By Count (if count is set and more archives exist than desired count, after age filtering)
    if [[ "$CONF_RETENTION_COMPRESSED_COUNT" -gt 0 ]]; then
        log_msg INFO "Checking compressed archive count. Retaining max $CONF_RETENTION_COMPRESSED_COUNT."
        local current_archives
        # Get all archives, sorted oldest first, excluding those already marked by age
        current_archives=$(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -printf "%T@ %p\n" | sort -n)
        
        local total_archives_found=0
        local archives_not_marked_for_age_deletion=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            total_archives_found=$((total_archives_found + 1))
            local arc_path
            arc_path=$(echo "$line" | cut -d' ' -f2-)
            
            # Check if this archive is already in archives_to_delete
            local already_marked=0
            for marked_arc in "${archives_to_delete[@]}"; do
                if [[ "$marked_arc" == "$arc_path" ]]; then
                    already_marked=1
                    break
                fi
            done
            if [[ "$already_marked" -eq 0 ]]; then
                archives_not_marked_for_age_deletion+=("$arc_path")
            fi
        done <<< "$current_archives"

        local num_to_delete_by_count=0
        num_to_delete_by_count=$((${#archives_not_marked_for_age_deletion[@]} - CONF_RETENTION_COMPRESSED_COUNT))

        if [[ "$num_to_delete_by_count" -gt 0 ]]; then
            log_msg INFO "Need to delete $num_to_delete_by_count oldest archives to meet retention count."
            # Add the oldest ones from archives_not_marked_for_age_deletion to archives_to_delete
            for ((i=0; i<num_to_delete_by_count; i++)); do
                archives_to_delete+=("${archives_not_marked_for_age_deletion[i]}")
                log_msg DEBUG "Marked for deletion (by count): ${archives_not_marked_for_age_deletion[i]}"
            done
        fi
    fi
    
    # Remove duplicates from archives_to_delete (if any item got marked by both age and count logic)
    local unique_archives_to_delete
    unique_archives_to_delete=$(printf "%s\n" "${archives_to_delete[@]}" | sort -u)

    if [[ -z "$unique_archives_to_delete" ]]; then
        log_msg INFO "No compressed archives marked for deletion."
    else
        log_msg INFO "The following compressed archives will be deleted:"
        echo "$unique_archives_to_delete" # Shows the list
        if confirm_action "Proceed with deleting these $(echo "$unique_archives_to_delete" | wc -l) compressed archive(s)?"; then
            while IFS= read -r archive_to_delete; do
                [[ -z "$archive_to_delete" ]] && continue
                log_msg INFO "Deleting compressed archive: $archive_to_delete"
                rm -f "$archive_to_delete"
            done <<< "$unique_archives_to_delete"
        else
            log_msg INFO "Deletion of old compressed archives cancelled by user."
        fi
    fi
    log_msg INFO "Backup cleanup finished."
}


# === Main Backup Orchestration ===
run_backup() {
    log_msg INFO "Starting Arch Linux Backup (Version $SCRIPT_VERSION)"
    CURRENT_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    local current_backup_path_uncompressed="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}"
    mkdir -p "$current_backup_path_uncompressed"
    log_msg INFO "Current backup destination (uncompressed): $current_backup_path_uncompressed"

    check_disk_space "$CONF_BACKUP_ROOT_DIR" "$CONF_MIN_FREE_DISK_SPACE_PERCENT"

    local link_dest_option=""
    if [[ "$CONF_INCREMENTAL_BACKUP" == "true" ]]; then
        # Find the latest existing uncompressed snapshot directory (chronologically)
        local latest_snapshot_dir
        latest_snapshot_dir=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d ! -name "$CURRENT_TIMESTAMP" -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)

        if [[ -n "$latest_snapshot_dir" && -d "$latest_snapshot_dir" ]]; then
            # Use relative path for link-dest for portability if backup root is moved
            local relative_link_dest
            relative_link_dest="../$(basename "$latest_snapshot_dir")"
            link_dest_option="--link-dest=$relative_link_dest" # rsync resolves this from its destination
            log_msg INFO "Incremental backup enabled. Using '$latest_snapshot_dir' as base via $link_dest_option."
        else
            log_msg INFO "Incremental backup enabled, but no previous snapshot found. Performing full backup."
        fi
    else
        log_msg INFO "Incremental backup disabled. Performing full backup."
    fi

    # Prepare list of backup tasks (functions)
    # Format: "function_name parameter_for_link_dest"
    # Parameter is the link_dest_option determined above.
    # It must be quoted if it contains spaces or special characters for `eval` or command substitution.
    local backup_tasks=()
    [[ "$CONF_BACKUP_SYSTEM_CONFIG" == "true" ]] && backup_tasks+=("backup_system_config \"$link_dest_option\"")
    [[ "$CONF_BACKUP_USER_DATA" == "true" ]] && backup_tasks+=("backup_user_data \"$link_dest_option\"")
    [[ "$CONF_BACKUP_PACKAGES" == "true" ]] && backup_tasks+=("backup_packages") # No rsync, no link-dest
    [[ "$CONF_BACKUP_LOGS" == "true" ]] && backup_tasks+=("backup_logs") # No rsync, no link-dest
    [[ "$CONF_BACKUP_CUSTOM_PATHS" == "true" ]] && backup_tasks+=("backup_custom_paths \"$link_dest_option\"")

    if [[ ${#backup_tasks[@]} -eq 0 ]]; then
        log_msg WARN "No backup categories enabled. Nothing to do."
        rm -rf "$current_backup_path_uncompressed" # Clean up empty timestamp dir
        return 0
    fi

    local overall_backup_success="true"
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 && -n "$PARALLEL_CMD" ]]; then
        log_msg INFO "Running backup tasks in parallel..."
        # Pass each task as a command string to GNU Parallel
        # Each task function must handle its own errors and log them.
        # GNU Parallel's --halt soon,fail=1 will stop if any job fails.
        # This requires tasks to exit non-zero on failure.
        printf "%s\n" "${backup_tasks[@]}" | $PARALLEL_CMD {} || overall_backup_success="false"
    else
        log_msg INFO "Running backup tasks sequentially..."
        for task_cmd in "${backup_tasks[@]}"; do
            # Using eval carefully here because task_cmd can contain quotes for arguments
            if ! eval "$task_cmd"; then
                overall_backup_success="false"
                log_msg ERROR "Task '$task_cmd' failed. Subsequent tasks might be affected."
                # Decide: continue or abort? For now, continue to attempt other backups.
                # If strict error handling is needed, add 'exit 1' here or make _perform_rsync_backup exit.
            fi
        done
    fi

    if [[ "$overall_backup_success" == "false" ]]; then
        log_msg ERROR "One or more backup tasks failed. The backup at $current_backup_path_uncompressed may be incomplete."
        # Optionally, delete the failed backup attempt:
        # if confirm_action "Delete incomplete backup directory $current_backup_path_uncompressed?"; then
        #    rm -rf "$current_backup_path_uncompressed"
        #    log_msg INFO "Incomplete backup deleted."
        # fi
        # exit 1 # Exit with error if any part failed
    else
        log_msg INFO "All backup tasks completed successfully for $CURRENT_TIMESTAMP."
        # Basic validation: check if backup directory is non-empty
        if [ -z "$(ls -A "$current_backup_path_uncompressed")" ]; then
            log_msg WARN "Backup directory $current_backup_path_uncompressed is empty. This might indicate an issue."
        else
            log_msg INFO "Basic validation: backup directory $current_backup_path_uncompressed is not empty."
            # Here you could add more complex validation, like checking for specific marker files.
        fi
    fi

    # Cleanup old backups (this also handles compressing backups that are older than uncompressed retention)
    cleanup_backups

    log_msg INFO "Arch Linux Backup finished for $CURRENT_TIMESTAMP."
    # If overall_backup_success is false, script will exit with error due to set -e if a command failed
    # or we can explicitly exit 1 if we tracked the failure.
    if [[ "$overall_backup_success" == "false" ]]; then
        return 1
    fi
    return 0
}


# === Script Entry Point ===
main() {
    # Ensure script is not run as root unless necessary for /etc, /var/log
    # This check is more informational as specific functions handle privileges.
    if [[ "$EFFECTIVE_UID" -eq 0 && -z "$SUDO_USER" ]]; then
        log_msg WARN "Running as root directly. Consider using sudo if user-specific backups are intended."
    fi

    # Load config first to get log path and level
    load_config # This also sets CURRENT_LOG_LEVEL and initializes log file

    # Now that logging is configured, check dependencies
    local required_system_deps=("rsync" "tar" "find" "sort" "df" "getent" "cut" "head" "tail" "sed" "grep" "wc" "mkdir" "rm" "id" "date")
    local compression_tool=""
    case "$CONF_COMPRESSION_METHOD" in # Check only the configured compression tool
        gzip)  compression_tool="gzip" ;;
        bzip2) compression_tool="bzip2" ;;
        xz)    compression_tool="xz" ;;
    esac
    [[ -n "$compression_tool" ]] && required_system_deps+=("$compression_tool")
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 ]]; then
        required_system_deps+=("parallel") # GNU Parallel
    fi
    check_dependencies "${required_system_deps[@]}"

    # Actual work
    if run_backup; then
        log_msg INFO "$SCRIPT_NAME completed successfully."
    else
        log_msg ERROR "$SCRIPT_NAME encountered errors."
        exit 1
    fi

    exit 0
}

# Trap for cleanup on exit (e.g. temp files, though not heavily used here yet)
# trap "echo 'Script interrupted. Cleaning up...'; exit 1" SIGINT SIGTERM

# Execute main function
main "$@"