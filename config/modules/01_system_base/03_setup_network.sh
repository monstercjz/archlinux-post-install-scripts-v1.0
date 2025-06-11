#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/02_setup_network.sh
# 版本: 1.0.1 (修复菜单排序和数组索引错误)
# 日期: 2025-06-11
# 描述: 提供使用 NetworkManager (nmcli) 进行网络配置的交互式菜单。
# ------------------------------------------------------------------------------
# 核心功能:
# - 展示当前网络接口的详细信息。
# - 设置静态 IP 地址、子网掩码、网关和 DNS。
# - 单独修改 DNS 服务器。
# - 单独修改网关。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示、错误处理等基础函数)
#   - menu_framework.sh (直接依赖，用于驱动本脚本的菜单)
#   - main_config.sh (直接依赖，提供 NETWORK_MANAGER_TYPE 等配置)
#   - 系统命令: nmcli (NetworkManager 命令行工具)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。从旧的独立 network.sh 脚本迁移并完全重构，
#                       以适配 archlinux-post-install-scripts 项目的框架、日志系统和编码规范。
# v1.0.1 - 2025-06-11 - **修复由于关联数组无序导致的菜单显示混乱问题。**
#                       **修复由于用户输入无效导致的“数组下标不正确”错误。**
#                       **增强了主菜单循环的输入验证和处理逻辑。**
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
# 辅助函数
# ==============================================================================

# _get_interfaces()
# @description: 获取所有以太网和 Wi-Fi 网络接口的设备名称。
# @param: 无
# @returns: array - 包含所有接口名称的数组。
_get_interfaces() {
    nmcli -t -f DEVICE,TYPE device | grep 'ethernet\|wifi' | awk -F: '{print $1}'
}

# _get_connection_name()
# @description: 根据接口设备名称获取其对应的 NetworkManager 连接名称。
# @param: $1 (string) interface - 网络接口设备名称 (e.g., "enp3s0").
# @returns: string - 对应的连接名称 (e.g., "Wired connection 1")。
_get_connection_name() {
    local interface="$1"
    nmcli -t -f NAME,DEVICE connection show | grep "^.*:$interface$" | awk -F: '{print $1}'
}

# ==============================================================================
# 功能函数 (对应菜单中的每个选项)
# ==============================================================================

# _show_current_ip()
# @description: 显示所有网络接口的详细信息。
_show_current_ip() {
    display_header_section "Current IP Information" "box" 80
    # nmcli device show 提供非常详细的信息
    if ! nmcli device show; then
        log_error "Failed to execute 'nmcli device show'. Is NetworkManager running?"
        return 1
    fi
    log_info "Displayed current IP information using 'nmcli device show'."
    read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to return to the menu...${COLOR_RESET}")"
}

