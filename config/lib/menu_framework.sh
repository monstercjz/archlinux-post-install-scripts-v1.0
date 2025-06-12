#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/lib/menu_framework.sh
# 版本: 1.0.13 (增强：错误日志指向实际失败的子脚本日志)
# 日期: 2025-06-09
# 描述: 通用菜单框架脚本。
#       提供一个可重用的函数，用于显示和处理 Bash 脚本中的多级菜单。
#       此脚本不包含任何具体的业务逻辑，仅提供菜单导航的机制。
# ------------------------------------------------------------------------------
# 职责:
#   1. 根据传入的关联数组数据动态生成和显示菜单。
#   2. 接收用户输入，并进行健壮的捕获、验证和分析。
#   3. 根据菜单项的约定 (例如 "menu:" 或 "action:" 前缀以及基础路径键)
#      导航到子菜单或执行功能脚本。
#   4. 确保所有菜单操作的日志记录和错误处理遵循项目标准。
#   5. 当子脚本失败时，尝试定位并提示用户检查该子脚本的特定日志文件。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh (间接依赖，用于确保 BASE_DIR, MODULES_DIR,
#     ANOTHER_MODULES_DIR, BASE_PATH_MAP, CURRENT_DAY_LOG_DIR 等已导出/填充)
#   - utils.sh (直接依赖，提供日志、颜色、头部显示等基础函数，包括 _confirm_action )
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
# v1.0.0  - 2025-06-08 - 初始版本。
# v1.0.1  - 2025-06-08 - 适配新的多模块路径配置模式 (BASE_PATH_MAP)。
#                        更新菜单数据格式约定。增强对 BASE_PATH_MAP 及其键值的校验。
# v1.0.2  - 2025-06-08 - 优化：移除不属于本脚本的硬编码调试输出。
#                        优化：在菜单退出选项时添加用户确认，提升用户体验。
# v1.0.3  - 2025-06-08 - 修复：处理当用户输入无效菜单选项时，`set -u` 导致的“未绑定变量”错误。
#                        使用 `${parameter:-word}` 扩展确保变量在被引用时不会未设置。
# v1.0.4  - 2025-06-08 - 修复：当用户输入非数字字符时，`set -u` 导致的“未绑定变量”错误。
#                        将退出选项的判断从数字比较 (`-eq`) 改为字符串精确比较 (`==`)。
# v1.0.5  - 2025-06-08 - 增强：对用户输入进行全面的捕获和分析（验证），包括空、非数字和超出范围的输入，并提供清晰的提示。
#                        重构：将菜单显示、输入验证、动作处理拆分为独立函数，提升代码模块化和可扩展性。
#                        新增：支持在菜单中直接输入特殊命令（如 'q', 'h', 'debug'）以实现额外功能。
# v1.0.6  - 2025-06-08 - 增强：当子脚本执行失败时，在终端显示醒目错误提示，并暂停等待用户确认，提升用户感知。
# v1.0.7  - 2025-06-08 - 增强：添加 'c' 或 'clear' 作为特殊命令，用于清屏，提升用户体验。
# v1.0.8  - 2025-06-08 - 终极优化：特殊命令集中定义和处理。
#                        新增 _SPECIAL_COMMANDS_MAP 关联数组集中定义特殊命令及其内部标识符/确认需求。
#                        新增 _handle_special_command 函数，统一处理特殊命令的具体逻辑。
#                        _get_validated_menu_choice 仅识别特殊命令，并返回其标识符。
#                        简化 _run_generic_menu 中对特殊命令的处理逻辑。
# v1.0.9  - 2025-06-08 - 修复：统一特殊命令（如 'q'/'exit'）的确认逻辑，使其在 `_get_validated_menu_choice` 阶段完成，与数字选项的退出确认行为保持一致。
#                        移除 `_handle_special_command` 中重复的确认提示。
# v1.0.10 - 2025-06-08 - 修复：在 `_get_validated_menu_choice` 中，将特殊命令的“内部标识符”正确赋值给 `_VALIDATED_CHOICE_VALUE`。
#                         在 `_run_generic_menu` 调用 `_handle_special_command` 时，将“原始用户输入”作为第二个参数传入。
#                         这将确保 `_handle_special_command` 能够正确匹配并执行其内部逻辑。
# v1.0.11 - 2025-06-08 - 核心优化：将所有确认提示逻辑提炼成一个通用的 `_confirm_action` 函数，提高代码复用性。
#                        此函数已移至 `config/lib/utils.sh`。
# v1.0.12 - 2025-06-08 - **增强：在菜单显示时，使菜单项的文本颜色交错显示，提高视觉效果。**
#                        **精简：将菜单退出选项和底部分隔线移入 `_display_menu_items` 函数，使其负责完整菜单主体的显示。**
#                        **简化 `_run_generic_menu` 中的菜单显示部分。**
# v1.0.13 - 2025-06-09 - 增强: 当子脚本执行失败时，错误提示将尝试指向实际失败子脚本的最新日志文件，
#                        而不是当前菜单脚本的日志。新增 _LAST_FAILED_SCRIPT_LOG_FILE 全局变量。
#                        新增对 LOG_DIR 环境变量的依赖检查。
# ==============================================================================

