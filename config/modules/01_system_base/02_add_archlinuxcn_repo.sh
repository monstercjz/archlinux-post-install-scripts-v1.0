#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/02_add_archlinuxcn_repo.sh
# 版本: 1.0.13 (最终交互流程优化：先展示后询问)
# 日期: 2025-06-11
# 描述: 添加并配置 Arch Linux CN (archlinuxcn) 软件仓库及其 GPG 密钥。
# ------------------------------------------------------------------------------
# 核心功能:
#   1. **pacman.conf 备份管理**: 自动备份 Pacman 配置文件，并限制备份文件数量，防止过度占用磁盘空间。
#      (通过调用 `utils.sh` 中的 `_cleanup_old_backups` 实现)
#   2. **[archlinuxcn] 仓库智能配置**:
#      - 检测 `pacman.conf` 中 `[archlinuxcn]` 仓库的当前状态（活跃或注释掉）。
#      - 如果已活跃，允许用户修改其镜像源。
#      - 如果被注释，提示用户取消注释激活。
#      - 如果不存在，提示用户添加新配置块，并提供多个国内镜像源选择。
#   3. **GPG 密钥自动导入**: 自动安装 `archlinuxcn-keyring` 包，导入必要的 GPG 密钥，确保软件包的完整性和安全性。
#   4. **系统同步与数据库刷新**: 在所有配置完成后，执行全面的 `pacman -Syyu` 操作，确保新仓库生效并系统软件包保持最新。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于环境初始化、全局变量和工具函数加载，如 BASE_DIR, ORIGINAL_USER)
#   - utils.sh (直接依赖，提供日志、颜色输出、通用确认提示 _confirm_action, 目录创建 _create_directory_if_not_exists,
#               以及脚本错误处理 handle_error, 头部显示 display_header_section, _cleanup_old_backups)
#   - package_management_utils.sh (直接依赖，提供 is_package_installed, install_pacman_pkg,
#                                  refresh_pacman_database, sync_system_and_refresh_db 功能)
#   - main_config.sh (直接依赖，提供 PACMAN_CONF_PATH, MAX_BACKUP_FILES_PACMAN_CONF 等配置)
#   - 系统命令: cp, mv, grep, sed, pacman, date, printf, tee, rm, ls, stat
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。实现 pacman.conf 备份、仓库添加/激活、keyring 安装、数据库刷新。
# v1.0.1 - 2025-06-08 - 移除重复的刷新数据库和系统同步函数，改用 `package_management_utils.sh` 中的相应函数。
#                       将 `archlinuxcn-keyring` 的安装逻辑替换为 `package_management_utils.sh` 中的 `install_pacman_pkg`。
# v1.0.2 - 2025-06-08 - 增加详尽的注释，细化日志输出，符合最佳实践标注。改进 sed 命令以更可靠地取消注释。
#                       使用 printf 避免 shell 解释 $arch。
# v1.0.3 - 2025-06-11 - 添加备份文件清理机制，限制备份文件数量。优化仓库配置检测逻辑，增加镜像源选择功能。
#                       改进用户交互，提供更详细的操作提示。
# v1.0.4 - 2025-06-11 - 所有函数和主流程的注释更加全面和标准化，日志输出更为精确。
#                       修正 _add_or_activate_archlinuxcn_repo 中移除现有配置的 sed 命令，使其更精确。
# v1.o.5 - 2025-06-11 - 增强用户交互：在关键操作时提供明确的确认提示，并记录用户的选择。
#                       所有日志输出更为精准，提供更详细的上下文信息和操作结果提醒。
#                       修正了 `_add_or_activate_archlinuxcn_repo` 中移除已有配置的 `sed` 逻辑，使其更安全。
# v1.0.6 - 2025-06-11 - 将备份清理逻辑 (`_cleanup_old_backups`) 提炼到 `utils.sh` 中，并调整此脚本的调用。
# v1.0.7 - 2025-06-11 - 修复重复添加 `[archlinuxcn]` 仓库的问题。
#                       优化 `_remove_all_archlinuxcn_blocks` 函数，使其能更彻底、准确地移除所有 `[archlinuxcn]` 配置块（包括重复的和注释掉的），确保文件干净。
#                       调整 `_add_or_activate_archlinuxcn_repo` 逻辑，优先删除所有 `[archlinuxcn]` 再添加。
# v1.0.8 - 2025-06-11 - 彻底修复由于 `sed` 命令在删除多行块时可能留下的空行或未完全删除的问题。
#                       `_remove_all_archlinuxcn_blocks` 现在使用更高级的 `sed` 模式，确保删除从 `[archlinuxcn]` 开始到下一个仓库定义或文件末尾的所有内容。
#                       确保在追加新内容前，文件末尾有至少两个空行，以提供清晰分隔。
# v1.0.9 - 2025-06-11 - 最终修复 `_remove_all_archlinuxcn_blocks` 中 `sed` 导致卡住和重复添加的问题。
#                       采用更简单、更鲁棒的 `sed` 删除策略：分步删除所有包含 `[archlinuxcn]`、`SigLevel` 或 `Server` 的行。
#                       修正了 `_remove_all_archlinuxcn_blocks` 中文件末尾添加空行的逻辑，确保总是有足够的空行且不重复添加。
# v1.0.10 - 2025-06-11 - 最终修复用户交互流程：将破坏性的删除操作置于用户确认之后，避免意外删除用户配置。
# v1.0.11 - 2025-06-11 - 最终修复：区分用户取消操作和实际错误。
#                        `_add_or_activate_archlinuxcn_repo` 现在在用户取消时返回 2，`main` 函数据此决定是否将此视为错误。
# v1.0.12 - 2025-06-11 - 彻底修复用户交互流程。`main` 函数在开始时询问用户是否要继续，而不是依赖子函数的返回值来判断用户意图。
# v1.0.13 - 2025-06-11 - **最终交互流程优化：`main` 函数在开始时检测并展示当前配置状态，然后根据状态询问用户意图，避免了所有逻辑漏洞。**
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
PACMANCONF="pacnman_conf"
# @var string PACMAN_CONF_BACKUP_DIR 备份目录，在 pacman.conf 文件所在目录创建一个 backups 子目录。
PACMAN_CONF_BACKUP_DIR="${GLOBAL_BACKUP_ROOT}/${PACMANCONF}"
# @var int MAX_BACKUP_FILES_PACMAN_CONF 最大保留的 pacman.conf 备份文件数量，从 main_config.sh 获取。
MAX_BACKUP_FILES_PACMAN_CONF="${MAX_BACKUP_FILES_PACMAN_CONF:-5}" # 提供默认值以防万一未在 main_config.sh 中定义

