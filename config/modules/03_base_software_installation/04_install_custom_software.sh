#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/02_base_installation/01_install_essential_software_interactive_v2.sh
# 版本: 2.2.0 (手动输入支持直接包名或自定义 .list 文件路径)
# 日期: 2025-06-15
# 描述: 安装基础软件，允许用户选择预制列表、手动输入包名或指定自定义列表文件。
# ------------------------------------------------------------------------------
# 变更记录:
# v2.2.0 - 2025-06-15 - 手动输入时，增加选项让用户可以直接输入包名或提供一个 .list 文件路径。
# v2.1.0 - 2025-06-15 - (原版本) 新增用户交互，允许选择使用预制列表或手动输入包名。
# ==============================================================================

# --- 脚本顶部引导块 START ---
# (保持不变)
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
# 辅助函数 (如果 _prompt_return_to_continue 不在 utils.sh 中)
# ==============================================================================
if ! type -t _prompt_return_to_continue &>/dev/null; then
    _prompt_return_to_continue() {
        local message="${1:-按 Enter 键继续...}"
        read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
    }
fi

# ==============================================================================
# 主函数
# ==============================================================================
main() {
    display_header_section "安装基础软件" "box" 80
    
    if [ -z "${PKG_LISTS_DIR_RELATIVE_TO_ASSETS:-}" ]; then
        log_fatal "配置错误: PKG_LISTS_DIR_RELATIVE_TO_ASSETS 未在 main_config.sh 中定义！"
    fi
    local predefined_list_file_basename="essential"
    local predefined_list_file_path="${ASSETS_DIR}/${PKG_LISTS_DIR_RELATIVE_TO_ASSETS}/${predefined_list_file_basename}.list"
    local pkgs_from_predefined_list=""

    log_info "正在读取预制的基础软件包列表: $predefined_list_file_path"
    if [ -f "$predefined_list_file_path" ]; then
        pkgs_from_predefined_list=$(_read_pkg_list_from_file "$predefined_list_file_path")
        if [ -n "$pkgs_from_predefined_list" ]; then
            log_info "预制列表 '${predefined_list_file_basename}.list' 内容如下:"
            log_summary "${pkgs_from_predefined_list}" "" "${COLOR_BRIGHT_CYAN}"
        else
            log_warn "预制列表文件 '$predefined_list_file_path' 为空或读取失败。"
        fi
    else
        log_warn "预制列表文件 '$predefined_list_file_path' 未找到。"
    fi
    echo # 空行

    local final_pkgs_to_install_str=""
    local user_choice_main_menu

    # --- 主选择菜单 ---
    while true; do # 主选择循环
        log_notice "请选择软件包列表来源:"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 使用上述预制列表 (${COLOR_CYAN}${predefined_list_file_basename}.list${COLOR_RESET})"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 手动提供软件包列表"
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 跳过基础软件安装"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"


        local default_main_choice="1"
        if [ -z "$pkgs_from_predefined_list" ]; then default_main_choice="2"; fi

        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [1, 2, 0] (默认为 ${default_main_choice}): ${COLOR_RESET}")" user_choice_main_menu
        user_choice_main_menu="${user_choice_main_menu:-$default_main_choice}"
        echo

        case "$user_choice_main_menu" in
            1) # 使用预制列表
                if [ -n "$pkgs_from_predefined_list" ]; then
                    final_pkgs_to_install_str="$pkgs_from_predefined_list"
                    log_info "用户选择使用预制列表 '${predefined_list_file_basename}.list'。"
                    break # 跳出主选择循环
                else
                    log_error "预制列表无效或未找到，无法选择此项。"
                    _prompt_return_to_continue "按 Enter 重新选择..."
                    # 循环会继续，让用户重新选主菜单
                fi
                ;;
            2) # 手动提供软件包列表
                log_info "用户选择手动提供软件包列表。"
                local user_choice_manual_input_type
                
                # --- 手动输入类型子菜单 ---
                while true; do # 子菜单循环
                    clear # 清理主菜单的显示
                    display_header_section "手动提供软件包列表" "sub_box" 70
                    log_notice "请选择手动提供的方式:"
                    echo -e "  ${COLOR_GREEN}A.${COLOR_RESET} 直接输入以空格分隔的软件包名称"
                    echo -e "  ${COLOR_GREEN}B.${COLOR_RESET} 输入一个自定义 '.list' 文件的绝对路径"
                    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 返回上一级选择"
                    echo -e "${COLOR_PURPLE}----------------------------------------------------------------------${COLOR_RESET}"
                    read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [A, B, 0]: ${COLOR_RESET}")" user_choice_manual_input_type
                    echo

                    case "${user_choice_manual_input_type^^}" in # 转换为大写进行比较
                        A) # 直接输入包名
                            local manually_entered_pkgs_str
                            while true; do # 输入包名循环
                                read -rp "$(echo -e "${COLOR_YELLOW}请输入软件包名称 (用空格分隔，或留空返回手动类型选择): ${COLOR_RESET}")" manually_entered_pkgs_str
                                manually_entered_pkgs_str=$(echo "$manually_entered_pkgs_str" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                                if [ -n "$manually_entered_pkgs_str" ]; then
                                    final_pkgs_to_install_str="$manually_entered_pkgs_str"
                                    log_info "将使用手动输入的软件包列表。"
                                    break 2 # 跳出两层循环 (输入包名循环 和 手动类型子菜单循环)
                                else
                                    log_warn "未输入任何软件包。是否返回手动类型选择?"
                                    if _confirm_action "确认返回手动类型选择吗 (否则重新输入包名)?" "y"; then
                                        break # 跳出输入包名循环，返回手动类型子菜单
                                    fi
                                    # 否则，循环会继续，让用户重新输入包名
                                fi
                            done
                            ;; # case A 结束
                        B) # 输入 .list 文件路径
                            local custom_list_file_path
                            while true; do # 输入路径循环
                                read -erp "$(echo -e "${COLOR_YELLOW}请输入自定义 '.list' 文件的绝对路径 (或留空返回手动类型选择): ${COLOR_RESET}")" custom_list_file_path
                                # 使用 -e 开启 readline 编辑功能，方便路径输入
                                if [ -z "$custom_list_file_path" ]; then
                                    log_info "用户取消输入文件路径。"
                                    break # 跳出输入路径循环，返回手动类型子菜单
                                fi
                                if [ -f "$custom_list_file_path" ] && [ -r "$custom_list_file_path" ]; then
                                    log_info "正在从自定义文件读取软件包列表: $custom_list_file_path"
                                    final_pkgs_to_install_str=$(_read_pkg_list_from_file "$custom_list_file_path")
                                    if [ -n "$final_pkgs_to_install_str" ]; then
                                        log_info "已从 '$custom_list_file_path' 加载软件包。"
                                        break 2 # 跳出两层循环
                                    else
                                        log_error "自定义列表文件 '$custom_list_file_path' 为空或读取失败。"
                                        # 允许用户重新输入路径或返回
                                        if ! _confirm_action "是否尝试输入其他文件路径?" "y"; then
                                            break; # 返回手动类型子菜单
                                        fi
                                    fi
                                else
                                    log_error "文件路径无效: '$custom_list_file_path' (文件不存在或不可读)。"
                                    if ! _confirm_action "是否尝试输入其他文件路径?" "y"; then
                                         break; # 返回手动类型子菜单
                                    fi
                                fi
                            done
                            ;; # case B 结束
                        0) # 返回主选择菜单
                            log_info "用户取消手动提供方式。"
                            # final_pkgs_to_install_str 保持不变或为空
                            break # 跳出子菜单循环，返回主选择菜单
                            ;;
                        *)
                            log_warn "无效的手动输入类型选择: '$user_choice_manual_input_type'。"
                            _prompt_return_to_continue
                            ;;
                    esac
                    # 如果 final_pkgs_to_install_str 在子菜单中被成功设置，则跳出主选择循环
                    if [ -n "$final_pkgs_to_install_str" ] || [[ "$user_choice_manual_input_type" == "0" ]]; then # 或者用户选择从子菜单返回
                        break # 跳出主选择循环 (如果用户在子菜单中成功提供了列表或选择返回)
                    fi
                done # 子菜单循环结束
                # 如果从子菜单返回 (user_choice_manual_input_type == "0") 但未设置列表，则主循环会继续
                if [[ "$user_choice_manual_input_type" == "0" ]] && [ -z "$final_pkgs_to_install_str" ]; then
                    continue # 继续主选择循环
                fi
                ;; # case 2 (主菜单) 结束
            0) # 跳过基础软件安装
                log_info "用户选择跳过基础软件安装。"
                return 0 # 直接从 main 函数返回
                ;;
            *)
                log_error "无效的主菜单选择: '$user_choice_main_menu'。"
                _prompt_return_to_continue "按 Enter 重新选择..."
                # 循环会继续
                ;;
        esac
        # 如果 final_pkgs_to_install_str 已被设置 (通过预制列表或手动方式)，则跳出主选择循环
        if [ -n "$final_pkgs_to_install_str" ]; then
            break
        fi
    done # 主选择循环结束


    # 3. 检查最终列表是否为空 (可能用户在所有步骤中都取消了)
    if [ -z "$final_pkgs_to_install_str" ]; then
        log_info "最终未确定任何软件包列表，无需安装。跳过。"
        return 0
    fi
    
    local final_pkgs_array
    read -r -a final_pkgs_array <<< "$final_pkgs_to_install_str" # 将字符串转为数组以便计数和显示

    log_notice "将要安装以下基础软件包 (${#final_pkgs_array[@]} 个):"
    for pkg_item_final in "${final_pkgs_array[@]}"; do
        log_summary "  - $pkg_item_final" "" "${COLOR_BRIGHT_CYAN}"
    done
    echo

    if ! _confirm_action "是否继续安装这些软件包？" "y" "${COLOR_YELLOW}"; then
        log_info "用户已取消安装。"
        return 0
    fi
    
    # 4. 调用安装函数
    if ! install_packages $final_pkgs_to_install_str; then # install_packages 接受空格分隔的字符串
        log_error "安装部分或全部基础软件包失败。请检查日志获取详细信息。"
        return 1 
    fi

    log_success "基础软件安装完成。"
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

# exit_script 函数保持不变
exit_script() {
    local exit_code=${1:-$?}
    if [ "$exit_code" -eq 0 ]; then
        log_info "成功退出基础软件安装脚本。"
    else
        log_warn "基础软件安装脚本因错误或用户取消而退出 (退出码: $exit_code)。"
    fi
    exit "$exit_code"
}
exit_script $?