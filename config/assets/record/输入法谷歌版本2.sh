#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/04_common_software_installation/02_install_input_method.sh (假设已重命名)
# 版本: 1.0.2 (修复 ORIGINAL_USER_GROUP 未定义问题，增强健壮性)
# 日期: 2025-06-14
# 描述: Arch Linux 输入法安装与配置工具
# ------------------------------------------------------------------------------
# 功能说明:
# - 提供多种输入法框架的安装选项: fcitx5, ibus
# - 支持多种输入方案: 中文拼音、五笔、日文、韩文等
# - 自动配置输入法环境变量
# - 集成到现有菜单系统中
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
# 全局变量和定义
# ==============================================================================
# 输入法框架配置文件路径
IM_CONFIG_FILE="${ORIGINAL_HOME}/.xprofile"
IM_ENV_FILE="${ORIGINAL_HOME}/.pam_environment"

# 检测当前桌面环境
DESKTOP_ENV_RAW="${XDG_CURRENT_DESKTOP:-unknown}"
DESKTOP_ENV=$(echo "$DESKTOP_ENV_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/:.*//')

# 可用的输入法框架和输入方案 (请仔细核对这些键名是否为正确的 Arch Linux 包名)
declare -A INPUT_METHOD_FRAMEWORKS=(
    ["fcitx5"]="Fcitx5 (推荐现代 Linux 系统)"
    ["ibus"]="IBus (经典输入法框架)"
)

declare -A INPUT_SCHEMES=(
    # 拼音输入法 (Fcitx5)
    ["fcitx5-chinese-addons"]="Fcitx5 中文输入方案集合 (含多种拼音、云拼音、自然码等)"
    ["fcitx5-pinyin-zhwiki"]="Fcitx5 中文维基百科词库 (需 fcitx5-pinyin)" # 这是一个词库包，不是引擎
    ["fcitx5-rime"]="Fcitx5 Rime (中州韵，高度可定制)"
    # 拼音输入法 (IBus)
    ["ibus-libpinyin"]="IBus LibPinyin (推荐的 IBus 拼音引擎)"
    ["ibus-rime"]="IBus Rime (中州韵)"

    # 五笔输入法 (Fcitx5) - 包名可能为 fcitx5-table-extra 或特定五笔包
    ["fcitx5-table-wubi"]="Fcitx5 五笔输入法 (基于码表, 请确认包名)"
    # 五笔输入法 (IBus) - 包名可能为 ibus-table 或特定五笔包
    ["ibus-table-wubi"]="IBus 五笔输入法 (基于码表, 请确认包名)"

    # 日文输入法 (Fcitx5)
    ["fcitx5-mozc"]="Fcitx5 Mozc (日文)"
    # 日文输入法 (IBus)
    ["ibus-mozc"]="IBus Mozc (日文)"

    # 韩文输入法 (Fcitx5)
    ["fcitx5-hangul"]="Fcitx5 Hangul (韩文)"
    # 韩文输入法 (IBus)
    ["ibus-hangul"]="IBus Hangul (韩文)"

    # 表情符号 (Fcitx5)
    ["fcitx5-emoji"]="Fcitx5 表情符号支持"

    # 其他语言 (Fcitx5)
    ["fcitx5-unikey"]="Fcitx5 Unikey (越南语)"
)

# 输入法框架依赖的包 (考虑使用包组如 fcitx5-im)
declare -A FRAMEWORK_DEPENDENCIES=(
    ["fcitx5"]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool" # 或 'fcitx5-im' 包组
    ["ibus"]="ibus ibus-gtk ibus-gtk3 ibus-qt"                 # 或 'ibus' 包组
)

# 选中的输入法框架和输入方案
SELECTED_FRAMEWORK=""
SELECTED_SCHEMES=()

# ==============================================================================
# 辅助函数 (如果多处使用，建议移至 utils.sh)
# ==============================================================================

# 对关联数组的键进行排序 (用于固定菜单显示顺序)
get_sorted_keys_for_assoc_array() {
    local -n arr_ref="$1"
    printf '%s\n' "${!arr_ref[@]}" | sort
}

# 简单的提示并等待回车继续的函数
_prompt_return_to_continue() {
    local message="${1:-按 Enter 键继续...}"
    read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
}

# 检查字体是否安装
_is_font_installed() {
    local font_name_pattern="$1"
    if fc-list : family | grep -iqE "$font_name_pattern"; then
        return 0
    else
        return 1
    fi
}

# 检测当前是否安装了特定输入法框架
_is_im_framework_installed() {
    local framework="$1"
    case "$framework" in
        "fcitx5") is_package_installed "fcitx5" ;;
        "ibus") is_package_installed "ibus" ;;
        *) return 1 ;;
    esac
}