# 严格模式由调用脚本的顶部引导块设置。

# 防止此框架脚本在同一个 shell 进程中被重复 source
__MENU_FRAMEWORK_SOURCED__="${__MENU_FRAMEWORK_SOURCED__:-}"
if [ -n "$__MENU_FRAMEWORK_SOURCED__" ]; then
    return 0
fi

# ==============================================================================
# 全局变量 (用于在 _get_validated_menu_choice 和 _run_generic_menu 之间传递结果)
# 注意：这些变量在此处声明，但由 _get_validated_menu_choice 函数赋值。
# ==============================================================================
# _VALIDATED_CHOICE_TYPE: 验证后的输入类型 ("numeric", "exit", "special_command", "invalid")
_VALIDATED_CHOICE_TYPE=""
# _VALIDATED_CHOICE_VALUE: 验证后的具体输入值 (内部标识符字符串，如 "quit_program")
_VALIDATED_CHOICE_VALUE=""
# _ORIGINAL_COMMAND_INPUT: 原始用户输入字符串 (例如 "debug on"，用于 _handle_special_command 解析参数)
_ORIGINAL_COMMAND_INPUT=""
# _LAST_FAILED_SCRIPT_LOG_FILE: 存储最近一次失败的子脚本的推断日志文件路径
_LAST_FAILED_SCRIPT_LOG_FILE=""


# ==============================================================================
# 特殊命令定义 (集中化管理)
# 格式: [用户输入字符串]="内部标识符|是否需要确认 (true/false)"
# ==============================================================================
declare -A _SPECIAL_COMMANDS_MAP=(
    ["q"]="quit_program|true" # 需要确认
    ["exit"]="quit_program|true" # 'exit' 作为 'q' 的别名
    ["h"]="show_help|false" # 不需要确认
    ["help"]="show_help|false" # 'help' 作为 'h' 的别名
    ["c"]="clear_screen|false" # 不需要确认
    ["clear"]="clear_screen|false" # 'clear' 作为 'c' 的别名
    ["debug on"]="toggle_debug|false" # 带参数的命令，不需要确认
    ["debug off"]="toggle_debug|false"
)

# ==============================================================================
# 菜单显示辅助函数
# ==============================================================================

