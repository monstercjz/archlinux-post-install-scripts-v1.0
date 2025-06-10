#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/03_add_archlinuxcn_repo.sh
# 版本: 1.0.2 (详尽注释与日志优化，遵循最佳实践)
# 日期: 2025-06-08
# 描述: 添加并配置 Arch Linux CN (archlinuxcn) 软件仓库及其 GPG 密钥。
# ------------------------------------------------------------------------------
# 核心功能:
#   1. 备份当前的 pacman.conf 文件。
#   2. 检查 pacman.conf 中是否已存在 [archlinuxcn] 仓库配置（活跃或注释掉）。
#   3. 如果不存在，提示用户添加 [archlinuxcn] 仓库配置块。
#   4. 如果存在但被注释掉，提示用户取消注释并激活。
#   5. 安装 archlinuxcn-keyring 包以导入仓库签名密钥。
#   6. 刷新 Pacman 数据库并同步系统以应用新的仓库配置。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (提供日志、颜色输出、确认提示、目录创建 _create_directory_if_not_exists 等基础函数)
#   - package_management_utils.sh (提供 is_package_installed, install_pacman_pkg,
#                                  refresh_pacman_database, sync_system_and_refresh_db 功能)
#   - main_config.sh (提供 PACMAN_CONF_PATH 等配置)
#   - 系统命令: cp, mv, grep, sed, pacman, date, printf, tee
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现 pacman.conf 备份、仓库添加/激活、keyring 安装、数据库刷新。
# v1.0.1 - 2025-06-08 - 移除重复的刷新数据库和系统同步函数，改用 `package_management_utils.sh` 中的相应函数。
#                       将 `archlinuxcn-keyring` 的安装逻辑替换为 `package_management_utils.sh` 中的 `install_pacman_pkg`。
# v1.0.2 - 2025-06-08 - 增加详尽的注释，细化日志输出，符合最佳实践标注。
#                       改进 sed 命令以更可靠地取消注释。
#                       使用 printf 避免 shell 解释 $arch。
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

# @var string PACMAN_CONF Pacman 配置文件路径，从 main_config.sh 获取。
PACMAN_CONF="${PACMAN_CONF_PATH}"
# @var string PACMAN_CONF_BACKUP_DIR 备份目录，在 pacman.conf 文件所在目录创建一个 backups 子目录。
PACMAN_CONF_BACKUP_DIR="$(dirname "$PACMAN_CONF")/backups"

# @var string ARCHLINUXCN_REPO_CONFIG ArchlinuxCN 仓库的配置块。
# 使用 Here-document (<<EOF) 来定义多行字符串，方便配置管理。
# SigLevel = Optional TrustAll: 允许不强制签名校验，为了方便，但生产环境建议更严格。
# Server: 使用中科大镜像源，快速稳定。
ARCHLINUXCN_REPO_CONFIG="
[archlinuxcn]
SigLevel = Optional TrustAll
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
"

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_pacman_conf()
# @description: 备份当前的 pacman.conf 文件。
# @functionality:
#   - 检查 pacman.conf 文件是否存在。
#   - 如果存在，创建备份目录 (如果不存在)。
#   - 使用带时间戳的名称将当前 pacman.conf 复制到备份目录。
# @param: 无
# @returns: 0 on success (backup created or no file to backup), 1 on failure (e.g., cannot create directory or copy file).
# @depends: _create_directory_if_not_exists() (from utils.sh), cp, date (system commands)
_backup_pacman_conf() {
    log_info "Attempting to back up current Pacman configuration file '$PACMAN_CONF'..."
    if [ -f "$PACMAN_CONF" ]; then
        if ! _create_directory_if_not_exists "$PACMAN_CONF_BACKUP_DIR"; then
            log_error "Failed to create backup directory: '$PACMAN_CONF_BACKUP_DIR'. Cannot backup pacman.conf."
            return 1
        fi
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${PACMAN_CONF_BACKUP_DIR}/pacman.conf.bak.${timestamp}"
        if cp -p "$PACMAN_CONF" "$backup_file"; then
            log_success "Current '$PACMAN_CONF' successfully backed up to: '$backup_file'."
            return 0
        else
            log_error "Failed to back up '$PACMAN_CONF' to '$backup_file'. Permissions issue?"
            return 1
        fi
    else
        log_warn "Pacman configuration file '$PACMAN_CONF' not found. No backup created as there's nothing to backup."
        return 0 # 没有文件可备份，但这不被视为错误
    fi
}

