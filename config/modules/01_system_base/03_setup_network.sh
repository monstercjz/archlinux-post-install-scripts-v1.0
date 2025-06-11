#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/02_setup_network.sh
# 版本: 1.0.6 (彻底修复 `_get_interfaces` 函数逻辑)
# 日期: 2025-06-11
# 描述: 提供使用 NetworkManager (nmcli) 进行网络配置的交互式菜单。
# ------------------------------------------------------------------------------
# 核心功能:
# - **启动时展示网络状态**: 在进入菜单前，清晰地展示所有可用网络接口的当前配置。
# - **设置静态 IP 地址**: 完整设置 IP/子网/网关/DNS，并为子网和 DNS 提供预设选项。
# - **单独修改 DNS**: 只修改 DNS，并提供预设选项。
# - **单独修改网关**: 只修改网关。
# - **切换到 DHCP**: 将连接切换回自动获取模式。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于环境初始化、全局变量和工具函数加载)
#   - utils.sh (直接依赖，提供日志、颜色输出、确认提示、错误处理等基础函数)
#   - main_config.sh (直接依赖，提供 NETWORK_MANAGER_TYPE 等配置)
#   - 系统命令: nmcli (NetworkManager 命令行工具)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本。从旧的独立 network.sh 脚本迁移并完全重构。
# v1.0.1 - 2025-06-11 - 修复由于关联数组无序导致的菜单显示混乱问题。
#                       修复由于用户输入无效导致的“数组下标不正确”错误。
#                       增强了主菜单循环的输入验证和处理逻辑。
# v1.0.2 - 2025-06-11 - 将重复的“选择接口”逻辑提炼成 `_select_interface_and_get_connection` 辅助函数。
#                       为 IP、网关、DNS 等输入增加了基础的格式验证。
#                       新增“切换到 DHCP”和“修改网关”功能。
#                       所有注释和日志更加详尽，符合项目最佳实践。
# v1.0.3 - 2025-06-11 - 新增启动时展示所有网络接口当前配置的功能。
#                       为子网掩码和 DNS 服务器设置增加了预设选项，同时保留自定义输入。
#                       优化了用户交互流程和提示信息。
# v1.0.4 - 2025-06-11 - 恢复了“修改 DNS”和“修改网关”作为独立的菜单选项，确保所有五个核心功能都可用。
# v1.0.5 - 2025-06-11 - 彻底修复 `_get_interfaces` 函数的实现逻辑，确保它能正确输出接口列表，解决“未找到命令”的错误。
# v1.0.6 - 2025-06-11 - **最终修复 `_get_interfaces` 函数，通过在管道命令后添加 `|| true` 来避免 `set -e` 在 `grep` 未找到匹配时中断脚本，彻底解决“未找到命令”问题。**
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
# @returns: string - 包含所有接口名称的、以换行符分隔的字符串。如果失败，则返回空字符串。
_get_interfaces() {
    # 最终修复：在管道命令后添加 `|| true`。
    # 这可以确保即使 `grep` 没有找到任何匹配项（并返回非零状态码），`set -e` 也不会中断脚本。
    # `|| true` 意味着“如果前面的命令失败，则执行 `true`”，而 `true` 命令总是成功（返回0），
    # 所以整个表达式的退出状态总是0，函数能安全地返回空输出。
    nmcli -t -f DEVICE,TYPE device | grep -E 'ethernet|wifi' | cut -d':' -f1 || true
}

# _get_connection_name()
# @description: 根据接口设备名称获取其对应的 NetworkManager 连接名称。
# @param: $1 (string) interface - 网络接口设备名称 (e.g., "enp3s0").
# @returns: string - 对应的连接名称 (e.g., "Wired connection 1")。
_get_connection_name() {
    local interface="$1"
    # 修正：使用 --active 确保只获取当前活动的连接，避免混淆。
    # `|| true` 确保在没有匹配时命令不会因非零退出状态而导致脚本中断。
    nmcli -t -f NAME,DEVICE connection show --active | grep ":$interface$" | cut -d':' -f1 || true
}