# @var string ARCHLINUXCN_REPO_CONFIG ArchlinuxCN 仓库的配置块模板。
# 此变量的值将根据用户选择的镜像源在运行时动态更新。
# SigLevel = Optional TrustAll: 允许不强制签名校验，为了方便，但生产环境建议更严格。
# Server: 占位符 `%s`，由 `_select_mirror` 函数填充。
ARCHLINUXCN_REPO_CONFIG="
[archlinuxcn]
SigLevel = Optional TrustAll
Server = %s
"

# @var string MIRROR_USTC 中国科学技术大学 ArchlinuxCN 镜像源地址。
MIRROR_USTC="https://mirrors.ustc.edu.cn/archlinuxcn/\$arch"
# @var string MIRROR_TSINGHUA 清华大学 ArchlinuxCN 镜像源地址。
MIRROR_TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch"
# @var string MIRROR_DLUT 大连理工大学 ArchlinuxCN 镜像源地址。
MIRROR_DLUT="https://mirror.dlut.edu.cn/archlinuxcn/\$arch"
# @var string SELECTED_ARCHLINUXCN_MIRROR 存储用户最终选择的 ArchlinuxCN 镜像源地址。
# 默认选择中科大，可以在用户未选择时作为fallback。
SELECTED_ARCHLINUXCN_MIRROR="$MIRROR_USTC" 

