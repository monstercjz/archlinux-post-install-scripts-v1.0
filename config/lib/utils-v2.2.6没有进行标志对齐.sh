#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/utils.sh
# 版本: 2.2.6 (修复多处问题，包括 _center_text 语法和 prefix_only_color 逻辑)
# 日期: 2025-06-08
# 描述: 核心通用函数库。
#       提供项目运行所需的基础功能，包括日志记录、用户上下文识别、权限检查辅助、
#       文件操作等。此文件不直接进行环境初始化或Root权限检查；其函数由
#       'environment_setup.sh' 调用以完成环境引导。
# ------------------------------------------------------------------------------
# 核心功能：
# - 统一的日志系统：支持INFO/WARN/ERROR/DEBUG/SUMMARY/FATAL/SUCCESS级别，
#   可配置的日志级别过滤（仅对终端输出有效），多种终端彩色输出模式，
#   **所有级别的日志均写入纯文本日志文件**，并由原始用户拥有。
# - 支持自定义日志消息的前缀格式（完整、只显示级别、无前缀、时间戳+级别）。
# - 日志系统初始化 (initialize_logging_system) - 职责更单一。
# - 用户上下文：识别调用 sudo 的原始用户 (ORIGINAL_USER) 及期家目录 (ORIGINAL_HOME)。
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
# v2.1.0 - 2025-06-08 - 日志系统核心重构：
#                        1. 引入 `CURRENT_LOG_LEVEL` (从 `main_config.sh` 获取) 控制日志输出级别。
#                        2. 引入 `DISPLAY_MODE` (从 `main_config.sh` 获取) 控制终端日志的默认显示模式。
#                        3. `_log_message_core` 增加可选参数，支持覆盖默认的显示模式和消息内容颜色。
#                        4. 新增 `_get_log_level_number` 辅助函数，用于日志级别与数值的映射。
#                        5. `log_debug`, `log_info`, `log_notice`, `log_warn`, `log_error`, `log_summary`
#                           等封装函数更新，以支持新的可选参数。
# v2.1.1 - 2025-06-08 - 日志系统优化：
#                        1. 所有日志消息无论级别高低，都会写入日志文件。`CURRENT_LOG_LEVEL` 仅用于控制终端显示。
#                        2. 为 `_log_message_core` 中的 `all_color` 模式，为每种日志级别（INFO, DEBUG, NOTICE等）
#                           预设了更具体的消息内容颜色，增强视觉区分度。
# v2.2.0 - 2025-06-08 - 日志系统再次核心重构：
#                        1. 引入 `DEFAULT_MESSAGE_FORMAT_MODE` 和 `optional_message_format_mode_override` 参数，
#                           允许更细粒度地控制终端日志的前缀格式（时间戳、级别、调用者）。
#                        2. 新增 `SUCCESS` 日志级别，并为其提供默认的颜色和前缀格式（`level_only`），
#                           满足“只显示标志，不需要显示来源”的需求。
#                        3. 调整 `_log_message_core` 的参数顺序，以适应新的可选参数。
#                        4. 更新所有对外暴露的 `log_*` 封装函数，使其能正确传递新的参数。
# v2.2.1 - 2025-06-08 - 日志系统参数统一化：
#                        1. 统一所有 `log_*` 封装函数的外部参数顺序，使其与 `_log_message_core` 的参数顺序保持一致。
#                           即：`(message, optional_display_mode_override, optional_message_format_mode_override, optional_message_content_color)`。
#                        2. 相应地调整了 `log_summary` 和 `display_header_section` 中对参数的传递方式。
# v2.2.2 - 2025-06-08 - 日志系统最终统一化和逻辑修正：
#                        1. 移除了 `_log_message_core` 内部对 `SUMMARY` 级别前缀格式的特殊处理，
#                           现在其前缀格式完全由 `final_message_format_mode` 参数控制。
#                        2. 更新 `log_summary` 函数的调用，确保它强制性地传递 `"all_color"` 和 `"no_prefix"`
#                           作为其默认的显示模式和消息格式模式，从而实现其固有的无前缀全彩显示特性。
#                        3. 确保 `display_header_section` 调用 `log_summary` 时，保持正确的参数传递。
# v2.2.3 - 2025-06-08 - 新增日志消息格式模式 "timestamp_level"，允许只显示时间戳和级别。
# v2.2.4 - 2025-06-08 - 引入模式解析辅助函数 `_get_display_mode_name` 和 `_get_format_mode_name`，
#                        使得 `_log_message_core` 及所有 `log_*` 封装函数支持数字代号输入模式。
#                        更新 `_log_message_core` 内部逻辑以使用这些解析后的规范模式名称。
#                        修正 `prefix_only_color` 模式下时间戳和调用者不应着色的问题。
# v2.2.5 - 2025-06-08 - 修复 `_center_text` 函数中的 `if` 语句块语法错误，将 `}` 改为 `fi`。
#                        此错误导致脚本加载时出现 "未预期的记号 "}" 附近有语法错误" 的致命问题。
# v2.2.6 - 2025-06-08 - **修复 `_get_original_user_and_home` 函数中 `ORIGEN_USER` 拼写错误为 `ORIGINAL_USER`。**
#                        **进一步完善 `_log_message_core` 中 `prefix_only_color` 和 `all_color` 模式下**
#                        **对时间戳、级别、调用者和消息内容颜色处理的精确性，确保只有预期部分被着色，**
#                        **且颜色重置正确，避免颜色“溢出”。**
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
# (此变量不会被导出，但其值在当前 shell 进程中可用，通过函数参数传递)

