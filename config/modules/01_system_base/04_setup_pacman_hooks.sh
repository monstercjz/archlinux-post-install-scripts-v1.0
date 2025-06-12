#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_package_management/04_setup_pacman_hooks.sh
# 版本: 1.0.3 (增强用户交互决策)
# 日期: 2025-06-11
# 描述: 部署自定义的 Pacman hooks 以在包管理操作前后自动执行脚本。
# ------------------------------------------------------------------------------
# 核心功能:
# - **智能部署与用户决策**: 在部署文件前，检查目标文件是否存在。
#   - 如果内容相同，提示用户并询问是否仍要重新部署。
#   - 如果内容不同，提示用户并询问是否要覆盖。
#   - 只有在用户确认后才进行备份和覆盖。
# - **数组驱动**: 将要部署的文件列表定义为常量数组，便于扩展和维护。
# - **原子化操作**: 在部署失败时（如复制失败），会自动恢复之前的备份，确保系统状态一致。
# - 从项目的 `assets` 目录复制 `.hook` 文件和其依赖的可执行脚本到系统目录。
# - 自动设置正确的文件权限。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于获取 `ASSETS_DIR` 和加载工具函数)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示、错误处理等基础函数)
#   - main_config.sh (直接依赖，提供 `PACMAN_HOOKS_DIR` 等配置)
#   - 系统命令: cp, chmod, mv, date, cmp
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。从旧的独立 pacman-hook.sh 脚本迁移并完全重构。
# v1.0.1 - 2025-06-11 - 在 `_deploy_file` 函数中增加了对目标文件的备份逻辑，防止意外覆盖用户已有的同名文件。
# v1.0.2 - 2025-06-11 - 将要部署的文件列表提取为常量数组，使部署逻辑由数据驱动，更易扩展。
#                       新增文件内容比较逻辑：如果目标文件已存在且内容与源文件相同，则跳过部署。
#                       完善了 `_deploy_file` 函数中的备份恢复逻辑，确保在复制失败时能安全回滚。
# v1.0.3 - 2025-06-11 - **增强用户交互：当目标文件已存在时（无论内容是否相同），都将决策权交给用户，让用户决定是否覆盖。**
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
# 变量与常量定义
# ==============================================================================

# @var string SOURCE_HOOK_DIR Pacman hook 源文件目录，从项目 assets 目录获取。
SOURCE_HOOK_DIR="${ASSETS_DIR}/pacman/hooks"
# @var string DEST_BIN_DIR 可执行脚本的目标目录。
DEST_BIN_DIR="/usr/local/bin"
# @var string DEST_HOOK_DIR Pacman hook 目标目录，从 main_config.sh 获取。
DEST_HOOK_DIR="${PACMAN_HOOKS_DIR}"

# --- 定义要部署的文件列表 ---
# @const array HOOK_SCRIPTS_TO_DEPLOY 需要部署到 DEST_BIN_DIR 的可执行脚本列表。
declare -r HOOK_SCRIPTS_TO_DEPLOY=(
    "backup-manual_install_package-info.sh"
    "backup-pacman-info.sh"
)
# @const array HOOK_FILES_TO_DEPLOY 需要部署到 DEST_HOOK_DIR 的 hook 配置文件列表。
declare -r HOOK_FILES_TO_DEPLOY=(
    "backup-manual_install_package.hook"
    "backup-pkglist-log.hook"
)

# ==============================================================================
# 辅助函数
# ==============================================================================