# ==============================================================================
# 辅助函数
# ==============================================================================

# _backup_pacman_conf()
# @description: 备份当前的 pacman.conf 文件。
# @functionality:
#   - 检查 Pacman 配置文件是否存在于预设路径 (`PACMAN_CONF`)。
#   - 如果存在，则首先创建用于存放备份的目录（如果不存在）。
#   - 使用当前时间戳生成一个唯一的备份文件名，并将当前的 `pacman.conf` 文件复制到该备份路径。
#   - 在成功创建备份后，调用 `_cleanup_old_backups` 函数（来自 `utils.sh`）以保持备份文件数量在限制范围内。
# @param: 无
# @returns: 0 on success (backup created or no file to backup), 1 on failure (e.g., cannot create directory or copy file).
# @depends: _create_directory_if_not_exists() (from utils.sh), cp, date (system commands),
#           _cleanup_old_backups() (from utils.sh), log_info(), log_success(), log_warn(), log_error() (from utils.sh)
_backup_pacman_conf() {
    # log_info "Attempting to back up current Pacman configuration file '$PACMAN_CONF'..."
    # if [ -f "$PACMAN_CONF" ]; then
    #     if ! _create_directory_if_not_exists "$PACMAN_CONF_BACKUP_DIR"; then
    #         log_error "Failed to create backup directory: '$PACMAN_CONF_BACKUP_DIR'. Cannot proceed with pacman.conf backup."
    #         return 1
    #     fi
    #     local timestamp=$(date +%Y%m%d_%H%M%S)
    #     local backup_file="${PACMAN_CONF_BACKUP_DIR}/pacman.conf.bak.${timestamp}"
    #     if cp -p "$PACMAN_CONF" "$backup_file"; then
    #         log_success "Current '$PACMAN_CONF' successfully backed up to: '$backup_file'."
            
    #         # 在成功备份后，清理旧备份文件
    #         _cleanup_old_backups "$PACMAN_CONF_BACKUP_DIR" "pacman.conf.bak.*" "$MAX_BACKUP_FILES_PACMAN_CONF" || \
    #             log_warn "Failed to cleanup old pacman.conf backup files. This may lead to excessive backup files."
            
    #         return 0
    #     else
    #         log_error "Failed to back up '$PACMAN_CONF' to '$backup_file'. This might be a permissions issue, disk full, or an invalid path."
    #         return 1
    #     fi
    # else
    #     log_warn "Pacman configuration file '$PACMAN_CONF' not found. No backup created as there's nothing to backup."
    #     return 0 # 没有文件可备份，但这不被视为错误
    # fi
    if create_backup_and_cleanup "$PACMAN_CONF" "$PACMANCONF"; then
        # 备份成功，函数可以成功返回
        return 0
    else
        # 备份失败，create_backup_and_cleanup 内部已经记录了详细错误。
        # 此处只需记录一个概要错误，并向上层返回失败状态。
        log_error "The backup process for repo failed. See previous logs for details."
        return 1
    fi
}

