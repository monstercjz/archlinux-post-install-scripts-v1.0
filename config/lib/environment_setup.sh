#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/environment_setup.sh
# 版本: 1.0.12 (新增 utils.sh source 错误检查)
# 日期: 2025-06-08
# 描述: 核心环境设置脚本。由所有入口脚本的顶部引导块调用。
#       负责在 BASE_DIR 确定后，完成项目运行环境的后续初始化。
# ------------------------------------------------------------------------------
# 职责:
#   1. 执行 Root 权限检查 (最早执行)。
#   2. 导入核心工具函数库 (utils.sh)，**并进行错误检查**。
#   3. 健壮地确定项目根目录 (BASE_DIR)。
#   4. 获取调用 sudo 的原始用户及其家目录 (ORIGINAL_USER, ORIGINAL_HOME)。
#   5. 加载主配置文件 (main_config.sh)。
#   6. 定义当前运行的日志日期目录 (CURRENT_DAY_LOG_DIR)。
#   7. 确保日志根目录（包括日期目录）存在并具备正确权限。
#   8. 为当前脚本初始化日志系统。
# ------------------------------------------------------------------------------
# 使用方法: (此文件不应被直接调用，而是由各脚本的顶部引导块 source)
#   source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# ...
# v1.0.11 - 2025-06-08 - 优化日志调用者信息显示。
# v1.0.12 - 2025-06-08 - **新增对 utils.sh 文件的存在性和可读性检查。**
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
    echo -e "\033[0;31m=====================================================================${COLOR_RESET}" >&2
    echo -e "\033[0;31mError: This script must be run with root privileges (using 'sudo').\033[0m" >&2
    echo -e "\033[0;31mPlease run: sudo $(basename "$_caller_script_path")\033[0m" >&2
    echo -e "\033[0;31m=====================================================================${COLOR_RESET}\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" # 打印一个换行符，使提示符在新行显示
    exit 1
fi

# --- 2. 导入核心工具函数库 (utils.sh) ---
_utils_path="$(dirname "${BASH_SOURCE[0]}")/utils.sh" # 获取 utils.sh 的绝对路径
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup] Sourcing utils.sh from '$_utils_path'..." >&2

# 检查 utils.sh 是否存在且可读
if [[ ! -f "$_utils_path" || ! -r "$_utils_path" ]]; then
    echo -e "\033[0;31mFatal Error:\033[0m Core utility file not found or not readable: '$_utils_path'." >&2
    echo -e "\033[0;31mPlease ensure the project structure is correct and file permissions allow reading.\033[0m" >&2
    exit 1
fi
source "$_utils_path"
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
    _get_original_user_and_home 
    log_info "Original user detected: $ORIGINAL_USER (Home: $ORIGINAL_HOME)."
else
    log_debug "ORIGINAL_USER already set in environment: $ORIGINAL_USER."
fi

# --- 5. 加载主配置文件 (main_config.sh) ---
main_config_path="${CONFIG_DIR}/main_config.sh" 
log_debug "Sourcing main_config.sh from '$main_config_path'..."
# 检查 main_config.sh 是否存在且可读
if [[ ! -f "$main_config_path" || ! -r "$main_config_path" ]]; then
    handle_error "Fatal: Main configuration file not found or not readable: '$main_config_path'."
fi
. "$main_config_path" # source the file
log_info "main_config.sh loaded. PROJECT_NAME: $PROJECT_NAME, LOG_ROOT: $LOG_ROOT, DEBUG_MODE: $DEBUG_MODE."

# --- 6. 定义当前运行的日志日期目录 ---
export CURRENT_DAY_LOG_DIR="${LOG_ROOT}/$(date +%Y-%m-%d)"
log_debug "Current day's log directory set to: '$CURRENT_DAY_LOG_DIR'."

# --- 7. 确保日志根目录（包括日期目录）存在并对 ORIGINAL_USER 有写入权限 ---
log_debug "Ensuring log directory '$CURRENT_DAY_LOG_DIR' is prepared for user '$ORIGINAL_USER'..."
if ! _ensure_log_dir_user_owned "$CURRENT_DAY_LOG_DIR" "$ORIGINAL_USER"; then
    handle_error "Fatal: Could not prepare log directory '$CURRENT_DAY_LOG_DIR' for '$ORIGINAL_USER'. Script cannot proceed."
fi
log_info "Log directory '$CURRENT_DAY_LOG_DIR' confirmed ready."

# --- 8. 为当前脚本初始化日志系统 ---
log_debug "Initializing logging system for current script: '$_caller_script_path'..."
if ! setup_logging "$_caller_script_path"; then
    handle_error "Fatal: Failed to initialize logging system for current script. Script cannot proceed."
fi
log_info "Logging system fully initialized. Current script log file: '$CURRENT_SCRIPT_LOG_FILE'."

# 标记此初始化脚本已被加载 (不导出)
__ENVIRONMENT_SETUP_SOURCED__="true"
log_debug "Environment setup complete. All core variables exported."