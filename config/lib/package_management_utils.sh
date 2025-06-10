#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/package_management_utils.sh
# 版本: 1.0.1 (根据用户建议，精简为更纯粹的功能函数)
# 日期: 2025-06-08
# 描述: 核心包管理工具函数库。
#       提供项目运行所需的通用包管理功能，包括 Pacman 和 AUR 助手操作。
# ------------------------------------------------------------------------------
# 职责:
#   - 刷新 Pacman 数据库 (pacman -Syy)。
#   - 同步系统并刷新数据库 (pacman -Syyu)。
#   - 检查特定包是否已安装。
#   - 清理 Pacman 缓存。
#   - 清理 AUR 助手 (yay/paru) 缓存。
#   - 安装官方仓库包 (pacman)。
#   - 安装 AUR 包 (yay)。
#   - 安装 AUR 包 (paru)。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于确保 BASE_DIR, ORIGINAL_USER,
#     ORIGINAL_HOME 等已导出，以及 utils.sh 已加载)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示等基础函数)
#   - 系统命令: pacman, yay, paru (在各自的安装/清理函数中检查其可用性)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。封装了更粒度化的 Pacman 和 AUR 包管理操作。
# v1.0.1 - 2025-06-08 - 根据用户建议，移除内部的 '_ensure_aur_helper_installed' 函数。
#                       将 AUR 助手的安装逻辑完全从本文件剥离，
#                       'install_yay_pkg' 和 'install_paru_pkg' 不再检查/安装助手，
#                       而是直接调用助手命令，如果助手未安装则报错。
#                       这将判断和安装 AUR 助手的职责推给调用者（例如独立的 AUR 助手安装模块）。
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 防止此框架脚本在同一个 shell 进程中被重复 source
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="${__PACKAGE_MANAGEMENT_UTILS_SOURCED__:-}"
if [ -n "$__PACKAGE_MANAGEMENT_UTILS_SOURCED__" ]; then
    log_debug "Package management utilities already sourced. Skipping re-sourcing."
    return 0 
fi

# ==============================================================================
# 内部辅助函数 (以 "_" 开头，不对外暴露，主要供其他本文件中的函数调用)
# ==============================================================================

# _get_installed_aur_helper()
# 功能: 检测当前系统已安装的 AUR 助手 (yay 或 paru)。
# 返回: 返回已安装的 AUR 助手名称 (小写)，如果未安装则返回空字符串。
_get_installed_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    else
        echo ""
    fi
}

# ==============================================================================
# 对外暴露的包管理功能函数
# ==============================================================================

# refresh_pacman_database()
# 功能: 刷新 Pacman 数据库 (pacman -Syy)。
# 参数: 无。
# 返回: 0 (成功) 或 1 (失败)。
refresh_pacman_database() {
    log_info "Refreshing Pacman database (pacman -Syy)..."
    if pacman -Syy --noconfirm; then
        log_success "Pacman database refreshed successfully."
        return 0
    else
        log_error "Failed to refresh Pacman database. Check your network connection."
        return 1
    fi
}

# sync_system_and_refresh_db()
# 功能: 刷新 Pacman 数据库并同步系统 (pacman -Syyu)。
# 参数: 无。
# 返回: 0 (成功) 或 1 (失败)。
sync_system_and_refresh_db() {
    log_info "Synchronizing system packages and refreshing database (pacman -Syyu)..."
    if pacman -Syyu --noconfirm; then
        log_success "System synchronized and database refreshed successfully."
        return 0
    else
        log_error "Failed to synchronize system and refresh database. Please check your network or mirrorlist configuration."
        return 1
    fi
}

# is_package_installed()
# 功能: 检查指定包是否已安装。
# 参数: $1 (package_name) - 要检查的包名。
# 返回: 0 (已安装) 或 1 (未安装)。
is_package_installed() {
    local package_name="$1"
    log_debug "Checking if package '$package_name' is installed..."
    if pacman -Q "$package_name" &>/dev/null; then
        log_debug "Package '$package_name' is installed."
        return 0
    else
        log_debug "Package '$package_name' is NOT installed."
        return 1
    fi
}

