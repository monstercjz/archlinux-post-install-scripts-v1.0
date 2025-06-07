#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/utils.sh
# 版本: 1.3.1 (日志核心逻辑更新为基于索引)
# 日期: 2025-06-07
# 描述: 核心通用函数库。
#       提供项目运行所需的基础功能，包括依赖加载、日志记录、权限检查、
#       用户交互、文件操作等。旨在提高代码复用性、健壮性和可维护性。
# ------------------------------------------------------------------------------
# 核心功能：
# - 统一项目环境初始化 (_initialize_project_environment)。
# - 统一的日志系统：支持INFO/WARN/ERROR/DEBUG级别，终端彩色输出(可控)，
#   每脚本独立纯文本日志文件，并由原始用户拥有。
# - 权限管理：早期 root 权限检查，日志目录权限确保。
# - 用户上下文：识别调用 sudo 的原始用户 (ORIGINAL_USER) 及其家目录 (ORIGINAL_HOME)。
# ==============================================================================
# 相较于2.0版本的更新
# 你准确地指出了 display_header_section 这个问题。在方法二（固定索引）中，log_info 是被 display_header_section 调用的，所以 FUNCNAME[2] 会显示 display_header_section。
# 要解决这个问题，我们需要在 _log_message_core 中进一步调整索引。考虑到 display_header_section 位于 log_info 的上层调用，调用链是：
# run_setup.sh -> display_header_section() -> log_info() -> _log_message_core()
# 从 _log_message_core 的视角看：
# FUNCNAME[0] 是 _log_message_core
# FUNCNAME[1] 是 log_info
# FUNCNAME[2] 是 display_header_section
# FUNCNAME[3] 才是 display_header_section 的调用者（即 run_setup.sh 或它内部的某个函数）。
# 所以，我们需要将索引从 2 调整为 3。
# 没有使用2.2版本，而是用现在的2.1版本，2.2还是不准确

# 严格模式：
# -e: 遇到任何非零退出状态的命令立即退出。
# -u: 引用未设置的变量时报错。
# -o pipefail: 管道命令中任何一个失败都导致整个管道失败。
set -euo pipefail

# ==============================================================================
# 全局标志与变量 (由脚本内部设置和导出)
# ------------------------------------------------------------------------------
# 这些变量在 utils.sh 首次被 source 时初始化，并导出供所有后续脚本使用。
# 它们在此处被声明为 export，对于标志变量会赋初始值以避免 set -u 报错。
# ==============================================================================

# __UTILS_SOURCED__: 防止 utils.sh 被重复 source 导致函数重复定义。
# 必须赋初始值，否则在 set -u 模式下会报错。
export __UTILS_SOURCED__="" 
# __LOGGING_SETUP__: 确保日志系统只被初始化一次。 (此变量在当前设计中未使用，可考虑移除)
export __LOGGING_SETUP__="" 

# BASE_DIR: 项目的根目录。由 _initialize_project_environment 确定并导出。
# 仅声明导出，不在此处赋值，以避免覆盖已从父 shell 导出的值。
export BASE_DIR               
# CURRENT_SCRIPT_LOG_FILE: 当前脚本实例的专属日志文件路径。由 setup_logging 确定并导出。
export CURRENT_SCRIPT_LOG_FILE

# ORIGINAL_USER: 调用 sudo 的原始用户。由 _initialize_project_environment 确定并导出。
# 仅声明导出，不在此处赋值。
export ORIGINAL_USER          
# ORIGINAL_HOME: ORIGINAL_USER 的家目录。由 _initialize_project_environment 确定并导出。
# 仅声明导出，不在此处赋值。
export ORIGINAL_HOME          

# --- 颜色常量 (用于终端输出) ---
# 这些变量会在 source_dependencies 后，根据 main_config.sh 中的 ENABLE_COLORS 决定是否使用。
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_RESET="\033[0m" # 重置所有属性到默认值

# ==============================================================================
# 内部辅助函数 (不对外暴露，以 "_" 开头命名)
# ------------------------------------------------------------------------------

