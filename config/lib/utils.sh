#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/utils.sh
# 版本: 2.0.6 (重构日志核心函数：拆分格式化与写入逻辑)
# 日期: 2025-06-08
# 描述: 核心通用函数库。
#       提供项目运行所需的基础功能，包括日志记录、用户上下文识别、权限检查辅助、
#       文件操作等。此文件不直接进行环境初始化或Root权限检查；其函数由
#       'environment_setup.sh' 调用以完成环境引导。
# ------------------------------------------------------------------------------
# 核心功能：
# - 统一的日志系统：支持INFO/WARN/ERROR/DEBUG/SUMMARY/NOTICE级别，
#   终端彩色输出(可控，支持两种颜色模式)，每脚本独立纯文本日志文件，
#   并由原始用户拥有。
# - 日志系统初始化 (initialize_logging_system) - 职责更单一。
# - 用户上下文：识别调用 sudo 的原始用户 (ORIGINAL_USER) 及家庭目录 (ORIGINAL_HOME)。
# - 统一的错误处理函数 (handle_error)。
# - 文件与目录权限管理辅助 - 职责更单一。
# - 增强的头部显示函数 (display_header_section) 支持多种样式。
# ------------------------------------------------------------------------------
# 变更记录:
# v2.0.0 - 2025-06-08 - 核心函数全面拆分重构，注释极致详尽。
# v2.0.1 - 2025-06-08 - 优化变量声明：移除 utils.sh 顶部不必要的全局 export 变量声明。
# v2.0.2 - 2025-06-08 - 优化变量声明：将 CURRENT_DAY_LOG_DIR 和 CURRENT_SCRIPT_LOG_FILE
#                      的声明保留在 utils.sh，因为它们是日志模块的动态输出。
# v2.0.3 - 2025-06-08 - 进一步优化变量声明：utils.sh 仅声明和导出其自身管理的变量 (颜色和日志状态)。
#                      其他全局变量 (如 BASE_DIR, ORIGINAL_USER等) 假定由 environment_setup.sh 提供。
# v2.0.4 - 2025-06-08 - 新增通用确认提示函数 `_confirm_action`，提高代码复用性。
# v2.0.5 - 2025-06-08 - 新增日志颜色显示模式控制 (LOG_COLOR_MODE)。
#                      默认为 'full_line' (整行着色)，可设为 'level_only' (仅日志级别着色)。
#                      新增 'NOTICE' 日志级别及其对应的绿色。
# v2.0.6 - 2025-06-08 - **重构日志核心函数 `_log_message_core`，将其拆分为：**
#                      **`_format_log_strings` (负责日志字符串格式化和拼接)**
#                      **`_write_log_output` (负责将格式化后的日志写入终端和文件)。**
# ==============================================================================

# 严格模式：
# -e: 遇到任何非零退出状态的命令立即退出。
# -u: 引用未设置的变量时报错。
# -o pipefail: 管道命令中任何一个失败都导致整个管道失败。
set -euo pipefail

# ==============================================================================
# 全局标志与变量声明 (仅限 utils.sh 内部管理和核心日志系统状态变量)
# ------------------------------------------------------------------------------

# __UTILS_SOURCED__: 防止 utils.sh 在同一个 shell 进程中被重复 source 导致函数重复定义。
# (此变量不会被导出，以确保在新的子进程中能重新加载 utils.sh 的函数定义)
__UTILS_SOURCED__="" 

# CURRENT_SCRIPT_LOG_FILE: 当前脚本实例的专属日志文件路径。由 initialize_logging_system 函数确定并导出。
export CURRENT_SCRIPT_LOG_FILE

# CURRENT_DAY_LOG_DIR: 当前日期日志目录的绝对路径（例如：/path/to/logs/YYYY-MM-DD）。
# 由 initialize_logging_system 函数内部定义并导出。
export CURRENT_DAY_LOG_DIR 

# _caller_script_path: 原始调用（执行）脚本的绝对路径。
# 由调用脚本的顶部引导块设置，并作为参数传递给 environment_setup.sh，
# 再由 environment_setup.sh 传递给需要它的函数（如 _get_log_caller_info）。
# (此变量不会被导出，但其值在当前 shell 进程中可用，通过函数参数传递)

# LOG_COLOR_MODE: 控制日志在终端的颜色显示模式。
# "full_line": 整行日志（包括时间戳、调用者、消息）都显示颜色 (现有行为)。
# "level_only": 仅日志级别标签（如 [INFO], [WARN]）显示颜色，其余内容保持默认终端颜色。
# 默认值应在 environment_setup.sh (通过 main_config.sh) 中设置。
# 如果未设置，此文件内部默认使用 "full_line" 以保持向后兼容。
export LOG_COLOR_MODE="${LOG_COLOR_MODE:-full_line}" 

# --- 颜色常量 (用于终端输出) ---
# 这些变量在 utils.sh 首次被 source 时初始化，并被 export readonly 到环境中。
# 确保所有子进程都能继承并使用这些颜色代码。

export readonly COLOR_DARK_GRAY='\033[1;30m' # 暗灰色 (info)
export readonly COLOR_GREEN="\033[0;32m"  # 绿色 (notice)
export readonly COLOR_RED="\033[0;31m"    # 红色 (Error)
export readonly COLOR_YELLOW="\033[0;33m" # 黄色 (Warn)
export readonly COLOR_BLUE="\033[0;34m"   # 蓝色 (Debug)
export readonly COLOR_PURPLE="\033[0;35m" # 紫色 (Summary 默认) - 注意：与 MAGENTA 默认值相同，可根据终端表现选择
export readonly COLOR_CYAN="\033[0;36m"   # 青色 (交错行/边框)
export readonly COLOR_WHITE="\033[0;37m"  # 白色 (新增，用于 Box Header Style 标题)
export readonly COLOR_BOLD="\033[1m"      # 粗体 (Bold) 属性
export readonly COLOR_RESET="\033[0m"     # 重置所有属性到默认值

