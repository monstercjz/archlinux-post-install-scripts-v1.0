#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/package_management_utils.sh
# 版本: 1.0.3 (优化：sync_system_and_refresh_db 增加重试机制和详细错误捕获)
# 日期: 2025-06-08
# 描述: 核心包管理工具函数库。
#       提供项目运行所需的通用包管理功能，包括 Pacman 和 AUR 助手操作。
# ------------------------------------------------------------------------------
# 核心功能:
# - 刷新 Pacman 数据库 (pacman -Syy)。
# - 同步系统并刷新数据库 (pacman -Syyu)。
# - 检查特定包是否已安装 (is_package_installed)。
# - 清理 Pacman 缓存 (clean_pacman_cache)。
# - 清理 AUR 助手 (yay/paru) 缓存 (clean_aur_cache)。
# - 安装官方仓库包 (install_pacman_pkg)。
# - 安装 AUR 包 (install_yay_pkg, install_paru_pkg)。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于确保 BASE_DIR, ORIGINAL_USER,
#     ORIGINAL_HOME 等已导出，以及 utils.sh 已加载)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示等基础函数)
#   - 系统命令: pacman, yay, paru (在各自的安装/清理函数中检查其可用性), git
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。封装了更粒度化的 Pacman 和 AUR 包管理操作。
# v1.0.1 - 2025-06-08 - 移除内部的 '_ensure_aur_helper_installed' 函数，
#                       将 AUR 助手的安装逻辑完全从本文件剥离，使函数更纯粹。
# v1.0.2 - 2025-06-08 - 增加详尽的注释，细化日志输出，符合最佳实践标注。
# v1.0.3 - 2025-06-08 - 优化 'sync_system_and_refresh_db' 函数：
#                       1. 增加重试机制 (最多3次)。
#                       2. 捕获并记录 'pacman' 的标准错误输出，提供更详细的错误信息。
#                       3. 提供网络问题故障排除提示。
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 防止此框架脚本在同一个 shell 进程中被重复 source。
# (此变量不会被导出，以确保在新的子进程中能重新加载)
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="${__PACKAGE_MANAGEMENT_UTILS_SOURCED__:-}"
if [ -n "$__PACKAGE_MANAGEMENT_UTILS_SOURCED__" ]; then
    log_debug "Skipping re-sourcing for package_management_utils.sh as it's already loaded."
    return 0 
fi

# ==============================================================================
# 内部辅助函数 (以 "_" 开头，不对外暴露，主要供其他本文件中的函数调用)
# ==============================================================================

# _get_installed_aur_helper()
# @description: 检测当前系统已安装的 AUR 助手 (yay 或 paru)。
# @functionality:
#   - 检查 'yay' 命令是否存在于 PATH 中。
#   - 如果 'yay' 不存在，则检查 'paru' 命令是否存在。
#   - 如果两者都存在，优先返回 'yay' (可根据需求调整优先级)。
# @param: 无
# @returns: string - 已安装的 AUR 助手名称 (小写，例如 "yay" 或 "paru")。如果未安装，则返回空字符串。
# @depends: command (Bash 内置命令)
_get_installed_aur_helper() {
    log_debug "Attempting to detect installed AUR helper..."
    if command -v yay &>/dev/null; then
        log_debug "Detected AUR helper: yay."
        echo "yay"
    elif command -v paru &>/dev/null; then
        log_debug "Detected AUR helper: paru."
        echo "paru"
    else
        log_debug "No common AUR helper (yay/paru) detected."
        echo ""
    fi
}

# ==============================================================================
# 对外暴露的包管理功能函数
# ==============================================================================

# refresh_pacman_database()
# @description: 刷新 Pacman 数据库。
# @functionality:
#   - 执行 'pacman -Syy --noconfirm' 命令，从所有配置的仓库中下载最新的包列表。
#   - '--noconfirm' 参数用于非交互式操作。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: pacman (系统命令)
refresh_pacman_database() {
    log_info "Executing 'pacman -Syy' to refresh Pacman database..."
    local output
    if output=$(pacman -Syy --noconfirm 2>&1); then
        log_success "Pacman database refreshed successfully."
        log_info "Pacman -Syy output:$(echo -e "\n${output}")"
        return 0
    else
        log_error "Failed to refresh Pacman database."
        log_error "Pacman -Syy error output:$(echo -e "\n${output}")"
        log_error "Possible reasons: Network connectivity issues, incorrect mirrorlist, or repository server problems."
        return 1
    fi
}

