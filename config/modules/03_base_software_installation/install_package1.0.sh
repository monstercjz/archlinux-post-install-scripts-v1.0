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
    if output=$(pacman -Syy --noconfirm 2>&1 | tee /dev/stderr); then
        log_success "Pacman database refreshed successfully."
        log_debug "Pacman -Syy output:$(echo -e "\n${output}")"
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
    # | tee /dev/stderr 可以让同步输出到标准错误流，这样用户可以看到同步进度。
    while [ "$retry_count" -lt "$max_retries" ]; do
        if output=$(pacman -Syyu --noconfirm 2>&1 | tee /dev/stderr); then
            log_success "System synchronized and database refreshed successfully."
            log_debug "Pacman -Syyu output:$(echo -e "\n${output}")"
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


# _read_pkg_list_from_file()
# @description: 从给定的文件中读取软件包列表，过滤注释和空行，并返回一个用空格分隔的字符串。
# @param: $1 (string) - 软件包列表文件的完整路径。
# @returns: string - 用空格分隔的软件包名称字符串。
_read_pkg_list_from_file() {
    local file_path="$1"
    if [[ ! -f "$file_path" || ! -r "$file_path" ]]; then
        log_warn "软件包列表文件未找到或不可读: '$file_path'。跳过。"
        return
    fi
    # 使用 grep 过滤掉以#开头的行和空行，然后用 tr 将换行符转换为空格
    grep -vE '^\s*#|^\s*$' "$file_path" | tr '\n' ' '
}

# install_pacman_pkg()
# @description: 使用 Pacman 安装一个或多个官方仓库的软件包。
# @functionality:
#   - 接受一个或多个软件包名称作为参数。
#   - 将所有软件包名称合并到一个 pacman 命令中进行安装。
#   - 使用 --noconfirm 和 --needed 选项以实现自动化和效率。
# @precondition: 此函数应在 root 权限下执行 (由框架保证)。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 on success, 1 on failure.
# @depends: pacman (系统命令), log_* (from utils.sh)
install_pacman_pkg() {
    # 检查是否有传入参数
    if [ "$#" -eq 0 ]; then
        log_warn "install_pacman_pkg called with no packages to install."
        return 0
    fi

    # 关键修复：使用 "$*" 获取所有参数，形成一个空格分隔的字符串
    local pkgs_to_install="$*"
    
    log_info "Attempting to install official repository packages with Pacman: '$pkgs_to_install'..."

    local pacman_output
    refresh_pacman_database
    # 直接执行 pacman，不加 sudo，因为框架已保证 root 权限
    if pacman_output=$(pacman -S --noconfirm --needed $pkgs_to_install 2>&1 | tee /dev/stderr); then
        log_success "Official packages installed successfully: '$pkgs_to_install'."
        # 使用 log_debug 记录详细输出，避免刷屏，但在需要时可查
        log_debug "Pacman -S output:\n$pacman_output"
        return 0
    else
        # 错误处理，可以使用框架的 handle_error 函数，它会记录错误并退出
        # 或者返回 1，让调用者决定如何处理
        log_error "Failed to install packages: '$pkgs_to_install' with Pacman."
        log_error "Error details:\n$pacman_output"
        return 1
    fi
}