# 检测当前是否安装了特定输入方案
_is_input_scheme_installed() {
    local scheme_package_name="$1"
    is_package_installed "$scheme_package_name"
}

# 显示可用的输入法框架列表
_display_framework_options_list() {
    local -n _available_frameworks_ref="$1"
    local -n _frameworks_data_ref="$2"
    _available_frameworks_ref=() # 清空，确保每次调用都重新构建

    local display_count=1
    for framework_key in $(get_sorted_keys_for_assoc_array _frameworks_data_ref); do
        local status=""
        if _is_im_framework_installed "$framework_key"; then
            status="(${COLOR_GREEN}已安装${COLOR_RESET})"
        else
            status="(${COLOR_RED}未安装${COLOR_RESET})"
        fi
        echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${_frameworks_data_ref[$framework_key]} $status"
        _available_frameworks_ref+=("$framework_key")
        ((display_count++))
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消并返回"
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
}

# 显示可用的输入方案列表
_display_scheme_options_list() {
    local -n _available_schemes_ref="$1"
    local -n _schemes_data_ref="$2"
    local _current_framework="$3"
    local -n _current_selected_schemes_ref="$4"
    _available_schemes_ref=() # 清空，确保每次调用都重新构建

    local display_count=1
    for scheme_key in $(get_sorted_keys_for_assoc_array _schemes_data_ref); do
        if [[ "$scheme_key" == "$_current_framework"* ]]; then
            local status=""
            if _is_input_scheme_installed "$scheme_key"; then
                status="(${COLOR_GREEN}已安装${COLOR_RESET})"
            else
                status="(${COLOR_RED}未安装${COLOR_RESET})"
            fi

            local selected_indicator=""
            for s_chk in "${_current_selected_schemes_ref[@]}"; do
                if [[ "$s_chk" == "$scheme_key" ]]; then
                    selected_indicator="${COLOR_YELLOW}[已选]${COLOR_RESET} "
                    break
                fi
            done

            echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${selected_indicator}${_schemes_data_ref[$scheme_key]} $status"
            _available_schemes_ref+=("$scheme_key")
            ((display_count++))
        fi
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成选择并安装"
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
}

# 配置输入法环境变量
_configure_im_environment() {
    local framework="$1"

    log_info "正在为 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 配置输入法环境变量..."

    create_backup_and_cleanup "$IM_CONFIG_FILE" "im_config_xprofile_backup"
    create_backup_and_cleanup "$IM_ENV_FILE" "im_env_pam_backup"

    sed -i -E -e '/^export (GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE)=/d' \
              -e '/^# Fcitx5 输入法配置/d' \
              -e '/^# IBus 输入法配置/d' \
              "$IM_CONFIG_FILE"
    if [ -f "$IM_ENV_FILE" ]; then
        sed -i -E -e '/^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE) DEFAULT=/d' "$IM_ENV_FILE"
    fi

    case "$framework" in
        "fcitx5")
            log_info "配置 Fcitx5 环境变量到 $IM_CONFIG_FILE 和 $IM_ENV_FILE"
            cat >> "$IM_CONFIG_FILE" << EOF

# Fcitx5 输入法配置 (由脚本添加于 $(date))
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
            touch "$IM_ENV_FILE" # 确保文件存在
            cat >> "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