# _get_script_dir()
# 功能: 获取当前正在执行（或被 source）的脚本的绝对路径。
# 说明: 使用 BASH_SOURCE[0] 而非 $0，因为 $0 在 sourced 脚本中指向调用者。
#       `cd ... && pwd -P` 用于处理符号链接，确保获取真实路径。
# 返回: 脚本所在目录的绝对路径。
_get_script_dir() {
    local script_path="${BASH_SOURCE[0]}"
    # 兼容性处理: 在某些 shell 或特殊情况下，BASH_SOURCE[0] 可能为空或不准确。
    if [[ -z "$script_path" || "$script_path" == "-bash" ]]; then
        script_path="$0"
    fi
    echo "$(cd "$(dirname "$script_path")" && pwd -P)"
}

# _determine_base_dir_internal()
# 功能: 动态确定项目的根目录 (BASE_DIR)。
# 说明: 从当前脚本所在目录向上遍历，查找包含 'run_setup.sh' 文件和 'config' 目录的目录。
# 参数: $1 (caller_script_path) - 调用此函数的脚本的完整路径。
# 退出: 如果无法确定 BASE_DIR，则直接输出错误并退出。
_determine_base_dir_internal() {
    local caller_script_path="$1"
    
    # 获取调用者脚本的绝对目录
    local SCRIPT_DIR_ABS=$(cd "$(dirname "$caller_script_path")" && pwd)

    # 从当前目录开始向上查找项目根目录
    local temp_project_root="$SCRIPT_DIR_ABS"
    local found_root=false

    # 循环向上查找，直到找到项目根目录或到达文件系统根目录
    while [[ "$temp_project_root" != "/" ]]; do
        # 检查是否存在项目根目录的标志文件和目录
        if [[ -f "$temp_project_root/run_setup.sh" && -d "$temp_project_root/config" ]]; then
            BASE_DIR="$temp_project_root" # 找到根目录，赋值给全局变量
            found_root=true
            break
        fi
        temp_project_root=$(dirname "$temp_project_root") # 向上移动一层目录
    done

    # 如果未能找到项目根目录
    if ! "$found_root"; then
        echo "${COLOR_RED}Error:${COLOR_RESET} Could not determine project base directory from '$caller_script_path'. Please ensure script structure is correct." >&2
        exit 1
    fi
    export BASE_DIR # 导出 BASE_DIR，供所有后续脚本使用
}

# _initial_check_root_and_exit()
# 功能: 在日志系统初始化之前，执行强制性的 root 权限检查。
# 说明: 如果不是 root 用户，则打印带颜色的错误信息，等待用户按键后退出。
#       这是一个独立的函数，可在任何脚本的早期被调用。
_initial_check_root_and_exit() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${COLOR_RED}=====================================================================${COLOR_RESET}" >&2
        echo -e "${COLOR_RED}Error: This script must be run with root privileges (using 'sudo').${COLOR_RESET}" >&2
        echo -e "${COLOR_RED}Please run: sudo $0${COLOR_RESET}" >&2 # 使用 $0 显示当前脚本名
        echo -e "${COLOR_RED}=====================================================================${COLOR_RESET}" >&2
        read -rp "Press any key to exit..." -n 1
        echo "" # 打印一个换行符，使提示符在新行显示
        exit 1
    fi
}

# _get_original_user_and_home()
# 功能: 获取调用 sudo 的原始用户和其家目录。
# 说明: 在日志系统初始化之前被调用，直接将结果赋值给全局变量 ORIGINAL_USER 和 ORIGINAL_HOME。
_get_original_user_and_home() {
    # ORIGINAL_USER 由 SUDO_USER 决定，如果不存在则使用当前用户 (root)。
    ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
    export ORIGINAL_USER # 确保立即导出

    if [ "$ORIGINAL_USER" == "root" ]; then
        ORIGINAL_HOME="/root"
    else
        # 更安全地获取原始用户的家目录
        if id -u "$ORIGINAL_USER" &>/dev/null; then 
            # 优先使用 getent，如果系统安装了它
            if command -v getent &>/dev/null; then
                ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
            else
                # 作为回退，直接从 /etc/passwd 解析 (不够健壮，但比 eval 好)
                ORIGINAL_HOME=$(grep "^$ORIGINAL_USER:" /etc/passwd | cut -d: -f6)
            fi

            if [[ -z "$ORIGINAL_HOME" ]]; then
                 echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Could not determine home directory for '$ORIGINAL_USER' via getent/grep. Falling back to current \$HOME." >&2
                 ORIGINAL_HOME="$HOME" # 回退到当前 SHELL 的 $HOME
            fi
        else
            echo "${COLOR_RED}Error:${COLOR_RESET} Original user '$ORIGINAL_USER' not found. Falling back to current \$HOME." >&2
            ORIGINAL_HOME="$HOME" # 回退到当前 SHELL 的 $HOME
        fi
    fi
    export ORIGINAL_HOME # 确保立即导出
    echo "Detected original user: $ORIGINAL_USER (Home: $ORIGINAL_HOME)" >&2 # 早期输出
}