# --- 背景色常量 (用于终端输出) ---
export readonly BG_BLACK="\033[40m"
export readonly BG_RED="\033[41m"
export readonly BG_GREEN="\033[42m"
export readonly BG_YELLOW="\033[43m"
export readonly BG_BLUE="\033[44m"
export readonly BG_MAGENTA="\033[45m"
export readonly BG_CYAN="\033[46m"
export readonly BG_WHITE="\033[47m" # 标准白色背景，在深色终端下可能显示为亮灰

# 亮色背景（更常用，效果通常更明显）
export readonly BG_LIGHT_BLACK="\033[100m" # 通常显示为深灰背景
export readonly BG_LIGHT_RED="\033[101m"
export readonly BG_LIGHT_GREEN="\033[102m"
export readonly BG_LIGHT_YELLOW="\033[103m"
export readonly BG_LIGHT_BLUE="\033[104m"
export readonly BG_LIGHT_MAGENTA="\033[105m"
export readonly BG_LIGHT_CYAN="\033[106m"
export readonly BG_LIGHT_WHITE="\033[107m" # 通常显示为亮白背景

# ==============================================================================
# 内部辅助函数 (以 "_" 开头命名，不对外暴露，主要供其他 utils.sh 函数调用)
# ------------------------------------------------------------------------------

# _get_original_user_and_home()
# 功能: 获取调用 sudo 的原始用户的用户名和其家目录路径。
# 说明: 在脚本以 sudo 权限运行时，识别出实际操作的用户。
#       由 environment_setup.sh 调用，直接将结果赋值给全局导出变量
#       ORIGINAL_USER 和 ORIGINAL_HOME。
# 依赖: SUDO_USER (环境变量), whoami, id, getent, grep (系统命令)。
# 返回: 无。成功获取则设置全局变量，失败则输出警告/错误日志。
_get_original_user_and_home() {
    # 优先使用 SUDO_USER (如果通过 sudo 调用)，否则使用当前执行脚本的用户 (通常是 root)。
    ORIGINAL_USER="${SUDO_USER:-$(whoami)}" 
    export ORIGINAL_USER

    if [ "$ORIGINAL_USER" == "root" ]; then
        ORIGINAL_HOME="/root" # root 用户的家目录固定为 /root
    else
        # 更安全地获取原始用户的家目录，优先使用 getent
        if id -u "$ORIGINAL_USER" &>/dev/null; then # 检查用户是否存在
            if command -v getent &>/dev/null; then
                ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
            else
                # 作为回退，直接从 /etc/passwd 解析 (不够健壮，但可在无 getent 时使用)
                ORIGINAL_HOME=$(grep "^$ORIGINAL_USER:" /etc/passwd | cut -d: -f6)
            fi

            if [[ -z "$ORIGINAL_HOME" ]]; then
                 log_warn "Could not determine home directory for '$ORIGINAL_USER' via getent/grep. Falling back to current \$HOME."
                 ORIGINAL_HOME="$HOME" # 回退到当前 SHELL 的 $HOME
            fi
        else
            log_error "Original user '$ORIGINAL_USER' not found. Falling back to current \$HOME."
            ORIGINAL_HOME="$HOME" # 回退到当前 SHELL 的 $HOME
        fi
    fi
    export ORIGINAL_HOME # 确保 ORIGINAL_HOME 立即导出
}

# _create_directory_if_not_exists()
# 功能: 辅助函数，用于创建目录（如果不存在）。
# 参数: $1 (dir_path) - 要创建的目录路径。
# 依赖: mkdir (系统命令)。
# 返回: 0 (成功，目录已存在或创建成功) 或 1 (失败，无法创建目录)。
_create_directory_if_not_exists() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        if mkdir -p "$dir_path"; then 
            log_info "Directory '$dir_path' created."
            return 0
        else
            log_error "Failed to create directory '$dir_path'. Permissions issue?"
            return 1
        fi
    fi
    return 0 # 目录已存在，也视为成功
}

# _check_dir_writable_by_user()
# 功能: 辅助函数，检查指定目录是否对指定用户可写。
# 参数: $1 (dir_path) - 要检查的目录路径。
#       $2 (user) - 要检查的用户。
# 依赖: sudo (如果用户不是当前用户), test (Bash 内置)。
# 返回: 0 (可写) 或 1 (不可写)。
_check_dir_writable_by_user() {
    local dir_path="$1"
    local user="$2"
    sudo -u "$user" test -w "$dir_path"
}

# _try_set_dir_acl()
# 功能: 辅助函数，尝试使用 setfacl 为目录设置用户写入权限。
# 依赖: setfacl (系统命令)。
# 参数: $1 (dir_path) - 目录路径。
#       $2 (user) - 要授权的用户。
# 返回: 0 (setfacl 成功) 或 1 (setfacl 失败或命令不可用)。
_try_set_dir_acl() {
    local dir_path="$1"
    local user="$2"
    if command -v setfacl &>/dev/null; then
        log_info "Attempting to use setfacl to grant write access to '$user' for '$dir_path'."
        # -m: modify ACL, -d: default ACL (for new files/dirs), u: user, rwx: read, write, execute
        if setfacl -m u:"$user":rwx -d -m u:"$user":rwx "$dir_path"; then
            log_info "setfacl successfully granted write access to '$user' for '$dir_path'."
            return 0
        else
            log_error "setfacl failed for '$dir_path'."
            return 1 # 表示 setfacl 失败
        fi
    else
        log_warn "setfacl command not found. Cannot use ACLs for '$dir_path'."
        return 1 # 表示 setfacl 不可用
    fi
}