EOF
            log_success "Fcitx5 环境变量已写入配置文件。"
            ;;
        "ibus")
            log_info "配置 IBus 环境变量到 $IM_CONFIG_FILE 和 $IM_ENV_FILE"
            cat >> "$IM_CONFIG_FILE" << EOF

# IBus 输入法配置 (由脚本添加于 $(date))
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF
            touch "$IM_ENV_FILE" # 确保文件存在
            cat >> "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=ibus
QT_IM_MODULE DEFAULT=ibus
XMODIFIERS DEFAULT=@im=ibus
EOF
            log_success "IBus 环境变量已写入配置文件。"
            ;;
        *)
            log_error "未知的输入法框架: $framework。无法配置环境变量。"
            return 1
            ;;
    esac

    # 设置文件权限 (修复 ORIGINAL_USER_GROUP 问题)
    local user_primary_group
    user_primary_group=$(id -gn "$ORIGINAL_USER" 2>/dev/null)

    if [ -z "$user_primary_group" ]; then
        log_warn "无法获取用户 '$ORIGINAL_USER' 的主组名。文件组所有权可能不会被正确设置。"
        if [ -f "$IM_CONFIG_FILE" ]; then
            chown "$ORIGINAL_USER" "$IM_CONFIG_FILE" && chmod 644 "$IM_CONFIG_FILE" || log_warn "设置 $IM_CONFIG_FILE 所有权/权限失败。"
        fi
        if [ -f "$IM_ENV_FILE" ]; then
            chown "$ORIGINAL_USER" "$IM_ENV_FILE" && chmod 644 "$IM_ENV_FILE" || log_warn "设置 $IM_ENV_FILE 所有权/权限失败。"
        fi
    else
        log_debug "用户 '$ORIGINAL_USER' 的主组是 '$user_primary_group'。"
        if [ -f "$IM_CONFIG_FILE" ]; then
            chown "$ORIGINAL_USER:$user_primary_group" "$IM_CONFIG_FILE" && chmod 644 "$IM_CONFIG_FILE" || log_warn "设置 $IM_CONFIG_FILE 所有权/权限失败。"
        fi
        if [ -f "$IM_ENV_FILE" ]; then
            chown "$ORIGINAL_USER:$user_primary_group" "$IM_ENV_FILE" && chmod 644 "$IM_ENV_FILE" || log_warn "设置 $IM_ENV_FILE 所有权/权限失败。"
        fi
    fi

    log_notice "环境变量已配置。更改将在下次登录或重启 X 会话后生效。"
    log_warn "请注意: .pam_environment 的支持因系统和显示管理器的不同而异。"
    log_info "推荐检查您的显示管理器和桌面环境文档，了解设置 IM 环境变量的最佳实践。"
    return 0
}