# _display_menu_items()
# 功能: 遍历菜单数据并显示格式化的菜单项，包括退出选项和底部分隔线。
# 参数: $1 (menu_data_array_name) - 包含菜单项的关联数组的名称。
#       $2 (exit_option_text) - 退出/返回选项的文本。
# 返回: 无。直接输出到终端。
_display_menu_items() {
    local -n menu_data="$1" # 使用 nameref 引用传入的关联数组
    local exit_option_text="$2"

    local counter=0 # 用于交错颜色显示
    local current_text_color=""

    for choice_num in $(echo "${!menu_data[@]}" | tr ' ' '\n' | sort -n); do
        counter=$((counter + 1))

        # 根据奇偶行切换颜色
        if (( counter % 2 == 1 )); then # 奇数行
            current_text_color="${COLOR_BRIGHT_CYAN}"
        else # 偶数行
            current_text_color="${COLOR_CYAN}"
        fi

        local item_string="${menu_data[$choice_num]}"
        local menu_description _ # 声明局部变量，_ 用于忽略路径部分
        IFS='|' read -r menu_description _ <<< "$item_string"
        # 数字部分仍为绿色，文本部分使用交错颜色
        echo -e "  ${COLOR_GREEN}${choice_num}.${COLOR_RESET} ${current_text_color}${menu_description}${COLOR_RESET}"
        echo "" # 在每个菜单项后添加一个空白行
    done

    echo -e "  ${COLOR_RED}0.${COLOR_RESET} ${exit_option_text}"
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------${COLOR_RESET}"
}

# ==============================================================================
# 特殊命令处理函数
# ==============================================================================

# _handle_special_command()
# 功能: 根据内部标识符处理特殊命令。
# 参数: $1 (command_id) - 内部命令标识符 (例如 "quit_program", "show_help")
#       $2 (original_user_input) - 原始用户输入 (例如 "debug on")，用于带参数的命令解析
#       $3 (exit_option_text) - 退出选项文本，用于帮助信息
# 返回: 0 (成功处理), 1 (处理失败或取消)
_handle_special_command() {
    local command_id="$1"
    local original_user_input="$2"
    local exit_option_text="$3" # 用于帮助信息

    # 在这里，我们假定所有确认已经在 _get_validated_menu_choice 中完成，
    # _handle_special_command 只需要执行命令。
    case "$command_id" in
        "quit_program")
            log_info "用户请求退出整个程序。"
            exit 0 # 直接退出整个父脚本和所有子进程
            ;;
        "show_help")
            display_header_section "帮助与特殊命令" "default" 60 "${COLOR_BLUE}" "${COLOR_BOLD}${COLOR_CYAN}"
            log_summary "可用的特殊命令:"
            log_summary "  0       : ${exit_option_text}"
            log_summary "  q / exit: 立即退出整个程序。"
            log_summary "  h / help: 显示此帮助信息。"
            log_summary "  c / clear: 清除终端屏幕。"
            log_summary "  debug on/off: 切换调试模式。 (当前: $(if [[ "${DEBUG_MODE}" == "true" ]]; then echo "开启"; else echo "关闭"; fi))"
            log_summary "--------------------------------------------------"
            read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回菜单...${COLOR_RESET}")"
            return 0
            ;;
        "clear_screen")
            clear # 执行清屏
            log_info "屏幕已清除。"
            return 0
            ;;
        "toggle_debug")
            local debug_arg="${original_user_input#debug }" # 提取 "on" 或 "off"
            if [[ "$debug_arg" == "on" ]]; then
                export DEBUG_MODE="true"
                log_info "调试模式已开启。"
            elif [[ "$debug_arg" == "off" ]]; then
                export DEBUG_MODE="false"
                log_info "调试模式已关闭。"
            else
                log_warn "内部错误: 无效的调试命令参数: '$debug_arg' (原始输入 '$original_user_input')."
                return 1
            fi
            return 0
            ;;
        *)
            log_error "内部错误: 未处理的特殊命令 ID: '$command_id'."
            return 1
            ;;
    esac
}

# ==============================================================================
# 用户输入捕获与验证函数
# ==============================================================================

