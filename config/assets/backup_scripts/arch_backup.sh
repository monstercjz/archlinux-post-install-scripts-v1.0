#!/usr/bin/env bash

# arch_backup.sh - 高级 Arch Linux 系统备份脚本
# -----------------------------------------------------------------------------
# 版本 (Version):         1.3.0_zh_enhancements
# 最后更新 (Last Updated): 2025-06-17 # 请替换为实际日期
# 作者 (Author):          AI (由 cjz 协助测试和反馈)
# 联系 (Contact):         <您的邮箱或项目地址，可选>
# 许可证 (License):       MIT
# -----------------------------------------------------------------------------
# 描述 (Description):
#   一个用于 Arch Linux 系统的全面备份工具，支持系统配置、用户数据、
#   软件包列表、系统日志和自定义路径的备份。特性包括增量备份、
#   压缩、旧备份清理、并行处理、详细日志记录、错误捕获、
#   备份内容清单生成、资源使用控制和可选的带时间戳的日志轮转。
#   建议使用 'sudo ./arch_backup.sh' 运行以获得完整功能。
#
# 运行需求 (Requirements):
#   - Bash 4.0+
#   - rsync, tar, coreutils (find, sort, df, cut, head, tail, sed, grep, wc, mkdir, rm, id, date, basename, dirname, mktemp, du, awk)
#   - 压缩工具 (根据配置: gzip, bzip2, or xz)
#   - GNU Parallel (可选, 用于并行备份 CONF_PARALLEL_JOBS > 1)
#   - nice, ionice (可选, 用于资源控制 CONF_USE_NICE/CONF_USE_IONICE 为 true)
#
# 配置 (Configuration):
#   配置文件应位于以下任一路径 (按优先级):
#   1. ${HOME}/.config/arch_backup.conf (如果CONF_TARGET_USERNAME未指定，则为执行sudo的用户的HOME)
#   2. /etc/arch_backup.conf
#   可以在配置文件中设置 CONF_TARGET_USERNAME 来指定要备份家目录的特定用户。
#   如果未找到配置文件，脚本会提议生成一个默认配置文件，位置在/home/usr/.config/。
#   3. 钩子脚本位于默认：
#   /etc/arch_back/这个目录下面
# -----------------------------------------------------------------------------
# 更新日志 (Changelog):
#   1.3.2 (2025-06-17):
#     - 修复增量路径的问题，改用绝对路径
#   1.3.1 (2025-06-17):
#     - 给arch_back补齐函数注释
#     - 添加一个user目录下的排除项logs
#     - 发现一个新问题，增量路径失效，下个版本修复
#   1.3.0 (2025-06-17):
#     - 新增 `trap ERR` 错误处理机制，记录更详细的错误位置信息。
#     - 新增备份验证功能：在每个主要备份子目录内生成 `MANIFEST.txt` 文件。
#     - 新增资源使用优化：可通过配置使用 `nice` 和 `ionice` 控制 `rsync` 和 `tar`。
#     - 新增主要操作的耗时记录到日志。
#     - 新增自动生成默认配置文件功能：当未找到现有配置文件时提示用户创建。
#     - 新增带时间戳的日志文件轮转功能：
#       - `CONF_LOG_TIMESTAMPED`: 启用后，每次运行生成新的带时间戳的日志文件。
#       - `CONF_LOG_FILE`: 当轮转启用时，此项作为日志存放目录；否则为固定日志文件名。
#       - `CONF_LOG_RETENTION_DAYS`: 设置时间戳日志的保留天数。
#     - 更新脚本版本号和最后更新日期。
#   1.2.2 (2025-06-16):
#     - 修正 cleanup_backups 函数中处理未压缩快照的逻辑。
#     - 改进 cleanup_backups 中打印待删除压缩归档列表的方式。
#   (更早版本日志省略)
# -----------------------------------------------------------------------------

# 严格模式
set -euo pipefail
IFS=$'\n\t'

# === 脚本信息 ===
SCRIPT_VERSION="1.3.0_zh_enhancements"
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PID=$$
SESSION_TIMESTAMP=$(date '+%Y%m%d_%H%M%S') # 旧的用于日志文件名，现在使用GLOBAL_RUN_TIMESTAMP

# === 全局变量 (默认值, 会被配置文件覆盖) ===
CONF_BACKUP_ROOT_DIR=""
CONF_LOG_FILE="/tmp/${SCRIPT_NAME}.log" # 默认单日志文件路径，或时间戳日志的存放目录
CONF_LOG_TIMESTAMPED="false"            # 是否启用带时间戳的日志轮转
CONF_LOG_RETENTION_DAYS="30"          # 时间戳日志保留天数
CONF_LOG_LEVEL="INFO"                 # DEBUG, INFO, WARN, ERROR
CONF_TARGET_USERNAME=""

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
CONF_PROMPT_FOR_CONFIRMATION="false"
CONF_MIN_FREE_DISK_SPACE_PERCENT="10"

CONF_USE_NICE="false"
CONF_NICE_LEVEL="10"
CONF_USE_IONICE="false"
CONF_IONICE_CLASS="2" # 1=RT, 2=BE, 3=Idle
CONF_IONICE_LEVEL="4" # 0-7 for BE

# 运行时变量
LOADED_CONFIG_FILE=""
ACTUAL_LOG_FILE="$CONF_LOG_FILE" # 实际使用的日志文件路径, 会被 setup_logging 更新
CURRENT_TIMESTAMP=""             # 用于备份目录名
BACKUP_TARGET_DIR_UNCOMPRESSED=""
BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES=""

EFFECTIVE_UID=$(id -u)
EFFECTIVE_USER=$(id -un)
EFFECTIVE_GID=$(id -g)
TARGET_BACKUP_USER=""
TARGET_BACKUP_UID=""
TARGET_BACKUP_GID=""
TARGET_BACKUP_HOME=""
# === 处理可能未定义的 sudo 相关环境变量，以兼容 set -u ===
# 如果这些变量在环境中未设置（例如通过 cron 运行），则将其视为空字符串。
# 这样后续的 [[ -n "$SUDO_USER" ]] 判断仍然能正确工作（空字符串长度为0，-n 为假），
# 并且直接引用如 $SUDO_USER 也不会因“未绑定变量”而报错。
SUDO_USER="${SUDO_USER:-}"
SUDO_UID="${SUDO_UID:-}"   # SUDO_UID 通常由 sudo 设置，但 cron 环境下可能没有
SUDO_GID="${SUDO_GID:-}"   # SUDO_GID 通常由 sudo 设置，但 cron 环境下可能没有

PARALLEL_CMD=""

LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4 # 新增致命错误级别
declare -A LOG_LEVEL_NAMES=([0]="DEBUG" [1]="INFO" [2]="WARN" [3]="ERROR" [4]="FATAL_ERROR")
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_MAGENTA='\033[0;35m'


# === 错误处理 Trap ===
################################################################################
# 捕获未处理的错误 (与 set -e 配合使用)。
# Globals:
#   ACTUAL_LOG_FILE (R)
#   SCRIPT_NAME (R)
# Arguments:
#   $1 - LINENO: 发生错误的行号。
#   $2 - BASH_COMMAND: 失败的命令。
#   $3 - FUNCNAME (array string): 函数调用栈。
# Returns:
#   无，脚本通常会因此退出。
################################################################################
handle_error() {
    local exit_code=$?
    local line_no="${1:-?}"
    local command="${2:-Unknown}"
    local func_stack_str="${3:-N/A}"
    # shellcheck disable=SC2154 # SCRIPT_NAME is global
    local msg="Command '$command' on line $line_no (in function stack: $func_stack_str) failed with exit code $exit_code."

    # 尝试使用 log_msg，如果失败则回退到 echo
    if typeset -f log_msg &>/dev/null && [[ -n "${ACTUAL_LOG_FILE:-}" ]] && ( [[ -f "$ACTUAL_LOG_FILE" && -w "$ACTUAL_LOG_FILE" ]] || [[ -d "$(dirname "$ACTUAL_LOG_FILE")" && -w "$(dirname "$ACTUAL_LOG_FILE")" ]] ); then
        log_msg "FATAL_ERROR" "$msg"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [${LOG_LEVEL_NAMES[$LOG_LEVEL_FATAL]}] $msg" | tee -a "${ACTUAL_LOG_FILE:-/tmp/${SCRIPT_NAME}_fallback.log}" >&2
    fi
    # set -e 将确保脚本退出。trap ERR 在命令执行后、脚本退出前执行。
}
trap 'handle_error $LINENO "$BASH_COMMAND" "$(IFS=">"; echo "${FUNCNAME[*]}")"' ERR


# === 辅助函数 ===

################################################################################
# 记录日志消息到终端和日志文件。
# Globals:
#   ACTUAL_LOG_FILE     日志文件路径。
#   CURRENT_LOG_LEVEL   当前脚本的日志级别阈值。
#   LOG_LEVEL_NAMES     日志级别名称映射数组。
#   COLOR_*             终端颜色代码。
# Arguments:
#   $1 - 日志级别字符串 (e.g., "INFO", "ERROR", "FATAL_ERROR").
#   $2 - 要记录的日志消息.
# Returns:
#   None
################################################################################
log_msg() {
    local level_name="$1"
    local message="$2"
    local level_num

    case "$level_name" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO  ;;
        WARN)  level_num=$LOG_LEVEL_WARN  ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        FATAL_ERROR) level_num=$LOG_LEVEL_FATAL ;; # 新增
        *)     level_num=$LOG_LEVEL_INFO; message="[无效日志级别] $message" ;;
    esac

    if [[ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]]; then
        local color="$COLOR_RESET"
        [[ "$level_name" == "ERROR" ]] && color="$COLOR_RED"
        [[ "$level_name" == "FATAL_ERROR" ]] && color="$COLOR_MAGENTA" # 新增
        [[ "$level_name" == "WARN" ]]  && color="$COLOR_YELLOW"
        [[ "$level_name" == "INFO" ]]  && color="$COLOR_GREEN"
        [[ "$level_name" == "DEBUG" ]] && color="$COLOR_CYAN"
        # 确保 ACTUAL_LOG_FILE 已经被正确设置和可写
        if [[ -n "$ACTUAL_LOG_FILE" ]]; then
             echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${color}${level_name}${COLOR_RESET}] $message" | tee -a "$ACTUAL_LOG_FILE"
        else # 回退到标准错误和临时日志
             echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${color}${level_name}${COLOR_RESET}] $message (Fallback logging)" | tee -a "/tmp/${SCRIPT_NAME}_init_err.log" >&2
        fi
    elif [[ "$level_name" == "ERROR" || "$level_name" == "WARN" || "$level_name" == "FATAL_ERROR" ]]; then # 确保重要信息总是写入日志文件
        if [[ -n "$ACTUAL_LOG_FILE" ]]; then
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level_name}] $message" >> "$ACTUAL_LOG_FILE"
        else
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level_name}] $message (Fallback logging)" >> "/tmp/${SCRIPT_NAME}_init_err.log"
        fi
    fi
}

################################################################################
# 初始化和设置日志系统。
# 会根据配置决定最终的日志文件路径 (固定或带时间戳)。
# Globals:
#   CONF_LOG_FILE (R/W)      - 从配置中读取的日志基础路径或目录。
#   CONF_LOG_TIMESTAMPED (R) - 是否启用时间戳日志。
#   GLOBAL_RUN_TIMESTAMP (R)    - 当前会话的时间戳。
#   SCRIPT_NAME (R)          - 脚本名称，用于生成日志文件名。
#   ACTUAL_LOG_FILE (W)      - 设置实际使用的日志文件完整路径。
#   EFFECTIVE_UID (R)
#   EFFECTIVE_GID (R)
#   TARGET_BACKUP_UID (R)
#   TARGET_BACKUP_GID (R)
#   SUDO_USER (R)
# Arguments:
#   None
# Returns:
#   None. 如果无法创建日志目录/文件，脚本会退出。
################################################################################
_setup_final_log_path() {
    # 此函数在 load_config 内部被调用，此时配置已加载
    local final_log_path_candidate="$CONF_LOG_FILE" # 从配置中获取

    if [[ "$CONF_LOG_TIMESTAMPED" == "true" ]]; then
        # CONF_LOG_FILE 被视为日志目录
        local log_dir="$CONF_LOG_FILE"
        # 确保 log_dir 结尾不是脚本名的一部分，如果用户错误配置
        if [[ "$(basename "$log_dir")" == "${SCRIPT_NAME}.log" || "$(basename "$log_dir")" == "$SCRIPT_NAME" ]]; then
            log_dir=$(dirname "$log_dir")
        fi
        final_log_path_candidate="${log_dir%/}/${SCRIPT_NAME}_${GLOBAL_RUN_TIMESTAMP}.log"
    fi

    ACTUAL_LOG_FILE="$final_log_path_candidate" # 更新全局实际日志文件路径

    local log_owner_uid="$EFFECTIVE_UID"
    local log_owner_gid="$EFFECTIVE_GID"
    # 确定日志文件的合理所有者 (尝试非 root 用户，如果适用)
    if [[ -n "$TARGET_BACKUP_USER" && "$TARGET_BACKUP_UID" != "0" ]]; then
        log_owner_uid="$TARGET_BACKUP_UID"
        log_owner_gid="$TARGET_BACKUP_GID"
    elif [[ -n "$SUDO_USER" && "$(id -u "$SUDO_USER" 2>/dev/null)" != "0" && "$(id -u "$SUDO_USER" 2>/dev/null)" != "" ]]; then
        if id -u "$SUDO_USER" >/dev/null 2>&1; then
           log_owner_uid=$(id -u "$SUDO_USER")
           log_owner_gid=$(id -g "$SUDO_USER")
        fi
    fi

    local actual_log_dir; actual_log_dir=$(dirname "$ACTUAL_LOG_FILE")
    if [[ ! -d "$actual_log_dir" ]]; then
        # 尝试创建日志目录
        # 使用 log_msg 前，确保它能写入临时位置或 stdout/stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Log directory '$actual_log_dir' not found, attempting to create."
        mkdir -p "$actual_log_dir" || { echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL_ERROR] Cannot create log directory: $actual_log_dir" >&2; exit 1; }
        if [[ "$EFFECTIVE_UID" -eq 0 ]]; then
            chown "$log_owner_uid:$log_owner_gid" "$actual_log_dir" || echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Cannot chown log directory '$actual_log_dir' to $log_owner_uid:$log_owner_gid." >&2
        fi
    fi

    touch "$ACTUAL_LOG_FILE" || { echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL_ERROR] Cannot create or access log file: $ACTUAL_LOG_FILE" >&2; exit 1; }
    if [[ "$EFFECTIVE_UID" -eq 0 ]]; then
         chown "$log_owner_uid:$log_owner_gid" "$ACTUAL_LOG_FILE" || echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Cannot chown log file '$ACTUAL_LOG_FILE' to $log_owner_uid:$log_owner_gid." >&2
    fi
    log_msg INFO "Logging initialized. Actual log file: $ACTUAL_LOG_FILE"
}

################################################################################
# 清理旧的带时间戳的日志文件。
# Globals:
#   CONF_LOG_TIMESTAMPED (R)
#   CONF_LOG_FILE (R)        - 当时间戳启用时，作为日志目录
#   CONF_LOG_RETENTION_DAYS (R)
#   SCRIPT_NAME (R)
# Arguments:
#   None
# Returns:
#   None
################################################################################
cleanup_old_logs_bydays() {
    if [[ "$CONF_LOG_TIMESTAMPED" != "true" || "${CONF_LOG_RETENTION_DAYS:-0}" -le 0 ]]; then
        return 0
    fi

    local log_dir_to_clean="$CONF_LOG_FILE" # Assumed to be a directory
    if [[ "$(basename "$log_dir_to_clean")" == "${SCRIPT_NAME}.log" || "$(basename "$log_dir_to_clean")" == "$SCRIPT_NAME" ]]; then
        log_dir_to_clean=$(dirname "$log_dir_to_clean") # Correct if user put full path as dir
    fi

    log_msg INFO "[Log Cleanup] Cleaning up logs older than $CONF_LOG_RETENTION_DAYS days in '$log_dir_to_clean'."
    local find_name_pattern="${SCRIPT_NAME}_*.log"
    local deleted_count=0
    # Use a loop to handle filenames with spaces correctly, though unlikely for our pattern
    # And to log each deletion
    while IFS= read -r -d $'\0' old_log_file; do
        if rm -f "$old_log_file"; then
            log_msg DEBUG "[Log Cleanup] Deleted old log file: $old_log_file"
            deleted_count=$((deleted_count + 1))
        else
            log_msg WARN "[Log Cleanup] Failed to delete old log file: $old_log_file"
        fi
    done < <(find "$log_dir_to_clean" -maxdepth 1 -type f -name "$find_name_pattern" -mtime "+$CONF_LOG_RETENTION_DAYS" -print0)
    
    log_msg INFO "[Log Cleanup] Deleted $deleted_count old log file(s)."
}

