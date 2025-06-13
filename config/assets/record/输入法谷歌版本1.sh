#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_system_tools/01_input_method.sh
# 版本: 1.0.1 (修正多选逻辑，增强用户体验)
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
IM_ENV_FILE="${ORIGINAL_HOME}/.pam_environment" # 注意: .pam_environment 很多现代系统不再推荐，但某些DM可能仍读取
                                               # 更好的方式可能是 /etc/environment 或 systemd environment.d

# 检测当前桌面环境
DESKTOP_ENV_RAW="${XDG_CURRENT_DESKTOP:-unknown}"
DESKTOP_ENV=$(echo "$DESKTOP_ENV_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/:.*//') # 取第一个，并转小写

# 可用的输入法框架和输入方案
declare -A INPUT_METHOD_FRAMEWORKS=(
    ["fcitx5"]="Fcitx5 (推荐现代 Linux 系统)"
    ["ibus"]="IBus (经典输入法框架)"
)

declare -A INPUT_SCHEMES=(
    # 拼音输入法 (Fcitx5)
    ["fcitx5-chinese-addons"]="Fcitx5 中文输入方案集合 (包含多种拼音、双拼等)"
    ["fcitx5-pinyin-zhwiki"]="Fcitx5 中文维基百科词库 (需配合 fcitx5-pinyin)"
    ["fcitx5-rime"]="Fcitx5 Rime (中州韵，高度可定制)"
    # 拼音输入法 (IBus)
    ["ibus-pinyin"]="IBus 拼音输入法"
    ["ibus-libpinyin"]="IBus LibPinyin (推荐的 IBus 拼音引擎)" # 替换 sunpinyin
    ["ibus-rime"]="IBus Rime (中州韵)"

    # 五笔输入法 (Fcitx5)
    ["fcitx5-table-wubi"]="Fcitx5 五笔输入法 (基于码表)" # 更具体的包名
    # 五笔输入法 (IBus)
    ["ibus-table-wubi"]="IBus 五笔输入法 (基于码表)"

    # 日文输入法 (Fcitx5)
    ["fcitx5-mozc"]="Fcitx5 Mozc (日文)"
    # 日文输入法 (IBus)
    ["ibus-mozc"]="IBus Mozc (日文)" # 推荐 ibus-anthy 较老

    # 韩文输入法 (Fcitx5)
    ["fcitx5-hangul"]="Fcitx5 Hangul (韩文)"
    # 韩文输入法 (IBus)
    ["ibus-hangul"]="IBus Hangul (韩文)"

    # 表情符号 (Fcitx5)
    ["fcitx5-emoji"]="Fcitx5 表情符号支持"

    # 其他语言 (Fcitx5)
    ["fcitx5-unikey"]="Fcitx5 Unikey (越南语)"
)

# 输入法框架依赖的包
declare -A FRAMEWORK_DEPENDENCIES=(
    ["fcitx5"]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool" # fcitx5-im 包组通常包含这些
    ["ibus"]="ibus ibus-gtk ibus-gtk3 ibus-qt" # ibus 包组通常包含这些
)

# 选中的输入法框架和输入方案
SELECTED_FRAMEWORK=""
SELECTED_SCHEMES=() # 存储用户选中的输入方案的键名

# ==============================================================================
# 辅助函数
# ==============================================================================

# 对关联数组的键进行排序 (用于固定菜单显示顺序)
get_sorted_keys_for_assoc_array() {
    local -n arr_ref="$1" # nameref 指向传入的关联数组
    printf '%s\n' "${!arr_ref[@]}" | sort
}

# 检查字体是否安装
_is_font_installed() {
    local font_name_pattern="$1"
    if fc-list : family | grep -iqE "$font_name_pattern"; then
        return 0 # 找到了
    else
        return 1 # 未找到
    fi
}

# 简单的提示并等待回车继续的函数 (如果 utils.sh 中没有)
_prompt_return_to_continue() {
    local message="${1:-按 Enter 键继续...}"
    read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
}

# 检测当前是否安装了特定输入法框架
_is_im_framework_installed() {
    local framework="$1"
    case "$framework" in
        "fcitx5")
            is_package_installed "fcitx5" # 检查核心包
            ;;
        "ibus")
            is_package_installed "ibus" # 检查核心包
            ;;
        *)
            return 1 # 未知框架
            ;;
    esac
}

# 检测当前是否安装了特定输入方案
_is_input_scheme_installed() {
    local scheme_package_name="$1" # 参数应该是包名
    is_package_installed "$scheme_package_name"
}

