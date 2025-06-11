#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/01_configure_mirrors.sh
# 版本: 1.0.6 (最终交互流程优化：先展示后询问)
# 日期: 2025-06-11
# 描述: 配置 Arch Linux 的 Pacman 镜像源。
#       提供自动选择中国镜像源、手动编辑当前镜像列表及恢复备份的功能，并支持备份文件管理。
# ------------------------------------------------------------------------------
# 核心功能:
# - **Pacman Mirrorlist 备份管理**: 自动备份当前镜像列表，并限制备份文件数量，防止过度占用磁盘空间。
#   (通过调用 `utils.sh` 中的 `_cleanup_old_backups` 实现)
# - **Reflector 自动配置**: 检查并安装 `reflector` 工具，使用其自动生成和优化中国地区的 Pacman 镜像源列表。
# - **手动编辑支持**: 提供选项，允许用户使用默认编辑器（如 nano, vim）手动修改 `mirrorlist` 文件，进行精细控制。
# - **备份恢复机制**: 列出所有历史备份，用户可以选择恢复到任何一个之前的状态，确保配置可回溯。
# - **数据库刷新**: 在所有镜像配置操作完成后，刷新 Pacman 数据库，确保更改立即生效。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于环境初始化、全局变量和工具函数加载，如 BASE_DIR, ORIGINAL_USER)
#   - utils.sh (直接依赖，提供日志、颜色输出、通用确认提示 _confirm_action, 目录创建 _create_directory_if_not_exists,
#               以及脚本错误处理 handle_error, 头部显示 display_header_section, **_cleanup_old_backups**)
#   - package_management_utils.sh (直接依赖，提供 is_package_installed, install_pacman_pkg, refresh_pacman_database)
#   - main_config.sh (直接依赖，提供 PACMAN_MIRRORLIST_PATH, DEFAULT_EDITOR, MAX_BACKUP_FILES_MIRRORLIST 等配置)
#   - 系统命令: cp, mv, sed, reflector, date, ls, rm, stat
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现备份、reflector自动配置、手动编辑、恢复备份和刷新数据库功能。
# v1.0.1 - 2025-06-08 - 移除重复的刷新数据库函数，改用 `package_management_utils.sh` 中的 `refresh_pacman_database`。
#                       将 `reflector` 的安装逻辑替换为 `package_management_utils.sh` 中的 `install_pacman_pkg`。
# v1.0.2 - 2025-06-08 - 增加详尽的注释，细化日志输出，符合最佳实践标注。
# v1.0.3 - 2025-06-11 - 新增备份文件清理机制，限制 `mirrorlist` 备份文件数量，防止无限增长。
# v1.0.4 - 2025-06-11 - 增强用户交互：在关键操作时提供明确的确认提示，并记录用户的选择。
#                       所有日志输出更为精准，提供更详细的上下文信息和操作结果提醒。
# v1.0.5 - 2025-06-11 - 将备份清理逻辑 (`_cleanup_old_backups`) 提炼到 `utils.sh` 中，并调整此脚本的调用。
# v1.0.6 - 2025-06-11 - **最终交互流程优化：`main` 函数在开始时检测并展示当前 `mirrorlist` 的状态，然后根据状态询问用户意图。**
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
# @var int MAX_BACKUP_FILES_MIRRORLIST 最大保留的 mirrorlist 备份文件数量，从 main_config.sh 获取。
MAX_BACKUP_FILES_MIRRORLIST="${MAX_BACKUP_FILES_MIRRORLIST:-5}" # 提供默认值以防万一未在 main_config.sh 中定义

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_mirrorlist()
# @description: 备份当前的 Pacman mirrorlist 文件。
# @functionality:
#   - 检查 Pacman `mirrorlist` 文件是否存在于预设路径 (`MIRRORLIST_PATH`)。
#   - 如果存在，则首先创建用于存放备份的目录（如果不存在）。
#   - 使用当前时间戳生成一个唯一的备份文件名，并将当前的 `mirrorlist` 文件复制到该备份路径。
#   - 在成功创建备份后，调用 `_cleanup_old_backups` 函数（来自 `utils.sh`）以保持备份文件数量在限制范围内。
# @param: 无
# @returns: 0 on success (backup created or no file to backup), 1 on failure (e.g., cannot create directory or copy file).
# @depends: _create_directory_if_not_exists() (from utils.sh), cp, date (system commands),
#           _cleanup_old_backups() (from utils.sh), log_info(), log_success(), log_warn(), log_error() (from utils.sh)
_backup_mirrorlist() {
    log_info "Attempting to back up current Pacman mirrorlist from '$MIRRORLIST_PATH'..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        if ! _create_directory_if_not_exists "$MIRRORLIST_BACKUP_DIR"; then
            log_error "Failed to create backup directory: '$MIRRORLIST_BACKUP_DIR'. Cannot proceed with mirrorlist backup."
            return 1
        fi
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${MIRRORLIST_BACKUP_DIR}/mirrorlist.bak.${timestamp}"
        if cp -p "$MIRRORLIST_PATH" "$backup_file"; then
            log_success "Current mirrorlist successfully backed up to: '$backup_file'."
            
            # 在成功备份后，清理旧备份文件
            _cleanup_old_backups "$MIRRORLIST_BACKUP_DIR" "mirrorlist.bak.*" "$MAX_BACKUP_FILES_MIRRORLIST" || \
                log_warn "Failed to cleanup old mirrorlist backup files. This may lead to excessive backup files."
            
            return 0
        else
            log_error "Failed to back up '$MIRRORLIST_PATH' to '$backup_file'. This might be a permissions issue, disk full, or an invalid path."
            return 1
        fi
    else
        log_warn "Pacman mirrorlist file '$MIRRORLIST_PATH' not found. No backup created as there's nothing to backup."
        return 0 # 没有文件可备份，但这不被视为错误
    fi
}

