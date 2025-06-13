#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/04_common_software_installation/02_install_input_method.sh (示例路径)
# 版本: 1.0.3 (注释更新，符合最佳实践标注)
# 日期: 2025-06-15
# 描述: Arch Linux 输入法安装与配置模块。
#       提供图形化菜单引导用户选择、安装和配置 fcitx5 或 ibus 输入法框架及其方案。
# ------------------------------------------------------------------------------
# 功能说明:
# - 动态菜单支持选择 Fcitx5 或 IBus 输入法框架。
# - 动态菜单支持为选定框架选择多种输入方案 (如拼音、五笔、日文、韩文等)。
# - 自动备份和配置输入法相关的系统环境变量 (如 .xprofile, .pam_environment)。
# - 提供针对常见桌面环境 (GNOME, KDE, XFCE) 的输入法集成指导。
# - 包含检查和安装推荐字体的功能。
# - 支持以普通用户身份安全启动输入法框架的图形化配置工具。
# - 提供完整的引导式安装流程以及单独配置各个步骤的选项。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh: (间接) 项目环境初始化，提供 BASE_DIR, ORIGINAL_USER 等。
#   - utils.sh: (直接) 提供日志、颜色、确认提示、头部显示等核心工具函数。
#   - package_management_utils.sh: (直接) 提供 is_package_installed, install_packages 等包管理函数。
#   - 系统命令: fc-list, id, su, nohup, fcitx5-configtool/ibus-setup (根据选择)。
# ------------------------------------------------------------------------------
# 注意事项:
#   - **包名准确性**: INPUT_SCHEMES 和 FRAMEWORK_DEPENDENCIES 中的包名/包组名
#     需要用户根据当前的 Arch Linux 官方仓库和 AUR 进行仔细核对和调整。
#   - **环境变量生效**: 大部分配置 (尤其是环境变量) 需要用户注销并重新登录图形会话才能生效。
#   - **桌面环境特定配置**: 脚本主要提供通用指导，特定桌面环境的深度集成可能仍需用户手动微调。
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 严格模式，确保脚本在遇到错误时能快速失败，并防止使用未定义变量。
set -euo pipefail
# 获取当前脚本的入口点路径，用于后续环境初始化。
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
# 检查并设置项目根目录 BASE_DIR (如果尚未设置)。
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
# 加载核心环境设置脚本，它会初始化日志、加载配置、工具库等。
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 全局变量和定义
# ==============================================================================
# 输入法框架相关的用户配置文件路径。
# ORIGINAL_HOME 由 environment_setup.sh 设置，指向执行 sudo 的原始用户的家目录。
IM_CONFIG_FILE="${ORIGINAL_HOME}/.xprofile"       # X Display Manager (XDM) 登录时通常会 source 此文件。
IM_ENV_FILE="${ORIGINAL_HOME}/.pam_environment" # PAM 模块可能读取此文件设置会话环境变量 (现代系统不常用)。

# 检测当前运行的桌面环境。
DESKTOP_ENV_RAW="${XDG_CURRENT_DESKTOP:-unknown}" # 从环境变量获取，可能包含多个值，如 "GNOME:GNOME-Classic"。
DESKTOP_ENV=$(echo "$DESKTOP_ENV_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/:.*//') # 转换为小写并取第一个值。

# 可用的输入法框架及其描述。
declare -A INPUT_METHOD_FRAMEWORKS=(
    ["fcitx5"]="Fcitx5 (推荐现代 Linux 系统)"
    ["ibus"]="IBus (经典输入法框架)"
)

# 可用的输入方案及其描述。
# !! 重要: 这里的键名需要是 Arch Linux 中对应的实际【包名】。用户需要根据实际情况核对和修改。
declare -A INPUT_SCHEMES=(
    # 拼音输入法 (Fcitx5)
    ["fcitx5-chinese-addons"]="Fcitx5 中文输入方案集合 (含多种拼音、云拼音、自然码等)"
    ["fcitx5-pinyin-zhwiki"]="Fcitx5 中文维基百科词库 (需 fcitx5-pinyin)" # 这是一个词库包
    ["fcitx5-rime"]="Fcitx5 Rime (中州韵，高度可定制)"
    # 拼音输入法 (IBus)
    ["ibus-libpinyin"]="IBus LibPinyin (推荐的 IBus 拼音引擎)"
    ["ibus-rime"]="IBus Rime (中州韵)"

    # 五笔输入法 (Fcitx5) - 包名需要确认，可能是 fcitx5-table-extra 或特定五笔包
    ["fcitx5-table-wubi"]="Fcitx5 五笔输入法 (基于码表, 请确认包名)"
    # 五笔输入法 (IBus) - 包名需要确认，可能是 ibus-table 或特定五笔包
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

# 输入法框架的核心依赖包。
# !! 注意: 考虑使用 Arch Linux 的【包组】(e.g., 'fcitx5-im', 'ibus') 可能更方便管理依赖。
declare -A FRAMEWORK_DEPENDENCIES=(
    ["fcitx5"]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool" # 示例包，或使用 'fcitx5-im' 包组
    ["ibus"]="ibus ibus-gtk ibus-gtk3 ibus-qt"                 # 示例包，或使用 'ibus' 包组
)

# 全局变量，用于存储用户当前选中的输入法框架的键名。
SELECTED_FRAMEWORK=""
# 全局数组，用于存储用户当前选中的所有输入方案的键名（即包名）。
SELECTED_SCHEMES=()

# ==============================================================================
# 辅助函数 (若在项目中多处复用，建议移至 utils.sh)
# ==============================================================================

# @description 获取关联数组的所有键，并进行排序。
# @param $1 (nameref) - 对关联数组的引用。
# @returns (stdout) - 每行一个排序后的键名。
# @example sorted_keys=($(get_sorted_keys_for_assoc_array MY_ASSOC_ARRAY))
get_sorted_keys_for_assoc_array() {
    local -n arr_ref="$1" # 使用 nameref 直接操作传入的数组名
    printf '%s\n' "${!arr_ref[@]}" | sort # 打印所有键，然后排序
}

# @description 显示一个提示消息，并等待用户按 Enter 键继续。
# @param $1 (string, optional) - 要显示的提示文本。默认为 "按 Enter 键继续..."。
_prompt_return_to_continue() {
    local message="${1:-按 Enter 键继续...}" # 如果未提供参数，使用默认消息
    # 使用 utils.sh 提供的颜色变量
    read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
}

# @description 检查指定的字体名称模式是否已安装在系统中。
# @param $1 (string) font_name_pattern - 要检查的字体名称模式 (支持 grep 正则表达式)。
# @returns (status) - 0 (已安装), 1 (未安装)。
# @depends fc-list, grep (系统命令)
_is_font_installed() {
    local font_name_pattern="$1"
    # fc-list : family 列出所有已安装字体的家族名称
    # grep -iqE 使用不区分大小写的扩展正则表达式进行静默匹配
    if fc-list : family | grep -iqE "$font_name_pattern"; then
        return 0 # 找到匹配字体，返回成功
    else
        return 1 # 未找到，返回失败
    fi
}

# @description 检测系统中是否已安装了指定的核心输入法框架包。
# @param $1 (string) framework - 输入法框架的键名 (如 "fcitx5", "ibus")。
# @returns (status) - 0 (已安装), 1 (未安装或未知框架)。
# @depends is_package_installed (from package_management_utils.sh)
_is_im_framework_installed() {
    local framework="$1"
    case "$framework" in
        "fcitx5") is_package_installed "fcitx5" ;; # 检查 fcitx5 核心包
        "ibus") is_package_installed "ibus" ;;     # 检查 ibus 核心包
        *) return 1 ;; # 未知框架，返回失败
    esac
}

