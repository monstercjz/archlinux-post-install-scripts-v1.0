#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_system_tools/01_input_method.sh
# 版本: 1.0.0
# 日期: 2025-06-13
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
DESKTOP_ENV=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')

# 可用的输入法框架和输入方案
declare -A INPUT_METHOD_FRAMEWORKS=(
    ["fcitx5"]="Fcitx5 (推荐现代 Linux 系统)"
    ["ibus"]="IBus (经典输入法框架)"
)

declare -A INPUT_SCHEMES=(
    # 拼音输入法
    ["fcitx5-chinese-addons"]="Fcitx5 中文输入方案集合"
    ["fcitx5-pinyin-zhwiki"]="Fcitx5 中文维基百科词库"
    ["ibus-pinyin"]="IBus 拼音输入法"
    ["ibus-sunpinyin"]="IBus 智能拼音输入法"
    
    # 五笔输入法
    ["fcitx5-wubi"]="Fcitx5 五笔输入法"
    ["ibus-table-wubi"]="IBus 五笔输入法"
    
    # 日文输入法
    ["fcitx5-mozc"]="Fcitx5 Mozc (日文)"
    ["ibus-anthy"]="IBus Anthy (日文)"
    
    # 韩文输入法
    ["fcitx5-hangul"]="Fcitx5 Hangul (韩文)"
    ["ibus-hangul"]="IBus Hangul (韩文)"
    
    # 表情符号
    ["fcitx5-emoji"]="Fcitx5 表情符号支持"
    
    # 其他语言
    ["fcitx5-unikey"]="Fcitx5 Unikey (越南语)"
)

# 输入法框架依赖的包
declare -A FRAMEWORK_DEPENDENCIES=(
    ["fcitx5"]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool"
    ["ibus"]="ibus ibus-gtk ibus-gtk3 ibus-qt5"
)

# 桌面环境特定配置
declare -A DESKTOP_ENV_CONFIGS=(
    ["gnome"]="im-config"
    ["kde"]="im-config"
    ["xfce"]="im-config"
    ["deepin"]="im-config"
    ["mate"]="im-config"
    ["lxde"]="im-config"
)

# 选中的输入法框架和输入方案
SELECTED_FRAMEWORK=""
SELECTED_SCHEMES=()

# ==============================================================================
# 辅助函数
# ==============================================================================

# 检测当前是否安装了特定输入法框架
_is_im_framework_installed() {
    local framework="$1"
    case "$framework" in
        "fcitx5")
            is_package_installed "fcitx5"
            ;;
        "ibus")
            is_package_installed "ibus"
            ;;
        *)
            return 1
            ;;
    esac
}

# 检测当前是否安装了特定输入方案
_is_input_scheme_installed() {
    local scheme="$1"
    is_package_installed "$scheme"
}

# 显示可用的输入法框架列表
_display_framework_options() {
    display_header_section "可用的输入法框架" "default" 80
    local count=1
    for framework in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
        local status=""
        if _is_im_framework_installed "$framework"; then
            status="(${COLOR_GREEN}已安装${COLOR_RESET})"
        else
            status="(${COLOR_RED}未安装${COLOR_RESET})"
        fi
        echo -e "  ${COLOR_GREEN}${count}.${COLOR_RESET} ${INPUT_METHOD_FRAMEWORKS[$framework]} $status"
        ((count++))
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消并返回"
}

# 显示可用的输入方案列表
_display_scheme_options() {
    display_header_section "可用的输入方案 (选择与 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]} 兼容的方案)" "default" 80
    
    local count=1
    for scheme in "${!INPUT_SCHEMES[@]}"; do
        # 过滤出与所选框架兼容的方案
        if [[ "$scheme" == "$SELECTED_FRAMEWORK"* ]]; then
            local status=""
            if _is_input_scheme_installed "$scheme"; then
                status="(${COLOR_GREEN}已安装${COLOR_RESET})"
            else
                status="(${COLOR_RED}未安装${COLOR_RESET})"
            fi
            
            # 检查是否已被选中
            local selected=""
            for s in "${SELECTED_SCHEMES[@]}"; do
                if [[ "$s" == "$scheme" ]]; then
                    selected="${COLOR_YELLOW}[已选]${COLOR_RESET} "
                    break
                fi
            done
            
            echo -e "  ${COLOR_GREEN}${count}.${COLOR_RESET} ${selected}${INPUT_SCHEMES[$scheme]} $status"
            ((count++))
            scheme_options[$count]="$scheme"  # 保存选项映射
        fi
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成选择"
}