# 为特定桌面环境配置输入法
_configure_for_desktop_environment() {
    local framework="$1"

    log_info "尝试为桌面环境 '$DESKTOP_ENV' 配置输入法 '$framework'..."

    if is_package_installed "im-config"; then
        log_info "'im-config' 工具已安装。"
        if _confirm_action "是否尝试使用 'im-config -n $framework' 来设置 '$framework' 为活动输入法?" "y"; then
            if run_as_user "im-config -n $framework"; then # im-config 通常需要普通用户权限执行
                log_success "'im-config -n $framework' 执行成功。"
            else
                log_warn "'im-config -n $framework' 执行失败或被取消。"
            fi
        fi
    else
        log_info "'im-config' 工具未安装。"
    fi

    case "$DESKTOP_ENV" in
        "gnome")
            log_info "检测到 GNOME 桌面环境。"
            log_notice "对于 GNOME，请在环境变量生效 (重新登录) 后，"
            log_notice "进入 GNOME 设置 -> 键盘 -> 输入源, 点击 '+' 添加 '${INPUT_METHOD_FRAMEWORKS[$framework]}'。"
            ;;
        "kde"|"plasma")
            log_info "检测到 KDE Plasma 桌面环境。"
            log_notice "对于 KDE Plasma, 请在环境变量生效 (重新登录) 后，"
            log_notice "进入系统设置 -> 区域设置 -> 输入法, 配置 '${INPUT_METHOD_FRAMEWORKS[$framework]}'."
            if [[ "$framework" == "fcitx5" ]] && ! is_package_installed "kcm-fcitx5"; then
                 log_warn "建议安装 'kcm-fcitx5' 以在 KDE 系统设置中获得 Fcitx5 配置模块。"
            fi
            ;;
        "xfce")
            log_info "检测到 XFCE 桌面环境。"
            log_notice "对于 XFCE, 请确保以下步骤已完成或将要完成："
            log_notice "  1. ${COLOR_YELLOW}环境变量已通过本脚本配置${COLOR_RESET} (通常写入 ~/.xprofile)。"
            log_notice "  2. ${COLOR_YELLOW}您已完全注销并重新登录 XFCE 会话${COLOR_RESET}以使环境变量生效。"
            log_notice "  3. Fcitx5 守护进程 (${COLOR_CYAN}fcitx5${COLOR_RESET}) 需要在您登录后自动启动。"
            log_notice "     - 检查 XFCE 的 '会话和启动' -> '应用程序自动启动' 中是否有 Fcitx5。"
            log_notice "     - 如果没有，请手动添加一个条目，命令为: ${COLOR_CYAN}fcitx5${COLOR_RESET}"
            log_notice "     - 或者确保 ${COLOR_CYAN}/etc/xdg/autostart/org.fcitx.Fcitx5.desktop${COLOR_RESET} 文件存在且有效。"
            log_notice "  4. 一旦 Fcitx5 守护进程运行，您就可以使用 ${COLOR_CYAN}fcitx5-configtool${COLOR_RESET} 配置输入方案。"

            # 可选的检查：
            if is_package_installed "fcitx5"; then # 假设 fcitx5 是核心包
                if [ -f "/etc/xdg/autostart/org.fcitx.Fcitx5.desktop" ]; then
                    log_info "检测到 Fcitx5 的 XDG 自动启动文件: /etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
                    log_info "这通常会确保 Fcitx5 在 XFCE 登录时自动启动。"
                else
                    log_warn "未找到 Fcitx5 的标准 XDG 自动启动文件。"
                    log_warn "您可能需要手动在 XFCE 的 '会话和启动' 中添加 'fcitx5' 作为启动命令。"
                fi
            fi
            ;;
        *)
            log_info "当前桌面环境为 '$DESKTOP_ENV'。没有特定的自动化配置步骤。"
            log_notice "请确保环境变量生效，并查阅您的桌面环境文档以配置输入法。"
            ;;
    esac
    return 0
}




