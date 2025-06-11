#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_user_environment/01_configure_shell.sh
# 版本: 1.1.0 (流程复刻版)
# 日期: 2025-06-12
# 描述: 全自动安装和配置 Zsh 全家桶。此版本完全复刻了原始独立脚本的
#       “检查-决策-安装-配置-验证”的用户交互流程，并适配到本项目框架。
# ------------------------------------------------------------------------------
# 核心功能:
#   - 阶段化执行：清晰地分为检查、安装、配置和验证四个阶段。
#   - 交互式决策：在检查后向用户报告现状，并询问安装策略。
#   - 智能安装：根据用户决策和检查结果，精确安装所需组件。
#   - 全自动配置：安全、幂等地修改 .zshrc 文件。
#   - 详尽的报告与指导：在流程开始和结束时提供清晰的报告和操作指南。
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
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory." >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 全局变量 (模块内)
# ==============================================================================
declare -A CHECK_RESULTS
INSTALL_MODE="" # 将由 _perform_checks_and_get_decision 函数填充
# --- Zsh 和用户 Shell 相关配置 ---
export ZSH_CUSTOM_PLUGINS_DIR="${ZSH_CUSTOM:-${ORIGINAL_HOME}/.oh-my-zsh/custom}/plugins"
export ZSH_CUSTOM_THEMES_DIR="${ZSH_CUSTOM:-${ORIGINAL_HOME}/.oh-my-zsh/custom}/themes"

# Zsh 及其相关工具的软件包列表
declare -a PKG_ZSH_STACK=("zsh" "fzf" "bat" "eza")
# Oh My Zsh 插件的 Git 仓库 URL
declare -A ZSH_PLUGINS_GIT_URLS=(
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
    ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git"
)
# Powerlevel10k 主题的 Git 仓库 URL
export ZSH_THEME_P10K_GIT_URL="https://github.com/romkatv/powerlevel10k.git"

# Powerlevel10k 推荐字体的下载 URL
declare -A FONT_MESLOLGS_URLS=(
    ["MesloLGS NF Regular.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    ["MesloLGS NF Bold.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    ["MesloLGS NF Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    ["MesloLGS NF Bold Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)

# ==============================================================================
# 阶段一：检查与决策
# ==============================================================================

# _check_single_item()
# @description: 检查单个组件的安装状态
_check_single_item() {
    local key="$1"
    
    case "$key" in
        "oh-my-zsh")
            [ -d "${ORIGINAL_HOME}/.oh-my-zsh" ] && CHECK_RESULTS[$key]="已安装" || CHECK_RESULTS[$key]="未安装"
            ;;
        "p10k-theme")
            [ -d "${ZSH_CUSTOM_THEMES_DIR}/powerlevel10k" ] && CHECK_RESULTS[$key]="已安装" || CHECK_RESULTS[$key]="未安装"
            ;;
        "meslolgs-font")
            # 这是一个启发式检查，不完全可靠
            if find "${ORIGINAL_HOME}/.local/share/fonts" -iname "*MesloLGS*" -print -quit 2>/dev/null | grep -q .; then
                CHECK_RESULTS[$key]="可能已安装"
            else
                CHECK_RESULTS[$key]="未安装"
            fi
            ;;
        *) # 检查插件或pacman包
            if [[ " ${!ZSH_PLUGINS_GIT_URLS[@]} " =~ " ${key} " ]]; then
                # 是插件
                [ -d "${ZSH_CUSTOM_PLUGINS_DIR}/${key}" ] && CHECK_RESULTS[$key]="已安装" || CHECK_RESULTS[$key]="未安装"
            elif is_package_installed "$key"; then
                # 是 pacman 包
                 CHECK_RESULTS[$key]="已安装"
            else
                 CHECK_RESULTS[$key]="未安装"
            fi
            ;;
    esac
}

