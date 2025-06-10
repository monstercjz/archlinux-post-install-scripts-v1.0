#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/01_configure_mirrors.sh
# 版本: 1.0.2 (详尽注释与日志优化，遵循最佳实践)
# 日期: 2025-06-08
# 描述: 配置 Arch Linux 的 Pacman 镜像源。
#       提供自动选择中国镜像源、手动编辑当前镜像列表及恢复备份的功能。
# ------------------------------------------------------------------------------
# 核心功能:
# - 备份当前 Pacman mirrorlist 文件。
# - 使用 reflector 自动生成并优化中国地区的镜像源列表。
# - 提供手动编辑 mirrorlist 文件的选项。
# - 提供从备份中恢复 mirrorlist 文件的选项。
# - 刷新 Pacman 数据库以应用新的镜像配置。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (提供日志、颜色输出、确认提示、目录创建 _create_directory_if_not_exists 等基础函数)
#   - package_management_utils.sh (提供 is_package_installed, install_pacman_pkg, refresh_pacman_database)
#   - main_config.sh (提供 PACMAN_MIRRORLIST_PATH, DEFAULT_EDITOR 等配置)
#   - 系统命令: cp, mv, sed, reflector, date, ls, rm, stat
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现备份、reflector自动配置、手动编辑、恢复备份和刷新数据库功能。
# v1.0.1 - 2025-06-08 - 移除重复的刷新数据库函数，改用 `package_management_utils.sh` 中的 `refresh_pacman_database`。
#                       将 `reflector` 的安装逻辑替换为 `package_management_utils.sh` 中的 `install_pacman_pkg`。
# v1.0.2 - 2025-06-08 - 增加详尽的注释，细化日志输出，符合最佳实践标注。
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

# @var string MIRRORLIST_PATH Pacman 镜像列表文件路径，从 main_config.sh 获取。
MIRRORLIST_PATH="${PACMAN_MIRRORLIST_PATH}"
# @var string MIRRORLIST_BACKUP_DIR 备份目录，在 mirrorlist 文件所在目录创建一个 backups 子目录。
MIRRORLIST_BACKUP_DIR="$(dirname "$MIRRORLIST_PATH")/backups"

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_mirrorlist()
# @description: 备份当前的 Pacman mirrorlist 文件。
# @functionality:
#   - 检查 mirrorlist 文件是否存在。
#   - 如果存在，创建备份目录 (如果不存在)。
#   - 使用带时间戳的名称将当前 mirrorlist 复制到备份目录。
# @param: 无
# @returns: 0 on success (backup created or no file to backup), 1 on failure (e.g., cannot create directory or copy file).
# @depends: _create_directory_if_not_exists() (from utils.sh), cp, date (system commands)
_backup_mirrorlist() {
    log_info "Attempting to back up current Pacman mirrorlist from '$MIRRORLIST_PATH'..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        if ! _create_directory_if_not_exists "$MIRRORLIST_BACKUP_DIR"; then
            log_error "Failed to create backup directory: '$MIRRORLIST_BACKUP_DIR'. Cannot backup mirrorlist."
            return 1
        fi
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${MIRRORLIST_BACKUP_DIR}/mirrorlist.bak.${timestamp}"
        if cp -p "$MIRRORLIST_PATH" "$backup_file"; then
            log_success "Current mirrorlist successfully backed up to: '$backup_file'."
            return 0
        else
            log_error "Failed to back up '$MIRRORLIST_PATH' to '$backup_file'. Permissions issue?"
            return 1
        fi
    else
        log_warn "Pacman mirrorlist file '$MIRRORLIST_PATH' not found. No backup created as there's nothing to backup."
        return 0 # 没有文件可备份，但这不被视为错误
    fi
}

