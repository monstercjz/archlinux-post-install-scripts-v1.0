#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_user_environment/01_configure_sudo.sh
# 版本: 1.0.1 (增加 sudo 配置文件备份功能)
# 日期: 2025-06-11
# 描述: 为当前非 root 用户配置 sudo 权限，提供免密或需密码选项。
# ------------------------------------------------------------------------------
# 核心功能:
# - 自动为 `ORIGINAL_USER` (调用 sudo 的用户) 配置 sudo 权限。
# - **新增**: 在写入新规则前，自动备份用户已有的 sudo 配置文件。
# - 提供三种配置模式：
#   1. 完全免密 (NOPASSWD: ALL)
#   2. 需要密码 (ALL)
#   3. 为特定命令免密
# - 自动检查并安装 `sudo` 包（如果不存在）。
# - 使用 `visudo` 验证配置文件的语法，确保系统安全。
# - 将配置写入 `/etc/sudoers.d/` 目录，这是管理 sudo 权限的最佳实践。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于获取 `ORIGINAL_USER` 和加载工具函数)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示、错误处理等基础函数)
#   - package_management_utils.sh (直接依赖，用于检查和安装 `sudo` 包)
#   - 系统命令: sudo, visudo, tee, chmod, rm, mkdir, cp, date
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。从旧的独立 sudo.sh 脚本迁移并完全重构。
# v1.0.1 - 2025-06-11 - **在写入新的 sudo 规则之前，增加了对用户现有 sudo 配置文件的备份功能。**
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 这是所有入口脚本最开始执行的代码，用于健壮地确定项目根目录 (BASE_DIR)。
# 无论脚本从哪个位置被调用，都能正确找到项目根目录，从而构建其他文件的绝对路径。

# 严格模式：
set -euo pipefail

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

# ==============================================================================
# 辅助函数
# ==============================================================================

