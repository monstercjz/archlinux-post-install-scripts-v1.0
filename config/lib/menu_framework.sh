#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/menu_framework.sh
# 版本: 1.0.2 (优化：移除不必要的调试输出，添加退出确认)
# 日期: 2025-06-08
# 描述: 通用菜单框架脚本。
#       提供一个可重用的函数，用于显示和处理 Bash 脚本中的多级菜单。
#       此脚本不包含任何具体的业务逻辑，仅提供菜单导航的机制。
# ------------------------------------------------------------------------------
# 职责:
#   1. 根据传入的关联数组数据动态生成和显示菜单。
#   2. 接收用户输入，验证选项。
#   3. 根据菜单项的约定 (例如 "menu:" 或 "action:" 前缀以及基础路径键)
#      导航到子菜单或执行功能脚本。
#   4. 确保所有菜单操作的日志记录和错误处理遵循项目标准。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于确保 BASE_DIR, MODULES_DIR,
#     ANOTHER_MODULES_DIR, BASE_PATH_MAP 等已导出/填充)
#   - utils.sh (直接依赖，提供日志、颜色、头部显示等基础函数)
# ------------------------------------------------------------------------------
# 使用方法: (此文件不应被直接执行，而是由其他菜单脚本 source)
#   source "${LIB_DIR}/menu_framework.sh"
#   _run_generic_menu "MY_MENU_ARRAY" "My Custom Menu" "Back" "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_GREEN}"
# ------------------------------------------------------------------------------
# 菜单数据格式约定:
#   关联数组中的键为菜单选项数字。
#   值为 "菜单描述文本|类型:基础路径键:相对路径/到/脚本.sh"
#   类型可以是:
#     - "menu:": 表示这是一个子菜单，目标是另一个菜单脚本 (例如 00_*.sh)
#     - "action:": 表示这是一个动作脚本，执行特定功能
#   基础路径键: BASE_PATH_MAP 中定义的键 (例如 "core_modules", "extra_modules")
#   相对路径: 相对于选定基础路径的脚本路径
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本，实现通用菜单框架的核心功能。
# v1.0.1 - 2025-06-08 - 适配新的多模块路径配置模式 (BASE_PATH_MAP)。
#                        更新菜单数据格式约定。增强对 BASE_PATH_MAP 及其键值的校验。
# v1.0.2 - 2025-06-08 - **优化：移除不属于本脚本的硬编码调试输出。**
#                        **优化：在菜单退出选项时添加用户确认，提升用户体验。**
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 防止此框架脚本在同一个 shell 进程中被重复 source
__MENU_FRAMEWORK_SOURCED__="${__MENU_FRAMEWORK_SOURCED__:-}"
if [ -n "$__MENU_FRAMEWORK_SOURCED__" ]; then
    return 0 
fi

# ==============================================================================
# 核心通用菜单函数
# ==============================================================================