# _install_reflector_if_missing()
# @description: 检查 `reflector` 工具是否已安装，如果未安装则提示用户安装。
# @functionality:
#   - 使用 `is_package_installed` 函数（来自 `package_management_utils.sh`）检查 `reflector` 包的状态。
#   - 如果未安装，通过 `_confirm_action` 提示用户是否继续安装。
#   - 如果用户同意，则使用 `install_pacman_pkg` 函数（来自 `package_management_utils.sh`）执行安装。
# @param: 无
# @returns: 0 if `reflector` is available (already installed or successfully installed), 1 if `reflector` is not available.
# @depends: is_package_installed() (from package_management_utils.sh), install_pacman_pkg() (from package_management_utils.sh),
#           _confirm_action() (from utils.sh), log_info(), log_success(), log_warn(), log_error() (from utils.sh)
_install_reflector_if_missing() {
    log_info "Checking for 'reflector' utility, which is highly recommended for automatic mirror selection..."
    if ! is_package_installed "reflector"; then
        log_warn "'reflector' is not currently installed on your system. Automatic mirror selection requires it."
        if _confirm_action "Do you want to install 'reflector' now to enable automatic mirror selection?" "y" "${COLOR_YELLOW}"; then
            log_info "User chose to install 'reflector'. Attempting installation via Pacman..."
            if install_pacman_pkg "reflector"; then
                log_success "'reflector' installed successfully."
                return 0
            else
                log_error "Failed to install 'reflector'. Automatic mirror selection will not be available."
                log_error "Please install it manually (sudo pacman -S reflector) if you wish to use this feature, or choose another option."
                return 1
            fi
        else
            log_info "User chose to skip 'reflector' installation. Automatic mirror selection will not be performed."
            return 1
        fi
    else
        log_success "'reflector' is already installed and ready for use."
        return 0
    fi
}