# _deploy_file()
# @description: 智能部署单个文件到目标目录，并设置指定的权限。
# @functionality:
#   - 检查源文件是否存在。
#   - 检查目标文件是否存在。
#   - 如果目标文件存在，比较内容。
#     - 内容相同：询问用户是否仍要覆盖。
#     - 内容不同：警告用户内容不同，并询问是否覆盖。
#   - 只有在用户确认后，才执行备份和覆盖操作。
#   - 如果复制新文件失败，会自动从备份中恢复，确保操作的原子性。
# @param: $1 (string) source_file - 源文件的完整路径。
# @param: $2 (string) dest_dir - 目标目录的完整路径。
# @param: $3 (string) permissions - 要设置的文件权限 (e.g., "755" or "644")。
# @param: $4 (string) file_type - 文件类型描述，用于日志 (e.g., "script" or "hook")。
# @returns: 0 on success, 1 on failure.
_deploy_file() {
    local source_file="$1"
    local dest_dir="$2"
    local permissions="$3"
    local file_type="$4"
    local filename=$(basename "$source_file")
    local dest_path="${dest_dir}/${filename}"

    log_info "Processing $file_type: '$filename'..."

    if [ ! -f "$source_file" ]; then
        log_error "Source $file_type file not found: '$source_file'."
        return 1
    fi

    # 检查目标文件是否存在
    if [ -f "$dest_path" ]; then
        local confirm_prompt=""
        # 比较文件内容
        if cmp -s "$source_file" "$dest_path"; then
            log_notice "Target file '$dest_path' already exists and has the same content."
            confirm_prompt="Do you want to re-deploy it anyway (backup and overwrite)?"
        else
            log_warn "Target file '$dest_path' already exists but its content is DIFFERENT."
            confirm_prompt="Do you want to overwrite it with the new version? (The existing file will be backed up)"
        fi
        
        # 询问用户是否覆盖
        if ! _confirm_action "$confirm_prompt" "n" "${COLOR_YELLOW}"; then
            log_info "User chose to skip deployment for '$filename'. The existing file remains unchanged."
            return 0
        fi
        log_info "User confirmed to overwrite '$filename'."

        # 内容不同或用户坚持覆盖，进行备份
        local backup_file="${dest_path}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing file to '$backup_file'."
        if ! mv "$dest_path" "$backup_file"; then
            log_error "Failed to back up existing file at '$dest_path'. Aborting deployment of this file."
            return 1
        fi
        log_success "Existing file backed up successfully."
    fi

    # 部署新文件
    log_info "Deploying new $file_type: '$filename' to '$dest_dir'."
    if ! cp -p "$source_file" "$dest_path"; then
        log_error "Failed to copy $file_type from '$source_file' to '$dest_path'."
        # 完善的恢复逻辑：如果复制失败，并且之前有备份，则恢复备份。
        if [ -n "${backup_file-}" ] && [ -f "$backup_file" ]; then
            log_info "Attempting to restore from backup due to copy failure..."
            if mv "$backup_file" "$dest_path"; then
                log_success "Successfully restored '$dest_path' from backup."
            else
                log_fatal "CRITICAL: Could not restore '$dest_path' from backup. The file is now missing. Please fix it manually from '$backup_file'."
            fi
        fi
        return 1
    fi

    # 设置权限
    if ! chmod "$permissions" "$dest_path"; then
        log_error "Failed to set permissions '$permissions' for '$dest_path'."
        return 1
    fi
    
    log_success "Successfully deployed $file_type '$filename' with permissions $permissions."
    return 0
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Pacman Hooks Deployment" "box" 80
    log_info "This script will deploy custom Pacman hooks to automate tasks during package management."
    
    # 检查源目录是否存在
    if [ ! -d "$SOURCE_HOOK_DIR" ]; then
        handle_error "Source directory for hooks not found at '$SOURCE_HOOK_DIR'. Please check the project structure."
    fi

    # 列出将要部署的文件
    log_notice "The following files will be deployed:"
    log_summary "  - Executable Scripts to '$DEST_BIN_DIR':"
    for script in "${HOOK_SCRIPTS_TO_DEPLOY[@]}"; do
        log_summary "    - $script"
    done
    log_summary "  - Hook Files to '$DEST_HOOK_DIR':"
    for hook in "${HOOK_FILES_TO_DEPLOY[@]}"; do
        log_summary "    - $hook"
    done
    log_info "Note: If any of these files already exist, you will be prompted for action."

    # 用户确认
    if ! _confirm_action "Do you want to start the deployment process?" "y" "${COLOR_YELLOW}"; then
        log_warn "User cancelled Pacman hooks deployment."
        return 0
    fi
    log_info "User confirmed. Starting deployment..."

    # @step 1: 确保目标目录存在
    log_info "Step 1: Ensuring destination directories exist."
    if ! _create_directory_if_not_exists "$DEST_BIN_DIR"; then
        handle_error "Failed to create destination directory: '$DEST_BIN_DIR'."
    fi
    if ! _create_directory_if_not_exists "$DEST_HOOK_DIR"; then
        handle_error "Failed to create destination directory: '$DEST_HOOK_DIR'."
    fi
    log_success "Destination directories are ready."

    local deployment_failed=false

    # @step 2: 部署可执行脚本 (由数组驱动)
    log_info "Step 2: Deploying executable scripts to '$DEST_BIN_DIR'."
    for script in "${HOOK_SCRIPTS_TO_DEPLOY[@]}"; do
        if ! _deploy_file "${SOURCE_HOOK_DIR}/${script}" "$DEST_BIN_DIR" "755" "script"; then
            deployment_failed=true
        fi
    done

    # @step 3: 部署 Hook 文件 (由数组驱动)
    log_info "Step 3: Deploying hook files to '$DEST_HOOK_DIR'."
    for hook in "${HOOK_FILES_TO_DEPLOY[@]}"; do
        if ! _deploy_file "${SOURCE_HOOK_DIR}/${hook}" "$DEST_HOOK_DIR" "644" "hook"; then
            deployment_failed=true
        fi
    done

    # 最终总结
    if [ "$deployment_failed" = true ]; then
        log_error "Pacman hooks deployment finished with some errors. Please review the logs."
        return 1
    else
        log_success "All Pacman hooks and scripts have been deployed successfully!"
        log_notice "These hooks will now run automatically during Pacman transactions."
        return 0
    fi
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

main "$@"

exit_script() {
    local exit_code=${1:-0}
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Pacman Hooks Deployment script successfully."
    else
        log_warn "Exiting Pacman Hooks Deployment script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

exit_script $?