# _perform_checks_and_get_decision()
# @description: 执行所有检查，向用户报告，并获取安装决策。
_perform_checks_and_get_decision() {
    display_header_section "Phase 1: Environment Check" "default" 80
    
    local components_to_check=("zsh" "fzf" "bat" "eza" "git" "curl" "wget" "oh-my-zsh" "${!ZSH_PLUGINS_GIT_URLS[@]}" "p10k-theme" "meslolgs-font")
    local all_installed=true

    log_info "Performing checks for all required components..."
    for item in "${components_to_check[@]}"; do
        _check_single_item "$item"
        if [[ "${CHECK_RESULTS[$item]}" == "未安装" ]]; then
            all_installed=false
        fi
    done

    # 显示检查报告
    log_summary "------------------- Check Report -------------------"
    printf "%-30s | %s\n" "Component" "Status"
    log_summary "--------------------------------------------------"
    for item in "${!CHECK_RESULTS[@]}"; do
        local status="${CHECK_RESULTS[$item]}"
        local color="${COLOR_GREEN}"
        if [[ "$status" != "已安装" ]]; then color="${COLOR_YELLOW}"; fi
        log_summary "$(printf "%-30s | ${color}%s${COLOR_RESET}" "$item" "$status")"
    done
    log_summary "--------------------------------------------------"

    # 获取用户决策
    if [[ "$all_installed" = true ]]; then
        log_notice "All components seem to be installed."
        # 使用 select 实现菜单选择
        PS3="$(echo -e "${COLOR_YELLOW}Please choose an action: ${COLOR_RESET}")"
        options=("Force reinstall all components" "Skip installation, only run configuration" "Cancel")
        select opt in "${options[@]}"; do
            case $opt in
                "${options[0]}") INSTALL_MODE="force"; break;;
                "${options[1]}") INSTALL_MODE="skip_install"; break;;
                "${options[2]}") INSTALL_MODE="cancel"; break;;
                *) log_warn "Invalid option. Please enter 1, 2, or 3.";;
            esac
        done
    else
        log_warn "Some components are missing."
        PS3="$(echo -e "${COLOR_YELLOW}Please choose an installation mode: ${COLOR_RESET}")"
        options=("Install missing components only" "Force reinstall all components" "Cancel")
        select opt in "${options[@]}"; do
            case $opt in
                "${options[0]}") INSTALL_MODE="missing"; break;;
                "${options[1]}") INSTALL_MODE="force"; break;;
                "${options[2]}") INSTALL_MODE="cancel"; break;;
                *) log_warn "Invalid option. Please enter 1, 2, or 3.";;
            esac
        done
    fi

    if [[ "$INSTALL_MODE" == "cancel" ]]; then
        log_info "User cancelled the operation."
        return 1
    fi

    log_info "User selected mode: '$INSTALL_MODE'"
    return 0
}


# ==============================================================================
# 阶段二：安装
# ==============================================================================

_install_component() {
    local item="$1"
    # 如果不是强制模式，且已安装，则跳过
    if [[ "$INSTALL_MODE" != "force" && "${CHECK_RESULTS[$item]}" == "已安装" ]]; then
        return 0
    fi
    # 字体特殊处理
    if [[ "$item" == "meslolgs-font" && "$INSTALL_MODE" != "force" && "${CHECK_RESULTS[$item]}" == "可能已安装" ]]; then
        if ! _confirm_action "Font 'MesloLGS' may already be installed. Do you want to install it again?" "n"; then
            return 0
        fi
    fi

    log_notice "Installing/Updating component: $item"
    case "$item" in
        "oh-my-zsh")
            _run_as_user "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended" || log_error "Failed to install Oh My Zsh."
            ;;
        "p10k-theme")
            _run_as_user "git clone --depth=1 '${ZSH_THEME_P10K_GIT_URL}' '${ZSH_CUSTOM_THEMES_DIR}/powerlevel10k'" || log_error "Failed to install Powerlevel10k."
            ;;
        "meslolgs-font")
            _install_fonts_logic
            ;;
        *)
            if [[ " ${!ZSH_PLUGINS_GIT_URLS[@]} " =~ " ${item} " ]]; then
                local repo_url="${ZSH_PLUGINS_GIT_URLS[$item]}"
                _run_as_user "git clone --depth=1 '${repo_url}' '${ZSH_CUSTOM_PLUGINS_DIR}/${item}'" || log_error "Failed to install plugin '$item'."
            fi
            ;;
    esac
}

