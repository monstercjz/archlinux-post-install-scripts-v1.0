#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/environment_setup.sh
# 版本: 1.0.11 (优化日志调用者信息显示)
# 日期: 2025-06-08
# 描述: 核心环境设置脚本。由所有入口脚本的顶部引导块调用。
#       负责在 BASE_DIR 确定后，完成项目运行环境的后续初始化。
# ------------------------------------------------------------------------------
# 职责:
#   1. 执行 Root 权限检查 (最早执行)。
#   2. 导入核心工具函数库 (utils.sh)。
#   3. 健壮地确定项目根目录 (BASE_DIR)。
#   4. 获取调用 sudo 的原始用户及其家目录 (ORIGINAL_USER, ORIGINAL_HOME)。
#   5. 加载主配置文件 (main_config.sh)。
#   6. 确保日志根目录存在并具备正确权限。
#   7. 为当前脚本初始化日志系统。
# ------------------------------------------------------------------------------
# 使用方法: (此文件不应被直接调用，而是由各脚本的顶部引导块 source)
#   source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# v1.0.1 - 2025-06-08 - 修复了在顶层作用域使用 'local' 关键字的错误。
# v1.0.2 - 2025-06-08 - 优化初始化流程的逻辑顺序，增加调试输出，提升可追踪性。
# v1.0.3 - 2025-06-08 - 将 Root 权限检查提前到文件最顶端。
# v1.0.4 - 2025-06-08 - 优化流程：在确定 BASE_DIR 之前直接导入 utils.sh。
# v1.0.5 - 2025-06-08 - BASE_DIR 确定逻辑移至调用脚本的顶部引导块；自身不再查找 BASE_DIR。
# v1.0.6 - 2025-06-08 - 修正了顶部引导块中 BASE_DIR 每次都查找的问题，实现按需查找。
# v1.0.7 - 2025-06-08 - __SOURCED__ 变量不再导出，确保子进程重新加载函数。
# v1.0.8 - 2025-06-08 - 修正了 utils.sh 加载时序问题，确保日志函数调用前已可用。
# v1.0.9 - 2025-06-08 - 修正了 environment_setup.sh 内部 main_config_path 声明时使用 'local' 的错误。
# v1.0.10 - 2025-06-08 - 修正了 ORIGINAL_HOME 变量在 main_config.sh 加载前未赋值的问题。
# v1.0.11 - 2025-06-08 - **优化日志调用者信息显示，避免硬编码前缀；调整 utils.sh 内部函数调用。**
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 传递给日志系统和环境初始化的原始调用者脚本路径。
_caller_script_path="$1" 

# 防止此初始化脚本被重复 source (如果已被加载，则直接返回)
__ENVIRONMENT_SETUP_SOURCED__="${__ENVIRONMENT_SETUP_SOURCED__:-}"
if [ -n "$__ENVIRONMENT_SETUP_SOURCED__" ]; then
    return 0 
fi

# --- 1. Root 权限检查 ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mError: This script must be run with root privileges (using 'sudo').\033[0m" >&2
    echo -e "\033[0;31mPlease run: sudo $(basename "$_caller_script_path")\033[0m" >&2
    echo -e "\033[0;31m=====================================================================${_C_RESET}\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" # 打印一个换行符，使提示符在新行显示
    exit 1
fi
# 这里不能立即使用 log_debug，因为 utils.sh 还没加载。

# --- 2. 导入核心工具函数库 (utils.sh) ---
# 注意：这里使用 echo 输出，因为 log_debug 在 utils.sh 载入前不可用
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup] Sourcing utils.sh from '$(dirname "${BASH_SOURCE[0]}")/utils.sh'..." >&2
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# 现在 log_debug 和其他日志函数可用了
log_info "utils.sh sourced. Core utilities and logging functions are now available."
log_debug "Root privileges confirmed." 

# --- 3. 验证 BASE_DIR 是否已由调用脚本确定 ---
if [ -z "${BASE_DIR+set}" ] || [ -z "$BASE_DIR" ]; then
    handle_error "Fatal: BASE_DIR was not set by the calling script's initialization block. Exiting."
fi
log_info "BASE_DIR confirmed: '$BASE_DIR'."

# --- 定义核心子目录变量 ---
export CONFIG_DIR="${BASE_DIR}/config"
export LIB_DIR="${CONFIG_DIR}/lib"
export MODULES_DIR="${CONFIG_DIR}/modules"
export ASSETS_DIR="${CONFIG_DIR}/assets" 
log_debug "Core directory variables defined: CONFIG_DIR=$CONFIG_DIR, LIB_DIR=$LIB_DIR, MODULES_DIR=$MODULES_DIR, ASSETS_DIR=$ASSETS_DIR"

# --- 4. 获取调用 sudo 的原始用户和其家目录 (ORIGINAL_USER, ORIGINAL_HOME) ---
log_debug "Determining original user and home directory..."
if [ -z "${ORIGINAL_USER+set}" ]; then 
    _get_original_user_and_home # 调用 utils.sh 中的函数获取值，其内部的 echo 信息将被移除
    log_info "Original user detected: $ORIGINAL_USER (Home: $ORIGINAL_HOME)."
else
    log_debug "ORIGINAL_USER already set in environment: $ORIGINAL_USER."
fi

# --- 5. 加载主配置文件 (main_config.sh) ---
main_config_path="${CONFIG_DIR}/main_config.sh" 
log_debug "Sourcing main_config.sh from '$main_config_path'..."
if [ -f "$main_config_path" ]; then
    . "$main_config_path"
    log_info "main_config.sh loaded. PROJECT_NAME: $PROJECT_NAME, LOG_ROOT: $LOG_ROOT, DEBUG_MODE: $DEBUG_MODE."
else
    handle_error "Fatal: Main configuration file not found at '$main_config_path'."
fi

# --- 6. 确保日志根目录存在并对 ORIGINAL_USER 有写入权限 ---
log_debug "Ensuring log directory '$LOG_ROOT' is prepared for user '$ORIGINAL_USER'..."
# _ensure_log_dir_user_owned 内部的 echo 信息将被移除或转换为 log_X
if ! _ensure_log_dir_user_owned "$LOG_ROOT" "$ORIGINAL_USER"; then
    handle_error "Fatal: Could not prepare log directory '$LOG_ROOT' for '$ORIGINAL_USER'. Script cannot proceed."
fi
log_info "Log directory '$LOG_ROOT' confirmed ready."

# --- 7. 为当前脚本初始化日志系统 ---
log_debug "Initializing logging system for current script: '$_caller_script_path'..."
# setup_logging 内部的 echo 信息将被移除或转换为 log_X
setup_logging "$_caller_script_path"
log_info "Logging system fully initialized. Current script log file: '$CURRENT_SCRIPT_LOG_FILE'."

# 标记此初始化脚本已被加载 (不导出)
__ENVIRONMENT_SETUP_SOURCED__="true"
log_debug "Environment setup complete. All core variables exported."