# _set_static_ip()
# @description: 引导用户为选定的网络接口设置静态 IP 地址。
_set_static_ip() {
    display_header_section "Set Static IP Address" "box" 80
    
    local interfaces=($(_get_interfaces))
    if [ ${#interfaces[@]} -eq 0 ]; then
        log_error "No available network interfaces (ethernet or wifi) found."
        return 1
    fi

    echo "Please select a network interface to configure:"
    for i in "${!interfaces[@]}"; do
        echo -e "  ${COLOR_GREEN}$((i+1))${COLOR_RESET}. ${interfaces[$i]}"
    done
    read -rp "$(echo -e "${COLOR_YELLOW}Enter the number for your choice: ${COLOR_RESET}")" choice

    if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt ${#interfaces[@]} ]; then
        log_error "Invalid selection: '$choice'. Please enter a number from 1 to ${#interfaces[@]}."
        return 1
    fi
    local interface=${interfaces[$((choice-1))]}
    log_info "User selected interface: '$interface'."

    local connection_name=$(_get_connection_name "$interface")
    if [ -z "$connection_name" ]; then
        log_error "Could not find an active connection name for interface '$interface'."
        return 1
    fi
    log_info "Found connection name: '$connection_name' for interface '$interface'."

    read -rp "Enter IP address (e.g., 192.168.1.100): " ip_address
    read -rp "Enter subnet prefix (e.g., 24 for 255.255.255.0): " prefix_length
    read -rp "Enter gateway (e.g., 192.168.1.1): " gateway
    read -rp "Enter DNS servers (comma-separated, e.g., 8.8.8.8,1.1.1.1): " dns

    log_summary "--------------------------------------------------"
    log_summary "Configuration to be applied to '$connection_name':"
    log_summary "  IP Address: $ip_address/$prefix_length"
    log_summary "  Gateway:    $gateway"
    log_summary "  DNS:        $dns"
    log_summary "--------------------------------------------------"

    if _confirm_action "Confirm: Apply these static IP settings?" "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying static IP configuration..."
        # 先修改配置，再重启连接，这样更安全
        if ! nmcli connection modify "$connection_name" ipv4.method manual ipv4.addresses "$ip_address/$prefix_length" ipv4.gateway "$gateway" ipv4.dns "$dns"; then
            log_error "Failed to modify connection '$connection_name'."
            log_error "Please check your input and NetworkManager status."
            return 1
        fi
        log_success "Connection '$connection_name' modified successfully."
        
        log_info "Re-activating connection '$connection_name' to apply changes..."
        # 尝试重启连接
        if ! (nmcli connection down "$connection_name" && nmcli connection up "$connection_name"); then
            log_warn "Failed to automatically re-activate connection '$connection_name'. You may need to do it manually."
            log_warn "Try running: 'nmcli connection up \"$connection_name\"'"
        fi
        log_success "Static IP configuration applied. Please verify your connection."
    else
        log_warn "User cancelled static IP configuration."
    fi
}

# _modify_dns()
# @description: 引导用户修改选定网络接口的 DNS 服务器。
_modify_dns() {
    display_header_section "Modify DNS Servers" "box" 80
    
    local interfaces=($(_get_interfaces))
    if [ ${#interfaces[@]} -eq 0 ]; then
        log_error "No available network interfaces (ethernet or wifi) found."
        return 1
    fi

    echo "Please select a network interface to modify DNS for:"
    for i in "${!interfaces[@]}"; do
        echo -e "  ${COLOR_GREEN}$((i+1))${COLOR_RESET}. ${interfaces[$i]}"
    done
    read -rp "$(echo -e "${COLOR_YELLOW}Enter the number for your choice: ${COLOR_RESET}")" choice

    if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt ${#interfaces[@]} ]; then
        log_error "Invalid selection: '$choice'. Please enter a number from 1 to ${#interfaces[@]}."
        return 1
    fi
    local interface=${interfaces[$((choice-1))]}
    log_info "User selected interface: '$interface'."

    local connection_name=$(_get_connection_name "$interface")
    if [ -z "$connection_name" ]; then
        log_error "Could not find an active connection name for interface '$interface'."
        return 1
    fi
    log_info "Found connection name: '$connection_name' for interface '$interface'."

    read -rp "Enter new DNS servers (comma-separated, e.g., 223.5.5.5,114.114.114.114): " dns
    
    if _confirm_action "Confirm: Set DNS for '$connection_name' to '$dns'?" "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying new DNS settings..."
        if ! nmcli connection modify "$connection_name" ipv4.dns "$dns"; then
            log_error "Failed to modify DNS for connection '$connection_name'."
            return 1
        fi
        log_success "DNS servers for '$connection_name' modified successfully."
        
        log_info "Re-activating connection to apply DNS changes..."
        if ! (nmcli connection up "$connection_name"); then
             log_warn "Failed to re-apply connection settings. A network restart might be needed."
        fi
    else
        log_warn "User cancelled DNS modification."
    fi
}

# ==============================================================================
# 菜单定义
# ==============================================================================

declare -A NETWORK_MENU_ACTIONS=(
    [1]="_show_current_ip"
    [2]="_set_static_ip"
    [3]="_modify_dns"
)

declare -A NETWORK_MENU_DESCRIPTIONS=(
    [1]="Show Current IP Information"
    [2]="Set Static IP Address"
    [3]="Modify DNS Servers"
)

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    # 检查 NetworkManager 是否正在运行
    if ! pgrep NetworkManager &>/dev/null; then
        handle_error "NetworkManager service is not running. This script requires NetworkManager. Please start it with 'sudo systemctl start NetworkManager'."
    fi

    # 循环显示菜单，直到用户选择退出
    while true; do
        display_header_section "Network Configuration (nmcli)" "box" 80 "${COLOR_CYAN}" "${COLOR_YELLOW}"
        
        # 修正：对关联数组的键进行排序以确保菜单顺序稳定
        local sorted_keys=$(echo "${!NETWORK_MENU_ACTIONS[@]}" | tr ' ' '\n' | sort -n)
        
        # 显示菜单选项
        for i in $sorted_keys; do
            echo -e "  ${COLOR_GREEN}$i.${COLOR_RESET} ${NETWORK_MENU_DESCRIPTIONS[$i]}"
        done
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Return to Previous Menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------${COLOR_RESET}"
        
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice: ${COLOR_RESET}")" choice
        echo

        # 增强输入验证
        if [[ "$choice" == "0" ]]; then
            log_info "User chose to exit Network Configuration. Returning to previous menu."
            break
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ -n "${NETWORK_MENU_ACTIONS[$choice]:-}" ]]; then
            # 只有当 choice 是一个有效的数字并且在我们的菜单键中存在时，才执行
            local action_func="${NETWORK_MENU_ACTIONS[$choice]}"
            log_info "Executing action: $action_func"
            # 调用对应的功能函数
            "$action_func" || log_error "Action '$action_func' returned with an error."
        else
            log_warn "Invalid choice: '$choice'. Please try again."
        fi
    done
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

main "$@"

exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Network Configuration script with exit code $exit_code."
    exit "$exit_code"
}

exit_script 0