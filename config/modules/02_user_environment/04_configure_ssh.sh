#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_user_environment/04_configure_ssh.sh
# 版本: 1.0.0 (完全重构，适配项目框架)
# 日期: 2025-06-12
# 描述: 提供一个全面的 SSH 服务器 (OpenSSH) 配置流程。
#       此脚本从一个旧的独立脚本完全重构而来，以完美融入当前框架。
# ------------------------------------------------------------------------------
# 核心功能:
# - 提供一个内部菜单，用于管理 SSH 服务的安装、启停和配置。
# - 检查并安装 `openssh` 包。
# - 启动、停止、启用、禁用 `sshd.service` 服务。
# - 提供一个配置子菜单，用于：
#   - 修改 SSH 端口。
#   - 允许/禁止 root 登录。
#   - 启用/禁用密码认证。
#   - 手动编辑 `sshd_config` 文件。
# - 为当前用户生成 SSH 密钥对。
# - 在修改 `sshd_config` 前，使用框架函数进行统一备份和清理。
# - 所有配置修改操作都具有幂等性，并使用更健壮的方式（grep+sed/echo）。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖)
#   - utils.sh (直接依赖)
#   - package_management_utils.sh (直接依赖)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-12 - 初始版本。完全重构，替代了旧的、独立的 ssh.sh 脚本。
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
# 核心功能函数
# ==============================================================================

# _ensure_ssh_installed()
# @description: 检查并安装 `openssh` 包。
_ensure_ssh_installed() {
    display_header_section "Install OpenSSH Server"
    if ! is_package_installed "openssh"; then
        log_warn "'openssh' is not installed."
        if _confirm_action "Do you want to install 'openssh' now?" "y" "${COLOR_YELLOW}"; then
            if ! install_pacman_pkg "openssh"; then
                log_error "Failed to install 'openssh'. Aborting task."
                return 1
            fi
        else
            log_warn "User chose to skip installation. Most SSH functions will not work."
            return 1
        fi
    fi
    log_success "'openssh' is installed."
    return 0
}

# _manage_ssh_service()
# @description: 启动/停止并启用/禁用 sshd 服务。
# @param: $1 (string) - "enable" 或 "disable"
_manage_ssh_service() {
    local action="$1"
    local systemd_start_action="start"
    local systemd_enable_action="enable"
    local display_action="Enable and Start"

    if [[ "$action" == "disable" ]]; then
        systemd_start_action="stop"
        systemd_enable_action="disable"
        display_action="Stop and Disable"
    fi
    
    display_header_section "${display_action} SSH Service (sshd)"
    if ! _confirm_action "Do you want to ${display_action} the sshd service?" "y" "${COLOR_YELLOW}"; then
        log_info "User cancelled."
        return 0
    fi
    
    log_info "Attempting to ${systemd_start_action} sshd.service..."
    if systemctl "${systemd_start_action}" sshd.service; then
        log_success "sshd.service ${systemd_start_action}ed successfully."
    else
        log_error "Failed to ${systemd_start_action} sshd.service."
        # Don't exit, maybe they just want to enable/disable it
    fi

    log_info "Attempting to ${systemd_enable_action} sshd.service for boot..."
    if systemctl "${systemd_enable_action}" sshd.service; then
        log_success "sshd.service ${systemd_enable_action}d successfully."
    else
        log_error "Failed to ${systemd_enable_action} sshd.service."
        return 1
    fi
    return 0
}

# _restart_ssh_service()
# @description: 重启 sshd 服务，通常在配置变更后调用。
_restart_ssh_service() {
    if _confirm_action "A configuration change requires restarting the SSH service. Restart now?" "y" "${COLOR_RED}"; then
        log_info "Restarting sshd.service..."
        if systemctl restart sshd.service; then
            log_success "sshd.service restarted successfully."
        else
            log_error "Failed to restart sshd.service. Please check its status with 'systemctl status sshd'."
        fi
    fi
}

# _set_sshd_config_value()
# @description: 健壮地设置 sshd_config 中的键值对。
# @param: $1 (string) - 配置键 (e.g., "Port")
# @param: $2 (string) - 配置值 (e.g., "2222")
_set_sshd_config_value() {
    local key="$1"
    local value="$2"
    local config_file="/etc/ssh/sshd_config"

    log_info "Setting '$key' to '$value' in '$config_file'..."
    
    # 检查键是否已存在 (忽略注释和大小写)
    if grep -iE "^\s*#?\s*${key}\s+" "$config_file"; then
        # 如果存在，则使用 sed 替换它，同时取消注释
        sed -i -E "s/^\s*#?\s*(${key})\s+.*/\1 ${value}/I" "$config_file"
    else
        # 如果不存在，则在文件末尾追加
        echo "${key} ${value}" >> "$config_file"
    fi
    log_success "Configuration for '$key' updated."
}

