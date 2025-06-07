#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/utils.sh
# 版本: 1.5.1 (适配日期日志目录层级)
# 日期: 2025-06-08
# 描述: 核心通用函数库。
#       提供项目运行所需的基础功能，包括日志记录、用户上下文识别、权限检查辅助、
#       文件操作等。此文件不直接进行环境初始化或Root权限检查（由 environment_setup.sh 完成）。
# ------------------------------------------------------------------------------
# 核心功能：
# - 统一的日志系统：支持INFO/WARN/ERROR/DEBUG级别，终端彩色输出(可控)，
#   每脚本独立纯文本日志文件，并由原始用户拥有。
# - 用户上下文：识别调用 sudo 的原始用户 (ORIGINAL_USER) 及其家目录 (ORIGINAL_HOME)。
# - 统一的错误处理函数 (handle_error)。
# - 文件与目录权限管理辅助。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.5.0 - 2025-06-08 - 全面增强注释，日志相关函数归集，提升可读性。
# v1.5.1 - 2025-06-08 - **适配日期日志目录层级 (CURRENT_DAY_LOG_DIR)。**
# ==============================================================================

# 严格模式：
set -euo pipefail

# ==============================================================================
# 全局标志与变量声明 (由 environment_setup.sh 负责赋值和导出)
# ------------------------------------------------------------------------------
__UTILS_SOURCED__="" 

export BASE_DIR               
export CURRENT_SCRIPT_LOG_FILE

export ORIGINAL_USER          
export ORIGINAL_HOME          

export CONFIG_DIR
export LIB_DIR
export MODULES_DIR
export ASSETS_DIR

# CURRENT_DAY_LOG_DIR: 当前日期日志目录的绝对路径。由 environment_setup.sh 定义并导出。
export CURRENT_DAY_LOG_DIR # <--- 新增导出声明

# _caller_script_path: 原始调用（执行）脚本的绝对路径。
# ... (注释不变) ...

# --- 颜色常量 (用于终端输出) ---
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_RESET="\033[0m"

# ==============================================================================
# 内部辅助函数 (以 "_" 开头命名)
# ------------------------------------------------------------------------------

# _get_original_user_and_home()
_get_original_user_and_home() {
    ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
    export ORIGINAL_USER

    if [ "$ORIGINAL_USER" == "root" ]; then
        ORIGINAL_HOME="/root"
    else
        if id -u "$ORIGINAL_USER" &>/dev/null; then 
            if command -v getent &>/dev/null; then
                ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
            else
                ORIGINAL_HOME=$(grep "^$ORIGINAL_USER:" /etc/passwd | cut -d: -f6)
            fi

            if [[ -z "$ORIGINAL_HOME" ]]; then
                 log_warn "Could not determine home directory for '$ORIGINAL_USER' via getent/grep. Falling back to current \$HOME."
                 ORIGINAL_HOME="$HOME"
            fi
        else
            log_error "Original user '$ORIGINAL_USER' not found. Falling back to current \$HOME."
            ORIGINAL_HOME="$HOME"
        fi
    fi
    export ORIGINAL_HOME
}

# _ensure_log_dir_user_owned()
# 功能: 确保指定的日志目录存在，并设置适当的权限。
# 参数: $1 (dir_path) - 要检查/创建的日志目录的绝对路径（现在通常是 CURRENT_DAY_LOG_DIR）。
#       $2 (user)    - ORIGINAL_USER。
_ensure_log_dir_user_owned() {
    local dir_path="$1"
    local user="$2"
    
    log_info "Checking/creating log directory '$dir_path' for user '$user'..."

    if [ ! -d "$dir_path" ]; then
        if mkdir -p "$dir_path"; then 
            log_info "Log directory '$dir_path' created."
        else
            log_error "Failed to create log directory '$dir_path'. Permissions issue?"
            return 1
        fi
    fi

    if ! sudo -u "$user" test -w "$dir_path"; then
        log_warn "Log directory '$dir_path' is not writable by user '$user'. Attempting to adjust permissions..."

        if command -v setfacl &>/dev/null; then
            log_info "Using setfacl to grant write access to '$user' for '$dir_path'."
            if setfacl -m u:"$user":rwx -d -m u:"$user":rwx "$dir_path"; then
                log_info "setfacl successfully granted write access to '$user' for '$dir_path'."
            else
                log_error "setfacl failed. Falling back to chmod/chown method."
                local user_primary_group=$(id -gn "$user" 2>/dev/null)
                if [[ -n "$user_primary_group" ]]; then
                    chown "root:$user_primary_group" "$dir_path" || \
                        log_error "Failed to set group of '$dir_path' to '$user_primary_group'."
                fi
                chmod g+w "$dir_path" || \
                    log_error "Failed to set group write permissions for '$dir_path'."
                log_warn "You may need to log out and back in for group changes to take effect for '$user'."
            fi
        else
            log_warn "setfacl not found. Falling back to chmod/chown method (less precise)."
            local user_primary_group=$(id -gn "$user" 2>/dev/null)
            if [[ -n "$user_primary_group" ]]; then
                chown "root:$user_primary_group" "$dir_path" || \
                    log_error "Failed to set group of '$dir_path' to '$user_primary_group'."
            fi
            chmod g+w "$dir_path" || \
                    log_error "Failed to set group write permissions for '$dir_path'."
            log_warn "You may need to log out and back in for group changes to take effect for '$user'."
        fi

        if ! sudo -u "$user" test -w "$dir_path"; then
            log_error "After attempting adjustments, log directory '$dir_path' is still not writable by user '$user'. Logging to file may fail."
            return 1
        fi
    fi

    log_info "Log directory '$dir_path' is writable by '$user'."
    return 0
}