# 配置输入法环境变量
_configure_im_environment() {
    local framework="$1"
    
    log_info "配置输入法环境变量..."
    
    # 创建备份
    create_backup_and_cleanup "$IM_CONFIG_FILE" "im_config"
    create_backup_and_cleanup "$IM_ENV_FILE" "im_env"
    
    # 根据框架类型设置不同的环境变量
    case "$framework" in
        "fcitx5")
            # 配置 XDG 环境变量
            cat > "$IM_CONFIG_FILE" << EOF
# Fcitx5 输入法配置
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export INPUT_METHOD=fcitx
export SDL_IM_MODULE=fcitx
EOF
            
            # 配置 PAM 环境变量
            cat > "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
INPUT_METHOD DEFAULT=fcitx
SDL_IM_MODULE DEFAULT=fcitx
EOF
            
            log_success "Fcitx5 环境变量配置完成"
            ;;
            
        "ibus")
            # 配置 XDG 环境变量
            cat > "$IM_CONFIG_FILE" << EOF
# IBus 输入法配置
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF
            
            # 配置 PAM 环境变量
            cat > "$IM_ENV_FILE" << EOF
GTK_IM_MODULE DEFAULT=ibus
QT_IM_MODULE DEFAULT=ibus
XMODIFIERS DEFAULT=@im=ibus
EOF
            
            log_success "IBus 环境变量配置完成"
            ;;
            
        *)
            log_error "未知的输入法框架: $framework"
            return 1
            ;;
    esac
    
    # 设置文件权限
    chown "$ORIGINAL_USER:$ORIGINAL_USER" "$IM_CONFIG_FILE" "$IM_ENV_FILE"
    chmod 644 "$IM_CONFIG_FILE" "$IM_ENV_FILE"
    
    log_notice "环境变量已配置。更改将在下次登录后生效。"
}

# 为特定桌面环境配置输入法
_configure_for_desktop_environment() {
    local framework="$1"
    
    log_info "为桌面环境配置输入法..."
    
    # 对于大多数桌面环境，我们只需要设置环境变量
    # 但有些桌面环境可能需要额外配置
    
    case "$DESKTOP_ENV" in
        "gnome")
            log_info "检测到 GNOME 桌面环境，正在配置..."
            
            # 对于 GNOME，我们可以使用 gsettings 命令
            if run_as_user "type -t gsettings >/dev/null 2>&1"; then
                if [[ "$framework" == "fcitx5" ]]; then
                    run_as_user "gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us'), ('ibus', 'pinyin')]\""
                    log_success "GNOME 输入法源已配置"
                elif [[ "$framework" == "ibus" ]]; then
                    run_as_user "gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us'), ('ibus', 'pinyin')]\""
                    log_success "GNOME 输入法源已配置"
                fi
            else
                log_warn "gsettings 命令不可用，无法配置 GNOME 输入法源"
                log_notice "请手动配置 GNOME 输入法源"
            fi
            ;;
            
        "kde")
            log_info "检测到 KDE 桌面环境，正在配置..."
            
            # 对于 KDE，我们可以使用 kwriteconfig5 命令
            if run_as_user "type -t kwriteconfig5 >/dev/null 2>&1"; then
                if [[ "$framework" == "fcitx5" ]]; then
                    run_as_user "kwriteconfig5 --file kdeglobals --group 'Locale' --key 'InputMethod' 'fcitx5'"
                    log_success "KDE 输入法已配置"
                elif [[ "$framework" == "ibus" ]]; then
                    run_as_user "kwriteconfig5 --file kdeglobals --group 'Locale' --key 'InputMethod' 'ibus'"
                    log_success "KDE 输入法已配置"
                fi
            else
                log_warn "kwriteconfig5 命令不可用，无法配置 KDE 输入法"
                log_notice "请手动配置 KDE 输入法"
            fi
            ;;
            
        *)
            log_info "检测到桌面环境: $DESKTOP_ENV，使用默认配置"
            ;;
    esac
    
    log_notice "桌面环境配置完成。部分更改可能需要重启桌面环境才能生效。"
}