# 显示可用的输入法框架列表 (此函数仅用于显示，不处理选择逻辑)
_display_framework_options_list() {
    # 此函数被 _install_im_framework 调用，动态构建列表并显示
    # 参数 $1: available_frameworks_for_selection 数组的引用 (nameref)
    # 参数 $2: INPUT_METHOD_FRAMEWORKS 数组的引用 (nameref)
    local -n _available_frameworks_ref="$1"
    local -n _frameworks_data_ref="$2"

    local display_count=1
    # 使用 get_sorted_keys_for_assoc_array 来保证顺序
    for framework_key in $(get_sorted_keys_for_assoc_array _frameworks_data_ref); do
        local status=""
        if _is_im_framework_installed "$framework_key"; then
            status="(${COLOR_GREEN}已安装${COLOR_RESET})"
        else
            status="(${COLOR_RED}未安装${COLOR_RESET})"
        fi
        echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${_frameworks_data_ref[$framework_key]} $status"
        _available_frameworks_ref+=("$framework_key") # 将框架键名添加到临时数组
        ((display_count++))
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消并返回"
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
}


# 显示可用的输入方案列表 (此函数仅用于显示，不处理选择逻辑)
_display_scheme_options_list() {
    # 此函数被 _install_input_schemes 调用，动态构建列表并显示
    # 参数 $1: available_schemes_for_selection 数组的引用 (nameref)
    # 参数 $2: INPUT_SCHEMES 数组的引用 (nameref)
    # 参数 $3: SELECTED_FRAMEWORK (字符串)
    # 参数 $4: SELECTED_SCHEMES 数组的引用 (nameref)

    local -n _available_schemes_ref="$1"
    local -n _schemes_data_ref="$2"
    local _current_framework="$3"
    local -n _current_selected_schemes_ref="$4"

    local display_count=1
    # 使用 get_sorted_keys_for_assoc_array 来保证顺序
    for scheme_key in $(get_sorted_keys_for_assoc_array _schemes_data_ref); do
        # 过滤出与所选框架兼容的方案 (基于键名的前缀)
        if [[ "$scheme_key" == "$_current_framework"* ]]; then
            local status=""
            if _is_input_scheme_installed "$scheme_key"; then # 假设 scheme_key 就是包名
                status="(${COLOR_GREEN}已安装${COLOR_RESET})"
            else
                status="(${COLOR_RED}未安装${COLOR_RESET})"
            fi

            # 检查是否已被选中
            local selected_indicator=""
            for s_chk in "${_current_selected_schemes_ref[@]}"; do
                if [[ "$s_chk" == "$scheme_key" ]]; then
                    selected_indicator="${COLOR_YELLOW}[已选]${COLOR_RESET} "
                    break
                fi
            done

            echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${selected_indicator}${_schemes_data_ref[$scheme_key]} $status"
            _available_schemes_ref+=("$scheme_key") # 将方案键名添加到临时数组
            ((display_count++))
        fi
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成选择并安装"
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
}


# 配置输入法环境变量
_configure_im_environment() {
    local framework="$1" # 选中的框架 (fcitx5 或 ibus)

    log_info "正在为 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 配置输入法环境变量..."

    # 创建备份
    # create_backup_and_cleanup 是 utils.sh 提供的函数
    create_backup_and_cleanup "$IM_CONFIG_FILE" "im_config_xprofile_backup" # 使用更明确的备份名
    create_backup_and_cleanup "$IM_ENV_FILE" "im_env_pam_backup"

    # 清理旧的输入法配置 (避免冲突)
    # 从 .xprofile 中移除已知的输入法环境变量设置
    sed -i -E -e '/^export (GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE)=/d' \
              -e '/^# Fcitx5 输入法配置/d' \
              -e '/^# IBus 输入法配置/d' \
              "$IM_CONFIG_FILE"
    # 从 .pam_environment 中移除已知的输入法环境变量设置
    if [ -f "$IM_ENV_FILE" ]; then # 确保文件存在
        sed -i -E -e '/^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE) DEFAULT=/d' "$IM_ENV_FILE"
    fi


    # 根据框架类型设置不同的环境变量
    case "$framework" in
        "fcitx5")
            log_info "配置 Fcitx5 环境变量到 $IM_CONFIG_FILE 和 $IM_ENV_FILE"
            # 配置 .xprofile (XDG 环境变量, 通常由 Display Manager source)
            # 使用 cat 追加到文件末尾，如果文件不存在则创建
            cat >> "$IM_CONFIG_FILE" << EOF

# Fcitx5 输入法配置 (由脚本添加于 $(date))
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
# INPUT_METHOD 和 SDL_IM_MODULE 通常会自动设置或不是所有应用都需要
# export INPUT_METHOD=fcitx
# export SDL_IM_MODULE=fcitx
EOF
            # 配置 .pam_environment (如果系统使用 PAM 来设置会话环境变量)
            # 注意: .pam_environment 已不被广泛推荐，但为兼容性保留
            # 确保文件存在，如果不存在则创建
            touch "$IM_ENV_FILE"
            cat >> "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
# INPUT_METHOD DEFAULT=fcitx
# SDL_IM_MODULE DEFAULT=fcitx
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
# export INPUT_METHOD=ibus
EOF
            touch "$IM_ENV_FILE"
            cat >> "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=ibus