# _log_message_core() - 已修改为使用 BASH_SOURCE 和 FUNCNAME 索引
# 功能: 核心日志记录逻辑，负责格式化日志信息并输出到终端和文件。
# 参数: $1 (level) - 日志级别 (例如 "INFO", "ERROR")。
#       $2 (message) - 要记录的日志消息。
# 说明: 通过 BASH_SOURCE 和 FUNCNAME 数组的固定索引来定位日志的原始调用源。
#       调用链通常为: _log_message_core <- log_X <- display_header_section <- 原始调用函数/脚本。
#       因此，FUNCNAME[3] 和 BASH_SOURCE[3] 通常指向原始调用者（跳过display_header_section）。
#       此方法对调用层级变化敏感，如果中间函数层级改变，索引需手动调整。
_log_message_core() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # --- 关键修正开始: 使用 BASH_SOURCE 和 FUNCNAME 数组索引定位调用源 ---
    # 调整索引为 [3] 以跳过 display_header_section。
    local calling_source_name="unknown"
    local source_func="${FUNCNAME[3]:-}"        # 尝试获取原始调用函数名
    local source_file_path="${BASH_SOURCE[3]:-}" # 尝试获取原始调用文件路径

    # 优先使用函数名，如果存在且不是 shell 内部的伪函数 (如 "source", "main")
    if [[ -n "$source_func" && "$source_func" != "source" && "$source_func" != "main" ]]; then
        calling_source_name="$source_func"
    # 否则，如果文件路径存在，使用文件名
    elif [[ -n "$source_file_path" ]]; then
        calling_source_name=$(basename "$source_file_path")
    # 如果以上都失败，回退到最顶层执行的脚本名 (最可靠的通用回退)
    else
        calling_source_name=$(basename "${BASH_SOURCE[-1]}")
    fi
    # --- 关键修正结束 ---

    local terminal_color_code="${COLOR_RESET}"
    case "$level" in
        "INFO")    terminal_color_code="${COLOR_GREEN}" ;;
        "WARN")    terminal_color_code="${COLOR_YELLOW}" ;;
        "ERROR")   terminal_color_code="${COLOR_RED}" ;;
        "DEBUG")   terminal_color_code="${COLOR_BLUE}" ;;
        *)         terminal_color_code="${COLOR_RESET}" ;;
    esac

    # 1. 终端输出：带颜色的日志信息。
    if [[ "${ENABLE_COLORS:-true}" == "true" ]]; then
        echo -e "${terminal_color_code}[$timestamp] [$level] [$calling_source_name] $message${COLOR_RESET}"
    else
        echo "[$timestamp] [$level] [$calling_source_name] $message"
    fi
    
    # 2. 文件写入：纯文本日志信息。
    if [[ -n "${CURRENT_SCRIPT_LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] [$calling_source_name] $message" >> "${CURRENT_SCRIPT_LOG_FILE}" || \
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to write log to file '${CURRENT_SCRIPT_LOG_FILE}'. Check permissions." >&2
    fi
}

# ==============================================================================
# 核心项目初始化函数 (供所有入口脚本调用)
# ------------------------------------------------------------------------------

# _initialize_project_environment()
# 功能: 统一的项目环境初始化函数。
# 说明: 负责所有脚本启动时的必要设置，包括权限检查、目录确定、配置加载、
#       用户上下文获取和日志系统初始化。
# 参数: $1 (caller_script_path) - 调用此函数的脚本的完整路径 (如 "${BASH_SOURCE[0]}")。
_initialize_project_environment() {
    local caller_script_path="$1"

    # 1. 检查 utils.sh 是否已加载，防止重复定义函数。
    if [ -n "${__UTILS_SOURCED__}" ]; then # 检查标志变量是否有非空值
        return 0 # 如果已被加载，直接返回，避免重复执行初始化逻辑。
    fi

    # 2. 早期 root 权限检查。
    _initial_check_root_and_exit

    # 3. 确定项目根目录 (BASE_DIR)。
    #    只有当 BASE_DIR 未从父 shell 导出（即处于 unset 状态）时才执行推断。
    #    使用 ${VAR+set} 检查变量是否已设置 (无论值是否为空)，这是最安全的。
    if [ -z "${BASE_DIR+set}" ]; then 
        _determine_base_dir_internal "$caller_script_path"
    fi

    # 4. 加载 main_config.sh，使其定义的变量在早期可用。
    local main_config_path="${BASE_DIR}/config/main_config.sh"
    if [ -f "$main_config_path" ]; then
        . "$main_config_path"
    else
        # 此时可能日志系统未完全初始化，直接 echo 致命错误。
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} Main configuration file not found at '$main_config_path'. Exiting." >&2
        exit 1
    fi

    # 5. 获取原始用户和家目录信息。
    #    只有当 ORIGINAL_USER 未从父 shell 导出（即处于 unset 状态）时才执行获取。
    if [ -z "${ORIGINAL_USER+set}" ]; then 
        _get_original_user_and_home
    fi

    # 6. 确保日志根目录存在并对 ORIGINAL_USER 有写入权限。
    if ! _ensure_log_dir_user_owned "$LOG_ROOT" "$ORIGINAL_USER"; then
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} Could not prepare log directory. Exiting." >&2
        exit 1
    fi

    # 7. 初始化日志系统。
    setup_logging "$caller_script_path"

    # 8. 标记 utils.sh 已加载。
    export __UTILS_SOURCED__="true"
}