# install_yay_pkg()
# @description: 使用 yay 安装一个或多个 AUR 包。
# @functionality:
#   - 接受一个或多个软件包名称作为参数。
#   - 验证 'yay' 命令是否已安装。
#   - **核心安全实践：切换到普通用户 ($ORIGINAL_USER) 来执行 yay 命令。**
#   - 使用 --noconfirm 和 --needed 选项。
# @precondition: 框架已初始化，ORIGINAL_USER 变量可用。脚本在 root 权限下运行。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 on success, 1 on failure.
# @depends: yay (系统命令), sudo (系统命令), log_* (from utils.sh)
install_yay_pkg() {
    if [ "$#" -eq 0 ]; then
        log_warn "No AUR packages specified for yay installation. Skipping."
        return 0
    fi

    # 关键修复：使用 "$*" 获取所有参数
    local pkgs_to_install="$*"
    log_info "Attempting to install AUR packages with yay: '$pkgs_to_install'..."

    # 检查 yay 是否已安装
    if ! command -v yay &>/dev/null; then
        log_error "'yay' command not found. Please install it first, for example, via the '02_package_management/01_install_aur_helper.sh' module."
        return 1
    fi

    # **关键安全修复：必须作为普通用户运行 yay**
    # 使用 `sudo -u` 切换到原始用户来执行命令。
    # yay 在需要时会自己调用 sudo 获取 root 权限。
    # 我们传递 --noconfirm 给 yay，它会将其传递给底层的 pacman。
    log_notice "Running 'yay' as non-root user '$ORIGINAL_USER'. This is required for safety."
    refresh_pacman_database
    local yay_output
    # 使用新的通用函数
    if yay_output=$(run_as_user "yay -S --noconfirm --needed $pkgs_to_install" 2>&1 | tee /dev/stderr); then
        log_success "AUR packages installed successfully using yay: '$pkgs_to_install'."
        log_debug "yay -S output:\n$yay_output"
        return 0
    else
        log_error "Failed to install AUR packages using yay: '$pkgs_to_install'."
        log_error "yay -S error output:\n$yay_output"
        return 1
    fi
}


# install_paru_pkg()
# @description: 使用 paru 安装一个或多个 AUR 包。
# @functionality:
#   - 接受一个或多个软件包名称作为参数。
#   - 验证 'paru' 命令是否已安装。
#   - **核心安全实践：切换到普通用户 ($ORIGINAL_USER) 来执行 paru 命令。**
#   - 使用 --noconfirm 和 --needed 选项。
# @precondition: 框架已初始化，ORIGINAL_USER 变量可用。脚本在 root 权限下运行。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 on success, 1 on failure.
# @depends: paru (系统命令), sudo (系统命令), log_* (from utils.sh)
install_paru_pkg() {
    if [ "$#" -eq 0 ]; then
        log_warn "No AUR packages specified for paru installation. Skipping."
        return 0
    fi

    # 关键修复：使用 "$*" 获取所有参数
    local pkgs_to_install="$*"
    log_info "Attempting to install AUR packages with paru: '$pkgs_to_install'..."

    # 检查 paru 是否已安装
    if ! command -v paru &>/dev/null; then
        log_error "'paru' command not found. Please install it first, for example, via the '02_package_management/01_install_aur_helper.sh' module."
        return 1
    fi

    # **关键安全修复：必须作为普通用户运行 paru**
    log_notice "Running 'paru' as non-root user '$ORIGINAL_USER'. This is required for safety."
    refresh_pacman_database
    local paru_output
    if paru_output=$(run_as_user "paru -S --noconfirm --needed $pkgs_to_install" 2>&1 | tee /dev/stderr); then
        log_success "AUR packages installed successfully using paru: '$pkgs_to_install'."
        log_debug "paru -S output:\n$paru_output"
        return 0
    else
        log_error "Failed to install AUR packages using paru: '$pkgs_to_install'."
        log_error "paru -S error output:\n$paru_output"
        return 1
    fi
}
# ==============================================================================
# 统一智能安装函数 (推荐使用)
# ==============================================================================

# 在 package_management_utils.sh 中的 install_packages 函数

# _display_installation_summary 函数保持不变 (或略作调整以适应新参数，如果需要)
# 在 package_management_utils.sh 中

# _get_installed_aur_helper, refresh_pacman_database, is_package_installed, 等其他辅助函数保持不变...

# 在 package_management_utils.sh 中

# _get_installed_aur_helper, refresh_pacman_database, is_package_installed, 等其他辅助函数保持不变...