# sync_system_and_refresh_db()
# @description: 刷新 Pacman 数据库并同步系统软件包。
# @functionality:
#   - 执行 'pacman -Syyu --noconfirm' 命令，从所有配置的仓库中下载最新的包列表。
#   - 同时升级所有已安装的包。
#   - '--noconfirm' 参数用于非交互式操作。
#   - 包含重试机制，最多尝试3次，以应对临时的网络波动。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: pacman (系统命令)
sync_system_and_refresh_db() {
    local max_retries=3
    local retry_count=0
    local output
    local success=1

    log_info "Executing 'pacman -Syyu' to synchronize system packages and refresh database..."

    while [ "$retry_count" -lt "$max_retries" ]; do
        if output=$(pacman -Syyu --noconfirm 2>&1); then
            log_success "System synchronized and database refreshed successfully."
            log_info "Pacman -Syyu output:$(echo -e "\n${output}")"
            success=0
            break
        else
            log_warn "Attempt $((retry_count + 1)) of $max_retries failed to synchronize system."
            log_warn "Pacman -Syyu error output:$(echo -e "\n${output}")"
            retry_count=$((retry_count + 1))
            if [ "$retry_count" -lt "$max_retries" ]; then
                log_info "Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    if [ "$success" -eq 0 ]; then
        return 0
    else
        log_error "Failed to synchronize system and refresh database after $max_retries attempts."
        log_error "Possible reasons: Persistent network connectivity issues, incorrect mirrorlist, corrupted database, or repository server problems."
        log_error "Troubleshooting steps:"
        log_error "  1. Check your internet connection (e.g., 'ping archlinux.org')."
        log_error "  2. Verify your Pacman mirrorlist ('/etc/pacman.d/mirrorlist'). You might need to re-run mirror configuration."
        log_error "  3. If you suspect database corruption, try 'sudo rm -rf /var/lib/pacman/sync/*' and then 'sudo pacman -Syyu'."
        return 1
    fi
}

# is_package_installed()
# @description: 检查指定包是否已通过 Pacman 安装。
# @functionality:
#   - 执行 'pacman -Q <package_name>' 命令查询包信息。
#   - 通过检查命令的退出状态来判断包是否存在。
# @param: $1 (string) package_name - 要检查的包名。
# @returns: 0 if the package is installed, 1 if not.
# @depends: pacman (系统命令)
is_package_installed() {
    local package_name="$1"
    log_debug "Checking if package '$package_name' is installed using 'pacman -Q'..."
    if pacman -Q "$package_name" &>/dev/null; then
        log_debug "Package '$package_name' is indeed installed."
        return 0
    else
        log_debug "Package '$package_name' is NOT installed."
        return 1
    fi
}

# clean_pacman_cache()
# @description: 清理 Pacman 的包缓存。
# @functionality:
#   - 执行 'pacman -Sc --noconfirm' 命令，清理 Pacman 缓存中所有不再需要的包文件。
#   - '--noconfirm' 参数用于非交互式操作。
# @param: 无
# @returns: 0 on success, 1 on failure.
# @depends: pacman (系统命令)
clean_pacman_cache() {
    log_info "Executing 'pacman -Sc' to clean Pacman cache..."
    local output
    if output=$(pacman -Sc --noconfirm 2>&1); then
        log_success "Pacman cache cleaned successfully."
        log_info "Pacman -Sc output:$(echo -e "\n${output}")"
        return 0
    else
        log_warn "Failed to clean Pacman cache. Please review any error messages."
        log_warn "Pacman -Sc error output:$(echo -e "\n${output}")"
        return 1
    fi
}

# clean_aur_cache()
# @description: 清理 AUR 助手的包缓存。
# @functionality:
#   - 首先检测当前已安装的 AUR 助手 (yay/paru)。
#   - 如果找到助手，则执行其对应的清理命令 (例如 'yay -Sc' 或 'paru -Sc')。
#   - 如果没有找到任何 AUR 助手，则跳过清理并发出通知。
# @param: 无
# @returns: 0 on success, 1 on failure (if helper found but cache cleaning fails).
# @depends: _get_installed_aur_helper() (内部辅助函数), yay/paru (系统命令，如果已安装)
clean_aur_cache() {
    local installed_aur_helper=$(_get_installed_aur_helper)
    if [ -n "$installed_aur_helper" ]; then
        log_info "Executing '$installed_aur_helper -Sc' to clean AUR cache..."
        local output
        if output=$("$installed_aur_helper" -Sc --noconfirm 2>&1); then
            log_success "'$installed_aur_helper' cache cleaned successfully."
            log_info "AUR helper -Sc output:$(echo -e "\n${output}")"
            return 0
        else
            log_warn "Failed to clean '$installed_aur_helper' cache. Please review any error messages."
            log_warn "AUR helper -Sc error output:$(echo -e "\n${output}")"
            return 1
        fi
    else
        log_info "No AUR helper (yay/paru) found. Skipping AUR cache cleaning."
    fi
    return 0
}