# ==============================================================================
# 日志记录模块 (包含核心日志逻辑和封装函数)
# ------------------------------------------------------------------------------

# _log_message_core()
# 功能: 核心日志记录逻辑，负责格式化日志信息并输出到终端和文件。
# 说明: 遍历 BASH_SOURCE 和 FUNCNAME 数组，跳过所有被视为内部工具链的函数，
#       以识别出最上层的业务逻辑调用源（函数名或脚本名）。
# 参数: $1 (level) - 日志级别 (例如 "INFO", "ERROR")。
#       $2 (message) - 要记录的日志消息。
_log_message_core() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    local calling_source_name="unknown"
    local stack_idx=0
    local found_source=false

    # 定义所有应被跳过的内部日志/工具函数名。
    # 如果希望其日志源显示脚本名而非函数名，也应添加。
    local -a internal_utility_functions=(
        "_log_message_core"           # 自身
        "log_info"                    # 日志封装函数
        "log_warn"
        "log_error"
        "log_debug"
        "display_header_section"      # 通用头部显示函数
        "handle_error"                # 错误处理函数
        "setup_logging"               # 日志系统初始化函数
        "_get_original_user_and_home" # 内部辅助函数
        "_ensure_log_dir_user_owned"  # 内部辅助函数
        "check_root_privileges"       # 通用权限检查辅助函数
        "show_main_menu"              # 菜单显示函数 (主菜单)
        # 扩展列表：
        # "show_system_base_menu"     # 示例：系统基础配置菜单显示函数
        # "process_main_menu_choice"  # 示例：如果希望该函数内部日志显示脚本名而非函数名
    )

    for (( stack_idx=0; stack_idx < ${#FUNCNAME[@]}; stack_idx++ )); do
        local current_func_name="${FUNCNAME[stack_idx]:-}"
        local current_file_path="${BASH_SOURCE[stack_idx]:-}"

        local is_internal_func=false
        for internal_func in "${internal_utility_functions[@]}"; do
            if [[ "$current_func_name" == "$internal_func" ]]; then
                is_internal_func=true
                break
            fi
        done

        if "$is_internal_func"; then
            continue
        fi

        if [[ -n "$current_func_name" && "$current_func_name" != "source" && "$current_func_name" != "main" ]]; then
            calling_source_name="$current_func_name"
            found_source=true
            break
        elif [[ -n "$current_file_path" ]]; then
            if [[ -n "${BASE_DIR:-}" && "$current_file_path" == "${BASE_DIR}"* ]]; then
                calling_source_name="${current_file_path#"$BASE_DIR/"}"
            else
                calling_source_name=$(basename "$current_file_path")
            fi
            found_source=true
            break
        fi
    done

    if ! "$found_source"; then
        calling_source_name=$(basename "${_caller_script_path:-${BASH_SOURCE[-1]}}")
    fi

    local terminal_color_code="${COLOR_RESET}"
    case "$level" in
        "INFO")    terminal_color_code="${COLOR_GREEN}" ;;
        "WARN")    terminal_color_code="${COLOR_YELLOW}" ;;
        "ERROR")   terminal_color_code="${COLOR_RED}" ;;
        "DEBUG")   terminal_color_code="${COLOR_BLUE}" ;;
        *)         terminal_color_code="${COLOR_RESET}" ;;
    esac

    if [[ "${ENABLE_COLORS:-true}" == "true" ]]; then
        echo -e "${terminal_color_code}[$timestamp] [$level] [$calling_source_name] $message${COLOR_RESET}"
    else
        echo "[$timestamp] [$level] [$calling_source_name] $message"
    fi
    
    if [[ -n "${CURRENT_SCRIPT_LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] [$calling_source_name] $message" >> "${CURRENT_SCRIPT_LOG_FILE}" || \
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to write log to file '${CURRENT_SCRIPT_LOG_FILE}'. Check permissions." >&2
    fi
}

# setup_logging()
# 功能: 初始化当前脚本实例的日志系统。
# 说明: 为当前脚本实例生成一个唯一的日志文件路径，并将其导出。
#       日志文件会由当前执行的用户 (root) 创建，然后其所有权会尝试调整给 ORIGINAL_USER。
#       此函数在 environment_setup.sh 中调用。
# 参数: $1 (caller_script_path) - 当前正在执行的（原始入口点）脚本的完整路径。
# 返回: 0 (成功) 或 1 (失败)。
setup_logging() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    # 确保 BASE_DIR 和 CURRENT_DAY_LOG_DIR 已被 environment_setup.sh 设置
    if [ -z "${BASE_DIR+set}" ] || [ -z "${CURRENT_DAY_LOG_DIR+set}" ]; then
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.setup_logging] Logging environment (BASE_DIR or CURRENT_DAY_LOG_DIR) not set. Exiting." >&2
        exit 1
    fi

    # 日志文件路径现在包含日期目录
    CURRENT_SCRIPT_LOG_FILE="$CURRENT_DAY_LOG_DIR/${script_name%.*}-$(date +%Y%m%d_%H%M%S).log"
    export CURRENT_SCRIPT_LOG_FILE

    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} Initializing logging for '$script_name'. Log file will be: '$CURRENT_SCRIPT_LOG_FILE'" >&2
    
        if ! touch "$CURRENT_SCRIPT_LOG_FILE"; then 
        echo "${COLOR_RED}Error:${COLOR_RESET} Failed to create log file '$CURRENT_SCRIPT_LOG_FILE' as root. Logging might fail." >&2
        return 1 # 文件创建失败，返回 1
    fi

    if ! chmod 644 "$CURRENT_SCRIPT_LOG_FILE"; then
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to set permissions 644 for '$CURRENT_SCRIPT_LOG_FILE' as root." >&2
        return 1 # <--- 修正：权限设置失败，也返回 1。因为日志文件后续写入可能依赖这些权限。
    fi

    if id -u "$ORIGINAL_USER" &>/dev/null; then # 确保 ORIGINAL_USER 存在
        if ! chown "$ORIGINAL_USER" "$CURRENT_SCRIPT_LOG_FILE"; then
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to change ownership of '$CURRENT_SCRIPT_LOG_FILE' to '$ORIGINAL_USER'. File will be owned by root." >&2
            return 1 # <--- 修正：所有权更改失败，也返回 1。因为 ORIGINAL_USER 后续可能需要管理这些日志。
        fi
    else
        # 这种情况通常是 _get_original_user_and_home 已经发出警告的情况，
        # 如果 ORIGINAL_USER 不存在，chown 本身就会失败。这里可以继续警告。
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Original user '$ORIGINAL_USER' not found or invalid. Log file '$CURRENT_SCRIPT_LOG_FILE' will remain owned by root." >&2
        # 这里仍然不返回 1，因为它不是 chown 失败的直接原因，而是前置条件的问题。
        # 如果 ORIGINAL_USER 不存在，那么 chown "$ORIGINAL_USER" "$FILE" 会失败，上面会捕获。
    fi
    
    return 0 # 成功
}

# --- 对外暴露的日志级别封装函数 ---
log_info() { _log_message_core "INFO" "$1"; }
log_warn() { _log_message_core "WARN" "$1" >&2; }
log_error() { _log_message_core "ERROR" "$1" >&2; }
log_debug() {
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        _log_message_core "DEBUG" "$1"
    fi
}

# ==============================================================================
# 通用工具函数 (对外暴露)
# ------------------------------------------------------------------------------

# check_root_privileges()
check_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return 1
    else
        return 0
    fi
}

# display_header_section()
display_header_section() {
    local title="$1"
    log_info "=================================================="
    log_info ">>> $title"
    log_info "=================================================="
}

# handle_error()
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    log_error "Script execution terminated due to previous error."
    exit "$exit_code"
}