################################################################################
# 清理旧的带时间戳的日志文件。
# Globals:
#   CONF_LOG_TIMESTAMPED (R) - 是否启用时间戳日志。
#   CONF_LOG_FILE (R)        - 当时间戳启用时，作为日志目录。
#   CONF_RETENTION_UNCOMPRESSED_COUNT (R) - 用作保留的最新日志文件数量。
#   SCRIPT_NAME (R)          - 脚本名称，用于匹配日志文件名。
# Arguments:
#   None
# Returns:
#   None
################################################################################
cleanup_old_logs_bycounts() {
    # 仅当启用了时间戳日志时才执行清理
    if [[ "$CONF_LOG_TIMESTAMPED" != "true" ]]; then
        log_msg DEBUG "[Log Cleanup] 时间戳日志未启用，跳过日志清理。"
        return 0
    fi

    # 从 CONF_RETENTION_UNCOMPRESSED_COUNT 获取要保留的日志数量
    # 如果该值未设置或无效，则设置一个合理的默认值，例如 7
    local max_log_files_to_keep="${CONF_RETENTION_UNCOMPRESSED_COUNT:-7}"
    if ! [[ "$max_log_files_to_keep" =~ ^[0-9]+$ ]] || [[ "$max_log_files_to_keep" -le 0 ]]; then
        log_msg WARN "[Log Cleanup] 无效的 CONF_RETENTION_UNCOMPRESSED_COUNT 值 ('$max_log_files_to_keep') 用于日志保留。将使用默认值 7。"
        max_log_files_to_keep=7
    fi

    # 获取日志目录路径
    # CONF_LOG_FILE 在时间戳模式下应为目录
    local log_dir_to_clean="$CONF_LOG_FILE"
    if [[ ! -d "$log_dir_to_clean" ]]; then
        # 检查 CONF_LOG_FILE 是否被错误地配置为一个文件名
        if [ -f "$log_dir_to_clean" ]; then
            log_dir_to_clean=$(dirname "$log_dir_to_clean")
            if [[ ! -d "$log_dir_to_clean" ]]; then
                 log_msg WARN "[Log Cleanup] 日志目录 '$log_dir_to_clean' (从 '$CONF_LOG_FILE' 推断) 无效或不存在。跳过日志清理。"
                 return 1
            fi
        else
            log_msg WARN "[Log Cleanup] 日志目录 '$CONF_LOG_FILE' 无效或不存在。跳过日志清理。"
            return 1
        fi
    fi

    log_msg INFO "[Log Cleanup] 开始清理日志文件，将保留最新的 $max_log_files_to_keep 个日志 (基于 CONF_RETENTION_UNCOMPRESSED_COUNT)。"
    log_msg DEBUG "[Log Cleanup] 日志目录: '$log_dir_to_clean'."

    # 构建日志文件名的查找模式
    # 假设日志文件名格式为: SCRIPT_NAME_YYYYMMDD_HHMMSS.log
    local find_name_pattern="${SCRIPT_NAME}_*.log"
    local deleted_count=0
    local kept_count=0

    # 获取所有匹配的日志文件，并按修改时间排序 (最新的在前)
    # 使用 find -printf "%T@ %p\n" 获取时间戳和路径，然后 sort -nr，再 cut 路径
    # 或者，如果文件名中的时间戳是可靠的，可以直接对文件名排序
    # 假设文件名中的时间戳是 YYYYMMDD_HHMMSS，可以直接用 ls -t (按修改时间) 或 sort (按文件名)

    # 使用 find 和 sort 按修改时间获取文件列表 (最新的在前)
    local log_files_sorted_newest_first=()
    mapfile -t log_files_sorted_newest_first < <(find "$log_dir_to_clean" -maxdepth 1 -type f -name "$find_name_pattern" -printf "%T@ %p\n" 2>/dev/null | sort -nr | cut -d' ' -f2-)

    if [[ ${#log_files_sorted_newest_first[@]} -eq 0 ]]; then
        log_msg INFO "[Log Cleanup] 未找到匹配的日志文件 ('$find_name_pattern') 于 '$log_dir_to_clean'。无需清理。"
        return 0
    fi

    log_msg DEBUG "[Log Cleanup] 找到 ${#log_files_sorted_newest_first[@]} 个匹配的日志文件。"

    # 遍历文件列表，保留最新的 N 个，删除其余的
    local current_file_index=0
    for log_file_path in "${log_files_sorted_newest_first[@]}"; do
        current_file_index=$((current_file_index + 1))
        if [[ "$current_file_index" -le "$max_log_files_to_keep" ]]; then
            log_msg DEBUG "[Log Cleanup] 保留日志文件 (第 $current_file_index 个最新): $log_file_path"
            kept_count=$((kept_count + 1))
        else
            # 超出保留数量，删除此文件
            log_msg DEBUG "[Log Cleanup] 准备删除旧日志文件: $log_file_path"
            if rm -f "$log_file_path"; then
                log_msg INFO "[Log Cleanup] 已删除旧日志文件: $(basename "$log_file_path")"
                deleted_count=$((deleted_count + 1))
            else
                log_msg WARN "[Log Cleanup] 删除旧日志文件 '$log_file_path' 失败。"
            fi
        fi
    done
    
    log_msg INFO "[Log Cleanup] 日志清理完成。保留了 $kept_count 个日志文件，删除了 $deleted_count 个旧日志文件。"
    return 0
}


################################################################################
# cleanup_old_logs - 清理旧的、与已不存在的备份相关联的日志文件。
#
# 工作原理:
# 1. 此函数仅在时间戳日志模式 (CONF_LOG_TIMESTAMPED="true")下工作。
# 2. 它会遍历指定日志目录 (CONF_LOG_FILE) 中所有符合命名模式的日志文件。
# 3. 【核心保护】当前脚本会话正在使用的日志文件 (ACTUAL_LOG_FILE) 会被明确识别并跳过，
#    确保它绝不会被删除。
# 4. 对于其他所有旧的日志文件：
#    a. 从日志文件名中提取其关联的时间戳 (应与GLOBAL_RUN_TIMESTAMP格式一致)。
#    b. 检查该时间戳对应的未压缩快照 (在 BACKUP_TARGET_DIR_UNCOMPRESSED 中)
#       或压缩归档 (在 BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES 中) 是否仍然存在。
#    c. 如果对应的快照和归档均已不存在，则该旧日志文件被视为“孤立的”，并被删除。
#    d. 否则 (即至少有一个对应的备份存在)，则保留该旧日志文件。
#
# Globals (R - Read-only by this function):
#   CONF_LOG_TIMESTAMPED           - (String) 是否启用时间戳日志 ("true" 或 "false")。
#   CONF_LOG_FILE                  - (String) 日志文件的存放目录 (当时间戳启用时)。
#   ACTUAL_LOG_FILE                - (String) 当前脚本会话正在使用的日志文件的完整路径。
#   SCRIPT_NAME                    - (String) 当前脚本的文件名 (用于匹配日志文件)。
#   BACKUP_TARGET_DIR_UNCOMPRESSED - (String) 未压缩备份快照的根目录。
#   BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES - (String) 压缩备份归档的根目录。
#
# Globals (Not directly used but relevant for context):
#   GLOBAL_RUN_TIMESTAMP           - (String) 用于本次运行的日志和备份的统一时间戳。
#                                    此函数依赖于旧日志文件名中的时间戳与旧备份的
#                                    时间戳一致的约定（由方案C保证）。
#
# Arguments:
#   None
#
# Returns:
#   0 - 清理成功完成或无需清理。
#   1 - 如果日志目录无效或在关键步骤发生错误。
#
# Side effects:
#   - 可能会删除日志目录下的旧日志文件。
#   - 输出日志信息到 ACTUAL_LOG_FILE。
################################################################################
cleanup_old_logs() {
    # 检查时间戳日志功能是否已启用
    if [[ "${CONF_LOG_TIMESTAMPED:-false}" != "true" ]]; then
        log_msg DEBUG "[Log Cleanup] 时间戳日志功能未启用。跳过与备份关联的日志清理。"
        return 0
    fi

    # 获取并验证日志目录路径
    # 在时间戳模式下，CONF_LOG_FILE 应被配置为日志文件的父目录
    local log_dir_to_clean="$CONF_LOG_FILE"
    if [[ ! -d "$log_dir_to_clean" ]]; then
        # 尝试从 CONF_LOG_FILE 推断目录，以防用户错误地将其配置为文件名
        if [ -f "$log_dir_to_clean" ] && [[ "$CONF_LOG_TIMESTAMPED" == "true" ]]; then
            log_msg DEBUG "[Log Cleanup] CONF_LOG_FILE ('$CONF_LOG_FILE') 似乎是一个文件路径，但期望是目录。尝试使用其父目录。"
            log_dir_to_clean=$(dirname "$log_dir_to_clean")
            if [[ ! -d "$log_dir_to_clean" ]]; then
                 log_msg WARN "[Log Cleanup] 日志目录 '$log_dir_to_clean' (从 '$CONF_LOG_FILE' 推断) 无效或不存在。跳过日志清理。"
                 return 1
            fi
        else
            log_msg WARN "[Log Cleanup] 日志目录 '$CONF_LOG_FILE' (在CONF_LOG_TIMESTAMPED=true时应为目录路径) 无效或不存在。跳过日志清理。"
            return 1
        fi
    fi

    # 获取当前正在使用的日志文件的基本名称，以便在扫描时排除它
    local current_log_basename=""
    if [[ -n "${ACTUAL_LOG_FILE:-}" && -f "${ACTUAL_LOG_FILE:-}" ]]; then
        current_log_basename=$(basename "$ACTUAL_LOG_FILE")
    else
        # 如果无法确定当前日志文件，方案B的直接保护会失效。
        # 但如果方案C (统一时间戳) 工作正常，当前日志仍会因找到关联备份而被保留。
        log_msg WARN "[Log Cleanup] 无法确定当前会话日志文件 (ACTUAL_LOG_FILE: '${ACTUAL_LOG_FILE:-未设置}'). 清理时将无法显式跳过当前日志文件，但仍会基于其与备份的关联性进行判断。"
    fi

    log_msg INFO "[Log Cleanup] 开始扫描并清理旧的、与已不存在的备份相关联的日志文件..."
    log_msg DEBUG "[Log Cleanup] 日志存放目录: '$log_dir_to_clean'"
    log_msg DEBUG "[Log Cleanup] 未压缩快照目录: '$BACKUP_TARGET_DIR_UNCOMPRESSED'"
    log_msg DEBUG "[Log Cleanup] 压缩归档目录: '$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES'"
    if [[ -n "$current_log_basename" ]]; then
        log_msg DEBUG "[Log Cleanup] 当前会话日志文件 '$current_log_basename' 将被自动保留，不参与删除判断。"
    fi

    local deleted_count=0
    local kept_due_to_backup_count=0 # 统计因找到关联备份而被保留的 *旧* 日志数量
    local kept_due_to_error_count=0  # 统计因处理错误（如无法提取时间戳、删除失败）而被保留的 *旧* 日志数量
    # 日志文件名模式，假设为 SCRIPT_NAME_YYYYMMDD_HHMMSS.log
    local log_file_pattern="${SCRIPT_NAME}_*.log"

    # 使用 find 安全地遍历日志文件，避免含特殊字符的文件名导致问题
    # -print0 和 read -d $'\0' 是处理这类问题的标准方法
        # 使用进程替换，使得 while 循环在当前 shell 上下文执行，以便正确更新计数器
    while IFS= read -r -d $'\0' log_file_path; do
        local log_filename
        log_filename=$(basename "$log_file_path")

        # --- 方案 B 的核心：如果文件名与当前日志文件名相同，则直接跳过后续处理 ---
        if [[ -n "$current_log_basename" && "$log_filename" == "$current_log_basename" ]]; then
            # 对当前日志文件不做任何计数，因为它不属于“旧日志”的范畴
            # log_msg DEBUG "[Log Cleanup]   当前会话日志文件 '$log_filename'，跳过。" # 此日志可省略，因为结尾会统一说明
            continue
        fi
        # --------------------------------------------------------------------------

        # 从旧日志文件名中提取时间戳部分 (应与 GLOBAL_RUN_TIMESTAMP 格式一致)
        local timestamp_from_log
        local sed_script_name_safe
        # sed_script_name_safe=$(echo "$SCRIPT_NAME" | sed 's/[.^$*\[]/\\[&]/g; s/]/\\&/g') # 旧的转义
        sed_script_name_safe=$(echo "$SCRIPT_NAME" | sed 's/\./\\./g') # 修正后的仅转义点号

        # 提取 SCRIPT_NAME 和 .log 之间的 YYYYMMDD_HHMMSS 部分
        timestamp_from_log=$(echo "$log_filename" | sed -n "s/^${sed_script_name_safe}_\([0-9]\{8\}_[0-9]\{6\}\)\.log$/\1/p")

        if [[ -z "$timestamp_from_log" ]]; then
            log_msg WARN "[Log Cleanup] 无法从旧日志文件名 '$log_filename' 中提取有效的时间戳 (期望格式 YYYYMMDD_HHMMSS)。将保留此文件。"
            kept_due_to_error_count=$((kept_due_to_error_count + 1))
            continue
        fi

        log_msg DEBUG "[Log Cleanup] 正在检查旧日志文件 '$log_filename' (提取的时间戳: $timestamp_from_log)..."

        local snapshot_exists=false
        local archive_exists=false

        # 检查对应的未压缩快照是否存在
        if [[ -d "${BACKUP_TARGET_DIR_UNCOMPRESSED}/${timestamp_from_log}" ]]; then
            snapshot_exists=true
            log_msg DEBUG "[Log Cleanup]     发现对应的未压缩快照: '${BACKUP_TARGET_DIR_UNCOMPRESSED}/${timestamp_from_log}'"
        fi

        # 检查对应的压缩归档是否存在 (匹配如 .tar.gz, .tar.xz, .tar.bz2 等)
        if find "${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}" -maxdepth 1 -type f -name "${timestamp_from_log}.tar.*" -print -quit 2>/dev/null | grep -q .; then
            archive_exists=true
            log_msg DEBUG "[Log Cleanup]     发现对应的压缩归档 (例如: '${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}/${timestamp_from_log}.tar.xz')"
        fi

        # 根据是否存在关联的备份（快照 或 归档）来决定是否保留或删除该旧日志
        if $snapshot_exists || $archive_exists; then
            log_msg DEBUG "[Log Cleanup]     对应的备份（快照或归档）仍然存在。保留旧日志文件 '$log_filename'。"
            kept_due_to_backup_count=$((kept_due_to_backup_count + 1))
        else
            log_msg INFO "[Log Cleanup]     对应的备份（快照和归档）均已不存在。准备删除旧日志文件 '$log_filename'。"
            if rm -f "$log_file_path"; then
                log_msg INFO "[Log Cleanup]       已删除旧日志文件: $log_filename"
                deleted_count=$((deleted_count + 1))
            else
                log_msg WARN "[Log Cleanup]       删除旧日志文件 '$log_file_path' 失败。"
                kept_due_to_error_count=$((kept_due_to_error_count + 1)) # 删除失败也视为因错误而保留
            fi
        fi
    done < <(find "$log_dir_to_clean" -maxdepth 1 -type f -name "$log_file_pattern" -print0 2>/dev/null)

    # 循环结束后，总结清理结果
    if [[ -n "$current_log_basename" ]]; then
        log_msg INFO "[Log Cleanup] 当前会话日志 '$current_log_basename' 已按设计始终保留，未参与上述旧日志的删除判断。"
    fi
    log_msg INFO "[Log Cleanup] 旧日志清理完成。在扫描的旧日志中："
    log_msg INFO "[Log Cleanup]   - 因找到关联备份而保留: $kept_due_to_backup_count 个文件。"
    log_msg INFO "[Log Cleanup]   - 因处理错误（如无法提时间戳、删除失败）而保留: $kept_due_to_error_count 个文件。"
    log_msg INFO "[Log Cleanup]   - 因无关联备份而被删除: $deleted_count 个文件。"
    
    return 0
}

################################################################################
# 向用户显示一个确认提示。
# (unchanged from original)
################################################################################
confirm_action() {
    local prompt_message="$1"
    if [[ "$CONF_PROMPT_FOR_CONFIRMATION" != "true" ]]; then
        log_msg INFO "由于CONF_PROMPT_FOR_CONFIRMATION=false，自动确认操作: $prompt_message"
        return 0
    fi
    while true; do
        read -r -p "$prompt_message [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]|"") return 1 ;;
            *) echo "请输入 yes (y) 或 no (n)。" ;;
        esac
    done
}

################################################################################
# 检查脚本运行所需的依赖工具是否已安装。
# Globals:
#   None
# Arguments:
#   $@ - 需要检查的依赖工具名称列表。
# Returns:
#   0 如果所有依赖都存在。
#   脚本会以状态码 1 退出，如果任何依赖缺失。
################################################################################
check_dependencies() {
    local missing_deps=0
    log_msg INFO "开始检查依赖工具..."
    
    # Dynamically add nice/ionice to the list if configured
    local deps_to_check=("$@")
    [[ "$CONF_USE_NICE" == "true" ]] && ! (printf '%s\n' "${deps_to_check[@]}" | grep -qxF "nice") && deps_to_check+=("nice")
    [[ "$CONF_USE_IONICE" == "true" ]] && ! (printf '%s\n' "${deps_to_check[@]}" | grep -qxF "ionice") && deps_to_check+=("ionice")

    for dep in "${deps_to_check[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_msg ERROR "必需的依赖工具 '$dep' 未安装。"
            missing_deps=1
        else
            local version_info_raw=""
            local version_info_display=""
            case "$dep" in
                rsync)    version_info_raw=$((rsync --version | head -n1) 2>/dev/null || true) ;;
                tar)      version_info_raw=$((tar --version | head -n1) 2>/dev/null || true) ;;
                xz)       version_info_raw=$((xz --version | head -n1) 2>/dev/null || true) ;;
                gzip)     version_info_raw=$((gzip --version | head -n1) 2>/dev/null || true) ;;
                bzip2)    version_info_raw=$((bzip2 --help 2>&1 | grep "bzip2,.*Version") 2>/dev/null || true) ;;
                parallel) version_info_raw=$((parallel --version | head -n1) 2>/dev/null || true) ;;
                awk)      version_info_raw=$((awk --version | head -n1) 2>/dev/null || true) ;;
                nice)     version_info_raw=$((nice --version 2>&1 | head -n1) 2>/dev/null || true) ;;
                ionice)   version_info_raw=$((ionice --version 2>&1 | head -n1) 2>/dev/null || true) ;; # ionice may not have --version
                *)        version_info_raw="" ;;
            esac
            if [[ -n "$version_info_raw" ]]; then
                version_info_cleaned=$(echo "$version_info_raw" | LC_ALL=C tr -dc '[:alnum:][:punct:][:space:]')
            else
                version_info_cleaned=""
            fi
            if [[ -n "$version_info_cleaned" ]]; then
                version_info_display="$version_info_cleaned"
                log_msg DEBUG "依赖 '$dep' 已找到。版本信息: $version_info_display"
            else
                 # For ionice, version might not be available, just confirm presence.
                if [[ "$dep" == "ionice" ]]; then
                     log_msg DEBUG "依赖 '$dep' 已找到。(版本信息通常不可用)"
                else
                    log_msg DEBUG "依赖 '$dep' 已找到。(版本信息获取失败、为空或未尝试)"
                fi
            fi
        fi
    done
    if [[ "$missing_deps" -eq 1 ]]; then
        log_msg ERROR "请安装缺失的依赖项后重试。"
        log_msg INFO "在 Arch Linux 上, 通常可以使用以下命令安装: sudo pacman -S <软件包名称>"
        exit 1
    fi
    log_msg INFO "所有核心依赖项检查完毕。"
}

