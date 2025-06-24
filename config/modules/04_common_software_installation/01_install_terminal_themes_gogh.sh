#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_user_environment/05_install_terminal_themes_gogh.sh
# 版本: 1.1.0 (简化版)
# 日期: 2025-06-15
# 描述: 使用 Gogh 官方一键交互式脚本安装终端颜色主题。
# ------------------------------------------------------------------------------
# 功能:
# - 检查并安装 Arch Linux 的依赖项 (dconf, util-linux-libs, wget)。
# - 显示 "pipe-to-sh" 的安全警告并获取用户确认。
# - 以普通用户身份执行 Gogh 的官方一键安装脚本。
# ==============================================================================

# --- 脚本顶部引导块 START ---
set -euo pipefail
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
if [ -z "${BASE_DIR+set}" ]; then
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""
    while [[ "$_project_root_candidate" != "/" ]]; do
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate")
    done
    if [[ -z "$_found_base_dir" ]]; then
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory." >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 主逻辑
# ==============================================================================
main() {
    display_header_section "安装终端颜色主题 (Gogh - 交互式)" "box" 80

    # --- 1. 检查依赖 ---
    log_info "步骤 1/3: 检查 Gogh 依赖项 (dconf, util-linux-libs, wget)..."
    # util-linux-libs 通常已存在，主要检查 dconf 和 wget
    local pkgs_to_check=("dconf" "wget")
    local missing_pkgs=()

    for pkg in "${pkgs_to_check[@]}"; do
        if ! is_package_installed "$pkg"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        log_warn "缺少以下依赖包: ${missing_pkgs[*]}"
        if _confirm_action "是否现在安装这些依赖包?" "y"; then
            if ! install_packages "${missing_pkgs[@]}"; then
                log_error "依赖包安装失败。无法继续。"
                return 1
            fi
        else
            log_error "用户拒绝安装依赖。无法继续。"
            return 1
        fi
    fi
    log_success "所有 Gogh 依赖项均已满足。"

    # --- 2. 安全警告和确认 ---
    log_info "步骤 2/3: 安全确认"
    echo
    log_warn "您即将通过网络执行 Gogh 的官方一键安装脚本。" "all_color" "full" "${COLOR_RED}"
    log_warn "命令: bash -c \"\$(wget -qO- https://git.io/vQgMr)\"" "all_color" "full" "${COLOR_RED}"
    log_warn "这是一个“pipe-to-sh”方法，将不经审查直接运行网络代码。" "all_color" "full" "${COLOR_RED}"
    log_warn "请确认您信任此脚本的来源 (Gogh-Co on GitHub)。" "all_color" "full" "${COLOR_RED}"
    echo

    if ! _confirm_action "您是否理解风险并希望继续运行 Gogh 安装程序?" "n" "${COLOR_RED}"; then
        log_info "操作已取消。未进行任何更改。"
        return 0
    fi

    # --- 3. 以普通用户身份执行安装 ---
    log_info "步骤 3/3: 以用户 '$ORIGINAL_USER' 的身份执行 Gogh 安装脚本..."
    log_notice "Gogh 的脚本是交互式的，它会要求您选择终端和主题。"
    log_notice "请按照其命令行提示进行操作。"
    
    # 构造要执行的命令
    local install_cmd='bash -c "$(wget -qO- https://git.io/vQgMr)"'

    # 使用 run_as_user 函数，确保在正确的用户上下文中执行
    if run_as_user "$install_cmd"; then
        log_success "Gogh 交互式安装程序执行完毕。"
        log_notice "如果已应用主题，请重启终端或在设置中切换 Profile 以查看效果。"
    else
        log_error "Gogh 交互式安装程序执行失败或被中途取消。"
        log_error "请检查上面的输出以获取详细信息。"
        return 1
    fi

    return 0
}

# --- 脚本入口 ---
main "$@"
exit $?