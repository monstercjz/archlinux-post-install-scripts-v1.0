#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_user_environment/05_configure_firewall.sh
# 版本: 1.2.0 (新增端口状态查询功能并汉化)
# 日期: 2025-06-12
# 描述: 提供一个基于 ufw (Uncomplicated Firewall) 的防火墙管理模块。
#       此脚本从一个旧的独立脚本完全重构而来，以完美融入当前框架。
# ------------------------------------------------------------------------------
# 核心功能:
# - 提供一个内部菜单，用于管理 ufw 的安装、启停、规则和状态。
# - 检查并安装 `ufw` 包。
# - 启用/禁用防火墙（并自动处理开机自启）。
# - 添加/删除防火墙规则（允许/拒绝端口）。
# - 查看防火墙状态和详细规则。
# - **新增**: 查询特定端口的状态，并根据默认策略给出最终结论。
# - 提供一个安全的重置防火墙功能，并带有明确警告。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-12 - 初始版本。完全重构。
# v1.1.0 - 2025-06-12 - 将所有面向用户的交互信息和提示修改为中文。
# v1.2.0 - 2025-06-12 - 新增 _check_port_status 函数，用于查询特定端口的状态。
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
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 核心功能函数
# ==============================================================================

# _ensure_ufw_installed()
# @description: 检查并安装 `ufw` 包。
_ensure_ufw_installed() {
    display_header_section "安装 UFW 防火墙"
    if ! is_package_installed "ufw"; then
        log_warn "'ufw' (Uncomplicated Firewall) 尚未安装。"
        if _confirm_action "您想现在安装 'ufw' 吗？" "y" "${COLOR_YELLOW}"; then
            if ! install_pacman_pkg "ufw"; then
                log_error "安装 'ufw' 失败。任务中止。"
                return 1
            fi
        else
            log_warn "用户选择跳过安装。防火墙功能将不可用。"
            return 1
        fi
    fi
    log_success "'ufw' 已安装。"
    return 0
}

# _manage_firewall_state()
# @description: 启用或禁用防火墙。ufw 会自动处理开机自启。
# @param: $1 (string) - "enable" 或 "disable"
_manage_firewall_state() {
    local action="$1"
    local display_action_text="启用"
    if [[ "$action" == "disable" ]]; then
        display_action_text="禁用"
    fi
    
    display_header_section "${display_action_text}防火墙 (ufw)"
    if ! _confirm_action "您确定要${display_action_text}防火墙吗？" "y" "${COLOR_YELLOW}"; then
        log_info "用户已取消操作。"
        return 0
    fi
    
    log_info "正在执行 'ufw ${action}'..."
    # ufw enable/disable 需要 y/n 确认，我们用 echo "y" 通过管道传递
    if echo "y" | ufw "${action}"; then
        log_success "防火墙已成功${display_action_text}。"
        log_notice "请注意: 'ufw ${action}' 命令也会将防火墙设置为开机${display_action_text}。"
    else
        log_error "${display_action_text}防火墙失败。"
        return 1
    fi
    return 0
}

# _manage_port_rule()
# @description: 开放或关闭一个端口。
# @param: $1 (string) - "allow" 或 "deny"
_manage_port_rule() {
    local action="$1"
    local display_action_text="开放"
    local action_text="开放"
    if [[ "$action" == "deny" ]]; then
        display_action_text="关闭"
        action_text="关闭/拒绝"
    fi

    display_header_section "${display_action_text}端口"
    read -rp "请输入要${action_text}的端口号: " port
    if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
        log_error "无效的端口号: '$port'。请输入 1 到 65535 之间的数字。"
        return 1
    fi

    read -rp "请指定协议 (tcp, udp, 或留空表示两者都设置): " proto
    local rule="${port}"
    if [[ -n "$proto" ]]; then
        rule="${port}/${proto}"
    fi

    if ! _confirm_action "您确定要${action_text}端口 ${rule} 吗？" "y" "${COLOR_YELLOW}"; then
        log_info "用户已取消操作。"
        return 0
    fi

    log_info "正在执行 'ufw ${action} ${rule}'..."
    if ufw "${action}" "${rule}"; then
        log_success "${action_text}端口 ${rule} 的规则已添加。"
    else
        log_error "为端口 ${rule} 添加规则失败。"
        return 1
    fi
    return 0
}

# _view_firewall_status()
# @description: 查看防火墙的状态和规则。
_view_firewall_status() {
    display_header_section "防火墙状态与规则"
    log_info "正在执行 'ufw status verbose'..."
    echo -e "${COLOR_CYAN}"
    # 直接执行命令，让输出显示在终端
    ufw status verbose
    echo -e "${COLOR_RESET}"
}