# 启动输入法配置工具
# _start_config_tool()
# 功能: 尝试以原始用户身份启动指定输入法框架的配置工具。
# 参数: $1 (framework) - 输入法框架的键名 (例如 "fcitx5", "ibus")。
# 返回: 0 (命令成功发送到后台), 1 (启动失败或必要工具/用户不存在)。
_start_config_tool() {
    local framework="$1"
    log_info "准备启动 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的配置工具..."

    local config_tool_cmd=""
    case "$framework" in
        "fcitx5") config_tool_cmd="fcitx5-configtool" ;;
        "ibus") config_tool_cmd="ibus-setup" ;; # 或 ibus-preferences, ibus-pref-gtk3
        *)
            log_error "未知输入法框架: '$framework'。无法确定配置工具。"
            return 1
            ;;
    esac

    # 检查配置工具命令是否存在
    if ! command -v "$config_tool_cmd" &>/dev/null; then
        log_error "配置工具 '$config_tool_cmd' 未找到或未安装。请确保已正确安装框架及其配置工具包。"
        return 1
    fi

    # 检查 ORIGINAL_USER 是否有效
    if [ -z "$ORIGINAL_USER" ] || ! id "$ORIGINAL_USER" &>/dev/null; then
        log_error "原始用户 '$ORIGINAL_USER' 未定义或无效。无法启动配置工具。"
        return 1
    fi

    log_notice "将尝试以用户 '$ORIGINAL_USER' 身份通过 'su -l' 启动 '$config_tool_cmd'。"
    log_warn "请确保 '$ORIGINAL_USER' 的图形会话 (X11/Wayland) 正在运行。"
    log_info "如果配置窗口未自动弹出，请检查是否有其他错误提示，"
    log_info "并尝试手动从 '$ORIGINAL_USER' 的终端运行命令: $config_tool_cmd"

    # 构建要在 'su -l -c' 中执行的命令字符串
    # nohup 和 & 确保命令在后台运行且不受脚本退出的影响
    # >/dev/null 2>&1 将所有输出重定向，避免干扰脚本的终端输出
    local cmd_to_execute_as_user="nohup $config_tool_cmd >/dev/null 2>&1 &"

    log_debug "将通过 'su -l $ORIGINAL_USER -c \"...\"' 执行的命令: $cmd_to_execute_as_user"

    # 使用 su -l -c 来执行命令。这会为 ORIGINAL_USER 创建一个更完整的登录环境。
    # su 命令本身由 root 执行。
    if su -l "$ORIGINAL_USER" -c "$cmd_to_execute_as_user"; then
        # 'su -l -c "command &"' 通常会立即返回成功状态 (0)，因为 'command &' 进入后台。
        # 它不保证 'command' 本身一定能成功打开图形窗口。
        log_success "'$config_tool_cmd' 的启动命令已通过 'su -l' 成功发送到 '$ORIGINAL_USER' 的后台会话。"
        log_info "请检查您的桌面环境，看 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的配置窗口是否已弹出。"
        log_info "在配置工具中，您通常需要：1. 添加已安装的输入方案。 2. 调整顺序和快捷键。"
        return 0
    else
        local su_exit_status=$?
        log_error "使用 'su -l $ORIGINAL_USER -c \"...\"' 尝试启动 '$config_tool_cmd' 失败 (su 命令退出码: $su_exit_status)。"
        log_error "这可能表示切换用户失败，或命令执行环境有问题。"
        log_error "请尝试手动从终端以普通用户 '$ORIGINAL_USER' 身份运行 '$config_tool_cmd' 进行配置。"
        return 1
    fi
}




# 检查并安装必要的字体
_install_required_fonts() {
    log_info "检查并安装必要的字体..."
    local packages_to_install=()

    if ! _is_font_installed "Noto Sans CJK"; then
        packages_to_install+=(noto-fonts-cjk)
    fi
    if ! _is_font_installed "Noto Color Emoji"; then
        packages_to_install+=(noto-fonts-emoji)
    fi
    if ! _is_font_installed "Noto Sans"; then # 通用西文字体
        packages_to_install+=(noto-fonts)
    fi
    # 可根据 SELECTED_SCHEMES 添加更多特定字体，如 wqy-zenhei 等

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "以下推荐字体包建议安装: ${packages_to_install[*]}"
        if _confirm_action "是否安装这些字体包?" "y"; then
            if install_packages "${packages_to_install[@]}"; then
                log_success "推荐字体安装成功。"
            else
                log_error "部分或全部推荐字体安装失败。"
            fi
        else
            log_info "跳过安装推荐字体。"
        fi
    else
        log_info "未发现需要安装的核心字体，或已跳过。"
    fi
    return 0
}

# ==============================================================================
# 主流程函数 (由 main 菜单调用)
# ==============================================================================

