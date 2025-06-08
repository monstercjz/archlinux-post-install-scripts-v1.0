#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/environment_setup.sh
# 版本: 1.0.21 (最终版：协调所有全局变量的赋值)
# 日期: 2025-06-08
# 描述: 核心环境设置脚本。由所有入口脚本的顶部引导块调用。
#       负责在 BASE_DIR 确定后，完成项目运行环境的后续初始化。
# ------------------------------------------------------------------------------
# 职责:
#   1. 执行 Root 权限检查 (最早执行)。
#   2. 验证 BASE_DIR 是否已由调用脚本确定。
#   3. 加载主配置文件 (main_config.sh)。
#   4. 定义并导出核心子目录变量 (CONFIG_DIR, LIB_DIR, MODULES_DIR, ASSETS_DIR)。
#   5. 导入核心工具函数库 (utils.sh)，并进行错误检查。
#   6. 获取并导出调用 sudo 的原始用户及其家目录 (ORIGINAL_USER, ORIGINAL_HOME)。
#   7. 赋值 DOTFILES_LOCAL_PATH。
#   8. 调用 initialize_logging_system 初始化日志系统。
#   9. 显示初始化统计，并等待用户确认。
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
# v1.0.11 - 2025-06-08 - 优化日志调用者信息显示。
# v1.0.12 - 2025-06-08 - 新增对 utils.sh source 的错误检查。
# v1.0.13 - 2025-06-08 - 优化：核心目录变量定义提前，utils.sh 引用统一使用 LIB_DIR。
# v1.0.14 - 2025-06-08 - 在 BASE_DIR 验证失败时，添加用户交互提示后退出。
# v1.0.15 - 2025-06-08 - 在所有初始化步骤完成后，显示环境统计摘要并等待用户确认。
# v1.0.16 - 2025-06-08 - 引入并应用新的颜色 (例如 COLOR_PURPLE) 用于总结性输出。
# v1.0.17 - 2025-06-08 - 应用新的 SUMMARY 日志级别。
# v1.0.18 - 2025-06-08 - **统一调用 initialize_logging_system() 函数来完成日志系统初始化。**
# v1.0.21 - 2025-06-08 - **最终优化：调整main_confing调用顺序。**
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 传递给日志系统和环境初始化的原始调用者脚本路径。
# (由调用脚本的顶部引导块传递进来)
_caller_script_path="$1" 

# 防止此初始化脚本在同一个 shell 进程中被重复 source (如果已被加载，则直接返回)。
# (此变量不会被导出，以确保在新的子进程中能重新加载)
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup] 检查environment_setup是否重复加载..." >&2
__ENVIRONMENT_SETUP_SOURCED__="${__ENVIRONMENT_SETUP_SOURCED__:-}"
if [ -n "$__ENVIRONMENT_SETUP_SOURCED__" ]; then
    return 0 
fi

# ==============================================================================
# 阶段 1: 最早的、不依赖 utils.sh 的检查 (使用硬编码 ANSI 颜色码)
# ==============================================================================

