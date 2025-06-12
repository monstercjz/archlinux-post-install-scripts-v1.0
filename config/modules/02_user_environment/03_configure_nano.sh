#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_user_environment/03_configure_nano.sh
# 版本: 1.1.0 (引入内部菜单，分离配置选项)
# 日期: 2025-06-12
# 描述: 为当前非 root 用户提供一个全面的 Nano 编辑器配置流程。
#       此脚本从一个旧的独立脚本完全重构而来，以完美融入当前框架。
# ------------------------------------------------------------------------------
# 核心功能:
# - **新增**: 提供一个简单的内部菜单，允许用户独立选择配置默认编辑器或 .nanorc。
# - 检查并安装 `nano` 编辑器包。
# - 可选地将 `nano` 设置为用户的默认 EDITOR 和 VISUAL。
# - 可选地为用户配置一个推荐的 `.nanorc` 文件，以启用语法高亮、行号和自动缩进等功能。
# - 在修改任何用户配置文件 (.bashrc, .zshrc, .nanorc) 之前，使用框架的
#   `create_backup_and_cleanup` 函数进行统一备份和旧备份清理。
# - 所有针对用户配置文件的读写操作，均通过 `run_as_user` 函数以非 root 权限执行，
#   确保安全和正确的文件所有权。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。完全重构，替代了旧的、独立的 nano.sh 脚本。
# v1.0.1 - 2025-06-12 - 修复了 shell 路径匹配和 grep 对不存在文件的警告问题。
# v1.1.0 - 2025-06-12 - **重构为内部菜单驱动模式，允许用户独立选择配置项，增强灵活性。**
# ==============================================================================

# --- 脚本顶部引导块 START ---
set -euo pipefail
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
if [ -z "${BASE_DIR+set}" ]; then
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""
    while [[ "$_project_root_candidate" != "/" ]]; do
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate")
    done
    if [[ -z "$_found_base_dir" ]]; then
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 核心功能函数 (逻辑不变)
# ==============================================================================

# _ensure_nano_installed()
# @description: 检查并安装 `nano` 包。
# @returns: 0 on success, 1 on failure.
_ensure_nano_installed() {
    log_info "Step 1: Checking and ensuring 'nano' editor is installed."
    if ! is_package_installed "nano"; then
         log_warn "'nano' is not installed."
        if _confirm_action "Do you want to install 'nano' now?" "y" "${COLOR_YELLOW}"; then
            log_info "User confirmed. Installing 'nano'..."
            if ! install_pacman_pkg "nano"; then
                log_error "Failed to install 'nano'."
                return 1
            fi
        else
            log_warn "Nano is required for this module. Aborting."
            return 1
        fi
    fi
    log_success "'nano' is installed and ready."
    return 0
}

# _configure_default_editor()
# @description: 引导用户将 nano 设置为默认编辑器，修改 shell 配置文件。
# @returns: 0 on success or user skip, 1 on failure.
_configure_default_editor() {
    display_header_section "Set Nano as Default Editor" "default" 80
    
    if ! _confirm_action "Do you want to proceed with setting 'nano' as the default editor for user '$ORIGINAL_USER'?" "y" "${COLOR_GREEN}"; then
        log_info "User chose to skip."
        return 0
    fi

    local user_shell; user_shell=$(getent passwd "$ORIGINAL_USER" | cut -d: -f7)
    local shell_name; shell_name=$(basename "$user_shell")
    local shell_config_path=""

    case "$shell_name" in
        "bash") shell_config_path="${ORIGINAL_HOME}/.bashrc";;
        "zsh") shell_config_path="${ORIGINAL_HOME}/.zshrc";;
        *)
            log_warn "Unsupported shell '$shell_name' (from path '$user_shell'). Cannot automatically set default editor."
            log_warn "Please manually add 'export EDITOR=nano' and 'export VISUAL=nano' to your shell configuration file."
            return 0
            ;;
    esac
    log_info "Detected user shell: '$shell_name'. Target configuration file: '$shell_config_path'."
    
    create_backup_and_cleanup "$shell_config_path" "shell_config"

    local -a vars_to_set=("EDITOR=nano" "VISUAL=nano")
    local changes_made=false
    for var_assignment in "${vars_to_set[@]}"; do
        if ! run_as_user "grep -q \"^export ${var_assignment}\$\" \"${shell_config_path}\""; then
            log_info "Adding 'export ${var_assignment}' to '${shell_config_path}'."
            if run_as_user "echo 'export ${var_assignment}' >> \"${shell_config_path}\""; then
                changes_made=true
            else
                log_error "Failed to add 'export ${var_assignment}' to '${shell_config_path}'."
                return 1
            fi
        else
            log_info "'export ${var_assignment}' already exists. Skipping."
        fi
    done

    if [ "$changes_made" = true ]; then
        log_success "Default editor configuration completed for '$ORIGINAL_USER'."
        log_notice "The changes will take effect after you start a new shell session or run 'source ${shell_config_path}'."
    else
        log_info "No changes were needed for the default editor configuration."
    fi
    return 0
}