# _generate_ssh_key()
# @description: 为当前用户生成 SSH 密钥。
_generate_ssh_key() {
    display_header_section "Generate SSH Key for User '$ORIGINAL_USER'"
    log_info "This will create a new SSH key pair."
    
    local default_key_path="${ORIGINAL_HOME}/.ssh/id_ed25519"
    local key_path
    read -rp "$(echo -e "${COLOR_YELLOW}Enter path to save the key [default: ${default_key_path}]: ${COLOR_RESET}")" key_path
    key_path="${key_path:-${default_key_path}}"
    
    if ! _confirm_action "Generate a new ED25519 SSH key at '${key_path}'?" "y" "${COLOR_GREEN}"; then
        log_info "User cancelled key generation."
        return 0
    fi
    
    # 确保 .ssh 目录存在且权限正确
    run_as_user "mkdir -p \"$(dirname "${key_path}")\" && chmod 700 \"$(dirname "${key_path}")\""

    # 使用 run_as_user 以普通用户身份生成密钥
    log_info "Generating a 4096-bit RSA key. You will be prompted for a passphrase (recommended)."
    if run_as_user "ssh-keygen -t ed25519 -f \"${key_path}\""; then
        log_success "SSH key pair generated successfully at '${key_path}'."
        log_info "Public key is at: ${key_path}.pub. You can now copy it to remote servers."
    else
        log_error "SSH key generation failed."
        return 1
    fi
    return 0
}

# _run_ssh_config_menu()
# @description: 显示并处理 SSH 配置的子菜单。
_run_ssh_config_menu() {
    local config_file="/etc/ssh/sshd_config"
    while true; do
        display_header_section "SSH Configuration Menu" "box"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Change SSH Port"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Toggle Root Login"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} Toggle Password Authentication (for key-only auth)"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} Edit sshd_config manually (with $DEFAULT_EDITOR)"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Back to previous menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        
        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-4, 0]: ${COLOR_RESET}")" choice
        echo

        local config_changed=false
        case "$choice" in
            1)
                read -rp "Enter new SSH port number: " new_port
                if [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]]; then
                    _set_sshd_config_value "Port" "$new_port"
                    config_changed=true
                else
                    log_error "Invalid port number."
                fi
                ;;
            2)
                read -rp "Allow root login? (yes/no): " root_choice
                if [[ "$root_choice" == "yes" || "$root_choice" == "no" ]]; then
                    _set_sshd_config_value "PermitRootLogin" "$root_choice"
                    config_changed=true
                else
                    log_error "Invalid input. Please enter 'yes' or 'no'."
                fi
                ;;
            3)
                read -rp "Disable password authentication (enforce key-only)? (yes/no): " key_choice
                if [[ "$key_choice" == "yes" ]]; then
                    _set_sshd_config_value "PasswordAuthentication" "no"
                    config_changed=true
                elif [[ "$key_choice" == "no" ]]; then
                    _set_sshd_config_value "PasswordAuthentication" "yes"
                    config_changed=true
                else
                    log_error "Invalid input. Please enter 'yes' or 'no'."
                fi
                ;;
            4)
                log_info "Opening '$config_file' with '$DEFAULT_EDITOR'..."
                "$DEFAULT_EDITOR" "$config_file"
                config_changed=true
                ;;
            0)
                log_info "Returning to SSH main menu."
                return 0
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please try again."
                ;;
        esac
        
        if [ "$config_changed" = true ]; then
            _restart_ssh_service
        fi
        read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to return to the SSH config menu...${COLOR_RESET}")"
    done
}

# ==============================================================================
# 主函数 (菜单驱动)
# ==============================================================================
main() {
    display_header_section "SSH Server (OpenSSH) Management" "box" 80 "${COLOR_BLUE}"

    # 主菜单循环
    while true; do
        display_header_section "SSH Main Menu" "box" 80 "${COLOR_PURPLE}"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Install/Verify OpenSSH"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Enable & Start SSH Service"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} Disable & Stop SSH Service"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} Advanced SSH Configuration (Port, Auth, etc.)"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} Generate SSH Key for User '$ORIGINAL_USER'"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Finish and return to the previous menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        
        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-5, 0]: ${COLOR_RESET}")" choice
        echo

        case "$choice" in
            1) _ensure_ssh_installed ;;
            2) _manage_ssh_service "enable" ;;
            3) _manage_ssh_service "disable" ;;
            4)
                create_backup_and_cleanup "/etc/ssh/sshd_config" "sshd_config"
                _run_ssh_config_menu
                ;;
            5) _generate_ssh_key ;;
            0)
                log_info "SSH configuration finished."
                break
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please try again."
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to return to the SSH main menu...${COLOR_RESET}")"
        fi
    done
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

exit_script() {
    local exit_code=${1:-$?_}
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting SSH Management script successfully."
    else
        log_warn "Exiting SSH Management script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}
exit_script $?