QT_IM_MODULE DEFAULT=ibus
XMODIFIERS DEFAULT=@im=ibus
# INPUT_METHOD DEFAULT=ibus
EOF
            log_success "IBus 环境变量已写入配置文件。"
            ;;

        *)
            log_error "未知的输入法框架: $framework。无法配置环境变量。"
            return 1
            ;;
    esac

    # 设置文件权限
    # run_as_user "chown \"$ORIGINAL_USER:$ORIGINAL_USER\" \"$IM_CONFIG_FILE\" \"$IM_ENV_FILE\""
    # run_as_user "chmod 644 \"$IM_CONFIG_FILE\" \"$IM_ENV_FILE\""
    # 权限应由创建文件的用户（即脚本执行用户，通常是root）在写入后确保，
    # 或者如果以普通用户身份写入，则不需要额外chown/chmod。
    # 这里假设脚本以root执行，但文件位于普通用户家目录。
    # 如果 ORIGINAL_HOME 和 ORIGINAL_USER 可靠，以下操作是安全的。
    if [ -f "$IM_CONFIG_FILE" ]; then
        chown "$ORIGINAL_USER:$ORIGINAL_USER_GROUP" "$IM_CONFIG_FILE"
        chmod 644 "$IM_CONFIG_FILE"
    fi
    if [ -f "$IM_ENV_FILE" ]; then
        chown "$ORIGINAL_USER:$ORIGINAL_USER_GROUP" "$IM_ENV_FILE"
        chmod 644 "$IM_ENV_FILE"
    fi

    log_notice "环境变量已配置。更改将在下次登录或重启 X 会话后生效。"
    log_warn "请注意: .pam_environment 的支持因系统和显示管理器的不同而异。"
    log_info "推荐检查您的显示管理器和桌面环境文档，了解设置 IM 环境变量的最佳实践。"
    return 0
}

# 为特定桌面环境配置输入法
_configure_for_desktop_environment() {
    local framework="$1" # 选中的框架

    log_info "尝试为桌面环境 '$DESKTOP_ENV' 配置输入法 '$framework'..."

    # 对于大多数桌面环境，环境变量的设置是关键。
    # im-config 工具 (如果安装) 可以帮助管理这些。
    if is_package_installed "im-config"; then
        log_info "'im-config' 工具已安装。可以尝试使用它来设置活动输入法。"
        if _confirm_action "是否尝试使用 'im-config -n $framework' 来设置 '$framework' 为活动输入法?" "y"; then
            if run_as_user "im-config -n $framework"; then
                log_success "'im-config -n $framework' 执行成功。"
                log_notice "通过 im-config 的更改通常在下次登录后生效。"
                # im-config 会处理 .xinputrc 或类似文件，可能覆盖部分 .xprofile 设置
            else
                log_warn "'im-config -n $framework' 执行失败或被取消。"
            fi
        fi
    else
        log_info "'im-config' 工具未安装。将依赖手动配置或特定桌面环境的设置。"
    fi

    case "$DESKTOP_ENV" in
        "gnome")
            log_info "检测到 GNOME 桌面环境。"
            # GNOME 通常通过其设置守护进程管理输入源。
            # 环境变量设置后，Fcitx5/IBus 通常可以在 GNOME 设置中被找到并添加。
            log_notice "对于 GNOME，请在环境变量生效 (重新登录) 后，"
            log_notice "进入 GNOME 设置 -> 键盘 -> 输入源, 点击 '+' 添加 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 相关的输入法。"
            if [[ "$framework" == "ibus" ]]; then
                log_info "对于 IBus, GNOME 集成较好，通常可直接在设置中添加。"
            elif [[ "$framework" == "fcitx5" ]]; then
                log_info "对于 Fcitx5, 确保 fcitx5 守护进程在登录时启动。"
                log_info "可能需要在 GNOME Tweaks 中将 fcitx5 添加到启动应用程序，或检查 fcitx5 的自动启动配置。"
            fi
            # gsettings set org.gnome.settings-daemon.plugins.keyboard active true # 确保键盘插件活动
            # gsettings get org.gnome.desktop.input-sources sources # 查看当前输入源
            # 自动修改 gsettings 比较复杂且易出错，建议用户手动操作
            ;;

        "kde"|"plasma") # KDE Plasma
            log_info "检测到 KDE Plasma 桌面环境。"
            # KDE Plasma 也有自己的输入法配置模块。
            log_notice "对于 KDE Plasma, 请在环境变量生效 (重新登录) 后，"
            log_notice "进入系统设置 -> 区域设置 -> 输入法 (或类似路径), 配置 '${INPUT_METHOD_FRAMEWORKS[$framework]}'."
            if [[ "$framework" == "fcitx5" ]]; then
                log_info "Fcitx5 在 KDE Plasma 下通常需要安装 'kcm-fcitx5' (fcitx5-qt 的一部分) 以获得系统设置集成模块。"
                log_info "确保 fcitx5-autostart 或等效机制使 fcitx5 守护进程在登录时启动。"
            fi
            # kwriteconfig5 --file kcmimlocalsocket --group General --key socketFile $XDG_RUNTIME_DIR/fcitx5/dbuspath (示例，需验证)
            ;;
        "xfce")
            log_info "检测到 XFCE 桌面环境。"
            log_notice "对于 XFCE, 确保环境变量生效。可能需要在 '会话和启动' 中添加 fcitx5/ibus 启动项。"
            ;;
        "deepin")
            log_info "检测到 Deepin DDE 桌面环境。"
            log_notice "Deepin DDE 有自己的输入法设置，通常在控制中心配置。"
            ;;
        *)
            log_info "当前桌面环境为 '$DESKTOP_ENV'。没有特定的自动化配置步骤。"
            log_notice "请确保环境变量生效，并查阅您的桌面环境文档以配置输入法。"
            ;;
    esac

    log_notice "桌面环境相关的提示已提供。部分更改可能需要重启桌面环境或注销才能生效。"
    return 0
}