# _generate_china_mirrors()
# @description: 使用 `reflector` 自动生成中国地区的优化镜像列表。
# @functionality:
#   - 首先调用 `_install_reflector_if_missing` 确保 `reflector` 工具可用。
#   - 将当前的 `mirrorlist` 文件临时重命名为 `.old` 备份，因为 `reflector` 默认不会覆盖现有文件。
#   - 执行 `reflector` 命令，配置参数以筛选中国地区、HTTPS 协议、最近6小时内同步过，并按下载速率排序的镜像。
#   - 将 `reflector` 的输出直接保存到 `MIRRORLIST_PATH`。
#   - 如果 `reflector` 命令执行失败，尝试将 `.old` 备份文件恢复到原始位置。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: _install_reflector_if_missing() (internal), cp, mv, reflector (system commands),
#           log_info(), log_success(), log_warn(), log_error(), log_notice(), log_debug() (from utils.sh)
_generate_china_mirrors() {
    log_info "Starting process to automatically generate a new mirrorlist for China using 'reflector'..."

    # 确保 reflector 已安装并可用
    if ! _install_reflector_if_missing; then
        log_error "Reflector is not available or could not be installed. Automatic mirrorlist generation cannot proceed."
        return 1
    fi

    # 移动旧的 mirrorlist，因为 reflector 默认不会覆盖现有文件
    if [ -f "$MIRRORLIST_PATH" ]; then
        log_debug "Moving existing mirrorlist to '${MIRRORLIST_PATH}.old' before generating a new one to prevent overwrite conflicts."
        if ! mv "$MIRRORLIST_PATH" "${MIRRORLIST_PATH}.old"; then
            log_error "Failed to move old mirrorlist aside (${MIRRORLIST_PATH} -> ${MIRRORLIST_PATH}.old). Cannot generate new one. Permissions issue?"
            return 1
        fi
        log_debug "Old mirrorlist successfully moved to '${MIRRORLIST_PATH}.old'."
    fi

    log_info "Executing reflector to fetch and rank mirrors: --country China --age 6 --protocol https --sort rate --save '$MIRRORLIST_PATH'..."
    local reflector_output
    if reflector_output=$(reflector --country China --age 6 --protocol https --sort rate --save "$MIRRORLIST_PATH" 2>&1); then
        log_success "New mirrorlist generated successfully at '$MIRRORLIST_PATH'."
        log_info "Reflector output:$(echo -e "\n${reflector_output}")" # 记录 reflector 的详细输出
        log_notice "The new mirrorlist includes fast HTTPS mirrors from China, updated within the last 6 hours."
        log_info "It's highly recommended to manually review '$MIRRORLIST_PATH' for any specific preferences or to uncomment/reorder desired mirrors."
        return 0
    else
        log_error "Failed to generate mirrorlist using 'reflector'."
        log_error "Reflector error output:$(echo -e "\n${reflector_output}")" # 记录 reflector 的错误输出
        log_error "This might be due to network connectivity issues, reflector misconfiguration, or repository server problems."
        log_warn "Attempting to restore original mirrorlist from '${MIRRORLIST_PATH}.old' if it exists to ensure system stability."
        if [ -f "${MIRRORLIST_PATH}.old" ]; then
            if mv "${MIRRORLIST_PATH}.old" "$MIRRORLIST_PATH"; then
                log_success "Original mirrorlist successfully restored from temporary backup."
            else
                log_error "Failed to restore original mirrorlist. Manual intervention for '$MIRRORLIST_PATH' may be required to prevent issues."
            fi
        fi
        return 1
    fi
}

# _edit_mirrorlist()
# @description: 使用默认编辑器手动编辑 mirrorlist 文件。
# @functionality:
#   - 检查 `mirrorlist` 文件是否存在。
#   - 如果存在，利用 `DEFAULT_EDITOR` 环境变量中指定的编辑器（例如 nano, vim）打开该文件供用户修改。
#   - 该函数仅负责打开编辑器，不验证用户在编辑器中的操作结果。用户需自行保存并退出。
# @param: 无
# @returns: 0 on success (editor opened), 1 on failure (file not found or editor error).
# @depends: DEFAULT_EDITOR (from main_config.sh), [system editor command (e.g., nano, vim)],
#           log_info(), log_success(), log_error(), log_notice() (from utils.sh)
_edit_mirrorlist() {
    log_info "Opening Pacman mirrorlist for manual editing using the configured editor: '$DEFAULT_EDITOR'..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        log_notice "Please make your desired changes in the editor. Remember to save and exit to continue the script."
        # 使用 bash -c 确保正确调用编辑器，并捕获其退出状态。
        # 即使编辑器本身没有返回错误，我们也视为用户已完成编辑。
        if bash -c "$DEFAULT_EDITOR '$MIRRORLIST_PATH'"; then
            log_success "Manual editing session for '$MIRRORLIST_PATH' completed."
            log_info "It is crucial to ensure your saved changes are valid and correctly formatted for Pacman."
            return 0
        else
            log_error "Editor '$DEFAULT_EDITOR' exited with an error during manual editing of '$MIRRORLIST_PATH'."
            log_error "This might indicate a problem with the editor itself or how it was used. Please check manually."
            return 1
        fi
    else
        log_error "Mirrorlist file '$MIRRORLIST_PATH' not found. Cannot open for editing."
        log_error "Please ensure Pacman is installed and its mirrorlist exists at the expected path ('$MIRRORLIST_PATH')."
        return 1
    fi
}

