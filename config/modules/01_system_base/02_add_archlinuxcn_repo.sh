#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/03_add_archlinuxcn_repo.sh
# 版本: 1.0.0
# 日期: 2025-06-08
# 描述: 添加并配置 Arch Linux CN (archlinuxcn) 软件仓库及其 GPG 密钥。
# ------------------------------------------------------------------------------
# 职责:
#   1. 备份当前的 pacman.conf 文件。
#   2. 检查 pacman.conf 中是否已存在 [archlinuxcn] 仓库配置。
#   3. 如果不存在，提示用户添加 [archlinuxcn] 仓库配置块。
#   4. 如果存在但被注释掉，提示用户取消注释并激活。
#   5. 安装 archlinuxcn-keyring 包以导入仓库签名密钥。
#   6. 刷新 Pacman 数据库以应用新的仓库配置。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (提供日志、颜色输出、确认提示等功能)
#   - main_config.sh (提供 PACMAN_CONF_PATH 等配置)
#   - 系统命令: cp, mv, grep, sed, pacman, date
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现 pacman.conf 备份、仓库添加/激活、keyring 安装、数据库刷新。
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

# Pacman 配置文件路径，从 main_config.sh 获取
PACMAN_CONF="${PACMAN_CONF_PATH}"
# 备份目录
PACMAN_CONF_BACKUP_DIR="$(dirname "$PACMAN_CONF")/backups"

# archlinuxcn 仓库的配置块
ARCHLINUXCN_REPO_CONFIG="
[archlinuxcn]
SigLevel = Optional TrustAll
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
"

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_pacman_conf()
# 功能: 备份当前的 pacman.conf 文件。
# 返回: 0 (成功) 或 1 (失败)。
_backup_pacman_conf() {
    log_info "Attempting to back up current Pacman configuration file '$PACMAN_CONF'..."
    if [ -f "$PACMAN_CONF" ]; then
        _create_directory_if_not_exists "$PACMAN_CONF_BACKUP_DIR" || { log_error "Failed to create backup directory: $PACMAN_CONF_BACKUP_DIR"; return 1; }
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${PACMAN_CONF_BACKUP_DIR}/pacman.conf.bak.${timestamp}"
        if cp -p "$PACMAN_CONF" "$backup_file"; then
            log_success "Current '$PACMAN_CONF' backed up to: '$backup_file'."
            return 0
        else
            log_error "Failed to back up '$PACMAN_CONF' to '$backup_file'."
            return 1
        fi
    else
        log_warn "Pacman configuration file '$PACMAN_CONF' not found. No backup created."
        return 0 # 没有文件可备份，但不是错误
    fi
}

# _add_or_activate_archlinuxcn_repo()
# 功能: 添加或激活 pacman.conf 中的 [archlinuxcn] 仓库。
# 返回: 0 (成功) 或 1 (失败)。
_add_or_activate_archlinuxcn_repo() {
    log_info "Checking for [archlinuxcn] repository in '$PACMAN_CONF'..."

    # 检查是否已存在活跃的 [archlinuxcn] 段落
    if grep -q -E "^\s*\[archlinuxcn\]" "$PACMAN_CONF"; then
        if ! grep -q -E "^\s*#\s*\[archlinuxcn\]" "$PACMAN_CONF"; then
            log_notice "ArchlinuxCN repository is already active in '$PACMAN_CONF'. Skipping addition."
            return 0
        else
            log_info "Found commented out [archlinuxcn] repository in '$PACMAN_CONF'."
            if _confirm_action "Do you want to uncomment and activate the [archlinuxcn] repository?" "y" "${COLOR_YELLOW}"; then
                # 使用 sed 激活仓库配置，移除注释
                if sed -i '/^#\s*\[archlinuxcn\]/,/^#\s*Server/s/^#\s*//' "$PACMAN_CONF"; then
                    log_success "ArchlinuxCN repository uncommented and activated in '$PACMAN_CONF'."
                    return 0
                else
                    log_error "Failed to uncomment ArchlinuxCN repository in '$PACMAN_CONF'."
                    return 1
                fi
            else
                log_warn "Skipping activation of [archlinuxcn] repository."
                return 1
            fi
        fi
    fi

    # 如果不存在，则添加
    log_info "ArchlinuxCN repository not found or not active in '$PACMAN_CONF'."
    if _confirm_action "Do you want to add the [archlinuxcn] repository now? (Recommended for Chinese users)" "y" "${COLOR_YELLOW}"; then
        log_info "Appending [archlinuxcn] repository configuration to '$PACMAN_CONF'..."
        # 使用 tee -a 以 root 权限追加内容
        echo "$ARCHLINUXCN_REPO_CONFIG" | sudo tee -a "$PACMAN_CONF" >/dev/null || {
            log_error "Failed to add [archlinuxcn] repository to '$PACMAN_CONF'."
            return 1
        }
        log_success "ArchlinuxCN repository added to '$PACMAN_CONF'."
        return 0
    else
        log_warn "Skipping addition of [archlinuxcn] repository."
        return 1
    fi
}