# --- 颜色常量 (用于终端输出) ---
# 这些变量在 utils.sh 首次被 source 时初始化，并被 export readonly 到环境中。
# 确保所有子进程都能继承并使用这些颜色代码。

export readonly COLOR_DARK_GRAY='\033[1;30m' # 暗灰色 (info)
export readonly COLOR_GREEN="\033[0;32m"  # 绿色 (notice/success)
export readonly COLOR_RED="\033[0;31m"    # 红色 (Error/Fatal)
export readonly COLOR_YELLOW="\033[0;33m" # 黄色 (Warn)
export readonly COLOR_BLUE="\033[0;34m"   # 蓝色 (Debug)
export readonly COLOR_PURPLE="\033[0;35m" # 紫色 (Summary 默认)
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

    if [ "$ORIGINAL_USER" == "root" ]; then # 修正：将 ORIGEN_USER 修正为 ORIGINAL_USER
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
        log_error "Failed to create log directory '$dir_path'. Permissions issue?"
        return 1
    fi

    # 2. 确保 ORIGINAL_USER 对目录有写入权限
    if ! _check_dir_writable_by_user "$dir_path" "$user"; then
        log_warn "Log directory '$dir_path' is not writable by user '$user'. Attempting to adjust permissions..."

        # 优先使用 setfacl 尝试调整权限
        if ! _try_set_dir_acl "$dir_path" "$user"; then
            # setfacl 失败或不可用，回退到 chown/chmod 方法
            if ! _try_chown_chmod_dir_group_write "$dir_path" "$user"; then
                log_error "Failed to set write permissions for '$dir_path' using chmod/chown."
                return 1
            fi
        fi

        # 再次检查是否可写。如果调整后仍不可写，则视为失败。
        if ! _check_dir_writable_by_user "$dir_path" "$user"; then
            log_error "After attempting adjustments, log directory '$dir_path' is still not writable by user '$user'. Logging to file may fail."
            return 1
        fi
    fi

    log_info "Log directory '$dir_path' is writable by '$user'."
    return 0
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
        return 1
    fi
    log_info "Log file '$file_path' created."

    # 尝试设置文件权限
    if ! chmod 644 "$file_path"; then
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to set permissions 644 for '$file_path' as root." >&2
        return 1
    fi
    log_debug "Permissions 644 set for '$file_path'."

    # 尝试更改文件所有权给原始用户
    if id -u "$user" &>/dev/null; then # 确保 ORIGINAL_USER 存在
        if ! chown "$user" "$file_path"; then
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to change ownership of '$file_path' to '$user'. File will be owned by root." >&2
            return 1
        fi
        log_debug "Ownership of '$file_path' changed to '$user'."
    else
        echo "${COLOR_YELLOW}Warning:${COLOR_RESET} User '$user' not found or invalid. Log file '$file_path' will remain owned by root." >&2
        # 这种情况通常是 _get_original_user_and_home 已经发出警告的情况，
        # 如果 ORIGINAL_USER 不存在，chown 本身就会失败，并被上面捕获。
        # 这里仅作为额外的防御性输出，不影响返回状态。
    fi
    return 0
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
    fi # <--- 修正：确保这里是 'fi' 而不是 '}'

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
        "log_info"                    # 日志级别封装函数
        "log_notice"
        "log_warn"
        "log_error"
        "log_debug"
        "log_summary"                 # SUMMARY 日志级别封装函数
        "log_fatal"                   # FATAL 日志级别封装函数
        "log_success"                 # SUCCESS 日志级别封装函数
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
        "_get_log_level_number"           # 日志级别转换辅助 (新增)
        "_get_display_mode_name"          # 显示模式名称转换辅助 (新增)
        "_get_format_mode_name"           # 格式模式名称转换辅助 (新增)
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