################################################################################
# 获取并设置用于备份家目录的目标用户的信息 (用户名, UID, GID, 家目录路径)。
# 优先使用 CONF_TARGET_USERNAME 配置项。如果未配置，则尝试使用 SUDO_USER
# (如果脚本通过 sudo 执行且 SUDO_USER 不是 root)。
# 如果两者都不可用或无效，则 TARGET_BACKUP_* 变量可能为空，
# 后续的用户数据备份任务将跳过。
# Globals:
#   CONF_TARGET_USERNAME (R)  配置文件中指定的目标用户名。
#   SUDO_USER            (R)  环境变量，表示原始 sudo 用户。
#   USER                 (R)  环境变量，表示当前用户。
#   HOME                 (R)  环境变量，表示当前用户的家目录。
#   TARGET_BACKUP_USER   (W)  设置目标用户名。
#   TARGET_BACKUP_UID    (W)  设置目标用户的 UID。
#   TARGET_BACKUP_GID    (W)  设置目标用户的 GID。
#   TARGET_BACKUP_HOME   (W)  设置目标用户的家目录。
# Arguments:
#   None
# Returns:
#   None. 直接修改全局变量。
################################################################################
get_target_backup_user_info() {
    local user_to_query=""

    if [[ -n "$CONF_TARGET_USERNAME" ]]; then
        log_msg INFO "配置文件中指定了目标用户: '$CONF_TARGET_USERNAME'。"
        user_to_query="$CONF_TARGET_USERNAME"
    elif [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        log_msg INFO "脚本通过 sudo 执行，尝试使用原始用户 '$SUDO_USER' 作为备份目标。"
        user_to_query="$SUDO_USER"
    elif [[ "$EFFECTIVE_USER" != "root" ]]; then # 非 sudo，且当前用户不是 root
        log_msg INFO "脚本以普通用户 '$EFFECTIVE_USER' 执行，将尝试备份此用户的家目录。"
        user_to_query="$EFFECTIVE_USER"
    else # 直接以 root 运行，且未指定 CONF_TARGET_USERNAME
        log_msg WARN "脚本以 root 身份运行，且未在配置中指定 CONF_TARGET_USERNAME。将不进行特定用户的家目录备份，除非手动配置了包含root家目录的自定义路径。"
        TARGET_BACKUP_USER=""
        TARGET_BACKUP_UID=""
        TARGET_BACKUP_GID=""
        TARGET_BACKUP_HOME=""
        return
    fi

    if ! id -u "$user_to_query" >/dev/null 2>&1; then
        log_msg ERROR "无法找到用户 '$user_to_query' 的信息。请检查用户名是否正确或用户是否存在。"
        TARGET_BACKUP_USER=""
        TARGET_BACKUP_UID=""
        TARGET_BACKUP_GID=""
        TARGET_BACKUP_HOME=""
        return 
    fi

    TARGET_BACKUP_USER="$user_to_query"
    TARGET_BACKUP_UID=$(id -u "$user_to_query")
    TARGET_BACKUP_GID=$(id -g "$user_to_query")
    TARGET_BACKUP_HOME=$(getent passwd "$user_to_query" | cut -d: -f6)

    if [[ -z "$TARGET_BACKUP_HOME" || ! -d "$TARGET_BACKUP_HOME" ]]; then
        log_msg ERROR "无法获取或访问用户 '$TARGET_BACKUP_USER' 的家目录 ('$TARGET_BACKUP_HOME')。"
        TARGET_BACKUP_USER=""
        TARGET_BACKUP_UID=""
        TARGET_BACKUP_GID=""
        TARGET_BACKUP_HOME=""
    else
        log_msg INFO "目标备份用户信息: User='$TARGET_BACKUP_USER', UID='$TARGET_BACKUP_UID', GID='$TARGET_BACKUP_GID', Home='$TARGET_BACKUP_HOME'"
    fi
}

################################################################################
# 生成默认配置文件的内容。
# Globals:
#   SCRIPT_NAME (R)
# Arguments:
#   None
# Returns:
#   Prints default config content to stdout.
################################################################################
_generate_default_config_content() {
cat <<EOF
# ~/.config/arch_backup.conf or /etc/arch_backup.conf
# arch_backup.sh 脚本的配置文件 (版本 1.3.0+)

# === 基本设置 ===
# 备份文件存放的根目录。
# 请确保此目录存在并且有足够的磁盘空间。
CONF_BACKUP_ROOT_DIR="/mnt/arch_backups/auto_backup_systems" # <<<--- 请务必修改为您的实际备份位置

# 日志文件设置
# CONF_LOG_FILE:
#   如果 CONF_LOG_TIMESTAMPED="false", 此为固定日志文件的完整路径。
#     例如: CONF_LOG_FILE="/var/log/arch_backup.log"
#   如果 CONF_LOG_TIMESTAMPED="true", 此为存放带时间戳日志文件的 *目录* 路径。
#     例如: CONF_LOG_FILE="/var/log/arch_backups_logs" (脚本会自动在此目录下创建 arch_backup.sh_YYYYMMDD_HHMMSS.log)
#CONF_LOG_FILE="/var/log/arch_backups_logs/auto_backups_logs"   # 推荐使用目录路径配合时间戳日志
CONF_LOG_FILE="${CONF_BACKUP_ROOT_DIR}/backup_logs"
CONF_LOG_TIMESTAMPED="true"                 # "true" 为每次运行创建新日志 (推荐), "false" 为追加到单一日志文件
CONF_LOG_RETENTION_DAYS="30"                # 如果 CONF_LOG_TIMESTAMPED="true", 保留多少天的日志文件 (0 表示不自动删除)
CONF_LOG_LEVEL="DEBUG"                       # DEBUG, INFO, WARN, ERROR, FATAL_ERROR (FATAL_ERROR会显示所有级别)

# === 用户特定备份设置 ===
# 如果希望备份特定用户的家目录 (而不是执行 sudo 的用户，或者当脚本由 root 的 cron 运行时)，
# 在这里指定用户名。如果留空，脚本将尝试确定原始 sudo 用户。
# 如果脚本以普通用户身份运行 (非 sudo)，则此设置无效，将备份当前用户。
CONF_TARGET_USERNAME="cjz" # 例如: "myuser", 或者留空 ""

# === 备份类别 ===
# 设置为 "true" 启用该类别的备份, "false" 则禁用。
CONF_BACKUP_SYSTEM_CONFIG="true"  # 系统配置文件 (/etc)
CONF_BACKUP_USER_DATA="true"      # 用户家目录数据 (由 CONF_TARGET_USERNAME 或 sudo 用户决定)
CONF_BACKUP_PACKAGES="true"       # 已安装软件包列表
CONF_BACKUP_LOGS="true"           # 系统日志 (/var/log, journalctl)
CONF_BACKUP_CUSTOM_PATHS="true"   # 用户自定义路径
CONF_BACKUP_SYSTEM_STATE_INFO="true"

# === 用户数据配置 (仅当 CONF_BACKUP_USER_DATA="true") ===
# 用户家目录下需要备份的项目列表 (空格分隔的数组)。路径相对于用户家目录。
CONF_USER_HOME_INCLUDE=(
    ".config"
    ".local/share"
    # ".ssh"  # 注意：备份 SSH 私钥需谨慎，确保备份安全
    # ".gnupg" # 注意：备份 GPG 私钥需谨慎
    ".bashrc"
    ".zsh_history"
    ".zshrc"
    ".gitconfig"
    # "Documents"
    # "Pictures"
    # "Code"
)
# 从用户家目录备份中排除的模式列表 (rsync 排除模式)。
CONF_USER_HOME_EXCLUDE=(
    "Code/"
    "microsoft-edge/"
    "*/.cache/*"
    "*/Cache/*"          # Firefox, Chrome etc.
    "*/[Tt]rash/*"
    "*/Downloads/*"      # 通常包含临时或可重新获取的文件
    "*.tmp"
    "node_modules/"      # JS 项目依赖，通常很大且可重建
    ".npm/"
    ".bundle/"           # Ruby 项目依赖
    ".gradle/"           # Java/Android 项目缓存
    ".m2/"               # Maven 仓库缓存
    "target/"            # Rust/Java 构建输出
    "__pycache__/"
    "*.pyc"
    "arch_backup.conf"   # 避免备份脚本自身的配置文件 (如果在家目录)
    ".DS_Store"
    "Thumbs.db"
    "logs"
    "*AppImage"
)

# === 自定义路径配置 (仅当 CONF_BACKUP_CUSTOM_PATHS="true") ===
# 需要备份的绝对路径列表。
CONF_CUSTOM_PATHS_INCLUDE=(
    # "/opt/my_custom_app/data"
    # "/srv/docker_volumes"
    # "/usr/local/bin"
    # "/etc/nginx/sites-available" # 如果不想备份整个 /etc 但需要特定子目录
)
# 自定义路径的 rsync 排除模式列表 (全局应用于所有 CONF_CUSTOM_PATHS_INCLUDE 中的项)。
CONF_CUSTOM_PATHS_EXCLUDE=(
    "*/temp_files/*"
    "*.log" # 如果这些路径下有大量日志，可能希望排除
    "*/backups/*" # 避免备份中包含备份
)

# === 系统日志配置 (仅当 CONF_BACKUP_LOGS="true") ===
# /var/log 下的关键日志文件/目录列表 (相对于 /var/log)。
CONF_SYSTEM_LOG_FILES=(
    "pacman.log"
    "Xorg.0.log"
    # "nginx" # 示例: 备份整个 nginx 日志目录
    # "journal" # journalctl 的输出通常更全面，如果启用下面选项，这个可能多余
)
# 是否捕获 journalctl 的输出?
CONF_BACKUP_JOURNALCTL="true"
# journalctl 的参数 (例如: --boot=-1 代表上次启动的日志, 为空则代表当前启动的所有日志)
CONF_JOURNALCTL_ARGS="" # 或例如: "--since yesterday" 或 "--lines=10000"

# === 备份机制 ===
# 是否启用增量备份 (使用 rsync 的 --link-dest)。
CONF_INCREMENTAL_BACKUP="true"

# 是否为旧备份启用压缩。
CONF_COMPRESSION_ENABLE="true"
# 压缩方法: gzip, bzip2, xz
CONF_COMPRESSION_METHOD="xz"
# 压缩级别 (取决于压缩方法, 例如 gzip/xz 为 1-9, xz 默认为 6)
CONF_COMPRESSION_LEVEL="6"
# CONF_COMPRESSION_EXT 会自动根据 METHOD 设置，无需手动配置 (e.g. tar.xz)

# === 保留策略 ===
# 保留最近多少个 *未压缩* 的快照。
# 如果启用了增量备份，这些快照将用于 --link-dest。最少为1。
CONF_RETENTION_UNCOMPRESSED_COUNT="3"

# 如何清理 *已压缩* 的归档文件:
# 保留特定数量的压缩归档 (0 禁用基于数量的保留)。
CONF_RETENTION_COMPRESSED_COUNT="10"
# 删除超过 X 天的压缩归档 (0 禁用基于时间的保留)。
CONF_RETENTION_COMPRESSED_DAYS="90"
# 两者都可设置。脚本会先按时间删除，然后如果数量仍超出，则删除最旧的以满足数量限制。

# === 高级功能 ===
# 并行备份任务的数量。
# 如果 > 1, 需要 GNU Parallel。如果找不到 parallel 或值为 1, 则回退到串行执行。
CONF_PARALLEL_JOBS="2" # 设置为 1 表示串行执行。推荐值不超过 CPU 核心数的一半到2/3，视磁盘IO瓶颈。

# === 资源使用控制 ===
# 是否使用 'nice' 来降低备份进程的 CPU 优先级。
CONF_USE_NICE="false" # 设置为 "true" 启用
CONF_NICE_LEVEL="10"  # nice 值 (0 表示最高优先级, 19 表示最低优先级)

# 是否使用 'ionice' 来降低备份进程的磁盘 I/O 优先级。
CONF_USE_IONICE="false" # 设置为 "true" 启用
CONF_IONICE_CLASS="2"   # ionice 类别: 1 (实时), 2 (尽力而为/best-effort), 3 (空闲/idle)
                        # 通常为 2 (best-effort) 或 3 (idle)
CONF_IONICE_LEVEL="4"   # ionice 级别 (对于 best-effort, 0-7, 数字越小优先级越高。用 4-7 来降低优先级)

# === 用户交互与安全 ===
# 在执行有风险的操作前 (例如删除旧备份) 是否提示用户确认。
# 对于 cron 作业或无头服务器，应设置为 "false"。
CONF_PROMPT_FOR_CONFIRMATION="false"

# 备份目标路径上要求的最小剩余磁盘空间百分比。
CONF_MIN_FREE_DISK_SPACE_PERCENT="10"
# 是否启用钩子
CONF_HOOKS_ENABLE="true"
CONF_HOOKS_BASE_DIR="/etc/arch_backup/hooks.d"
EOF
}

################################################################################
# 加载脚本配置文件。
# (Now includes auto-config generation and finalized log path setup)
################################################################################
load_config() {
    # _setup_final_log_path 将在配置加载后被调用来确定最终日志路径
    # log_msg 在此之前可能使用初始的 ACTUAL_LOG_FILE
    log_msg INFO "开始加载配置文件..."
    log_msg INFO "获取目标用户信息, 用于确定用户特定配置文件路径"
    get_target_backup_user_info # 获取目标用户信息, 用于确定用户特定配置文件路径

    local config_file_search_paths=()
    # 优先用户家目录下的配置
    if [[ -n "$TARGET_BACKUP_HOME" && -d "$TARGET_BACKUP_HOME" ]]; then
        config_file_search_paths+=(
            "${TARGET_BACKUP_HOME}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
            "${TARGET_BACKUP_HOME}/.config/arch_backup.conf"
        )
    fi
    # 其次是 sudo 用户家目录 (如果不同于 TARGET_BACKUP_HOME 且存在)
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        local sudo_user_home
        sudo_user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [[ -n "$sudo_user_home" && -d "$sudo_user_home" && "$sudo_user_home" != "$TARGET_BACKUP_HOME" ]]; then
            config_file_search_paths+=(
                "${sudo_user_home}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
                "${sudo_user_home}/.config/arch_backup.conf"
            )
        fi
    fi
    # 最后是系统级配置
    config_file_search_paths+=(
        "/etc/$(basename "$SCRIPT_NAME" .sh).conf"
        "/etc/arch_backup.conf"
        "/etc/arch_backup/arch_backup.conf"
        "${SCRIPT_DIR}/$(basename "$SCRIPT_NAME" .sh).conf" # 同目录下
    )
    # 去重并移除空路径
    config_file_paths=($(printf "%s\n" "${config_file_search_paths[@]}" | awk '!seen[$0]++' | grep .))

    # 如果不想用/etc/arch_backup/目录下的配置，就在用户目录的.config目录下新建一个arch_backup.conf,找到这个之后就不会继续找了
    for cf_path in "${config_file_paths[@]}"; do
        if [[ -f "$cf_path" ]]; then
            log_msg INFO "找到配置文件: $cf_path"
            # shellcheck source=/dev/null
            source "$cf_path"
            LOADED_CONFIG_FILE="$cf_path"
            log_msg INFO "成功加载配置文件: $LOADED_CONFIG_FILE"
            # 如果配置文件中指定了 CONF_TARGET_USERNAME, 需要重新评估目标用户
            get_target_backup_user_info
            break
        fi
    done

    if [[ -z "$LOADED_CONFIG_FILE" ]]; then
        log_msg WARN "未找到配置文件。搜索路径:"
        for cf_path in "${config_file_paths[@]}"; do log_msg WARN "  - $cf_path"; done
        
        local user_config_dir_candidate="${HOME}/.config"
        # 尝试 SUDO_USER 的家目录 (如果当前是 root 且 SUDO_USER存在)
        if [[ "$EFFECTIVE_UID" -eq 0 && -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
            local sudo_user_home_for_conf
            sudo_user_home_for_conf=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            [[ -n "$sudo_user_home_for_conf" ]] && user_config_dir_candidate="${sudo_user_home_for_conf}/.config"
        elif [[ -n "$TARGET_BACKUP_HOME" ]]; then # 或使用已确定的目标用户家目录
             user_config_dir_candidate="${TARGET_BACKUP_HOME}/.config"
        fi
        
        local default_config_path_to_propose="${user_config_dir_candidate}/$(basename "$SCRIPT_NAME" .sh).conf"

        # 确保在提议前 confirm_action 能工作 (至少输出到终端)
        # CONF_PROMPT_FOR_CONFIRMATION 此时仍为默认值 "false"
        if confirm_action "未找到配置文件。是否在 '$default_config_path_to_propose' 创建一个默认配置文件？"; then
            mkdir -p "$user_config_dir_candidate" || { log_msg ERROR "无法创建目录 '$user_config_dir_candidate' 以存放默认配置。"; exit 1; }
            if _generate_default_config_content > "$default_config_path_to_propose"; then
                log_msg INFO "默认配置文件已创建于 '$default_config_path_to_propose'。"
                log_msg INFO "请检查并根据您的需求修改此文件, 然后重新运行脚本。"
                # 尝试加载新创建的配置文件
                if [[ -f "$default_config_path_to_propose" ]]; then
                     # shellcheck source=/dev/null
                    source "$default_config_path_to_propose"
                    LOADED_CONFIG_FILE="$default_config_path_to_propose"
                    log_msg INFO "已加载新创建的默认配置文件。"
                    get_target_backup_user_info # 再次获取用户信息
                fi
                # 首次生成后，通常用户需要编辑，所以可以选择退出
                log_msg WARN "建议: 编辑新生成的配置文件 '$default_config_path_to_propose' 后再正式运行备份。"
                exit 0 # 或者 return 1 让主流程判断是否继续
            else
                log_msg ERROR "创建默认配置文件 '$default_config_path_to_propose' 失败。"
            fi
        else
            log_msg INFO "将使用内置的默认设置继续运行。"
        fi
    fi

    # 根据加载的配置（或默认值）设置最终日志路径和级别
    _setup_final_log_path # <--- 在这里最终确定 ACTUAL_LOG_FILE

    case "${CONF_LOG_LEVEL^^}" in
        DEBUG) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;; INFO) CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO  ;;
        WARN)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN  ;; ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        FATAL_ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_FATAL ;;
        *) log_msg WARN "无效的 CONF_LOG_LEVEL '${CONF_LOG_LEVEL}'. 将使用默认级别 INFO."; CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac
    log_msg DEBUG "当前日志级别设置为: ${LOG_LEVEL_NAMES[$CURRENT_LOG_LEVEL]} ($CURRENT_LOG_LEVEL)"


    if [[ -z "$CONF_BACKUP_ROOT_DIR" ]]; then
        log_msg FATAL_ERROR "CONF_BACKUP_ROOT_DIR 未在配置文件中设置或为空。请配置此项。" # 使用 FATAL_ERROR
        exit 1
    fi
    mkdir -p "$CONF_BACKUP_ROOT_DIR" || { log_msg FATAL_ERROR "无法创建备份根目录: $CONF_BACKUP_ROOT_DIR"; exit 1; }
    BACKUP_TARGET_DIR_UNCOMPRESSED="${CONF_BACKUP_ROOT_DIR}/snapshots"
    BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES="${CONF_BACKUP_ROOT_DIR}/archives"
    mkdir -p "$BACKUP_TARGET_DIR_UNCOMPRESSED" || { log_msg FATAL_ERROR "无法创建快照目录: $BACKUP_TARGET_DIR_UNCOMPRESSED"; exit 1; }
    mkdir -p "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" || { log_msg FATAL_ERROR "无法创建归档目录: $BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES"; exit 1; }

    case "$CONF_COMPRESSION_METHOD" in
        gzip) CONF_COMPRESSION_EXT="tar.gz" ;; bzip2) CONF_COMPRESSION_EXT="tar.bz2" ;;
        xz) CONF_COMPRESSION_EXT="tar.xz" ;;
        *) log_msg WARN "未知的压缩方法 '$CONF_COMPRESSION_METHOD'. CONF_COMPRESSION_EXT 可能不正确";;
    esac

    if [[ "${CONF_PARALLEL_JOBS:-1}" -gt 1 ]]; then
        if command -v parallel &>/dev/null; then
            PARALLEL_CMD="parallel --no-notice --jobs $CONF_PARALLEL_JOBS --halt soon,fail=1"
            log_msg INFO "找到 GNU Parallel。将尝试使用 $CONF_PARALLEL_JOBS 个并行任务。"
        else
            log_msg WARN "未找到 GNU Parallel，但 CONF_PARALLEL_JOBS ($CONF_PARALLEL_JOBS) > 1。将回退到串行执行。"
            CONF_PARALLEL_JOBS=1; PARALLEL_CMD=""
        fi
    else
        CONF_PARALLEL_JOBS=1; PARALLEL_CMD=""
        log_msg INFO "将使用串行方式执行备份任务 (CONF_PARALLEL_JOBS: $CONF_PARALLEL_JOBS)。"
    fi
    log_msg INFO "配置文件加载和初始化完成。"
}

