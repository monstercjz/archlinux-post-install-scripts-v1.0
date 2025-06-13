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

# 在 package_management_utils.sh 中

# _get_installed_aur_helper, refresh_pacman_database, is_package_installed, 等其他辅助函数保持不变...

# @description (内部辅助函数) 显示软件包安装过程的摘要信息。
# @param $1 (int) total_requested - 最初请求安装的总包数。
# @param $2 (int) already_installed_count - 开始时就已安装的包数。
# @param $3 (int) pacman_success_count - 通过 Pacman 成功安装的包数。
# @param $4 (int) aur_success_count - 通过 AUR 助手成功安装的包数。
# @param $5 (int) final_fail_count - 最终安装失败的包数。
# @param $6 (string) already_installed_list_str - 已安装包的列表 (空格分隔)。
# @param $7 (string) pacman_success_list_str - Pacman 成功安装包的列表。
# @param $8 (string) aur_success_list_str - AUR 成功安装包的列表。
# @param $9 (string) final_fail_list_str - 最终失败包的列表。
_display_installation_summary() {
    local total_requested="$1"
    local already_installed_count="$2"
    local pacman_success_count="$3"
    local aur_success_count="$4"
    local final_fail_count="$5"
    # 将列表字符串转换为数组以便更好地处理（特别是当列表为空时）
    local -a already_installed_list_arr=($6) # $6 是字符串，这里会被词法分割
    local -a pacman_success_list_arr=($7)
    local -a aur_success_list_arr=($8)
    local -a final_fail_list_arr=($9)

    # 准备要显示的列表字符串，如果数组为空则显示 (无)
    local already_installed_display="${already_installed_list_arr[*]:-(无)}"
    local pacman_success_display="${pacman_success_list_arr[*]:-(无)}"
    local aur_success_display="${aur_success_list_arr[*]:-(无)}"
    local final_fail_display="${final_fail_list_arr[*]:-(无)}"


    display_header_section "软件包安装摘要" "box" 70 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_WHITE}"

    log_summary "总共请求安装软件包: ${COLOR_CYAN}${total_requested}${COLOR_RESET} 个"
    log_summary "--------------------------------------------------"

    log_summary "启动时已安装: ${COLOR_GREEN}${already_installed_count}${COLOR_RESET} 个"
    if [ "$already_installed_count" -gt 0 ]; then
        # 假设 COLOR_DIM_GREEN 已在 utils.sh 中定义，例如 export readonly COLOR_DIM_GREEN="${ESC}2;32m"
        # 如果未定义，可以替换为 COLOR_GREEN 或其他颜色
        log_summary "  ${COLOR_DIM_GREEN:-$COLOR_GREEN}($already_installed_display)${COLOR_RESET}"
    fi

    log_summary "通过 Pacman (官方仓库) 成功安装: ${COLOR_GREEN}${pacman_success_count}${COLOR_RESET} 个"
    if [ "$pacman_success_count" -gt 0 ]; then
        log_summary "  ${COLOR_DIM_GREEN:-$COLOR_GREEN}($pacman_success_display)${COLOR_RESET}"
    fi

    log_summary "通过 AUR 助手成功安装: ${COLOR_GREEN}${aur_success_count}${COLOR_RESET} 个"
    if [ "$aur_success_count" -gt 0 ]; then
        log_summary "  ${COLOR_DIM_GREEN:-$COLOR_GREEN}($aur_success_display)${COLOR_RESET}"
    fi
    
    log_summary "--------------------------------------------------"
    if [ "$final_fail_count" -gt 0 ]; then
        log_summary "最终未能成功安装: ${COLOR_RED}${final_fail_count}${COLOR_RESET} 个"
        log_summary "  ${COLOR_BRIGHT_RED}($final_fail_display)${COLOR_RESET}"
        log_summary "${COLOR_YELLOW}请检查之前的日志以获取这些失败软件包的详细错误信息。${COLOR_RESET}"
    else
        log_summary "${COLOR_BRIGHT_GREEN}所有需要安装的软件包均已成功处理！${COLOR_RESET}"
    fi
    log_summary "==================================================" "" "${COLOR_BLUE}"
    echo # 空行
}