# _select_interface_and_get_connection()
# @description: 引导用户选择一个网络接口，并返回其对应的连接名称。
# @param: $1 (string, by-reference) - 用于存储返回的连接名称的变量名。
# @returns: 0 on success, 1 on failure. 通过引用参数返回连接名称。
_select_interface_and_get_connection() {
    local -n connection_ref=$1 # 使用 nameref 引用传入的变量名

    local interfaces
    # 将 `_get_interfaces` 的输出读入数组。
    mapfile -t interfaces < <(_get_interfaces)

    if [ ${#interfaces[@]} -eq 0 ]; then
        log_error "No available network interfaces (ethernet or wifi) found."
        return 1
    fi

    echo "Please select a network interface:"
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

    connection_ref=$(_get_connection_name "$interface")
    if [ -z "$connection_ref" ]; then
        log_error "Could not find an active connection name for interface '$interface'."
        return 1
    fi
    log_info "Found active connection name: '$connection_ref' for interface '$interface'."
    
    return 0
}

# _validate_ip()
# @description: 验证一个字符串是否是有效的 IPv4 地址。
# @param: $1 (string) ip - 要验证的 IP 地址。
# @returns: 0 if valid, 1 if invalid.
_validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# _show_connection_details()
# @description: 显示指定连接的当前配置信息。
# @param: $1 (string) connection_name - 要显示配置的连接名称。
_show_connection_details() {
    local connection_name="$1"
    log_info "Displaying current settings for connection: '$connection_name'."
    if ! nmcli connection show "$connection_name" | grep -E 'ipv4.method|ipv4.addresses|ipv4.gateway|ipv4.dns'; then
        log_warn "Could not retrieve detailed settings for '$connection_name'."
    fi
}

# _select_dns_preset()
# @description: 提示用户选择预设的 DNS 服务器或自定义输入。
# @param: $1 (string, by-reference) - 用于存储返回的 DNS 字符串的变量名。
# @returns: 0 on success.
_select_dns_preset() {
    local -n dns_ref=$1
    
    log_info "Please choose a DNS server preset or provide a custom one:"
    echo -e "  ${COLOR_CYAN}1. Cloudflare (1.1.1.1, 1.0.0.1)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}2. Google (8.8.8.8, 8.8.4.4)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}3. AliDNS (223.5.5.5, 223.6.6.6)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}4. Custom DNS${COLOR_RESET}"
    
    read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-4, default: 1]: ${COLOR_RESET}")" choice
    
    case "$choice" in
        2) dns_ref="8.8.8.8,8.8.4.4" ;;
        3) dns_ref="223.5.5.5,223.6.6.6" ;;
        4) 
            read -rp "Enter custom DNS servers (comma-separated): " custom_dns
            dns_ref="$custom_dns"
            ;;
        1|*)
            dns_ref="1.1.1.1,1.0.0.1"
            ;;
    esac
    log_success "DNS servers set to: '$dns_ref'."
}

# _select_prefix_preset()
# @description: 提示用户选择预设的子网前缀或自定义输入。
# @param: $1 (string, by-reference) - 用于存储返回的子网前缀的变量名。
# @returns: 0 on success.
_select_prefix_preset() {
    local -n prefix_ref=$1

    log_info "Please choose a subnet prefix (CIDR) or provide a custom one:"
    echo -e "  ${COLOR_CYAN}1. 24 (255.255.255.0 - Common for home/small office networks)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}2. 16 (255.255.0.0)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}3. 8 (255.0.0.0)${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}4. Custom prefix${COLOR_RESET}"

    read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice [1-4, default: 1]: ${COLOR_RESET}")" choice

    case "$choice" in
        2) prefix_ref=16 ;;
        3) prefix_ref=8 ;;
        4)
            read -rp "Enter custom subnet prefix (1-32): " custom_prefix
            prefix_ref="$custom_prefix"
            ;;
        1|*)
            prefix_ref=24
            ;;
    esac
    log_success "Subnet prefix set to: '$prefix_ref'."
}

# ==============================================================================
# 功能函数 (对应菜单中的每个选项)
# ==============================================================================