# _add_or_activate_archlinuxcn_repo()
# @description: 添加或激活 pacman.conf 中的 [archlinuxcn] 仓库配置。
# @functionality:
#   - 检查 pacman.conf 中是否已存在活跃的 [archlinuxcn] 仓库段落。
#   - 如果已活跃，则跳过。
#   - 如果存在但被注释掉，则提示用户取消注释并激活。
#   - 如果完全不存在，则提示用户添加该仓库配置块。
#   - 使用 `sed -i` 进行文件修改，或 `printf ... | sudo tee -a` 进行追加。
# @param: 无
# @returns: 0 on success (repo added or activated), 1 on failure or user cancellation.
# @depends: _confirm_action() (from utils.sh), grep, sed, printf, tee (system commands)
_add_or_activate_archlinuxcn_repo() {
    log_info "Checking for [archlinuxcn] repository configuration in '$PACMAN_CONF'..."

    # 检查是否已存在活跃的 [archlinuxcn] 段落 (即没有被 '#' 注释掉的行)
    if grep -q -E "^\s*\[archlinuxcn\]" "$PACMAN_CONF" && ! grep -q -E "^\s*#\s*\[archlinuxcn\]" "$PACMAN_CONF"; then
        log_notice "ArchlinuxCN repository is already active in '$PACMAN_CONF'. No action needed."
        return 0
    fi

    # 检查是否以注释形式存在 (即存在被 '#' 注释掉的 [archlinuxcn] 行)
    if grep -q -E "^\s*#\s*\[archlinuxcn\]" "$PACMAN_CONF"; then
        log_info "Found commented-out [archlinuxcn] repository in '$PACMAN_CONF'."
        if _confirm_action "Do you want to uncomment and activate the [archlinuxcn] repository now?" "y" "${COLOR_YELLOW}"; then
            log_info "Attempting to uncomment ArchlinuxCN repository lines in '$PACMAN_CONF'..."
            # 使用 sed 激活仓库配置：从匹配 `[archlinuxcn]` 的注释行开始，到下一个非空或非注释行之前，移除行首的 '#' 和可选的空白。
            # 这是为了处理整个仓库块被注释掉的情况。
            if sed -i '/^#\s*\[archlinuxcn\]/,/^[^#].*/s/^#\s*//' "$PACMAN_CONF"; then
                log_success "ArchlinuxCN repository successfully uncommented and activated in '$PACMAN_CONF'."
                return 0
            else
                log_error "Failed to uncomment ArchlinuxCN repository in '$PACMAN_CONF'. Manual editing of the file may be required."
                return 1
            fi
        else
            log_warn "Skipping activation of [archlinuxcn] repository as per user request."
            return 1
        fi
    fi

    # 如果既不存在活跃形式也不存在注释形式，则添加新的配置块
    log_info "ArchlinuxCN repository configuration not found in '$PACMAN_CONF'. It needs to be added."
    if _confirm_action "Do you want to add the [archlinuxcn] repository now? (Recommended for Chinese users for better software availability)" "y" "${COLOR_YELLOW}"; then
        log_info "Appending [archlinuxcn] repository configuration block to '$PACMAN_CONF'..."
        # 使用 printf 和 sudo tee -a 安全地追加内容到文件。
        # printf 确保 $arch 不会被 shell 提前解释。
        if printf "%s" "$ARCHLINUXCN_REPO_CONFIG" | sudo tee -a "$PACMAN_CONF" >/dev/null; then
            log_success "ArchlinuxCN repository configuration successfully added to '$PACMAN_CONF'."
            return 0
        else
            log_error "Failed to add [archlinuxcn] repository to '$PACMAN_CONF'. Permissions issue?"
            return 1
        fi
    else
        log_warn "Skipping addition of [archlinuxcn] repository as per user request."
        return 1
    fi
}