# _get_validated_menu_choice()
# 功能: 捕获用户输入，并进行全面的验证。
# 参数: $1 (menu_data_array_name) - 关联数组名称，用于验证数字选项范围。
#       $2 (exit_option_text) - 退出选项的文本，用于确认提示。
# 返回: 0 (输入合法并已处理或等待后续处理), 1 (输入非法，需要重新提示)。
#       通过全局变量 _VALIDATED_CHOICE_TYPE, _VALIDATED_CHOICE_VALUE, _ORIGINAL_COMMAND_INPUT 返回结果。
_get_validated_menu_choice() {
    local -n menu_data="$1" # 使用 nameref 引用传入的关联数组
    local exit_option_text="$2"

    local choice # 用户输入的原始选择
    read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择: ${COLOR_RESET}")" choice
    echo # 添加一个换行符，美化输出

    # 重置全局结果变量
    _VALIDATED_CHOICE_TYPE="invalid"
    _VALIDATED_CHOICE_VALUE=""
    _ORIGINAL_COMMAND_INPUT="" # 重置原始输入变量

    # 1. 处理空输入
    if [[ -z "$choice" ]]; then
        log_warn "输入不能为空。请输入一个菜单选项。"
        return 1 # 非法输入，需要重新提示
    fi

    # 2. 检查退出/返回选项 (字符串精确比较)
    if [[ "$choice" == "0" ]]; then
        if _confirm_action "您确定要 ${exit_option_text} 吗?" "n" "${COLOR_YELLOW}"; then
            _VALIDATED_CHOICE_TYPE="exit"
            log_info "用户选择 '$exit_option_text'."
            return 0 # 合法退出操作
        else
            log_info "'${exit_option_text}' 操作已取消。返回菜单。"
            return 1 # 取消退出，需要重新提示
        fi
    fi

    # 3. 检查并确认特殊命令 (如果需要)
    local special_cmd_id=""
    local confirm_needed="false"
    # 遍历 _SPECIAL_COMMANDS_MAP 的键，进行精确或前缀匹配
    for special_cmd_key in "${!_SPECIAL_COMMANDS_MAP[@]}"; do
        # 针对 "debug on/off" 这样的带参数命令，需要精确匹配用户输入的完整字符串
        if [[ "$special_cmd_key" == "debug "* ]]; then
            if [[ "$choice" == "debug on" || "$choice" == "debug off" ]]; then
                IFS='|' read -r special_cmd_id confirm_needed <<< "${_SPECIAL_COMMANDS_MAP[$special_cmd_key]}"
                break # 匹配到带参数命令
            fi
        # 其他不带参数的命令进行精确匹配
        elif [[ "$choice" == "$special_cmd_key" ]]; then
            IFS='|' read -r special_cmd_id confirm_needed <<< "${_SPECIAL_COMMANDS_MAP[$special_cmd_key]}"
            break # 匹配到精确命令
        fi
    done

    # 如果匹配到特殊命令
    if [[ -n "$special_cmd_id" ]]; then
        if [[ "$confirm_needed" == "true" ]]; then
            if ! _confirm_action "警告: 您确定要执行 '$choice' 吗?" "n" "${COLOR_RED}"; then
                log_info "特殊命令 '$choice' 已取消。"
                return 1 # 取消操作，需要重新提示
            fi
        fi
        # 确认通过或不需要确认，设置结果变量
        _VALIDATED_CHOICE_TYPE="special_command"
        _VALIDATED_CHOICE_VALUE="$special_cmd_id" # 存储内部标识符
        _ORIGINAL_COMMAND_INPUT="$choice" # 存储原始用户输入
        log_debug "特殊命令 '$choice' 已验证为 '$special_cmd_id'."
        return 0 # 合法特殊命令，等待 _run_generic_menu 处理
    fi

    # 4. 验证是否为有效数字 (正整数)
    if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]]; then
        log_warn "无效输入: '$choice'。请输入一个有效的数字 (1-$((${#menu_data[@]}))) 或特殊命令 (例如 'h' 获取帮助)，或输入 0 退出。"
        return 1 # 非法输入，需要重新提示
    fi

    # 5. 检查数字是否在有效菜单选项范围内
    local full_entry_string="${menu_data[$choice]:-}"
    if [[ -z "$full_entry_string" ]]; then
        log_warn "无效菜单选项: '$choice'。该选项不存在。请从可用选项 (1-$((${#menu_data[@]}))) 中选择，或输入 0 退出。"
        return 1 # 非法输入，需要重新提示
    fi

    # 如果通过了所有验证，则返回合法的数字选择
    _VALIDATED_CHOICE_TYPE="numeric"
    _VALIDATED_CHOICE_VALUE="$choice" # 存储数字选项
    _ORIGINAL_COMMAND_INPUT="" # 重置
    return 0 # 合法数字选择，等待后续处理
}