# _get_log_level_number()
# 功能: 将日志级别名称转换为数值，用于比较和过滤。
# 参数: $1 (level_name) - 日志级别名称 (例如 "INFO", "WARN")。
# 返回: 对应的数值。如果未知，返回 0 (最低优先级)。
_get_log_level_number() {
    local level_name="$1"
    case "${level_name^^}" in # Convert to uppercase for robust comparison
        "DEBUG")   echo 10 ;;
        "INFO")    echo 20 ;;
        "NOTICE")  echo 25 ;; # 新增 NOTICE 级别，介于 INFO 和 SUCCESS 之间
        "SUCCESS") echo 30 ;; # 新增 SUCCESS 级别，优先级略高于 INFO/NOTICE
        "WARN")    echo 40 ;;
        "ERROR")   echo 50 ;;
        "FATAL")   echo 60 ;; # FATAL 级别，优先级最高
        "SUMMARY") echo 70 ;; # SUMMARY 级别通常独立于过滤，但在此也赋予高优先级
        *)         echo 0 ;;  # 默认最低优先级，例如对于未知级别
    esac
}

# _get_display_mode_name()
# 功能: 将终端显示模式的数字代号或字符串名称转换为规范的字符串名称。
# 参数: $1 (mode_input) - 模式输入（可以是数字 "1", "2", "3" 或字符串 "no_color", "prefix_only_color", "all_color"）。
# 返回: 规范的字符串模式名称。如果输入无效，则返回全局默认值 DISPLAY_MODE。
_get_display_mode_name() {
    local mode_input="$1"
    case "${mode_input}" in
        "1" | "no_color") echo "no_color" ;;
        "2" | "prefix_only_color") echo "prefix_only_color" ;;
        "3" | "all_color") echo "all_color" ;;
        # 如果是空值或者未知值，回退到全局默认 DISPLAY_MODE
        "") echo "$DISPLAY_MODE" ;;
        *) echo "$DISPLAY_MODE" ;; # 对未识别的字符串也回退到默认
    esac
}