# @description 检测系统中是否已安装了指定的输入方案包。
# @param $1 (string) scheme_package_name - 输入方案的包名。
# @returns (status) - 0 (已安装), 1 (未安装)。
# @depends is_package_installed (from package_management_utils.sh)
_is_input_scheme_installed() {
    local scheme_package_name="$1"
    is_package_installed "$scheme_package_name" # 直接调用包管理工具检查
}

# @description (内部) 显示可供选择的输入法框架列表，并标记其安装状态。
#              此函数仅负责显示，不处理用户的选择逻辑。
# @param $1 (nameref) _available_frameworks_ref - 用于存储可选项键名的数组的引用。
# @param $2 (nameref) _frameworks_data_ref - 包含框架数据 (键名->描述) 的关联数组的引用。
_display_framework_options_list() {
    local -n _available_frameworks_ref="$1" # nameref, 调用者需传入一个数组名
    local -n _frameworks_data_ref="$2"    # nameref, 指向 INPUT_METHOD_FRAMEWORKS
    _available_frameworks_ref=()          # 每次调用时清空输出数组，确保它是干净的

    local display_count=1 # 用于显示给用户的选项编号
    # 遍历排序后的框架键名，以保证菜单项顺序固定
    for framework_key in $(get_sorted_keys_for_assoc_array _frameworks_data_ref); do
        local status_indicator="" # 用于显示 "(已安装)" 或 "(未安装)"
        if _is_im_framework_installed "$framework_key"; then
            status_indicator="(${COLOR_GREEN}已安装${COLOR_RESET})"
        else
            status_indicator="(${COLOR_RED}未安装${COLOR_RESET})"
        fi
        # 格式化输出每个菜单项
        echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${_frameworks_data_ref[$framework_key]} $status_indicator"
        _available_frameworks_ref+=("$framework_key") # 将框架的实际键名存入可选项数组
        ((display_count++))
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消并返回" # 固定的退出选项
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}" # 分隔线
}

# @description (内部) 显示与当前选定框架兼容的输入方案列表，并标记其安装和选中状态。
#              此函数仅负责显示，不处理用户的选择逻辑。
# @param $1 (nameref) _available_schemes_ref - 用于存储可选项键名的数组的引用。
# @param $2 (nameref) _schemes_data_ref - 包含所有方案数据 (键名->描述) 的关联数组的引用 (INPUT_SCHEMES)。
# @param $3 (string) _current_framework - 当前选定的输入法框架的键名。
# @param $4 (nameref) _current_selected_schemes_ref - 当前已选方案列表 (SELECTED_SCHEMES) 的引用。
_display_scheme_options_list() {
    local -n _available_schemes_ref="$1"
    local -n _schemes_data_ref="$2"
    local _current_framework="$3"
    local -n _current_selected_schemes_ref="$4"
    _available_schemes_ref=() # 每次调用时清空输出数组

    local display_count=1 # 用户看到的选项编号
    # 遍历排序后的所有输入方案键名
    for scheme_key in $(get_sorted_keys_for_assoc_array _schemes_data_ref); do
        # 关键过滤：只显示与当前框架兼容的方案 (通过包名前缀判断，如 "fcitx5-" 或 "ibus-")
        if [[ "$scheme_key" == "$_current_framework"* ]]; then
            local install_status_indicator="" # "(已安装)" 或 "(未安装)"
            if _is_input_scheme_installed "$scheme_key"; then
                install_status_indicator="(${COLOR_GREEN}已安装${COLOR_RESET})"
            else
                install_status_indicator="(${COLOR_RED}未安装${COLOR_RESET})"
            fi

            local selection_status_indicator="" # "[已选]"
            # 检查此方案是否已在 SELECTED_SCHEMES 数组中
            for s_chk in "${_current_selected_schemes_ref[@]}"; do
                if [[ "$s_chk" == "$scheme_key" ]]; then
                    selection_status_indicator="${COLOR_YELLOW}[已选]${COLOR_RESET} "
                    break
                fi
            done

            # 格式化输出每个兼容的输入方案项
            echo -e "  ${COLOR_GREEN}${display_count}.${COLOR_RESET} ${selection_status_indicator}${_schemes_data_ref[$scheme_key]} $install_status_indicator"
            _available_schemes_ref+=("$scheme_key") # 将方案的实际键名 (包名) 存入可选项数组
            ((display_count++))
        fi
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成选择并安装" # 固定的完成选项
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}" # 分隔线
}

# @description 配置选定输入法框架的环境变量。
#              会备份现有的 .xprofile 和 .pam_environment 文件，然后写入新的配置。
# @param $1 (string) framework - 要配置的输入法框架的键名 (e.g., "fcitx5", "ibus")。
# @returns (status) - 0 (成功), 1 (失败或未知框架)。
# @depends create_backup_and_cleanup (from utils.sh), sed, touch, cat (系统命令), id (用于获取组名)。
_configure_im_environment() {
    local framework="$1" # 接收传入的框架名称

    log_info "正在为 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 配置输入法环境变量..."

    # 备份用户现有的配置文件，使用 utils.sh 中的通用备份函数
    # 第二个参数是备份子目录名，用于组织备份文件
    create_backup_and_cleanup "$IM_CONFIG_FILE" "im_config_xprofile_backup"
    create_backup_and_cleanup "$IM_ENV_FILE" "im_env_pam_backup"

    # 清理旧的输入法配置，避免环境变量重复或冲突
    # 使用 sed 直接在文件上操作 (in-place edit with -i)
    # -E 使用扩展正则表达式, -e 指定多个编辑命令
    # 匹配并删除以 "export GTK_IM_MODULE=" 等开头的行，以及特定注释行
    log_debug "清理 '$IM_CONFIG_FILE' 中旧的输入法环境变量..."
    sed -i -E \
        -e '/^export (GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE)=/d' \
        -e '/^# Fcitx5 输入法配置/d' \
        -e '/^# IBus 输入法配置/d' \
        "$IM_CONFIG_FILE"
    
    if [ -f "$IM_ENV_FILE" ]; then # 确保 .pam_environment 文件存在再操作
        log_debug "清理 '$IM_ENV_FILE' 中旧的输入法环境变量..."
        sed -i -E \
            -e '/^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE) DEFAULT=/d' \
            "$IM_ENV_FILE"
    fi

    # 根据选择的框架写入新的环境变量配置
    case "$framework" in
        "fcitx5")
            log_info "配置 Fcitx5 环境变量到 '$IM_CONFIG_FILE' 和 '$IM_ENV_FILE'"
            # 使用 here document (<< EOF) 向 .xprofile 追加配置
            cat >> "$IM_CONFIG_FILE" << EOF