# install_pacman_pkg()
# @description: 使用 Pacman 安装指定的官方仓库包。
# @functionality:
#   - 检查传入的包列表是否为空。
#   - 执行 'pacman -S --noconfirm --needed <package_list>' 命令安装包。
#   - '--noconfirm' 用于非交互式。'--needed' 确保只安装未安装的包。
# @param: $1 (string) package_list - 包含要安装的包的空格分隔字符串 (例如 "git curl zsh")。
# @returns: 0 on success, 1 on failure.
# @depends: pacman (系统命令)
install_pacman_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No official packages specified for installation via Pacman. Skipping installation."
        return 0
    fi

    log_info "Attempting to install official repository packages with Pacman: '${package_list}'..."
    local output
    if output=$(pacman -S --noconfirm --needed "$package_list" 2>&1); then
        log_success "Official packages installed successfully: '${package_list}'."
        log_info "Pacman -S output:$(echo -e "\n${output}")"
        return 0
    else
        log_error "Failed to install official packages using Pacman: '${package_list}'."
        log_error "Pacman -S error output:$(echo -e "\n${output}")"
        log_error "Possible reasons: Network issues, incorrect package names, or dependencies not met."
        return 1
    fi
}

# install_yay_pkg()
# @description: 使用 yay 安装指定的 AUR 包。
# @functionality:
#   - 检查传入的包列表是否为空。
#   - 验证 'yay' 命令是否已安装并可用。如果不可用，则报错并返回。
#   - 执行 'yay -S --noconfirm --needed <package_list>' 命令安装 AUR 包。
#   - '--noconfirm' 用于非交互式。'--needed' 确保只安装未安装的包。
# @param: $1 (string) package_list - 包含要安装的包的空格分隔字符串。
# @returns: 0 on success, 1 on failure.
# @depends: yay (系统命令，必须已安装)
install_yay_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No AUR packages specified for yay installation. Skipping installation."
        return 0
    fi

    log_info "Attempting to install AUR packages with yay: '${package_list}'..."
    # 检查 yay 是否已安装
    if ! command -v yay &>/dev/null; then
        log_error "'yay' command not found. Cannot install AUR packages using yay."
        log_error "Please ensure 'yay' is installed before attempting to install AUR packages with 'install_yay_pkg'."
        return 1
    fi

    local output
    if output=$(yay -S --noconfirm --needed "$package_list" 2>&1); then
        log_success "AUR packages installed successfully using yay: '${package_list}'."
        log_info "yay -S output:$(echo -e "\n${output}")"
        return 0
    else
        log_error "Failed to install AUR packages using yay: '${package_list}'."
        log_error "yay -S error output:$(echo -e "\n${output}")"
        log_error "Possible reasons: Network issues, incorrect package names, AUR helper configuration, or build failures."
        return 1
    fi
}

# install_paru_pkg()
# @description: 使用 paru 安装指定的 AUR 包。
# @functionality:
#   - 检查传入的包列表是否为空。
#   - 验证 'paru' 命令是否已安装并可用。如果不可用，则报错并返回。
#   - 执行 'paru -S --noconfirm --needed <package_list>' 命令安装 AUR 包。
#   - '--noconfirm' 用于非交互式。'--needed' 确保只安装未安装的包。
# @param: $1 (string) package_list - 包含要安装的包的空格分隔字符串。
# @returns: 0 on success, 1 on failure.
# @depends: paru (系统命令，必须已安装)
install_paru_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No AUR packages specified for paru installation. Skipping installation."
        return 0
    fi

    log_info "Attempting to install AUR packages with paru: '${package_list}'..."
    # 检查 paru 是否已安装
    if ! command -v paru &>/dev/null; then
        log_error "'paru' command not found. Cannot install AUR packages using paru."
        log_error "Please ensure 'paru' is installed before attempting to install AUR packages with 'install_paru_pkg'."
        return 1
    fi

    local output
    if output=$(paru -S --noconfirm --needed "$package_list" 2>&1); then
        log_success "AUR packages installed successfully using paru: '${package_list}'."
        log_info "paru -S output:$(echo -e "\n${output}")"
        return 0
    else
        log_error "Failed to install AUR packages using paru: '${package_list}'."
        log_error "paru -S error output:$(echo -e "\n${output}")"
        log_error "Possible reasons: Network issues, incorrect package names, AUR helper configuration, or build failures."
        return 1
    fi
}

# 标记此初始化脚本已被加载 (不导出)
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="true"
log_debug "Package management utilities sourced and available (v1.0.3)."