# --- 1. Root 权限检查 ---
# 如果不是 root 用户，则打印带颜色的错误信息，等待用户按键后退出。
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【1/7】 检查是否以root权限执行..." >&2
if [[ "$(id -u)" -ne 0 ]]; then
    # 使用硬编码的 ANSI 颜色码，因为此时 utils.sh 尚未加载。
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mError: This script must be run with root privileges (using 'sudo').\033[0m" >&2
    echo -e "\033[0;31mPlease run: sudo $(basename "$_caller_script_path")\033[0m" >&2
    echo -e "\033[0;31m=====================================================================${COLOR_RESET}\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" # 打印一个换行符，使提示符在新行显示
    exit 1
fi

# --- 2. 验证 BASE_DIR 是否已由调用脚本确定 ---
# 此时 BASE_DIR 应该已经被调用脚本的顶部引导块设置并导出。
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【2/7】 检查是否可以确定根目录路径值..." >&2
if [ -z "${BASE_DIR+set}" ] || [ -z "$BASE_DIR" ]; then
    # 使用硬编码的 ANSI 颜色码，因为 utils.sh 尚未加载。
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mFatal Error:\033[0m [environment_setup] BASE_DIR was not set by the calling script's initialization block." >&2
    echo -e "\033[0;31mThis indicates a critical issue with the script's core setup. Exiting.\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" 
    exit 1
fi

# ==============================================================================
# 阶段 2: 加载配置与导入工具 (为后续步骤提供基础支持)
# ==============================================================================

# --- 3. 加载主配置文件 (main_config.sh) ---
# 此文件会声明所有全局 export 变量，并为静态配置项提供默认值。
main_config_path="${BASE_DIR}/config/main_config.sh" 
# echo -e "\033[0;34mDEBUG:\033[0m [environment_setup] Sourcing main_config.sh from '$main_config_path'..." >&2
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【3/7】 加载配置文件：main_config 从 '$main_config_path'..." >&2
if [[ ! -f "$main_config_path" || ! -r "$main_config_path" ]]; then
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mFatal Error:\033[0m Main configuration file not found or not readable: '$_utils_path'." >&2
    echo -e "\033[0;31mPlease ensure '$main_config_path' exists and has read permissions.${_C_RESET}\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" 
    exit 1
fi
. "$main_config_path" # <--- 加载所有 main_config.sh 中声明的变量和默认值

# --- 4. 定义核心子目录变量 ---
# 这些变量的值依赖于 BASE_DIR，由 environment_setup.sh 在运行时计算并 export。
# 注意：这些变量在 main_config.sh 中有声明，这里是再次声明和赋值。
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【4/7】 补全生成项目各资源文件夹路径..." >&2
export CONFIG_DIR="${BASE_DIR}/config"
export LIB_DIR="${CONFIG_DIR}/lib"
export MODULES_DIR="${CONFIG_DIR}/modules"
export ASSETS_DIR="${CONFIG_DIR}/assets" 
# 注意：此时还不能使用 log_debug，因为 utils.sh 尚未加载。

# --- 5. 导入核心工具函数库 (utils.sh) ---
# utils.sh 内部不声明全局 export 变量，仅使用它们。
_utils_path="${LIB_DIR}/utils.sh" 
# echo -e "\033[0;34mDEBUG:\033[0m [environment_setup] Sourcing utils.sh from '$_utils_path'..." >&2
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【5/7】 加载核心工具库：utils.sh 从 '$_utils_path'..." >&2
if [[ ! -f "$_utils_path" || ! -r "$_utils_path" ]]; then
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mFatal Error:\033[0m Core utility file not found or not readable: '$_utils_path'." >&2
    echo -e "\033[0;31mPlease ensure the project structure is correct and file permissions allow reading.\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" 
    exit 1
fi
source "$_utils_path" # <--- utils.sh 及其函数和颜色变量现在可用

# ==============================================================================
# 阶段 3: 基于已加载的 utils.sh 和配置，初始化剩余环境
# ==============================================================================

echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【6/7】 判断脚本执行的真实用户信息并展示各种必须的环境变量值..." >&2
# 现在 log_info/log_debug 等函数和 COLOR_X 变量都已可用。
log_info "main_config.sh loaded. PROJECT_NAME: $PROJECT_NAME, LOG_ROOT: $LOG_ROOT, DEBUG_MODE: $DEBUG_MODE."
log_info "utils.sh sourced. Core utilities and logging functions are now available."
log_debug "Root privileges confirmed." 
log_info "BASE_DIR confirmed: '$BASE_DIR'."
log_debug "Core directory variables defined: CONFIG_DIR=$CONFIG_DIR, LIB_DIR=$LIB_DIR, MODULES_DIR=$MODULES_DIR, ASSETS_DIR=$ASSETS_DIR"

# --- 6. 获取调用 sudo 的原始用户和其家目录 (ORIGINAL_USER, ORIGINAL_HOME) ---
# _get_original_user_and_home 内部会根据 SUDO_USER 动态计算并 export ORIGINAL_USER, ORIGINAL_HOME。
# 这将是 ORIGINAL_USER 和 ORIGINAL_HOME 的首次赋值。
# log_debug "Determining original user and home directory..."
# if [ -z "${ORIGINAL_USER+set}" ] || [ -z "$ORIGINAL_USER" ]; then # 每次都调用，确保值正确
_get_original_user_and_home # 此函数内部会 export ORIGINAL_USER 和 ORIGINAL_HOME
log_info "Original user detected: $ORIGINAL_USER (Home: $ORIGINAL_HOME)."
# else
#     log_debug "ORIGINAL_USER already set in environment: $ORIGINAL_USER."
# fi


# ==============================================================================
# 阶段 4: 日志系统初始化 (统一通过 initialize_logging_system)
# ==============================================================================

# --- 7. 调用 initialize_logging_system 初始化日志系统 ---
# initialize_logging_system 内部会定义并 export CURRENT_DAY_LOG_DIR 和 CURRENT_SCRIPT_LOG_FILE。
# log_debug "Initializing logging system fully..."
echo -e "\033[0;34mDEBUG:\033[0m [environment_setup]【7/7】 初始化日志系统--文件记录..." >&2
if ! initialize_logging_system "$_caller_script_path"; then
    echo -e "\033[0;31m=====================================================================\033[0m" >&2
    echo -e "\033[0;31mFatal Error:\033[0m Failed to initialize logging system. Script cannot proceed." >&2
    echo -e "\033[0;31mPlease ensure the project structure is correct and file permissions allow reading.\033[0m" >&2
    read -rp "Press any key to exit..." -n 1
    echo "" 
    exit 1
fi
log_info "Logging system fully initialized. Current script log file: '$CURRENT_SCRIPT_LOG_FILE'."


# ==============================================================================
# 阶段 5: 初始化统计与用户确认阶段
# ==============================================================================

# --- . 显示初始化统计，并等待用户确认 ---
display_header_section "Environment Setup Summary" "box" 80 "${COLOR_CYAN}" "${COLOR_BOLD}${COLOR_YELLOW}"

log_summary "--------------------------------------------------"
log_summary "Project: ${PROJECT_NAME} ${PROJECT_VERSION}"
log_summary "Author: ${PROJECT_AUTHOR}"
log_summary "Description: ${PROJECT_DESCRIPTION}"
log_summary "--------------------------------------------------"
log_summary "Running as: root (Original User: ${ORIGINAL_USER}, Home: ${ORIGINAL_HOME})"
log_summary "Project Root: ${BASE_DIR}"
log_summary "Log Directory: ${LOG_ROOT}" # 显示 LOG_ROOT 而非 CURRENT_DAY_LOG_DIR
log_summary "Current Log File: ${CURRENT_SCRIPT_LOG_FILE}"
log_summary "Debug Mode: $(if [[ "${DEBUG_MODE}" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
log_summary "Colors: $(if [[ "${ENABLE_COLORS}" == "true" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
log_summary "--------------------------------------------------"

log_info "Environment setup completed successfully. Please review the above details and the log file."
read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to continue or Ctrl+C to abort...${COLOR_RESET}")"

# 标记此初始化脚本已被加载 (不导出)
__ENVIRONMENT_SETUP_SOURCED__="true"
log_debug "Environment setup complete. All core variables exported."