# _install_reflector_if_missing()
# @description: 检查并安装 reflector (如果未安装)。
# @functionality:
#   - 使用 `is_package_installed` (来自 package_management_utils.sh) 检查 reflector。
#   - 如果未安装，提示用户是否安装。
#   - 如果用户同意，则使用 `install_pacman_pkg` (来自 package_management_utils.sh) 安装 reflector。
# @param: 无
# @returns: 0 if reflector is available (already installed or successfully installed), 1 if reflector is not available.
# @depends: is_package_installed() (from package_management_utils.sh), install_pacman_pkg() (from package_management_utils.sh),
#           _confirm_action() (from utils.sh), command (Bash 内置命令)
_install_reflector_if_missing() {
    log_info "Checking for 'reflector' utility, which is recommended for automatic mirror selection..."
    if ! is_package_installed "reflector"; then
        log_warn "'reflector' is not currently installed."
        if _confirm_action "Do you want to install 'reflector' now to enable automatic mirror selection?" "y" "${COLOR_YELLOW}"; then
            log_info "Attempting to install 'reflector' via Pacman..."
            if install_pacman_pkg "reflector"; then
                log_success "'reflector' installed successfully."
                return 0
            else
                log_error "Failed to install 'reflector'. Please install it manually if you wish to use automatic mirror selection, or choose another option."
                return 1
            fi
        else
            log_warn "Skipping 'reflector' installation. Automatic mirror selection will not be available."
            return 1
        fi
    else
        log_success "'reflector' is already installed and ready for use."
        return 0
    fi
}

# _generate_china_mirrors()
# @description: 使用 reflector 自动生成中国地区的优化镜像列表。
# @functionality:
#   - 确保 reflector 已安装 (调用 _install_reflector_if_missing)。
#   - 备份旧的 mirrorlist 文件 (将其重命名为 .old)，因为 reflector 不会直接覆盖。
#   - 执行 reflector 命令，筛选中国地区、HTTPS 协议、最近6小时内同步过，并按下载速率排序的镜像。
#   - 将结果保存到 MIRRORLIST_PATH。
#   - 如果 reflector 失败，尝试恢复 .old 备份。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: _install_reflector_if_missing(), cp, mv, reflector (system commands)
_generate_china_mirrors() {
    log_info "Starting process to automatically generate a new mirrorlist for China using 'reflector'..."

    if ! _install_reflector_if_missing; then
        log_error "Reflector is not available. Automatic mirrorlist generation cannot proceed."
        return 1
    fi

    # 移动旧的 mirrorlist，reflector 不会覆盖现有文件
    if [ -f "$MIRRORLIST_PATH" ]; then
        log_debug "Moving existing mirrorlist to '${MIRRORLIST_PATH}.old' before generating a new one."
        if ! mv "$MIRRORLIST_PATH" "${MIRRORLIST_PATH}.old"; then
            log_error "Failed to move old mirrorlist aside. Cannot generate new one. Permissions issue?"
            return 1
        fi
        log_debug "Old mirrorlist moved to '${MIRRORLIST_PATH}.old'."
    fi

    log_info "Executing reflector: --country China --age 6 --protocol https --sort rate --save '$MIRRORLIST_PATH'..."
    if reflector --country China --age 6 --protocol https --sort rate --save "$MIRRORLIST_PATH"; then
        log_success "New mirrorlist generated successfully at '$MIRRORLIST_PATH'."
        log_notice "The new mirrorlist includes fast HTTPS mirrors from China, updated within the last 6 hours."
        log_info "It's recommended to manually review '$MIRRORLIST_PATH' for any specific preferences or uncomment desired mirrors."
        return 0
    else
        log_error "Failed to generate mirrorlist using 'reflector'. This might be due to network issues or reflector misconfiguration."
        log_warn "Attempting to restore original mirrorlist from '${MIRRORLIST_PATH}.old' if it exists..."
        if [ -f "${MIRRORLIST_PATH}.old" ]; then
            if mv "${MIRRORLIST_PATH}.old" "$MIRRORLIST_PATH"; then
                log_success "Original mirrorlist successfully restored from backup."
            else
                log_error "Failed to restore original mirrorlist. Manual intervention for '$MIRRORLIST_PATH' may be required."
            fi
        fi
        return 1
    fi
}