# Fcitx5 输入法配置 (由脚本添加于 $(date))
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
# INPUT_METHOD 和 SDL_IM_MODULE 通常由 fcitx 自动处理或不是必需的，故注释掉
# export INPUT_METHOD=fcitx
# export SDL_IM_MODULE=fcitx
EOF
            # 对 .pam_environment 执行类似操作，先确保文件存在
            touch "$IM_ENV_FILE" 
            cat >> "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
# INPUT_METHOD DEFAULT=fcitx
# SDL_IM_MODULE DEFAULT=fcitx
EOF
            log_success "Fcitx5 环境变量已成功写入配置文件。"
            ;;
        "ibus")
            log_info "配置 IBus 环境变量到 '$IM_CONFIG_FILE' 和 '$IM_ENV_FILE'"
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
# export INPUT_METHOD=ibus
EOF
            log_success "IBus 环境变量已成功写入配置文件。"
            ;;
        *)
            log_error "未知的输入法框架: '$framework'。无法配置环境变量。"
            return 1 # 返回错误状态
            ;;
    esac

    # 设置配置文件的所有权和权限，确保它们属于原始用户且权限正确 (644)
    # 修复：在函数内部获取用户主组名，而不是依赖未定义的 ORIGINAL_USER_GROUP
    local user_primary_group
    user_primary_group=$(id -gn "$ORIGINAL_USER" 2>/dev/null) # 获取组名，并抑制潜在错误输出

    if [ -z "$user_primary_group" ]; then
        # 如果无法获取组名，记录警告，并只尝试设置用户所有者
        log_warn "无法获取用户 '$ORIGINAL_USER' 的主组名。文件组所有权可能不会被正确设置。"
        if [ -f "$IM_CONFIG_FILE" ]; then
            # chown 和 chmod 失败时记录警告，但不中止函数 (非致命)
            chown "$ORIGINAL_USER" "$IM_CONFIG_FILE" && chmod 644 "$IM_CONFIG_FILE" || \
                log_warn "设置 '$IM_CONFIG_FILE' 所有权/权限失败。"
        fi
        if [ -f "$IM_ENV_FILE" ]; then
            chown "$ORIGINAL_USER" "$IM_ENV_FILE" && chmod 644 "$IM_ENV_FILE" || \
                log_warn "设置 '$IM_ENV_FILE' 所有权/权限失败。"
        fi
    else
        # 如果成功获取组名，则同时设置用户和组所有者
        log_debug "用户 '$ORIGINAL_USER' 的主组是 '$user_primary_group'。"
        if [ -f "$IM_CONFIG_FILE" ]; then
            chown "$ORIGINAL_USER:$user_primary_group" "$IM_CONFIG_FILE" && chmod 644 "$IM_CONFIG_FILE" || \
                log_warn "设置 '$IM_CONFIG_FILE' 所有权/权限失败。"
        fi
        if [ -f "$IM_ENV_FILE" ]; then
            chown "$ORIGINAL_USER:$user_primary_group" "$IM_ENV_FILE" && chmod 644 "$IM_ENV_FILE" || \
                log_warn "设置 '$IM_ENV_FILE' 所有权/权限失败。"
        fi
    fi

    log_notice "环境变量已配置。更改将在下次登录或重启 X 会话后生效。"
    # 提示 .pam_environment 的兼容性问题
    log_warn "请注意: '.pam_environment' 文件的支持因系统和显示管理器的不同而异。"
    log_info "推荐检查您的显示管理器和桌面环境文档，了解设置输入法环境变量的最佳实践。"
    return 0 # 配置完成，返回成功
}

