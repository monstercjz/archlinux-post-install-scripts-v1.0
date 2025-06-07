#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_menu.sh
# 版本: 1.0.6 (最终修正，使用通用顶部引导块)
# 日期: 2025-06-08
# 描述: Arch Linux 后安装脚本的主菜单界面。
#       提供一个交互式菜单，引导用户选择不同的配置和安装模块。
#       支持作为独立脚本运行，或由 run_setup.sh 调用。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# v1.0.1 - 2025-06-08 - 引入 init_script_boilerplate.sh (旧版名称) 简化环境初始化。
# v1.0.2 - 2025-06-08 - 适配 boilerplate.sh，完全剥离 utils.sh 的初始化职责。
# v1.0.3 - 2025-06-08 - 适配更名为 environment_setup.sh 的环境引导脚本。
# v1.0.4 - 2025-06-08 - 适配 environment_setup.sh 的调试优化和流程细化。
# v1.0.5 - 2025-06-08 - 适配 environment_setup.sh 的 Root 权限检查提前。
# v1.0.6 - 2025-06-08 - **适配 environment_setup.sh 和 utils.sh 中的 __SOURCED__ 变量不再导出。**
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 这是所有入口脚本最开始执行的代码，用于健壮地确定项目根目录 (BASE_DIR)。
# 无论脚本从哪个位置被调用，都能正确找到项目根目录，从而构建其他文件的绝对路径。

# 严格模式：
set -euo pipefail

# 获取当前正在执行（或被 source）的脚本的绝对路径。
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
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        echo -e "\033[0;31mPlease ensure 'run_setup.sh' and 'config/' directory are present in the project root.\033[0m" >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi

# 在 BASE_DIR 确定后，立即 source environment_setup.sh
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# --- 函数定义 ---

show_main_menu() {
    display_header_section "Main Configuration Menu"
    log_info "Please choose a section to configure:"
    log_info "--------------------------------------------------"
    log_info "  1. System Base Configuration      (网络、镜像、时区等)"
    log_info "  2. Package Management             (AUR 助手、Pacman Hook)"
    log_info "  3. User Environment Setup         (Shell、点文件、编辑器等)"
    log_info "  4. Software Installation          (常用、特定应用)"
    log_info "  5. Cleanup and Finish             (清理、生成报告)"
    log_info "  0. Exit Script"
    log_info "--------------------------------------------------"
}

process_main_menu_choice() {
    local choice="$1"
    local module_script=""

    case "$choice" in
        1)
            module_script="${MODULES_DIR}/01_system_base/00_system_base_menu.sh"
            ;;
        2)
            module_script="${MODULES_DIR}/02_package_management/00_package_management_menu.sh"
            ;;
        3)
            module_script="${MODULES_DIR}/03_user_environment/00_user_environment_menu.sh"
            ;;
        4)
            module_script="${MODULES_DIR}/04_software_installation/00_software_installation_menu.sh"
            ;;
        5)
            module_script="${MODULES_DIR}/00_cleanup_and_finish.sh"
            ;;
        0)
            log_info "Exiting the setup script. Goodbye!"
            exit 0
            ;;
        *)
            log_warn "Invalid choice: '$choice'. Please enter a number between 0 and 5."
            return 1
            ;;
    esac

    if [ -f "$module_script" ]; then
        log_info "Navigating to: $(basename "$(dirname "$module_script")")/$(basename "$module_script")"
        bash "$module_script"
        local script_exit_code=$?
        if [ "$script_exit_code" -ne 0 ]; then
            log_warn "Module '$(basename "$module_script")' exited with code $script_exit_code. Review logs."
        else
            log_info "Module '$(basename "$module_script")' completed successfully."
        fi
    else
        handle_error "Error: Module script '$module_script' not found. Please check project structure." 1
    fi
    return 0
}

main() {
    log_info "Starting Main Menu for $PROJECT_NAME $PROJECT_VERSION."
    log_debug "Detected BASE_DIR: $BASE_DIR"
    log_debug "Detected ORIGINAL_USER: $ORIGINAL_USER (Home: $ORIGINAL_HOME)"

    while true; do
        show_main_menu
        read -rp "Enter your choice: " main_choice

        main_choice=$(echo "$main_choice" | tr -d '[:space:]')

        if ! [[ "$main_choice" =~ ^[0-9]+$ ]]; then
            log_warn "Invalid input. Please enter a number."
            continue
        fi

        process_main_menu_choice "$main_choice"
        log_info "Returning to Main Menu."
        read -rp "Press Enter to continue to Main Menu..."
        echo
    done
}

# --- 脚本执行入口 ---
main "$@"