# _edit_mirrorlist()
# @description: 使用默认编辑器手动编辑 mirrorlist 文件。
# @functionality:
#   - 检查 mirrorlist 文件是否存在。
#   - 如果存在，使用 `DEFAULT_EDITOR` (从 main_config.sh) 打开文件。
#   - `DEFAULT_EDITOR` 通常是 nano 或 vim，用户需要手动保存并退出。
# @param: 无
# @returns: 0 on success (editor opened), 1 on failure (file not found).
# @depends: DEFAULT_EDITOR (from main_config.sh), [system editor command (e.g., nano, vim)]
_edit_mirrorlist() {
    log_info "Opening Pacman mirrorlist for manual editing with '$DEFAULT_EDITOR'..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        # 注意: 这里不会检查编辑器命令的退出状态，因为用户可能只是打开查看然后退出，
        # 或者编辑器本身崩溃。由用户自己确保编辑操作的有效性。
        "$DEFAULT_EDITOR" "$MIRRORLIST_PATH"
        log_info "Manual editing session for '$MIRRORLIST_PATH' completed. Please ensure your changes are saved and valid."
        return 0
    else
        log_error "Mirrorlist file '$MIRRORLIST_PATH' not found. Cannot open for editing."
        return 1
    fi
}

# _restore_mirrorlist_backup()
# @description: 从备份中恢复 Pacman mirrorlist 文件。
# @functionality:
#   - 列出 MIRRORLIST_BACKUP_DIR 中所有带有时间戳的备份文件，并按时间倒序排列 (最新在前)。
#   - 提示用户选择一个备份文件进行恢复。
#   - 如果用户确认，则将选定的备份文件复制回 MIRRORLIST_PATH。
# @param: 无
# @returns: 0 on success, 1 on failure (no backups found, invalid choice, or copy fails).
# @depends: _create_directory_if_not_exists() (from utils.sh), _confirm_action() (from utils.sh),
#           ls, stat, cp, date (system commands)
_restore_mirrorlist_backup() {
    log_info "Searching for Pacman mirrorlist backups in '$MIRRORLIST_BACKUP_DIR'..."
    # 使用 `ls -t` 按修改时间倒序排列，`2>/dev/null` 抑制错误，`|| true` 确保即使没有文件也成功
    local backups=($(ls -t "${MIRRORLIST_BACKUP_DIR}"/mirrorlist.bak.* 2>/dev/null || true))

    if [ ${#backups[@]} -eq 0 ]; then
        log_warn "No Pacman mirrorlist backups found in '$MIRRORLIST_BACKUP_DIR'."
        return 1
    fi

    log_info "Found the following backups (most recent first):"
    local i=1
    for backup_file in "${backups[@]}"; do
        # 使用 stat -c %y 获取文件修改时间，并截取到秒
        log_info "  ${COLOR_GREEN}$i)${COLOR_RESET} $(basename "$backup_file") (Created: $(stat -c %y "$backup_file" | cut -d'.' -f1))"
        i=$((i + 1))
    done

    local backup_choice
    read -rp "$(echo -e "${COLOR_YELLOW}Enter the number of the backup to restore, or 'c' to cancel: ${COLOR_RESET}")" backup_choice
    echo # 打印一个换行符，美化输出

    if [[ "$backup_choice" =~ ^[1-9][0-9]*$ ]] && (( backup_choice <= ${#backups[@]} )); then
        local selected_backup="${backups[$((backup_choice - 1))]}"
        if _confirm_action "Are you sure you want to restore '$selected_backup' to '$MIRRORLIST_PATH'?" "y" "${COLOR_RED}"; then
            log_info "Restoring mirrorlist from '$selected_backup'..."
            if cp -p "$selected_backup" "$MIRRORLIST_PATH"; then
                log_success "Mirrorlist successfully restored from '$selected_backup'."
                return 0
            else
                log_error "Failed to restore mirrorlist from '$selected_backup'. Permissions issue?"
                return 1
            fi
        else
            log_info "Backup restoration cancelled by user."
            return 1
        fi
    elif [[ "$backup_choice" == "c" || "$backup_choice" == "C" ]]; then
        log_info "Backup restoration cancelled by user."
        return 1
    else
        log_warn "Invalid choice for backup restoration: '$backup_choice'. No backup was restored."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

# main()
# @description: 脚本的主执行函数，负责 Pacman 镜像配置的流程控制。
# @functionality:
#   - 显示模块标题。
#   - 引导用户进行 Pacman mirrorlist 的备份。
#   - 提供一个循环菜单，让用户选择自动配置、手动编辑或恢复备份。
#   - 根据用户选择调用相应的辅助函数。
#   - 在配置完成后，刷新 Pacman 数据库。
# @param: $@ - 脚本的所有命令行参数。
# @returns: 0 on successful completion of configuration, 1 on critical failure.
# @depends: display_header_section(), _backup_mirrorlist(), _generate_china_mirrors(),
#           _edit_mirrorlist(), _restore_mirrorlist_backup(), refresh_pacman_database()
#           (from package_management_utils.sh), handle_error(), _confirm_action() (from utils.sh)
main() {
    display_header_section "Pacman Mirror Configuration" "box" 60 "${COLOR_PURPLE}" "${COLOR_BOLD}${COLOR_GREEN}"
    log_info "This script assists in managing your Arch Linux Pacman mirrorlist."
    log_info "The current active mirrorlist file is located at: '$MIRRORLIST_PATH'."

    # 1. 备份当前 mirrorlist (作为安全操作的第一步)
    _backup_mirrorlist || log_warn "Initial mirrorlist backup failed or was skipped. Proceeding without a guaranteed restore point for current state."

    local choice            # 用户输入的菜单选择
    local configured=false  # 标志，指示是否成功进行了镜像配置

    # 循环显示菜单直到用户选择退出或配置成功
    while true; do
        log_info "Please choose an option for configuring your Pacman mirrors:"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} Automatically select fastest China mirrors (using reflector)"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} Manually edit '$MIRRORLIST_PATH' with default editor"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} Restore from a previous mirrorlist backup"
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Skip mirror configuration and return to previous menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------${COLOR_RESET}"
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice (0-3): ${COLOR_RESET}")" choice
        echo # 打印一个换行符，美化输出

        case "$choice" in
            1)
                log_info "User selected: Automatically select fastest China mirrors."
                if _generate_china_mirrors; then
                    configured=true
                    break # 镜像生成成功，退出菜单循环
                else
                    log_error "Automatic mirror generation failed. Please try again or choose another configuration option."
                fi
                ;;
            2)
                log_info "User selected: Manually edit '$MIRRORLIST_PATH'."
                if _edit_mirrorlist; then
                    log_success "Manual editing session finished. Please ensure your changes are valid."
                    # 即使手动编辑过程不一定“成功”配置，但已完成交互，可以视为“已尝试配置”
                    configured=true
                    break # 手动编辑完成后，退出菜单循环以进行数据库刷新
                else
                    log_error "Failed to open editor for mirrorlist. This option could not be completed."
                    # 不退出循环，让用户选择其他选项或重试
                fi
                ;;
            3)
                log_info "User selected: Restore from a previous backup."
                if _restore_mirrorlist_backup; then
                    configured=true
                    break # 备份恢复成功，退出菜单循环
                else
                    log_warn "Backup restoration failed or was cancelled. Returning to mirror options."
                    # 不退出循环，让用户选择其他选项或重试
                fi
                ;;
            0)
                log_info "User chose to skip mirror configuration. Returning to the previous menu."
                return 0 # 返回到上一级菜单
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please enter a number between 0 and 3."
                ;;
        esac
    done

    # 如果进行了镜像配置 (无论是自动生成、手动编辑还是恢复备份)，则刷新 Pacman 数据库
    if "$configured"; then
        log_info "Mirror configuration completed. Now refreshing Pacman database to apply changes."
        # 调用 package_management_utils.sh 中的 refresh_pacman_database
        if ! refresh_pacman_database; then
            handle_error "Failed to refresh Pacman database after mirror configuration. This may cause issues with package management." 1
        fi
    else
        log_notice "Mirror configuration was skipped or did not complete successfully. Pacman database was not refreshed."
    fi

    log_success "Pacman mirror configuration process finalized."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

# 调用主函数，传入所有命令行参数
main "$@"

# exit_script()
# @description: 统一的脚本退出处理函数。
# @functionality: 记录退出信息并以指定的退出码终止脚本执行。
# @param: $1 (integer, optional) exit_code - 脚本的退出码 (默认为 0)。
# @returns: Does not return (exits the script).
exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Pacman mirror configuration script with exit code $exit_code."
    exit "$exit_code"
}

# 脚本正常退出
exit_script 0