# _try_chown_chmod_dir_group_write()
# 功能: 辅助函数，尝试使用 chown/chmod 为目录设置组写入权限，并改变所有者。
# 说明: 作为 setfacl 的回退方案。
# 依赖: id, chown, chmod (系统命令)。
# 参数: $1 (dir_path) - 目录路径。
#       $2 (user) - 用户 (用于 chown，更改为 root:$user_primary_group)。
# 返回: 0 (成功) 或 1 (失败)。
_try_chown_chmod_dir_group_write() {
    local dir_path="$1"
    local user="$2"
    local user_primary_group=$(id -gn "$user" 2>/dev/null)

    if [[ -z "$user_primary_group" ]]; then
        log_error "Could not determine primary group for user '$user'. Cannot set group permissions for '$dir_path'."
        return 1
    fi

    log_info "Attempting to use chown/chmod to grant group write permissions for '$dir_path'."
    # 更改目录的组所有者为 ORIGINAL_USER 的主组，并设置组写权限
    if chown "root:$user_primary_group" "$dir_path"; then
        if chmod g+w "$dir_path"; then
            log_info "Changed group ownership to '$user_primary_group' and granted group write permissions for '$dir_path'."
            return 0
        else
            log_error "Failed to set group write permissions for '$dir_path'."
            return 1
        fi
    else
        log_error "Failed to change group ownership of '$dir_path' to 'root:$user_primary_group'."
        return 1
    fi
}

# _ensure_log_dir_user_owned()
# 功能: 确保指定的日志目录存在，并设置适当的权限，使其可供 ORIGINAL_USER 写入。
# 说明: 封装了创建目录、检查可写、尝试 setfacl、回退到 chown/chmod 的完整逻辑。
#       由 initialize_logging_system 调用。
# 依赖: _create_directory_if_not_exists, _check_dir_writable_by_user,
#       _try_set_dir_acl, _try_chown_chmod_dir_group_write。
# 参数: $1 (dir_path) - 要检查/创建的日志目录的绝对路径（例如 CURRENT_DAY_LOG_DIR）。
#       $2 (user)    - ORIGINAL_USER (调用 sudo 的用户)。
# 返回: 0 (成功) 或 1 (失败)。
_ensure_log_dir_user_owned() {
    local dir_path="$1"
    local user="$2"
    
    log_info "Checking/creating log directory '$dir_path' for user '$user'..."

    # 1. 创建目录 (如果不存在) - 调用辅助函数 _create_directory_if_not_exists
    if ! _create_directory_if_not_exists "$dir_path"; then
        log_error "Failed to create log directory '$dir_path'. Cannot proceed with permission setup."
        return 1 # 目录创建失败是致命的
    fi

    # 2. 确保 ORIGINAL_USER 对目录有写入权限
    if ! _check_dir_writable_by_user "$dir_path" "$user"; then
        log_warn "Log directory '$dir_path' is not writable by user '$user'. Attempting to adjust permissions..."

        # 优先使用 setfacl 尝试调整权限
        if ! _try_set_dir_acl "$dir_path" "$user"; then
            # setfacl 失败或不可用，回退到 chown/chmod 方法
            if ! _try_chown_chmod_dir_group_write "$dir_path" "$user"; then
                log_error "Failed to set write permissions for '$dir_path' using chmod/chown."
                return 1 # 权限设置失败，视为致命
            fi
        fi

        # 再次检查是否可写。如果调整后仍不可写，则视为失败。
        if ! _check_dir_writable_by_user "$dir_path" "$user"; then
            log_error "After attempting adjustments, log directory '$dir_path' is still not writable by user '$user'. Logging to file may fail."
            return 1 # 最终检查失败，视为致命
        fi
    fi

    log_info "Log directory '$dir_path' is writable by '$user'."
    return 0 # 成功
}


# _create_and_secure_log_file()
# 功能: 辅助函数，封装单个日志文件的创建、权限和所有权设置。
# 依赖: touch, chmod, chown, id (系统命令)。
# 参数: $1 (file_path) - 要创建的日志文件的绝对路径。
#       $2 (user) - 日志文件的预期所有者用户。
# 返回: 0 (成功) 或 1 (失败)。
_create_and_secure_log_file() {
    local file_path="$1"
    local user="$2"

    # 尝试创建日志文件
    if ! touch "$file_path"; then 
        echo "${COLOR_RED}Error:${COLOR_RESET} Failed to create log file '$file_path' as root. Logging might fail." >&2
        return 1 # 文件创建失败是致命的
    fi
    log_info "Log file '$file_path' created."

    # 尝试设置文件权限
    if ! chmod 644 "$file_path"; then
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to set permissions 644 for '$file_path' as root." >&2
        return 1 # 权限设置失败，也视为致命
    fi
    log_debug "Permissions 644 set for '$file_path'."

    # 尝试更改文件所有权给原始用户
    if id -u "$user" &>/dev/null; then # 确保 ORIGINAL_USER 存在
        if ! chown "$user" "$file_path"; then
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to change ownership of '$file_path' to '$user'. File will be owned by root." >&2
            return 1 # 所有权更改失败，也视为致命
        fi
        log_debug "Ownership of '$file_path' changed to '$user'."
    else
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} User '$user' not found or invalid. Log file '$file_path' will remain owned by root." >&2
        # 这种情况通常是 _get_original_user_and_home 已经发出警告的情况，
        # 如果 ORIGINAL_USER 不存在，chown 本身就会失败，并被上面捕获。
        # 这里仅作为额外的防御性输出，不影响返回状态。
    fi
    return 0 # 成功
}

