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
    if pacman_output=$(pacman -S --noconfirm --needed $pkgs_to_install 2>&1); then
        log_success "Official packages installed successfully: '$pkgs_to_install'."
        # 使用 log_debug 记录详细输出，避免刷屏，但在需要时可查
        log_info "Pacman -S output:\n$pacman_output"
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
    if yay_output=$(run_as_user "yay -S --noconfirm --needed $pkgs_to_install" 2>&1); then
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
    if paru_output=$(run_as_user "paru -S --noconfirm --needed $pkgs_to_install" 2>&1); then
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

# install_packages()
# @description: 智能地安装一个或多个软件包。它会自动检测包的来源（官方仓库或 AUR），
#                并使用合适的包管理器（pacman, yay, paru）进行高效的批量安装。
# @param: $@ (strings) - 一个或多个要安装的软件包名称。
# @returns: 0 如果所有请求的包都成功安装或已安装, 1 如果有任何包最终安装失败。
install_packages() {
    if [ "$#" -eq 0 ]; then
        log_warn "install_packages: 未指定任何要安装的软件包。"
        return 0
    fi

    local all_pkgs_to_process=("$@")
    local pkgs_to_install=()
    local pkgs_already_installed=()

    display_header_section "智能软件包安装程序" "box"
    log_info "请求安装的软件包 (${#all_pkgs_to_process[@]} 个): ${all_pkgs_to_process[*]}"

    # --- 步骤 1: 检查哪些包已经安装 ---
    log_info "步骤 1/4: 检查软件包安装状态..."
    for pkg in "${all_pkgs_to_process[@]}"; do
        if is_package_installed "$pkg"; then
            pkgs_already_installed+=("$pkg")
        else
            pkgs_to_install+=("$pkg")
        fi
    done

    if [ ${#pkgs_already_installed[@]} -gt 0 ]; then
        log_success "以下软件包已安装，将跳过 (${#pkgs_already_installed[@]} 个): ${pkgs_already_installed[*]}"
    fi

    if [ ${#pkgs_to_install[@]} -eq 0 ]; then
        log_success "所有请求的软件包均已安装。无需任何操作。"
        return 0
    fi

    log_notice "将要尝试安装以下未安装的软件包 (${#pkgs_to_install[@]} 个): ${pkgs_to_install[*]}"

    # --- 步骤 2: 优先尝试用 pacman 一次性安装所有包 (高效) ---
    log_info "步骤 2/4: 尝试从官方仓库 (pacman) 一次性安装..."
    local pacman_output
    local pacman_failed=false
    
    # 注意：我们直接调用 pacman，而不是 install_pacman_pkg，因为我们需要捕获其原始输出进行解析。
    # `install_pacman_pkg` 内部有自己的日志逻辑，会干扰我们的解析。
    # 使用 `|| pacman_failed=true` 来捕获非零退出码，防止 `set -e` 中止脚本。
    pacman_output=$(pacman -S --noconfirm --needed "${pkgs_to_install[@]}" 2>&1) || pacman_failed=true

    if ! $pacman_failed; then
        log_success "所有请求的软件包均已通过 pacman 成功安装！"
        log_info "Pacman 输出:\n$pacman_output"
        return 0
    fi
    
    # --- 步骤 3: 解析 pacman 输出，找出失败的包 ---
    log_info "步骤 3/4: pacman 未能安装部分软件包，正在解析失败列表..."
    local pkgs_failed_pacman=()
    # pacman 失败时通常会输出 "error: target not found: <package>"
    # 我们用这个模式来精确地找出哪些包需要交由 AUR 助手处理。
    pkgs_failed_pacman=($(echo "$pacman_output" | grep -oP 'target not found: \K\S+'))

    if [ ${#pkgs_failed_pacman[@]} -eq 0 ]; then
        # 如果 pacman 失败了，但我们没有解析出任何“未找到”的包，
        # 那说明是其他严重错误（如网络问题、GPG密钥问题、文件冲突等）。
        log_error "Pacman 安装失败，但原因并非'未找到目标'。这通常是严重错误。"
        log_error "请检查 pacman 输出以确定问题:"
        # 将原始输出以错误级别记录，方便调试
        log_error "$(echo -e "\n${pacman_output}")"
        return 1
    fi
    
    # 从失败列表中排除那些实际上成功了的包（如果有的话）
    local successfully_installed_by_pacman=()
    for pkg in "${pkgs_to_install[@]}"; do
        # 如果一个包不在失败列表里，那它就是成功了
        if ! [[ " ${pkgs_failed_pacman[*]} " =~ " ${pkg} " ]]; then
            successfully_installed_by_pacman+=("$pkg")
        fi
    done

    if [ ${#successfully_installed_by_pacman[@]} -gt 0 ]; then
         log_success "已通过 pacman 成功安装 (${#successfully_installed_by_pacman[@]} 个): ${successfully_installed_by_pacman[*]}"
    fi

    log_notice "以下软件包在官方仓库未找到，将尝试从 AUR 安装 (${#pkgs_failed_pacman[@]} 个): ${pkgs_failed_pacman[*]}"

    # --- 步骤 4: 对于 pacman 失败的包，回退到 AUR 助手 ---
    local aur_helper
    aur_helper=$(_get_installed_aur_helper) # _get_installed_aur_helper 是我们已有的内部函数

    if [ -z "$aur_helper" ]; then
        log_error "未找到 AUR 助手 (yay 或 paru)。无法安装以下 AUR 包: ${pkgs_failed_pacman[*]}"
        log_error "请先运行 '安装 AUR 助手' 模块。"
        return 1
    fi
    
    log_info "步骤 4/4: 使用检测到的 AUR 助手 '$aur_helper' 安装剩余的包..."
    
    # 使用 run_as_user 来安全地执行 AUR 助手的安装命令
    if run_as_user "$aur_helper -S --noconfirm --needed ${pkgs_failed_pacman[*]}"; then
        log_success "已通过 '$aur_helper' 成功安装 (${#pkgs_failed_pacman[@]} 个): ${pkgs_failed_pacman[*]}"
    else
        log_error "使用 '$aur_helper' 安装部分或全部 AUR 软件包失败。"
        log_error "请检查上面的日志以获取 '$aur_helper' 的详细输出。"
        return 1
    fi

    log_success "所有软件包安装流程执行完毕！"
    return 0
}
# 标记此初始化脚本已被加载 (不导出)
__PACKAGE_MANAGEMENT_UTILS_SOURCED__="true"
log_debug "Package management utilities sourced and available (v1.0.3)."