# @description 为特定的桌面环境提供输入法集成配置的指导。
#              对于某些环境，可能会尝试执行一些自动化配置命令。
# @param $1 (string) framework - 当前选定的输入法框架键名。
# @returns (status) - 0 (指导提供完成)。目前不因配置失败而返回错误。
# @depends is_package_installed (from package_management_utils.sh),
#           _confirm_action, run_as_user (from utils.sh)。
_configure_for_desktop_environment() {
    local framework="$1" # 选定的输入法框架

    log_info "尝试为桌面环境 '$DESKTOP_ENV' 配置输入法 '$framework' 的集成..."

    # 检查 im-config 工具。此工具在 Debian/Ubuntu 中常用，Arch Linux 不常用。
    if is_package_installed "im-config"; then
        log_info "'im-config' 工具已安装。"
        # 询问用户是否尝试使用 im-config (以普通用户身份运行)
        if _confirm_action "是否尝试使用 'im-config -n $framework' 来设置 '$framework' 为活动输入法?" "y"; then
            if run_as_user "im-config -n $framework"; then # im-config 通常以普通用户权限运行
                log_success "'im-config -n $framework' 执行成功。"
                log_notice "通过 im-config 的更改通常在下次登录后生效。"
            else
                log_warn "'im-config -n $framework' 执行失败或被用户取消。"
            fi
        fi
    else
        log_info "'im-config' 工具未安装。将依赖特定桌面环境的设置或手动配置。"
    fi

    # 根据检测到的桌面环境提供具体指导
    case "$DESKTOP_ENV" in
        "gnome")
            log_info "检测到 GNOME 桌面环境。"
            log_notice "对于 GNOME，请在环境变量生效 (需要重新登录) 后，"
            log_notice "进入 GNOME '设置' -> '键盘' -> '输入源' 部分。"
            log_notice "点击 '+' 按钮，然后查找并添加 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 相关的输入法。"
            if [[ "$framework" == "fcitx5" ]]; then
                log_info "对于 Fcitx5, 确保 fcitx5 守护进程在登录时启动 (通常通过 XDG Autostart)。"
            fi
            ;;
        "kde"|"plasma") # 匹配 KDE Plasma (XDG_CURRENT_DESKTOP 可能为 "KDE" 或 "plasma")
            log_info "检测到 KDE Plasma 桌面环境。"
            log_notice "对于 KDE Plasma, 请在环境变量生效 (需要重新登录) 后，"
            log_notice "进入 '系统设置' -> '区域设置' -> '输入法' (或类似路径)。"
            log_notice "在此处添加并配置 '${INPUT_METHOD_FRAMEWORKS[$framework]}'."
            # 提示 KDE 下 Fcitx5 的系统设置集成模块
            if [[ "$framework" == "fcitx5" ]] && ! is_package_installed "kcm-fcitx5"; then
                 log_warn "为了在 KDE 系统设置中更好地集成 Fcitx5, 建议安装 'kcm-fcitx5' 包。"
            fi
            log_info "确保 '${framework}' 守护进程在登录时启动 (通常通过 XDG Autostart 或 KDE Plasma 的自动启动设置)。"
            ;;
        "xfce") # 针对 XFCE 环境的详细指导
            log_info "检测到 XFCE 桌面环境。"
            log_notice "对于 XFCE, 请确保以下步骤已完成或将要完成："
            log_notice "  1. ${COLOR_YELLOW}环境变量已通过本脚本配置${COLOR_RESET} (通常写入用户家目录下的 .xprofile)。"
            log_notice "  2. ${COLOR_YELLOW}您已完全注销并重新登录 XFCE 会话${COLOR_RESET}以使这些环境变量生效。"
            log_notice "  3. '${framework}' 守护进程 (例如 ${COLOR_CYAN}${framework}${COLOR_RESET}) 需要在您登录后自动启动。"
            log_notice "     - 检查 XFCE 的 '会话和启动' (xfce4-session-settings) -> '应用程序自动启动' 标签页中是否有 '${framework}'。"
            log_notice "     - 如果没有，请手动添加一个条目。名称可设为 '${INPUT_METHOD_FRAMEWORKS[$framework]}', 命令通常为: ${COLOR_CYAN}${framework}${COLOR_RESET}"
            log_notice "     - 或者，可以检查标准的 XDG Autostart 文件是否存在，如 ${COLOR_CYAN}/etc/xdg/autostart/org.${framework}.desktop${COLOR_RESET} (文件名可能不同)。"
            log_notice "  4. 一旦 '${framework}' 守护进程运行且环境变量生效，您就可以使用其配置工具 (如 ${COLOR_CYAN}${framework}-configtool${COLOR_RESET}) 来添加和管理输入方案。"

            # 可选的、更主动的检查 (示例性，具体包名和路径可能需调整)
            if [[ "$framework" == "fcitx5" ]] && is_package_installed "fcitx5"; then
                if [ -f "/etc/xdg/autostart/org.fcitx.Fcitx5.desktop" ]; then
                    log_info "检测到 Fcitx5 的标准 XDG 自动启动文件。这通常能确保它在 XFCE 登录时启动。"
                else
                    log_warn "未找到 Fcitx5 的标准 XDG 自动启动文件。您很可能需要按上述提示手动将其添加到 XFCE 的自动启动应用程序中。"
                fi
            fi
            ;;
        *) # 其他未特别处理的桌面环境
            log_info "当前桌面环境为 '$DESKTOP_ENV'。没有特定的自动化配置步骤。"
            log_notice "请确保环境变量已按预期生效 (通常需要重新登录)。"
            log_notice "然后，请查阅您的桌面环境文档以及 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的文档，了解如何在该环境下配置和自动启动输入法。"
            ;;
    esac
    log_notice "桌面环境相关的集成指导已提供。"
    return 0 # 指导性函数，通常返回成功
}


# @description 尝试以原始用户身份启动指定输入法框架的配置工具。
# @param $1 (string) framework - 输入法框架的键名 (例如 "fcitx5", "ibus")。
# @returns (status) - 0 (命令成功发送到后台), 1 (启动失败或必要工具/用户不存在)。
# @depends command (Bash 内置), id, su (系统命令), log_* (from utils.sh)。
_start_config_tool() {
    local framework="$1" # 接收框架名称
    log_info "准备启动 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的配置工具..."

    local config_tool_cmd="" # 用于存储实际的配置工具命令
    case "$framework" in
        "fcitx5") config_tool_cmd="fcitx5-configtool" ;;
        "ibus") config_tool_cmd="ibus-setup" ;; # IBus 的配置工具可能有不同名称，如 ibus-preferences
        *)
            log_error "未知输入法框架: '$framework'。无法确定配置工具。"
            return 1
            ;;
    esac

    # 检查配置工具命令是否在 PATH 中可用
    if ! command -v "$config_tool_cmd" &>/dev/null; then
        log_error "配置工具 '$config_tool_cmd' 未找到或未安装。请确保已正确安装框架及其配置工具包。"
        return 1
    fi

    # 检查 ORIGINAL_USER 是否有效 (应已由 environment_setup.sh 设置)
    if [ -z "$ORIGINAL_USER" ] || ! id "$ORIGINAL_USER" &>/dev/null; then
        log_error "原始用户 '$ORIGINAL_USER' 未定义或无效。无法以该用户身份启动配置工具。"
        return 1
    fi

    log_notice "将尝试以用户 '$ORIGINAL_USER' 身份通过 'su -l' 启动 '$config_tool_cmd'。"
    log_warn "请确保 '$ORIGINAL_USER' 的图形会话 (X11/Wayland) 正在运行。"
    log_info "如果配置窗口未自动弹出，请检查是否有其他错误提示 (可能在系统日志中)，"
    log_info "并尝试手动从 '$ORIGINAL_USER' 的终端运行命令: ${COLOR_CYAN}$config_tool_cmd${COLOR_RESET}"

    # 构建要在 'su -l -c' 中执行的命令字符串。
    # 使用 nohup 使命令在脚本退出后继续运行，& 使其在后台执行。
    # 重定向标准输出和标准错误到 /dev/null 以避免它们干扰脚本的终端。
    local cmd_to_execute_as_user="nohup $config_tool_cmd >/dev/null 2>&1 &"

    log_debug "将通过 'su -l $ORIGINAL_USER -c \"...\"' 执行的后台命令: $cmd_to_execute_as_user"

    # 使用 'su -l <user> -c <command>' 来执行。
    # 'su -l' (或 'su -') 会为目标用户创建一个更接近完整登录的环境，
    # 这通常有助于图形程序正确获取 DISPLAY, DBUS_SESSION_BUS_ADDRESS 等变量。
    # 此 su 命令本身由当前的 root 用户执行。
    if su -l "$ORIGINAL_USER" -c "$cmd_to_execute_as_user"; then
        # 注意: 'su -l -c "command &"' 这个命令本身通常会立即返回成功 (退出码 0)，
        # 因为 'command &' 是一个后台任务。这并不保证 'command' 图形界面一定能成功显示。
        log_success "'$config_tool_cmd' 的启动命令已通过 'su -l' 成功发送到 '$ORIGINAL_USER' 的后台会话。"
        log_info "请检查您的桌面环境，看 '${INPUT_METHOD_FRAMEWORKS[$framework]}' 的配置窗口是否已弹出。"
        log_info "在配置工具中，您通常需要：1. 添加已安装的输入方案。 2. 调整顺序和快捷键。"
        return 0
    else
        local su_exit_status=$? # 获取 su 命令的退出码
        log_error "使用 'su -l $ORIGINAL_USER -c \"...\"' 尝试启动 '$config_tool_cmd' 失败 (su 命令退出码: $su_exit_status)。"
        log_error "这可能表示切换用户时遇到问题 (例如密码策略、会话限制)，或命令执行环境仍不正确。"
        log_error "请尝试手动从终端以普通用户 '$ORIGINAL_USER' 身份运行 '$config_tool_cmd' 进行配置。"
        return 1
    fi
}


