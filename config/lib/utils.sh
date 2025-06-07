#!/bin/bash
# ... (顶部注释和版本号更新) ...

# 严格模式：
set -euo pipefail

# ==============================================================================
# 全局标志与变量 (由 environment_setup.sh 设置和导出)
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

# _caller_script_path: 由调用脚本的顶部引导块设置，并作为参数传递给 environment_setup.sh，
# environment_setup.sh 再将它传递给 setup_logging 和内部辅助函数。
# 它最终在环境中是可用的，供 _log_message_core 使用。

# --- 颜色常量 (用于终端输出) ---
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_RESET="\033[0m"

# ==============================================================================
# 内部辅助函数 (不对外暴露，以 "_" 开头命名)
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

# _log_message_core()
_log_message_core() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    local calling_source_name="unknown"
    local stack_idx=0
    local found_source=false

    # 定义所有应被跳过的内部日志/工具函数名
    # 当新增任何调用 log_X 的 utils.sh 内部辅助函数时，都应将其添加到此列表。
    # 此外，像菜单显示函数（如 show_main_menu）等，如果希望其日志源显示脚本名而非函数名，也可添加。
    local -a internal_utility_functions=(
        "_log_message_core"
        "log_info"
        "log_warn"
        "log_error"
        "log_debug"
        "display_header_section"    # <-- 确保添加这个，它是通用头显示函数
        "handle_error"
        "setup_logging"
        "_get_original_user_and_home"
        "_ensure_log_dir_user_owned"
        "check_root_privileges"
        "show_main_menu"            # <-- **新增！**
        # 未来如果添加例如：show_system_base_menu, show_package_management_menu 等，如果希望其日志源显示脚本名，也应添加到此列表。
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

        # 到达这里，说明找到第一个不是内部工具函数/日志包装器的函数/脚本
        # 优先使用函数名（如果存在且不是 shell 内部的伪函数）
        if [[ -n "$current_func_name" && "$current_func_name" != "source" && "$current_func_name" != "main" ]]; then
            calling_source_name="$current_func_name"
            found_source=true
            break # 找到源，退出循环
        # 否则，如果文件路径存在，使用相对于 BASE_DIR 的路径或文件名
        elif [[ -n "$current_file_path" ]]; then
            if [[ -n "${BASE_DIR:-}" && "$current_file_path" == "${BASE_DIR}"* ]]; then
                calling_source_name="${current_file_path#"$BASE_DIR/"}"
            else
                calling_source_name=$(basename "$current_file_path")
            fi
            found_source=true
            break # 找到源，退出循环
        fi
    done

    # 最终回退：如果循环结束仍未找到合适的源
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

# ==============================================================================
# 日志记录函数 (对外暴露)
# ------------------------------------------------------------------------------
setup_logging() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    if [ -z "${BASE_DIR+set}" ] || [ -z "${LOG_ROOT+set}" ]; then
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.setup_logging] Logging environment (BASE_DIR or LOG_ROOT) not set. Exiting." >&2
        exit 1
    fi

    CURRENT_SCRIPT_LOG_FILE="$LOG_ROOT/${script_name%.*}-$(date +%Y%m%d_%H%M%S).log"
    export CURRENT_SCRIPT_LOG_FILE

    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} Initializing logging for '$script_name'. Log file will be: '$CURRENT_SCRIPT_LOG_FILE'" >&2
    
    if ! touch "$CURRENT_SCRIPT_LOG_FILE"; then 
        echo "${COLOR_RED}Error:${COLOR_RESET} Failed to create log file '$CURRENT_SCRIPT_LOG_FILE' as root. Logging might fail." >&2
        return 1
    fi

    if ! chmod 644 "$CURRENT_SCRIPT_LOG_FILE"; then
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to set permissions 644 for '$CURRENT_SCRIPT_LOG_FILE' as root." >&2
    fi

    if id -u "$ORIGINAL_USER" &>/dev/null; then
        if ! chown "$ORIGINAL_USER" "$CURRENT_SCRIPT_LOG_FILE"; then
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to change ownership of '$CURRENT_SCRIPT_LOG_FILE' to '$ORIGINAL_USER'. File will be owned by root." >&2
        fi
    else
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Original user '$ORIGINAL_USER' not found or invalid. Log file '$CURRENT_SCRIPT_LOG_FILE' will remain owned by root." >&2
    fi
}

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
# 功能: 检查当前脚本是否以 root 权限运行。
# 返回: 0 (成功) 表示是 root，1 (失败) 表示不是 root。
check_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return 1
    else
        return 0
    fi
}

# display_header_section()
# 功能: 在终端和日志中打印一个格式化的标题或部分分隔符。
# 参数: $1 (title) - 要显示的标题文本。
display_header_section() {
    local title="$1"
    log_info "=================================================="
    log_info ">>> $title"
    log_info "=================================================="
}

# handle_error()
# 功能: 统一的错误处理函数，记录错误并退出脚本。
# 参数: $1 (message) - 错误消息。
#       $2 (exit_code) - 可选，自定义退出码 (默认为 1)。
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    log_error "Script execution terminated due to previous error."
    exit "$exit_code"
}

# ==============================================================================
# 日志目录权限管理函数 (内部辅助，由 environment_setup.sh 调用)
# ------------------------------------------------------------------------------

# _ensure_log_dir_user_owned()
# 功能: 确保日志根目录存在并对 ORIGINAL_USER 有写入权限。
# 说明: 这个函数在日志系统完全初始化之前被调用，因此它不能使用 log() 函数。
_ensure_log_dir_user_owned() {
    local dir_path="$1"
    local user="$2"
    # 直接使用 log_info/warn/error，因为它们现在应该可用，并且 _log_message_core 会跳过这些内部函数
    
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