# _restore_mirrorlist_backup()
# @description: 从备份中恢复 Pacman mirrorlist 文件。
# @functionality:
#   - 列出 `MIRRORLIST_BACKUP_DIR` 中所有符合 `mirrorlist.bak.*` 命名模式的备份文件。
#   - 备份文件按修改时间倒序排列 (最新在前)，方便用户选择。
#   - 提示用户输入要恢复的备份文件的编号，或选择取消。
#   - 验证用户输入，并在用户确认后，将选定的备份文件复制回 `MIRRORLIST_PATH`。
# @param: 无
# @returns: 0 on success, 1 on failure (no backups found, invalid choice, or copy fails).
# @depends: _create_directory_if_not_exists() (from utils.sh), _confirm_action() (from utils.sh),
#           ls, stat, cp, date (system commands), log_info(), log_success(), log_warn(), log_error() (from utils.sh)
_restore_mirrorlist_backup() {
    log_info "Searching for Pacman mirrorlist backups in '$MIRRORLIST_BACKUP_DIR'..."
    # 使用 `ls -t` 按修改时间倒序排列，`2>/dev/null` 抑制错误，`|| true` 确保即使没有文件也成功
    local backups=($(ls -t "${MIRRORLIST_BACKUP_DIR}"/mirrorlist.bak.* 2>/dev/null || true))

    if [ ${#backups[@]} -eq 0 ] || [ ! -e "${backups[0]}" ]; then
        log_warn "No Pacman mirrorlist backups found in '$MIRRORLIST_BACKUP_DIR'. Cannot perform restoration."
        return 1
    fi

    log_info "Found the following backups (most recent first):"
    local i=1
    for backup_file in "${backups[@]}"; do
        # 使用 stat -c %y 获取文件修改时间，并截取到秒，以提供更友好的显示。
        log_info "  ${COLOR_GREEN}$i)${COLOR_RESET} $(basename "$backup_file") (Created: $(stat -c %y "$backup_file" | cut -d'.' -f1))"
        i=$((i + 1))
    done

    local backup_choice
    read -rp "$(echo -e "${COLOR_YELLOW}Enter the number of the backup to restore, or 'c' to cancel: ${COLOR_RESET}")" backup_choice
    echo # 打印一个换行符，美化输出

    if [[ "$backup_choice" =~ ^[1-9][0-9]*$ ]] && (( backup_choice >= 1 && backup_choice <= ${#backups[@]} )); then
        local selected_backup="${backups[$((backup_choice - 1))]}" # 数组索引从0开始
        log_info "User selected to restore backup: '$selected_backup'."
        if _confirm_action "Are you sure you want to restore '$selected_backup' to '$MIRRORLIST_PATH'? This action will overwrite the current mirrorlist and cannot be undone easily." "y" "${COLOR_RED}"; then
            log_info "User confirmed restoration. Proceeding to restore mirrorlist from '$selected_backup'..."
            if cp -p "$selected_backup" "$MIRRORLIST_PATH"; then
                log_success "Mirrorlist successfully restored from '$selected_backup'."
                return 0
            else
                log_error "Failed to restore mirrorlist from '$selected_backup'. This might be a permissions issue or an invalid path."
                log_error "Manual restoration from '$selected_backup' to '$MIRRORLIST_PATH' might be necessary."
                return 1
            fi
        else
            log_info "User cancelled restoration of backup: '$selected_backup'."
            return 1
        fi
    elif [[ "$backup_choice" == "c" || "$backup_choice" == "C" ]]; then
        log_info "User explicitly cancelled backup restoration."
        return 1
    else
        log_warn "Invalid choice for backup restoration: '$backup_choice'. Please enter a valid number or 'c' to cancel. No backup was restored."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

# main()
# @description: 脚本的主执行函数，负责 Pacman 镜像配置的整体流程控制。
# @functionality:
#   - 显示模块标题，告知用户脚本的目的。
#   - 在所有操作之前，强制进行当前 `mirrorlist` 文件的备份，确保可回溯性。
#   - 提供一个循环菜单，让用户选择自动配置（使用 `reflector`）、手动编辑或恢复之前的备份。
#   - 根据用户的有效选择，调用相应的辅助函数来执行具体操作。
#   - 在任何成功的镜像配置操作完成后，强制刷新 Pacman 数据库，以确保新的镜像配置立即生效。
#   - 如果用户选择跳过配置或配置过程中发生错误，则优雅地处理，并返回适当的状态码。
# @param: $@ - 脚本的所有命令行参数，此处通常不直接使用，但保留传递习惯。
# @returns: 0 on successful completion of configuration or user exit, 1 on critical failure during the process.
# @depends: display_header_section(), _backup_mirrorlist(), _generate_china_mirrors(),
#           _edit_mirrorlist(), _restore_mirrorlist_backup(), refresh_pacman_database()
#           (from package_management_utils.sh), handle_error(), _confirm_action() (from utils.sh)
main() {
    display_header_section "Pacman Mirror Configuration" "box" 60 "${COLOR_PURPLE}" "${COLOR_BOLD}${COLOR_GREEN}"
    log_info "This script assists in managing your Arch Linux Pacman mirrorlist (`$MIRRORLIST_PATH`)."
    log_info "Proper mirror configuration is crucial for fast and reliable package management."

    # @step 1: 检测并展示当前 mirrorlist 状态
    log_info "Step 1: Analyzing current mirrorlist status..."
    if [ -f "$MIRRORLIST_PATH" ]; then
        local active_mirrors=$(grep -v '^#' "$MIRRORLIST_PATH" | grep -c '^Server')
        log_notice "Current mirrorlist contains $active_mirrors active server(s)."
        log_info "Top 3 active servers:"
        grep -v '^#' "$MIRRORLIST_PATH" | grep '^Server' | head -n 3
    else
        log_warn "Pacman mirrorlist file '$MIRRORLIST_PATH' not found. This is unusual. It's recommended to generate a new one."
    fi

    # @step 2: 询问用户是否要进行配置
    if ! _confirm_action "Do you want to proceed with configuring the mirrorlist?" "y" "${COLOR_YELLOW}"; then
        log_warn "User chose to skip mirrorlist configuration. No changes will be made."
        return 0
    fi
    log_info "User confirmed to proceed. Starting configuration process."

    # @step 3: 备份当前 mirrorlist (只有在用户确认后才备份)
    log_info "Step 3: Attempting to back up the current Pacman mirrorlist before any changes are made."
    _backup_mirrorlist || { log_error "Backup failed, aborting to prevent data loss."; return 1; }

    local choice            # 存储用户从菜单中选择的选项
    local configured=false  # 标志，设置为 `true` 表示已成功进行了镜像配置（无论通过何种方式）

    # 循环显示菜单，直到用户选择退出（'0'）或某个配置操作成功完成
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
                log_info "User selected: Option 1 - Automatically select fastest China mirrors."
                if _confirm_action "Confirm: Generate new mirrorlist with reflector? This action will replace your current mirrorlist." "y" "${COLOR_YELLOW}"; then
                    log_info "User confirmed automatic mirror generation. Proceeding with reflector."
                    if _generate_china_mirrors; then
                        configured=true # 镜像成功生成
                        break           # 退出菜单循环，进入最终的数据库刷新步骤
                    else
                        log_error "Automatic mirror generation failed. Please review the log and try again or choose another configuration option."
                    fi
                else
                    log_info "User cancelled automatic mirror generation. Returning to mirror options."
                fi
                ;;
            2)
                log_info "User selected: Option 2 - Manually edit '$MIRRORLIST_PATH'."
                if _confirm_action "Confirm: Open '$MIRRORLIST_PATH' for manual editing? You will need to save and exit the editor yourself." "y" "${COLOR_YELLOW}"; then
                    log_info "User confirmed manual editing. Opening editor."
                    if _edit_mirrorlist; then
                        log_success "Manual editing session finished."
                        configured=true # 视为已尝试配置
                        break           # 退出菜单循环
                    else
                        log_error "Failed to open editor for mirrorlist or editor exited with an error. This option could not be completed."
                    fi
                else
                    log_info "User cancelled manual editing. Returning to mirror options."
                fi
                ;;
            3)
                log_info "User selected: Option 3 - Restore from a previous backup."
                if _restore_mirrorlist_backup; then
                    configured=true # 备份成功恢复
                    break           # 退出菜单循环
                else
                    log_warn "Backup restoration failed or was cancelled. Returning to mirror configuration options."
                fi
                ;;
            0)
                log_info "User chose Option 0 - Skip mirror configuration. Returning to the previous menu."
                return 0 # 脚本正常退出，返回到上一级菜单
                ;;
            *)
                log_warn "Invalid choice: '$choice'. Please enter a number between 0 and 3 to select an action."
                ;;
        esac
    done

    # @step 4: 刷新 Pacman 数据库 (仅当镜像配置成功完成时)
    if "$configured"; then
        log_info "Mirror configuration completed. Now performing a Pacman database refresh (`pacman -Syy`) to apply changes."
        if ! refresh_pacman_database; then
            handle_error "Failed to refresh Pacman database after mirror configuration. This may cause significant issues with package management." 1
        fi
    fi

    log_success "Pacman mirror configuration process finalized successfully."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

# 调用主函数，并根据其返回值决定脚本的最终退出码
main "$@"

# exit_script()
# @description: 统一的脚本退出处理函数。
# @functionality: 记录退出信息并以指定的退出码终止脚本执行。
# @param: $1 (integer, optional) exit_code - 脚本的退出码 (默认为 0)。
# @returns: Does not return (exits the script).
exit_script() {
    local exit_code=${1:-0}
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Pacman mirror configuration script successfully."
    else
        log_warn "Exiting Pacman mirror configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

# 脚本退出
exit_script $?