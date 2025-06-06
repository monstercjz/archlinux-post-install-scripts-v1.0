#!/bin/bash

# lib/utils.sh
# 包含日志记录、sudo 命令包装、用户确认、颜色输出、原始用户及家目录获取、模块调度器等通用函数。

# 日志函数
log() {
    local level="$1"
    local display_message="$2" # 带颜色的消息
    local raw_message="$3"     # 不带颜色的消息
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "[${timestamp}] [${level}] ${display_message}"
    echo "[${timestamp}] [${level}] $(echo -e "${raw_message}" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")" >> "$LOG_FILE"
}

log_info() {
    log "INFO" "${COLOR_CYAN}$1${COLOR_RESET}" "$1"
}

log_success() {
    log "SUCCESS" "${COLOR_GREEN}$1${COLOR_RESET}" "$1"
}

log_warn() {
    log "WARN" "${COLOR_YELLOW}$1${COLOR_RESET}" "$1"
}

log_error() {
    log "ERROR" "${COLOR_RED}$1${COLOR_RESET}" "$1" >&2
}

# 检查是否以 root 权限运行
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此操作需要 root 权限。请使用 sudo 运行。"
        return 1
    fi
    return 0
}

# 以原始用户身份执行命令
run_as_original_user() {
    if [[ -z "$ORIGINAL_USER_NAME" ]]; then
        log_error "无法确定原始用户。请确保 ORIGINAL_USER_NAME 已设置。"
        return 1
    fi
    log_info "以用户 '$ORIGINAL_USER_NAME' 身份执行: $*"
    sudo -u "$ORIGINAL_USER_NAME" bash -c "$*"
    return $?
}

# 用户确认函数
confirm_action() {
    local prompt_message="$1"
    read -p "${COLOR_YELLOW}${prompt_message} (y/N)? ${COLOR_RESET}" -n 1 -r
    echo # 换行
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0 # 用户确认
    else
        return 1 # 用户取消
    fi
}

# 获取原始用户和家目录
get_original_user_info() {
    if [[ -n "$SUDO_USER" ]]; then
        ORIGINAL_USER_NAME="$SUDO_USER"
        ORIGINAL_USER_HOME=$(eval echo "~$SUDO_USER")
        log_info "检测到原始用户: ${ORIGINAL_USER_NAME}, 家目录: ${ORIGINAL_USER_HOME}"
    else
        log_warn "无法通过 SUDO_USER 环境变量检测到原始用户。请确保脚本通过 sudo 运行。"
        ORIGINAL_USER_NAME=$(whoami)
        ORIGINAL_USER_HOME="$HOME"
        log_warn "将当前用户 (${ORIGINAL_USER_NAME}) 视为原始用户。"
    fi
}

# 模块调度器
# 用于执行 modules 目录下的脚本
dispatch_module() {
    local module_path="$1"
    if [[ -f "$module_path" && -x "$module_path" ]]; then
        log_info "正在执行模块: $(basename "$module_path")"
        "$module_path"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log_success "模块 $(basename "$module_path") 执行成功。"
        else
            log_error "模块 $(basename "$module_path") 执行失败，退出码: $exit_code。"
        fi
        return $exit_code
    else
        log_error "模块不存在或不可执行: $module_path"
        return 1
    fi
}

# 通用初始化块 (所有需要共享功能和配置的脚本都将包含此块)
# 动态定位项目根目录，并从中加载 main_config.sh 和 lib/utils.sh。
# 注意：此块将在每个 .sh 脚本（除了 run_setup.sh）的开头插入。
# --------------------------------------------------------------------
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# PROJECT_ROOT=""
# current_dir="$SCRIPT_DIR"
# while [[ "$current_dir" != "/" && ! -d "$current_dir/config" ]]; do
#     current_dir="$(dirname "$current_dir")"
# done
# if [[ -d "$current_dir/config" ]]; then
#     PROJECT_ROOT="$current_dir"
# else
#     echo "错误：无法找到项目根目录 (包含 config 目录)。" >&2
#     exit 1
# fi
# source "$PROJECT_ROOT/config/main_config.sh"
# source "$PROJECT_ROOT/config/lib/utils.sh"
# get_original_user_info # 获取原始用户信息
# --------------------------------------------------------------------