################################################################################
# 检查指定路径上的可用磁盘空间百分比。
# Globals:
#   None
# Arguments:
#   $1 - 需要检查磁盘空间的路径。
#   $2 - 要求的最小剩余磁盘空间百分比。
# Returns:
#   0 如果磁盘空间充足。
#   脚本会以状态码 1 退出，如果磁盘空间不足。
#   如果无法获取磁盘空间信息，则记录警告并返回 0 (跳过检查)。
################################################################################
check_disk_space() {
    local path_to_check="$1"
    local required_percent="$2"
    local available_space_used_percent
    log_msg INFO "检查路径 '$path_to_check' 的可用磁盘空间 (要求最小剩余 ${required_percent}%)..."
    if ! available_space_used_percent=$(df --output=pcent "$path_to_check" 2>/dev/null | tail -n 1 | sed 's/%//' | xargs); then
        log_msg WARN "无法获取路径 '$path_to_check' 的磁盘使用百分比。跳过磁盘空间检查。"
        return 0
    fi
    local free_space_percent=$((100 - available_space_used_percent))

    if [[ "$free_space_percent" -lt "$required_percent" ]]; then
        log_msg ERROR "路径 '$path_to_check' 磁盘空间不足。可用: ${free_space_percent}%, 要求: ${required_percent}%。"
        exit 1
    else
        log_msg INFO "路径 '$path_to_check' 磁盘空间检查通过。可用: ${free_space_percent}% (要求: ${required_percent}% 剩余)。"
    fi
}

# (将其放在 arch_backup.sh 的辅助函数区域)

################################################################################
# _run_hooks - 执行指定事件类型的所有钩子脚本。
#
# Globals (R):
#   CONF_HOOKS_ENABLE             - 是否启用钩子。
#   CONF_HOOKS_BASE_DIR           - 钩子脚本的根目录。
#   CURRENT_TIMESTAMP             - 当前备份的时间戳 (作为参数传递给钩子)。
#   BACKUP_TARGET_DIR_UNCOMPRESSED - 当前未压缩备份的路径 (作为参数传递给钩子)。
#   ACTUAL_LOG_FILE               - 当前脚本的日志文件路径 (作为参数传递给钩子)。
#   <other relevant global vars>  - 可以选择性地导出更多变量给钩子脚本。
#
# Arguments:
#   $1 - (String) hook_event_name - 钩子事件的名称。这将决定在 CONF_HOOKS_BASE_DIR
#                                   下查找哪个子目录中的脚本。
#                                   例如: "pre-backup", "post-backup-success",
#                                         "pre-task-system_config", "post-task-user_data-failure"
#   $@ - (Optional, Strings) context_args - 传递给每个钩子脚本的额外参数。
#                                           例如，对于任务相关的钩子，可以传递任务名。
#                                           对于 post-backup 钩子，可以传递备份的最终状态。
#
# Returns:
#   0 - 如果所有钩子成功执行或没有钩子执行。
#   非0 - 如果有任何钩子脚本以非零状态退出 (根据策略，这可能不中止主流程)。
#
# Side effects:
#   - 执行用户定义的脚本，这些脚本可能有任意副作用。
#   - 输出日志信息。
################################################################################
_run_hooks() {
    local hook_event_name="$1"
    shift # 移除第一个参数，剩下的是 context_args

    # 检查钩子功能是否启用
    if [[ "${CONF_HOOKS_ENABLE:-false}" != "true" ]]; then
        log_msg DEBUG "[Hooks] 钩子功能未启用 (CONF_HOOKS_ENABLE)。跳过 '$hook_event_name' 钩子。"
        return 0
    fi

    # 确定钩子脚本所在的目录
    # 假设钩子子目录直接以 event_name 命名，位于 CONF_HOOKS_BASE_DIR 之下
    local hook_dir="${CONF_HOOKS_BASE_DIR%/}/${hook_event_name}" # %/ 移除末尾斜杠（如果存在）再添加

    if [[ ! -d "$hook_dir" ]]; then
        log_msg DEBUG "[Hooks] 未找到 '$hook_event_name' 的钩子目录: '$hook_dir'。无需执行钩子。"
        return 0
    fi

    log_msg INFO "[Hooks] 开始执行 '$hook_event_name' 事件的钩子 (来自目录: '$hook_dir')..."
    local overall_hook_status=0 # 用于记录是否有钩子失败

    # 查找并按文件名顺序执行所有可执行文件
    # 使用 find 和 sort 来处理文件名，并确保它们是可执行的常规文件
    # -print0 和 read -d $'\0' 用于安全处理包含特殊字符的文件名
    find "$hook_dir" -mindepth 1 -maxdepth 1 -type f -executable -print0 2>/dev/null | sort -z | while IFS= read -r -d $'\0' hook_script_path; do
        local hook_script_name
        hook_script_name=$(basename "$hook_script_path")
        log_msg INFO "[Hooks]   执行钩子脚本: '$hook_script_name' (事件: $hook_event_name)"

        # 准备传递给钩子脚本的环境变量 (除了参数，环境变量也是一种上下文传递方式)
        # 这些变量在钩子脚本中可以直接使用
        export HOOK_EVENT_NAME="$hook_event_name"
        export HOOK_CURRENT_TIMESTAMP="$CURRENT_TIMESTAMP"
        export HOOK_BACKUP_SNAPSHOT_DIR="$BACKUP_TARGET_DIR_UNCOMPRESSED" # 包含当前时间戳的快照根
        export HOOK_CURRENT_SNAPSHOT_PATH="${BACKUP_TARGET_DIR_UNCOMPRESSED%/}/${CURRENT_TIMESTAMP}" # 本次备份的快照路径
        export HOOK_MAIN_LOG_FILE="$ACTUAL_LOG_FILE" # 主备份脚本的日志文件
        # 可以根据需要添加更多如 HOOK_BACKUP_ROOT_DIR, HOOK_ARCHIVE_DIR 等

        # 执行钩子脚本，并传递额外的上下文参数 (如果 _run_hooks 被调用时提供了)
        if "$hook_script_path" "$@"; then # "$@" 会将 _run_hooks 接收到的 context_args 传递过去
            log_msg DEBUG "[Hooks]     钩子脚本 '$hook_script_name' 执行成功。"
        else
            local hook_exit_code=$?
            log_msg WARN "[Hooks]     钩子脚本 '$hook_script_name' 执行失败 (退出码: $hook_exit_code)。"
            overall_hook_status=1 # 标记至少有一个钩子失败了
            # 根据策略，决定是否因为钩子失败而中止主备份流程
            # 默认情况下，我们只记录警告，不中止主流程，除非钩子内部自己 exit 1
            # 如果需要中止，可以在这里 `return $hook_exit_code` 或 `exit $hook_exit_code`
        fi

        # 清理为本次钩子导出的环境变量 (可选，如果担心污染后续钩子或主脚本环境)
        # unset HOOK_EVENT_NAME HOOK_CURRENT_TIMESTAMP ... (通常不需要，因为子进程环境独立)
    done

    if [[ "$overall_hook_status" -eq 0 ]]; then
        log_msg INFO "[Hooks] '$hook_event_name' 事件的所有钩子执行完毕 (或无钩子执行)。"
    else
        log_msg WARN "[Hooks] '$hook_event_name' 事件的部分钩子执行失败。请检查日志。"
    fi

    return "$overall_hook_status"
}


################################################################################
# 为实际命令 (rsync, tar) 构建资源控制前缀 (nice, ionice)。
# Globals:
#   CONF_USE_NICE, CONF_NICE_LEVEL
#   CONF_USE_IONICE, CONF_IONICE_CLASS, CONF_IONICE_LEVEL
# Arguments:
#   None
# Returns:
#   Array of command prefixes.
################################################################################
_get_resource_cmd_prefix_array() {
    local cmd_prefix_array=()
    if [[ "$CONF_USE_NICE" == "true" ]]; then
        if command -v nice &>/dev/null; then
            cmd_prefix_array+=("nice" "-n" "${CONF_NICE_LEVEL:-10}")
        else
            log_msg WARN "'nice' 命令未找到, 但 CONF_USE_NICE=true。将忽略 nice 设置。"
        fi
    fi
    if [[ "$CONF_USE_IONICE" == "true" ]]; then
        if command -v ionice &>/dev/null; then
            cmd_prefix_array+=("ionice" "-c" "${CONF_IONICE_CLASS:-2}" "-n" "${CONF_IONICE_LEVEL:-4}")
        else
            log_msg WARN "'ionice' 命令未找到, 但 CONF_USE_IONICE=true。将忽略 ionice 设置。"
        fi
    fi
    echo "${cmd_prefix_array[@]}" # Returns as a string, caller should convert to array if needed
}

################################################################################
# 在指定目录内生成 MANIFEST.txt 文件。
# Manifest 包含文件列表、大小和修改时间。
# Globals: None
# Arguments:
#   $1 - 要生成清单的目标目录的完整路径。
#   $2 - 清单文件的名称 (默认为 MANIFEST.txt)。
# Returns:
#   0 on success, 1 on failure.
################################################################################
_generate_manifest() {
    local target_dir="$1"
    local manifest_filename="${2:-MANIFEST.txt}"
    local manifest_path="${target_dir}/${manifest_filename}"

    if [[ ! -d "$target_dir" ]]; then
        log_msg WARN "[Manifest] 目录 '$target_dir' 不存在，无法生成清单。"
        return 1
    fi

    log_msg DEBUG "[Manifest] 正在为 '$target_dir' 生成清单文件 '$manifest_path'..."
    local item_count=0
    # Use find to get relative paths (%P), modification time (%T@), size (%s)
    # Redirect stderr to /dev/null to suppress "Permission denied" for unreadable subdirs (should not happen with rsync numeric-ids)
    if (cd "$target_dir" && find . -type f -printf "%T@ %s %P\n" 2>/dev/null > "$manifest_filename"); then
        item_count=$(wc -l < "$manifest_path" | awk '{print $1}')
        log_msg INFO "[Manifest] 成功为 '$target_dir' 生成清单 '$manifest_filename' (包含 $item_count 个文件条目)。"
        # 可选：记录清单文件的哈希值
        # local manifest_hash=$(sha256sum "$manifest_path" | cut -d' ' -f1)
        # log_msg DEBUG "[Manifest] 清单 '$manifest_path' SHA256: $manifest_hash"
        return 0
    else
        log_msg WARN "[Manifest] 为 '$target_dir' 生成清单 '$manifest_filename' 失败。"
        rm -f "$manifest_path" # Clean up partial manifest
        return 1
    fi
}

