#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: run_setup.sh
# 版本: 1.0.7 (最终修正，使用通用顶部引导块)
# 日期: 2025-06-08
# 描述: Arch Linux 后安装脚本的主入口点。
#       负责初始化项目环境、显示欢迎信息，并引导用户进入主菜单。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# v1.0.1 - 2025-06-08 - 引入 init_script_boilerplate.sh (旧版名称) 简化环境初始化。
# v1.0.2 - 2025-06-08 - 适配 boilerplate.sh，完全剥离 utils.sh 的初始化职责。
# v1.0.3 - 2025-06-08 - 适配更名为 environment_setup.sh 的环境引导脚本。
# v1.0.4 - 2025-06-08 - 适配 environment_setup.sh 的调试优化和流程细化。
# v1.0.5 - 2025-06-08 - 适配 environment_setup.sh 的 Root 权限检查提前。
# v1.0.6 - 2025-06-08 - 采用新的脚本顶部引导块来健壮地确定 BASE_DIR 并加载 environment_setup.sh。
# v1.0.7 - 2025-06-08 - **适配 environment_setup.sh 和 utils.sh 中的 __SOURCED__ 变量不再导出。**
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 这是所有入口脚本最开始执行的代码，用于健壮地确定项目根目录 (BASE_DIR)。
# 无论脚本从哪个位置被调用，都能正确找到项目根目录，从而构建其他文件的绝对路径。

# 严格模式：
set -euo pipefail

# === 核心优化：确保每次顶层启动都提示环境确认 ===
# 在脚本执行的最开始，清除 _SETUP_INITIAL_CONFIRMED 变量。
# 这可以确保当用户从终端手动运行此脚本时，环境确认提示会重新出现。
unset _SETUP_INITIAL_CONFIRMED

# 获取当前正在执行（或被 source）的脚本的绝对路径。
# BASH_SOURCE[0] 指向当前文件自身。如果此文件被 source，则 BASH_SOURCE[1] 指向调用者。
# 我们需要的是原始调用脚本的路径来确定项目根目录。
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

# 动态查找项目根目录 (仅当 BASE_DIR 尚未设置时执行查找)
if [ -z "${BASE_DIR+set}" ]; then # 检查 BASE_DIR 是否已设置 (无论值是否为空)
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""

    while [[ "$_project_root_candidate" != "/" ]]; do
        # 检查项目根目录的“签名”：存在 run_setup.sh 文件和 config/ 目录
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate") # 向上移动一层目录
    done

    if [[ -z "$_found_base_dir" ]]; then
        # 此时任何日志或颜色变量都不可用，直接输出致命错误并退出。
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        echo -e "\033[0;31mPlease ensure 'run_setup.sh' and 'config/' directory are present in the project root.\033[0m" >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi

# 在 BASE_DIR 确定后，立即 source environment_setup.sh
# 这样 environment_setup.sh 和它内部的所有路径引用（如 utils.sh, main_config.sh）
# 都可以基于 BASE_DIR 进行绝对引用，解决了 'source' 路径写死的痛点。
# 同时，_current_script_entrypoint 传递给 environment_setup.sh 以便其内部用于日志等。
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---


# --- 主要逻辑 ---

main() {
    display_header_section "$PROJECT_NAME $PROJECT_VERSION" "box" 80
    log_info "Welcome to the Arch Linux Post-Installation Setup script!"
    log_info "This script will guide you through configuring your Arch Linux system."
    log_info "All operations are logged to: ${CURRENT_SCRIPT_LOG_FILE}"
    log_info "Running as user: ${USER} (Original user: ${ORIGINAL_USER}, Home: ${ORIGINAL_HOME})"

    local main_menu_script="${CONFIG_DIR}/main_menu.sh" # 使用 CONFIG_DIR
    if [ -f "$main_menu_script" ]; then
        log_info "Starting main configuration menu..."
        bash "$main_menu_script"
        local menu_exit_code=$?

        if [ "$menu_exit_code" -ne 0 ]; then
            handle_error "Main menu exited with an error code ($menu_exit_code). Please review logs." "$menu_exit_code"
        else
            log_info "Main menu completed successfully or user chose to exit."
        fi
    else
        handle_error "Main menu script not found at '$main_menu_script'."
    fi

    log_info "Setup process finished. Please review the log file for details."
}

# 调用主函数
main "$@"

exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Arch Linux Post-Installation Setup script."
    exit "$exit_code"
}

exit_script 0