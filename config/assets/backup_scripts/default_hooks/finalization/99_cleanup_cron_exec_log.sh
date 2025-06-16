#!/bin/bash
# ==============================================================================
# Hook Script for arch_backup.sh (Event: finalization)
# File: 99_cleanup_cron_exec_logs.sh
# Description: Cleans old timestamped cron execution logs for arch_backup.sh.
# ==============================================================================

# --- Configuration ---
CRON_EXEC_LOG_DIR="/var/log/arch_backups_logs/arch_system_backup_cron_logs"
LOG_FILENAME_PATTERN="cron_exec_*.log" # 匹配 cron_exec_YYYYMMDD_HHMMSS.log
MAX_CRON_LOGS_TO_KEEP=30 # 例如，保留最近30个 cron 执行日志

CLEANUP_SCRIPT_LOG_PREFIX="[HOOK_CronExecLogCleanup $(date '+%Y-%m-%d %H:%M%S')]"

_hook_log() {
    local level="$1"
    local message="$2"
    if [[ -n "${HOOK_MAIN_LOG_FILE:-}" && -w "${HOOK_MAIN_LOG_FILE:-/dev/null}" ]]; then
        echo "${CLEANUP_SCRIPT_LOG_PREFIX} [${level}] ${message}" >> "$HOOK_MAIN_LOG_FILE"
    else
        echo "${CLEANUP_SCRIPT_LOG_PREFIX} [${level}] ${message}" >&2
    fi
}

_hook_log "INFO" "Starting cleanup of old cron execution logs in: $CRON_EXEC_LOG_DIR"
_hook_log "INFO" "Pattern: '$LOG_FILENAME_PATTERN', Max to keep: $MAX_CRON_LOGS_TO_KEEP"
_hook_log "INFO" "Hook Event: ${HOOK_EVENT_NAME:-N/A}, Backup TS: ${HOOK_CURRENT_TIMESTAMP:-N/A}, Main Backup Exit: ${HOOK_MAIN_BACKUP_EXIT_CODE:-N/A}"


if [ ! -d "$CRON_EXEC_LOG_DIR" ]; then
    _hook_log "INFO" "Cron execution log directory not found: $CRON_EXEC_LOG_DIR. Nothing to clean."
    exit 0
fi

deleted_count=0
kept_count=0

# 获取所有匹配的日志文件，并按修改时间排序 (最新的在前)
# find ... -printf "%T@ %p\n" | sort -nr | cut ...
cron_log_files_sorted_newest_first=()
mapfile -t cron_log_files_sorted_newest_first < <(find "$CRON_EXEC_LOG_DIR" -maxdepth 1 -type f -name "$LOG_FILENAME_PATTERN" -printf "%T@ %p\n" 2>/dev/null | sort -nr | cut -d' ' -f2-)

if [[ ${#cron_log_files_sorted_newest_first[@]} -eq 0 ]]; then
    _hook_log "INFO" "No cron execution log files found matching pattern '$LOG_FILENAME_PATTERN'."
    exit 0
fi

_hook_log "INFO" "Found ${#cron_log_files_sorted_newest_first[@]} cron execution log files."

current_file_index=0
for log_file_path in "${cron_log_files_sorted_newest_first[@]}"; do
    current_file_index=$((current_file_index + 1))
    if [[ "$current_file_index" -le "$MAX_CRON_LOGS_TO_KEEP" ]]; then
        _hook_log "DEBUG" "Keeping cron execution log (newest $current_file_index): $(basename "$log_file_path")"
        kept_count=$((kept_count + 1))
    else
        _hook_log "INFO" "Deleting old cron execution log: $(basename "$log_file_path")"
        if rm -f "$log_file_path"; then
            deleted_count=$((deleted_count + 1))
        else
            _hook_log "WARN" "Failed to delete old cron execution log: $log_file_path"
            # 如果删除失败，也算作被“保留”（尽管是意外的）
            kept_count=$((kept_count + 1)) 
        fi
    fi
done

_hook_log "INFO" "Cron execution log cleanup finished. Kept $kept_count files, deleted $deleted_count files."
exit 0