#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_base_software_installation/01_install_software_Allinone.sh (新文件名示例)
# 版本: 2.1.0 (扩展为通过菜单选择单个 .list 文件进行安装)
# 日期: 2025-06-15
# 描述: 通过菜单选择一个预定义的软件包列表文件，并安装其中的软件包。
# ------------------------------------------------------------------------------
# 变更记录:
# v2.1.0 - 2025-06-15 - 将原 main 函数封装为 _install_package_list, 新 main 函数使用
#                        menu_framework.sh 构建菜单以选择不同的 .list 文件。
# v2.0.0 - 2025-06-12 - (原版本) 从单个固定的 essential.list 文件读取软件包列表。
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
# 内部函数：安装指定列表中的软件包 (基于你之前的 main 函数逻辑)
# ==============================================================================
# _install_package_list()
# @description 安装指定 .list 文件中定义的软件包。
# @param $1 (string) list_file_basename - 要安装的软件包列表文件的基本名称 (例如 "essential", "development")。
#                                         脚本会自动添加 .list 后缀和路径。
# @returns (status) - 0 (成功或用户取消), 1 (失败)。
_install_package_list() {
    local list_file_basename="$1"
    if [ -z "$list_file_basename" ]; then
        log_error "_install_package_list: 未提供软件包列表文件名。"
        return 1
    fi

    display_header_section "安装软件包列表: ${list_file_basename}.list" "sub_box" 70 # 子标题

    # 1. 构建软件包列表文件的完整路径
    # 确保 PKG_LISTS_DIR_RELATIVE_TO_ASSETS 在 main_config.sh 中已定义
    if [ -z "${PKG_LISTS_DIR_RELATIVE_TO_ASSETS:-}" ]; then
        log_fatal "配置错误: PKG_LISTS_DIR_RELATIVE_TO_ASSETS 未在 main_config.sh 中定义！"
        # log_fatal 会退出，所以不需要显式 return 1
    fi
    local list_file="${ASSETS_DIR}/${PKG_LISTS_DIR_RELATIVE_TO_ASSETS}/${list_file_basename}.list"

    log_info "正在从文件读取软件包列表: $list_file"

    # 检查文件是否存在
    if [ ! -f "$list_file" ]; then
        log_error "错误: 软件包列表文件 '$list_file' 不存在！"
        return 1
    fi

    # 2. 调用辅助函数读取并格式化软件包列表
    local pkgs_to_install
    pkgs_to_install=$(_read_pkg_list_from_file "$list_file")

    # 3. 检查列表是否为空
    if [ -z "$pkgs_to_install" ]; then
        log_info "基础软件包列表为空，无需安装。跳过。"
        return 0
    fi

    log_notice "将要安装以下基础软件包:"
    log_summary "${pkgs_to_install}" # 使用 log_summary 格式化输出
    
    if ! _confirm_action "是否继续安装？" "y" "${COLOR_YELLOW}"; then
        log_info "用户已取消安装。"
        return 0
    fi
    
    # 4. 调用安装函数
    if ! install_packages $pkgs_to_install; then
        log_error "安装部分基础软件包失败。请检查日志获取详细信息。"
        # 即使失败，也允许脚本继续，而不是中止整个流程
        return 1 
    fi

    log_success "基础软件安装完成。"
    return 0
}

# ==============================================================================
# 菜单配置 (用于新的 main 函数)
# ==============================================================================
# 声明一个关联数组，用于通用菜单框架。
# 键是菜单选项数字。
# 值是 "菜单描述文本|类型:基础路径键:要传递给_install_package_list的参数"
#   类型: "action_param:" (表示这是一个动作，并且需要传递参数给一个本地函数)
#   基础路径键: 这里我们用一个特殊值 "local_function" 表示调用本脚本内的函数。
#   参数: 就是 .list 文件的基本名称。

# ==============================================================================
# 菜单数据构建 (用于本地菜单循环)
# ==============================================================================
declare -A SOFTWARE_LIST_MENU_ENTRIES_LOCAL # 使用新名称以区分