# ==============================================================================
# 菜单操作执行函数
# ==============================================================================

# _process_menu_action()
# 功能: 根据一个已验证的数字选择，解析菜单数据并执行对应的操作。
#       如果执行的脚本失败，尝试找到其最新日志文件并设置 _LAST_FAILED_SCRIPT_LOG_FILE。
# 参数: $1 (menu_data_array_name) - 关联数组名称。
#       $2 (choice) - 已验证的数字选择。
# 返回: 0 (成功执行), 1 (执行失败或脚本未找到)。
_process_menu_action() {
    local -n menu_data="$1" # 使用 nameref 引用传入的关联数组
    local choice="$2"

    _LAST_FAILED_SCRIPT_LOG_FILE="" # 在每次操作前重置

    local full_entry_string="${menu_data[$choice]}"
    local menu_description type_and_path
    IFS='|' read -r menu_description type_and_path <<< "$full_entry_string"

    local menu_type base_key relative_path
    IFS=':' read -r menu_type base_key relative_path <<< "$type_and_path"

    local base_dir="${BASE_PATH_MAP[$base_key]}"

    # 这部分检查在 _get_validated_menu_choice 后应该不会再触发，但作为防御性编程保留。
    if [[ -z "$base_dir" ]]; then
        log_error "内部错误: 选项 '$choice' 的基础目录键 '$base_key' 未定义。"
        return 1
    fi

    local script_path="${base_dir}/${relative_path}"
    local script_basename
    script_basename=$(basename "$script_path") # 获取脚本文件名，例如 01_script.sh
    local script_description=""

    case "$menu_type" in
        "menu") script_description="子菜单";;
        "action") script_description="操作";;
        *)
            log_error "内部错误: 选项 '$choice' 的菜单项类型 '$menu_type'无法识别。"
            return 1
            ;;
    esac

    if [ -f "$script_path" ]; then
        log_info "正在从 '$base_key' 执行 $script_description 脚本: '$script_basename'."
        # 在子 shell 中运行
        bash "$script_path"
        local script_exit_status=$?

        if [ "$script_exit_status" -ne 0 ]; then
            log_error "$script_description 脚本 '$script_basename' 以状态 $script_exit_status 退出。"
            # 尝试查找失败脚本的特定日志文件
            if [ -n "${CURRENT_DAY_LOG_DIR:-}" ] && [ -d "${CURRENT_DAY_LOG_DIR}" ]; then
                local failed_script_name_no_ext="${script_basename%.sh}" # 移除 .sh 后缀
                # 在 LOG_DIR 中查找最新的、名称包含脚本基本名称 (不含.sh) 且以 .log 结尾的文件。
                # 按时间排序 (最新在前)，取第一个。
                # -print0 和 xargs -0 用于安全处理包含特殊字符的文件名。
                _LAST_FAILED_SCRIPT_LOG_FILE=$(find "${CURRENT_DAY_LOG_DIR}" -maxdepth 1 -type f -name "*${failed_script_name_no_ext}*.log" -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null | head -n 1)
                if [ -n "${_LAST_FAILED_SCRIPT_LOG_FILE}" ]; then
                    log_info "尝试识别失败脚本的日志: ${_LAST_FAILED_SCRIPT_LOG_FILE}"
                else
                    log_warn "无法在 '${CURRENT_DAY_LOG_DIR}' 中自动识别 '$script_basename' 的特定日志文件。请检查通用日志。"
                fi
            else
                log_warn "CURRENT_DAY_LOG_DIR 未设置或不是一个目录。无法搜索特定脚本日志。"
            fi
            return 1
        else
            log_info "$script_description 脚本 '$script_basename' 已完成或正常退出。"
            return 0
        fi
    else
        log_error "$script_description 脚本未找到: '$script_path'。请检查 '$base_key' 的项目结构和菜单配置。"
        return 1
    fi
}