# _install_archlinuxcn_keyring()
# @description: 安装 archlinuxcn-keyring 包以导入仓库的 GPG 签名密钥。
# @functionality:
#   - 首先刷新 Pacman 数据库，以确保能够找到 archlinuxcn-keyring 包 (特别是当仓库刚添加时)。
#   - 使用 `install_pacman_pkg` (来自 package_management_utils.sh) 安装 archlinuxcn-keyring。
#   - 此包安装后会自动导入所需的 GPG 密钥，允许 Pacman 验证来自 ArchlinuxCN 仓库的包。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: refresh_pacman_database() (from package_management_utils.sh),
#           install_pacman_pkg() (from package_management_utils.sh), pacman (system command)
_install_archlinuxcn_keyring() {
    log_info "Initiating installation/update of 'archlinuxcn-keyring' for GPG key import..."

    # 预先刷新数据库，以确保 Pacman 能找到新添加的仓库及其中的包
    log_info "Refreshing Pacman database to ensure 'archlinuxcn-keyring' is discoverable..."
    if ! refresh_pacman_database; then
        log_error "Failed to refresh Pacman database. Cannot proceed with 'archlinuxcn-keyring' installation."
        return 1
    fi

    # 使用 package_management_utils.sh 中的 install_pacman_pkg 函数安装 keyring
    log_info "Attempting to install 'archlinuxcn-keyring' package..."
    if install_pacman_pkg "archlinuxcn-keyring"; then
        log_success "'archlinuxcn-keyring' installed/updated successfully. The ArchlinuxCN GPG key has been imported."
        return 0
    else
        log_error "Failed to install 'archlinuxcn-keyring'. This means ArchlinuxCN packages might not be verifiable."
        log_error "Manual key import or installation may be required. Please try: 'sudo pacman -S archlinuxcn-keyring'."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

# main()
# @description: 脚本的主执行函数，负责 ArchlinuxCN 仓库配置的流程控制。
# @functionality:
#   - 显示模块标题。
#   - 备份当前的 pacman.conf 文件。
#   - 尝试添加或激活 [archlinuxcn] 仓库配置。
#   - 如果仓库配置成功，则尝试安装 archlinuxcn-keyring。
#   - 最后，执行全面的系统同步和数据库刷新，以应用所有更改。
# @param: $@ - 脚本的所有命令行参数。
# @returns: 0 on successful completion, 1 on any failure during the process.
# @depends: display_header_section(), _backup_pacman_conf(), _add_or_activate_archlinuxcn_repo(),
#           _install_archlinuxcn_keyring(), sync_system_and_refresh_db() (from package_management_utils.sh),
#           log_info(), log_success(), log_error(), log_warn(), log_notice() (from utils.sh)
main() {
    display_header_section "ArchlinuxCN Repository Configuration" "box" 70 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_BRIGHT_BLUE}"
    log_info "This script will add and configure the Arch Linux CN (archlinuxcn) repository."
    log_info "The ArchlinuxCN repository provides many useful Chinese-specific software and convenient AUR helpers."
    log_info "The main Pacman configuration file is: '$PACMAN_CONF'."

    # @step 1: 备份当前 pacman.conf
    _backup_pacman_conf || log_warn "Pacman.conf backup failed or skipped. It's advisable to manually back it up if proceeding."

    local setup_successful=0 # 标志，0表示成功，1表示有错误

    # @step 2: 添加或激活 [archlinuxcn] 仓库配置
    log_info "Proceeding to add or activate the [archlinuxcn] repository."
    if _add_or_activate_archlinuxcn_repo; then
        log_notice "ArchlinuxCN repository configuration step completed."
        
        # @step 3: 安装 archlinuxcn-keyring (只有在仓库被成功添加或激活后才尝试)
        log_info "Repository configured. Now installing 'archlinuxcn-keyring' to import GPG keys."
        if _install_archlinuxcn_keyring; then
            log_notice "ArchlinuxCN GPG key import step completed successfully."
            
            # @step 4: 刷新 Pacman 数据库并同步系统 (使用 -Syyu 进行全面更新)
            log_info "All configurations applied. Performing a full system synchronization (pacman -Syyu)."
            # 使用 package_management_utils.sh 中的 sync_system_and_refresh_db
            if ! sync_system_and_refresh_db; then
                log_error "Failed to refresh Pacman database and synchronize system after ArchlinuxCN configuration."
                setup_successful=1
            fi
        else
            log_error "Failed to install 'archlinuxcn-keyring'. The ArchlinuxCN repository might not be fully functional or verifiable without the key."
            setup_successful=1
        fi
    else
        log_warn "ArchlinuxCN repository was not added or activated as per user choice or due to an error. Skipping key import and system synchronization related to this repository."
        setup_successful=1
    fi

    # 最终总结
    if [ "$setup_successful" -eq 0 ]; then
        log_success "ArchlinuxCN repository setup process completed successfully!"
        log_notice "You can now install packages from the ArchlinuxCN repository, e.g., 'sudo pacman -S yay'."
    else
        log_error "ArchlinuxCN repository setup process finished with some errors. Please review the logs above for details."
    fi

    return "$setup_successful"
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
    log_info "Exiting ArchlinuxCN repository configuration script with exit code $exit_code."
    exit "$exit_code"
}

# 脚本正常退出
exit_script 0