# _ensure_sudo_installed()
# @description: 检查并安装 `sudo` 包（如果未安装）。
# @returns: 0 on success (already installed or successfully installed), 1 on failure.
_ensure_sudo_installed() {
    log_info "Checking if 'sudo' package is installed..."
    if ! is_package_installed "sudo"; then
        log_warn "'sudo' is not installed. It is required for managing user privileges."
        if _confirm_action "Do you want to install 'sudo' now?" "y" "${COLOR_YELLOW}"; then
            log_info "User confirmed. Attempting to install 'sudo' via Pacman..."
            if install_pacman_pkg "sudo"; then
                log_success "'sudo' package installed successfully."
                return 0
            else
                log_error "Failed to install 'sudo'. Cannot proceed with sudo configuration."
                return 1
            fi
        else
            log_warn "User chose to skip 'sudo' installation. Cannot configure sudo privileges."
            return 1
        fi
    else
        log_success "'sudo' is already installed."
        return 0
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Sudo Privileges Configuration" "box" 80
    log_info "This script will configure sudo privileges for the user who invoked this setup: '$ORIGINAL_USER'."

    # 检查 ORIGINAL_USER 是否为 root
    if [ "$ORIGINAL_USER" == "root" ]; then
        log_warn "The original user is 'root'. No sudo configuration is needed for the root user."
        log_notice "If you intended to configure a different user, please run this script using 'sudo -u <username> bash ...' or log in as that user and use 'sudo'."
        return 0
    fi

    # @step 1: 确保 sudo 已安装
    log_info "Step 1: Ensuring the 'sudo' package is installed."
    if ! _ensure_sudo_installed; then
        return 1
    fi

    # @step 2: 引导用户选择 sudo 权限配置
    log_info "Step 2: Please choose the desired sudo permission level for user '$ORIGINAL_USER'."
    echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Allow user to run ALL commands WITHOUT a password (convenient, less secure)."
    echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Allow user to run ALL commands, but require a password (recommended, secure)."
    echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} Allow user to run SPECIFIC commands without a password (advanced)."
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} Skip and do not change sudo configuration."
    
    read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-3, 0 to skip]: ${COLOR_RESET}")" choice
    
    local rule=""
    case "$choice" in
        1)
            rule="$ORIGINAL_USER ALL=(ALL:ALL) NOPASSWD: ALL"
            log_info "User selected: grant full sudo access without password."
            ;;
        2)
            rule="$ORIGINAL_USER ALL=(ALL:ALL) ALL"
            log_info "User selected: grant full sudo access, password required."
            ;;
        3)
            log_info "User selected: grant passwordless sudo for specific commands."
            read -rp "Enter the full path to the commands, separated by spaces (e.g., /usr/bin/pacman /usr/bin/systemctl): " commands
            if [ -z "$commands" ]; then
                log_error "No commands were provided. Aborting."
                return 1
            fi
            # 构建规则，注意逗号分隔
            rule="$ORIGINAL_USER ALL=(ALL:ALL) NOPASSWD: "
            local command_list=$(echo "$commands" | tr ' ' ',')
            rule+="$command_list"
            log_info "Generated rule for specific commands: $rule"
            ;;
        0)
            log_warn "User chose to skip sudo configuration. No changes will be made."
            return 0
            ;;
        *)
            log_error "Invalid choice: '$choice'. Aborting sudo configuration."
            return 1
            ;;
    esac

    # @step 3: 写入 sudoers 配置文件并验证
    log_info "Step 3: Writing and validating the new sudo rule."
    local sudoers_file="/etc/sudoers.d/$ORIGINAL_USER"
    log_info "The following rule will be written to '$sudoers_file':"
    log_summary "  $rule"
    
    if ! _confirm_action "Confirm: Apply this sudo rule?" "y" "${COLOR_RED}"; then
        log_warn "User cancelled the operation. Sudo configuration remains unchanged."
        return 0
    fi
    log_info "User confirmed. Proceeding to write the configuration."

    # 确保 /etc/sudoers.d 目录存在
    if ! _create_directory_if_not_exists "/etc/sudoers.d"; then
        log_error "Failed to create /etc/sudoers.d directory. Cannot proceed."
        return 1
    fi

    # **新增：备份已存在的用户 sudo 配置文件**
    if [ -f "$sudoers_file" ]; then
        local backup_file="${sudoers_file}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Found existing configuration at '$sudoers_file'. Backing it up to '$backup_file'."
        if cp -p "$sudoers_file" "$backup_file"; then
            log_success "Backup of existing sudo configuration created successfully."
        else
            log_error "Failed to back up existing sudo configuration. Aborting to prevent data loss."
            return 1
        fi
    fi

    # 使用 tee 将规则写入文件 (这会覆盖旧文件)
    if ! echo "$rule" | tee "$sudoers_file" >/dev/null; then
        log_error "Failed to write rule to '$sudoers_file'. Check permissions."
        return 1
    fi
    log_success "Rule written to '$sudoers_file'."
    
    # 验证配置文件语法
    log_info "Validating sudoers file syntax with 'visudo -c'..."
    if visudo -c -f "$sudoers_file"; then
        log_success "Sudo configuration file syntax is valid."
    else
        log_error "Sudo configuration file syntax is invalid! This is a critical error."
        log_error "Removing the invalid file '$sudoers_file' to prevent system lockout."
        if rm -f "$sudoers_file"; then
            log_success "Invalid sudoers file removed."
            # 尝试恢复备份
            if [ -n "${backup_file-}" ] && [ -f "$backup_file" ]; then
                log_info "Attempting to restore from backup: '$backup_file'."
                if mv "$backup_file" "$sudoers_file"; then
                    log_success "Successfully restored from backup."
                else
                    log_fatal "Could not restore from backup! The sudo configuration for '$ORIGINAL_USER' is now missing. Please fix it manually!"
                fi
            fi
        else
            log_fatal "Could not remove the invalid sudoers file '$sudoers_file'. Please remove it manually IMMEDIATELY!"
        fi
        return 1
    fi

    # 设置正确的权限
    log_info "Setting correct permissions (440) for '$sudoers_file'..."
    if chmod 440 "$sudoers_file"; then
        log_success "Permissions for '$sudoers_file' set to 440."
    else
        log_error "Failed to set permissions for '$sudoers_file'. Manual intervention required."
        return 1
    fi

    log_success "Sudo privileges for user '$ORIGINAL_USER' have been configured successfully."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

main "$@"

exit_script() {
    local exit_code=${1:-0}
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Sudo Configuration script successfully."
    else
        log_warn "Exiting Sudo Configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

exit_script $?