# ==============================================================================
# 通用菜单主循环函数 (调度器)
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
    local exit_option_text="${3:-退出}" # 默认退出文本
    local border_color="${4:-${COLOR_PURPLE}}"
    local title_color="${5:-${COLOR_BOLD}${COLOR_WHITE}}"

    # ========================== 依赖验证 START ==========================
    # 验证必要的 utils.sh 函数是否已加载
    if ! type -t log_info &>/dev/null || ! type -t display_header_section &>/dev/null; then
        echo -e "${COLOR_RED}致命错误:${COLOR_RESET} [menu_framework] 未找到 utils.sh 函数 (log_info, display_header_section)。请确保 utils.sh 已 source。" >&2
        return 1
    fi
    # 验证 BASE_PATH_MAP 关联数组是否已定义并可用
    if ! declare -p BASE_PATH_MAP &>/dev/null; then
        log_error "致命错误: [menu_framework] BASE_PATH_MAP 关联数组未定义。请确保 environment_setup.sh 定义并填充了它。"
        return 1
    fi
    # 验证 BASE_DIR 是否已由调用脚本顶部引导块导出
    if [ -z "${BASE_DIR+set}" ]; then # 检查 BASE_DIR 是否已设置
        log_error "致命错误: [menu_framework] BASE_DIR 环境变量未设置。请确保它已被导出。"
        return 1
    fi
    # 验证 _confirm_action 是否已加载 (现在来自 utils.sh)
    if ! type -t _confirm_action &>/dev/null; then
        log_error "致命错误: [menu_framework] _confirm_action 函数未找到。请确保 utils.sh (v2.0.4+) 已 source。"
        return 1
    fi
     # 新增：检查 CURRENT_DAY_LOG_DIR
    if [ -z "${CURRENT_DAY_LOG_DIR+set}" ]; then # 检查 CURRENT_DAY_LOG_DIR 是否已设置
        log_warn "[menu_framework] CURRENT_DAY_LOG_DIR 环境变量未设置。对失败脚本的日志文件建议功能可能会受限。"
        # 不将其设为致命错误，但这对于新功能很重要。
    elif [ ! -d "${CURRENT_DAY_LOG_DIR}" ]; then
        log_warn "[menu_framework] CURRENT_DAY_LOG_DIR ('${LOG_DIR}') 已设置但不是一个目录。对失败脚本的日志文件建议功能将无法工作。"
    fi
    # ========================== 依赖验证 END ==========================

    # 引用传入的关联数组（Bash 4.3+ nameref）
    if ! declare -n menu_data="$menu_data_array_name"; then
        log_error "为菜单数据数组 '$menu_data_array_name' 创建 nameref 失败。它是一个有效的全局数组名吗?"
        return 1
    fi
    log_debug "通用菜单已启动，数组: '$menu_data_array_name'，标题: '$menu_title'。"

    local keep_running=true
    while "$keep_running"; do
        display_header_section "$menu_title" "box" 60 "$border_color" "$title_color"
        _display_menu_items "$menu_data_array_name" "$exit_option_text"

        if ! _get_validated_menu_choice "$menu_data_array_name" "$exit_option_text"; then
            continue # 输入无效或取消，重新显示菜单
        fi

        # 根据验证结果处理不同的输入类型
        case "$_VALIDATED_CHOICE_TYPE" in
            "exit")
                keep_running=false # 退出当前菜单循环
                ;;
            "numeric")
                # 处理数字选择，调用动作处理函数
                if ! _process_menu_action "$menu_data_array_name" "$_VALIDATED_CHOICE_VALUE"; then
                    log_error "菜单选项 '$_VALIDATED_CHOICE_VALUE' 执行失败。显示严重错误提示。"

                    local log_to_inspect="${CURRENT_SCRIPT_LOG_FILE}" # 默认日志文件
                    if [ -n "${_LAST_FAILED_SCRIPT_LOG_FILE}" ] && [ -f "${_LAST_FAILED_SCRIPT_LOG_FILE}" ]; then
                        log_to_inspect="${_LAST_FAILED_SCRIPT_LOG_FILE}" # 使用找到的特定子脚本日志
                    else
                        # 如果 _LAST_FAILED_SCRIPT_LOG_FILE 未找到或 CURRENT_DAY_LOG_DIR 有问题,
                        # 这提供一个更通用但仍有用的回退。
                        log_warn "未能精确定位失败脚本的具体日志。将指向当前菜单脚本日志或请检查 CURRENT_DAY_LOG_DIR。"
                    fi

                    echo -e "${COLOR_RED}${COLOR_BOLD}======================================================================${COLOR_RESET}"
                    echo -e "${COLOR_RED}${COLOR_BOLD}   >>>  错误：所选模块/操作执行失败！ <<<                  ${COLOR_RESET}"
                    echo -e "${COLOR_RED}${COLOR_BOLD}======================================================================${COLOR_RESET}"
                    echo -e "${COLOR_RED} 在执行您的选择期间发生了一个严重错误。                            ${COLOR_RESET}"
                    echo -e "${COLOR_RED} 请查看以下详细日志以获取更多信息：                                ${COLOR_RESET}"
                    echo -e "${COLOR_RED}   --> ${log_to_inspect}                                      ${COLOR_RESET}"
                    if [ -z "${_LAST_FAILED_SCRIPT_LOG_FILE}" ] || [ ! -f "${_LAST_FAILED_SCRIPT_LOG_FILE}" ]; then
                        # 如果没有找到特定的子脚本日志，给一个通用提示
                        echo -e "${COLOR_YELLOW} 提示: 请检查通用日志目录: ${CURRENT_DAY_LOG_DIR:-未设置}${COLOR_RESET}"
                    fi
                    echo -e "${COLOR_RED} 您可以按 Ctrl+C 中止整个脚本。                                    ${COLOR_RESET}"
                    echo -e "${COLOR_RED}======================================================================${COLOR_RESET}"
                    _confirm_action "按 Enter 返回菜单并选择其他选项..." "" "${COLOR_YELLOW}"
                fi
                ;;
            "special_command")
                # 调用统一的特殊命令处理函数
                # _handle_special_command 内部会处理具体的逻辑，包括退出程序
                if ! _handle_special_command "$_VALIDATED_CHOICE_VALUE" "$_ORIGINAL_COMMAND_INPUT" "$exit_option_text"; then
                    log_debug "特殊命令 '$_ORIGINAL_COMMAND_INPUT' (ID: $_VALIDATED_CHOICE_VALUE) 未完全执行或已取消。"
                fi
                ;;
            "invalid")
                # 理论上不会执行到这里
                log_error "内部错误: 从验证函数意外接收到 'invalid' 选择类型。"
                ;;
        esac
        log_debug "通用菜单循环迭代完成。"
    done

    log_info "通用菜单循环已结束，标题: '$menu_title'。"
    return 0
}

# 标记此初始化脚本已被加载 (不导出)
__MENU_FRAMEWORK_SOURCED__="true"
log_debug "菜单框架已 source 且可用。"