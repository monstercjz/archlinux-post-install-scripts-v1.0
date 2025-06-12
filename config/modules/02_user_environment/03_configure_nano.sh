#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_user_environment/03_configure_nano.sh
# 版本: 1.0.0 (完全重构，适配项目框架)
# 日期: 2025-06-11
# 描述: 为当前非 root 用户提供一个全面的 Nano 编辑器配置流程。
#       此脚本从一个旧的独立脚本完全重构而来，以完美融入当前框架。
# ------------------------------------------------------------------------------
# 核心功能:
# - 检查并安装 `nano` 编辑器包。
# - 可选地将 `nano` 设置为用户的默认 EDITOR 和 VISUAL。
# - 可选地为用户配置一个推荐的 `.nanorc` 文件，以启用语法高亮、行号和自动缩进等功能。
# - 在修改任何用户配置文件 (.bashrc, .zshrc, .nanorc) 之前，使用框架的
#   `create_backup_and_cleanup` 函数进行统一备份和旧备份清理。
# - 所有针对用户配置文件的读写操作，均通过 `run_as_user` 函数以非 root 权限执行，
#   确保安全和正确的文件所有权。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖)
#   - utils.sh (直接依赖: log_*, display_header_section, _confirm_action,
#     run_as_user, create_backup_and_cleanup)
#   - package_management_utils.sh (直接依赖: is_package_installed, install_pacman_pkg)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。完全重构，替代了旧的、独立的 nano.sh 脚本。
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
# 辅助函数
# ==============================================================================

# _ensure_nano_installed()
# @description: 检查并安装 `nano` 包。如果已安装，则询问是否重新安装。
# @returns: 0 on success, 1 on failure.
_ensure_nano_installed() {
    log_info "Step 1: Checking and ensuring 'nano' editor is installed."
    if is_package_installed "nano"; then
        log_success "'nano' is already installed."
        if _confirm_action "Do you want to force reinstall 'nano' anyway?" "n" "${COLOR_YELLOW}"; then
            log_info "User confirmed. Reinstalling 'nano'..."
            # --overwrite='*' 可以在某些情况下解决文件冲突问题
            if install_pacman_pkg "nano --overwrite='*'"; then
                log_success "'nano' reinstalled successfully."
            else
                log_error "Failed to reinstall 'nano'."
                return 1
            fi
        fi
    else
        log_warn "'nano' is not installed."
        if _confirm_action "Do you want to install 'nano' now?" "y" "${COLOR_YELLOW}"; then
            log_info "User confirmed. Installing 'nano'..."
            if install_pacman_pkg "nano"; then
                log_success "'nano' installed successfully."
            else
                log_error "Failed to install 'nano'."
                return 1
            fi
        fi
    fi
    return 0
}