# _select_mirror()
# @description: 提示用户选择 ArchlinuxCN 仓库的镜像源，并更新 `SELECTED_ARCHLINUXCN_MIRROR` 变量。
# @functionality:
#   - 显示一个包含多个国内 ArchlinuxCN 镜像源的列表供用户选择。
#   - 捕获用户输入，并根据选择更新全局变量 `SELECTED_ARCHLINUXCN_MIRROR`。
#   - 如果用户输入无效，则保留默认选择（中科大）并记录。
# @param: 无
# @returns: 0 on success (user made a valid selection or kept default), 1 on error (e.g., unexpected input, although rarely happens here).
# @depends: log_info(), log_success(), log_warn(), log_debug() (from utils.sh)
_select_mirror() {
    log_info "Please choose your preferred ArchlinuxCN mirror source for the repository configuration:"
    
    local mirror_options=(
        "1. China University of Science and Technology (USTC): ${MIRROR_USTC}"
        "2. Tsinghua University (Tsinghua): ${MIRROR_TSINGHUA}"
        "3. Dalian University of Technology (DLUT): ${MIRROR_DLUT}"
        "4. Keep current selected or default (USTC)"
    )
    
    # 显示所有可用的镜像源选项
    for option in "${mirror_options[@]}"; do
        echo -e "  ${COLOR_CYAN}$option${COLOR_RESET}"
    done
    
    local choice
    read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-4, default: 4]: ${COLOR_RESET}")" choice
    echo # 美化输出，添加换行符

    case "$choice" in
        1)
            SELECTED_ARCHLINUXCN_MIRROR="$MIRROR_USTC"
            log_success "User selected ArchlinuxCN mirror: China University of Science and Technology (USTC)."
            ;;
        2)
            SELECTED_ARCHLINUXCN_MIRROR="$MIRROR_TSINGHUA"
            log_success "User selected ArchlinuxCN mirror: Tsinghua University (Tsinghua)."
            ;;
        3)
            SELECTED_ARCHLINUXCN_MIRROR="$MIRROR_DLUT"
            log_success "User selected ArchlinuxCN mirror: Dalian University of Technology (DLUT)."
            ;;
        4|*) # 默认或无效输入，保持中科大
            log_info "User chose to keep the default ArchlinuxCN mirror: China University of Science and Technology (USTC)."
            SELECTED_ARCHLINUXCN_MIRROR="$MIRROR_USTC"
            ;;
    esac
    
    return 0
}