# _center_text()
# 功能: 辅助函数，用于将文本居中并用指定字符填充。
# 说明: 主要供 display_header_section 函数内部使用。
# 参数: $1 (text) - 要居中的文本。
#       $2 (total_width) - 总宽度。
#       $3 (fill_char) - 填充字符 (例如 " ")。
# 返回: 居中后的字符串。
_center_text() {
    local text="$1"
    local total_width="$2"
    local fill_char="$3"
    local text_len="${#text}"

    if (( text_len >= total_width )); then
        echo "$text" # 如果文本太长，直接返回文本
        return
    fi

    local padding_len=$(( total_width - text_len ))
    local left_padding=$(( padding_len / 2 ))
    local right_padding=$(( padding_len - left_padding ))

    printf "%*s%s%*s" "$left_padding" "" "$text" "$right_padding" "" | tr ' ' "$fill_char"
}

# _strip_ansi_colors()
# 功能: 辅助函数，从字符串中移除 ANSI 颜色转义码。
# 说明: 主要用于确保写入日志文件的字符串是纯文本，避免日志文件包含颜色码。
# 依赖: sed (系统命令)。
# 参数: $1 (text) - 包含 ANSI 颜色码的字符串。
# 返回: 移除颜色码后的纯文本字符串。
_strip_ansi_colors() {
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# _get_log_caller_info()
# 功能: 从 Bash 堆栈中解析出日志调用者的名称（函数名或脚本文件路径）。
# 说明: 遍历 FUNCNAME 和 BASH_SOURCE 数组，跳过内部日志/工具函数。
# 依赖: FUNCNAME (Bash 内置数组), BASH_SOURCE (Bash 内置数组), basename (系统命令)。
# 参数: $1 (current_level) - 当前日志级别，用于特殊处理 SUMMARY 级别 (跳过查找)。
# 返回: 字符串，表示调用者的名称。
_get_log_caller_info() {
    local current_level="$1"
    
    # 对于 SUMMARY 级别，在终端输出时无前缀，调用者信息仅用于文件日志。
    # 此时可以简化查找，直接使用最顶层脚本名作为调用者。
    if [[ "$current_level" == "SUMMARY" ]]; then
        echo "$(basename "${_caller_script_path:-${BASH_SOURCE[-1]}}")"
        return
    fi

    local calling_source_name="unknown"
    local stack_idx=0
    local found_source=false

    # 定义所有应被跳过的内部日志/工具函数名。
    # 这些函数在日志中不应被显示为调用者，因为它们是日志系统或通用辅助的一部分。
    # 此外，像菜单显示函数（如 show_main_menu）等，如果希望其日志源显示脚本名而非函数名，则在此处添加。
    local -a internal_utility_functions=(
        "_log_message_core"           # 核心日志处理函数自身
        "_format_log_strings"         # 新增：日志字符串格式化辅助函数
        "_write_log_output"           # 新增：日志输出辅助函数
        "log_info"                    # 日志级别封装函数
        "log_notice"
        "log_warn"
        "log_error"
        "log_debug"
        "log_summary"                 # SUMMARY 日志级别封装函数
        "display_header_section"      # 通用头部显示函数
        "handle_error"                # 错误处理函数
        "initialize_logging_system"   # 日志系统初始化函数
        # 重要的修正：所有以 "_" 开头的辅助函数都应添加到此列表
        "_get_original_user_and_home" 
        "_ensure_log_dir_user_owned"  
        "_create_directory_if_not_exists" 
        "_check_dir_writable_by_user"     
        "_try_set_dir_acl"              
        "_try_chown_chmod_dir_group_write" 
        "_create_and_secure_log_file"   
        "_center_text"                  
        "_strip_ansi_colors"            
        "_get_log_caller_info"        # 自身也需要加入，否则日志源会显示为 _get_log_caller_info
        "_validate_logging_prerequisites" # 日志初始化辅助
        "_get_current_day_log_dir"        # 日志初始化辅助
        "_confirm_action"             # 通用确认函数
        # 通用权限检查辅助函数
        "check_root_privileges"       
        # 菜单显示函数 (如果希望其日志源显示脚本名而非函数名，则在此处添加)
        "show_main_menu"              
        # "show_system_base_menu"     # 示例：系统基础配置菜单显示函数
        # "process_main_menu_choice"  # 示例：如果希望该函数内部日志显示脚本名而非函数名
    )

    # 从最内层函数 (_log_message_core) 开始向上遍历 FUNCNAME 数组，寻找真正的调用源。
    # FUNCNAME[0] 是当前函数，FUNCNAME[1] 是调用当前函数的函数，以此类推。
    # BASH_SOURCE[n] 对应 FUNCNAME[n] 所在的文件路径。
    for (( stack_idx=0; stack_idx < ${#FUNCNAME[@]}; stack_idx++ )); do
        local current_func_name="${FUNCNAME[stack_idx]:-}"
        local current_file_path="${BASH_SOURCE[stack_idx]:-}"

        local is_internal_func=false
        # 检查当前函数名是否在内部工具函数列表中
        for internal_func in "${internal_utility_functions[@]}"; do
            if [[ "$current_func_name" == "$internal_func" ]]; then
                is_internal_func=true
                break
            fi
        done

        # 如果是内部工具函数，则跳过并继续向上查找
        if "$is_internal_func"; then
            continue
        fi

        # 到达这里，说明找到第一个不是内部工具函数/日志包装器的函数/脚本。
        # 这就是我们希望显示为日志来源的“业务逻辑”调用者。
        # 优先使用函数名（如果存在且不是 shell 内部的伪函数，如 'source'）。
        if [[ -n "$current_func_name" && "$current_func_name" != "source" ]]; then
            # 排除 'main' 函数名如果它不具有特定业务意义（例如，脚本的顶层 main 函数）
            if [[ "$current_func_name" == "main" && -n "$current_file_path" ]]; then
                calling_source_name="${current_file_path#"$BASE_DIR/"}" # 使用相对于 BASE_DIR 的文件路径
            else
                calling_source_name="$current_func_name"
            fi
            found_source=true
            break # 找到源，退出循环
        # 否则，如果文件路径存在，使用相对于 BASE_DIR 的路径或文件名。
        elif [[ -n "$current_file_path" ]]; then
            # 尝试从 BASE_DIR 移除前缀，使路径更相对和简洁
            if [[ -n "${BASE_DIR:-}" && "$current_file_path" == "${BASE_DIR}"* ]]; then
                calling_source_name="${current_file_path#"$BASE_DIR/"}"
            else
                calling_source_name=$(basename "$current_file_path")
            fi
            found_source=true
            break # 找到源，退出循环
        fi
    done

    # 最终回退：如果循环结束仍未找到合适的源（理论上不应该发生，除非堆栈非常浅）。
    # 回退到顶部引导块传递的原始入口点脚本名，这是最可靠的通用回退。
    if [[ "$found_source" == "false" ]]; then
        calling_source_name=$(basename "${_caller_script_path:-${BASH_SOURCE[-1]}}")
    fi
    echo "$calling_source_name" # 返回调用者信息
}

# ==============================================================================
# 日志记录模块 (包含核心日志逻辑、初始化函数和对外暴露的封装函数)
# ------------------------------------------------------------------------------

# _format_log_strings()
# 功能: 内部辅助函数，负责根据日志级别和模式格式化日志消息，生成终端和文件输出字符串。
# 依赖: _get_log_caller_info(), _strip_ansi_colors()。
#       全局变量：LOG_COLOR_MODE, COLOR_X 等。
# 参数: $1 (level) - 日志级别 (例如 "INFO", "ERROR", "SUMMARY")。
#       $2 (message) - 原始日志消息。
#       $3 (optional_color_code) - 可选，用于 SUMMARY 级别的特定颜色代码。
# 返回: 将格式化后的终端字符串和文件字符串分别通过 echo 输出，由调用者捕获。
_format_log_strings() {
    local level="$1"
    local message="$2"
    local optional_color_code="$3" # Passed directly from log_summary

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local calling_source_name="$(_get_log_caller_info "$level")"

    local level_color="${COLOR_RESET}" # 默认颜色
    case "$level" in
        "INFO")    level_color="${COLOR_DARK_GRAY}" ;;
        "NOTICE")  level_color="${COLOR_GREEN}" ;; 
        "WARN")    level_color="${COLOR_YELLOW}" ;;
        "ERROR")   level_color="${COLOR_RED}" ;;
        "DEBUG")   level_color="${COLOR_BLUE}" ;;
        "SUMMARY") level_color="${optional_color_code:-$COLOR_PURPLE}" ;; # SUMMARY 可自定义颜色，否则默认紫色
        *)         level_color="${COLOR_RESET}" ;; # 未知级别，不着色
    esac

    local formatted_terminal_string=""
    local plain_log_prefix="[$timestamp] [$level] [$calling_source_name] "
    local formatted_file_string="$plain_log_prefix$(_strip_ansi_colors "$message")" # 文件日志总是纯文本且带完整前缀

    # 根据 LOG_COLOR_MODE 构建终端输出字符串
    if [[ "${LOG_COLOR_MODE:-full_line}" == "level_only" ]]; then
        # level_only 模式: 仅日志级别标签着色
        if [[ "$level" == "SUMMARY" ]]; then
            # SUMMARY 级别在终端没有标准前缀，整行着色（与 full_line 模式相同，因为它本身是特殊样式）
            formatted_terminal_string="${level_color}${message}${COLOR_RESET}"
        else
            # 其他级别：仅对 [LEVEL] 部分着色，其他部分保持默认终端颜色
            formatted_terminal_string="[$timestamp] [${level_color}${level}${COLOR_RESET}] [$calling_source_name] ${message}"
        fi
    else # full_line 模式 (默认) 或未设置
        # full_line 模式: 整行日志都显示颜色
        if [[ "$level" == "SUMMARY" ]]; then
            # SUMMARY 级别在终端没有标准前缀，整行着色
            formatted_terminal_string="${level_color}${message}${COLOR_RESET}"
        else
            # 其他级别：整行日志都使用 level_color
            formatted_terminal_string="${level_color}${plain_log_prefix}${message}${COLOR_RESET}"
        fi
    fi

    # Echo the two formatted strings, each on a new line.
    # The caller will capture them using `read -r -d '' -a`.
    echo "$formatted_terminal_string"
    echo "$formatted_file_string"
}