# install_packages()
# @description: 智能地安装一个或多个软件包。它会自动检测包的来源（官方仓库或 AUR），
#                并使用合适的包管理器（pacman, yay, paru）进行高效的批量安装。
#                此函数可以接受多个参数 (pkg1 pkg2 ...)，也可以接受一个包含空格的字符串 ("pkg1 pkg2 ...")。
#                函数末尾会输出安装摘要。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 如果所有请求的包都成功安装或已是最新, 1 如果有任何包最终安装失败。
install_packages() {
    if [ "$#" -eq 0 ]; then
        log_warn "install_packages: 未指定任何要安装的软件包。"
        return 0
    fi

    # --- 初始化计数器和列表数组 ---
    local -a initial_requested_pkgs_array=() # 使用 -a 显式声明为数组
    local -a pkgs_already_installed_on_entry=()
    local -a pkgs_to_attempt_install=()
    
    local -a pkgs_successfully_installed_by_pacman=()
    local -a pkgs_identified_for_aur=()
    local -a pkgs_successfully_installed_by_aur=()
    local -a pkgs_failed_final=()

    # --- 智能输入处理 ---
    if [ "$#" -eq 1 ] && [[ "$1" == *" "* ]]; then
        # 如果只有一个参数且包含空格，则按空格分割
        read -r -a initial_requested_pkgs_array <<< "$1"
    else
        # 否则将所有参数视为一个列表
        initial_requested_pkgs_array=("$@")
    fi
    local total_initial_requested_count=${#initial_requested_pkgs_array[@]}
    log_info "收到 ${total_initial_requested_count} 个软件包的安装请求: ${initial_requested_pkgs_array[*]}"

    # --- 步骤 0: 刷新数据库 ---
    if ! refresh_pacman_database; then
        log_error "刷新 Pacman 数据库失败。中止软件包安装。"
        # 在此阶段，还没有包被处理，所以摘要可以简化
        _display_installation_summary "$total_initial_requested_count" 0 0 0 "$total_initial_requested_count" "" "" "" "${initial_requested_pkgs_array[*]}"
        return 1
    fi

    # --- 步骤 1: 检查初始安装状态 ---
    display_header_section "软件包安装状态检查与执行" "sub_box" 70
    log_info "步骤 1/${total_initial_requested_count}: 检查软件包初始安装状态..."
    for pkg in "${initial_requested_pkgs_array[@]}"; do
        if is_package_installed "$pkg"; then
            pkgs_already_installed_on_entry+=("$pkg")
        else
            pkgs_to_attempt_install+=("$pkg")
        fi
    done

    if [ ${#pkgs_already_installed_on_entry[@]} -gt 0 ]; then
        log_success "以下 ${#pkgs_already_installed_on_entry[@]} 个软件包已安装，将跳过: ${pkgs_already_installed_on_entry[*]}"
    fi

    if [ ${#pkgs_to_attempt_install[@]} -eq 0 ]; then
        log_success "所有请求的软件包均已安装。无需额外操作。"
        _display_installation_summary "$total_initial_requested_count" \
                                      "${#pkgs_already_installed_on_entry[@]}" \
                                      0 0 0 \
                                      "${pkgs_already_installed_on_entry[*]}" \
                                      "" "" ""
        return 0
    fi
    log_notice "将要尝试安装以下 ${#pkgs_to_attempt_install[@]} 个未安装的软件包: ${pkgs_to_attempt_install[*]}"
    echo

    # --- 步骤 2: Pacman 安装尝试 ---
    log_info "步骤 2: 尝试从官方仓库 (pacman) 安装 ${#pkgs_to_attempt_install[@]} 个软件包..."
    local pacman_output
    local pacman_failed_flag=false
    
    # 将数组作为参数传递给 pacman
    pacman_output=$(pacman -S --noconfirm --needed "${pkgs_to_attempt_install[@]}" 2>&1 | tee /dev/stderr) || pacman_failed_flag=true

    # --- 步骤 3: 解析 Pacman 结果 ---
    log_info "步骤 3: 解析 Pacman 安装结果..."
    local -a pacman_output_lines # 显式声明为数组
    mapfile -t pacman_output_lines <<< "$pacman_output"
    for line in "${pacman_output_lines[@]}"; do
        if [[ "$line" =~ error:[[:space:]]+target[[:space:]]+not[[:space:]]+found:[[:space:]]+([^[:space:]]+) ]] || \
           [[ "$line" =~ 错误：未找到目标：([^[:space:]]+) ]]; then # 注意中文冒号
            pkgs_identified_for_aur+=("${BASH_REMATCH[1]}")
        fi
    done
    # 去重 pkgs_identified_for_aur
    if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_identified_for_aur[@]} > 0 )); then
        declare -A seen; local temp_array=();
        for item in "${pkgs_identified_for_aur[@]}"; do if [[ -z "${seen[$item]:-}" ]]; then temp_array+=("$item"); seen[$item]=1; fi; done
        pkgs_identified_for_aur=("${temp_array[@]}")
    elif [ ${#pkgs_identified_for_aur[@]} -gt 0 ]; then # Bash 3 回退
        local sorted_unique_str=$(printf "%s\n" "${pkgs_identified_for_aur[@]}" | sort -u | tr '\n' ' '); read -r -a pkgs_identified_for_aur <<< "${sorted_unique_str% }";
    fi
    log_debug "Pacman raw output for parsing errors:\n${pacman_output}"
    log_debug "Packages parsed by pacman as 'target not found': ${pkgs_identified_for_aur[*]}"


    for pkg in "${pkgs_to_attempt_install[@]}"; do
        local is_aur_candidate=false
        for aur_pkg in "${pkgs_identified_for_aur[@]}"; do if [[ "$pkg" == "$aur_pkg" ]]; then is_aur_candidate=true; break; fi; done
        # 如果不是AUR候选包，并且现在检查是已安装状态，则认为是pacman成功安装的
        if ! $is_aur_candidate && is_package_installed "$pkg"; then
            pkgs_successfully_installed_by_pacman+=("$pkg")
        fi
    done
    # 去重 pkgs_successfully_installed_by_pacman
    if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_successfully_installed_by_pacman[@]} > 0 )); then
        declare -A seen; local temp_array=();
        for item in "${pkgs_successfully_installed_by_pacman[@]}"; do if [[ -z "${seen[$item]:-}" ]]; then temp_array+=("$item"); seen[$item]=1; fi; done
        pkgs_successfully_installed_by_pacman=("${temp_array[@]}")
    elif [ ${#pkgs_successfully_installed_by_pacman[@]} -gt 0 ]; then
        local sorted_unique_str=$(printf "%s\n" "${pkgs_successfully_installed_by_pacman[@]}" | sort -u | tr '\n' ' '); read -r -a pkgs_successfully_installed_by_pacman <<< "${sorted_unique_str% }";
    fi


    if [ ${#pkgs_successfully_installed_by_pacman[@]} -gt 0 ]; then
         log_success "已通过 Pacman 成功安装 ${#pkgs_successfully_installed_by_pacman[@]} 个软件包: ${pkgs_successfully_installed_by_pacman[*]}"
    fi

    if $pacman_failed_flag && [ ${#pkgs_identified_for_aur[@]} -eq 0 ] && [ ${#pkgs_successfully_installed_by_pacman[@]} -lt ${#pkgs_to_attempt_install[@]} ]; then
        log_error "Pacman 安装失败，且原因并非'未找到目标'。这通常是严重错误 (网络、GPG、文件冲突等)。"
        log_error "Pacman 输出详情:\n${pacman_output}"
        for pkg_fail in "${pkgs_to_attempt_install[@]}"; do
            local already_successful_pacman=false
            for suc_pkg in "${pkgs_successfully_installed_by_pacman[@]}"; do if [[ "$pkg_fail" == "$suc_pkg" ]]; then already_successful_pacman=true; break; fi; done
            if ! $already_successful_pacman; then pkgs_failed_final+=("$pkg_fail"); fi
        done
        # 去重 pkgs_failed_final (即使是错误路径，也保持一致性)
        if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_failed_final[@]} > 0 )); then
            declare -A seen; local temp_array=(); for item in "${pkgs_failed_final[@]}"; do if [[ -z "${seen[$item]:-}" ]]; then temp_array+=("$item"); seen[$item]=1; fi; done; pkgs_failed_final=("${temp_array[@]}");
        elif [ ${#pkgs_failed_final[@]} -gt 0 ]; then local sus=$(printf "%s\n" "${pkgs_failed_final[@]}"|sort -u|tr '\n' ' '); read -r -a pkgs_failed_final <<< "${sus% }"; fi

        _display_installation_summary "$total_initial_requested_count" \
                                      "${#pkgs_already_installed_on_entry[@]}" \
                                      "${#pkgs_successfully_installed_by_pacman[@]}" \
                                      0 \
                                      "${#pkgs_failed_final[@]}" \
                                      "${pkgs_already_installed_on_entry[*]}" \
                                      "${pkgs_successfully_installed_by_pacman[*]}" \
                                      "" \
                                      "${pkgs_failed_final[*]}"
        return 1
    fi

    if [ ${#pkgs_identified_for_aur[@]} -eq 0 ]; then
        # 计算最终失败的包 (即 pacman_failed_flag 为 true，但又不是 AUR 包，且未成功安装的)
        if $pacman_failed_flag; then
            log_error "Pacman 执行时遇到错误，但所有包似乎都在官方仓库中。请检查 Pacman 输出。"
            log_error "$(echo -e "\n${pacman_output}")"
            for pkg_f in "${pkgs_to_attempt_install[@]}"; do
                local found_success=false
                for suc_p in "${pkgs_successfully_installed_by_pacman[@]}"; do if [[ "$pkg_f" == "$suc_p" ]]; then found_success=true; break; fi; done
                if ! $found_success; then pkgs_failed_final+=("$pkg_f"); fi
            done
            # 去重
            if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_failed_final[@]} > 0 )); then declare -A s; local t=(); for i in "${pkgs_failed_final[@]}"; do if [[ -z "${s[$i]:-}" ]]; then t+=("$i"); s[$i]=1; fi; done; pkgs_failed_final=("${t[@]}"); elif [ ${#pkgs_failed_final[@]} -gt 0 ]; then local su=$(printf "%s\n" "${pkgs_failed_final[@]}"|sort -u|tr '\n' ' '); read -r -a pkgs_failed_final <<< "${su% }"; fi
        fi
        log_success "所有需要安装的软件包均已通过 Pacman 处理。"
         _display_installation_summary "$total_initial_requested_count" \
                                      "${#pkgs_already_installed_on_entry[@]}" \
                                      "${#pkgs_successfully_installed_by_pacman[@]}" \
                                      0 \
                                      "${#pkgs_failed_final[@]}" \
                                      "${pkgs_already_installed_on_entry[*]}" \
                                      "${pkgs_successfully_installed_by_pacman[*]}" \
                                      "" \
                                      "${pkgs_failed_final[*]}"
        return ${#pkgs_failed_final[@]} -eq 0 ? 0 : 1
    fi

    log_notice "以下 ${#pkgs_identified_for_aur[@]} 个软件包将尝试从 AUR 安装: ${pkgs_identified_for_aur[*]}"
    echo

    # --- 步骤 4: AUR 助手安装 ---
    local aur_helper; aur_helper=$(_get_installed_aur_helper)
    if [ -z "$aur_helper" ]; then
        log_error "未找到 AUR 助手 (yay 或 paru)。无法安装 AUR 包: ${pkgs_identified_for_aur[*]}"
        pkgs_failed_final+=("${pkgs_identified_for_aur[@]}") # 所有这些都失败
        # 去重 (此处也添加，以防万一)
        if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_failed_final[@]} > 0 )); then declare -A s; local t=(); for i in "${pkgs_failed_final[@]}"; do if [[ -z "${s[$i]:-}" ]]; then t+=("$i"); s[$i]=1; fi; done; pkgs_failed_final=("${t[@]}"); elif [ ${#pkgs_failed_final[@]} -gt 0 ]; then local su=$(printf "%s\n" "${pkgs_failed_final[@]}"|sort -u|tr '\n' ' '); read -r -a pkgs_failed_final <<< "${su% }"; fi
        _display_installation_summary "$total_initial_requested_count" \
                                      "${#pkgs_already_installed_on_entry[@]}" \
                                      "${#pkgs_successfully_installed_by_pacman[@]}" \
                                      0 \
                                      "${#pkgs_failed_final[@]}" \
                                      "${pkgs_already_installed_on_entry[*]}" \
                                      "${pkgs_successfully_installed_by_pacman[*]}" \
                                      "" \
                                      "${pkgs_failed_final[*]}"
        return 1
    fi
    
    log_info "步骤 4: 使用 AUR 助手 '$aur_helper' 安装 ${#pkgs_identified_for_aur[@]} 个软件包..."
    local aur_install_output
    local aur_failed_flag=false
    
    # 将数组作为参数传递给 run_as_user 和 AUR 助手
    aur_install_output=$(run_as_user "$aur_helper -S --noconfirm --needed ${pkgs_identified_for_aur[*]}" 2>&1 | tee /dev/stderr) || aur_failed_flag=true

    if $aur_failed_flag; then
         log_warn "AUR 助手 '$aur_helper' 执行时返回了错误状态。正在检查哪些包实际安装成功..."
    fi

    for pkg_aur_check in "${pkgs_identified_for_aur[@]}"; do
        if is_package_installed "$pkg_aur_check"; then
            pkgs_successfully_installed_by_aur+=("$pkg_aur_check")
        else
            # 避免重复添加
            local already_failed=false
            for pf in "${pkgs_failed_final[@]}"; do if [[ "$pf" == "$pkg_aur_check" ]]; then already_failed=true; break; fi; done
            if ! $already_failed; then pkgs_failed_final+=("$pkg_aur_check"); fi
        fi
    done
    # 去重 pkgs_successfully_installed_by_aur
    if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_successfully_installed_by_aur[@]} > 0 )); then
        declare -A seen; local temp_array=();
        for item in "${pkgs_successfully_installed_by_aur[@]}"; do if [[ -z "${seen[$item]:-}" ]]; then temp_array+=("$item"); seen[$item]=1; fi; done
        pkgs_successfully_installed_by_aur=("${temp_array[@]}")
    elif [ ${#pkgs_successfully_installed_by_aur[@]} -gt 0 ]; then
        local sorted_unique_str=$(printf "%s\n" "${pkgs_successfully_installed_by_aur[@]}" | sort -u | tr '\n' ' '); read -r -a pkgs_successfully_installed_by_aur <<< "${sorted_unique_str% }";
    fi
    # 去重 pkgs_failed_final
    if (( BASH_VERSINFO[0] >= 4 && ${#pkgs_failed_final[@]} > 0 )); then
        declare -A seen; local temp_array=();
        for item in "${pkgs_failed_final[@]}"; do if [[ -z "${seen[$item]:-}" ]]; then temp_array+=("$item"); seen[$item]=1; fi; done
        pkgs_failed_final=("${temp_array[@]}")
    elif [ ${#pkgs_failed_final[@]} -gt 0 ]; then
        local sorted_unique_str=$(printf "%s\n" "${pkgs_failed_final[@]}" | sort -u | tr '\n' ' '); read -r -a pkgs_failed_final <<< "${sorted_unique_str% }";
    fi


    if [ ${#pkgs_successfully_installed_by_aur[@]} -gt 0 ]; then
        log_success "已通过 AUR 助手 '$aur_helper' 成功安装 ${#pkgs_successfully_installed_by_aur[@]} 个软件包: ${pkgs_successfully_installed_by_aur[*]}"
    fi
    
    # --- 生成最终摘要 ---
    _display_installation_summary "$total_initial_requested_count" \
                                  "${#pkgs_already_installed_on_entry[@]}" \
                                  "${#pkgs_successfully_installed_by_pacman[@]}" \
                                  "${#pkgs_successfully_installed_by_aur[@]}" \
                                  "${#pkgs_failed_final[@]}" \
                                  "${pkgs_already_installed_on_entry[*]}" \
                                  "${pkgs_successfully_installed_by_pacman[*]}" \
                                  "${pkgs_successfully_installed_by_aur[*]}" \
                                  "${pkgs_failed_final[*]}"

    if [ ${#pkgs_failed_final[@]} -gt 0 ]; then
        log_error "部分软件包未能成功安装。"
        return 1
    else
        log_success "所有请求的软件包均已成功处理！"
        return 0
    fi
}
# _get_installed_aur_helper, refresh_pacman_database, is_package_installed, clean_pacman_cache, clean_aur_cache, _read_pkg_list_from_file, install_pacman_pkg, install_yay_pkg, install_paru_pkg 等其他函数保持不变...
# 标记此初始化脚本已被加载 (不导出)
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="true"
log_debug "Package management utilities sourced and available (v1.0.3)."

# 有问题，没法正确记录