# @description 动态构建用于本地菜单的软件包列表数据。
#              SOFTWARE_LIST_MENU_ENTRIES_LOCAL 的值将是 "描述|list_file_basename"
_build_local_software_list_menu_data() {
    SOFTWARE_LIST_MENU_ENTRIES_LOCAL=() # 清空
    local package_lists_dir="${ASSETS_DIR}/${PKG_LISTS_DIR_RELATIVE_TO_ASSETS}"
    local menu_index=1

    log_debug "Scanning for .list files in: '$package_lists_dir' for local menu."

    if [ ! -d "$package_lists_dir" ]; then
        log_warn "软件包列表目录 '$package_lists_dir' 未找到。"
        # 可以在这里设置一个错误提示菜单项，或者让函数返回错误
        return 1 # 表示构建失败
    fi

    local list_files_found=()
    mapfile -d $'\0' -t list_files_found < <(find "$package_lists_dir" -maxdepth 1 -type f -name "*.list" -print0 | sort -z) # 添加 sort -z

    if [ ${#list_files_found[@]} -eq 0 ]; then
        log_warn "在 '$package_lists_dir' 中未找到任何 .list 软件包列表文件。"
        return 2 # 表示未找到文件
    fi
    
    for list_file_path in "${list_files_found[@]}"; do
        if [ -z "$list_file_path" ]; then continue; fi 
        local list_filename_full=$(basename "$list_file_path")
        local list_filename_base="${list_filename_full%.list}"
        local menu_description="安装软件包列表: ${list_filename_full}"
        
        # 值格式: "描述|实际要用的参数(list_file_basename)"
        SOFTWARE_LIST_MENU_ENTRIES_LOCAL[$menu_index]="${menu_description}|${list_filename_base}"
        ((menu_index++))
    done
    return 0 # 构建成功
}


# ==============================================================================
# 新的主函数 (使用本地菜单循环，借用 menu_framework.sh 的部分函数)
# ==============================================================================
main() {
    display_header_section "从列表安装软件包 (菜单选择)" "box" 80

    # 动态构建菜单数据
    if ! _build_local_software_list_menu_data; then
        local build_status=$?
        if (( build_status == 1 )); then # 目录未找到
            log_error "软件包列表目录配置错误，无法继续。"
        elif (( build_status == 2 )); then # 未找到 .list 文件
            log_warn "未找到可供安装的软件包列表文件。"
        fi
        _prompt_return_to_continue "按 Enter 返回..."
        return $build_status
    fi

    # 确保 menu_framework.sh 中的辅助函数已加载
    # 我们需要 _display_menu_items 和 _get_validated_menu_choice
    if ! type -t _display_menu_items &>/dev/null || ! type -t _get_validated_menu_choice &>/dev/null; then
        log_debug "部分 menu_framework.sh 函数未加载，正在 source ${LIB_DIR}/menu_framework.sh"
        source "${LIB_DIR}/menu_framework.sh"
    fi
    if ! type -t _display_menu_items &>/dev/null || ! type -t _get_validated_menu_choice &>/dev/null; then
        log_fatal "无法加载 menu_framework.sh 中的必要辅助函数！"
    fi

    local keep_running=true
    while "$keep_running"; do
        clear
        # 使用 menu_framework.sh 的 _display_menu_items 来显示菜单
        # 注意：_display_menu_items 解析的值是 "描述|其他"，它只取 "描述" 部分显示
        _display_menu_items "SOFTWARE_LIST_MENU_ENTRIES_LOCAL" "返回上一级"
        
        # 使用 menu_framework.sh 的 _get_validated_menu_choice 获取用户选择
        # 它会处理数字、特殊命令（q, h等）和退出选项（0）
        if ! _get_validated_menu_choice "SOFTWARE_LIST_MENU_ENTRIES_LOCAL" "返回上一级"; then
            # 输入无效或用户取消了退出/特殊命令的确认，重新显示菜单
            _prompt_return_to_continue # 可能需要这个来暂停看错误信息
            continue
        fi

        # _get_validated_menu_choice 会设置全局变量:
        # _VALIDATED_CHOICE_TYPE: "numeric", "exit", "special_command", "invalid"
        # _VALIDATED_CHOICE_VALUE: 数字选择的值, 或特殊命令的内部标识符 (如 "quit_program")
        # _ORIGINAL_COMMAND_INPUT: 原始用户输入 (用于带参数的特殊命令)

        case "$_VALIDATED_CHOICE_TYPE" in
            "exit") # 用户选择了 "0. 返回上一级" 并确认
                keep_running=false
                ;;
            "numeric")
                # 用户选择了一个有效的数字菜单项
                local chosen_option_value="${SOFTWARE_LIST_MENU_ENTRIES_LOCAL[$_VALIDATED_CHOICE_VALUE]}"
                # 解析我们自己定义的值格式: "描述|list_file_basename"
                local list_to_install_basename
                IFS='|' read -r _ list_to_install_basename <<< "$chosen_option_value" # _ 忽略描述部分

                if [ -n "$list_to_install_basename" ]; then
                    # 调用我们自己的安装函数
                    if ! _install_package_list "$list_to_install_basename"; then
                        log_error "安装列表 '$list_to_install_basename.list' 失败。"
                        # 这里可以选择是否中止，或者让用户继续选择其他列表
                    fi
                else
                    log_error "内部错误：无法从菜单项 '$_VALIDATED_CHOICE_VALUE' 解析列表文件名。"
                fi
                _prompt_return_to_continue # 安装完一个列表后，暂停并返回菜单
                ;;
            "special_command")
                # 处理 menu_framework.sh 定义的特殊命令 (如 q, h, c, debug on/off)
                # _handle_special_command 来自 menu_framework.sh
                # 它需要: command_id, original_user_input, exit_option_text
                if _handle_special_command "$_VALIDATED_CHOICE_VALUE" "$_ORIGINAL_COMMAND_INPUT" "返回上一级"; then
                    # 如果特殊命令是清屏或帮助，循环会继续
                    # 如果是退出程序 (quit_program)，_handle_special_command 内部会 exit 0
                    : # Do nothing, loop will continue or exit based on command
                else
                    # 特殊命令处理失败或被取消（例如，退出程序的确认被取消）
                    log_debug "特殊命令 '$_ORIGINAL_COMMAND_INPUT' 未完全执行或已取消。"
                fi
                # 如果是清屏，我们可能不想暂停
                if [[ "$_VALIDATED_CHOICE_VALUE" != "clear_screen" ]]; then
                     _prompt_return_to_continue
                fi
                ;;
            "invalid") 
                # 理论上 _get_validated_menu_choice 返回 false 时已经处理了，这里作为保险
                log_warn "收到无效的选择类型。"
                _prompt_return_to_continue
                ;;
        esac
    done

    log_info "已退出软件包列表选择菜单。"
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
        log_info "成功退出软件包列表安装脚本。"
    else
        log_warn "软件包列表安装脚本因错误或用户取消而退出 (退出码: $exit_code)。"
    fi
    exit "$exit_code"
}
exit_script $?