# _get_format_mode_name()
# 功能: 将消息格式模式的数字代号或字符串名称转换为规范的字符串名称。
# 参数: $1 (mode_input) - 模式输入（可以是数字 "1", "2", "3", "4" 或字符串 "full", "level_only", "no_prefix", "timestamp_level"）。
# 返回: 规范的字符串模式名称。如果输入无效，则返回全局默认值 DEFAULT_MESSAGE_FORMAT_MODE。
_get_format_mode_name() {
    local mode_input="$1"
    case "${mode_input}" in
        "1" | "full") echo "full" ;;
        "2" | "level_only") echo "level_only" ;;
        "3" | "no_prefix") echo "no_prefix" ;;
        "4" | "timestamp_level") echo "timestamp_level" ;;
        # 如果是空值或者未知值，回退到全局默认 DEFAULT_MESSAGE_FORMAT_MODE
        "") echo "$DEFAULT_MESSAGE_FORMAT_MODE" ;;
        *) echo "$DEFAULT_MESSAGE_FORMAT_MODE" ;; # 对未识别的字符串也回退到默认
    esac
}

# ==============================================================================
# 日志记录模块 (包含核心日志逻辑、初始化函数和对外暴露的封装函数)
# ------------------------------------------------------------------------------

# _log_message_core()
# 功能: 核心日志记录逻辑，负责格式化日志信息并输出到终端和文件。
# 依赖: _get_log_caller_info(), _strip_ansi_colors(), _get_log_level_number() (内部辅助函数)。
#       全局变量：COLOR_X (颜色常量), ENABLE_COLORS, CURRENT_LOG_LEVEL, DISPLAY_MODE, DEFAULT_MESSAGE_FORMAT_MODE, CURRENT_SCRIPT_LOG_FILE。
# 参数: $1 (level) - 日志级别 (例如 "INFO", "ERROR", "SUMMARY", "FATAL", "SUCCESS")。
#       $2 (message) - 要记录的日志消息。
#       $3 (optional_display_mode_input) - 可选，覆盖全局 DISPLAY_MODE 的终端显示模式。
#                                             可选值: "no_color" (1), "prefix_only_color" (2), "all_color" (3)。
#       $4 (optional_message_format_mode_input) - 可选，覆盖全局 DEFAULT_MESSAGE_FORMAT_MODE 的消息前缀格式。
#                                                    可选值: "full" (1), "level_only" (2), "no_prefix" (3), "timestamp_level" (4)。
#       $5 (optional_message_content_color) - 可选，仅在 "all_color" 模式下生效，
#                                            指定消息内容本身的颜色。
# 返回: 无。直接将日志信息输出到终端和文件。
_log_message_core() {
    local level="$1"
    local message="$2"
    local optional_display_mode_input="${3:-}"          # 终端显示模式输入
    local optional_message_format_mode_input="${4:-}" # 消息前缀格式输入
    local optional_message_content_color="${5:-}"          # 消息内容颜色覆盖

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # 调用 _get_log_caller_info 来获取日志调用者信息，用于文件日志和带前缀的终端输出
    local calling_source_name="$(_get_log_caller_info "$level")"

    # 1. 文件写入：纯文本日志信息 (始终包含完整前缀，且不带颜色码)
    # `_strip_ansi_colors` 返回一个字符串，不需要外部 echo -e。
    # 如果写入失败，会输出警告到标准错误。
    if [[ -n "${CURRENT_SCRIPT_LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] [$calling_source_name] $(_strip_ansi_colors "$message")" >> "${CURRENT_SCRIPT_LOG_FILE}" || \
            echo "${COLOR_YELLOW}Warning:${COLOR_RESET} Failed to write log to file '${CURRENT_SCRIPT_LOG_FILE}'. Check permissions." >&2
    fi

    # 2. 日志级别过滤 (仅对终端输出有效)
    local level_num=$(_get_log_level_number "$level")
    local current_log_level_num=$(_get_log_level_number "$CURRENT_LOG_LEVEL")
    if (( level_num < current_log_level_num )); then
        return 0 # 级别低于当前设置的最低输出级别，终端不显示
    fi

    # 3. 确定终端颜色和显示模式
    local prefix_color_code="${COLOR_RESET}" # 前缀部分的颜色 (如 [INFO])
    local default_message_color_code="${COLOR_RESET}" # 消息内容部分的默认颜色

    case "$level" in
        "INFO")    prefix_color_code="${COLOR_DARK_GRAY}"; default_message_color_code="${COLOR_WHITE}" ;;
        "NOTICE")  prefix_color_code="${COLOR_GREEN}"; default_message_color_code="${COLOR_GREEN}" ;;
        "SUCCESS") prefix_color_code="${COLOR_BOLD}${COLOR_GREEN}"; default_message_color_code="${COLOR_GREEN}" ;; # 成功信息，加粗绿色
        "WARN")    prefix_color_code="${COLOR_YELLOW}"; default_message_color_code="${COLOR_YELLOW}" ;;
        "ERROR")   prefix_color_code="${COLOR_RED}"; default_message_color_code="${COLOR_RED}" ;;
        "FATAL")   prefix_color_code="${BG_RED}${COLOR_WHITE}"; default_message_color_code="${BG_RED}${COLOR_WHITE}" ;;
        "DEBUG")   prefix_color_code="${COLOR_BLUE}"; default_message_color_code="${COLOR_BLUE}" ;;
        "SUMMARY") 
            # 对于 SUMMARY，默认前景色就是其整体颜色，因此 optional_message_content_color 优先
            prefix_color_code="${optional_message_content_color:-$COLOR_PURPLE}" 
            default_message_color_code="${optional_message_content_color:-$COLOR_PURPLE}"
            ;;
        *)         prefix_color_code="${COLOR_RESET}"; default_message_color_code="${COLOR_RESET}" ;;
    esac

    # 确定最终使用的显示模式和格式模式 (通过解析输入)
    local final_display_mode="$( _get_display_mode_name "$optional_display_mode_input" )"
    local final_message_format_mode="$( _get_format_mode_name "$optional_message_format_mode_input" )"
    # 确定最终消息内容的颜色。优先级：函数参数 > 级别默认色。
    local final_message_color="${optional_message_content_color:-$default_message_color_code}"


    # 4. 构建终端输出字符串
    local terminal_full_output="" # 最终输出到终端的完整字符串

    local timestamp_text="[$timestamp] "
    local level_text="[$level] "
    local caller_text="[$calling_source_name] "
    local message_text="${message}" # 原始消息内容

    # 组合前缀的各个部分，并决定是否着色
    local prefix_colored_level="" # 仅用于 level_part_base 带着色后的结果
    local final_message_colored="${message_text}" # 用于消息内容着色后的结果

    # 根据 ENABLE_COLORS 和 final_display_mode 应用颜色
    if [[ "${ENABLE_COLORS:-true}" == "true" ]]; then
        case "$final_display_mode" in
            "no_color")
                # 所有部分保持原样，不应用任何颜色码
                :
                ;;
            "prefix_only_color")
                # 只有 level_text 被着色
                prefix_colored_level="${prefix_color_code}${level_text}${COLOR_RESET}"
                ;;
            "all_color")
                # level_text 被着色，message_text 也被着色
                prefix_colored_level="${prefix_color_code}${level_text}${COLOR_RESET}"
                final_message_colored="${final_message_color}${message_text}${COLOR_RESET}"
                ;;
            *) # 默认或未知选项，回退到 prefix_only_color
                prefix_colored_level="${prefix_color_code}${level_text}${COLOR_RESET}"
                ;;
        esac
    else
        # ENABLE_COLORS 为 false，强制不带颜色
        # 所有部分保持原样，不应用任何颜色码
        :
    fi
    
    # 根据 final_message_format_mode 组合最终的终端输出字符串
    case "$final_message_format_mode" in
        "full")
            terminal_full_output="${timestamp_text}${prefix_colored_level:-${level_text}}${caller_text}${final_message_colored}"
            ;;
        "level_only")
            terminal_full_output="${prefix_colored_level:-${level_text}}${final_message_colored}"
            ;;
        "no_prefix")
            terminal_full_output="${final_message_colored}"
            ;;
        "timestamp_level")
            terminal_full_output="${timestamp_text}${prefix_colored_level:-${level_text}}${final_message_colored}"
            ;;
        *) # Default to full
            terminal_full_output="${timestamp_text}${prefix_colored_level:-${level_text}}${caller_text}${final_message_colored}"
            ;;
    esac

    # 终端输出
    echo -e "$terminal_full_output"
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
    # 使用硬编码的输出方式，以确保在日志系统完全初始化前也能正常显示。
    # 这里我们模拟 `INFO` 级别的 `prefix_only_color` 模式。
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] ------ 开始为 '$script_name' 初始化日志系统 ------" >&2

    # 1. 验证必要全局变量是否已设置 - 调用辅助函数 _validate_logging_prerequisites
    # 这些变量应已由 environment_setup.sh 在调用此函数前设置并导出。
    echo -e "${COLOR_BLUE}DEBUG:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 1/4】: 验证日志环境参数 (BASE_DIR, LOG_ROOT, ORIGINAL_USER, ORIGINAL_HOME)..." >&2
    if ! _validate_logging_prerequisites; then
        # _validate_logging_prerequisites 内部会 echo 错误并 exit。
        return 1
    fi
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 1/4】: 日志环境参数验证成功." >&2

    # 2. 定义当前运行的日志日期目录 (在此函数内部定义并导出) - 调用辅助函数 _get_current_day_log_dir
    # 格式为 YYYY-MM-DD，用于组织日志文件。
    echo -e "${COLOR_BLUE}DEBUG:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 2/4】: 创建当前日志日期目录 (YYYY-MM-DD)..." >&2
    if ! _get_current_day_log_dir; then
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.initialize_logging_system] Could not determine current day's log directory. Logging cannot proceed." >&2
        return 1
    fi
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 2/4】: 成功创建日志目录: '$CURRENT_DAY_LOG_DIR'." >&2

    # 3. 确保日志根目录（包括日期目录）存在并对 ORIGINAL_USER 有写入权限
    echo -e "${COLOR_BLUE}DEBUG:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] Ensuring log directory '$CURRENT_DAY_LOG_DIR' is prepared for user '$ORIGINAL_USER'..." >&2
    echo -e "${COLOR_BLUE}DEBUG:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 3/4】: 检查用户： '$ORIGINAL_USER' 对目录： '$CURRENT_DAY_LOG_DIR'  是否有写权限..." >&2
    if ! _ensure_log_dir_user_owned "$CURRENT_DAY_LOG_DIR" "$ORIGINAL_USER"; then
        echo "${COLOR_RED}Fatal:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] Could not prepare log directory '$CURRENT_DAY_LOG_DIR' for '$ORIGINAL_USER'. Logging will not function correctly." >&2
        return 1
    fi
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 3/4】: 确定了目录: '$CURRENT_DAY_LOG_DIR' 已经存在，并且用户： '$ORIGINAL_USER' 拥有该目录的读写权限." >&2

    # 4. 为当前脚本创建具体的日志文件 - 调用辅助函数 _create_and_secure_log_file
    echo -e "${COLOR_BLUE}DEBUG:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 4/4】: 为当前脚本： '$script_name' 创建具体的日志文件..." >&2
    # 构建当前脚本的日志文件路径，包含脚本名称和精确到秒的时间戳。
    CURRENT_SCRIPT_LOG_FILE="$CURRENT_DAY_LOG_DIR/${script_name%.*}-$(date +%Y%m%d_%H%M%S).log"
    export CURRENT_SCRIPT_LOG_FILE

    # 注意：这里使用 echo 输出到 stderr，而不是 log_info，
    # 因为 log_info 内部依赖 CURRENT_SCRIPT_LOG_FILE 已经完全设置好，
    # 而这个函数正在设置它，避免死循环。
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] Initializing logging for '$script_name'. Log file will be: '$CURRENT_SCRIPT_LOG_FILE'" >&2
    
    if ! _create_and_secure_log_file "$CURRENT_SCRIPT_LOG_FILE" "$ORIGINAL_USER"; then
        echo "${COLOR_RED}Fatal:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] Failed to create and secure log file '$CURRENT_SCRIPT_LOG_FILE'. Logging might fail." >&2
        return 1
    fi
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] 【Step 4/4】: 成功创建日志文件: '$CURRENT_SCRIPT_LOG_FILE'." >&2
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} [$(date +"%Y-%m-%d %H:%M:%S")] [environment_setup] ------ 成功为 '$script_name' 初始化日志系统，日志文件为： '$CURRENT_SCRIPT_LOG_FILE'. ------ " >&2
    return 0
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
        echo "${COLOR_RED}Fatal Error:${COLOR_RESET} [utils.initialize_logging_system] Logging environment (BASE_DIR, LOG_ROOT, ORIGINAL_USER) not fully set. Exiting." >&2
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
# 它们现在支持可选参数来覆盖默认的显示模式、消息前缀格式和消息内容颜色。
#
# 参数说明 (适用于所有 log_* 函数，包括 log_summary):
#   $1 (message) - 要记录的日志消息。
#   $2 (optional_display_mode_override_input) - 可选，覆盖全局 DISPLAY_MODE (例如 "all_color" 或 "3")。
#   $3 (optional_message_format_mode_override_input) - 可选，覆盖全局 DEFAULT_MESSAGE_FORMAT_MODE (例如 "level_only" 或 "2")。
#   $4 (optional_message_content_color) - 可选，仅在 "all_color" 模式下生效，指定消息内容本身的颜色。
#
# 注意：对于 SUMMARY 级别，其 `optional_message_content_color` 参数将作为整个 SUMMARY 行的颜色。