# ==============================================================================
# 日志记录函数 (对外暴露)
# ------------------------------------------------------------------------------

# setup_logging()
# 功能: 初始化日志系统。
# 说明: 为当前脚本实例生成一个唯一的日志文件路径，并将其导出。
#       日志文件会由当前执行的用户 (root) 创建，然后其所有权会尝试调整给 ORIGINAL_USER。
# 参数: $1 (caller_script_path) - 当前正在执行的脚本的完整路径。
setup_logging() {
    local caller_script_path="$1"
    local script_name=$(basename "$caller_script_path")

    CURRENT_SCRIPT_LOG_FILE="$LOG_ROOT/${script_name%.*}-$(date +%Y%m%d_%H%M%S).log"
    export CURRENT_SCRIPT_LOG_FILE

    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} Initializing logging for '$script_name'. Log file will be: '$CURRENT_SCRIPT_LOG_FILE'" >&2
    
    # 1. 创建日志文件 (由当前用户，即 root)
    # 不使用 sudo，因为它由 root 运行
    if ! touch "$CURRENT_SCRIPT_LOG_FILE"; then 
        echo "${COLOR_RED}Error:${COLOR_RESET} Failed to create log file '$CURRENT_SCRIPT_LOG_FILE' as root. Logging might fail." >&2
        return 1 # 返回失败，但脚本可能继续运行
    fi

    # 2. 设置日志文件权限 (由当前用户，即 root)
    if ! chmod 644 "$CURRENT_SCRIPT_LOG_FILE"; then
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to set permissions 644 for '$CURRENT_SCRIPT_LOG_FILE' as root." >&2
    fi

    # 3. 尝试将日志文件所有权调整给 ORIGINAL_USER
    if id -u "$ORIGINAL_USER" &>/dev/null; then # 确保 ORIGINAL_USER 存在
        # 使用 chown，因为当前脚本以 root 运行
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
# 说明: 此函数只进行检查并返回状态码，不直接输出错误或退出。
#       由调用者处理其返回值。
check_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return 1 # 非 root 用户
    else
        return 0 # 是 root 用户
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

# ==============================================================================
# 日志目录权限管理函数 (内部辅助，由 _initialize_project_environment 调用)
# ------------------------------------------------------------------------------