# _install_archlinuxcn_keyring()
# 功能: 安装 archlinuxcn-keyring 以导入 GPG 密钥。
# 返回: 0 (成功) 或 1 (失败)。
_install_archlinuxcn_keyring() {
    log_info "Installing or updating 'archlinuxcn-keyring' for GPG key import..."

    if pacman -Qq archlinuxcn-keyring &>/dev/null; then
        log_notice "'archlinuxcn-keyring' is already installed. Attempting to update it."
    fi

    # 刷新数据库以确保能找到 archlinuxcn-keyring (如果repo刚添加)
    log_info "Refreshing Pacman database (pacman -Syy) before installing keyring..."
    if ! pacman -Syy; then
        log_error "Failed to refresh Pacman database. Cannot install archlinuxcn-keyring."
        return 1
    fi

    # 安装 archlinuxcn-keyring 包
    if pacman -S --noconfirm archlinuxcn-keyring; then
        log_success "'archlinuxcn-keyring' installed/updated successfully."
        log_notice "The ArchlinuxCN GPG key has been imported."
        return 0
    else
        log_error "Failed to install 'archlinuxcn-keyring'. Manual key import may be required."
        log_error "Please try: 'sudo pacman -S archlinuxcn-keyring' or consult ArchlinuxCN wiki."
        return 1
    fi
}

# _refresh_pacman_database()
# 功能: 刷新 Pacman 数据库。
# 说明: 此函数与 configure_mirrors.sh 中的类似，但在这里重定义以避免不必要的跨文件依赖，
#       或者未来可以将其抽象到一个 `package_management_utils.sh` 中。
# 返回: 0 (成功) 或 1 (失败)。
_refresh_pacman_database() {
    log_info "Refreshing Pacman database (pacman -Syyu) to apply new repository configuration..."
    # 使用 -Syyu 确保从所有仓库更新并同步最新的包列表
    if pacman -Syyu --noconfirm; then # --noconfirm for non-interactive updates
        log_success "Pacman database refreshed and system synced successfully."
        return 0
    else
        log_error "Failed to refresh Pacman database and sync system. Please check your network or repository configuration."
        return 1
    fi
}


# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "ArchlinuxCN Repository Configuration" "box" 70 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_BRIGHT_BLUE}"
    log_info "This script will add and configure the Arch Linux CN repository."
    log_info "This provides easier access to Chinese-specific software and AUR helpers like 'yay' or 'paru'."
    log_info "Pacman configuration file: '$PACMAN_CONF'."

    # 1. 备份当前 pacman.conf
    _backup_pacman_conf || log_warn "Pacman.conf backup failed or skipped. Please review logs."

    local success_status=0

    # 2. 添加或激活 [archlinuxcn] 仓库
    if _add_or_activate_archlinuxcn_repo; then
        log_notice "ArchlinuxCN repository configuration step completed."
        # 3. 安装 archlinuxcn-keyring (只有在仓库被成功添加或激活后才尝试)
        if _install_archlinuxcn_keyring; then
            log_notice "ArchlinuxCN GPG key import step completed."
            # 4. 刷新 Pacman 数据库
            if _refresh_pacman_database; then
                log_success "ArchlinuxCN repository configured and GPG key imported successfully!"
            else
                log_error "Failed to refresh Pacman database after ArchlinuxCN configuration."
                success_status=1
            fi
        else
            log_error "Failed to install archlinuxcn-keyring. ArchlinuxCN repository might not be fully functional without the key."
            success_status=1
        fi
    else
        log_warn "ArchlinuxCN repository was not added or activated. Skipping key import and database refresh for this repository."
        success_status=1
    fi

    if [ "$success_status" -eq 0 ]; then
        log_success "ArchlinuxCN repository setup process completed successfully."
    else
        log_error "ArchlinuxCN repository setup process finished with errors. Please check the logs."
    fi

    return "$success_status"
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

# 调用主函数
main "$@"

# 脚本退出函数
exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting ArchlinuxCN repository configuration script."
    exit "$exit_code"
}

# 脚本正常退出
exit_script 0