#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/01_configure_mirrors.sh
# 版本: 1.0.0
# 日期: 2025-06-08
# 描述: 配置 Arch Linux 的 Pacman 镜像源。
#       提供自动选择中国镜像源、手动编辑当前镜像列表及恢复备份的功能。
# ------------------------------------------------------------------------------
# 职责:
#   1. 备份当前的 Pacman mirrorlist 文件。
#   2. 使用 reflector 自动生成并优化中国地区的镜像源列表。
#   3. 提供手动编辑 mirrorlist 文件的选项。
#   4. 提供恢复之前备份的 mirrorlist 文件的选项。
#   5. 刷新 Pacman 数据库以应用新的镜像配置。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (提供日志、颜色输出、确认提示等功能)
#   - main_config.sh (提供 PACMAN_MIRRORLIST_PATH, DEFAULT_EDITOR 等配置)
#   - 系统命令: cp, mv, sed, reflector, pacman, date, ls, rm
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现备份、reflector自动配置、手动编辑、恢复备份和刷新数据库功能。
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
# 变量定义
# ==============================================================================

# Pacman 镜像列表文件路径，从 main_config.sh 获取
MIRRORLIST_PATH="${PACMAN_MIRRORLIST_PATH}"
# 备份目录，在 mirrorlist 文件所在目录创建一个 backups 子目录
MIRRORLIST_BACKUP_DIR="$(dirname "$MIRRORLIST_PATH")/backups"

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_mirrorlist()
# 功能: 备份当前的 Pacman mirrorlist 文件。
# 返回: 0 (成功) 或 1 (失败)。
_backup_mirrorlist() {
    log_info "Attempting to back up current Pacman mirrorlist..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        _create_directory_if_not_exists "$MIRRORLIST_BACKUP_DIR" || { log_error "Failed to create backup directory: $MIRRORLIST_BACKUP_DIR"; return 1; }
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${MIRRORLIST_BACKUP_DIR}/mirrorlist.bak.${timestamp}"
        if cp -p "$MIRRORLIST_PATH" "$backup_file"; then
            log_success "Current mirrorlist backed up to: '$backup_file'."
            return 0
        else
            log_error "Failed to back up '$MIRRORLIST_PATH' to '$backup_file'."
            return 1
        fi
    else
        log_warn "Pacman mirrorlist file '$MIRRORLIST_PATH' not found. No backup created."
        return 0 # 没有文件可备份，但不是错误
    fi
}

# _install_reflector_if_missing()
# 功能: 检查并安装 reflector (如果未安装)。
# 返回: 0 (reflector 可用) 或 1 (reflector 不可用)。
_install_reflector_if_missing() {
    log_info "Checking for 'reflector'..."
    if ! command -v reflector &>/dev/null; then
        log_warn "'reflector' is not installed. It is recommended for automatic mirror selection."
        if _confirm_action "Do you want to install 'reflector' now?" "y" "${COLOR_YELLOW}"; then
            if pacman -S --noconfirm reflector; then
                log_success "'reflector' installed successfully."
                return 0
            else
                log_error "Failed to install 'reflector'. Please install it manually or choose another option."
                return 1
            fi
        else
            log_warn "Skipping 'reflector' installation. Automatic mirror selection might not work as expected."
            return 1
        fi
    else
        log_success "'reflector' is already installed."
        return 0
    fi
}

# _generate_china_mirrors()
# 功能: 使用 reflector 自动生成中国地区的镜像列表。
# 返回: 0 (成功) 或 1 (失败)。
_generate_china_mirrors() {
    log_info "Generating new mirrorlist for China using 'reflector'..."

    if ! _install_reflector_if_missing; then
        log_error "Reflector is not available. Cannot automatically generate mirrorlist."
        return 1
    fi

    # 移动旧的 mirrorlist，reflector 不会覆盖现有文件
    if [ -f "$MIRRORLIST_PATH" ]; then
        if ! mv "$MIRRORLIST_PATH" "${MIRRORLIST_PATH}.old"; then
            log_error "Failed to move old mirrorlist aside. Cannot generate new one."
            return 1
        fi
        log_debug "Moved old mirrorlist to ${MIRRORLIST_PATH}.old"
    fi

    # 使用 reflector 生成中国境内的 HTTPS 镜像，并按速度排序，保存为新的 mirrorlist
    # --age 6: 只选择最近6小时内同步过的镜像
    # --protocol https: 只选择 HTTPS 协议的镜像
    # --sort rate: 按下载速率排序
    # --save: 保存到指定文件
    if reflector --country China --age 6 --protocol https --sort rate --save "$MIRRORLIST_PATH"; then
        log_success "New mirrorlist generated successfully at '$MIRRORLIST_PATH'."
        log_notice "Note: Only HTTPS mirrors from China updated within the last 6 hours are included."
        log_info "You might want to manually review '$MIRRORLIST_PATH' for any specific preferences."
        return 0
    else
        log_error "Failed to generate mirrorlist using 'reflector'. Please check your network connection or reflector configuration."
        # 如果 reflector 失败，尝试恢复旧文件
        if [ -f "${MIRRORLIST_PATH}.old" ]; then
            log_warn "Attempting to restore original mirrorlist from ${MIRRORLIST_PATH}.old..."
            if mv "${MIRRORLIST_PATH}.old" "$MIRRORLIST_PATH"; then
                log_success "Original mirrorlist restored."
            else
                log_error "Failed to restore original mirrorlist. Manual intervention may be required."
            fi
        fi
        return 1
    fi
}