# 启动输入法配置工具
_start_config_tool() {
    local framework="$1" # 选中的框架

    log_info "准备启动 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的配置工具..."

    local config_tool_cmd=""
    case "$framework" in
        "fcitx5")
            config_tool_cmd="fcitx5-configtool"
            ;;
        "ibus")
            config_tool_cmd="ibus-setup" # 或者 ibus-pref-gtk3
            ;;
        *)
            log_error "未知的输入法框架: $framework。无法确定配置工具。"
            return 1
            ;;
    esac

    if ! command -v "$config_tool_cmd" &>/dev/null; then
        log_error "配置工具 '$config_tool_cmd' 未找到或未安装。请确保已安装框架的配置工具包。"
        return 1
    fi

    log_notice "将尝试以用户 '$ORIGINAL_USER' 身份启动 '$config_tool_cmd'。"
    log_warn "确保 X 服务器正在运行并且您有权限连接到显示器。"
    # run_as_user 函数需要能正确处理图形化应用的启动，可能需要设置 DISPLAY
    if run_as_user "export DISPLAY='${DISPLAY:-:0}'; nohup $config_tool_cmd >/dev/null 2>&1 &"; then
        log_success "'$config_tool_cmd' 已在后台启动。请切换到该窗口进行配置。"
        log_info "在配置工具中，您通常需要：1. 添加您安装的输入方案。 2. 调整顺序和快捷键。"
    else
        log_error "启动 '$config_tool_cmd' 失败。请尝试手动从终端以普通用户身份运行它。"
        return 1
    fi
    return 0
}

# 检查并安装必要的字体
_install_required_fonts() {
    log_info "检查并安装必要的字体..."
    local packages_to_install=()

    # 检查通用的中日韩字体 (Noto)
    # Noto CJK 包含了中文、日文、韩文的基础字形
    if ! _is_font_installed "Noto Sans CJK"; then # 更精确的 Noto CJK 字体族名
        log_notice "未检测到 Noto CJK 字体，建议安装以支持中日韩字符显示。"
        packages_to_install+=(noto-fonts-cjk)
    fi
    # 表情符号字体
    if ! _is_font_installed "Noto Color Emoji"; then
        log_notice "未检测到 Noto Color Emoji 字体，建议安装以支持彩色表情符号。"
        packages_to_install+=(noto-fonts-emoji)
    fi
    # 通用字体 (如果连基础的 Noto 都没有)
    if ! _is_font_installed "Noto Sans"; then
        packages_to_install+=(noto-fonts)
    fi


    # 根据已选择的输入方案推荐特定字体
    # (这部分可以非常复杂，这里仅作示例)
    for scheme in "${SELECTED_SCHEMES[@]}"; do
        if [[ "$scheme" == *"rime"* ]] || [[ "$scheme" == *"chinese-addons"* ]]; then
            # Rime 和一些中文方案可能需要更全的字体
            if ! _is_font_installed "WenQuanYi Zen Hei"; then # 文泉驿正黑
                 # packages_to_install+=(wqy-zenhei) # 可以考虑添加
                 : # 占位，避免空语句
            fi
        fi
        # 可以为日文、韩文等添加特定字体检查
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "将尝试安装以下推荐字体包: ${packages_to_install[*]}"
        if _confirm_action "是否安装推荐的字体包?" "y"; then
            if install_packages "${packages_to_install[@]}"; then
                log_success "推荐字体安装成功。"
            else
                log_error "部分或全部推荐字体安装失败。"
                # 非致命错误，可以继续
            fi
        else
            log_info "跳过安装推荐字体。"
        fi
    else
        log_info "未发现需要立即安装的缺失核心字体，或用户已跳过。"
    fi

    log_success "字体检查完成。"
    return 0 # 字体安装通常不应阻塞主流程
}

# ==============================================================================
# 主流程函数 (由 main 菜单调用)
# ==============================================================================