# @description (内部辅助函数) 显示软件包安装过程的详细摘要信息 (新版)。
# @param $1 (int) total_requested_count - 最初请求安装的总包数。
# @param $2 (int) already_installed_count (B_count) - 启动时就已安装的包数。
# @param $3 (string) already_installed_list_str (B_list) - 已安装包的列表。
# @param $4 (int) official_candidates_count (D_count) - 初步筛选后，认为是官方仓库候选的包数。
# @param $5 (string) official_candidates_list_str (D_list) - 官方仓库候选包的列表。
# @param $6 (int) aur_candidates_count (C_count) - 初步筛选后，被认为是 AUR 候选的包数。
# @param $7 (string) aur_candidates_list_str (C_list) - AUR 候选包的列表。
# @param $8 (int) pacman_success_count (E_count) - 通过 Pacman 成功安装的包数。
# @param $9 (string) pacman_success_list_str (E_list) - Pacman 成功安装包的列表。
# @param $10 (int) pacman_fail_official_count (N_count) - Pacman 尝试安装官方包但失败的包数。
# @param $11 (string) pacman_fail_official_list_str (N_list) - Pacman 安装失败的官方包列表。
# @param $12 (int) aur_success_count (F_count) - 通过 AUR 助手成功安装的包数。
# @param $13 (string) aur_success_list_str (F_list) - AUR 成功安装包的列表。
# @param $14 (int) aur_fail_count (G_count) - AUR 助手安装失败的包数。
# @param $15 (string) aur_fail_list_str (G_list) - AUR 安装失败包的列表。
_display_installation_summary() {
    local total_requested_count="$1"
    # B
    local already_installed_count="$2"
    local -a already_installed_list_arr=($3)
    # D
    local official_candidates_count="$4"
    local -a official_candidates_list_arr=($5)
    # C
    local aur_candidates_count="$6"
    local -a aur_candidates_list_arr=($7)
    # E
    local pacman_success_count="$8"
    local -a pacman_success_list_arr=($9)
    # N
    local pacman_fail_official_count="${10}"
    local -a pacman_fail_official_list_arr=(${11})
    # F
    local aur_success_count_final="${12}" # Renamed to avoid conflict with param $6
    local -a aur_success_list_arr=(${13})
    # G
    local aur_fail_count="${14}"
    local -a aur_fail_list_arr=(${15})

    local already_installed_display="${already_installed_list_arr[*]:-(无)}"
    local official_candidates_display="${official_candidates_list_arr[*]:-(无)}"
    local aur_candidates_display="${aur_candidates_list_arr[*]:-(无)}"
    local pacman_success_display="${pacman_success_list_arr[*]:-(无)}"
    local pacman_fail_official_display="${pacman_fail_official_list_arr[*]:-(无)}"
    local aur_success_display_final="${aur_success_list_arr[*]:-(无)}" # Renamed
    local aur_fail_display="${aur_fail_list_arr[*]:-(无)}"

    local total_successfully_installed=$((pacman_success_count + aur_success_count_final))
    local total_failed_to_install=$((pacman_fail_official_count + aur_fail_count))

    display_header_section "软件包安装摘要" "box" 80 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_WHITE}"

    log_summary "总共请求安装软件包数: ${COLOR_CYAN}${total_requested_count}${COLOR_RESET} 个"
    log_summary "----------------------------------------------------------------------"
    log_summary "${COLOR_BOLD}初始状态与分类:${COLOR_RESET}"
    log_summary "  启动时已安装 (B): ${COLOR_GREEN}${already_installed_count}${COLOR_RESET} 个"
    if [ "$already_installed_count" -gt 0 ]; then log_summary "    (${COLOR_DIM_GREEN:-$COLOR_GREEN}$already_installed_display${COLOR_RESET})"; fi

    log_summary "  待处理的官方仓库候选包 (D): ${COLOR_CYAN}${official_candidates_count}${COLOR_RESET} 个"
    if [ "$official_candidates_count" -gt 0 ]; then log_summary "    (${COLOR_DIM_GREEN:-$COLOR_GREEN}$official_candidates_display${COLOR_RESET})"; fi
    
    log_summary "  待处理的疑似 AUR 候选包 (C): ${COLOR_CYAN}${aur_candidates_count}${COLOR_RESET} 个"
    if [ "$aur_candidates_count" -gt 0 ]; then log_summary "    (${COLOR_DIM_GREEN:-$COLOR_GREEN}$aur_candidates_display${COLOR_RESET})"; fi
    
    log_summary "----------------------------------------------------------------------"
    log_summary "${COLOR_BOLD}安装执行结果:${COLOR_RESET}"
    log_summary "  通过 Pacman 成功安装 (E): ${COLOR_GREEN}${pacman_success_count}${COLOR_RESET} 个"
    if [ "$pacman_success_count" -gt 0 ]; then log_summary "    (${COLOR_DIM_GREEN:-$COLOR_GREEN}$pacman_success_display${COLOR_RESET})"; fi

    log_summary "  Pacman 安装失败的官方包 (N): ${COLOR_RED}${pacman_fail_official_count}${COLOR_RESET} 个"
    if [ "$pacman_fail_official_count" -gt 0 ]; then log_summary "    (${COLOR_BRIGHT_RED}$pacman_fail_official_display${COLOR_RESET})"; fi

    log_summary "  通过 AUR 助手成功安装 (F): ${COLOR_GREEN}${aur_success_count_final}${COLOR_RESET} 个"
    if [ "$aur_success_count_final" -gt 0 ]; then log_summary "    (${COLOR_DIM_GREEN:-$COLOR_GREEN}$aur_success_display_final${COLOR_RESET})"; fi

    log_summary "  AUR 助手安装失败的包 (G): ${COLOR_RED}${aur_fail_count}${COLOR_RESET} 个"
    if [ "$aur_fail_count" -gt 0 ]; then log_summary "    (${COLOR_BRIGHT_RED}$aur_fail_display${COLOR_RESET})"; fi

    log_summary "----------------------------------------------------------------------"
    log_summary "${COLOR_BOLD}最终统计:${COLOR_RESET}"
    log_summary "  共成功安装新软件包: ${COLOR_BRIGHT_GREEN}${total_successfully_installed}${COLOR_RESET} 个"
    log_summary "  共未能成功安装软件包: ${COLOR_BRIGHT_RED}${total_failed_to_install}${COLOR_RESET} 个"
    
    if [ "$total_failed_to_install" -gt 0 ]; then
        log_summary "${COLOR_YELLOW}请检查之前的日志以获取失败软件包的详细错误信息。${COLOR_RESET}"
    else
        log_summary "${COLOR_BRIGHT_GREEN}所有需要新安装的软件包均已成功处理！${COLOR_RESET}"
    fi
    log_summary "======================================================================" "" "${COLOR_BLUE}"
    echo
}