# _check_port_status()
# @description: 检查特定端口在 ufw 规则中的状态。
_check_port_status() {
    display_header_section "查询端口状态"
    read -rp "请输入要查询的端口号: " port
    if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
        log_error "无效的端口号: '$port'。请输入 1 到 65535 之间的数字。"
        return 1
    fi

    log_info "正在查询端口 ${port} 的状态..."
    
    # 捕获 ufw status 的输出
    local ufw_status_output
    ufw_status_output=$(ufw status)

    # 构造 grep 的正则表达式以精确匹配端口
    # 匹配行首的端口号，后面可以是 /、空格或行尾
    local search_pattern="^${port}[[:space:]/]|^${port}$"
    
    # 使用 grep 查找相关规则
    local found_rules
    found_rules=$(echo "${ufw_status_output}" | grep -E "${search_pattern}")

    echo -e "${COLOR_CYAN}--------------------------------------------------${COLOR_RESET}"
    if [ -n "$found_rules" ]; then
        log_success "找到了关于端口 ${port} 的显式规则:"
        echo -e "${COLOR_GREEN}${found_rules}${COLOR_RESET}"
        log_info "上面的列表显示了端口 ${port} 的具体规则（ALLOW 表示允许，DENY 表示拒绝）。"
    else
        log_warn "未找到关于端口 ${port} 的显式规则。"
        # 获取默认策略
        local default_incoming_policy
        default_incoming_policy=$(echo "${ufw_status_output}" | grep "Default:" | awk '{print $2}')
        log_info "因此，该端口将遵循默认的入站策略: ${COLOR_BOLD}${default_incoming_policy^^}${COLOR_RESET}."
        if [[ "$default_incoming_policy" == "deny" || "$default_incoming_policy" == "reject" ]]; then
            log_info "这意味着端口 ${port} 当前是 ${COLOR_RED}关闭的${COLOR_RESET}。"
        else
            log_info "这意味着端口 ${port} 当前是 ${COLOR_GREEN}开放的${COLOR_RESET}。"
        fi
    fi
    echo -e "${COLOR_CYAN}--------------------------------------------------${COLOR_RESET}"
    
    return 0
}

# _reset_firewall()
# @description: 重置防火墙到默认状态。
_reset_firewall() {
    display_header_section "重置防火墙规则"
    log_warn "此操作将删除所有现有规则并禁用防火墙！"
    log_warn "如果您正通过 SSH 连接，且默认未放行 SSH 端口，连接将会中断！"
    
    if ! _confirm_action "您完全确定要重置防火墙吗？" "n" "${COLOR_RED}"; then
        log_info "用户已取消防火墙重置操作。"
        return 0
    fi

    log_info "正在执行 'ufw reset'..."
    # ufw reset 也需要 y/n 确认
    if echo "y" | ufw reset; then
        log_success "防火墙已重置为默认状态（禁用，所有规则已删除）。"
    else
        log_error "重置防火墙失败。"
        return 1
    fi
    return 0
}


# ==============================================================================
# 主函数 (菜单驱动)
# ==============================================================================
main() {
    display_header_section "防火墙管理 (UFW)" "box" 80 "${COLOR_BLUE}"

    # 前置条件：必须安装 ufw
    if ! _ensure_ufw_installed; then
        return 1
    fi

    # 主菜单循环
    while true; do
        display_header_section "UFW 防火墙主菜单" "default" 80 "${COLOR_PURPLE}"
        echo -e "  --- 防火墙状态与查询 ---"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 启用防火墙 (并设置为开机自启)"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 禁用防火墙 (并禁止开机自启)"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 查看防火墙完整状态和规则"
        echo -e "  ${COLOR_YELLOW}4.${COLOR_RESET} 查询特定端口的状态"
        echo -e "\n  --- 规则管理 ---"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} 允许 (开放) 一个端口"
        echo -e "  ${COLOR_GREEN}6.${COLOR_RESET} 拒绝 (关闭) 一个端口"
        echo -e "  ${COLOR_RED}7.${COLOR_RESET} 重置防火墙 (删除所有规则并禁用！)"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成并返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        
        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [1-7, 0]: ${COLOR_RESET}")" choice
        echo

        case "$choice" in
            1) _manage_firewall_state "enable" ;;
            2) _manage_firewall_state "disable" ;;
            3) _view_firewall_status ;;
            4) _check_port_status ;;
            5) _manage_port_rule "allow" ;;
            6) _manage_port_rule "deny" ;;
            7) _reset_firewall ;;
            0)
                log_info "防火墙配置结束。"
                break
                ;;
            *)
                log_warn "无效选择: '$choice'。请重新输入。"
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 键返回防火墙主菜单...${COLOR_RESET}")"
        fi
    done
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

exit_script() {
    local exit_code=${1:-$?_}
    if [ "$exit_code" -eq 0 ]; then
        log_info "成功退出防火墙管理脚本。"
    else
        log_warn "防火墙管理脚本因错误退出 (退出码: $exit_code)。"
    fi
    exit "$exit_code"
}
exit_script $?