# _configure_default_editor()
# @description: 引导用户将 nano 设置为默认编辑器，修改 shell 配置文件。
# @returns: 0 on success or user skip, 1 on failure.
_configure_default_editor() {
    log_info "Step 2: Configuring 'nano' as the default system editor (EDITOR/VISUAL)."
    
    if ! _confirm_action "Do you want to set 'nano' as the default editor for user '$ORIGINAL_USER'?" "y" "${COLOR_GREEN}"; then
        log_info "User chose to skip setting 'nano' as the default editor."
        return 0
    fi

    # 检测用户的默认 shell 以确定要修改的配置文件
    local user_shell; user_shell=$(getent passwd "$ORIGINAL_USER" | cut -d: -f7)
    local shell_config_path=""

    case "$user_shell" in
        "/bin/bash")
            shell_config_path="${ORIGINAL_HOME}/.bashrc"
            ;;
        "/bin/zsh")
            shell_config_path="${ORIGINAL_HOME}/.zshrc"
            ;;
        *)
            log_warn "Unsupported shell '$user_shell' for user '$ORIGINAL_USER'. Cannot automatically set default editor."
            log_warn "Please manually add 'export EDITOR=nano' and 'export VISUAL=nano' to your shell configuration file."
            return 0
            ;;
    esac
    log_info "Detected user shell: '$user_shell'. Target configuration file: '$shell_config_path'."

    # 备份 shell 配置文件
    create_backup_and_cleanup "$shell_config_path" "shell_config"

    local -a vars_to_set=("EDITOR=nano" "VISUAL=nano")
    local changes_made=false

    for var_assignment in "${vars_to_set[@]}"; do
        # 使用 run_as_user 安全地检查文件内容
        if ! run_as_user "grep -q \"^export ${var_assignment}\$\" \"${shell_config_path}\""; then
            log_info "Adding 'export ${var_assignment}' to '${shell_config_path}'."
            # 使用 run_as_user 安全地追加内容
            if run_as_user "echo 'export ${var_assignment}' >> \"${shell_config_path}\""; then
                log_success "Successfully added 'export ${var_assignment}'."
                changes_made=true
            else
                log_error "Failed to add 'export ${var_assignment}' to '${shell_config_path}'."
                return 1
            fi
        else
            log_info "'export ${var_assignment}' already exists in '${shell_config_path}'. Skipping."
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
    log_info "Step 3: Configuring '.nanorc' for a better editing experience (syntax highlighting, line numbers, etc.)."

    if ! _confirm_action "Do you want to apply a recommended configuration to '.nanorc' for user '$ORIGINAL_USER'?" "y" "${COLOR_GREEN}"; then
        log_info "User chose to skip '.nanorc' configuration."
        return 0
    fi
    
    local nanorc_path="${ORIGINAL_HOME}/.nanorc"
    log_info "Target configuration file: '$nanorc_path'."

    # 备份 .nanorc 文件
    create_backup_and_cleanup "$nanorc_path" "nanorc"

    # 推荐的配置项
    declare -A nano_options=(
        ["set linenumbers"]="Enable line numbers"
        ["set autoindent"]="Enable auto-indentation"
        ["include /usr/share/nano/*.nanorc"]="Enable syntax highlighting for all languages"
    )

    local changes_made=false
    for option in "${!nano_options[@]}"; do
        local description="${nano_options[$option]}"
        # 使用 run_as_user 安全地检查文件内容，注意转义特殊字符
        local escaped_option; escaped_option=$(sed 's/[&/\]/\\&/g' <<< "$option")
        if ! run_as_user "grep -q \"^${escaped_option}\$\" \"${nanorc_path}\" 2>/dev/null"; then
            log_info "Adding option: '$option' ($description)."
            if run_as_user "echo \"$option\" >> \"${nanorc_path}\""; then
                log_success "Successfully added."
                changes_made=true
            else
                log_error "Failed to add option '$option' to '${nanorc_path}'."
                return 1
            fi
        else
            log_info "Option '$option' already exists in '${nanorc_path}'. Skipping."
        fi
    done

    if [ "$changes_made" = true ]; then
        log_success "Nano configuration in '${nanorc_path}' has been updated."
    else
        log_info "No changes were needed for the '.nanorc' configuration."
    fi
    
    return 0
}

# ==============================================================================
# 主函数
# ==============================================================================
main() {
    display_header_section "Nano Editor Configuration" "box" 80 "${COLOR_BLUE}"
    log_info "This module will guide you through installing and configuring the Nano text editor."

    # Nano 配置主要针对非 root 的普通用户
    if [ "$ORIGINAL_USER" == "root" ]; then
        log_warn "Running as 'root'. User-specific Nano configuration is typically for non-root users."
        if ! _confirm_action "Do you want to proceed with configuring Nano for the 'root' user?" "n" "${COLOR_YELLOW}"; then
            log_info "Skipping Nano configuration for the root user."
            return 0
        fi
    fi

    # 执行各个配置步骤
    if ! _ensure_nano_installed; then
        handle_error "Nano installation step failed. Aborting module."
    fi

    if ! _configure_default_editor; then
        handle_error "Setting Nano as default editor failed. Aborting module."
    fi

    if ! _configure_nanorc; then
        handle_error "Configuring .nanorc failed. Aborting module."
    fi

    log_success "Nano editor configuration completed successfully."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

# 脚本退出处理函数
exit_script() {
    local exit_code=${1:-$?_} # 使用上一个命令的退出码，如果未提供
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Nano Configuration script successfully."
    else
        log_warn "Exiting Nano Configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

# 调用退出函数，传递 main 函数的退出码
exit_script $?