# _run_generic_menu()
# 功能: 通用的菜单显示和处理循环。
#       这个函数应该在 BASE_DIR, MODULES_DIR, LIB_DIR 以及 utils.sh 已经加载后被调用。
# 参数: $1 (menu_data_array_name) - 包含菜单项的关联数组的名称 (例如 "MAIN_MENU_ENTRIES")。
#                                  必须是已声明的全局关联数组名。
#       $2 (menu_title) - 菜单标题，用于 display_header_section。
#       $3 (exit_option_text) - 退出/返回选项的文本 (例如 "Exit Setup", "Return to Main Menu")。
#       $4 (border_color) - 可选，标题边框颜色 (例如 COLOR_CYAN)。
#       $5 (title_color) - 可选，标题文字颜色 (例如 COLOR_BOLD}${COLOR_YELLOW)。
# 返回: 0 (成功退出菜单循环) 或 1 (因错误退出)。
_run_generic_menu() {
    local menu_data_array_name="$1"
    local menu_title="$2"
    local exit_option_text="${3:-Exit}" # 默认为 "Exit"
    local border_color="${4:-${COLOR_CYAN}}"
    local title_color="${5:-${COLOR_BOLD}${COLOR_YELLOW}}"

    # 验证必要的依赖是否已加载：BASE_DIR 已由调用脚本顶部引导块导出
    if ! type -t log_info &>/dev/null || ! type -t display_header_section &>/dev/null; then
        # 此时 log_info 不可用，直接使用 echo
        echo -e "${COLOR_RED}Fatal Error:${COLOR_RESET} [menu_framework] utils.sh functions (log_info, display_header_section) not found. Ensure utils.sh is sourced." >&2
        return 1
    fi
    # 验证 BASE_PATH_MAP 是否已定义并可用
    if ! declare -p BASE_PATH_MAP &>/dev/null; then
        log_error "Fatal Error: [menu_framework] BASE_PATH_MAP associative array is not defined. Cannot resolve module paths. Ensure environment_setup.sh defines and populates it."
        return 1
    fi

    # 引用传入的关联数组（Bash 4.3+ nameref）
    if ! declare -n menu_data="$menu_data_array_name"; then
        log_error "Failed to create nameref for menu data array: '$menu_data_array_name'. Is it a valid global array name?"
        return 1
    fi
    log_debug "Generic menu started for array: '$menu_data_array_name' with title: '$menu_title'."

    local keep_running=true
    while "$keep_running"; do
        display_header_section "$menu_title" "decorated" 80 "$border_color" "$title_color"

        # 遍历菜单数据并显示
        for choice_num in $(echo "${!menu_data[@]}" | tr ' ' '\n' | sort -n); do
            local item_string="${menu_data[$choice_num]}"
            local menu_description _ # 声明局部变量
            IFS='|' read -r menu_description _ <<< "$item_string" # 使用IFS解析字符串，忽略路径部分
            echo -e "  ${COLOR_GREEN}${choice_num}.${COLOR_RESET} ${menu_description}"
        done
        
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} ${exit_option_text}"
        echo -e "${COLOR_CYAN}--------------------------------------------------------------------------------${COLOR_RESET}"

        read -rp "$(echo -e "${COLOR_YELLOW}Enter your choice: ${COLOR_RESET}")" choice
        echo # 添加一个换行符，美化输出

        # 检查退出选项
        if [[ "$choice" -eq 0 ]]; then
            # 添加退出确认提示
            read -rp "$(echo -e "${COLOR_YELLOW}Are you sure you want to ${exit_option_text}? (y/N): ${COLOR_RESET}")" confirm_exit
            if [[ "$confirm_exit" =~ ^[Yy]$ ]]; then
                log_info "User chose to '$exit_option_text'."
                keep_running=false # 退出当前菜单循环
                return 0 
            else
                log_info "'${exit_option_text}' cancelled. Returning to menu."
                continue # 继续菜单循环
            fi
        fi

        local full_entry_string="${menu_data[$choice]}"
        if [[ -n "$full_entry_string" ]]; then
            local menu_description type_and_path # 声明局部变量
            IFS='|' read -r menu_description type_and_path <<< "$full_entry_string" # 分割描述和类型+路径部分

            local menu_type base_key relative_path # 声明局部变量
            IFS=':' read -r menu_type base_key relative_path <<< "$type_and_path"

            local base_dir="${BASE_PATH_MAP[$base_key]}"

            if [[ -z "$base_dir" ]]; then
                log_error "Undefined base directory key '$base_key' found for choice '$choice'. Please check BASE_PATH_MAP configuration in environment_setup.sh."
                continue # 返回菜单，不执行
            fi
            
            local script_path="${base_dir}/${relative_path}"
            local script_description=""

            case "$menu_type" in
                "menu")
                    script_description="sub-menu"
                    ;;
                "action")
                    script_description="action"
                    ;;
                *)
                    log_warn "Unrecognized menu item type '$menu_type' for choice '$choice'. Defaulting to action script."
                    script_description="action (default)"
                    # 确保 target_path 仍然是完整的相对路径，而不是解析失败的部分
                    script_path="${base_dir}/${type_and_path}" # 如果类型解析失败，尝试使用原始 type_and_path 作为相对路径
                    ;;
            esac

            if [ -f "$script_path" ]; then
                log_info "Executing $script_description script from '$base_key': '$(basename "$script_path")'."
                # 在子shell中运行，以隔离变量环境和错误处理
                bash "$script_path"
                local script_exit_status=$?

                if [ "$script_exit_status" -ne 0 ]; then
                    log_error "$script_description script '$(basename "$script_path")' exited with status $script_exit_status. Please review its logs for details."
                else
                    log_info "$script_description script '$(basename "$script_path")' completed or exited gracefully."
                fi
            else
                log_error "$script_description script not found: '$script_path'. Please check project structure and menu configuration for '$base_key'."
            fi
        else
            log_warn "Invalid choice: '$choice'. Please enter a valid menu option."
        fi
        log_debug "Generic menu loop iteration finished."
    done

    log_info "Generic menu loop ended for '$menu_title'."
    return 0
}

# 标记此初始化脚本已被加载 (不导出)
__MENU_FRAMEWORK_SOURCED__="true"
log_debug "Menu framework sourced and available."