# _show_current_ip()
# @description: 显示所有网络接口的详细信息。
_show_current_ip() {
    display_header_section "Current IP Information" "box" 80
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
    
    local connection_name=""
    if ! _select_interface_and_get_connection connection_name; then return 1; fi
    _show_connection_details "$connection_name"

    read -rp "Enter IP address (e.g., 192.168.1.100): " ip_address
    if ! _validate_ip "$ip_address"; then
        log_error "Invalid IP address format: '$ip_address'."
        return 1
    fi
    
    local prefix_length=""
    _select_prefix_preset prefix_length
    if ! [[ "$prefix_length" =~ ^[0-9]+$ ]] || [ "$prefix_length" -lt 1 ] || [ "$prefix_length" -gt 32 ]; then
        log_error "Invalid subnet prefix: '$prefix_length'. Must be a number between 1 and 32."
        return 1
    fi

    read -rp "Enter gateway (e.g., 192.168.1.1): " gateway
    if ! _validate_ip "$gateway"; then
        log_error "Invalid gateway address format: '$gateway'."
        return 1
    fi
    
    local dns_servers=""
    _select_dns_preset dns_servers

    log_summary "--------------------------------------------------"
    log_summary "Configuration to be applied to '$connection_name':"
    log_summary "  IP Address: $ip_address/$prefix_length"
    log_summary "  Gateway:    $gateway"
    log_summary "  DNS:        $dns_servers"
    log_summary "--------------------------------------------------"

    if _confirm_action "Confirm: Apply these static IP settings?" "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying static IP configuration..."
        if ! nmcli connection modify "$connection_name" ipv4.method manual ipv4.addresses "$ip_address/$prefix_length" ipv4.gateway "$gateway" ipv4.dns "$dns_servers"; then
            log_error "Failed to modify connection '$connection_name'."
            return 1
        fi
        log_success "Connection '$connection_name' modified successfully."
        
        log_info "Re-activating connection '$connection_name' to apply changes..."
        if ! (nmcli connection up "$connection_name" &>/dev/null || nmcli connection up "$connection_name"); then
            log_warn "Failed to automatically re-activate connection '$connection_name'. You may need to do it manually."
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
    
    local connection_name=""
    if ! _select_interface_and_get_connection connection_name; then return 1; fi
    _show_connection_details "$connection_name"

    local dns_servers=""
    _select_dns_preset dns_servers
    
    if _confirm_action "Confirm: Set DNS for '$connection_name' to '$dns_servers'?" "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying new DNS settings..."
        if ! nmcli connection modify "$connection_name" ipv4.dns "$dns_servers"; then
            log_error "Failed to modify DNS for connection '$connection_name'."
            return 1
        fi
        log_success "DNS servers for '$connection_name' modified successfully."
        
        log_info "Re-activating connection to apply DNS changes..."
        if ! (nmcli connection up "$connection_name" &>/dev/null || nmcli connection up "$connection_name"); then
             log_warn "Failed to re-apply connection settings. A network restart might be needed."
        fi
    else
        log_warn "User cancelled DNS modification."
    fi
}

# _modify_gateway()
# @description: 引导用户修改选定网络接口的网关。
_modify_gateway() {
    display_header_section "Modify Gateway" "box" 80
    
    local connection_name=""
    if ! _select_interface_and_get_connection connection_name; then return 1; fi
    _show_connection_details "$connection_name"

    read -rp "Enter new gateway address (e.g., 192.168.1.1): " gateway
    if ! _validate_ip "$gateway"; then
        log_error "Invalid gateway address format: '$gateway'."
        return 1
    fi

    if _confirm_action "Confirm: Set gateway for '$connection_name' to '$gateway'?" "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying new gateway setting..."
        if ! nmcli connection modify "$connection_name" ipv4.gateway "$gateway"; then
            log_error "Failed to modify gateway for connection '$connection_name'."
            return 1
        fi
        log_success "Gateway for '$connection_name' modified successfully."
        
        log_info "Re-activating connection to apply gateway change..."
        if ! (nmcli connection up "$connection_name" &>/dev/null || nmcli connection up "$connection_name"); then
             log_warn "Failed to re-apply connection settings. A network restart might be needed."
        fi
    else
        log_warn "User cancelled gateway modification."
    fi
}

# _set_dhcp()
# @description: 将选定的网络接口切换回 DHCP (自动获取)。
_set_dhcp() {
    display_header_section "Set to DHCP (Auto)" "box" 80
    
    local connection_name=""
    if ! _select_interface_and_get_connection connection_name; then return 1; fi
    _show_connection_details "$connection_name"

    if _confirm_action "Confirm: Set connection '$connection_name' to DHCP (auto-config)? This will clear static IP settings." "y" "${COLOR_RED}"; then
        log_info "User confirmed. Applying DHCP configuration..."
        # 清除手动配置，切换回自动
        if ! nmcli connection modify "$connection_name" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""; then
            log_error "Failed to modify connection '$connection_name' to DHCP."
            return 1
        fi
        log_success "Connection '$connection_name' set to DHCP (auto) successfully."
        
        log_info "Re-activating connection '$connection_name' to apply changes..."
        if ! (nmcli connection up "$connection_name" &>/dev/null || nmcli connection up "$connection_name"); then
            log_warn "Failed to automatically re-activate connection '$connection_name'. You may need to do it manually."
        fi
        log_success "DHCP configuration applied. Please verify your connection."
    else
        log_warn "User cancelled switching to DHCP."
    fi
}