# _write_log_output()
# 功能: 内部辅助函数，负责将格式化后的日志字符串输出到终端和文件。
# 依赖: CURRENT_SCRIPT_LOG_FILE, ENABLE_COLORS, COLOR_YELLOW, COLOR_RESET。
# 参数: $1 (level) - 日志级别 (用于判断是否输出到 stderr)。
#       $2 (terminal_string) - 已格式化并带有颜色的终端输出字符串。
#       $3 (file_string) - 已格式化且纯文本的文件输出字符串。
# 返回: 无。直接将日志信息输出到终端和文件。
_write_log_output() {
    local level="$1"
    local terminal_string="$2"
    local file_string="$3"

    # 1. 终端输出
    # ENABLE_COLORS 变量在 main_config.sh 中定义，并由 environment_setup.sh 加载。
    local output_target
    if [[ "$level" == "WARN" || "$level" == "ERROR" ]]; then
        output_target=">&2" # 警告和错误信息输出到标准错误
    else
        output_target="" # 其他信息输出到标准输出
    fi

    if [[ "${ENABLE_COLORS:-true}" == "true" ]]; then
        # 使用 eval 确保 `>&2` 正确应用
        eval "echo -e \"\$terminal_string\" $output_target"
    else
        # 如果禁用颜色，则移除所有 ANSI 颜色码再输出
        eval "echo \"\$(_strip_ansi_colors \"\$terminal_string\")\" $output_target"
    fi
    
    # 2. 文件写入：纯文本日志信息。
    # `_strip_ansi_colors` 已在 _format_log_strings 中应用到 file_string。
    # 如果写入失败，会输出警告到标准错误。
    if [[ -n "${CURRENT_SCRIPT_LOG_FILE:-}" ]]; then
        echo "$file_string" >> "${CURRENT_SCRIPT_LOG_FILE}" || \
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to write log to file '${CURRENT_SCRIPT_LOG_FILE}'. Check permissions." >&2
    fi
}