# _configure_nanorc()
# @description: 引导用户配置 .nanorc 文件以获得更好的体验。
# @returns: 0 on success or user skip, 1 on failure.
_configure_nanorc() {
    display_header_section "配置 .nanorc 以获得更好的体验" "default" 80

    if ! _confirm_action "您想为 .nanorc 应用推荐的配置吗？" "y" "${COLOR_GREEN}"; then
        log_info "用户选择跳过。"
        return 0
    fi
    
    local nanorc_path="${ORIGINAL_HOME}/.nanorc"
    log_info "目标配置文件: '$nanorc_path'."
    
    create_backup_and_cleanup "$nanorc_path" "nanorc"

    # =================================================================
    # 更新的配置项列表
    # =================================================================
    declare -A nano_options=(
        # --- 核心体验 ---
        ["set linenumbers"]="启用行号"
        ["set autoindent"]="启用自动缩进"
        ["set constantshow"]="在状态栏持续显示光标位置"
        
        # --- Tab 和缩进 ---
        ["set tabsize 4"]="设置Tab键宽度为4个空格"
        ["set tabstospaces"]="将Tab键转换为空格"

        # --- 鼠标和滚动 ---
        ["set mouse"]="启用鼠标支持 (点击定位, 滚轮滚动)"
        
        # --- 语法高亮 (通常放在最后) ---
        ["include /usr/share/nano/*.nanorc"]="启用语法高亮"
    )

    local changes_made=false
    for option in "${!nano_options[@]}"; do
        local description="${nano_options[$option]}"
        
        if ! run_as_user "grep -q -F -x \"${option}\" \"${nanorc_path}\""; then
            log_info "正在添加选项: '$option' ($description)。"
            if run_as_user "echo \"$option\" >> \"${nanorc_path}\""; then
                changes_made=true
            else
                log_error "添加选项 '$option' 到 '$nanorc_path' 失败。"
            fi
        else
            log_info "选项 '$option' 已存在，跳过。"
        fi
    done

    if [ "$changes_made" = true ]; then
        log_success "Nano 在 '${nanorc_path}' 中的配置已更新。"
    else
        log_info "无需更改 .nanorc 配置。"
    fi
    return 0
}

# ==============================================================================
# 主函数 (菜单驱动)
# ==============================================================================
main() {
    display_header_section "Nano Editor Configuration" "box" 80 "${COLOR_BLUE}"
    log_info "This module helps you install and configure the Nano text editor for user '$ORIGINAL_USER'."

    # 前置条件：必须安装 Nano
    if ! _ensure_nano_installed; then
        return 1
    fi

    # 内部菜单循环
    while true; do
        display_header_section "Nano Configuration Menu" "default" 80 "${COLOR_PURPLE}"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Set 'nano' as the default system editor"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Configure '.nanorc' (syntax highlighting, line numbers, etc.)"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Finish and return to the previous menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        
        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1, 2, 0]: ${COLOR_RESET}")" choice
        echo

        case "$choice" in
            1)
                _configure_default_editor
                ;;
            2)
                _configure_nanorc
                ;;
            0)
                log_info "Nano configuration finished. Returning to the main menu."
                break
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please try again."
                ;;
        esac
        
        # 在每次操作后暂停，让用户看到结果
        if [[ "$choice" == "1" || "$choice" == "2" ]]; then
            read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to return to the Nano menu...${COLOR_RESET}")"
        fi
    done

    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

# 脚本退出处理函数
exit_script() {
    local exit_code=${1:-$?_}
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Nano Configuration script successfully."
    else
        log_warn "Exiting Nano Configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

# 调用退出函数
exit_script $?