# _edit_mirrorlist()
# 功能: 使用默认编辑器手动编辑 mirrorlist 文件。
# 返回: 0 (编辑器退出)
_edit_mirrorlist() {
    log_info "Opening Pacman mirrorlist for manual editing with '$DEFAULT_EDITOR'..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        "$DEFAULT_EDITOR" "$MIRRORLIST_PATH"
        log_info "Finished editing '$MIRRORLIST_PATH'."
        return 0
    else
        log_error "Mirrorlist file '$MIRRORLIST_PATH' not found. Cannot edit."
        return 1
    fi
}

# _restore_mirrorlist_backup()
# 功能: 从备份中恢复 mirrorlist 文件。
# 返回: 0 (成功) 或 1 (失败)。
_restore_mirrorlist_backup() {
    log_info "Searching for Pacman mirrorlist backups in '$MIRRORLIST_BACKUP_DIR'..."
    local backups=($(ls -t "${MIRRORLIST_BACKUP_DIR}"/mirrorlist.bak.* 2>/dev/null || true))

    if [ ${#backups[@]} -eq 0 ]; then
        log_warn "No mirrorlist backups found in '$MIRRORLIST_BACKUP_DIR'."
        return 1
    fi

    log_info "Found the following backups (most recent first):"
    local i=1
    for backup_file in "${backups[@]}"; do
        log_info "  $i) $(basename "$backup_file") (Created: $(stat -c %y "$backup_file" | cut -d'.' -f1))"
        i=$((i + 1))
    done

    local backup_choice
    read -rp "$(echo -e "${COLOR_YELLOW}Enter the number of the backup to restore, or 'c' to cancel: ${COLOR_RESET}")" backup_choice
    echo

    if [[ "$backup_choice" =~ ^[1-9][0-9]*$ ]] && (( backup_choice <= ${#backups[@]} )); then
        local selected_backup="${backups[$((backup_choice - 1))]}"
        if _confirm_action "Are you sure you want to restore '$selected_backup'?" "y" "${COLOR_RED}"; then
            if cp -p "$selected_backup" "$MIRRORLIST_PATH"; then
                log_success "Mirrorlist successfully restored from '$selected_backup'."
                return 0
            else
                log_error "Failed to restore mirrorlist from '$selected_backup'."
                return 1
            fi
        else
            log_info "Backup restoration cancelled."
            return 1
        fi
    elif [[ "$backup_choice" == "c" || "$backup_choice" == "C" ]]; then
        log_info "Backup restoration cancelled by user."
        return 1
    else
        log_warn "Invalid choice. No backup restored."
        return 1
    fi
}

# _refresh_pacman_database()
# 功能: 刷新 Pacman 数据库。
# 返回: 0 (成功) 或 1 (失败)。
_refresh_pacman_database() {
    log_info "Refreshing Pacman database (pacman -Syy)..."
    if pacman -Syy; then
        log_success "Pacman database refreshed successfully."
        return 0
    else
        log_error "Failed to refresh Pacman database. Check your network or mirrorlist configuration."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Pacman Mirror Configuration" "box" 60 "${COLOR_PURPLE}" "${COLOR_BOLD}${COLOR_GREEN}"
    log_info "This script helps you manage your Arch Linux Pacman mirrorlist."
    log_info "Current mirrorlist path: '$MIRRORLIST_PATH'."

    # 1. 备份当前 mirrorlist
    _backup_mirrorlist || log_warn "Mirrorlist backup failed or skipped."

    local choice
    local configured=false

    while true; do
        log_info "Please choose an option for configuring mirrors:"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Automatically select fastest China mirrors (using reflector)"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Manually edit '$MIRRORLIST_PATH'"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} Restore from a previous backup"
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Skip mirror configuration and return to previous menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------${COLOR_RESET}"
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice (0-3): ${COLOR_RESET}")" choice
        echo

        case "$choice" in
            1)
                log_info "Option 1: Automatically select fastest China mirrors."
                if _generate_china_mirrors; then
                    configured=true
                    break # 配置成功，退出循环
                else
                    log_error "Automatic mirror generation failed. Please try again or choose another option."
                fi
                ;;
            2)
                log_info "Option 2: Manually edit '$MIRRORLIST_PATH'."
                if _edit_mirrorlist; then
                    log_success "Manual editing completed. Please ensure your changes are valid."
                    configured=true
                    break # 即使编辑失败，也让用户选择是否刷新数据库
                else
                    log_error "Failed to open editor for mirrorlist. Please check editor configuration."
                fi
                ;;
            3)
                log_info "Option 3: Restore from a previous backup."
                if _restore_mirrorlist_backup; then
                    configured=true
                    break # 恢复成功，退出循环
                else
                    log_warn "Backup restoration failed or cancelled. Returning to mirror options."
                fi
                ;;
            0)
                log_info "Skipping mirror configuration. Returning to previous menu."
                return 0 # 返回到上一级菜单
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please enter a number between 0 and 3."
                ;;
        esac
    done

    # 如果进行了镜像配置 (自动或手动编辑或恢复备份)，则刷新数据库
    if "$configured"; then
        if ! _refresh_pacman_database; then
            handle_error "Failed to refresh Pacman database after mirror configuration. This may cause issues."
        fi
    else
        log_info "Mirror configuration was skipped or unsuccessful. Pacman database not refreshed."
    fi

    log_success "Pacman mirror configuration process completed."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

# 调用主函数
main "$@"

# 脚本退出函数
exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Pacman mirror configuration script."
    exit "$exit_code"
}

# 脚本正常退出
exit_script 0