# @description 检查并提示安装推荐的字体包。
# @returns (status) - 0 (完成，无论是否安装)。目前不因字体安装失败而返回错误。
# @depends _is_font_installed (本脚本辅助函数), install_packages (from package_management_utils.sh),
#           _confirm_action (from utils.sh)。
_install_required_fonts() {
    log_info "检查并安装推荐的字体..."
    local packages_to_install=() # 用于收集需要安装的字体包名

    # 检查通用的 Noto CJK 字体 (支持中文、日文、韩文显示)
    if ! _is_font_installed "Noto Sans CJK"; then # 尝试匹配字体族名
        log_notice "未检测到 Noto CJK 字体，建议安装以获得良好的中日韩字符显示。"
        packages_to_install+=(noto-fonts-cjk) # Arch Linux 中的包名
    fi
    # 检查 Noto Color Emoji 字体 (支持彩色表情符号)
    if ! _is_font_installed "Noto Color Emoji"; then
        log_notice "未检测到 Noto Color Emoji 字体，建议安装以支持彩色表情符号显示。"
        packages_to_install+=(noto-fonts-emoji)
    fi
    # 检查基础的 Noto Sans 字体 (通用西文字体，其他 Noto 字体的基础)
    if ! _is_font_installed "Noto Sans"; then
        packages_to_install+=(noto-fonts)
    fi
    
    # 示例：可以根据 SELECTED_SCHEMES 添加更具体的字体推荐
    # for scheme in "${SELECTED_SCHEMES[@]}"; do
    #     if [[ "$scheme" == *"rime"* ]]; then
    #         if ! _is_font_installed "WenQuanYi Zen Hei"; then packages_to_install+=(wqy-zenhei); fi
    #     fi
    # done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "以下推荐字体包建议安装以获得更好的显示效果: ${COLOR_CYAN}${packages_to_install[*]}${COLOR_RESET}"
        if _confirm_action "是否安装这些推荐的字体包?" "y"; then
            # 调用通用的包安装函数
            if install_packages "${packages_to_install[@]}"; then # 将数组展开为参数列表
                log_success "推荐字体包安装成功。"
            else
                log_error "部分或全部推荐字体包安装失败。请检查错误信息。"
                # 字体安装失败通常不应阻止输入法核心功能的配置，所以这里不返回错误。
            fi
        else
            log_info "跳过安装推荐字体包。"
        fi
    else
        log_info "未发现需要立即安装的缺失核心字体，或者所有推荐字体已安装/用户已跳过。"
    fi

    log_success "字体检查与推荐安装流程完成。"
    return 0 # 字体检查/安装通常不作为关键路径的失败点
}

# ==============================================================================
# 主流程函数 (由本脚本的 main() 函数中的菜单选项调用)
# 这些函数构成了用户通过菜单与之交互的核心功能。
# ==============================================================================