# _ensure_log_dir_user_owned()
# 功能: 确保日志根目录存在，并确保 ORIGINAL_USER 对其有写入权限。
# 说明: 这个函数在日志系统完全初始化之前被调用，因此它不能使用 log() 函数。
#       它会直接使用 echo 输出信息。优先使用 setfacl 提供精确权限。
# 参数: $1 (dir_path) - 要检查/创建的日志根目录路径。
#       $2 (user)    - ORIGINAL_USER (调用 sudo 的用户)。
# 返回: 0 (成功) 或 1 (失败)。
_ensure_log_dir_user_owned() { # <--- 函数名已更改
    local dir_path="$1"
    local user="$2"
    local info_prefix="${COLOR_BLUE}INFO:${COLOR_RESET}"
    local warn_prefix="${COLOR_YELLOW}WARNING:${COLOR_RESET}"
    local error_prefix="${COLOR_RED}ERROR:${COLOR_RESET}"

    echo -e "${info_prefix} Checking/creating log directory '$dir_path' for user '$user'..." >&2

    # 1. 创建目录 (如果不存在) - 直接使用 mkdir，因为它由 root 运行
    if [ ! -d "$dir_path" ]; then
        if mkdir -p "$dir_path"; then 
            echo -e "${info_prefix} Log directory '$dir_path' created." >&2
        else
            echo -e "${error_prefix} Failed to create log directory '$dir_path'. Permissions issue?" >&2
            return 1
        fi
    fi

    # 2. 确保 ORIGINAL_USER 对目录有写入权限
    if ! sudo -u "$user" test -w "$dir_path"; then # 这里仍然需要 sudo -u 来测试指定用户权限
        echo -e "${warn_prefix} Log directory '$dir_path' is not writable by user '$user'. Attempting to adjust permissions..." >&2

        # 优先使用 setfacl (更精确，不破坏现有权限) - 直接使用 setfacl，因为它由 root 运行
        if command -v setfacl &>/dev/null; then
            echo -e "${info_prefix} Using setfacl to grant write access to '$user' for '$dir_path'." >&2
            # -m: modify ACL, -d: default ACL (for new files/dirs), u: user, w: write, x: execute
            # 确保用户具有读、写、执行权限，以及对新建文件的默认 ACL。
            if setfacl -m u:"$user":rwx -d -m u:"$user":rwx "$dir_path"; then
                echo -e "${info_prefix} setfacl successfully granted write access to '$user' for '$dir_path'." >&2
            else
                echo -e "${error_prefix} setfacl failed. Falling back to chmod/chown method." >&2
                # 回退到 chmod/chown - 直接使用 chown/chmod，因为它由 root 运行
                local user_primary_group=$(id -gn "$user" 2>/dev/null)
                if [[ -n "$user_primary_group" ]]; then
                    chown "root:$user_primary_group" "$dir_path" || \
                        echo "${error_prefix} Failed to set group of '$dir_path' to '$user_primary_group'." >&2
                fi
                chmod g+w "$dir_path" || \
                    echo "${error_prefix} Failed to set group write permissions for '$dir_path'." >&2
                echo -e "${warn_prefix} You may need to log out and back in for group changes to take effect for '$user'." >&2
            fi
        else
            echo -e "${warn_prefix} setfacl not found. Falling back to chmod/chown method (less precise)." >&2
            # 回退到 chmod/chown - 直接使用 chown/chmod，因为它由 root 运行
            local user_primary_group=$(id -gn "$user" 2>/dev/null)
            if [[ -n "$user_primary_group" ]]; then
                chown "root:$user_primary_group" "$dir_path" || \
                    echo "${error_prefix} Failed to set group of '$dir_path' to '$user_primary_group'." >&2
            fi
            chmod g+w "$dir_path" || \
                    echo "${error_prefix} Failed to set group write permissions for '$dir_path'." >&2
            echo -e "${warn_prefix} You may need to log out and back in for group changes to take effect for '$user'." >&2
        fi

        # 再次检查是否可写
        if ! sudo -u "$user" test -w "$dir_path"; then # 这里仍然需要 sudo -u 来测试指定用户权限
            echo -e "${error_prefix} After attempting adjustments, log directory '$dir_path' is still not writable by user '$user'. Logging to file may fail." >&2
            return 1
        fi
    fi

    echo -e "${info_prefix} Log directory '$dir_path' is writable by '$user'." >&2
    return 0
}