# 安装输入法框架
_install_im_framework() {
    display_header_section "选择要安装的输入法框架" "box" 80
    local available_frameworks_for_selection=()
    _display_framework_options_list available_frameworks_for_selection INPUT_METHOD_FRAMEWORKS

    local selection
    read -rp "$(echo -e "${COLOR_YELLOW}请选择框架 [1-$((${#available_frameworks_for_selection[@]}))], 0 取消: ${COLOR_RESET}")" selection

    if [[ "$selection" == "0" ]]; then log_info "操作已取消。"; return 0; fi
    if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_frameworks_for_selection[@]} )); then
        log_error "无效选择: '$selection'。"; return 1;
    fi

    local chosen_framework_key="${available_frameworks_for_selection[$((selection - 1))]}"
    if [[ -n "$SELECTED_FRAMEWORK" && "$SELECTED_FRAMEWORK" != "$chosen_framework_key" && ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
        if _confirm_action "更改框架将清空已选方案。是否继续?" "y" "${COLOR_RED}"; then
            SELECTED_SCHEMES=()
        else
            log_info "框架更改已取消。"; return 0;
        fi
    fi
    SELECTED_FRAMEWORK="$chosen_framework_key"
    log_info "您选择了: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"

    if _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
        if ! _confirm_action "'${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已安装。是否重新安装?" "n" "${COLOR_YELLOW}"; then
            log_info "保留已安装的框架。"; return 0;
        fi
    fi

    local dependencies="${FRAMEWORK_DEPENDENCIES[$SELECTED_FRAMEWORK]}"
    log_info "将安装框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 依赖: $dependencies"
    if install_packages "$dependencies"; then
        log_success "框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装成功。"; return 0;
    else
        log_error "框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装失败。"; return 1;
    fi
}

# 安装输入方案
_install_input_schemes() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。"
        if ! _install_im_framework; then return 1; fi
        if [[ -z "$SELECTED_FRAMEWORK" ]]; then log_info "未选框架，取消安装方案。"; return 0; fi
    fi

    while true; do
        clear
        display_header_section "选择输入方案 (用于 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]})" "box" 80
        echo -e "${COLOR_CYAN}当前已选方案 (${#SELECTED_SCHEMES[@]} 个):${COLOR_RESET}"
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
            local idx=1; for sk in "${SELECTED_SCHEMES[@]}"; do echo -e "  ${COLOR_YELLOW}${idx})${COLOR_RESET} ${INPUT_SCHEMES[$sk]}"; ((idx++)); done
        else echo -e "  (无)"; fi
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"

        local available_schemes_for_selection=()
        _display_scheme_options_list available_schemes_for_selection INPUT_SCHEMES "$SELECTED_FRAMEWORK" SELECTED_SCHEMES

        local selection
        read -rp "$(echo -e "${COLOR_YELLOW}输入序号 [1-$((${#available_schemes_for_selection[@]}))], 0 完成: ${COLOR_RESET}")" selection

        if [[ "$selection" == "0" ]]; then log_info "方案选择完成。"; break; fi
        if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_schemes_for_selection[@]} )); then
            log_warn "无效选择: '$selection'。"; _prompt_return_to_continue; continue;
        fi

        local actual_scheme_key="${available_schemes_for_selection[$((selection - 1))]}"
        local already_selected_index=-1
        for i in "${!SELECTED_SCHEMES[@]}"; do
            if [[ "${SELECTED_SCHEMES[$i]}" == "$actual_scheme_key" ]]; then already_selected_index=$i; break; fi
        done

        if (( already_selected_index != -1 )); then
            unset "SELECTED_SCHEMES[$already_selected_index]"; SELECTED_SCHEMES=("${SELECTED_SCHEMES[@]}")
            log_success "已取消: ${INPUT_SCHEMES[$actual_scheme_key]}"
        else
            SELECTED_SCHEMES+=("$actual_scheme_key")
            log_success "已选择: ${INPUT_SCHEMES[$actual_scheme_key]}"
        fi
        _prompt_return_to_continue "按 Enter 继续选择或完成..."
    done

    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then log_info "未选方案，跳过安装。"; return 0; fi
    log_info "最终选定方案 (${#SELECTED_SCHEMES[@]} 个):"; for sk in "${SELECTED_SCHEMES[@]}"; do log_info "  - ${INPUT_SCHEMES[$sk]}"; done
    if ! _confirm_action "确认安装/检查这 ${#SELECTED_SCHEMES[@]} 个方案吗?" "y"; then log_info "安装已取消。"; return 0; fi

    local schemes_to_actually_install=()
    for sk_key in "${SELECTED_SCHEMES[@]}"; do
        if ! _is_input_scheme_installed "$sk_key"; then schemes_to_actually_install+=("$sk_key");
        else log_info "方案 '${INPUT_SCHEMES[$sk_key]}' 已装，跳过。"; fi
    done

    if [[ ${#schemes_to_actually_install[@]} -eq 0 ]]; then log_success "所有选定方案均已安装。"; return 0; fi
    log_info "将实际安装 ${#schemes_to_actually_install[@]} 个新方案: ${schemes_to_actually_install[*]}"
    if install_packages "${schemes_to_actually_install[@]}"; then # 传递的是数组
        log_success "新输入方案安装成功。"; return 0;
    else
        log_error "部分或全部新输入方案安装失败。"; return 1;
    fi
}

# 配置输入法环境菜单
_configure_im_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then log_warn "请先选框架。"; _prompt_return_to_continue; return 1; fi
    display_header_section "配置输入法环境" "box" 80
    if _confirm_action "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 配置环境变量。继续吗?" "y" "${COLOR_YELLOW}"; then
        _configure_im_environment "$SELECTED_FRAMEWORK"; return $?
    else log_info "配置已取消。"; return 0; fi
}

# 配置桌面环境集成菜单
_configure_for_desktop_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then log_warn "请先选框架。"; _prompt_return_to_continue; return 1; fi
    display_header_section "配置桌面环境集成" "box" 80
    if _confirm_action "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 提供桌面 '$DESKTOP_ENV' 集成建议。继续吗?" "y"; then
        _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; return $?
    else log_info "配置已取消。"; return 0; fi
}

# 启动输入法配置工具菜单
_start_config_tool_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then log_warn "请先选框架。"; _prompt_return_to_continue; return 1; fi
    display_header_section "启动输入法配置工具" "box" 80
    if _confirm_action "将启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 配置工具。继续吗?" "y"; then
        _start_config_tool "$SELECTED_FRAMEWORK"; return $?
    else log_info "启动已取消。"; return 0; fi
}

# 完整安装流程
_run_full_installation() {
    display_header_section "完整输入法安装与配置流程" "box" 80
    # ... (日志和确认信息)
    if ! _confirm_action "是否开始完整流程?" "y" "${COLOR_GREEN}"; then log_info "流程已取消。"; return 0; fi

    if ! _install_im_framework; then log_error "步骤1: 框架安装失败/取消，中止。"; return 1; fi
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then log_error "步骤1: 未选有效框架，中止。"; return 1; fi
    log_success "步骤1: 框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 完成。"; _prompt_return_to_continue

    if ! _install_input_schemes; then log_error "步骤2: 方案安装失败/取消，中止。"; return 1; fi
    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then log_warn "步骤2: 未选方案。"; else log_success "步骤2: 方案选择完成。"; fi
    _prompt_return_to_continue

    if ! _configure_im_environment "$SELECTED_FRAMEWORK"; then log_error "步骤3: 环境变量配置失败，中止。"; return 1; fi
    log_success "步骤3: 环境变量配置完成。"; _prompt_return_to_continue

    if ! _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then log_warn "步骤4: 桌面集成指导或有问题。"; else log_success "步骤4: 桌面集成指导完成。"; fi
    _prompt_return_to_continue

    if ! _install_required_fonts; then log_warn "步骤5: 字体检查或安装或有问题。"; else log_success "步骤5: 字体检查完成。"; fi
    _prompt_return_to_continue

    clear; display_header_section "输入法完整安装流程已完成" "box" 80 "${COLOR_GREEN}"
    # ... (总结信息)
    log_summary "已选框架: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"
    if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
        log_summary "已安装/选定的输入方案:"
        for scheme_key in "${SELECTED_SCHEMES[@]}"; do log_summary "  - ${INPUT_SCHEMES[$scheme_key]}"; done
    fi
    log_summary "${COLOR_BOLD}重要后续步骤:${COLOR_RESET}"
    log_summary "1. ${COLOR_YELLOW}完全注销并重新登录您的用户会话${COLOR_RESET}。"
    log_summary "2. 登录后，通过配置工具确认方案、顺序和快捷键。"

    if _confirm_action "是否立即启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 配置工具?" "y" "${COLOR_YELLOW}"; then
        if ! _start_config_tool "$SELECTED_FRAMEWORK"; then log_warn "启动配置工具失败。"; fi
    fi
    log_success "完整安装流程结束。"; return 0
}

# ==============================================================================
# 主函数 (菜单入口)
# ==============================================================================
main() {
    local initial_framework_check_done=false
    local current_installed_framework=""

    while true; do
        clear
        display_header_section "Arch Linux 输入法安装与配置" "box" 80

        if [[ -n "$SELECTED_FRAMEWORK" ]]; then
            log_info "当前框架: ${COLOR_CYAN}${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}${COLOR_RESET} ($(_is_im_framework_installed "$SELECTED_FRAMEWORK" && echo "${COLOR_GREEN}已安装" || echo "${COLOR_RED}未安装")${COLOR_RESET})"
        elif ! "$initial_framework_check_done"; then
            for fw_key in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
                if _is_im_framework_installed "$fw_key"; then
                    current_installed_framework="$fw_key"
                    log_notice "检测到已安装框架: ${COLOR_GREEN}${INPUT_METHOD_FRAMEWORKS[$fw_key]}${COLOR_RESET}"
                    if _confirm_action "是否基于此框架操作?" "y" "${COLOR_YELLOW}"; then SELECTED_FRAMEWORK="$current_installed_framework"; fi
                    break
                fi
            done
            if [[ -z "$current_installed_framework" && -z "$SELECTED_FRAMEWORK" ]]; then log_warn "未检测到已安装框架。"; fi
            initial_framework_check_done=true
        fi
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
             log_info "已选方案 (${#SELECTED_SCHEMES[@]} 个):"; for sk in "${SELECTED_SCHEMES[@]}"; do echo -e "  - ${INPUT_SCHEMES[$sk]}"; done
        fi
        echo

        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 选择/安装输入法框架"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 选择/安装输入方案"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 配置输入法环境变量"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} 桌面环境集成指导"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} 启动输入法配置工具"
        echo -e "  ${COLOR_GREEN}6.${COLOR_RESET} 检查/安装推荐字体"
        echo -e "  ${COLOR_GREEN}7.${COLOR_RESET} ${COLOR_BOLD}完整安装与配置流程${COLOR_RESET}"
        echo -e "\n  ${COLOR_RED}0.${COLOR_RESET} 完成并返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"

        local choice; read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [0-7]: ${COLOR_RESET}")" choice; echo
        local op_status=0
        case "$choice" in
            1) _install_im_framework; op_status=$? ;;
            2) _install_input_schemes; op_status=$? ;;
            3) _configure_im_environment_menu; op_status=$? ;;
            4) _configure_for_desktop_environment_menu; op_status=$? ;;
            5) _start_config_tool_menu; op_status=$? ;;
            6) _install_required_fonts; op_status=$? ;;
            7) _run_full_installation; op_status=$? ;;
            0)
                log_info "输入法配置模块已退出。";
                if [[ -n "$SELECTED_FRAMEWORK" ]]; then log_warn "记得注销重登录使更改生效！"; fi
                break
                ;;
            *) log_warn "无效选择: '$choice'。"; op_status=99 ;;
        esac

        if [[ "$choice" != "0" ]]; then
            if (( op_status != 0 && op_status != 99 )); then log_error "操作未成功完成 (状态: $op_status)。"; fi
            _prompt_return_to_continue
        fi
    done
}

# --- 脚本入口 ---
main "$@"
exit 0这个现在是最终版了吧？