# @description 引导用户选择并安装一个输入法框架 (Fcitx5 或 IBus)。
#              处理框架的安装、重装以及更换框架时的已选方案清理。
# @returns (status) - 0 (成功或用户取消), 1 (安装失败或严重错误)。
_install_im_framework() {
    display_header_section "选择要安装的输入法框架" "box" 80 # 显示美化的标题
    local available_frameworks_for_selection=() # 临时数组，用于映射用户的数字选择
    # 调用内部显示函数，它会填充 available_frameworks_for_selection
    _display_framework_options_list available_frameworks_for_selection INPUT_METHOD_FRAMEWORKS

    local selection
    read -rp "$(echo -e "${COLOR_YELLOW}请选择框架 [1-$((${#available_frameworks_for_selection[@]}))], 0 取消: ${COLOR_RESET}")" selection

    if [[ "$selection" == "0" ]]; then log_info "操作已取消。"; return 0; fi # 用户选择退出
    # 验证用户输入是否为有效数字且在选项范围内
    if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_frameworks_for_selection[@]} )); then
        log_error "无效的选择: '$selection'。"; return 1; # 输入错误，返回失败
    fi

    # 将用户的数字选择转换为实际的框架键名
    local chosen_framework_key="${available_frameworks_for_selection[$((selection - 1))]}" # 数组索引从0开始

    # 如果用户更改了之前已选的框架，并且之前已选了一些输入方案，则提示用户确认是否清空这些方案
    if [[ -n "$SELECTED_FRAMEWORK" && "$SELECTED_FRAMEWORK" != "$chosen_framework_key" && ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
        log_warn "您正在从 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 切换到 '${INPUT_METHOD_FRAMEWORKS[$chosen_framework_key]}'."
        if _confirm_action "更改输入法框架将清空先前为旧框架选择的 ${#SELECTED_SCHEMES[@]} 个输入方案。是否继续?" "y" "${COLOR_RED}"; then
            log_info "已清空之前为旧框架选择的输入方案。"
            SELECTED_SCHEMES=() # 清空已选方案数组
        else
            log_info "框架更改已取消，保留原框架 '$SELECTED_FRAMEWORK' 和已选方案。"
            return 0 # 用户取消更改，返回成功（未执行破坏性操作）
        fi
    fi
    SELECTED_FRAMEWORK="$chosen_framework_key" # 更新全局选中的框架
    log_info "您选择了输入法框架: ${COLOR_CYAN}${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}${COLOR_RESET}"

    # 检查所选框架是否已安装
    if _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
        # 如果已安装，询问用户是否要重新安装
        if ! _confirm_action "'${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已安装。是否要重新安装此框架 (这不会卸载已安装的输入方案)?" "n" "${COLOR_YELLOW}"; then
            log_info "保留已安装的框架。如果需要配置，请从主菜单选择相应选项。"
            return 0 # 用户选择不重装，视为此步骤成功完成
        fi
        log_info "用户选择重新安装框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}'."
    fi

    # 获取框架的依赖包列表
    local dependencies="${FRAMEWORK_DEPENDENCIES[$SELECTED_FRAMEWORK]}"
    log_info "将安装框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 及其核心依赖包: ${COLOR_CYAN}$dependencies${COLOR_RESET}"
    # 调用通用的包安装函数 (来自 package_management_utils.sh)
    if install_packages "$dependencies"; then # install_packages 接受空格分隔的字符串或数组参数
        log_success "输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装成功。"
        return 0
    else
        log_error "输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 安装失败。"
        # SELECTED_FRAMEWORK="" # 考虑在安装失败时是否要重置 SELECTED_FRAMEWORK
        return 1 # 安装失败，返回错误
    fi
}

# @description 引导用户为当前选定的输入法框架选择并安装输入方案。
#              支持多选，再次选择已选方案则取消选择。
# @returns (status) - 0 (成功或用户取消), 1 (安装失败或严重错误)。
_install_input_schemes() {
    # 检查是否已选定一个输入法框架
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。"
        _prompt_return_to_continue "按 Enter 返回主菜单选择框架，或在此引导您选择一个..."
        if ! _install_im_framework; then # 尝试让用户选择框架
             # 如果 _install_im_framework 返回非0 (错误或用户在选择框架时取消)
            log_error "框架选择失败或被取消，无法继续安装输入方案。"
            return 1 
        fi
        # 再次检查，如果用户在 _install_im_framework 中取消且未选定框架
        if [[ -z "$SELECTED_FRAMEWORK" ]]; then
            log_info "未选定输入法框架，已取消安装输入方案。"
            return 0 # 用户流程，非错误
        fi
    fi

    # 进入输入方案选择循环
    while true; do
        clear # 每次循环开始时清屏，以刷新选项列表
        display_header_section "选择输入方案 (用于 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]})" "box" 80
        
        # 显示当前已选中的方案列表
        echo -e "${COLOR_CYAN}当前已选方案 (${#SELECTED_SCHEMES[@]} 个):${COLOR_RESET}"
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
            local display_idx=1
            for sel_scheme_key in "${SELECTED_SCHEMES[@]}"; do
                # 防御性检查，确保键名有效
                if [[ -n "${INPUT_SCHEMES[$sel_scheme_key]}" ]]; then
                    echo -e "  ${COLOR_YELLOW}${display_idx})${COLOR_RESET} ${INPUT_SCHEMES[$sel_scheme_key]}"
                    ((display_idx++))
                fi
            done
        else
            echo -e "  (无)"
        fi
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        echo -e "${COLOR_CYAN}请从以下列表选择要添加/移除的方案 (再次选择已选项可取消):${COLOR_RESET}"

        local available_schemes_for_selection=() # 临时数组，用于映射用户的数字选择
        # 调用内部显示函数，它会根据当前框架过滤并显示方案，同时填充 available_schemes_for_selection
        _display_scheme_options_list available_schemes_for_selection INPUT_SCHEMES "$SELECTED_FRAMEWORK" SELECTED_SCHEMES

        local selection
        read -rp "$(echo -e "${COLOR_YELLOW}输入方案序号 [1-$((${#available_schemes_for_selection[@]}))], 0 完成: ${COLOR_RESET}")" selection

        if [[ "$selection" == "0" ]]; then
            log_info "输入方案选择完成。"
            break # 用户选择完成，跳出循环
        fi

        # 验证用户输入
        if ! [[ "$selection" =~ ^[1-9][0-9]*$ ]] || (( selection < 1 || selection > ${#available_schemes_for_selection[@]} )); then
            log_warn "无效选择: '$selection'。请输入列表中的有效数字或 0。"
            _prompt_return_to_continue
            continue # 无效输入，继续下一次循环
        fi

        # 将用户的数字选择转换为实际的输入方案键名 (包名)
        local actual_scheme_key="${available_schemes_for_selection[$((selection - 1))]}"

        # 检查该方案是否已被选中，并进行添加或移除操作
        local already_selected_index=-1
        for i in "${!SELECTED_SCHEMES[@]}"; do # 遍历 SELECTED_SCHEMES 数组的索引
            if [[ "${SELECTED_SCHEMES[$i]}" == "$actual_scheme_key" ]]; then
                already_selected_index=$i # 记录已选方案在数组中的索引
                break
            fi
        done

        if (( already_selected_index != -1 )); then
            # 如果方案已选中 (索引有效)，则从 SELECTED_SCHEMES 数组中移除它
            unset "SELECTED_SCHEMES[$already_selected_index]"
            # 重要: unset 会在数组中留下空洞，需要重建数组以压缩它
            SELECTED_SCHEMES=("${SELECTED_SCHEMES[@]}") 
            log_success "已取消选择: ${INPUT_SCHEMES[$actual_scheme_key]}"
        else
            # 如果方案未选中，则将其添加到 SELECTED_SCHEMES 数组
            SELECTED_SCHEMES+=("$actual_scheme_key")
            log_success "已选择: ${INPUT_SCHEMES[$actual_scheme_key]}"
        fi
        _prompt_return_to_continue "按 Enter 继续选择或完成..." # 给用户时间查看操作结果
    done # 结束方案选择循环

    # 检查是否有选中的方案需要安装
    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then
        log_info "未选择任何输入方案，跳过安装步骤。"
        return 0 # 用户未选方案，非错误
    fi

    # 显示最终选定的方案列表
    log_info "最终选定的输入方案 (${#SELECTED_SCHEMES[@]} 个):"
    for final_scheme_key in "${SELECTED_SCHEMES[@]}"; do
        log_info "  - ${INPUT_SCHEMES[$final_scheme_key]}"
    done

    # 再次向用户确认是否安装这些选定的方案
    if ! _confirm_action "确认安装/检查这 ${#SELECTED_SCHEMES[@]} 个输入方案吗?" "y"; then
        log_info "输入方案安装已取消。"
        return 0 # 用户取消安装
    fi

    # 过滤掉那些已经安装的方案，只安装新的
    local schemes_to_actually_install=()
    for scheme_to_check_key in "${SELECTED_SCHEMES[@]}"; do
        # 假设输入方案的键名 (scheme_to_check_key) 就是其包名
        if ! _is_input_scheme_installed "$scheme_to_check_key"; then
            schemes_to_actually_install+=("$scheme_to_check_key")
        else
            log_info "输入方案 '${INPUT_SCHEMES[$scheme_to_check_key]}' (包: $scheme_to_check_key) 已安装，将跳过。"
        fi
    done

    if [[ ${#schemes_to_actually_install[@]} -eq 0 ]]; then
        log_success "所有选定的输入方案均已安装，无需额外安装操作。"
        return 0 # 所有已选方案都已安装
    fi

    # 执行实际的安装操作
    log_info "将实际安装以下 ${#schemes_to_actually_install[@]} 个新的输入方案: ${COLOR_CYAN}${schemes_to_actually_install[*]}${COLOR_RESET}"
    # install_packages 接受一个包含所有包名的数组参数
    if install_packages "${schemes_to_actually_install[@]}"; then 
        log_success "选定的新输入方案安装成功。"
        return 0
    else
        log_error "部分或全部新输入方案安装失败。请检查之前的错误日志。"
        return 1 # 安装失败
    fi
}


# @description 菜单选项：调用实际的环境变量配置函数。
# @returns (status) - 同 _configure_im_environment 的返回值，或用户取消时返回0。
_configure_im_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。请先从主菜单选择 '1. 选择/安装输入法框架'。"
        _prompt_return_to_continue
        return 1 # 未选框架，操作无法进行
    fi

    display_header_section "配置输入法环境" "box" 80
    log_info "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 配置系统环境变量。"
    log_warn "这将修改用户家目录下的 '${IM_CONFIG_FILE}' 和 '${IM_ENV_FILE}' 文件。"
    log_warn "强烈建议您在继续之前了解这些更改的影响。"

    if _confirm_action "确认继续配置环境变量吗?" "y" "${COLOR_YELLOW}"; then
        # 调用核心配置函数，并将其返回值作为本函数的返回值
        _configure_im_environment "$SELECTED_FRAMEWORK"; return $?
    else
        log_info "环境变量配置操作已取消。"
        return 0 # 用户取消，非错误
    fi
}

# @description 菜单选项：调用实际的桌面环境集成指导函数。
# @returns (status) - 同 _configure_for_desktop_environment 的返回值，或用户取消时返回0。
_configure_for_desktop_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。"; _prompt_return_to_continue; return 1;
    fi
    display_header_section "配置桌面环境集成" "box" 80
    log_info "将为 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 提供桌面环境 '$DESKTOP_ENV' 的集成建议/操作。"
    if _confirm_action "确认继续进行桌面环境集成配置/建议吗?" "y"; then
        _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; return $?
    else
        log_info "桌面环境集成配置操作已取消。"; return 0;
    fi
}

# @description 菜单选项：调用实际的启动配置工具函数。
# @returns (status) - 同 _start_config_tool 的返回值，或用户取消时返回0。
_start_config_tool_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "尚未选择输入法框架。"; _prompt_return_to_continue; return 1;
    fi
    # 额外检查框架是否已安装，因为配置工具通常依赖已安装的框架
    if ! _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
        log_error "输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 尚未安装或核心包缺失。"
        log_error "请先确保框架已成功安装，再尝试启动其配置工具。"
        _prompt_return_to_continue
        return 1
    fi

    display_header_section "启动输入法配置工具" "box" 80
    log_info "将尝试启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的图形化配置工具。"
    if _confirm_action "确认启动配置工具吗?" "y"; then
        _start_config_tool "$SELECTED_FRAMEWORK"; return $?
    else
        log_info "启动配置工具操作已取消。"; return 0;
    fi
}

# @description 执行完整的输入法安装与配置流程。
#              按顺序调用框架安装、方案安装、环境变量配置、桌面集成指导、字体安装等步骤。
# @returns (status) - 0 (流程成功完成或用户中途取消), 1 (流程中关键步骤失败)。
_run_full_installation() {
    display_header_section "完整输入法安装与配置流程" "box" 80

    # 显示流程概述
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
        return 0 # 用户取消，非错误
    fi

    # --- 步骤 1: 安装输入法框架 ---
    log_info "${COLOR_BOLD}--- 步骤 1/6: 安装输入法框架 ---${COLOR_RESET}"
    if ! _install_im_framework; then
        log_error "步骤 1 (安装输入法框架) 失败或被用户取消。完整流程中止。"
        return 1 # 关键步骤失败
    fi
    # 再次确认框架已选定 (防御性编程)
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_error "步骤 1 后，未成功选定输入法框架。完整流程中止。"
        return 1
    fi
    log_success "步骤 1: 输入法框架 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已成功选择/安装。"
    _prompt_return_to_continue

    # --- 步骤 2: 安装输入方案 ---
    log_info "${COLOR_BOLD}--- 步骤 2/6: 安装输入方案 ---${COLOR_RESET}"
    if ! _install_input_schemes; then
        log_error "步骤 2 (安装输入方案) 失败或被用户取消。完整流程中止。"
        return 1 # 关键步骤失败
    fi
    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then
        log_warn "步骤 2: 未选择任何输入方案。您可以稍后通过配置工具单独添加。"
    else
        log_success "步骤 2: 输入方案已成功选择/安装。"
    fi
    _prompt_return_to_continue

    # --- 步骤 3: 配置输入法环境 ---
    log_info "${COLOR_BOLD}--- 步骤 3/6: 配置输入法环境变量 ---${COLOR_RESET}"
    # 直接调用核心配置函数，不通过菜单封装函数以避免重复确认
    if ! _configure_im_environment "$SELECTED_FRAMEWORK"; then
        log_error "步骤 3 (配置输入法环境变量) 失败。完整流程中止。"
        return 1 # 环境变量配置是关键步骤
    fi
    log_success "步骤 3: 输入法环境变量已成功配置。"
    _prompt_return_to_continue

    # --- 步骤 4: 配置桌面环境集成 ---
    log_info "${COLOR_BOLD}--- 步骤 4/6: 桌面环境集成指导 ---${COLOR_RESET}"
    if ! _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then
        # 此步骤更多是指导性的，即使返回非0 (理论上不会)，也不一定中止主流程
        log_warn "步骤 4 (桌面环境集成指导) 提供期间可能存在问题，但流程将继续。"
    else
        log_success "步骤 4: 桌面环境集成指导已提供。"
    fi
    _prompt_return_to_continue

    # --- 步骤 5: 安装必要的字体 ---
    log_info "${COLOR_BOLD}--- 步骤 5/6: 检查/安装推荐字体 ---${COLOR_RESET}"
    if ! _install_required_fonts; then
        log_warn "步骤 5 (检查或安装字体) 期间可能存在问题，但流程将继续。"
    else
        log_success "步骤 5: 字体检查与推荐安装已完成。"
    fi
    _prompt_return_to_continue

    # --- 最终总结信息 ---
    clear # 清屏以显示最终总结
    display_header_section "输入法完整安装流程已完成" "box" 80 "${COLOR_GREEN}"
    log_summary "祝贺您！输入法 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 已基本配置完成。" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "已选框架: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"
    if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
        log_summary "已安装/选定的输入方案:"
        for scheme_key_summary in "${SELECTED_SCHEMES[@]}"; do # 使用不同变量名避免冲突
            log_summary "  - ${INPUT_SCHEMES[$scheme_key_summary]}"
        done
    else
        log_summary "未选择特定的输入方案 (可稍后通过配置工具添加)。"
    fi
    log_summary "环境变量已配置到: '${IM_CONFIG_FILE}' 和 (可能) '${IM_ENV_FILE}'"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "${COLOR_BOLD}重要后续步骤:${COLOR_RESET}"
    log_summary "1. ${COLOR_YELLOW}完全注销并重新登录您的用户会话${COLOR_RESET} (或重启计算机) 以使所有更改生效。"
    log_summary "2. 登录后，您可能需要通过 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的配置工具 (例如 ${COLOR_CYAN}${SELECTED_FRAMEWORK}-configtool${COLOR_RESET}) 来:"
    log_summary "   - 确认您安装的输入方案已启用。"
    log_summary "   - 调整输入方案的顺序。"
    log_summary "   - 设置您偏好的输入法切换快捷键 (通常默认为 Ctrl+Space 或 Super+Space)。"
    log_summary "3. 如果遇到问题，请检查本脚本的日志文件 (${COLOR_CYAN}${CURRENT_SCRIPT_LOG_FILE}${COLOR_RESET}) 以及 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的相关文档。"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"

    # --- 步骤 6: (可选) 启动输入法配置工具 ---
    log_info "${COLOR_BOLD}--- 步骤 6/6 (可选): 启动输入法配置工具 ---${COLOR_RESET}"
    if _confirm_action "是否立即启动 '${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}' 的配置工具?" "y" "${COLOR_YELLOW}"; then
        if ! _start_config_tool "$SELECTED_FRAMEWORK"; then
            log_warn "启动配置工具失败。请在重新登录后手动尝试运行它。"
        fi
    else
        log_info "您可以稍后从主菜单或手动启动配置工具。"
    fi

    log_success "输入法完整安装与配置流程结束。"
    return 0 # 完整流程成功结束
}

# ==============================================================================
# 主函数 (脚本的菜单入口点)
# ==============================================================================
# @description 主函数，负责显示输入法配置的主菜单并处理用户选择。
main() {
    # 用于标记是否已在首次进入菜单时检查过系统中已安装的输入法框架
    local initial_framework_check_done=false
    local current_installed_framework="" # 用于存储首次检测到的已安装框架

    # 主菜单循环
    while true; do
        clear # 每次循环开始时清屏
        display_header_section "Arch Linux 输入法安装与配置" "box" 80

        # 动态显示当前选定/已安装的框架信息
        if [[ -n "$SELECTED_FRAMEWORK" ]]; then # 如果已有选中的框架
            log_info "当前操作的输入法框架: ${COLOR_CYAN}${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}${COLOR_RESET} ($(_is_im_framework_installed "$SELECTED_FRAMEWORK" && echo "${COLOR_GREEN}已安装" || echo "${COLOR_RED}未安装")${COLOR_RESET})"
        elif ! "$initial_framework_check_done"; then # 如果是首次进入菜单且未检查过
            # 检测系统中是否已安装了任何受支持的输入法框架
            for fw_key_check in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
                if _is_im_framework_installed "$fw_key_check"; then
                    current_installed_framework="$fw_key_check" # 记录找到的框架
                    log_notice "检测到系统中已安装输入法框架: ${COLOR_GREEN}${INPUT_METHOD_FRAMEWORKS[$fw_key_check]}${COLOR_RESET}"
                    # 询问用户是否基于此已安装的框架进行后续操作
                    if _confirm_action "是否基于此已安装的框架进行后续操作?" "y" "${COLOR_YELLOW}"; then
                        SELECTED_FRAMEWORK="$current_installed_framework" # 将其设为当前选定框架
                        # 可以在此考虑加载此框架已安装的输入方案到 SELECTED_SCHEMES (这是一个复杂的功能，暂未实现)
                    fi
                    break # 找到一个后即停止检测
                fi
            done
            # 如果未检测到任何已安装框架，且用户也未选择过
            if [[ -z "$current_installed_framework" && -z "$SELECTED_FRAMEWORK" ]]; then
                log_warn "未检测到系统中安装任何受支持的输入法框架。"
            fi
            initial_framework_check_done=true # 标记已完成首次检查
        fi
        # 显示当前已选中的输入方案列表
        if [[ ${#SELECTED_SCHEMES[@]} -gt 0 ]]; then
             log_info "当前已选的输入方案 (${#SELECTED_SCHEMES[@]} 个):"
             for sch_key_display in "${SELECTED_SCHEMES[@]}"; do # 使用不同变量名
                echo -e "  - ${INPUT_SCHEMES[$sch_key_display]}"
             done
        fi
        echo # 输出一个空行美化界面

        # 主菜单选项定义
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 选择/安装输入法框架 (当前: ${COLOR_CYAN}${SELECTED_FRAMEWORK:-未选}${COLOR_RESET})"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 选择/安装输入方案 (需先选框架)"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 配置输入法环境变量 (需先选框架)"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} 桌面环境集成指导 (需先选框架)"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} 启动输入法配置工具 (需先选框架并安装)"
        echo -e "  ${COLOR_GREEN}6.${COLOR_RESET} 检查/安装推荐字体"
        echo -e "  ${COLOR_GREEN}7.${COLOR_RESET} ${COLOR_BOLD}完整安装与配置流程 (推荐新用户)${COLOR_RESET}"
        echo "" # 空行
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成并返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"

        local choice # 用户输入的选择
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [0-7]: ${COLOR_RESET}")" choice
        echo # 输出一个换行符

        local operation_status=0 # 用于记录被调用函数的操作状态
        case "$choice" in
            1) _install_im_framework; operation_status=$? ;;
            2) _install_input_schemes; operation_status=$? ;;
            3) _configure_im_environment_menu; operation_status=$? ;;
            4) _configure_for_desktop_environment_menu; operation_status=$? ;;
            5) _start_config_tool_menu; operation_status=$? ;;
            6) _install_required_fonts; operation_status=$? ;; # 字体安装通常不视为关键失败
            7) _run_full_installation; operation_status=$? ;;
            0) # 用户选择退出
                log_info "输入法配置模块已退出。"
                # 如果用户进行过配置，提示他们注销
                if [[ -n "$SELECTED_FRAMEWORK" ]]; then 
                    log_warn "如果您进行了任何安装或配置更改，请记得注销并重新登录以使更改生效！"
                fi
                break # 跳出主菜单循环
                ;;
            *) # 无效输入
                log_warn "无效选择: '$choice'。请重新输入。"
                operation_status=99 # 特殊状态码，表示无效用户输入
                ;;
        esac

        # 如果用户不是选择退出，则在操作后提示返回主菜单
        if [[ "$choice" != "0" ]]; then
            # 如果操作状态不是0 (成功) 且不是99 (无效输入)
            if (( operation_status != 0 && operation_status != 99 )); then
                log_error "之前的操作未成功完成或被用户取消 (返回状态: $operation_status)。"
            fi
            _prompt_return_to_continue # 等待用户按 Enter 返回菜单
        fi
    done
}

# --- 脚本入口 ---
# 调用主函数，并将所有命令行参数传递给它 (虽然此脚本目前不处理命令行参数)
main "$@"
# 脚本正常退出，返回状态码 0
exit 0