# _log_message_core()
# 功能: 核心日志记录逻辑的协调器。
# 说明: 负责调用格式化函数获取日志字符串，然后调用写入函数进行输出。
# 依赖: _format_log_strings(), _write_log_output()。
# 参数: $1 (level) - 日志级别。
#       $2 (message) - 要记录的日志消息。
#       $3 (optional_color_code) - 可选，用于 SUMMARY 级别的特定颜色代码。
# 返回: 无。
_log_message_core() {
    local level="$1"
    local message="$2"
    local optional_color_code="${3:-}"

    # 调用 _format_log_strings 辅助函数来获取终端和文件日志字符串。
    # `IFS=$'\n' read -r -d '' -a` 是一种健壮地读取多行输出到数组的方法。
    local formatted_strings_output
    IFS=$'\n' read -r -d '' -a formatted_strings_output < <(_format_log_strings "$level" "$message" "$optional_color_code" && printf '\0')

    local terminal_output="${formatted_strings_output[0]}"
    local file_output="${formatted_strings_output[1]}"

    # 调用 _write_log_output 辅助函数来处理实际的输出。
    _write_log_output "$level" "$terminal_output" "$file_output"
}

# initialize_logging_system()
# 功能: 初始化整个日志系统。
# 说明: 负责设置日志根目录、当前日期日志目录、文件路径、权限，并激活日志文件写入。
#       由 environment_setup.sh 调用一次，以确保日志系统在脚本早期可用。
# 依赖: 全局变量 BASE_DIR, LOG_ROOT, ORIGINAL_USER, ORIGINAL_HOME。
#       内部辅助函数：_validate_logging_prerequisites(), _get_current_day_log_dir(),
#       _ensure_log_dir_user_owned(), _create_and_secure_log_file()。
# 参数: $1 (caller_script_path) - 原始入口点脚本的完整路径。
# 返回: 0 (成功) 或 1 (失败)。
initialize_logging_system() {
    local caller_script_path="$1"
    local script_name=$(basename "$caller_script_path")
    log_info "------ 开始为 '$script_name' 初始化日志系统 ------"

    # 1. 验证必要全局变量是否已设置 - 调用辅助函数 _validate_logging_prerequisites
    # 这些变量应已由 environment_setup.sh 在调用此函数前设置并导出。
    log_debug "【Step 1/4】: 验证日志环境参数 (BASE_DIR, LOG_ROOT, ORIGINAL_USER, ORIGINAL_HOME)..."
    if ! _validate_logging_prerequisites; then
        # _validate_logging_prerequisites 内部会 echo 错误并 exit。
        return 1 # 理论上不会执行到，但作为安全措施。
    fi
    log_info "【Step 1/4】: 日志环境参数验证成功."

    # 2. 定义当前运行的日志日期目录 (在此函数内部定义并导出) - 调用辅助函数 _get_current_day_log_dir
    # 格式为 YYYY-MM-DD，用于组织日志文件。
    log_debug "【Step 2/4】: 创建当前日志日期目录 (YYYY-MM-DD)..."
    if ! _get_current_day_log_dir; then
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.initialize_logging_system] Could not determine current day's log directory. Logging cannot proceed." >&2
        return 1 # 获取目录失败，返回 1
    fi
    # log_debug "Current day's log directory set to: '$CURRENT_DAY_LOG_DIR'."
    log_info "【Step 2/4】: 成功创建日志目录: '$CURRENT_DAY_LOG_DIR'."

    # 3. 确保日志根目录（包括日期目录）存在并对 ORIGINAL_USER 有写入权限
    log_debug "Ensuring log directory '$CURRENT_DAY_LOG_DIR' is prepared for user '$ORIGINAL_USER'..."
    log_debug "【Step 3/4】: 检查用户： '$ORIGINAL_USER' 对目录： '$CURRENT_DAY_LOG_DIR'  是否有写权限..."
    if ! _ensure_log_dir_user_owned "$CURRENT_DAY_LOG_DIR" "$ORIGINAL_USER"; then
        log_error "Fatal: Could not prepare log directory '$CURRENT_DAY_LOG_DIR' for '$ORIGINAL_USER'. Logging will not function correctly."
        return 1 # 目录权限失败，返回 1
    fi
    # log_info "Log directory '$CURRENT_DAY_LOG_DIR' confirmed ready."
    log_info "【Step 3/4】: 确定了目录: '$CURRENT_DAY_LOG_DIR' 已经存在，并且用户： '$ORIGINAL_USER' 拥有该目录的读写权限."

    # 4. 为当前脚本创建具体的日志文件 - 调用辅助函数 _create_and_secure_log_file
    # log_debug "Initializing logging system for current script: '$caller_script_path'..."
    log_debug "【Step 4/4】: 为当前脚本： '$script_name' 创建具体的日志文件..."
    # 构建当前脚本的日志文件路径，包含脚本名称和精确到秒的时间戳。
    CURRENT_SCRIPT_LOG_FILE="$CURRENT_DAY_LOG_DIR/${script_name%.*}-$(date +%Y%m%d_%H%M%S).log"
    export CURRENT_SCRIPT_LOG_FILE

    # 注意：这里使用 echo 输出到 stderr，而不是 log_info，
    # 因为 log_info 内部依赖 CURRENT_SCRIPT_LOG_FILE 已经完全设置好，
    # 而这个函数正在设置它，避免死循环。
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} Initializing logging for '$script_name'. Log file will be: '$CURRENT_SCRIPT_LOG_FILE'" >&2
    
    if ! _create_and_secure_log_file "$CURRENT_SCRIPT_LOG_FILE" "$ORIGINAL_USER"; then
        log_error "Failed to create and secure log file '$CURRENT_SCRIPT_LOG_FILE'. Logging might fail."
        return 1 # 文件创建或权限设置失败，返回 1
    fi
    log_info "【Step 4/4】: 成功创建日志文件: '$CURRENT_SCRIPT_LOG_FILE'."
    log_info "------ 成功为 '$script_name' 初始化日志系统，日志文件为： '$CURRENT_SCRIPT_LOG_FILE'. ------ "
    return 0 # 成功
}