# _remove_all_archlinuxcn_blocks()
# @description: 从 pacman.conf 中彻底删除所有 [archlinuxcn] 仓库的配置块，包括重复的和注释掉的。
# @functionality:
#   - **核心逻辑**: 使用 `sed` 命令分步且鲁棒地删除 `[archlinuxcn]` 配置块。
#     1. 删除所有包含 `Server = ...` 的行。
#     2. 删除所有包含 `SigLevel = ...` 的行。
#     3. 删除所有包含 `[archlinuxcn]` (活跃或注释掉) 的行。
#   - 在删除特定内容行之后，清理由此产生的多余空白行，确保文件中没有连续超过一个的空行。
#   - 最后，确保文件末尾有至少两个空行，以提供清晰的分隔，方便后续追加。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: sed, grep, tail, tee (system commands), log_debug(), log_error() (from utils.sh)
_remove_all_archlinuxcn_blocks() {
    log_debug "Attempting to remove all existing [archlinuxcn] blocks (active or commented) from '$PACMAN_CONF'."
    
    local removal_failed=0

    # Step 1: Aggressively remove all lines containing `Server = ...`
    log_debug "Removing all lines containing 'Server = '..."
    if ! sed -i -E '/^\s*Server\s*=/d' "$PACMAN_CONF"; then
        log_warn "Sed failed to remove 'Server = ' lines. This might be a temporary issue or file is empty."
        removal_failed=1
    fi

    # Step 2: Aggressively remove all lines containing `SigLevel = ...`
    log_debug "Removing all lines containing 'SigLevel = '..."
    if ! sed -i -E '/^\s*SigLevel\s*=/d' "$PACMAN_CONF"; then
        log_warn "Sed failed to remove 'SigLevel = ' lines. This might be a temporary issue or file is empty."
        removal_failed=1
    fi

    # Step 3: Aggressively remove all lines containing `[archlinuxcn]` (active or commented)
    log_debug "Removing all lines containing '[archlinuxcn]' header..."
    if ! sed -i -E '/^\s*#?\[archlinuxcn\]/d' "$PACMAN_CONF"; then
        log_warn "Sed failed to remove '[archlinuxcn]' header lines. This might be a temporary issue or file is empty."
        removal_failed=1
    fi

    if [ "$removal_failed" -ne 0 ]; then
        log_error "Some parts of [archlinuxcn] configuration could not be fully removed from '$PACMAN_CONF'. Manual inspection is highly recommended."
        return 1
    fi
    log_success "All specific [archlinuxcn] related lines (headers, SigLevel, Server) have been removed from '$PACMAN_CONF'."


    # Step 4: Clean up any resulting consecutive blank lines
    # This sed command removes all consecutive blank lines, leaving only one blank line.
    # Pattern `^\s*$/N;/^\s*\n\s*$/D` means:
    # `^\s*$` : if line is empty (contains only whitespace or nothing)
    # `N`     : append the next line to the pattern space (now we have two lines in buffer)
    # `^\s*\n\s*$` : if the buffer (two lines) contains two empty lines (separated by newline `\n`)
    # `D`     : delete up to the first newline (effectively deleting the first empty line), and restart cycle with remaining second line.
    log_debug "Cleaning up excess blank lines after content removal to leave only single blank lines."
    if ! sed -i '/^\s*$/N;/^\s*\n\s*$/D' "$PACMAN_CONF"; then
        log_warn "Failed to remove excess blank lines from '$PACMAN_CONF'. File formatting might be inconsistent."
    fi

    # Step 5: Ensure file ends with at least two blank lines for clean appending
    # Read the last few lines, count actual non-blank lines.
    # Use '|| true' with `tail` and `grep` to prevent `set -e` from exiting if file is empty or only blank lines.
    local last_two_non_blank_lines=$(tail -n 3 "$PACMAN_CONF" | grep -v '^\s*$' || true)
    local num_non_blank_at_end=$(echo "$last_two_non_blank_lines" | wc -l)
    
    # If the file is not empty and its last meaningful content is not followed by enough newlines.
    # Note: `echo "" | tee -a` will always add a newline.
    if [ "$num_non_blank_at_end" -gt 0 ] || [ $(wc -l < "$PACMAN_CONF") -eq 0 ]; then # If file has content or is empty, ensure padding
        local current_lines=$(wc -l < "$PACMAN_CONF")
        local desired_lines_after_content=$((current_lines + 2)) # Want total lines = current lines + 2 new blank lines
        
        # Count actual current lines and add until we have enough
        local count_current_lines=$(wc -l < "$PACMAN_CONF")
        if [ "$count_current_lines" -lt "$((count_current_lines + 2))" ]; then
            log_debug "Ensuring at least two blank lines at the end of '$PACMAN_CONF' for clean appending."
            echo "" | sudo tee -a "$PACMAN_CONF" >/dev/null
            echo "" | sudo tee -a "$PACMAN_CONF" >/dev/null
        fi
    fi

    log_debug "Pacman.conf is now clean of [archlinuxcn] blocks and ready for new configuration."
    return 0
}