log_info() { _log_message_core "INFO" "$1" "${2:-}" "${3:-}" "${4:-}"; }
log_notice() { _log_message_core "NOTICE" "$1" "${2:-}" "${3:-}" "${4:-}"; }
log_success() { _log_message_core "SUCCESS" "$1" "${2:-prefix_only_color}" "${3:-level_only}" "${4:-}"; } # 默认前缀为 [SUCCESS]，消息内容用绿色
log_warn() { _log_message_core "WARN" "$1" "${2:-}" "${3:-}" "${4:-}" >&2; }
log_error() { _log_message_core "ERROR" "$1" "${2:-}" "${3:-}" "${4:-}" >&2; }
log_fatal() { _log_message_core "FATAL" "$1" "${2:-}" "${3:-}" "${4:-}" >&2; exit 1; }
log_debug() { _log_message_core "DEBUG" "$1" "${2:-}" "${3:-}" "${4:-}"; }
# log_summary 强制使用 "all_color" 和 "no_prefix"，并允许可选的颜色覆盖。
# 参数顺序： message, display_mode_override_input, format_mode_override_input, content_color
log_summary() { _log_message_core "SUMMARY" "$1" "all_color" "no_prefix" "${2:-}"; }

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
            
            # 使用 log_summary 打印，并为框线行指定颜色。
            # log_summary 内部已强制 all_color 和 no_prefix，此处仅需传递 content_color
            if [[ -n "$top_line_content" ]]; then log_summary "$top_line_content" "$border_color"; fi
            if [[ -n "$mid_line_content" ]]; then log_summary "$mid_line_content" "$border_color"; fi
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
            # log_summary 内部已强制 all_color 和 no_prefix，此处仅需传递 content_color
            log_summary "$top_line_content" "$border_color"; 

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
            
            # log_summary 内部已强制 all_color 和 no_prefix，此处仅需传递 content_color
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
    # 强制错误消息为红色，并以 full 格式显示（保持所有前缀信息）
    # 参数顺序： message, display_mode_override_input, format_mode_override_input, content_color
    log_error "$message" "all_color" "full" "${COLOR_RED}" 
    log_error "Script execution terminated due to previous error." "all_color" "full" "${COLOR_RED}"
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