# install_packages()
# @description: (新描述 V2) 根据精细化流程安装软件包，区分官方和AUR，并提供详细摘要。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 如果所有请求的新安装包都成功, 1 如果有任何新安装包最终失败。
install_packages() {
    if [ "$#" -eq 0 ]; then log_warn "install_packages: 未指定软件包。"; return 0; fi

    # --- 初始化所有跟踪数组 ---
    local -a initial_requested_pkgs_array=() # 所有传入的包
    local -a pkgs_already_installed_on_entry_B=() # B: 初始就已安装
    local -a pkgs_to_process_initially_B_complement=() # A (B的补集): 初步筛选后需要处理的
    
    local -a pkgs_identified_for_aur_C=()      # C: 被识别为 AUR 包或 Pacman 首次尝试"未找到目标"的
    local -a pkgs_official_repo_candidates_D=() # D: 首次 Pacman 后，被认为是官方仓库的
    
    local -a pkgs_successfully_installed_by_pacman_E=() # E: 最终由 Pacman 成功安装的
    local -a pkgs_failed_to_install_by_pacman_N=()   # N: Pacman 尝试官方包但失败的
    
    local -a pkgs_successfully_installed_by_aur_F=() # F: 最终由 AUR 助手成功安装的
    local -a pkgs_failed_to_install_by_aur_G=()    # G: AUR 助手安装失败的

    # --- 输入处理 ---
    if [ "$#" -eq 1 ] && [[ "$1" == *" "* ]]; then read -r -a initial_requested_pkgs_array <<< "$1"; else initial_requested_pkgs_array=("$@"); fi
    local total_initial_requested_count=${#initial_requested_pkgs_array[@]}
    log_info "收到 ${total_initial_requested_count} 个软件包的安装请求: ${initial_requested_pkgs_array[*]}"

    # --- 阶段 0: 准备工作 ---
    if ! refresh_pacman_database; then
        log_error "刷新 Pacman 数据库失败。中止软件包安装。"
        # 此时所有请求的包都视为失败
        _display_installation_summary "$total_initial_requested_count" \
            0 "" \
            0 "" \
            0 "" \
            0 "" \
            "$total_initial_requested_count" "${initial_requested_pkgs_array[*]}" \
            0 "" \
            0 ""
        return 1
    fi

    # --- 阶段 1: 检查真实需要安装的 (填充 A 和 B) ---
    display_header_section "软件包安装流程" "sub_box" 70
    log_info "阶段 1: 检查初始安装状态..."
    for pkg in "${initial_requested_pkgs_array[@]}"; do
        if is_package_installed "$pkg"; then
            pkgs_already_installed_on_entry_B+=("$pkg")
        else
            pkgs_to_process_initially_B_complement+=("$pkg")
        fi
    done
    # (可选去重B和A，但如果输入列表本身是干净的则不需要)

    if [ ${#pkgs_already_installed_on_entry_B[@]} -gt 0 ]; then
        log_success "以下 ${#pkgs_already_installed_on_entry_B[@]} 个包已安装 (B): ${pkgs_already_installed_on_entry_B[*]}"
    fi
    if [ ${#pkgs_to_process_initially_B_complement[@]} -eq 0 ]; then
        log_success "所有请求的包均已安装。"; 
        _display_installation_summary "$total_initial_requested_count" \
            "${#pkgs_already_installed_on_entry_B[@]}" "${pkgs_already_installed_on_entry_B[*]}" \
            0 "" 0 "" \
            0 "" 0 "" 0 "" 0 ""
        return 0;
    fi
    log_notice "将处理 ${#pkgs_to_process_initially_B_complement[@]} 个未安装的包 (A): ${pkgs_to_process_initially_B_complement[*]}"; echo

    # --- 阶段 2: 初步筛查分类 (对 B_complement/A 操作，填充 C 和 D) ---
    log_info "阶段 2: 使用 Pacman 初步筛查，区分官方与疑似AUR包..."
    local pacman_scan_output; local pacman_scan_failed_flag=false
    # 使用 --print 选项代替 -S，这样 pacman 只会查找包而不会尝试安装或下载
    # 这可以更快地识别 "target not found"
    # 注意：--print 可能不会检查所有依赖，但对于识别 AUR 包足够了
    # 我们仍然需要捕获错误，因为如果所有包都是官方的，--print 可能会成功（返回0）
    # 或者，如果列表为空，pacman --print 可能会报错
    if [ ${#pkgs_to_process_initially_B_complement[@]} -gt 0 ]; then
        # pacman_scan_output=$(pacman -S --noconfirm --needed --assume-installed "${pkgs_already_installed_on_entry_B[@]}" "${pkgs_to_process_initially_B_complement[@]}" 2>&1) || pacman_scan_failed_flag=true
        # 使用 -Sp 来仅打印目标，不执行操作。这能快速识别哪些包是官方的。
        # 然而，-Sp 对于不存在的包会直接报错退出，可能不适合批量识别。
        # 还是用第一次尝试安装的方式来识别，但主要看输出。
        pacman_scan_output=$(pacman -S --noconfirm --needed "${pkgs_to_process_initially_B_complement[@]}" 2>&1) || pacman_scan_failed_flag=true
    else
        pacman_scan_failed_flag=false # 没有包需要处理，所以不算失败
        pacman_scan_output=""
    fi

    local -a pacman_scan_output_lines; mapfile -t pacman_scan_output_lines <<< "$pacman_scan_output"
    for line in "${pacman_scan_output_lines[@]}"; do
        if [[ "$line" =~ error:[[:space:]]+target[[:space:]]+not[[:space:]]+found:[[:space:]]+([^[:space:]]+) ]] || \
           [[ "$line" =~ 错误：未找到目标：([^[:space:]]+) ]]; then
            pkgs_identified_for_aur_C+=("${BASH_REMATCH[1]}")
        fi
    done
    # 去重 C
    if ((BASH_VERSINFO[0] >= 4 && ${#pkgs_identified_for_aur_C[@]} > 0)); then declare -A s; local t=(); for i in "${pkgs_identified_for_aur_C[@]}"; do if [[ -z "${s[$i]:-}" ]]; then t+=("$i"); s[$i]=1; fi; done; pkgs_identified_for_aur_C=("${t[@]}"); elif [ ${#pkgs_identified_for_aur_C[@]} -gt 0 ]; then local su=$(printf "%s\n" "${pkgs_identified_for_aur_C[@]}"|sort -u|tr '\n' ' '); read -r -a pkgs_identified_for_aur_C <<< "${su% }"; fi

    for pkg_in_A in "${pkgs_to_process_initially_B_complement[@]}"; do
        local is_aur=false; for aur_c in "${pkgs_identified_for_aur_C[@]}"; do if [[ "$pkg_in_A" == "$aur_c" ]]; then is_aur=true; break; fi; done
        if ! $is_aur; then pkgs_official_repo_candidates_D+=("$pkg_in_A"); fi
    done
    # 去重 D
    if ((BASH_VERSINFO[0] >= 4 && ${#pkgs_official_repo_candidates_D[@]} > 0)); then declare -A s; local t=(); for i in "${pkgs_official_repo_candidates_D[@]}"; do if [[ -z "${s[$i]:-}" ]]; then t+=("$i"); s[$i]=1; fi; done; pkgs_official_repo_candidates_D=("${t[@]}"); elif [ ${#pkgs_official_repo_candidates_D[@]} -gt 0 ]; then local su=$(printf "%s\n" "${pkgs_official_repo_candidates_D[@]}"|sort -u|tr '\n' ' '); read -r -a pkgs_official_repo_candidates_D <<< "${su% }"; fi

    log_debug "Pacman 扫描输出:\n${pacman_scan_output}"
    log_info "官方仓库候选包 (D): ${#pkgs_official_repo_candidates_D[@]} 个 ${pkgs_official_repo_candidates_D[*]}"
    log_info "疑似 AUR 候选包 (C): ${#pkgs_identified_for_aur_C[@]} 个 ${pkgs_identified_for_aur_C[*]}"; echo

    # --- 阶段 3: 精确安装官方仓库候选包 (D)，填充 E 和 N ---
    if [ ${#pkgs_official_repo_candidates_D[@]} -gt 0 ]; then
        log_info "阶段 3: 安装 ${#pkgs_official_repo_candidates_D[@]} 个官方仓库包..."
        local pacman_install_D_output; local pacman_install_D_failed_flag=false
        if ! pacman_install_D_output=$(pacman -S --noconfirm --needed "${pkgs_official_repo_candidates_D[@]}" 2>&1 | tee /dev/stderr); then
            pacman_install_D_failed_flag=true
        fi
        for pkg_d_item in "${pkgs_official_repo_candidates_D[@]}"; do
            if is_package_installed "$pkg_d_item"; then pkgs_successfully_installed_by_pacman_E+=("$pkg_d_item");
            else pkgs_failed_to_install_by_pacman_N+=("$pkg_d_item"); fi
        done
        if [ ${#pkgs_successfully_installed_by_pacman_E[@]} -gt 0 ]; then log_success "Pacman 成功安装 (E): ${#pkgs_successfully_installed_by_pacman_E[@]} 个 ${pkgs_successfully_installed_by_pacman_E[*]}"; fi
        if [ ${#pkgs_failed_to_install_by_pacman_N[@]} -gt 0 ]; then log_error "Pacman 安装失败 (N): ${#pkgs_failed_to_install_by_pacman_N[@]} 个 ${pkgs_failed_to_install_by_pacman_N[*]}"; fi
    else log_info "阶段 3: 无官方仓库包需要安装。"; fi
    echo

    # --- 阶段 4: 尝试使用 AUR 助手安装 (C)，填充 F 和 G ---
    if [ ${#pkgs_identified_for_aur_C[@]} -gt 0 ]; then
        log_info "阶段 4: 尝试安装 ${#pkgs_identified_for_aur_C[@]} 个 AUR 包..."
        local aur_helper; aur_helper=$(_get_installed_aur_helper)
        if [ -z "$aur_helper" ]; then
            log_error "未找到 AUR 助手。以下包无法从 AUR 安装: ${pkgs_identified_for_aur_C[*]}"
            pkgs_failed_to_install_by_aur_G+=("${pkgs_identified_for_aur_C[@]}") # 所有这些都失败
        else
            log_info "使用 AUR 助手 '$aur_helper'..."
            local aur_install_output; local aur_failed_flag=false
            if ! aur_install_output=$(run_as_user "$aur_helper -S --noconfirm --needed ${pkgs_identified_for_aur_C[*]}" 2>&1 | tee /dev/stderr); then
                aur_failed_flag=true
            fi
            if $aur_failed_flag; then log_warn "AUR 助手 '$aur_helper' 执行时返回了错误状态。"; fi
            for pkg_c_item in "${pkgs_identified_for_aur_C[@]}"; do
                if is_package_installed "$pkg_c_item"; then pkgs_successfully_installed_by_aur_F+=("$pkg_c_item");
                else pkgs_failed_to_install_by_aur_G+=("$pkg_c_item"); fi
            done
            if [ ${#pkgs_successfully_installed_by_aur_F[@]} -gt 0 ]; then log_success "AUR 成功安装 (F): ${#pkgs_successfully_installed_by_aur_F[@]} 个 ${pkgs_successfully_installed_by_aur_F[*]}"; fi
            if [ ${#pkgs_failed_to_install_by_aur_G[@]} -gt 0 ]; then log_error "AUR 安装失败 (G): ${#pkgs_failed_to_install_by_aur_G[@]} 个 ${pkgs_failed_to_install_by_aur_G[*]}"; fi
        fi
    else log_info "阶段 4: 无 AUR 包需要安装。"; fi
    echo

    # --- 阶段 5: 摘要展示 ---
    # (确保所有统计数组在传递前都是最新的，如果前面有去重逻辑，则它们已去重)
    _display_installation_summary "$total_initial_requested_count" \
        "${#pkgs_already_installed_on_entry_B[@]}" "${pkgs_already_installed_on_entry_B[*]}" \
        "${#pkgs_official_repo_candidates_D[@]}" "${pkgs_official_repo_candidates_D[*]}" \
        "${#pkgs_identified_for_aur_C[@]}" "${pkgs_identified_for_aur_C[*]}" \
        "${#pkgs_successfully_installed_by_pacman_E[@]}" "${pkgs_successfully_installed_by_pacman_E[*]}" \
        "${#pkgs_failed_to_install_by_pacman_N[@]}" "${pkgs_failed_to_install_by_pacman_N[*]}" \
        "${#pkgs_successfully_installed_by_aur_F[@]}" "${pkgs_successfully_installed_by_aur_F[*]}" \
        "${#pkgs_failed_to_install_by_aur_G[@]}" "${pkgs_failed_to_install_by_aur_G[*]}"

    if [ ${#pkgs_failed_to_install_by_pacman_N[@]} -gt 0 ] || [ ${#pkgs_failed_to_install_by_aur_G[@]} -gt 0 ]; then
        return 1
    else
        return 0
    fi
}
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="true"
log_debug "Package management utilities sourced and available (v1.0.3)."

# 有问题，没法正确记录