# _install_archlinuxcn_keyring()
# @description: 安装 `archlinuxcn-keyring` 包以导入 ArchlinuxCN 仓库的 GPG 签名密钥。
# @functionality:
#   - 首先调用 `refresh_pacman_database` 函数（来自 `package_management_utils.sh`）刷新 Pacman 数据库，
#     以确保能够发现 `archlinuxcn-keyring` 包（特别是当 `[archlinuxcn]` 仓库刚被添加时）。
#   - 然后使用 `install_pacman_pkg` 函数（来自 `package_management_utils.sh`）安装 `archlinuxcn-keyring` 包。
#   - 此包安装后会自动导入所需的 GPG 密钥，允许 Pacman 验证来自 ArchlinuxCN 仓库的软件包，确保其完整性和安全性。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: refresh_pacman_database() (from package_management_utils.sh),
#           install_pacman_pkg() (from package_management_utils.sh), pacman (system command),
#           log_info(), log_success(), log_error(), log_notice() (from utils.sh)
_install_archlinuxcn_keyring() {
    log_info "Initiating installation/update of 'archlinuxcn-keyring' for GPG key import."

    # 预先刷新数据库，以确保 Pacman 能找到新添加的仓库及其中的包
    log_info "Refreshing Pacman database to ensure 'archlinuxcn-keyring' is discoverable in the newly added/activated repository."
    if ! refresh_pacman_database; then
        log_error "Failed to refresh Pacman database. This might hinder the installation of 'archlinuxcn-keyring'."
        log_error "Please check your network and mirrorlist for official repositories. Aborting keyring installation."
        return 1
    fi

    # 使用 package_management_utils.sh 中的 install_pacman_pkg 函数安装 keyring
    log_info "Attempting to install 'archlinuxcn-keyring' package from the ArchlinuxCN repository."
    if install_pacman_pkg "archlinuxcn-keyring"; then
        log_success "'archlinuxcn-keyring' installed/updated successfully. The ArchlinuxCN GPG key has been imported."
        log_notice "This key allows Pacman to verify packages from the ArchlinuxCN repository."
        return 0
    else
        log_error "Failed to install 'archlinuxcn-keyring'."
        log_error "This means packages from ArchlinuxCN might not be verifiable, leading to security warnings or installation failures."
        log_error "Please try manual installation: 'sudo pacman -S archlinuxcn-keyring' or consult ArchlinuxCN wiki for troubleshooting."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

# main()
# @description: 脚本的主执行函数，负责 ArchlinuxCN 仓库配置的整体流程控制。
# @functionality:
#   - 显示模块标题，告知用户脚本目的。
#   - **核心流程**: 首先检测并展示当前配置状态，然后根据状态询问用户意图。
#     - 如果用户同意，则执行完整的备份、清理、选择镜像、添加配置、安装 keyring 和系统同步流程。
#     - 如果用户拒绝，则脚本直接结束，不进行任何修改。
# @param: $@ - 脚本的所有命令行参数，此处通常不直接使用，但保留传递习惯。
# @returns: 0 on successful completion or user cancellation, 1 on any failure during the process.
# @depends: display_header_section(), _backup_pacman_conf(), _remove_all_archlinuxcn_blocks(), _select_mirror(),
#           _install_archlinuxcn_keyring(), sync_system_and_refresh_db() (from package_management_utils.sh),
#           log_info(), log_success(), log_error(), log_warn(), log_notice(), _confirm_action() (from utils.sh)
main() {
    display_header_section "ArchlinuxCN Repository Configuration" "box" 70 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_BRIGHT_BLUE}"
    log_info "This script will add and configure the Arch Linux CN (archlinuxcn) repository on your system."
    log_info "The ArchlinuxCN repository provides many useful Chinese-specific software, fonts, and convenient AUR helpers."
    log_info "The main Pacman configuration file affected is: '$PACMAN_CONF'."

    # @step 1: 检测并展示当前配置状态
    log_info "Step 1: Analyzing current state of [archlinuxcn] repository in '$PACMAN_CONF'..."
    local archlinuxcn_found=false
    local current_server=""
    # 查找 [archlinuxcn] 块，并提取其 Server 行
    if grep -q -E "^\s*\[archlinuxcn\]" "$PACMAN_CONF"; then
        archlinuxcn_found=true
        # 提取 Server 行，并移除前导空白和 "Server = "
        current_server=$(sed -n '/^\s*\[archlinuxcn\]/,/^\s*\[/ { /^\s*Server\s*=/p; }' "$PACMAN_CONF" | head -n 1 | sed -e 's/^\s*Server\s*=\s*//' || true)
        if [ -n "$current_server" ]; then
            log_notice "The [archlinuxcn] repository is currently active. Current server is: $current_server"
        else
            log_notice "The [archlinuxcn] repository block exists, but its server configuration is not found or is malformed."
        fi
    else
        log_info "The [archlinuxcn] repository is not currently configured in '$PACMAN_CONF'."
    fi

    # @step 2: 根据当前状态，询问用户意图
    local prompt_text="Do you want to add the [archlinuxcn] repository?"
    if [ "$archlinuxcn_found" == "true" ]; then
        prompt_text="Do you want to modify or re-configure the existing [archlinuxcn] repository?"
    fi

    if ! _confirm_action "$prompt_text" "y" "${COLOR_YELLOW}"; then
        log_warn "User chose to skip ArchlinuxCN repository configuration. No changes will be made."
        return 0 # 用户取消，视为正常退出
    fi
    log_info "User confirmed to proceed. Starting configuration process."

    local setup_successful=false # 标志，true表示所有步骤成功

    # @step 3: 备份当前 pacman.conf
    log_info "Step 3: Attempting to back up the current pacman.conf before any modifications."
    if ! _backup_pacman_conf; then
        log_error "Failed to back up pacman.conf. Aborting configuration to prevent data loss."
        return 1
    fi

    # @step 4: 清理旧配置
    log_info "Step 4: Preparing pacman.conf by removing any existing ArchlinuxCN repository configurations."
    if ! _remove_all_archlinuxcn_blocks; then
        log_error "Failed to fully clear old [archlinuxcn] repository configurations. This might lead to issues. Manual intervention is recommended."
        return 1
    fi
    log_success "Previous ArchlinuxCN repository configurations (if any) have been successfully removed."

    # @step 5: 选择镜像并添加新配置
    _select_mirror || { log_error "Mirror selection failed. Aborting configuration."; return 1; }
    
    log_info "Appending new ArchlinuxCN repository configuration with selected mirror: '$SELECTED_ARCHLINUXCN_MIRROR'."
    if ! (printf "$ARCHLINUXCN_REPO_CONFIG" "$SELECTED_ARCHLINUXCN_MIRROR" | sudo tee -a "$PACMAN_CONF" >/dev/null); then
        log_error "Failed to add [archlinuxcn] repository to '$PACMAN_CONF'. Permissions issue?"
        return 1
    fi
    log_success "ArchlinuxCN repository configuration successfully added to '$PACMAN_CONF'."

    # @step 6: 安装 keyring
    log_info "Step 6: Installing 'archlinuxcn-keyring' to import necessary GPG keys."
    if ! _install_archlinuxcn_keyring; then
        log_error "Failed to install 'archlinuxcn-keyring'. The ArchlinuxCN repository might not be fully functional."
        return 1
    fi
    log_notice "ArchlinuxCN GPG key import step completed successfully."

    # @step 7: 系统同步
    log_info "Step 7: Performing a full system synchronization (pacman -Syyu) to apply all changes."
    if ! sync_system_and_refresh_db; then
        log_error "Failed to refresh Pacman database and synchronize system after ArchlinuxCN configuration."
        return 1
    fi
    
    setup_successful=true

    # 最终总结
    log_info "Summary of ArchlinuxCN repository setup process:"
    if [ "$setup_successful" = true ]; then
        log_success "ArchlinuxCN repository setup process completed successfully!"
        log_notice "You can now install packages from the ArchlinuxCN repository, for example: 'sudo pacman -S yay'."
        log_notice "Recommended next steps: consider installing 'yay' (AUR helper) and 'archlinuxcn-mirrorlist-git' for more mirrors."
        return 0
    else
        # 这种情况通常不会发生，因为前面所有失败都已 `return 1`
        log_error "ArchlinuxCN repository setup process finished with some errors. Please review the logs above."
        return 1
    fi
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
        log_info "Exiting ArchlinuxCN repository configuration script successfully."
    else
        log_warn "Exiting ArchlinuxCN repository configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

# 脚本退出
exit_script $?