# _validate_logging_prerequisites()
# 功能: 辅助函数，验证 initialize_logging_system 所需的全局变量是否已设置。
# 说明: 在日志系统初始化时执行，确保所有依赖的全局变量可用。如果缺失，直接输出错误并退出。
# 依赖: 全局变量 BASE_DIR, LOG_ROOT, ORIGINAL_USER, ORIGINAL_HOME。
# 返回: 0 (所有变量已设置) 或 1 (缺失变量，直接退出)。
_validate_logging_prerequisites() {
    if [ -z "${BASE_DIR+set}" ] || [ -z "${LOG_ROOT+set}" ] || \
       [ -z "${ORIGINAL_USER+set}" ] || [ -z "${ORIGINAL_HOME+set}" ]; then
        # 此时 log_error 无法完全记录到文件，直接 echo 到 stderr。
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.initialize_logging_system] Logging environment (BASE_DIR, LOG_ROOT, ORIGINAL_USER, ORIGINAL_HOME) not fully set. Exiting." >&2
        exit 1
    fi
    return 0
}

# _get_current_day_log_dir()
# 功能: 辅助函数，计算并导出当前日期的日志目录路径。
# 依赖: LOG_ROOT (全局变量), date (系统命令)。
# 返回: 0 (成功) 或 1 (如果 LOG_ROOT 未设置则失败，直接退出)。
_get_current_day_log_dir() {
    if [ -z "${LOG_ROOT+set}" ] || [ -z "$LOG_ROOT" ]; then
        # 此时 log_error 可能还无法完全记录到文件，直接 echo。
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils._get_current_day_log_dir] LOG_ROOT is not set. Cannot determine daily log directory. Exiting." >&2
        return 1
    fi
    export CURRENT_DAY_LOG_DIR="${LOG_ROOT}/$(date +%Y-%m-%d)"
    return 0
}

# --- 对外暴露的日志级别封装函数 ---
# 这些函数是外部脚本与日志系统交互的主要接口，调用 _log_message_core 进行实际处理。
# 参数: $1 (message) - 要记录的日志消息。
#       $2 (optional_color_code) - 仅 log_summary 接受，用于指定颜色。
log_info() { _log_message_core "INFO" "$1"; }
log_notice() { _log_message_core "NOTICE" "$1"; }
log_warn() { _log_message_core "WARN" "$1"; } # 输出到 stderr 已经在 _write_log_output 中处理
log_error() { _log_message_core "ERROR" "$1"; } # 输出到 stderr 已经在 _write_log_output 中处理
log_debug() {
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        _log_message_core "DEBUG" "$1"
    fi
}
log_summary() { _log_message_core "SUMMARY" "$1" "${2:-}"; }

# ==============================================================================
# 通用工具函数 (对外暴露)
# ------------------------------------------------------------------------------

# check_root_privileges()
# 功能: 检查当前脚本是否以 root 权限运行。
# 说明: 此函数只进行检查并返回状态码，不直接输出错误或退出。
#       由调用者处理其返回值。早期的强制性 Root 检查在 environment_setup.sh 中。
# 返回: 0 (成功) 表示是 root，1 (失败) 表示不是 root。
check_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return 1 # 非 root 用户
    else
        return 0 # 是 root 用户
    fi
}