# 启动输入法配置工具
_start_config_tool() {
    local framework="$1"
    
    log_info "启动输入法配置工具..."
    
    case "$framework" in
        "fcitx5")
            log_notice "将启动 Fcitx5 配置工具。请添加您需要的输入方案。"
            run_as_user "fcitx5-configtool &"
            ;;
            
        "ibus")
            log_notice "将启动 IBus 配置工具。请添加您需要的输入方案。"
            run_as_user "ibus-setup &"
            ;;
            
        *)
            log_error "未知的输入法框架: $framework"
            return 1
            ;;
    esac
    
    log_notice "输入法配置工具已启动。请根据您的需求进行配置。"
}

# 检查并安装必要的字体
_install_required_fonts() {
    log_info "检查并安装必要的字体..."
    
    # 检查中文字体
    if ! _is_font_installed "noto"; then
        log_notice "未检测到 Noto 字体，将安装中文字体支持..."
        install_packages noto-fonts noto-fonts-cjk noto-fonts-emoji
    fi
    
    # 检查其他语言字体
    # 这里可以根据选择的输入方案添加更多字体检查
    
    log_success "必要的字体已检查并安装"
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Arch Linux 输入法安装与配置" "box" 80
    
    # 检查是否已安装输入法框架
    local has_framework=false
    for framework in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
        if _is_im_framework_installed "$framework"; then
            has_framework=true
            break
        fi
    done
    
    if $has_framework; then
        log_notice "检测到系统中已安装输入法框架。"
    else
        log_warn "未检测到系统中安装任何输入法框架。"
    fi
    
    # 主菜单循环
    while true; do
        display_header_section "输入法配置主菜单" "default" 80 "${COLOR_PURPLE}"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 安装输入法框架"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 安装输入方案"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 配置输入法环境"
        echo -e "  ${COLOR_GREEN}4.${COLOR_RESET} 配置桌面环境集成"
        echo -e "  ${COLOR_GREEN}5.${COLOR_RESET} 启动输入法配置工具"
        echo -e "  ${COLOR_GREEN}6.${COLOR_RESET} 安装必要的字体"
        echo -e "  ${COLOR_GREEN}7.${COLOR_RESET} 完整安装流程 (推荐)"
        echo ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 完成并返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
        
        local choice
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [1-7, 0]: ${COLOR_RESET}")" choice
        echo
        
        case "$choice" in
            1)
                _install_im_framework
                ;;
            2)
                _install_input_schemes
                ;;
            3)
                _configure_im_environment_menu
                ;;
            4)
                _configure_for_desktop_environment_menu
                ;;
            5)
                _start_config_tool_menu
                ;;
            6)
                _install_required_fonts
                ;;
            7)
                _run_full_installation
                ;;
            0)
                log_info "输入法配置结束。"
                break
                ;;
            *)
                log_warn "无效选择: '$choice'。请重新输入。"
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 键返回输入法配置主菜单...${COLOR_RESET}")"
        fi
    done
}