################################################################################
# 执行通用的 rsync 备份操作。
# 此函数被其他特定备份任务函数调用。
# Globals:
#   BACKUP_TARGET_DIR_UNCOMPRESSED (R) - 未压缩备份的根目录。
#   CURRENT_TIMESTAMP              (R) - 当前备份的时间戳。
#   CONF_USER_HOME_EXCLUDE         (R) - 用户家目录的排除列表 (如果 task_name 是 "用户数据")。
#   CONF_CUSTOM_PATHS_EXCLUDE      (R) - 自定义路径的排除列表 (如果 task_name 是 "自定义路径")。
#   SCRIPT_NAME                    (R) - 用于生成临时文件名。
# Arguments:
#   $1 - 备份任务的描述性名称 (用于日志)。
#   $2 - 在当前时间戳目录下创建的目标子目录名称 (如 "etc", "home_USER")。
#   $3 - rsync 的 --link-dest 选项字符串 (如果启用增量备份) 或空字符串。
#   $@ - (从第四个参数开始) 一个或多个要备份的源文件/目录路径。
# Returns:
#   0 如果 rsync 成功完成。
#   rsync 的退出码如果失败。
################################################################################
_perform_rsync_backup() {
    local task_name="$1"
    local dest_subdir_name="$2"
    local link_dest_opt="$3"
    shift 3
    local sources_array=("$@")
    local rsync_dest_path="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/${dest_subdir_name}/"

    mkdir -p "$rsync_dest_path"
    log_msg DEBUG "为任务 '$task_name' 创建目标子目录: $rsync_dest_path"

    local rsync_opts_array=(
        "-aH" "--delete" "--numeric-ids" "--info=progress2"
        # "--checksum" # Consider if --link-dest reliability across file systems is a concern, or mtime changes falsely
    )
    [[ -n "$link_dest_opt" ]] && rsync_opts_array+=("$link_dest_opt")

    log_msg INFO "开始执行备份任务: $task_name"
    log_msg DEBUG "源路径 (传递给rsync): ${sources_array[*]}"
    log_msg DEBUG "目标路径: $rsync_dest_path"
    
    local temp_exclude_files=()
    if [[ "$task_name" == "用户数据" && ${#CONF_USER_HOME_EXCLUDE[@]} -gt 0 ]]; then
        local user_exclude_file
        user_exclude_file=$(mktemp "/tmp/${SCRIPT_NAME}_user_exclude.XXXXXX")
        temp_exclude_files+=("$user_exclude_file")
        printf "%s\n" "${CONF_USER_HOME_EXCLUDE[@]}" > "$user_exclude_file"
        rsync_opts_array+=("--exclude-from=$user_exclude_file")
        log_msg DEBUG "为 '$task_name' 创建了用户排除文件: $user_exclude_file 内容: $(tr '\n' ' ' < "$user_exclude_file")"
    fi
    if [[ "$task_name" == "自定义路径" && ${#CONF_CUSTOM_PATHS_EXCLUDE[@]} -gt 0 ]]; then
        local custom_exclude_file
        custom_exclude_file=$(mktemp "/tmp/${SCRIPT_NAME}_custom_exclude.XXXXXX")
        temp_exclude_files+=("$custom_exclude_file")
        printf "%s\n" "${CONF_CUSTOM_PATHS_EXCLUDE[@]}" > "$custom_exclude_file"
        rsync_opts_array+=("--exclude-from=$custom_exclude_file")
        log_msg DEBUG "为 '$task_name' 创建了自定义排除文件: $custom_exclude_file 内容: $(tr '\n' ' ' < "$custom_exclude_file")"
    fi

    if [[ ${#sources_array[@]} -eq 0 ]]; then
        log_msg WARN "任务 '$task_name': 没有有效的源路径可供备份 (可能已被预先过滤)。"
        for tmp_file in "${temp_exclude_files[@]}"; do rm -f "$tmp_file"; done
        return 0
    fi

    local resource_prefix_arr_str=$(_get_resource_cmd_prefix_array)
    local rsync_cmd_array=()
    # Convert string back to array for prefix commands
    # shellcheck disable=SC2206 # Word splitting is intended here
    [[ -n "$resource_prefix_arr_str" ]] && rsync_cmd_array=($resource_prefix_arr_str)
    rsync_cmd_array+=("rsync" "${rsync_opts_array[@]}" "${sources_array[@]}" "$rsync_dest_path")

    log_msg DEBUG "执行 rsync 命令: ${rsync_cmd_array[*]}"
    local rsync_start_time=$(date +%s)
    if "${rsync_cmd_array[@]}"; then
        local rsync_end_time=$(date +%s)
        local rsync_duration=$((rsync_end_time - rsync_start_time))
        log_msg INFO "成功完成备份任务: $task_name (耗时: ${rsync_duration}s)"
        _generate_manifest "$rsync_dest_path" "MANIFEST.txt"
    else
        local rsync_exit_code=$?
        local rsync_end_time=$(date +%s)
        local rsync_duration=$((rsync_end_time - rsync_start_time))
        log_msg ERROR "备份任务失败: $task_name (rsync 退出码: $rsync_exit_code, 耗时: ${rsync_duration}s)"
        for tmp_file in "${temp_exclude_files[@]}"; do rm -f "$tmp_file"; done
        return "$rsync_exit_code"
    fi

    for tmp_file in "${temp_exclude_files[@]}"; do
        rm -f "$tmp_file"
        log_msg DEBUG "已删除临时排除文件: $tmp_file"
    done
    return 0
}

################################################################################
# 备份系统配置文件 (通常是 /etc)。
# Globals:
#   CONF_BACKUP_SYSTEM_CONFIG (R) - 是否启用此备份类别。
#   EFFECTIVE_UID             (R) - 当前脚本的有效用户ID。
# Arguments:
#   $1 - (传递给 _perform_rsync_backup) rsync 的 --link-dest 选项。
# Returns:
#   0 如果成功或跳过。
#   1 如果因权限问题而跳过或 _perform_rsync_backup 失败。
################################################################################
backup_system_config() {
    if [[ "$CONF_BACKUP_SYSTEM_CONFIG" != "true" ]]; then log_msg INFO "[系统配置] 跳过备份 (未启用)。"; return 0; fi
    log_msg INFO "[系统配置] 开始处理系统配置文件备份..."
    if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
        log_msg WARN "[系统配置] 跳过备份: 备份 /etc 需要 root 权限。"
        return 1
    fi
    log_msg DEBUG "[系统配置] 源路径: /etc/"
    _perform_rsync_backup "系统配置 (/etc)" "etc" "$1" "/etc/"
}

################################################################################
# 备份目标用户的家目录中的选定文件和数据。
# Globals:
#   CONF_BACKUP_USER_DATA    (R) - 是否启用此备份类别。
#   TARGET_BACKUP_USER       (R) - 目标用户名。
#   TARGET_BACKUP_HOME       (R) - 目标用户家目录。
#   CONF_USER_HOME_INCLUDE   (R) - 要包含在家目录备份中的项目列表。
# Arguments:
#   $1 - (传递给 _perform_rsync_backup) rsync 的 --link-dest 选项。
# Returns:
#   0 如果成功、跳过或没有有效源。
#   如果 _perform_rsync_backup 失败则返回其退出码。
################################################################################
backup_user_data() {
    if [[ "$CONF_BACKUP_USER_DATA" != "true" ]]; then log_msg INFO "[用户数据] 跳过备份 (未启用)。"; return 0; fi
    if [[ -z "$TARGET_BACKUP_HOME" ]]; then
        log_msg WARN "[用户数据] 跳过备份: 无法确定有效的用户家目录 (TARGET_BACKUP_HOME 未设置)。"
        return 0
    fi
    log_msg INFO "[用户数据] 开始处理用户 '${TARGET_BACKUP_USER}' (家目录: ${TARGET_BACKUP_HOME}) 的数据备份..."

    local valid_user_sources=()
    log_msg DEBUG "[用户数据] 配置文件中指定的包含项 (相对于家目录 '${TARGET_BACKUP_HOME}'): ${CONF_USER_HOME_INCLUDE[*]}"
    for item in "${CONF_USER_HOME_INCLUDE[@]}"; do
        local full_path="${TARGET_BACKUP_HOME}/${item}"
        if [[ -e "$full_path" ]]; then
            valid_user_sources+=("$full_path")
            log_msg DEBUG "[用户数据] 有效源 (存在): $full_path"
        else
            log_msg WARN "[用户数据] 源路径 '$full_path' 不存在，将跳过此项。"
        fi
    done

    if [[ ${#valid_user_sources[@]} -eq 0 ]]; then
        log_msg WARN "[用户数据] 跳过备份: CONF_USER_HOME_INCLUDE 中未找到任何实际存在的项目。"
        return 0
    fi
    log_msg INFO "[用户数据] 将备份以下有效源 (${#valid_user_sources[@]} 个): ${valid_user_sources[*]}"
    _perform_rsync_backup "用户数据" "home_${TARGET_BACKUP_USER}" "$1" "${valid_user_sources[@]}"
}

################################################################################
# 备份已安装的软件包列表。
# Globals:
#   CONF_BACKUP_PACKAGES             (R) - 是否启用此备份类别。
#   BACKUP_TARGET_DIR_UNCOMPRESSED (R)
#   CURRENT_TIMESTAMP              (R)
# Arguments:
#   None
# Returns:
#   0 总是成功 (除非 pacman 命令严重失败，但这通常不会中止脚本)。
################################################################################
backup_packages() {
    if [[ "$CONF_BACKUP_PACKAGES" != "true" ]]; then log_msg INFO "[软件包列表] 跳过备份 (未启用)。"; return 0; fi
    log_msg INFO "[软件包列表] 开始备份已安装的软件包列表..."
    local pkg_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/packages/"
    mkdir -p "$pkg_dest_dir"

    local official_list="${pkg_dest_dir}/packages_official.list"
    local aur_foreign_list="${pkg_dest_dir}/packages_aur_foreign.list"
    local all_versions_list="${pkg_dest_dir}/packages_all_versions.list"
    local official_count aur_foreign_count all_versions_count

    if pacman -Qqe > "$official_list"; then
        official_count=$(wc -l < "$official_list" | awk '{print $1}')
        log_msg DEBUG "[软件包列表] 官方包列表已保存至 $official_list ($official_count 个包)"
    else
        log_msg WARN "[软件包列表] 获取官方包列表失败。"
    fi

    if pacman -Qqm > "$aur_foreign_list"; then
        aur_foreign_count=$(wc -l < "$aur_foreign_list" | awk '{print $1}')
        log_msg DEBUG "[软件包列表] AUR/非官方包列表已保存至 $aur_foreign_list ($aur_foreign_count 个包)"
    else
        log_msg WARN "[软件包列表] 获取AUR/非官方包列表失败。"
    fi
    
    if pacman -Q > "$all_versions_list"; then
        all_versions_count=$(wc -l < "$all_versions_list" | awk '{print $1}')
        log_msg DEBUG "[软件包列表] 所有包带版本信息列表已保存至 $all_versions_list ($all_versions_count 个条目)"
    else
        log_msg WARN "[软件包列表] 获取所有包带版本信息列表失败。"
    fi

    _generate_manifest "$pkg_dest_dir" "MANIFEST_packages.txt"
    log_msg INFO "[软件包列表] 备份完成，存放于 $pkg_dest_dir"
    return 0
}

################################################################################
# 备份系统日志 (journalctl 输出和 /var/log 下的指定文件)。
# Globals:
#   CONF_BACKUP_LOGS                 (R) - 是否启用此备份类别。
#   CONF_BACKUP_JOURNALCTL           (R) - 是否备份 journalctl。
#   CONF_JOURNALCTL_ARGS             (R) - journalctl 的参数。
#   CONF_SYSTEM_LOG_FILES            (R) - /var/log 下要备份的文件列表。
#   BACKUP_TARGET_DIR_UNCOMPRESSED (R)
#   CURRENT_TIMESTAMP              (R)
#   EFFECTIVE_UID                  (R)
# Arguments:
#   None
# Returns:
#   0 总是成功 (日志备份中的错误通常视为非关键)。
################################################################################
backup_logs() {
    if [[ "$CONF_BACKUP_LOGS" != "true" ]]; then log_msg INFO "[系统日志] 跳过备份 (未启用)。"; return 0; fi
    log_msg INFO "[系统日志] 开始备份系统日志..."
    local logs_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/logs/"
    mkdir -p "$logs_dest_dir"

    if [[ "$CONF_BACKUP_JOURNALCTL" == "true" ]]; then
        local journal_log_file="${logs_dest_dir}/journal.log"
        log_msg DEBUG "[系统日志] 尝试备份 journalctl (参数: ${CONF_JOURNALCTL_ARGS:-<无>}) 至 $journal_log_file"
        if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
            log_msg WARN "[系统日志] 备份 journalctl 可能需要 root 权限以获取完整日志。"
        fi
        # shellcheck disable=SC2086 # CONF_JOURNALCTL_ARGS is intentionally split
        if journalctl ${CONF_JOURNALCTL_ARGS} > "$journal_log_file"; then
            log_msg DEBUG "[系统日志] journalctl 输出已保存 (大小: $(du -sh "$journal_log_file" | cut -f1))."
        else
            log_msg WARN "[系统日志] 备份 journalctl 失败 (非关键错误)。"
        fi
    fi

    if [[ ${#CONF_SYSTEM_LOG_FILES[@]} -gt 0 ]]; then
        log_msg DEBUG "[系统日志] 配置文件中指定的系统日志文件/目录: ${CONF_SYSTEM_LOG_FILES[*]}"
        if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
             log_msg WARN "[系统日志] 备份 /var/log/* 下的文件需要 root 权限，当前非 root 用户，将跳过这些文件。"
        else
            for log_file_item in "${CONF_SYSTEM_LOG_FILES[@]}"; do
                local source_log_path="/var/log/${log_file_item}"
                if [[ -e "$source_log_path" ]]; then
                    log_msg DEBUG "[系统日志] 尝试复制 $source_log_path 至 $logs_dest_dir"
                    if cp -aL "$source_log_path" "${logs_dest_dir}/"; then # -L to follow symlinks like /var/log/journal
                         log_msg DEBUG "[系统日志] 已复制 $log_file_item."
                    else
                         log_msg WARN "[系统日志] 复制日志 '$source_log_path' 失败 (非关键错误)。"
                    fi
                else
                    log_msg WARN "[系统日志] 日志 '$source_log_path' 未找到。"
                fi
            done
        fi
    fi
    _generate_manifest "$logs_dest_dir" "MANIFEST_logs.txt"
    log_msg INFO "[系统日志] 备份完成，存放于 $logs_dest_dir"
    return 0
}

################################################################################
# 备份用户在配置文件中指定的自定义文件或目录路径。
# Globals:
#   CONF_BACKUP_CUSTOM_PATHS (R) - 是否启用此备份类别。
#   CONF_CUSTOM_PATHS_INCLUDE (R) - 要包含的自定义路径列表。
#   EFFECTIVE_UID             (R)
# Arguments:
#   $1 - (传递给 _perform_rsync_backup) rsync 的 --link-dest 选项。
# Returns:
#   0 如果成功、跳过或没有有效源。
#   1 如果某些路径因权限问题无法访问且脚本非 root 运行。
#   如果 _perform_rsync_backup 失败则返回其退出码。
################################################################################
backup_custom_paths() {
    if [[ "$CONF_BACKUP_CUSTOM_PATHS" != "true" ]]; then log_msg INFO "[自定义路径] 跳过备份 (未启用)。"; return 0; fi
    log_msg INFO "[自定义路径] 开始处理自定义路径备份..."

    local valid_custom_sources=()
    local path_access_issue=false
    log_msg DEBUG "[自定义路径] 配置文件中指定的包含项: ${CONF_CUSTOM_PATHS_INCLUDE[*]}"

    for path_item in "${CONF_CUSTOM_PATHS_INCLUDE[@]}"; do
        if [[ ! -e "$path_item" ]]; then
            log_msg WARN "[自定义路径] 源路径 '$path_item' 不存在，将跳过此项。"
            continue
        fi

        local current_path_ok=true
        # Test read access; for directories, test execute access too for listing
        local access_test_path="$path_item"
        [[ -d "$path_item" && ! -x "$path_item" ]] && access_test_path="${path_item}/." # trick for findability check

        if ! sudo -u "#$EFFECTIVE_UID" test -r "$access_test_path"; then # Test as current effective user
            if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
                 # If not root, check if sudo might help (this is indicative, rsync itself needs appropriate perms)
                if sudo -n true 2>/dev/null && sudo test -r "$access_test_path"; then
                    log_msg DEBUG "[自定义路径] 源 '$path_item' 在 sudo下可读 (提示: rsync 仍需以 root 权限运行才能备份此路径)。"
                else
                    log_msg WARN "[自定义路径] 源 '$path_item' 不可读 (当前非root，尝试sudo检查失败或未配置)，将跳过此项。"
                    current_path_ok=false
                    path_access_issue=true
                fi
            else # Already root
                log_msg WARN "[自定义路径] 源 '$path_item' 作为 root 也不可读，将跳过此项。"
                current_path_ok=false
                path_access_issue=true # This is a more severe issue if root can't read
            fi
        fi


        if $current_path_ok; then
            valid_custom_sources+=("$path_item")
            log_msg DEBUG "[自定义路径] 有效源 (存在且可访问性已检查): $path_item"
        fi
    done

    if [[ ${#valid_custom_sources[@]} -eq 0 ]]; then
        log_msg WARN "[自定义路径] 跳过备份: CONF_CUSTOM_PATHS_INCLUDE 中未找到任何实际存在且可访问的项目。"
        return "$([ $path_access_issue == true ] && echo 1 || echo 0)"
    fi
    log_msg INFO "[自定义路径] 将备份以下有效源 (${#valid_custom_sources[@]} 个): ${valid_custom_sources[*]}"
    _perform_rsync_backup "自定义路径" "custom" "$1" "${valid_custom_sources[@]}"
}

################################################################################
# 备份系统当前的关键状态信息。
# 包括：系统摘要、网络详情、存储详情、定时任务、Systemd单元、防火墙规则等。
# 此函数是 arch_backup.sh 的一部分，应独立运行，不依赖外部框架。
# Globals:
#   CONF_BACKUP_SYSTEM_STATE_INFO (R) - 是否启用此备份类别 (来自 arch_backup.conf)。
#   BACKUP_TARGET_DIR_UNCOMPRESSED (R) - 未压缩备份的根目录。
#   CURRENT_TIMESTAMP              (R) - 当前备份的时间戳。
#   SCRIPT_VERSION                 (R) - 当前 arch_backup.sh 脚本的版本。
#   LOADED_CONFIG_FILE             (R) - 加载的 arch_backup.conf 路径。
#   EFFECTIVE_UID                  (R) - arch_backup.sh 脚本的有效用户ID。
#   CONF_TARGET_USERNAME           (R) - 配置文件中指定的目标用户名 (用于用户级信息收集)。
# Arguments:
#   None
# Returns:
#   0 如果成功或跳过。
#   如果主要信息收集步骤失败，可能会返回非0，但通常会记录警告并继续。
################################################################################
backup_system_state_info() {
    # 检查是否启用了此备份类别
    if [[ "${CONF_BACKUP_SYSTEM_STATE_INFO:-false}" != "true" ]]; then
        log_msg INFO "[系统状态信息] 跳过备份 (CONF_BACKUP_SYSTEM_STATE_INFO 未启用或为 false)。"
        return 0
    fi

    log_msg INFO "[系统状态信息] 开始收集系统关键状态信息..."
    local state_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/system_info/"
    if ! mkdir -p "$state_dest_dir"; then
        log_msg ERROR "[系统状态信息] 无法创建目标目录 '$state_dest_dir'。跳过此备份类别。"
        return 1
    fi

    # 定义将要生成的聚合信息文件名
    local summary_file="${state_dest_dir}/system_snapshot_summary.txt"
    local network_file="${state_dest_dir}/network_details.txt"
    local storage_file="${state_dest_dir}/storage_details.txt"
    local cron_jobs_file="${state_dest_dir}/cron_jobs.txt"
    local systemd_units_file="${state_dest_dir}/systemd_services_timers.txt"
    local firewall_file="${state_dest_dir}/firewall_rules.txt"

    # --- 1. 生成 system_snapshot_summary.txt (核心环境摘要) ---
    log_msg DEBUG "[系统状态信息] 1/6 生成摘要文件: $summary_file"
    # 使用大括号将多个命令的输出重定向到一个文件
    {
        echo "=== Arch Linux System Snapshot Summary ==="
        echo "Backup Task Timestamp: ${CURRENT_TIMESTAMP}"
        echo "Collection Timestamp:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Backup Script Version: ${SCRIPT_VERSION:-N/A}"
        if [[ -n "${LOADED_CONFIG_FILE:-}" ]]; then
            echo "Backup Config File:    $LOADED_CONFIG_FILE"
        else
            echo "Backup Config File:    Using default settings or not found"
        fi
        echo "----------------------------------------"

                # ... (接在 Backup Script Version 和 Config File 之后)
        echo "----------------------------------------"
        echo ">>> System Overview <<<"

        # OS
        local os_name os_arch
        os_name=$(grep -Po '^NAME="\K[^"]*' /etc/os-release 2>/dev/null || echo "Unknown OS")
        os_arch=$(uname -m)
        echo "OS:               ${os_name} ${os_arch}"

        # Host
        local host_name product_name
        host_name=$(hostnamectl status --static 2>/dev/null || hostname)
        # 尝试从 dmidecode 获取更详细的 Host/Product Name，如果失败则用 hostname
        if [[ "$EFFECTIVE_UID" -eq 0 ]] && command -v dmidecode &>/dev/null; then
            product_name=$(dmidecode -s system-product-name 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
            if [[ -n "$product_name" && "$product_name" != "None" && "$product_name" != "To Be Filled By O.E.M." ]]; then
                echo "Host:             ${product_name} (Hostname: ${host_name})"
            else
                echo "Host:             ${host_name}"
            fi
        else
            echo "Host:             ${host_name}"
        fi

        # Kernel
        echo "Kernel:           $(uname -s) $(uname -r)" # uname -s 显示内核名称 (Linux)

        # Uptime
        # uptime -p 提供更易读的格式，如果可用
        if command -v uptime &>/dev/null && uptime -p &>/dev/null; then
            echo "Uptime:           $(uptime -p | sed 's/^up //')"
        else
            echo "Uptime:           $(uptime | awk -F'( |,|:)+' '{if ($7=="min") print $6" "$7; else if ($7~/day/) print $6" "$7" "$8" "$9; else print $6" "$7" "$8}')" # 简化的 uptime 解析
        fi
        echo "" # 加个空行与下面的包信息分开

        # Packages (Pacman count)
        if command -v pacman &>/dev/null; then
            echo "Packages:         $(pacman -Q | wc -l) (pacman)"
        else
            echo "Packages:         Pacman not found"
        fi

        # Shell (当前脚本执行的 shell，或默认用户 shell)
        # $SHELL 通常是当前用户的登录 shell
        # basename "$0" 或 $BASH (如果用bash) 是脚本解释器
        # 为了获取 CONF_TARGET_USERNAME 的默认shell:
        local target_shell="N/A"
        if [[ -n "${CONF_TARGET_USERNAME:-}" ]]; then
            target_shell=$(getent passwd "${CONF_TARGET_USERNAME}" | cut -d: -f7 | xargs -r basename 2>/dev/null || echo "N/A")
            local shell_version_cmd
            if [[ "$target_shell" != "N/A" ]] && command -v "$target_shell" &>/dev/null; then
                case "$target_shell" in
                    bash) shell_version_cmd="bash --version | head -n1 | awk '{print \$4}' | sed 's/(.*//'" ;;
                    zsh)  shell_version_cmd="zsh --version | awk '{print \$2}'" ;;
                    fish) shell_version_cmd="fish --version | awk '{print \$3}'" ;;
                    *)    shell_version_cmd="" ;; # 其他shell版本获取方式可能不同
                esac
                if [[ -n "$shell_version_cmd" ]]; then
                    local shell_ver
                    shell_ver=$(eval "$shell_version_cmd" 2>/dev/null || echo "")
                    target_shell="${target_shell}${shell_ver:+" $shell_ver"}" # 如果有版本号则添加
                fi
            fi
            echo "Target User Shell: ${target_shell} (User: ${CONF_TARGET_USERNAME})"
        else
            echo "Shell:            $(basename "${SHELL:-N/A}") (Current login shell)"
        fi


        # DE (Desktop Environment) & WM (Window Manager)
        # XDG_CURRENT_DESKTOP 可能包含多个值，用冒号分隔，取第一个
        local de_raw="${XDG_CURRENT_DESKTOP:-N/A}"
        local de="${de_raw%%:*}" # 取第一个
        echo "DE:               ${de}"

        # WM - 获取 WM 比较复杂，不同的DE有不同的方式，没有一个通用简单命令
        # 对于 Xfce，通常是 xfwm4
        # 对于 cron 环境，这些 X11 相关的变量通常不存在
        local wm="N/A"
        if [[ "$de" == "XFCE" ]]; then # XDG_CURRENT_DESKTOP 对 XFCE 通常是 XFCE
            wm="Xfwm4" # 这是一个合理的猜测
            if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
                wm="${wm} (${XDG_SESSION_TYPE})"
            fi
        elif [[ -n "${XDG_SESSION_DESKTOP:-}" && "$XDG_SESSION_DESKTOP" != "$de" ]]; then # 有些情况 WM 单独设置
             wm="$XDG_SESSION_DESKTOP"
        elif [[ -n "${GDMSESSION:-}" && "$GDMSESSION" != "$de" ]]; then # GNOME 用的
             wm="$GDMSESSION"
        fi
        # 如果是 cron 环境，上述变量可能为空
        if [[ "$wm" == "N/A" ]] && [[ -n "${DESKTOP_SESSION:-}" ]]; then # 另一个可能的变量
            wm="$DESKTOP_SESSION"
        fi
        echo "WM:               ${wm}"


        # Terminal (在 cron 环境下这个信息意义不大，通常 $TERM 是 dumb)
        echo "Terminal:         ${TERM:-N/A} (Execution context)"

        # Locale
        echo "Locale:           ${LANG:-N/A}"
        echo "----------------------------------------"

        # >>> Kernel & Operating System <<< 这部分可以移到 System Overview 之后或者省略，因为上面已经有了 OS 和 Kernel
        # 如果还想保留 /etc/os-release 的部分信息（ID, BUILD_ID）可以这样做：
        echo ">>> OS Details (from /etc/os-release) <<<"
        if [ -f /etc/os-release ]; then
            grep -E '^ID=|^BUILD_ID=|^PRETTY_NAME=' /etc/os-release || cat /etc/os-release # 回退到完整输出
        else
            echo "Warning: /etc/os-release not found"
        fi
        echo "----------------------------------------"

        # >>> Hostname & Uptime <<< 也被上面的 Host 和 Uptime 覆盖了

        # >>> CPU & Memory Overview <<< (保持您之前的良好格式)
        echo ">>> CPU & Memory Overview <<<"
        local lscpu_output
        lscpu_output=$( (export LANG=C LC_ALL=C; lscpu) 2>&1 )
        if [[ $? -eq 0 ]]; then
            echo "$lscpu_output" | grep -E 'Model name|Architecture|CPU\(s\)|Thread\(s) per core|Core\(s) per socket'
            if [[ $? -ne 0 ]]; then
                echo "Warning: lscpu output (in English) did not contain expected keywords. Full lscpu output was:"
                echo "$lscpu_output"
            fi
        else
            echo "Error: lscpu command failed. Output/Error was:"
            echo "$lscpu_output"
        fi
        echo ""
        local free_output
        free_output=$( (export LANG=C LC_ALL=C; free -h) 2>&1 )
        if [[ $? -eq 0 ]]; then
            # 加上 Swap disabled/enabled 的判断
            echo "$free_output" | grep -E '^Mem:'
            if echo "$free_output" | grep -q '^Swap:[[:space:]]*0B'; then
                echo "Swap:             Disabled"
            else
                echo "$free_output" | grep -E '^Swap:'
            fi
            if [[ $? -ne 0 && ! $(echo "$free_output" | grep -q '^Swap:[[:space:]]*0B') ]]; then # 如果grep Swap失败且不是因为0B
                echo "Warning: free -h output (in English) did not contain expected keywords for Swap. Full free -h output was:"
                echo "$free_output"
            fi
        else
            echo "Error: free -h command failed. Output/Error was:"
            echo "$free_output"
        fi
        echo "----------------------------------------"

        # >>> Key Disk Usage (df -hT) <<< (保持不变，它很好)
        echo ">>> Key Disk Usage (df -hT) <<<"
        df -hT / /home /boot /var /tmp 2>/dev/null || df -hT
        echo "----------------------------------------"

        # >>> Primary Network IPv4/IPv6 Addresses <<< (保持不变，它很好)
        echo ">>> Primary Network IPv4/IPv6 Addresses <<<"
        ip -4 addr show scope global up | awk '/inet / {print "  " $NF ": " $2}' | sed 's/\/.*//' || echo "  IPv4: No primary global UP interfaces found or ip command failed"
        ip -6 addr show scope global up | awk '/inet6 / {print "  " $NF ": " $2}' | sed 's/\/.*//' || echo "  IPv6: No primary global UP interfaces found or ip command failed"
        echo "----------------------------------------"
        echo "=== End of System Snapshot Summary ==="
    } > "$summary_file" 2>"${state_dest_dir}/.summary_err.log"
    # ... (错误日志处理和 rm -f 不变)
    if [[ -s "${state_dest_dir}/.summary_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成摘要文件 '$summary_file' 时发生错误，详情见 .summary_err.log"
    fi
    rm -f "${state_dest_dir}/.summary_err.log"


    # --- 2. 生成 network_details.txt (网络详细配置) ---
    log_msg DEBUG "[系统状态信息] 2/6 生成网络详情文件: $network_file"
    {
        echo "=== Network Configuration Details ==="
        echo "Collection Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "----------------------------------------"
        echo ">>> IP Addresses (ip addr show) <<<"
        ip addr show || echo "Error: ip addr show failed"
        echo "----------------------------------------"
        echo ">>> Routing Table (ip route show) <<<"
        ip route show || echo "Error: ip route show failed"
        echo "----------------------------------------"
        echo ">>> ARP/Neighbor Cache (ip neigh show) <<<"
        ip neigh show || echo "Error: ip neigh show failed"
        echo "----------------------------------------"
        echo ">>> DNS Resolvers (/etc/resolv.conf) <<<"
        if [ -f /etc/resolv.conf ]; then cat /etc/resolv.conf; else echo "File /etc/resolv.conf not found"; fi
        echo "----------------------------------------"
        if command -v resolvectl &>/dev/null; then
            echo ">>> systemd-resolved Status (resolvectl status) <<<"
            resolvectl status || echo "Error: resolvectl status failed"
            echo "----------------------------------------"
        fi
        echo ">>> Listening Ports (ss -tulnp or netstat -tulnp) <<<"
        if command -v ss &>/dev/null; then
            ss -tulnp || echo "Error: ss -tulnp failed"
        elif command -v netstat &>/dev/null; then
            log_msg DEBUG "[系统状态信息] ss未找到，尝试netstat获取监听端口。"
            netstat -tulnp || echo "Error: netstat -tulnp failed"
        else
            echo "Warning: Neither ss nor netstat command found to list listening ports."
        fi
        echo "----------------------------------------"
        echo "=== End of Network Details ==="
    } > "$network_file" 2>"${state_dest_dir}/.network_err.log"
    if [[ -s "${state_dest_dir}/.network_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成网络详情文件 '$network_file' 时发生错误，详情见 .network_err.log"
    fi
     rm -f "${state_dest_dir}/.network_err.log"


    # --- 3. 生成 storage_details.txt (存储详细配置) ---
    log_msg DEBUG "[系统状态信息] 3/6 生成存储详情文件: $storage_file"
    {
        echo "=== Storage Configuration Details ==="
        echo "Collection Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "----------------------------------------"
        echo ">>> Block Devices & Filesystems (lsblk -f) <<<"
        lsblk -f || echo "Error: lsblk -f failed"
        echo "----------------------------------------"
        echo ">>> Disk Usage Full (df -hT) <<<"
        df -hT || echo "Error: df -hT full failed"
        echo "----------------------------------------"
        echo ">>> Real Mount Points (findmnt --real ...) <<<"
        findmnt --real -t nosquashfs,notmpfs,nodevtmpfs || echo "Warning: findmnt command failed or not available"
        echo "----------------------------------------"
        if command -v vgdisplay &>/dev/null && command -v lvdisplay &>/dev/null && command -v pvdisplay &>/dev/null; then
            echo ">>> LVM Information <<<"
            (echo "--- Volume Groups (vgdisplay) ---"; vgdisplay || echo "Error: vgdisplay failed"; echo "")
            (echo "--- Logical Volumes (lvdisplay) ---"; lvdisplay || echo "Error: lvdisplay failed"; echo "")
            (echo "--- Physical Volumes (pvdisplay) ---"; pvdisplay || echo "Error: pvdisplay failed"; echo "")
            echo "----------------------------------------"
        fi
        if [ -f /proc/mdstat ] && command -v mdadm &>/dev/null; then
            echo ">>> Software RAID Status (/proc/mdstat) <<<"
            cat /proc/mdstat || echo "Error: reading /proc/mdstat failed"
            echo "----------------------------------------"
        fi
        echo "=== End of Storage Details ==="
    } > "$storage_file" 2>"${state_dest_dir}/.storage_err.log"
    if [[ -s "${state_dest_dir}/.storage_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成存储详情文件 '$storage_file' 时发生错误，详情见 .storage_err.log"
    fi
    rm -f "${state_dest_dir}/.storage_err.log"


    # --- 4. 生成 cron_jobs.txt (定时任务) ---
    log_msg DEBUG "[系统状态信息] 4/6 生成定时任务文件: $cron_jobs_file"
    {
        echo "=== Cron Job Listings ==="
        echo "Collection Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "----------------------------------------"
        echo ">>> Root User's Crontab (crontab -l) <<<"
        # arch_backup.sh 通常以 root 运行，所以可以直接执行 crontab -l
        if [[ "$EFFECTIVE_UID" -eq 0 ]]; then
            crontab -l 2>/dev/null || echo "# No crontab found for root or error accessing it."
        else
            log_msg WARN "[系统状态信息] 脚本未以root权限运行，无法获取root用户的crontab。"
            echo "# Skipped: Not run as root, cannot get root crontab."
        fi
        echo "----------------------------------------"

        # 目标用户的 Crontab (如果 CONF_TARGET_USERNAME 已设置且有效，且脚本以root运行)
        if [[ -n "${CONF_TARGET_USERNAME:-}" && "$CONF_TARGET_USERNAME" != "root" ]]; then
            echo ">>> User '${CONF_TARGET_USERNAME}' Crontab (crontab -u ${CONF_TARGET_USERNAME} -l) <<<"
            if [[ "$EFFECTIVE_UID" -eq 0 ]]; then # 只有 root 可以安全查看其他用户的 crontab
                crontab -u "$CONF_TARGET_USERNAME" -l 2>/dev/null || echo "# No crontab found for user '${CONF_TARGET_USERNAME}' or error accessing it."
            else
                 log_msg WARN "[系统状态信息] 脚本未以root权限运行，无法获取用户 '${CONF_TARGET_USERNAME}' 的crontab。"
                 echo "# Skipped: Not run as root, cannot get user '${CONF_TARGET_USERNAME}' crontab."
            fi
            echo "----------------------------------------"
        fi
        echo "=== End of Cron Job Listings ==="
    } > "$cron_jobs_file" 2>"${state_dest_dir}/.cron_err.log"
    if [[ -s "${state_dest_dir}/.cron_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成定时任务文件 '$cron_jobs_file' 时发生错误，详情见 .cron_err.log"
    fi
    rm -f "${state_dest_dir}/.cron_err.log"


    # --- 5. 生成 systemd_services_timers.txt (Systemd 单元和定时器) ---
    log_msg DEBUG "[系统状态信息] 5/6 生成Systemd单元和定时器文件: $systemd_units_file"
    {
        echo "=== Systemd Unit Files & Timers ==="
        echo "Collection Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "----------------------------------------"
        echo ">>> System-wide Enabled Unit Files (systemctl list-unit-files --state=enabled) <<<"
        systemctl list-unit-files --state=enabled --type=service,socket,target,timer --no-pager || echo "Error: systemctl list-unit-files --state=enabled failed"
        echo "----------------------------------------"
        echo ">>> System-wide All Timers (systemctl list-timers --all) <<<"
        systemctl list-timers --all --no-pager || echo "Error: systemctl list-timers --all failed"
        echo "----------------------------------------"

        #sudo systemctl --machine=$USER@.host --user list-unit-files --state=enabled
        log_msg DEBUG "[系统状态信息] 尝试获取用户 '${CONF_TARGET_USERNAME}' 的 systemd --user enabled units via systemctl --machine"
        # 目标用户的 Systemd Enabled Unit Files (如果 CONF_TARGET_USERNAME 已设置且有效，且脚本以root运行)
        if [[ -n "${CONF_TARGET_USERNAME:-}" && "$CONF_TARGET_USERNAME" != "root" ]]; then
                echo ">>> User '${CONF_TARGET_USERNAME}' Enabled Unit Files (systemctl --user list-unit-files --state=enabled) <<<"
                if [[ "$EFFECTIVE_UID" -eq 0 ]]; then # 确保当前是 root
                    

                    # 使用您测试成功的方法，并明确指定目标用户名
                    systemctl --machine="${CONF_TARGET_USERNAME}@.host" \
                        --user list-unit-files --state=enabled \
                        --type=service,socket,target,timer --no-pager 2>/dev/null \
                    || echo "# Failed to get user '${CONF_TARGET_USERNAME}' systemd enabled units using --machine. User session might not be active or other issues."
                else
                    log_msg WARN "[系统状态信息] 脚本未以root权限运行，无法获取用户 '${CONF_TARGET_USERNAME}' 的systemd --user units。"
                    echo "# Skipped: Not run as root, cannot get user '${CONF_TARGET_USERNAME}' systemd --user units."
                fi
                echo "----------------------------------------"
            fi
        echo "=== End of Systemd Unit Files & Timers ==="
    } > "$systemd_units_file" 2>"${state_dest_dir}/.systemd_err.log"
    if [[ -s "${state_dest_dir}/.systemd_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成Systemd文件 '$systemd_units_file' 时发生错误，详情见 .systemd_err.log"
    fi
    rm -f "${state_dest_dir}/.systemd_err.log"


    # --- 6. 生成 firewall_rules.txt (防火墙规则) ---
    # arch_backup.sh 通常以 root 运行，所以可以直接执行这些命令
    log_msg DEBUG "[系统状态信息] 6/6 生成防火墙规则文件: $firewall_file"
    {
        echo "=== Firewall Rules ==="
        echo "Collection Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "----------------------------------------"
        local firewall_tool_found=false
        if command -v nft &>/dev/null; then
            echo ">>> nftables Ruleset (nft list ruleset) <<<"
            nft list ruleset || echo "Error: nft list ruleset failed"
            firewall_tool_found=true
        fi
        if command -v iptables-save &>/dev/null; then
            if $firewall_tool_found; then echo "----------------------------------------"; fi # Separator if multiple tools
            echo ">>> iptables Rules (iptables-save) <<<"
            iptables-save || echo "Error: iptables-save failed"
            firewall_tool_found=true
            if command -v ip6tables-save &>/dev/null; then
                echo ""
                echo ">>> ip6tables Rules (ip6tables-save) <<<"
                ip6tables-save || echo "Error: ip6tables-save failed"
            fi
        fi
        if command -v ufw &>/dev/null && systemctl is-active --quiet ufw 2>/dev/null; then
            if $firewall_tool_found; then echo "----------------------------------------"; fi
            echo ">>> UFW Status (ufw status numbered) <<<"
            ufw status numbered || echo "Error: ufw status numbered failed"
            firewall_tool_found=true
        fi
        if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
            if $firewall_tool_found; then echo "----------------------------------------"; fi
            echo ">>> firewalld Configuration (firewall-cmd --list-all-zones) <<<"
            firewall-cmd --list-all-zones || echo "Error: firewall-cmd --list-all-zones failed"
            firewall_tool_found=true
        fi

        if ! $firewall_tool_found; then
            echo "No common active firewall management tool (nft, iptables, ufw, firewalld) found or rule export failed."
        fi
        echo "----------------------------------------"
        echo "=== End of Firewall Rules ==="
    } > "$firewall_file" 2>"${state_dest_dir}/.firewall_err.log"
    if [[ -s "${state_dest_dir}/.firewall_err.log" ]]; then
        log_msg WARN "[系统状态信息] 生成防火墙规则文件 '$firewall_file' 时发生错误，详情见 .firewall_err.log"
    fi
    rm -f "${state_dest_dir}/.firewall_err.log"

    # --- 生成此目录的清单文件 ---
    # _generate_manifest 是 arch_backup.sh 内部的函数
    if type -t _generate_manifest &>/dev/null; then
        if ! _generate_manifest "$state_dest_dir" "MANIFEST_system_info.txt"; then
            log_msg WARN "[系统状态信息] 为 '$state_dest_dir' 生成清单文件失败。"
        fi
    else
        log_msg WARN "[系统状态信息] _generate_manifest 函数未找到，无法为 system_info 生成清单。"
    fi

    log_msg INFO "[系统状态信息] 系统关键状态信息收集完成，存放于 '$state_dest_dir'"
    return 0
}

################################################################################
# 压缩指定的未压缩备份目录，并在成功和校验后选择性删除原目录。
# Globals:
#   BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES (R) - 压缩归档的存放目录。
#   CONF_COMPRESSION_EXT                  (R) - 压缩文件的扩展名。
#   CONF_COMPRESSION_METHOD               (R) - 压缩方法 (gzip, bzip2, xz)。
#   CONF_COMPRESSION_LEVEL                (R) - 压缩级别。
# Arguments:
#   $1 - 要压缩的未压缩备份目录的完整路径。
# Returns:
#   0 如果压缩和校验成功 (无论原目录是否被删除)。
#   1 如果压缩或校验失败。
################################################################################
compress_and_verify_backup() {
    local uncompressed_dir_path="$1"
    local uncompressed_dir_name
    uncompressed_dir_name=$(basename "$uncompressed_dir_path")
    local archive_path="${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}/${uncompressed_dir_name}.${CONF_COMPRESSION_EXT}"

    if [[ ! -d "$uncompressed_dir_path" ]]; then
        log_msg WARN "[压缩] 无法压缩: 未找到未压缩目录 '$uncompressed_dir_path'。"
        return 1
    fi
    if [[ -f "$archive_path" ]]; then
        log_msg INFO "[压缩] 归档文件 '$archive_path' 已存在。跳过对 '$uncompressed_dir_name' 的压缩。"
        return 0
    fi

    log_msg INFO "[压缩] 开始压缩备份: $uncompressed_dir_name 至 $archive_path"
    log_msg DEBUG "[压缩] 使用方法: $CONF_COMPRESSION_METHOD, 级别: ${CONF_COMPRESSION_LEVEL:-默认}"
    
    local tar_comp_char="" # e.g. z for gzip, j for bzip2, J for xz
    local comp_test_cmd_base=""
    local comp_test_cmd_arg=""
    local compress_env_opts_str="" # For tar internal compression e.g. XZ_OPT="-T0 -6"

    case "$CONF_COMPRESSION_METHOD" in
        gzip)  tar_comp_char="z"; comp_test_cmd_base="gzip"; comp_test_cmd_arg="-t"
               [[ -n "$CONF_COMPRESSION_LEVEL" ]] && compress_env_opts_str="GZIP=\"-${CONF_COMPRESSION_LEVEL}\"" ;;
        bzip2) tar_comp_char="j"; comp_test_cmd_base="bzip2"; comp_test_cmd_arg="-t"
               [[ -n "$CONF_COMPRESSION_LEVEL" ]] && compress_env_opts_str="BZIP2=\"-${CONF_COMPRESSION_LEVEL}\"" ;;
        xz)    tar_comp_char="J"; comp_test_cmd_base="xz"; comp_test_cmd_arg="-t"
                # -T0 for xz to use all available cores
               [[ -n "$CONF_COMPRESSION_LEVEL" ]] && compress_env_opts_str="XZ_OPT=\"-T0 -${CONF_COMPRESSION_LEVEL}\"" || compress_env_opts_str="XZ_OPT=\"-T0\"" ;;
        *) log_msg ERROR "[压缩] 不支持的压缩方法: $CONF_COMPRESSION_METHOD"; return 1 ;;
    esac
    
    local tar_opts="-c${tar_comp_char}f"
    log_msg DEBUG "[压缩] Tar 命令选项: $tar_opts (通过 $tar_comp_char)"
    log_msg DEBUG "[压缩] 压缩环境变量 (如果适用): $compress_env_opts_str"
    log_msg DEBUG "[压缩] 校验命令原型: $comp_test_cmd_base $comp_test_cmd_arg <archive_file>"

    local resource_prefix_arr_str=$(_get_resource_cmd_prefix_array)
    local tar_cmd_array=()
    # shellcheck disable=SC2206
    [[ -n "$resource_prefix_arr_str" ]] && tar_cmd_array=($resource_prefix_arr_str)
    
    # Construct the tar command with potential environment variables
    # We need to run `env VAR=val tar ...` or `VAR=val command`
    # The `eval` approach for env vars with tar is more portable if tar itself respects them.
    # Simpler: just ensure tar uses the right char and hope it picks up XZ_OPT etc if set.
    # Most tars do. The `eval "$compress_env_opts_str tar ..."` can be tricky with array.
    # Let's try prepending env vars directly to the command array IF they are set.
    # This is non-standard for command arrays.
    # Instead, we rely on tar picking up the environment variables if they are exported or set for its execution context.
    # For `XZ_OPT` etc., `tar` often calls the `xz` binary which respects these.
    # If using `eval`, must be careful.
    # Using a subshell with env vars set:
    # (export XZ_OPT="-T0 -6"; tar -cJf ...)

    local full_tar_command_str
    if [[ -n "$compress_env_opts_str" ]]; then
        # Example: XZ_OPT="-T0 -6" tar -cJf ...
        full_tar_command_str="$compress_env_opts_str ${tar_cmd_array[*]} tar '$tar_opts' '$archive_path' '$uncompressed_dir_name'"
    else
        full_tar_command_str="${tar_cmd_array[*]} tar '$tar_opts' '$archive_path' '$uncompressed_dir_name'"
    fi
    
    log_msg DEBUG "[压缩] 完整 tar 执行原型 (cd to dirname then): $full_tar_command_str"

    local start_compress_time=$(date +%s)
    # Execute tar in the parent directory of the uncompressed_dir_path to get correct archive structure
    # Use bash -c for complex command with env vars
    if (cd "$(dirname "$uncompressed_dir_path")" && bash -c "$full_tar_command_str"); then
        local end_compress_time=$(date +%s)
        local compress_duration=$((end_compress_time - start_compress_time))
        log_msg INFO "[压缩] 成功压缩: $uncompressed_dir_name (耗时: ${compress_duration}s)"

        log_msg INFO "[压缩] 开始校验归档文件: $archive_path (使用: $comp_test_cmd_base $comp_test_cmd_arg)"
        local verify_start_time=$(date +%s)
        if "$comp_test_cmd_base" "$comp_test_cmd_arg" "$archive_path"; then
            local verify_end_time=$(date +%s)
            local verify_duration=$((verify_end_time - verify_start_time))
            log_msg INFO "[压缩] 归档 '$archive_path' 校验成功 (耗时: ${verify_duration}s)。"
            local archive_size=$(du -sh "$archive_path" | cut -f1)
            log_msg INFO "[压缩] 归档文件大小: $archive_size"
            if confirm_action "压缩成功后是否删除未压缩目录 '$uncompressed_dir_path'？"; then
                log_msg INFO "[压缩] 准备删除未压缩目录: $uncompressed_dir_path"
                rm -rf "$uncompressed_dir_path"
                log_msg INFO "[压缩] 已删除未压缩目录。"
            else
                log_msg INFO "[压缩] 用户选择保留未压缩目录: $uncompressed_dir_path"
            fi
        else
            log_msg ERROR "[压缩] 归档校验失败: '$archive_path'！将保留未压缩目录并删除损坏的归档。"
            rm -f "$archive_path"
            return 1
        fi
    else
        local tar_exit_code=$?
        local end_compress_time=$(date +%s)
        local compress_duration=$((end_compress_time - start_compress_time))
        log_msg ERROR "[压缩] 压缩过程失败: '$uncompressed_dir_name' (退出码: $tar_exit_code, 耗时: ${compress_duration}s)。"
        rm -f "$archive_path" # Ensure partial/corrupt archive is removed
        return 1
    fi
    return 0
}

################################################################################
# 清理旧的备份，包括压缩超期的未压缩快照和删除超期的压缩归档。
# Globals:
#   CONF_RETENTION_UNCOMPRESSED_COUNT   (R) - 保留的未压缩快照数量。
#   CONF_COMPRESSION_ENABLE             (R) - 是否启用压缩。
#   CONF_RETENTION_COMPRESSED_DAYS      (R) - 压缩归档按天数保留的策略。
#   CONF_RETENTION_COMPRESSED_COUNT     (R) - 压缩归档按数量保留的策略。
#   BACKUP_TARGET_DIR_UNCOMPRESSED    (R)
#   BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES (R)
#   CONF_COMPRESSION_EXT                (R)
# Arguments:
#   None
# Returns:
#   0 (总是，清理过程中的错误被记录但不中止脚本)。
################################################################################
cleanup_backups() {
    log_msg INFO "[清理] 开始执行备份清理流程..."
    local uncompressed_processed_count=0
    local compressed_deleted_count=0

    # 1. 清理未压缩的快照
    if [[ "${CONF_RETENTION_UNCOMPRESSED_COUNT:-0}" -gt 0 ]]; then
        log_msg INFO "[清理/未压缩] 策略: 保留最近 $CONF_RETENTION_UNCOMPRESSED_COUNT 个未压缩快照。"
        local uncompressed_snapshots_list
        uncompressed_snapshots_list=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr)
        
        local count=0
        local snapshots_to_process_for_cleanup=()
        log_msg DEBUG "[清理/未压缩] 找到的未压缩快照 (按新旧排序):"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local snap_path_seconds snap_path_name
            snap_path_seconds=$(echo "$line" | cut -d' ' -f1)
            snap_path_name=$(echo "$line" | cut -d' ' -f2-)
            log_msg DEBUG "[清理/未压缩]   - $(date -d "@$snap_path_seconds" "+%Y-%m-%d %H:%M:%S") - $snap_path_name"
            count=$((count + 1))
            if [[ "$count" -gt "$CONF_RETENTION_UNCOMPRESSED_COUNT" ]]; then
                snapshots_to_process_for_cleanup+=("$snap_path_name")
            fi
        done <<< "$uncompressed_snapshots_list"

        if [[ ${#snapshots_to_process_for_cleanup[@]} -gt 0 ]]; then
            log_msg INFO "[清理/未压缩] 将处理 ${#snapshots_to_process_for_cleanup[@]} 个超出保留数量的未压缩快照。"
            for snap_path_to_process in "${snapshots_to_process_for_cleanup[@]}"; do
                log_msg INFO "[清理/未压缩] 处理快照: $snap_path_to_process"
                
                if [[ "$CONF_COMPRESSION_ENABLE" == "true" ]]; then
                    local archive_name_base compressed_archive_path
                    archive_name_base=$(basename "$snap_path_to_process")
                    compressed_archive_path="${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}/${archive_name_base}.${CONF_COMPRESSION_EXT}"

                    if [[ -f "$compressed_archive_path" ]]; then
                        log_msg INFO "[清理/未压缩] 快照 '$snap_path_to_process' 对应的压缩归档 '$compressed_archive_path' 已存在。"
                        if confirm_action "是否删除未压缩快照 '$snap_path_to_process' (因其压缩版已存在)？"; then
                            log_msg INFO "[清理/未压缩] 准备删除 (压缩版已存在): $snap_path_to_process"
                            rm -rf "$snap_path_to_process"
                            log_msg INFO "[清理/未压缩] 已删除: $snap_path_to_process"
                            uncompressed_processed_count=$((uncompressed_processed_count + 1))
                        else
                            log_msg INFO "[清理/未压缩] 用户选择保留 '$snap_path_to_process' (即使压缩版已存在)。"
                        fi
                    else
                        log_msg INFO "[清理/未压缩] 尝试压缩 '$snap_path_to_process' (因为其压缩归档 '$compressed_archive_path' 不存在)。"
                        if compress_and_verify_backup "$snap_path_to_process"; then
                            uncompressed_processed_count=$((uncompressed_processed_count + 1))
                        else
                            log_msg WARN "[清理/未压缩] 压缩快照 '$snap_path_to_process' 失败，将保留此未压缩快照。"
                        fi
                    fi
                else
                    log_msg INFO "[清理/未压缩] 压缩功能已禁用。"
                    if confirm_action "是否永久删除旧的未压缩快照 '$snap_path_to_process' (因压缩功能禁用)？"; then
                        log_msg INFO "[清理/未压缩] 准备删除 (压缩禁用): $snap_path_to_process"
                        rm -rf "$snap_path_to_process"
                        log_msg INFO "[清理/未压缩] 已删除: $snap_path_to_process"
                        uncompressed_processed_count=$((uncompressed_processed_count + 1))
                    else
                        log_msg INFO "[清理/未压缩] 用户选择保留 '$snap_path_to_process' (压缩功能禁用)。"
                    fi
                fi 
            done
        else
            log_msg INFO "[清理/未压缩] 没有超出保留数量的未压缩快照需要处理。"
        fi
    else
        log_msg INFO "[清理/未压缩] 跳过清理 (CONF_RETENTION_UNCOMPRESSED_COUNT <= 0)。"
    fi

    # 2. 清理已压缩的归档文件
    log_msg INFO "[清理/压缩] 开始清理已压缩的归档文件..."
    local archives_to_delete_final=()

    if [[ "${CONF_RETENTION_COMPRESSED_DAYS:-0}" -gt 0 ]]; then
        log_msg INFO "[清理/压缩/按时间] 策略: 删除早于 $CONF_RETENTION_COMPRESSED_DAYS 天的归档。"
        local days_for_find_comp=$((CONF_RETENTION_COMPRESSED_DAYS)) # find -mtime +N means > N*24 hours ago
        # If CONF_RETENTION_COMPRESSED_DAYS is 1, -mtime +0 means older than 24h.
        # If CONF_RETENTION_COMPRESSED_DAYS is 90, -mtime +89 means older than 90 days (strictly > 89*24h)
        # So, if we want to delete *older than* 90 days, we mean files whose age is 91 days or more.
        # find -mtime +N means files modified N*24 hours ago or more. So +CONF_RETENTION_COMPRESSED_DAYS is fine.
        # No, find -mtime +N means file's data was last modified more than N*24 hours ago.
        # So for "older than 90 days", it's -mtime +89 (strictly older than 89 days, so 90 days or more)
        # Or, to be safe and simple: delete if mtime is strictly greater than (NOW - RETENTION_DAYS).
        # find -mtime +N means > N days. So if we want to delete files older than 90 days, N=90.
        # It's "more than N*24 hours".
        # Let's keep it simple: if CONF_RETENTION_COMPRESSED_DAYS=90, we delete files modified more than 90 days ago.
        # Example: if a file is 90 days and 1 hour old, it's deleted. If it's 89 days and 23 hours, it's kept.
        # So, -mtime +$(CONF_RETENTION_COMPRESSED_DAYS -1) is common if you mean "keep for N days then delete".
        # But `find -mtime +N` means *more than* N 24-hour periods. So +CONF_RETENTION_COMPRESSED_DAYS should be correct
        # for "delete files whose age in days is > CONF_RETENTION_COMPRESSED_DAYS".
        # Let's assume user means "keep for 90 days". So on day 91, it's eligible.
        # This means `mtime +89`.
        local mtime_arg_days="$CONF_RETENTION_COMPRESSED_DAYS"
        if [[ "$mtime_arg_days" -gt 0 ]]; then
            mtime_arg_days=$((mtime_arg_days -1)) # find +N means strictly greater than N days.
            [[ $mtime_arg_days -lt 0 ]] && mtime_arg_days=0
        fi

        log_msg DEBUG "[清理/压缩/按时间] 使用 find -mtime +$mtime_arg_days"
        while IFS= read -r archive_file_by_age; do
            [[ -z "$archive_file_by_age" ]] && continue
            archives_to_delete_final+=("$archive_file_by_age")
            log_msg DEBUG "[清理/压缩/按时间] 标记删除: $archive_file_by_age (修改时间: $(date -r "$archive_file_by_age" "+%Y-%m-%d %H:%M:%S"))"
        done < <(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -mtime "+${mtime_arg_days}")
    else
        log_msg INFO "[清理/压缩/按时间] 跳过按时间清理 (CONF_RETENTION_COMPRESSED_DAYS <= 0)。"
    fi

    if [[ "${CONF_RETENTION_COMPRESSED_COUNT:-0}" -gt 0 ]];then
        log_msg INFO "[清理/压缩/按数量] 策略: 保留最多 $CONF_RETENTION_COMPRESSED_COUNT 个归档。"
        local current_archives_sorted_list
        # Sort by modification time, newest first, then we take from the end (oldest) if over count.
        # No, sort oldest first, then count how many to delete from the beginning.
        current_archives_sorted_list=$(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -printf "%T@ %p\n" | sort -n)
        
        local archives_not_yet_marked_for_deletion=()
        log_msg DEBUG "[清理/压缩/按数量] 找到的压缩归档 (按旧新排序):"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local arc_path_seconds arc_path_name
            arc_path_seconds=$(echo "$line" | cut -d' ' -f1)
            arc_path_name=$(echo "$line" | cut -d' ' -f2-)
            log_msg DEBUG "[清理/压缩/按数量]   - $(date -d "@$arc_path_seconds" "+%Y-%m-%d %H:%M:%S") - $arc_path_name"

            local already_marked_by_age=false
            for marked_arc in "${archives_to_delete_final[@]}"; do
                if [[ "$marked_arc" == "$arc_path_name" ]]; then
                    already_marked_by_age=true; break
                fi
            done
            if ! $already_marked_by_age; then
                archives_not_yet_marked_for_deletion+=("$arc_path_name")
            fi
        done <<< "$current_archives_sorted_list"

        local num_to_delete_for_count=0
        if [[ ${#archives_not_yet_marked_for_deletion[@]} -gt "$CONF_RETENTION_COMPRESSED_COUNT" ]]; then
            num_to_delete_for_count=$((${#archives_not_yet_marked_for_deletion[@]} - CONF_RETENTION_COMPRESSED_COUNT))
        fi

        if [[ "$num_to_delete_for_count" -gt 0 ]]; then
            log_msg INFO "[清理/压缩/按数量] 需要额外删除 $num_to_delete_for_count 个最旧的归档以满足数量限制。"
            for ((i=0; i<num_to_delete_for_count; i++)); do
                archives_to_delete_final+=("${archives_not_yet_marked_for_deletion[i]}")
                log_msg DEBUG "[清理/压缩/按数量] 标记删除: ${archives_not_yet_marked_for_deletion[i]}"
            done
        else
            log_msg INFO "[清理/压缩/按数量] 当前归档数量 (${#archives_not_yet_marked_for_deletion[@]}) 未超出限制 ($CONF_RETENTION_COMPRESSED_COUNT)，无需按数量删除。"
        fi
    else
        log_msg INFO "[清理/压缩/按数量] 跳过按数量清理 (CONF_RETENTION_COMPRESSED_COUNT <= 0)。"
    fi
    
    local unique_archives_to_delete_final_list
    if [[ ${#archives_to_delete_final[@]} -gt 0 ]]; then
        # Use awk for unique, as sort -u might behave differently on some systems with empty lines
        unique_archives_to_delete_final_list=$(printf "%s\n" "${archives_to_delete_final[@]}" | awk '!seen[$0]++')
    else
        unique_archives_to_delete_final_list=""
    fi

    if [[ -z "$unique_archives_to_delete_final_list" ]]; then
        log_msg INFO "[清理/压缩] 没有标记为待删除的压缩归档。"
    else
        local num_unique_to_delete_comp
        # Count non-empty lines
        num_unique_to_delete_comp=$(echo "$unique_archives_to_delete_final_list" | grep -c .)
        log_msg INFO "[清理/压缩] 以下 $num_unique_to_delete_comp 个压缩归档将被删除:"
        
        mapfile -t f_array < <(echo "$unique_archives_to_delete_final_list" | grep .) # Ensure no empty lines in mapfile
        for f_item in "${f_array[@]}"; do # No need for index if just iterating values
            log_msg INFO "[清理/压缩]   - ${f_item}"
        done

        if confirm_action "是否继续删除这 $num_unique_to_delete_comp 个压缩归档文件？"; then
            # Re-read into mapfile to be safe, or just iterate over the string list
            local archive_to_delete
            while IFS= read -r archive_to_delete; do
                [[ -z "$archive_to_delete" ]] && continue # Should be filtered by grep . already
                log_msg INFO "[清理/压缩] 准备删除已标记的压缩归档: $archive_to_delete"
                if rm -f "$archive_to_delete"; then
                    compressed_deleted_count=$((compressed_deleted_count + 1))
                    log_msg INFO "[清理/压缩] 已删除: $archive_to_delete"
                else
                    log_msg WARN "[清理/压缩] 删除 '$archive_to_delete' 失败。"
                fi
            done <<< "$(echo "$unique_archives_to_delete_final_list" | grep .)"
        else
            log_msg INFO "[清理/压缩] 用户取消了旧压缩归档的删除操作。"
        fi
    fi

    log_msg INFO "[清理] 清理流程结束。共处理了(压缩或删除) $uncompressed_processed_count 个未压缩快照，删除了 $compressed_deleted_count 个压缩归档。"
    return 0
}

################################################################################
# 主备份流程编排函数。
# 负责初始化备份、执行各项备份任务 (串行或并行)、以及后续的清理工作。
# Globals:
#   (许多 CONF_* 和运行时变量)
# Arguments:
#   None
# Returns:
#   0 如果整个备份和清理流程成功。
#   1 如果流程中发生任何关键错误。
################################################################################
run_backup() {
    local backup_start_time
    backup_start_time=$(date +%s)

    log_msg INFO "===== 开始 Arch Linux 备份流程 (版本 $SCRIPT_VERSION) ====="
    #CURRENT_TIMESTAMP=$(date '+%Y%m%d_%H%M%S') # This is for backup directory names
    CURRENT_TIMESTAMP="$GLOBAL_RUN_TIMESTAMP"     # <--- 修改点：使用全局统一的时间戳
    local current_backup_path_uncompressed="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}"
    mkdir -p "$current_backup_path_uncompressed"
    log_msg INFO "当前备份时间戳 (用于目录名): $CURRENT_TIMESTAMP"
    log_msg INFO "当前备份目标 (未压缩): $current_backup_path_uncompressed"
    log_msg DEBUG "备份根目录: $CONF_BACKUP_ROOT_DIR"
    log_msg DEBUG "未压缩快照存放目录: $BACKUP_TARGET_DIR_UNCOMPRESSED"
    log_msg DEBUG "压缩归档存放目录: $BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES"

    check_disk_space "$CONF_BACKUP_ROOT_DIR" "$CONF_MIN_FREE_DISK_SPACE_PERCENT"

    local link_dest_option=""
    if [[ "$CONF_INCREMENTAL_BACKUP" == "true" ]]; then
        log_msg INFO "增量备份已启用，正在查找上一个快照..."
        local latest_snapshot_dir
        latest_snapshot_dir=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d ! -name "$CURRENT_TIMESTAMP" -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)

        if [[ -n "$latest_snapshot_dir" && -d "$latest_snapshot_dir" ]]; then
            # $latest_snapshot_dir 是上一个快照的绝对路径
            # 例如 /mnt/arch_backups/auto_backup_systems/snapshots/20250615_172348
            link_dest_option="--link-dest=${latest_snapshot_dir}"
            log_msg INFO "找到上一个快照: '$(basename "$latest_snapshot_dir")' (路径: ${latest_snapshot_dir})。将使用绝对路径 --link-dest 进行增量备份。"
        else
            log_msg INFO "未找到上一个有效快照。本次将作为新的完整备份基线。"
            link_dest_option=""
        fi
    else
        log_msg INFO "增量备份已禁用。本次将执行完整备份。"
        link_dest_option=""
    fi

    local backup_tasks=()
    [[ "$CONF_BACKUP_SYSTEM_CONFIG" == "true" ]] && backup_tasks+=("backup_system_config \"$link_dest_option\"")
    [[ "$CONF_BACKUP_USER_DATA" == "true" ]] && backup_tasks+=("backup_user_data \"$link_dest_option\"")
    [[ "$CONF_BACKUP_PACKAGES" == "true" ]] && backup_tasks+=("backup_packages")
    [[ "$CONF_BACKUP_LOGS" == "true" ]] && backup_tasks+=("backup_logs")
    [[ "$CONF_BACKUP_CUSTOM_PATHS" == "true" ]] && backup_tasks+=("backup_custom_paths \"$link_dest_option\"")
    [[ "$CONF_BACKUP_SYSTEM_STATE_INFO" == "true" ]] && backup_tasks+=("backup_system_state_info") # 新增

    if [[ ${#backup_tasks[@]} -eq 0 ]]; then
        log_msg WARN "没有启用的备份类别。备份流程中止。"
        rm -rf "$current_backup_path_uncompressed" # Clean up empty timestamped dir
        return 0
    fi
    log_msg INFO "将要执行的备份任务 (${#backup_tasks[@]} 个):"
    for task_desc in "${backup_tasks[@]}"; do log_msg INFO "  - ${task_desc%% \"*\"}"; done # Show only function name

    local overall_backup_success="true"
    local task_execution_summary=()

    if [[ "$CONF_PARALLEL_JOBS" -gt 1 && -n "$PARALLEL_CMD" ]]; then
        log_msg INFO "使用 GNU Parallel (${CONF_PARALLEL_JOBS}个作业) 并行执行备份任务..."
        # Export all necessary variables and functions for parallel subshells
        # Ensure ACTUAL_LOG_FILE is correct for sub-processes (it should be, as it's set before this)
        export SCRIPT_NAME SCRIPT_DIR SCRIPT_PID SESSION_TIMESTAMP ACTUAL_LOG_FILE
        export CURRENT_TIMESTAMP BACKUP_TARGET_DIR_UNCOMPRESSED CONF_BACKUP_ROOT_DIR CONF_LOG_LEVEL CURRENT_LOG_LEVEL
        export -A LOG_LEVEL_NAMES # Export associative array
        export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_CYAN COLOR_MAGENTA
        export CONF_USER_HOME_INCLUDE CONF_USER_HOME_EXCLUDE CONF_CUSTOM_PATHS_INCLUDE CONF_CUSTOM_PATHS_EXCLUDE
        export TARGET_BACKUP_HOME TARGET_BACKUP_USER TARGET_BACKUP_UID TARGET_BACKUP_GID
        export CONF_BACKUP_JOURNALCTL CONF_JOURNALCTL_ARGS CONF_SYSTEM_LOG_FILES EFFECTIVE_UID CONF_PROMPT_FOR_CONFIRMATION
        export LOG_LEVEL_DEBUG LOG_LEVEL_INFO LOG_LEVEL_WARN LOG_LEVEL_ERROR LOG_LEVEL_FATAL
        export CONF_USE_NICE CONF_NICE_LEVEL CONF_USE_IONICE CONF_IONICE_CLASS CONF_IONICE_LEVEL # Resource control vars
        # Export functions needed by parallel tasks
        export -f log_msg confirm_action _get_resource_cmd_prefix_array _generate_manifest _perform_rsync_backup
        export -f backup_system_config backup_user_data backup_packages backup_logs backup_custom_paths
        
        local parallel_input=""
        for task_cmd_str in "${backup_tasks[@]}"; do
             parallel_input+="${task_cmd_str}\n"
        done
        
        log_msg DEBUG "传递给 GNU Parallel 的任务列表:\n$parallel_input"
        local parallel_start_time=$(date +%s)
        # The subshell for parallel needs to re-source parts of the script or have functions exported.
        # Sourcing the whole script again in parallel jobs can be problematic if not designed for it.
        # Here we rely on exported functions.
        # The `{}` will be replaced by each line from printf.
        # We need `bash -c` because the task_cmd_str might contain arguments with spaces that need to be parsed by a shell.
        # The functions are already exported, so `bash -c "my_func arg1 arg2"` should work.
        if ! printf "%b" "$parallel_input" | $PARALLEL_CMD --tty bash -c ". \"${SCRIPT_DIR}/${SCRIPT_NAME}\"; {}"; then
        # if ! printf "%b" "$parallel_input" | $PARALLEL_CMD bash -c "source \"${SCRIPT_DIR}/${SCRIPT_NAME}\"; {}"; then
        # Sourcing the entire script in parallel is dangerous due to global var manipulations and traps.
        # Better: Ensure all functions called by tasks are self-contained or rely on EXPORTED variables/functions.
        # The `export -f my_func` is key.
        # `bash -c "$task_cmd_str"` is simpler if task_cmd_str is "my_func \"arg with space\""
        # Since `task_cmd_str` is like `backup_system_config \"$link_dest_option\"`, this should work with `bash -c`.
        # However, for `parallel` to correctly interpret this, it might be better to pass function and args separately.
        # The current method `bash -c ". \"$SCRIPT_DIR/$SCRIPT_NAME\"; {}"` re-sources functions definition for each job,
        # which is somewhat safer than sourcing the whole script if it has guards.
        # The functions are exported, so simple `bash -c "{}"` might work if `{}` is a valid command.
        # Let's stick to the existing approach and ensure exports are correct.
        # Simpler for parallel: `printf '%s\n' "${backup_tasks[@]}" | parallel --షిellquote $PARALLEL_CMD` - but this is for GNU Parallel specific syntax
        # The current format for `parallel_input` where each line is a command string to be executed by `bash -c` is fine.
             overall_backup_success="false"
             log_msg ERROR "GNU Parallel 执行返回错误，一个或多个并行备份任务可能失败。请检查上方日志。"
             task_execution_summary+=("并行任务组: 失败 (部分或全部，由 Parallel 报告)")
        else
             log_msg INFO "GNU Parallel 任务组执行完毕 (Parallel 本身未报告错误)。"
             task_execution_summary+=("并行任务组: 完成 (具体子任务状态需查阅其日志条目)")
        fi
        local parallel_end_time=$(date +%s)
        log_msg INFO "并行任务执行耗时: $((parallel_end_time - parallel_start_time))s"

    else # Serial execution
        log_msg INFO "串行执行备份任务..."
        local task_num=1
        for task_cmd_str in "${backup_tasks[@]}"; do
            local task_fn_name="${task_cmd_str%% \"*\"}" # Get function name
            log_msg INFO "--- [串行任务 ${task_num}/${#backup_tasks[@]}] 开始: ${task_fn_name} ---"
            local task_start_time=$(date +%s)
            if eval "$task_cmd_str"; then # eval is used to correctly parse function calls with arguments
                local task_end_time=$(date +%s)
                local task_duration=$((task_end_time - task_start_time))
                log_msg INFO "--- [串行任务 ${task_num}] (${task_fn_name}) 成功 (耗时: ${task_duration}s) ---"
                task_execution_summary+=("${task_fn_name}: 成功, ${task_duration}s")
            else
                local task_exit_code=$?
                local task_end_time=$(date +%s)
                local task_duration=$((task_end_time - task_start_time))
                overall_backup_success="false"
                log_msg ERROR "--- [串行任务 ${task_num}] (${task_fn_name}) 失败 (退出码: $task_exit_code, 耗时: ${task_duration}s) ---"
                task_execution_summary+=("${task_fn_name}: 失败 (退出码: $task_exit_code), ${task_duration}s")
            fi
            task_num=$((task_num + 1))
        done
    fi

    log_msg INFO "所有备份任务执行阶段完成。"
    log_msg INFO "任务执行摘要:"
    for summary_item in "${task_execution_summary[@]}"; do
        log_msg INFO "  - $summary_item"
    done

    if [[ "$overall_backup_success" == "false" ]]; then
        log_msg ERROR "由于一个或多个备份任务失败，当前备份 ($current_backup_path_uncompressed) 可能不完整或存在问题。"
        # Do not delete the potentially partial backup automatically, user might want to inspect
    else
        log_msg INFO "所有核心备份任务均已成功完成或按预期跳过: $CURRENT_TIMESTAMP。"
        # Check if backup directory is empty (e.g., all tasks skipped or produced no output)
        local backup_dir_content_check
        # find ... -print -quit will print the first found item and exit. If nothing, output is empty.
        backup_dir_content_check=$(find "$current_backup_path_uncompressed" -mindepth 1 -print -quit 2>/dev/null)

        if [[ -z "$backup_dir_content_check" ]]; then
            # Check if any task was supposed to produce output
            local any_task_should_produce_output=false
            for summary in "${task_execution_summary[@]}"; do
                if [[ "$summary" == *": 成功"* ]]; then # A task succeeded
                    # More fine-grained: check if the succeeded task was one that produces rsync output or files
                    if [[ "$summary" == "backup_system_config"* || \
                          "$summary" == "backup_user_data"* || \
                          "$summary" == "backup_custom_paths"* || \
                          "$summary" == "backup_packages"* || \
                          "$summary" == "backup_logs"* ]]; then
                        any_task_should_produce_output=true; break
                    fi
                fi
            done

            if $any_task_should_produce_output ; then
                 log_msg WARN "警告: 备份目录 $current_backup_path_uncompressed 最终为空，但有任务报告成功并期望产生输出！这可能表示配置或执行存在严重问题。"
                 # Consider this a failure for the current backup instance integrity
                 overall_backup_success="false" # Mark as overall failure
            else
                 log_msg INFO "所有任务均未产生输出或全部跳过，备份目录为空是正常的。"
                 log_msg INFO "删除空的快照目录: $current_backup_path_uncompressed"
                 rm -rf "$current_backup_path_uncompressed" 2>/dev/null
            fi
        else
            local uncompressed_size
            uncompressed_size=$(du -sh "$current_backup_path_uncompressed" | cut -f1)
            log_msg INFO "当前未压缩备份占用空间: $uncompressed_size"
            log_msg INFO "基本验证: 备份目录 $current_backup_path_uncompressed 非空。"
        fi
    fi

    # Cleanup (old snapshots, old archives) regardless of current backup success, unless current failed catastrophically early.
    local cleanup_start_time=$(date +%s)
    cleanup_backups
    local cleanup_end_time=$(date +%s)
    log_msg INFO "备份清理流程耗时: $((cleanup_end_time - cleanup_start_time))s"


    local backup_end_time=$(date +%s)
    local total_backup_duration=$((backup_end_time - backup_start_time))
    log_msg INFO "整个备份和清理流程总耗时: ${total_backup_duration} 秒。"

    if [[ "$overall_backup_success" == "false" ]]; then
        log_msg ERROR "===== Arch Linux 备份流程结束，但检测到错误 ====="
        return 1
    fi
    log_msg INFO "===== Arch Linux 备份流程成功结束 ====="
    return 0
}

################################################################################
# 脚本的主入口函数。
# 初始化、加载配置、检查依赖、然后调用 run_backup 执行备份流程。
# Globals:
#   (许多)
# Arguments:
#   $@ - 传递给脚本的命令行参数 (当前未使用)。
# Returns:
#   0 如果脚本成功完成。
#   1 如果发生错误。
################################################################################
main() {
    # Provisional log setup before config is loaded.
    # ACTUAL_LOG_FILE is already defaulted to /tmp/${SCRIPT_NAME}.log
    # The first echo must go to this provisional log.
    # 使用 export 确保子shell（如果将来有需要）也能访问，尽管对于当前结构可能不是严格必需
    export GLOBAL_RUN_TIMESTAMP
    GLOBAL_RUN_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    echo "--- $(date '+%Y-%m-%d %H:%M:%S') - $SCRIPT_NAME (PID: $SCRIPT_PID, Version: $SCRIPT_VERSION) - 脚本启动 (日志暂存: $ACTUAL_LOG_FILE) ---" >> "$ACTUAL_LOG_FILE"

    if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
        echo "警告: 为了完整备份系统文件 (如 /etc) 和正确处理权限，建议使用 'sudo $0' 运行此脚本。" >&2
        log_msg WARN "脚本未使用 root 权限运行。系统级备份功能将受限。"
    fi
    if [[ "$EFFECTIVE_UID" -eq 0 && -z "$SUDO_USER" ]]; then # SUDO_USER 已在脚本顶部处理过未定义的情况
        log_msg WARN "脚本正以 root 用户直接运行 (非通过sudo)。如果计划进行特定用户数据备份，请在配置文件中设置 CONF_TARGET_USERNAME。"
    fi

    load_config # This will call _setup_final_log_path() internally to set the final ACTUAL_LOG_FILE

    log_msg INFO "脚本版本: $SCRIPT_VERSION"
    log_msg INFO "脚本执行路径: $SCRIPT_DIR/$SCRIPT_NAME"
    # SESSION_TIMESTAMP 变量在您的脚本中似乎没有被使用，GLOBAL_RUN_TIMESTAMP 是主要的
    log_msg INFO "脚本PID: $SCRIPT_PID / 全局运行时间戳: $GLOBAL_RUN_TIMESTAMP"
    log_msg INFO "实际日志文件: $ACTUAL_LOG_FILE"
    log_msg INFO "执行用户 (有效): $EFFECTIVE_USER (UID: $EFFECTIVE_UID)"
    # if [[ -n "$SUDO_USER" ]]; then
    #     log_msg INFO "通过 sudo 调用，调用 sudo 的用户 (SUDO_USER): $SUDO_USER (UID: ${SUDO_UID:-N/A}, GID: ${SUDO_GID:-N/A})"
    # fi
    if [[ -n "$SUDO_USER" ]]; then # 如果 SUDO_USER 经过上面的处理，即使为空也不会报错
        # 即使 SUDO_USER 存在，SUDO_UID 和 SUDO_GID 也可能不存在（取决于 sudo 版本和配置）
        # 所以对它们使用参数扩展提供默认值是安全的。
        log_msg INFO "通过 sudo 调用，调用 sudo 的用户 (SUDO_USER): ${SUDO_USER} (UID: ${SUDO_UID:-未设置/N/A}, GID: ${SUDO_GID:-未设置/N/A})"
    fi
    log_msg INFO "用于家目录备份的目标用户信息: User='${TARGET_BACKUP_USER:-未指定/无效}', UID='${TARGET_BACKUP_UID:-N/A}', GID='${TARGET_BACKUP_GID:-N/A}', Home='${TARGET_BACKUP_HOME:-N/A}'"
    log_msg INFO "加载的配置文件: ${LOADED_CONFIG_FILE:-未找到，使用默认值或新生成的模板}"
    log_msg INFO "当前日志级别设置为: ${LOG_LEVEL_NAMES[$CURRENT_LOG_LEVEL]} ($CURRENT_LOG_LEVEL)"

    local required_system_deps=(
        "rsync" "tar" "find" "sort" "df" "getent" "cut" "head" "tail" "sed" "grep" "wc" "mkdir" "rm" "id" "date" "basename" "dirname" "mktemp" "du" "awk"
    )
    local compression_tool_to_check=""
    case "$CONF_COMPRESSION_METHOD" in
        gzip)  compression_tool_to_check="gzip" ;;
        bzip2) compression_tool_to_check="bzip2" ;;
        xz)    compression_tool_to_check="xz" ;;
    esac
    [[ -n "$compression_tool_to_check" ]] && required_system_deps+=("$compression_tool_to_check")

    if [[ "${CONF_PARALLEL_JOBS:-1}" -gt 1 ]]; then
        required_system_deps+=("parallel")
    fi
    # check_dependencies will add nice/ionice if configured
    check_dependencies "${required_system_deps[@]}"

    # --- 可以在这里添加一个非常早期的 "pre-execution" 钩子，如果需要的话 ---
    # _run_hooks "pre-execution" "$GLOBAL_RUN_TIMESTAMP"
    # --------------------------------------------------------------------

    local main_backup_exit_code=0 # 用于记录 run_backup 的最终状态
    if run_backup; then # run_backup 内部会调用 cleanup_backups (清理备份快照和归档)
        log_msg INFO "$SCRIPT_NAME 备份流程成功完成。"
    else
        main_backup_exit_code=$? # 获取 run_backup 的失败退出码
        # 如果 run_backup 返回非0，它内部应该已经记录了ERROR
        # log_msg ERROR "$SCRIPT_NAME 备份流程遇到一个或多个错误 (退出码: $main_backup_exit_code)。" # 这句可能重复
        #-------------------
        #main_process_status=1 # Mark that an error occurred in the main process
        #log_msg ERROR "$SCRIPT_NAME 执行过程中遇到一个或多个错误。"
        # trap ERR will have already logged details
    fi

    # 清理 arch_backup.sh 自身的日志文件
    cleanup_old_logs

    # --- 最终钩子：在所有操作（包括备份、备份清理、自身日志清理）完成后执行 ---
    # 这个钩子点非常适合执行与本次备份运行完全解耦的收尾任务，比如清理外部日志。
    log_msg INFO "[Hooks] 所有主要操作已完成，准备执行 'finalization' 钩子..."
    # 传递主备份流程的退出状态给钩子，以便钩子脚本可以根据情况决定是否执行某些操作
    export HOOK_MAIN_BACKUP_EXIT_CODE="$main_backup_exit_code" # 导出给钩子脚本
    _run_hooks "finalization" "$GLOBAL_RUN_TIMESTAMP" "$main_backup_exit_code"
    local finalization_hook_status=$?
    if [[ "$finalization_hook_status" -ne 0 ]]; then
        log_msg WARN "[Hooks] 'finalization' 钩子执行时报告了失败。"
        # 这里的钩子失败通常不应改变脚本的最终退出状态
    fi
    unset HOOK_MAIN_BACKUP_EXIT_CODE # 清理环境变量
    # --------------------------------------------------------------------------

    if [[ "$main_backup_exit_code" -ne 0 ]]; then
        echo "--- $(date '+%Y-%m-%d %H:%M:%S') - $SCRIPT_NAME (PID: $SCRIPT_PID) - 脚本因错误退出 (主备份流程错误码: $main_backup_exit_code) ---" >> "$ACTUAL_LOG_FILE"
        exit "$main_backup_exit_code"
    fi

    echo "--- $(date '+%Y-%m-%d %H:%M:%S') - $SCRIPT_NAME (PID: $SCRIPT_PID) - 脚本正常结束 ---" >> "$ACTUAL_LOG_FILE"
    exit 0
}

################################################################################
# 当脚本接收到 SIGINT 或 SIGTERM 信号时的清理处理函数。
# Globals:
#   ACTUAL_LOG_FILE (R) - 日志文件路径 (可能尚未完全初始化)。
#   SCRIPT_NAME   (R)
#   SCRIPT_PID    (R)
# Arguments:
#   $1 - 接收到的信号名称 (e.g., "SIGINT")。
# Returns:
#   脚本以对应信号的退出码退出 (通常是 128 + 信号编号)。
################################################################################
cleanup_on_signal() {
    local signal_name="$1"
    # Disable ERR trap to prevent recursive error handling if cleanup itself fails
    trap '' ERR

    local msg="脚本被信号 $signal_name 中断 (PID: $SCRIPT_PID)。正在尝试优雅退出..."
    if typeset -f log_msg &>/dev/null && [[ -n "${ACTUAL_LOG_FILE:-}" ]] && ( [[ -f "$ACTUAL_LOG_FILE" && -w "$ACTUAL_LOG_FILE" ]] || [[ -d "$(dirname "$ACTUAL_LOG_FILE")" && -w "$(dirname "$ACTUAL_LOG_FILE")" ]] ); then
        log_msg "WARN" "$msg"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $msg" | tee -a "${ACTUAL_LOG_FILE:-/tmp/${SCRIPT_NAME}_signal_fallback.log}" >&2
    fi
    
    # Add any other critical cleanup tasks here, e.g., removing temp files
    # find /tmp -maxdepth 1 -name "${SCRIPT_NAME}_*.XXXXXX" -user "$(id -un)" -delete 2>/dev/null
    
    local exit_code=1 # Default exit code for signals if not specific
    case "$signal_name" in
        SIGINT) exit_code=130 ;; # 128 + 2
        SIGTERM) exit_code=143 ;; # 128 + 15
    esac
    exit "$exit_code"
}
trap 'cleanup_on_signal SIGINT' SIGINT
trap 'cleanup_on_signal SIGTERM' SIGTERM

# 执行 main 函数
main "$@"