# 安装输入法框架
_install_im_framework() {
    display_header_section "选择要安装的输入法框架" "box" 80

    local available_frameworks_for_selection=() # 临时数组，索引从0开始
    # 调用显示函数填充可选项
    _display_framework_options_list available_frameworks_for_selection INPUT_METHOD_FRAMEWORKS

    local selection
    read -rp "$(echo -e "${COLOR_YELLOW}请选择输入法框架 [1-$((${#available_frameworks_for_selection[@]}))], 0 取消: ${COLOR_RESET}")" selection

    if [[ "$selection" == "0" ]]; then
        log_info "操作已取消。"
        # SELECTED_FRAMEWORK 保持不变或如果需要，可以在此清空
        return 0 # 用户取消，非错误
    fi

    # 验证输入
    if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_frameworks_for_selection[@]} )); then
        log_error "无效的选择: '$selection'。"
        # SELECTED_FRAMEWORK="" # 出错时可以考虑重置
        return 1 # 输入错误
    fi

    # 获取用户选择的真实框架键名 (数组索引是 selection - 1)
    local chosen_framework_key="${available_frameworks_for_selection[$((selection - 1))]}"

    # 如果选择的框架与当前 SELECTED_FRAMEWORK 不同，则清空已选的输入方案
    if [[ -n "$SELECTED_FRAMEWORK" && "$SELECTED_FRAMEWORK" != "$chosen_framework_key" ]]; then
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
            log_warn "输入法框架已从 '$SELECTED_FRAMEWORK' 更改为 '$chosen_framework_key'。"
            if _confirm_action "这将清空先前为 '$SELECTED_FRAMEWORK' 选择的 ${#SELECTED_SCHEMES[@]} 个输入方案。是否继续?" "y" "${COLOR_RED}"; then
                log_info "已清空之前选择的输入方案。"
                SELECTED_SCHEMES=()
            else
                log_info "框架更改已取消，保留原框架 '$SELECTED_FRAMEWORK' 和已选方案。"
                return 0 # 用户取消更改
            fi
        fi
    fi
    SELECTED_FRAMEWORK="$chosen_framework_key" # 更新全局选中的框架

    log_info "您选择了输入法框架: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"

    if _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
        log_warn "所选输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已安装。"
        if ! _confirm_action "是否要重新安装此框架 (这不会卸载已安装的输入方案)?" "n" "${COLOR_YELLOW}"; then
            log_info "保留已安装的框架。如果需要配置，请从主菜单选择相应选项。"
            return 0 # 框架已安装且用户不想重装，则认为此步骤成功
        fi
        log_info "用户选择重新安装框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}'."
    fi

    local dependencies="${FRAMEWORK_DEPENDENCIES[$SELECTED_FRAMEWORK]}"
    log_info "将安装框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 及其核心依赖包: $dependencies"

    if install_packages $dependencies; then # install_packages 是 utils.sh 提供的函数
        log_success "输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装成功。"
        return 0
    else
        log_error "输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装失败。"
        # SELECTED_FRAMEWORK="" # 安装失败则重置，防止后续操作基于错误状态
        return 1
    fi
}

# 安装输入方案
_install_input_schemes() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。"
        _prompt_return_to_continue "按 Enter 返回主菜单以选择框架，或在此选择一个框架..."
        if ! _install_im_framework; then # 调用框架选择，如果失败或取消则返回
            return 1 # _install_im_framework 返回1表示错误
        fi
        # 如果 _install_im_framework 用户取消 (返回0) 且 SELECTED_FRAMEWORK 仍为空
        if [[ -z "$SELECTED_FRAMEWORK" ]]; then
            log_info "未选择输入法框架，无法安装输入方案。"
            return 0 # 非错误，用户流程
        fi
    fi

    # 主循环，用于选择/取消选择输入方案
    while true; do
        clear # 每次循环前清屏，以刷新列表
        display_header_section "选择输入方案 (用于 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]})" "box" 80
        echo -e "${COLOR_CYAN}当前已选方案 (${#SELECTED_SCHEMES[@]} 个):${COLOR_RESET}"
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
            local display_idx=1
            for sel_scheme_key in "${SELECTED_SCHEMES[@]}"; do
                 # 确保 sel_scheme_key 存在于 INPUT_SCHEMES 中 (防御性编程)
                if [[ -n "${INPUT_SCHEMES[$sel_scheme_key]}" ]]; then
                    echo -e "  ${COLOR_YELLOW}${display_idx})${COLOR_RESET} ${INPUT_SCHEMES[$sel_scheme_key]}"
                    ((display_idx++))
                fi
            done
        else
            echo -e "  (无)"
        fi
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        echo -e "${COLOR_CYAN}请从以下列表选择要添加/移除的方案:${COLOR_RESET}"

        local available_schemes_for_selection=() # 临时数组，用于映射用户输入的数字
        # 调用显示函数，并填充 available_schemes_for_selection
        _display_scheme_options_list available_schemes_for_selection INPUT_SCHEMES "$SELECTED_FRAMEWORK" SELECTED_SCHEMES

        local selection
        read -rp "$(echo -e "${COLOR_YELLOW}输入方案序号 [1-$((${#available_schemes_for_selection[@]}))], 0 完成: ${COLOR_RESET}")" selection

        if [[ "$selection" == "0" ]]; then
            log_info "输入方案选择完成。"
            break # 跳出选择循环
        fi

        # 验证输入是否为数字且在有效范围内
        if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_schemes_for_selection[@]} )); then
            log_warn "无效选择: '$selection'。请输入列表中的有效数字或 0。"
            _prompt_return_to_continue
            continue # 继续循环，重新显示选项
        fi

        # 获取用户选择的真实输入方案键名 (数组索引是 selection - 1)
        local actual_scheme_key="${available_schemes_for_selection[$((selection - 1))]}"

        # 检查是否已选中，并进行添加或移除操作
        local already_selected_index=-1
        for i in "${!SELECTED_SCHEMES[@]}"; do # 获取 SELECTED_SCHEMES 数组的索引
            if [[ "${SELECTED_SCHEMES[$i]}" == "$actual_scheme_key" ]]; then
                already_selected_index=$i
                break
            fi
        done

        if (( already_selected_index != -1 )); then
            # 如果已选中，则取消选择 (从数组中移除)
            unset "SELECTED_SCHEMES[$already_selected_index]"
            # 重建数组以消除因 unset 造成的空洞 (bash数组特性)
            SELECTED_SCHEMES=("${SELECTED_SCHEMES[@]}") # 重新赋值以压缩数组
            log_success "已取消选择: ${INPUT_SCHEMES[$actual_scheme_key]}"
        else
            # 否则添加到选择列表
            SELECTED_SCHEMES+=("$actual_scheme_key")
            log_success "已选择: ${INPUT_SCHEMES[$actual_scheme_key]}"
        fi
        _prompt_return_to_continue "按 Enter 继续选择或完成..." # 给用户看结果的时间
    done # 结束 while true 选择循环

    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then
        log_info "未选择任何输入方案，跳过安装。"
        return 0 # 没有选择方案，非错误
    fi

    log_info "最终选定的输入方案 (${#SELECTED_SCHEMES[@]} 个):"
    for final_scheme_key in "${SELECTED_SCHEMES[@]}"; do
        log_info "  - ${INPUT_SCHEMES[$final_scheme_key]}"
    done

    if ! _confirm_action "确认安装/检查这 ${#SELECTED_SCHEMES[@]} 个输入方案吗?" "y"; then
        log_info "输入方案安装已取消。"
        return 0
    fi

    # 过滤掉已经安装的方案
    local schemes_to_actually_install=()
    for scheme_to_check_key in "${SELECTED_SCHEMES[@]}"; do
        # 假设输入方案的键名就是其包名
        if ! _is_input_scheme_installed "$scheme_to_check_key"; then
            schemes_to_actually_install+=("$scheme_to_check_key")
        else
            log_info "输入方案 '${INPUT_SCHEMES[$scheme_to_check_key]}' (包: $scheme_to_check_key) 已安装，将跳过。"
        fi
    done

    if [[ ${#schemes_to_actually_install[@]} -eq 0 ]]; then
        log_success "所有选定的输入方案均已安装，无需额外安装操作。"
        return 0
    fi

    log_info "将实际安装以下 ${#schemes_to_actually_install[@]} 个新的输入方案: ${schemes_to_actually_install[*]}"
    if install_packages "${schemes_to_actually_install[@]}"; then # install_packages 是 utils.sh 提供的函数
        log_success "选定的新输入方案安装成功。"
        return 0
    else
        log_error "部分或全部新输入方案安装失败。"
        return 1
    fi
}


# 配置输入法环境菜单 (调用实际配置函数)
_configure_im_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。请先从主菜单选择 '安装输入法框架'。"
        _prompt_return_to_continue
        return 1 # 或者引导用户去选择框架
    fi

    display_header_section "配置输入法环境" "box" 80
    log_info "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 配置系统环境变量。"
    log_warn "这将修改用户家目录下的 .xprofile 和 .pam_environment 文件。"

    if _confirm_action "确认继续配置环境变量吗?" "y" "${COLOR_YELLOW}"; then
        if _configure_im_environment "$SELECTED_FRAMEWORK"; then
            # _configure_im_environment 内部已有成功/失败日志
            return 0
        else
            return 1
        fi
    else
        log_info "环境变量配置操作已取消。"
        return 0
    fi
}

# 配置桌面环境集成菜单 (调用实际配置函数)
_configure_for_desktop_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。请先从主菜单选择 '安装输入法框架'。"
        _prompt_return_to_continue
        return 1
    fi

    display_header_section "配置桌面环境集成" "box" 80
    log_info "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 提供桌面环境 '$DESKTOP_ENV' 的集成建议/操作。"

    if _confirm_action "确认继续进行桌面环境集成配置/建议吗?" "y"; then
        if _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then
            # _configure_for_desktop_environment 内部已有日志
            return 0
        else
            return 1 # 理论上此函数目前只提供建议，应返回0
        fi
    else
        log_info "桌面环境集成配置操作已取消。"
        return 0
    fi
}

# 启动输入法配置工具菜单 (调用实际启动函数)
_start_config_tool_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。请先从主菜单选择 '安装输入法框架'。"
        _prompt_return_to_continue
        return 1
    fi

    display_header_section "启动输入法配置工具" "box" 80
    log_info "将尝试启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的图形化配置工具。"

    if _confirm_action "确认启动配置工具吗?" "y"; then
        if _start_config_tool "$SELECTED_FRAMEWORK"; then
            # _start_config_tool 内部已有日志
            return 0
        else
            return 1
        fi
    else
        log_info "启动配置工具操作已取消。"
        return 0
    fi
}

# 完整安装流程
_run_full_installation() {
    display_header_section "完整输入法安装与配置流程" "box" 80

    log_info "此流程将引导您完成以下步骤:"
    log_info "  1. 选择并安装输入法框架 (Fcitx5 或 IBus)"
    log_info "  2. 选择并安装所需的输入方案 (如拼音、五笔等)"
    log_info "  3. 配置系统环境变量以启用所选输入法框架"
    log_info "  4. 提供桌面环境集成指导"
    log_info "  5. 检查并安装推荐的字体"
    log_info "  6. (可选) 启动输入法配置工具"
    echo # 空行

    if ! _confirm_action "是否开始完整的输入法安装与配置流程?" "y" "${COLOR_GREEN}"; then
        log_info "完整安装流程已取消。"
        return 0
    fi

    # 步骤 1: 安装输入法框架
    if ! _install_im_framework; then
        log_error "步骤 1: 安装输入法框架失败或被取消。完整流程中止。"
        return 1
    fi
    # 确保框架已选
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_error "步骤 1: 未选择有效的输入法框架。完整流程中止。"
        return 1
    fi
    log_success "步骤 1: 输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已选择/安装。"
    _prompt_return_to_continue

    # 步骤 2: 安装输入方案
    if ! _install_input_schemes; then
        log_error "步骤 2: 安装输入方案失败或被取消。完整流程中止。"
        return 1
    fi
    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then
        log_warn "步骤 2: 未选择任何输入方案。您可以稍后单独添加。"
    else
        log_success "步骤 2: 输入方案已选择/安装。"
    fi
    _prompt_return_to_continue

    # 步骤 3: 配置输入法环境
    if ! _configure_im_environment "$SELECTED_FRAMEWORK"; then # 直接调用，不通过菜单函数
        log_error "步骤 3: 配置输入法环境变量失败。完整流程中止。"
        # 这是一个关键步骤，失败则后续意义不大
        return 1
    fi
    log_success "步骤 3: 输入法环境变量已配置。"
    _prompt_return_to_continue

    # 步骤 4: 配置桌面环境集成
    if ! _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then # 直接调用
        log_warn "步骤 4: 桌面环境集成配置/建议提供期间可能存在问题，但不中止流程。"
        # 此步骤更多是指导性的，不应中止主流程
    else
        log_success "步骤 4: 桌面环境集成指导已提供。"
    fi
    _prompt_return_to_continue

    # 步骤 5: 安装必要的字体
    if ! _install_required_fonts; then # 直接调用
        log_warn "步骤 5: 检查或安装字体期间可能存在问题，但不中止流程。"
    else
        log_success "步骤 5: 字体检查与推荐安装已完成。"
    fi
    _prompt_return_to_continue

    # 最终总结信息
    clear
    display_header_section "输入法完整安装流程已完成" "box" 80 "${COLOR_GREEN}"
    log_summary "祝贺您！输入法 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已基本配置完成。" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "已选框架: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"
    if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
        log_summary "已安装/选定的输入方案:"
        for scheme_key in "${SELECTED_SCHEMES[@]}"; do
            log_summary "  - ${INPUT_SCHEMES[$scheme_key]}"
        done
    else
        log_summary "未选择特定的输入方案 (可稍后通过配置工具添加)。"
    fi
    log_summary "环境变量已配置到: $IM_CONFIG_FILE 和 $IM_ENV_FILE"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "${COLOR_BOLD}重要后续步骤:${COLOR_RESET}"
    log_summary "1. ${COLOR_YELLOW}完全注销并重新登录您的用户会话${COLOR_RESET} (或重启计算机) 以使所有更改生效。"
    log_summary "2. 登录后，您可能需要通过 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的配置工具来:"
    log_summary "   - 确认您安装的输入方案已启用。"
    log_summary "   - 调整输入方案的顺序。"
    log_summary "   - 设置您偏好的输入法切换快捷键 (通常默认为 Ctrl+Space 或 Super+Space)。"
    log_summary "3. 如果遇到问题，请检查本脚本的日志文件以及 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的相关文档。"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"

    # 步骤 6: (可选) 启动输入法配置工具
    if _confirm_action "是否立即启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的配置工具?" "y" "${COLOR_YELLOW}"; then
        if ! _start_config_tool "$SELECTED_FRAMEWORK"; then
            log_warn "启动配置工具失败。请在重新登录后手动尝试。"
        fi
    else
        log_info "您可以稍后从主菜单或手动启动配置工具。"
    fi

    log_success "完整安装流程结束。"
    return 0
}

# ==============================================================================
# 主函数 (菜单入口)
# ==============================================================================
main() {
    # 首次运行时检查并提示当前状态
    local initial_framework_check_done=false
    local current_installed_framework=""

    while true; do
        clear
        display_header_section "Arch Linux 输入法安装与配置" "box" 80

        # 动态显示当前选定/已安装的框架信息
        if [[ -n "$SELECTED_FRAMEWORK" ]]; then
            log_info "当前操作的输入法框架: ${COLOR_CYAN}${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}${COLOR_RESET}"
            if _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
                log_info "状态: ${COLOR_GREEN}已安装${COLOR_RESET}"
            else
                log_info "状态: ${COLOR_RED}未安装 (或选择后未执行安装)${COLOR_RESET}"
            fi
        elif ! "$initial_framework_check_done"; then
            # 首次进入主菜单时，检测系统中已安装的框架
            for fw_key in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
                if _is_im_framework_installed "$fw_key"; then
                    current_installed_framework="$fw_key"
                    log_notice "检测到系统中已安装输入法框架: ${COLOR_GREEN}${INPUT_METHOD_FRAMEWORKS[$fw_key]}${COLOR_RESET}"
                    if _confirm_action "是否基于此已安装的框架进行后续操作?" "y" "${COLOR_YELLOW}"; then
                        SELECTED_FRAMEWORK="$current_installed_framework"
                        # 可以考虑加载此框架已安装的输入方案到 SELECTED_SCHEMES (较复杂)
                    fi
                    break # 只处理第一个找到的
                fi
            done
            if [[ -z "$current_installed_framework" ]] && [[ -z "$SELECTED_FRAMEWORK" ]]; then
                log_warn "未检测到系统中安装任何受支持的输入法框架。"
            fi
            initial_framework_check_done=true # 避免重复检测
        fi
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
             log_info "当前已选的输入方案 (${#SELECTED_SCHEMES[@]} 个):"
             for sch_key in "${SELECTED_SCHEMES[@]}"; do echo -e "  - ${INPUT_SCHEMES[$sch_key]}"; done
        fi
        echo # 空行

        # 主菜单选项
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 选择/安装输入法框架 (当前: ${SELECTED_FRAMEWORK:-未选})"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 选择/安装输入方案 (需先选框架)"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 配置输入法环境变量 (需先选框架)"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} 桌面环境集成指导 (需先选框架)"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} 启动输入法配置工具 (需先选框架并安装)"
        echo -e "  ${COLOR_GREEN}6.${COLOR_RESET} 检查/安装推荐字体"
        echo -e "  ${COLOR_GREEN}7.${COLOR_RESET} ${COLOR_BOLD}完整安装与配置流程 (推荐新用户)${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成并返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"

        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [0-7]: ${COLOR_RESET}")" choice
        echo # 输出一个空行，美化界面

        local operation_status=0 # 用于接收各函数返回值
        case "$choice" in
            1) _install_im_framework; operation_status=$? ;;
            2) _install_input_schemes; operation_status=$? ;;
            3) _configure_im_environment_menu; operation_status=$? ;;
            4) _configure_for_desktop_environment_menu; operation_status=$? ;;
            5) _start_config_tool_menu; operation_status=$? ;;
            6) _install_required_fonts; operation_status=$? ;; # 通常返回0
            7) _run_full_installation; operation_status=$? ;;
            0)
                log_info "输入法配置模块已退出。"
                # 可以在这里询问用户是否确认所有更改，或提示他们注销
                if [[ -n "$SELECTED_FRAMEWORK" ]]; then # 如果有操作过
                    log_warn "如果您进行了任何安装或配置更改，请记得注销并重新登录以使更改生效！"
                fi
                break # 退出主循环
                ;;
            *)
                log_warn "无效选择: '$choice'。请重新输入。"
                operation_status=99 # 特殊值表示无效输入
                ;;
        esac

        # 如果不是退出或无效输入，则提示用户返回主菜单
        if [[ "$choice" != "0" ]]; then
            if (( operation_status == 0 )); then
                # log_info "操作完成。" # 各函数内部已有详细日志
                :
            elif (( operation_status != 99 )); then # 非无效输入导致的非0状态
                log_error "操作未成功完成或被取消 (状态码: $operation_status)。"
            fi
            _prompt_return_to_continue "按 Enter 键返回输入法配置主菜单..."
        fi
    done
}

# --- 脚本入口 ---
main "$@"
exit 0 # main 函数自己会处理退出状态