_install_fonts_logic() {
    # 字体安装逻辑
    local font_dir_user="${ORIGINAL_HOME}/.local/share/fonts"
    mkdir -p "$font_dir_user" && chown -R "${ORIGINAL_USER}:${ORIGINAL_USER}" "$(dirname "$font_dir_user")"

    for font_name in "${!FONT_MESLOLGS_URLS[@]}"; do
        local dest_path="${font_dir_user}/${font_name}"
        if [[ "$INSTALL_MODE" == "force" || ! -f "$dest_path" ]]; then
            log_info "Downloading '$font_name'..."
            curl -fLo "$dest_path" "${FONT_MESLOLGS_URLS[$font_name]}" && chown "${ORIGINAL_USER}:${ORIGINAL_USER}" "$dest_path" || log_error "Failed to download $font_name"
        fi
    done
    log_info "Updating font cache..."
    _run_as_user "fc-cache -fv"
}

_run_installation_phase() {
    if [[ "$INSTALL_MODE" == "skip_install" ]]; then
        log_info "Skipping installation phase as requested by user."
        return 0
    fi

    display_header_section "Phase 2: Installation" "default" 80

    # 安装 pacman 包
    local pacman_pkgs_to_install=()
    local pacman_pkg_keys=("zsh" "fzf" "bat" "eza" "git" "curl" "wget")
    for key in "${pacman_pkg_keys[@]}"; do
        if [[ "$INSTALL_MODE" == "force" || "${CHECK_RESULTS[$key]}" != "已安装" ]]; then
            pacman_pkgs_to_install+=("$key")
        fi
    done
    if [ ${#pacman_pkgs_to_install[@]} -gt 0 ]; then
        install_pacman_pkg "${pacman_pkgs_to_install[@]}"
    fi

    # 安装其他组件
    local components_to_install=("oh-my-zsh" "${!ZSH_PLUGINS_GIT_URLS[@]}" "p10k-theme" "meslolgs-font")
    for item in "${components_to_install[@]}"; do
        _install_component "$item"
    done
}


# ==============================================================================
# 阶段三：配置
# ==============================================================================

_run_configuration_phase() {
    display_header_section "Phase 3: Configuration" "default" 80
    log_info "Configuring .zshrc file for user '$ORIGINAL_USER'..."
    local zshrc_path="${ORIGINAL_HOME}/.zshrc"

    # 备份
    if [ -f "$zshrc_path" ]; then
        local backup_path="${zshrc_path}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$zshrc_path" "$backup_path" && chown "${ORIGINAL_USER}:${ORIGINAL_USER}" "$backup_path"
        log_info "Backed up existing .zshrc to '$backup_path'."
    else
        touch "$zshrc_path" && chown "${ORIGINAL_USER}:${ORIGINAL_USER}" "$zshrc_path"
    fi

    # 使用 _run_as_user 和 here document 安全地修改文件
    local command_to_run
    read -r -d '' command_to_run << 'EOF'
ZSHRC_FILE=~/.zshrc
# 清理旧的托管配置
sed -i -e '/# Zsh theme setting (managed by script)/,/# End of Zsh theme setting/d' \
       -e '/# Oh My Zsh plugins (managed by script)/,/# End of Oh My Zsh plugins/d' \
       -e '/# Recommended aliases (managed by script)/,/# End of recommended aliases/d' \
       -e '/# fzf-tab zstyle configuration (managed by script)/,/# End of fzf-tab zstyle configuration/d' \
       -e '/# Powerlevel10k source line (managed by script)/,/# End of Powerlevel10k source line/d' \
       "$ZSHRC_FILE"

# 写入新的托管配置
{
    echo '# Zsh theme setting (managed by script)'
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"'
    echo '# End of Zsh theme setting'
    echo ''
    echo '# Oh My Zsh plugins (managed by script)'
    echo 'plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf fzf-tab)'
    echo '# End of Oh My Zsh plugins'
    echo ''
    echo '# Powerlevel10k source line (managed by script)'
    echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
    echo '# End of Powerlevel10k source line'
    echo ''
    echo '# Recommended aliases (managed by script)'
    echo "if command -v bat &>/dev/null; then alias cat='bat'; fi"
    echo "if command -v eza &>/dev/null; then"
    echo "    alias ls='eza'"
    echo "    alias l='eza -l'"
    echo "    alias la='eza -la'"
    echo "    alias ll='eza -l --git --icons'"
    echo "    alias tree='eza --tree'"
    echo "fi"
    echo '# End of recommended aliases'
    echo ''
    echo '# fzf-tab zstyle configuration (managed by script)'
    echo "zstyle ':fzf-tab:*' fzf-flags --height=60% --border"
    echo "zstyle ':fzf-tab:complete:*:*' fzf-preview '(bat --color=always --line-range :500 \${(f)realpath} 2>/dev/null || exa -al --git --icons \${(f)realpath} || ls -lAh --color=always \${(f)realpath}) 2>/dev/null'"
    echo '# End of fzf-tab zstyle configuration'
} >> "$ZSHRC_FILE"
EOF

    if _run_as_user "$command_to_run"; then
        log_success ".zshrc configuration completed successfully."
    else
        log_error "Failed to configure .zshrc."
    fi
}

# ==============================================================================
# 阶段四：验证与指导
# ==============================================================================

_run_post_install_phase() {
    display_header_section "Phase 4: Verification & Next Steps" "default" 80
    
    # 重新检查并报告
    log_info "Performing final verification..."
    local final_components_to_check=("zsh" "fzf" "bat" "eza" "oh-my-zsh" "${!ZSH_PLUGINS_GIT_URLS[@]}" "p10k-theme" "meslolgs-font")
    local final_report=""
    for item in "${final_components_to_check[@]}"; do
        _check_single_item "$item"
        final_report+=$(printf "%-30s | %s\n" "$item" "${CHECK_RESULTS[$item]}")
    done
    log_summary "---------------- Final Verification Report -----------------"
    echo -e "$final_report"
    log_summary "----------------------------------------------------------"

    # 后续指导
    log_notice "Setup finished. Please follow these steps to complete:"
    log_info "1. ${COLOR_YELLOW}Set Zsh as default shell:${COLOR_RESET} Run 'chsh -s \$(which zsh) ${ORIGINAL_USER}' and re-login."
    log_info "2. ${COLOR_YELLOW}Configure Powerlevel10k:${COLOR_RESET} Open a new Zsh terminal and run 'p10k configure'."
    log_info "3. ${COLOR_YELLOW}Set Terminal Font:${COLOR_RESET} In your terminal's settings, choose 'MesloLGS NF' as the font."
    
    # 询问是否设置默认shell
    if [[ "$(getent passwd "$ORIGINAL_USER" | cut -d: -f7)" != "$(which zsh)" ]]; then
        if _confirm_action "Do you want to set Zsh as the default shell for '$ORIGINAL_USER' now?"; then
            if chsh -s "$(which zsh)" "$ORIGINAL_USER"; then
                log_success "Default shell for '$ORIGINAL_USER' has been changed. Please re-login to take effect."
            else
                log_error "Failed to change default shell. Please run 'sudo chsh -s \$(which zsh) ${ORIGINAL_USER}' manually."
            fi
        fi
    fi
}

# ==============================================================================
# 辅助函数
# ==============================================================================

# _run_as_user()
# @description: 以原始用户的身份执行命令。
_run_as_user() {
    log_debug "Executing command as user '$ORIGINAL_USER': $@"
    if command -v runuser &>/dev/null; then
        runuser -l "$ORIGINAL_USER" -c "$*"
    elif command -v su &>/dev/null; then
        su - "$ORIGINAL_USER" -c "$*"
    else
        log_error "Cannot execute command as user: 'runuser' and 'su' not found."
        return 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Zsh Enhancement Setup" "box" 80
    
    # 阶段一：检查与决策
    if ! _perform_checks_and_get_decision; then
        log_warn "Setup cancelled by user during check phase."
        return 0
    fi

    # 阶段二：安装
    _run_installation_phase

    # 阶段三：配置
    _run_configuration_phase

    # 阶段四：验证与指导
    _run_post_install_phase

    log_success "Zsh enhancement module finished."
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"
exit_script $?