# clean_pacman_cache()
# 功能: 清理 Pacman 的包缓存。
# 参数: 无。
# 返回: 0 (成功) 或 1 (失败)。
clean_pacman_cache() {
    log_info "Cleaning Pacman cache (pacman -Sc)..."
    if pacman -Sc --noconfirm; then
        log_success "Pacman cache cleaned successfully."
        return 0
    else
        log_warn "Failed to clean Pacman cache. Please check for errors."
        return 1
    fi
}

# clean_aur_cache()
# 功能: 清理 AUR 助手的包缓存。
# 参数: 无。
# 返回: 0 (成功) 或 1 (失败)。
clean_aur_cache() {
    local installed_aur_helper=$(_get_installed_aur_helper)
    if [ -n "$installed_aur_helper" ]; then
        log_info "Cleaning '$installed_aur_helper' cache ('$installed_aur_helper' -Sc)..."
        if "$installed_aur_helper" -Sc --noconfirm; then
            log_success "'$installed_aur_helper' cache cleaned successfully."
            return 0
        else
            log_warn "Failed to clean '$installed_aur_helper' cache. Please check for errors."
            return 1
        fi
    else
        log_info "No AUR helper found. Skipping AUR cache cleaning."
    fi
    return 0
}

# install_pacman_pkg()
# 功能: 使用 Pacman 安装指定的官方仓库包。
# 参数: $1 (package_list) - 包含要安装的包的空格分隔字符串 (例如 "git curl zsh").
# 返回: 0 (所有包成功安装) 或 1 (至少一个包安装失败)。
install_pacman_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No official packages provided for installation."
        return 0
    fi

    log_info "Using Pacman to install official repository packages: ${package_list}"
    if pacman -S --noconfirm --needed "$package_list"; then
        log_success "Official packages installed successfully: ${package_list}"
        return 0
    else
        log_error "Failed to install official packages using Pacman: ${package_list}"
        return 1
    fi
}

# install_yay_pkg()
# 功能: 使用 yay 安装指定的 AUR 包。
# 参数: $1 (package_list) - 包含要安装的包的空格分隔字符串。
# 返回: 0 (所有包成功安装) 或 1 (至少一个包安装失败)。
install_yay_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No AUR packages provided for yay installation."
        return 0
    fi

    # 检查 yay 是否已安装，但不再负责安装它。
    if ! command -v yay &>/dev/null; then
        log_error "'yay' is not installed. Cannot install AUR packages using yay."
        log_error "Please ensure 'yay' is installed before attempting to install AUR packages with 'install_yay_pkg'."
        return 1
    fi

    log_info "Using yay to install AUR packages: ${package_list}"
    if yay -S --noconfirm --needed "$package_list"; then
        log_success "AUR packages installed successfully using yay: ${package_list}"
        return 0
    else
        log_error "Failed to install AUR packages using yay: ${package_list}"
        return 1
    fi
}

# install_paru_pkg()
# 功能: 使用 paru 安装指定的 AUR 包。
# 参数: $1 (package_list) - 包含要安装的包的空格分隔字符串。
# 返回: 0 (所有包成功安装) 或 1 (至少一个包安装失败)。
install_paru_pkg() {
    local package_list="$1"

    if [ -z "$package_list" ]; then
        log_warn "No AUR packages provided for paru installation."
        return 0
    fi

    # 检查 paru 是否已安装，但不再负责安装它。
    if ! command -v paru &>/dev/null; then
        log_error "'paru' is not installed. Cannot install AUR packages using paru."
        log_error "Please ensure 'paru' is installed before attempting to install AUR packages with 'install_paru_pkg'."
        return 1
    fi

    log_info "Using paru to install AUR packages: ${package_list}"
    if paru -S --noconfirm --needed "$package_list"; then
        log_success "AUR packages installed successfully using paru: ${package_list}"
        return 0
    else
        log_error "Failed to install AUR packages using paru: ${package_list}"
        return 1
    fi
}

# 标记此初始化脚本已被加载 (不导出)
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="true"
log_debug "Package management utilities sourced and available."