# ==============================================================================
# 菜单定义
# ==============================================================================

declare -A NETWORK_MENU_ACTIONS=(
    [1]="_show_current_ip"
    [2]="_set_static_ip"
    [3]="_modify_dns"
    [4]="_modify_gateway"
    [5]="_set_dhcp"
)

declare -A NETWORK_MENU_DESCRIPTIONS=(
    [1]="Show Current IP Information"
    [2]="Set Static IP Address (IP/Subnet/Gateway/DNS)"
    [3]="Modify DNS Servers Only"
    [4]="Modify Gateway Only"
    [5]="Set to DHCP (Auto-config)"
)

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    if ! pgrep NetworkManager &>/dev/null; then
        handle_error "NetworkManager service is not running. This script requires NetworkManager. Please start it with 'sudo systemctl start NetworkManager'."
    fi

    # 使用本地 `while` 循环来驱动菜单
    while true; do
        display_header_section "Network Configuration (nmcli)" "box" 80 "${COLOR_CYAN}" "${COLOR_YELLOW}"

        # @step 1: 展示所有接口的当前状态
        log_info "Displaying current network status..."
        local interfaces
        mapfile -t interfaces < <(_get_interfaces) # `_get_interfaces` 内部已经有 `|| true`

        if [ ${#interfaces[@]} -eq 0 ]; then
            log_warn "No network interfaces (ethernet or wifi) found. Cannot perform configuration."
        else
            for iface in "${interfaces[@]}"; do
                log_summary "--- Interface: $iface ---"
                # 使用 -g 获取特定字段，更干净
                local conn_name=$(_get_connection_name "$iface")
                if [ -n "$conn_name" ]; then
                    local method=$(nmcli -t -g ipv4.method c s "$conn_name" 2>/dev/null || echo "N/A")
                    local ip=$(nmcli -t -g IP4.ADDRESS c s "$conn_name" 2>/dev/null || echo "N/A")
                    local gw=$(nmcli -t -g IP4.GATEWAY c s "$conn_name" 2>/dev/null || echo "N/A")
                    local dns=$(nmcli -t -g IP4.DNS c s "$conn_name" 2>/dev/null || echo "N/A")

                    log_summary "  Connection: $conn_name"
                    log_summary "  Method:     $method"
                    log_summary "  IP/Subnet:  $ip"
                    log_summary "  Gateway:    $gw"
                    log_summary "  DNS:        $dns"
                else
                    log_summary "  Connection: Not active or not found"
                fi
            done
        fi
        echo "" # 添加一个空行

        # @step 2: 显示菜单选项
        local sorted_keys=$(echo "${!NETWORK_MENU_ACTIONS[@]}" | tr ' ' '\n' | sort -n)
        for i in $sorted_keys; do
            echo -e "  ${COLOR_GREEN}$i.${COLOR_RESET} ${NETWORK_MENU_DESCRIPTIONS[$i]}"
        done
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} Return to Previous Menu"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------${COLOR_RESET}"
        
        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice: ${COLOR_RESET}")" choice
        echo

        if [[ "$choice" == "0" ]]; then
            log_info "User chose to exit Network Configuration. Returning to previous menu."
            break
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ -n "${NETWORK_MENU_ACTIONS[$choice]:-}" ]]; then
            local action_func="${NETWORK_MENU_ACTIONS[$choice]}"
            log_info "Executing action: $action_func"
            # 调用对应的功能函数，如果失败则记录错误
            if ! "$action_func"; then
                log_error "Action '$action_func' returned with an error. Please check the logs."
            fi
            
            # 在执行完一个动作后，暂停一下，让用户看到结果
            if [ "$choice" != "1" ]; then # show_current_ip 内部已经有暂停
                read -rp "$(echo -e "${COLOR_YELLOW}Press Enter to return to the network menu...${COLOR_RESET}")"
            fi
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
    if [ "$exit_code" -eq 0 ]; then
        log_info "Exiting Network Configuration script successfully."
    else
        log_warn "Exiting Network Configuration script with errors (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

exit_script $?