# 安装输入法框架
_install_im_framework() {
    display_header_section "选择要安装的输入法框架" "box" 80
    
    # 显示可用的输入法框架
    _display_framework_options
    
    local selection
    read -rp "$(echo -e "${COLOR_YELLOW}请选择输入法框架 [1-$((${#INPUT_METHOD_FRAMEWORKS[@]}))]: ${COLOR_RESET}")" selection
    
    # 转换选择为框架名称
    local count=1
    for framework in "${!INPUT_METHOD_FRAMEWORKS[@]}"; do
        if [[ "$selection" == "$count" ]]; then
            SELECTED_FRAMEWORK="$framework"
            break
        fi
        ((count++))
    done
    
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        if [[ "$selection" == "0" ]]; then
            log_info "操作已取消"
            return 0
        else
            log_error "无效的选择: $selection"
            return 1
        fi
    fi
    
    log_info "您选择了: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"
    
    if _is_im_framework_installed "$SELECTED_FRAMEWORK"; then
        log_warn "所选输入法框架已安装"
        if ! _confirm_action "是否重新安装？" "n" "${COLOR_RED}"; then
            log_info "操作已取消"
            return 0
        fi
    fi
    
    # 安装依赖包
    local dependencies="${FRAMEWORK_DEPENDENCIES[$SELECTED_FRAMEWORK]}"
    log_info "将安装以下依赖包: $dependencies"
    
    if install_packages $dependencies; then
        log_success "输入法框架 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]} 安装成功"
        return 0
    else
        log_error "输入法框架安装失败"
        return 1
    fi
}

# 安装输入方案
_install_input_schemes() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "请先选择输入法框架"
        if ! _install_im_framework; then
            return 1
        fi
    fi
    
    display_header_section "选择要安装的输入方案" "box" 80
    
    # 清空已选方案
    SELECTED_SCHEMES=()
    
    # 创建方案选项映射数组
    declare -A scheme_options
    
    while true; do
        # 显示可用的输入方案
        _display_scheme_options
        
        local selection
        read -rp "$(echo -e "${COLOR_YELLOW}请选择输入方案 [1-$((${#scheme_options[@]}))]: ${COLOR_RESET}")" selection
        
        if [[ "$selection" == "0" ]]; then
            break
        fi
        
        # 检查选择是否有效
        if [[ -z "${scheme_options[$selection]}" ]]; then
            log_error "无效的选择: $selection"
            continue
        fi
        
        local scheme="${scheme_options[$selection]}"
        
        # 检查是否已选中
        local already_selected=false
        for s in "${SELECTED_SCHEMES[@]}"; do
            if [[ "$s" == "$scheme" ]]; then
                already_selected=true
                break
            fi
        done
        
        if $already_selected; then
            # 如果已选中，则取消选择
            local new_schemes=()
            for s in "${SELECTED_SCHEMES[@]}"; do
                if [[ "$s" != "$scheme" ]]; then
                    new_schemes+=("$s")
                fi
            done
            SELECTED_SCHEMES=("${new_schemes[@]}")
            log_info "已取消选择: ${INPUT_SCHEMES[$scheme]}"
        else
            # 否则添加到选择列表
            SELECTED_SCHEMES+=("$scheme")
            log_info "已选择: ${INPUT_SCHEMES[$scheme]}"
        fi
    done
    
    if [[ ${#SELECTED_SCHEMES[@]} -eq 0 ]]; then
        log_info "未选择任何输入方案，操作已取消"
        return 0
    fi
    
    log_info "将安装以下输入方案: ${SELECTED_SCHEMES[*]}"
    
    if install_packages "${SELECTED_SCHEMES[@]}"; then
        log_success "输入方案安装成功"
        return 0
    else
        log_error "输入方案安装失败"
        return 1
    fi
}

# 配置输入法环境菜单
_configure_im_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "请先选择输入法框架"
        if ! _install_im_framework; then
            return 1
        fi
    fi
    
    display_header_section "配置输入法环境" "box" 80
    
    log_info "将为 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]} 配置环境变量"
    
    if _confirm_action "确认配置输入法环境变量？" "y"; then
        if _configure_im_environment "$SELECTED_FRAMEWORK"; then
            log_success "输入法环境变量配置成功"
            return 0
        else
            log_error "输入法环境变量配置失败"
            return 1
        fi
    else
        log_info "操作已取消"
        return 0
    fi
}

# 配置桌面环境集成菜单
_configure_for_desktop_environment_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "请先选择输入法框架"
        if ! _install_im_framework; then
            return 1
        fi
    fi
    
    display_header_section "配置桌面环境集成" "box" 80
    
    log_info "检测到当前桌面环境: $DESKTOP_ENV"
    log_info "将为 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]} 配置桌面环境集成"
    
    if _confirm_action "确认配置桌面环境集成？" "y"; then
        if _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then
            log_success "桌面环境集成配置成功"
            return 0
        else
            log_error "桌面环境集成配置失败"
            return 1
        fi
    else
        log_info "操作已取消"
        return 0
    fi
}

# 启动输入法配置工具菜单
_start_config_tool_menu() {
    if [[ -z "$SELECTED_FRAMEWORK" ]]; then
        log_warn "请先选择输入法框架"
        if ! _install_im_framework; then
            return 1
        fi
    fi
    
    display_header_section "启动输入法配置工具" "box" 80
    
    log_info "将启动 ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]} 配置工具"
    
    if _confirm_action "确认启动配置工具？" "y"; then
        if _start_config_tool "$SELECTED_FRAMEWORK"; then
            log_success "输入法配置工具已启动"
            return 0
        else
            log_error "启动输入法配置工具失败"
            return 1
        fi
    else
        log_info "操作已取消"
        return 0
    fi
}

# 完整安装流程
_run_full_installation() {
    display_header_section "完整输入法安装流程" "box" 80
    
    log_info "将执行完整的输入法安装流程，包括:"
    log_info "1. 安装输入法框架"
    log_info "2. 安装输入方案"
    log_info "3. 配置输入法环境"
    log_info "4. 配置桌面环境集成"
    log_info "5. 安装必要的字体"
    
    if ! _confirm_action "确认执行完整安装流程？" "y"; then
        log_info "操作已取消"
        return 0
    fi
    
    # 安装输入法框架
    if ! _install_im_framework; then
        log_error "安装输入法框架失败，中止安装流程"
        return 1
    fi
    
    # 安装输入方案
    if ! _install_input_schemes; then
        log_error "安装输入方案失败，中止安装流程"
        return 1
    fi
    
    # 配置输入法环境
    if ! _configure_im_environment "$SELECTED_FRAMEWORK"; then
        log_error "配置输入法环境失败，中止安装流程"
        return 1
    fi
    
    # 配置桌面环境集成
    if ! _configure_for_desktop_environment "$SELECTED_FRAMEWORK"; then
        log_error "配置桌面环境集成失败，中止安装流程"
        return 1
    fi
    
    # 安装必要的字体
    if ! _install_required_fonts; then
        log_error "安装必要字体失败，中止安装流程"
        return 1
    fi
    
    # 显示安装完成信息
    display_header_section "输入法安装完成" "box" 80 "${COLOR_GREEN}"
    log_summary "输入法已成功安装和配置！" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "--------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "1. 框架: ${INPUT_METHOD_FRAMEWORKS[$SELECTED_FRAMEWORK]}"
    log_summary "2. 已安装的输入方案:"
    for scheme in "${SELECTED_SCHEMES[@]}"; do
        log_summary "   - ${INPUT_SCHEMES[$scheme]}"
    done
    log_summary "3. 环境变量已配置"
    log_summary "4. 桌面环境集成已配置"
    log_summary "--------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "使用说明:"
    log_summary "1. 重启会话或注销并重新登录以使配置生效"
    log_summary "2. 常用快捷键:"
    log_summary "   - Fcitx5: Ctrl+Space (切换输入法)"
    log_summary "   - IBus: Ctrl+Space (切换输入法)"
    log_summary "--------------------------------------------------" "" "${COLOR_GREEN}"
    
    # 询问是否立即启动配置工具
    if _confirm_action "是否立即启动输入法配置工具？" "y"; then
        _start_config_tool "$SELECTED_FRAMEWORK"
    fi
    
    return 0
}

# --- 脚本入口 ---
main "$@"
exit 0