# display_header_section()
# 功能: 在终端和日志中打印一个格式化的标题或部分分隔符。
# 说明: 其日志源通常希望显示调用脚本名而非函数名，
#       故其函数名已被添加到 _log_message_core 的内部工具函数列表中。
#       此函数通过调用 log_summary 来实现多色 SUMMARY 级别输出。
# 依赖: _center_text() (内部辅助函数), log_summary()。
# 参数: $1 (title) - 要显示的标题文本。
#       $2 (style) - 可选，标题样式 ("default", "box", "decorated")。
#       $3 (width) - 可选，标题总宽度 (默认为 60)。
#       $4 (border_color) - 可选，边框颜色 (例如 COLOR_CYAN)。
#       $5 (title_color) - 可选，标题文字颜色 (例如 COLOR_YELLOW)。
# 返回: 无。直接输出到终端和日志。
display_header_section() {
    local title="$1"
    local style="${2:-default}" # 默认为 default 样式
    local total_width="${3:-60}" # 默认总宽度 60
    local border_color="${4:-${COLOR_CYAN}}" # 默认为青色边框
    local title_color="${5:-${COLOR_BOLD}${COLOR_YELLOW}}" # 默认为粗体黄色标题

    # 确保宽度至少能容纳标题和一些边距
    if (( total_width < ${#title} + 6 )); then
        total_width=$(( ${#title} + 6 ))
    fi

    local top_line_content=""
    local mid_line_content=""
    local bottom_line_content=""

    # 纯文本标题，用于居中计算和文件日志 (不包含颜色码)
    local plain_title="${title}" 

    case "$style" in
        "box")
            local border_char="-"
            local corner_char="+"
            
            top_line_content="${corner_char}$(printf '%*s' "$((total_width - 2))" '' | tr ' ' "${border_char}")${corner_char}"
            # 在居中后的纯文本标题内容上应用颜色和粗体，然后再传递给 log_summary
            mid_line_content="${border_char} $(_center_text "$plain_title" "$((total_width - 4))" " ") ${border_char}"
            # 使用 sed 替换的方式将纯文本标题替换为带颜色的标题。
            # sed 's/[][\.\*^$]/\\&/g' 用于转义正则中的特殊字符，避免替换错误。
            mid_line_content="${mid_line_content/$(echo "$plain_title" | sed 's/[][\.\*^$]/\\&/g')/${title_color}${plain_title}${COLOR_RESET}}"
            
            bottom_line_content="${corner_char}$(printf '%*s' "$((total_width - 2))" '' | tr ' ' "${border_char}")${corner_char}"
            
            # 使用 log_summary 打印，并为框线行指定颜色
            if [[ -n "$top_line_content" ]]; then log_summary "$top_line_content" "$border_color"; fi
            if [[ -n "$mid_line_content" ]]; then log_summary "$mid_line_content" "$border_color"; fi # 标题行也用框线颜色作背景
            if [[ -n "$bottom_line_content" ]]; then log_summary "$bottom_line_content" "$border_color"; fi
            ;;
        "decorated")
            local decorator_char="#"
            local fill_char="="
            
            local available_fill=$(( (total_width - ${#plain_title} - 4) / 2 )) 
            if (( available_fill < 0 )); then available_fill=0; fi 

            top_line_content="${decorator_char}$(printf '%*s' "$available_fill" '' | tr ' ' "${fill_char}") ${plain_title} $(printf '%*s' "$available_fill" '' | tr ' ' "${fill_char}")${decorator_char}"
            top_line_content="$(_center_text "$top_line_content" "$total_width" " ")" # 居中
            
            # 替换中间的纯文本标题为带颜色和粗体的标题
            top_line_content="${top_line_content/$(echo "$plain_title" | sed 's/[][\.\*^$]/\\&/g')/${title_color}${plain_title}${COLOR_RESET}}"
            log_summary "$top_line_content" "$border_color"; # 整个装饰行使用 border_color

            mid_line_content="" 
            bottom_line_content="" 
            ;;
        "default"|*)
            local default_char="="
            local default_arrow=">>>"
            
            local fill_len=$(( total_width - ${#default_arrow} - ${#plain_title} - 3 ))
            if (( fill_len < 0 )); then fill_len=0; fi

            top_line_content="$(printf '%*s' "$total_width" '' | tr ' ' "${default_char}")"
            mid_line_content="${default_arrow} ${plain_title} $(printf '%*s' "$fill_len" '' | tr ' ' "${default_char}")"
            bottom_line_content="$top_line_content"

            # 替换中间的纯文本标题为带颜色和粗体的标题
            mid_line_content="${mid_line_content/$(echo "$plain_title" | sed 's/[][\.\*^$]/\\&/g')/${title_color}${plain_title}${COLOR_RESET}}"
            
            if [[ -n "$top_line_content" ]]; then log_summary "$top_line_content" "$border_color"; fi
            if [[ -n "$mid_line_content" ]]; then log_summary "$mid_line_content" "$border_color"; fi
            if [[ -n "$bottom_line_content" ]]; then log_summary "$bottom_line_content" "$border_color"; fi
            ;;
    esac
}

# handle_error()
# 功能: 统一的错误处理函数，记录错误并退出脚本。
# 说明: 通常用于致命错误，导致脚本无法继续执行。
#       其函数名已被添加到 _log_message_core 的内部工具函数列表中。
# 参数: $1 (message) - 错误消息。
#       $2 (exit_code) - 可选，自定义退出码 (默认为 1)。
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    log_error "Script execution terminated due to previous error."
    exit "$exit_code"
}
# _confirm_action()
# 功能: 显示一个带颜色的确认提示，并等待用户输入 (y/N)。
# 参数: $1 (prompt_text) - 提示用户的文本。
#       $2 (default_yn) - 默认响应 ('y' 或 'n'，不区分大小写)。
#       $3 (color_code) - 提示文本的颜色代码 (例如 ${COLOR_YELLOW}, ${COLOR_RED})。
# 返回: 0 (用户输入 Y/y), 1 (用户输入 N/n 或直接回车)。
_confirm_action() {
    local prompt_text="$1"
    local default_yn="${2:-n}" # Default to 'n' for safety if not provided
    local color_code="${3:-${COLOR_YELLOW}}" # Default to yellow if not provided

    local response
    read -rp "$(echo -e "${color_code}${prompt_text} (y/N): ${COLOR_RESET}")" response
    response="${response:-$default_yn}" # If empty, use default

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}