#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_user_environment/01_configure_shell.sh
# 版本: 1.0.0
# 日期: 2025-06-12
# 描述: 配置 Zsh Shell 环境，包括 Oh My Zsh, Powerlevel10k 主题及常用插件。
#       此模块整合了一个独立的 Zsh 配置项目，并将其完全适配到当前框架中。
# ------------------------------------------------------------------------------
# 核心功能:
# - 检查系统环境和 Zsh 相关组件的安装状态。
# - 安装 Zsh, Oh My Zsh, fzf, bat, eza 等核心工具。
# - 安装 Powerlevel10k 推荐字体 (MesloLGS NF)。
# - 安装 zsh-syntax-highlighting, zsh-autosuggestions, fzf-tab 等插件。
# - 自动配置 .zshrc 文件，启用主题和插件，并添加常用别名。
# - 提供详细的安装后验证和用户指导。
# ------------------------------------------------------------------------------
# 框架适配说明:
# - 使用框架的顶部引导块进行环境初始化。
# - 全面采用框架的日志系统 (log_info, log_error, display_header_section 等)。
# - 使用框架的包管理工具 (is_package_installed, install_pacman_pkg)。
# - 使用框架的全局变量 ($ORIGINAL_USER, $ORIGINAL_HOME)。
# - 所有需要以普通用户身份执行的命令，均通过 `sudo -u $ORIGINAL_USER` 执行。
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
# 全局变量和定义 (模块作用域)
# ==============================================================================

# @var string ZSHRC_FILE 目标用户的 .zshrc 文件路径
ZSHRC_FILE="${ORIGINAL_HOME}/.zshrc"
# @var string P10K_CONFIG_FILE 目标用户的 .p10k.zsh 文件路径
P10K_CONFIG_FILE="${ORIGINAL_HOME}/.p10k.zsh"
# @var string ZSH_CUSTOM_DIR Oh My Zsh 自定义目录路径
ZSH_CUSTOM_DIR="${ORIGINAL_HOME}/.oh-my-zsh/custom"

# @var array SOFTWARE_TO_CHECK 需要检查的软件包列表
declare -A SOFTWARE_TO_CHECK=(
    ["zsh"]="zsh"
    ["fzf"]="fzf"
    ["bat"]="bat" # Arch 仓库中是 bat
    ["eza"]="eza"
    ["git"]="git"
    ["curl"]="curl"
    ["wget"]="wget"
)

# @var array COMPONENTS_TO_CHECK 需要检查的非 pacman 组件
declare -A COMPONENTS_TO_CHECK=(
    ["oh-my-zsh"]="${ORIGINAL_HOME}/.oh-my-zsh"
    ["zsh-syntax-highlighting"]="zsh-syntax-highlighting"
    ["zsh-autosuggestions"]="zsh-autosuggestions"
    ["fzf-tab"]="fzf-tab"
    ["powerlevel10k"]="powerlevel10k"
    ["meslolgs-font"]="MesloLGS"
)

# @var array CHECK_RESULTS 存储所有检查结果
declare -A CHECK_RESULTS
# @var string INSTALL_MODE 用户的安装选择 (missing, force)
INSTALL_MODE=""


# ==============================================================================
# 辅助函数 (移植并适配)
# ==============================================================================

# _is_omz_plugin_installed()
# @description 检查 Oh My Zsh 插件是否已安装
_is_omz_plugin_installed() {
    local plugin_name="$1"
    local plugin_dir="${ZSH_CUSTOM_DIR}/plugins/${plugin_name}"
    [ -d "$plugin_dir" ] && [ -n "$(ls -A "$plugin_dir")" ]
}

# _is_p10k_theme_installed()
# @description 检查 Powerlevel10k 主题是否已安装
_is_p10k_theme_installed() {
    local theme_dir="${ZSH_CUSTOM_DIR}/themes/powerlevel10k"
    [ -d "$theme_dir" ] && [ -f "${theme_dir}/powerlevel10k.zsh-theme" ]
}

# _is_font_installed()
# @description 检查字体是否可能已安装
_is_font_installed() {
    local font_pattern="$1"
    local font_dirs=(
        "${ORIGINAL_HOME}/.local/share/fonts"
        "${ORIGINAL_HOME}/.fonts"
        "/usr/local/share/fonts"
        "/usr/share/fonts"
    )
    for dir in "${font_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # 使用 find 查找，-quit 使其找到第一个就退出，提高效率
            if find "$dir" -iname "*${font_pattern}*" -print -quit | grep -q .; then
                return 0
            fi
        fi
    done
    return 1
}




# ==============================================================================
# 核心功能函数 (移植并重构)
# ==============================================================================

# _perform_checks()
# @description 检查所有软件和组件的安装状态，并与用户交互决定安装模式
_perform_checks() {
    display_header_section "环境检查" "default" 80
    log_info "开始检查系统环境和 Zsh 相关组件..."

    local all_installed=true

    # 检查 Pacman 包
    for key in "${!SOFTWARE_TO_CHECK[@]}"; do
        if is_package_installed "${SOFTWARE_TO_CHECK[$key]}"; then
            CHECK_RESULTS[$key]="已安装"
        else
            CHECK_RESULTS[$key]="未安装"
            all_installed=false
        fi
    done

    # 检查非 Pacman 组件
    CHECK_RESULTS["oh-my-zsh"]=$([ -d "${COMPONENTS_TO_CHECK['oh-my-zsh']}" ] && echo "已安装" || { echo "未安装"; all_installed=false; })
    CHECK_RESULTS["zsh-syntax-highlighting"]=$(_is_omz_plugin_installed "${COMPONENTS_TO_CHECK['zsh-syntax-highlighting']}" && echo "已安装" || { echo "未安装"; all_installed=false; })
    CHECK_RESULTS["zsh-autosuggestions"]=$(_is_omz_plugin_installed "${COMPONENTS_TO_CHECK['zsh-autosuggestions']}" && echo "已安装" || { echo "未安装"; all_installed=false; })
    CHECK_RESULTS["fzf-tab"]=$(_is_omz_plugin_installed "${COMPONENTS_TO_CHECK['fzf-tab']}" && echo "已安装" || { echo "未安装"; all_installed=false; })
    CHECK_RESULTS["powerlevel10k"]=$(_is_p10k_theme_installed && echo "已安装" || { echo "未安装"; all_installed=false; })
    CHECK_RESULTS["meslolgs-font"]=$(_is_font_installed "${COMPONENTS_TO_CHECK['meslolgs-font']}" && echo "可能已安装" || echo "未安装")
    if [[ "${CHECK_RESULTS['meslolgs-font']}" == "未安装" ]]; then
        all_installed=false
    fi

    log_info "检查结果汇总:"
    echo "--------------------------------------------------"
    for key in "${!SOFTWARE_TO_CHECK[@]}" "${!COMPONENTS_TO_CHECK[@]}"; do
        printf "  %-30s: %s\n" "$key" "${CHECK_RESULTS[$key]}"
    done
    echo "--------------------------------------------------"

    if $all_installed; then
        log_success "所有组件似乎都已安装。"
        if _confirm_action "是否强制重新安装所有组件？" "n"; then
            INSTALL_MODE="force"
        else
            log_info "用户选择跳过安装，仅执行配置检查。"
            return 0 # 跳过安装
        fi
    else
        log_notice "部分组件未安装。"
        if _confirm_action "是否安装缺失的组件？（选择'n'将只配置已安装部分）" "y"; then
            INSTALL_MODE="missing"
        else
            log_info "用户选择跳过安装，仅执行配置检查。"
            return 0 # 跳过安装
        fi
    fi
    return 1 # 需要安装
}


# _install_fonts()
# @description 下载并安装 MesloLGS NF 字体
_install_fonts() {
    display_header_section "安装字体 (MesloLGS NF)" "default" 80
    
    local font_dir="${ORIGINAL_HOME}/.local/share/fonts"
    log_info "字体将安装到: $font_dir"
    run_as_user "mkdir -p '$font_dir'"

    declare -A FONT_URLS=(
        ["MesloLGS NF Regular.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
        ["MesloLGS NF Bold.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
        ["MesloLGS NF Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
        ["MesloLGS NF Bold Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    )

    local all_success=true
    for font_name in "${!FONT_URLS[@]}"; do
        local dest_path="$font_dir/$font_name"
        if [ -f "$dest_path" ]; then
            log_info "字体 '$font_name' 已存在，跳过下载。"
            continue
        fi
        log_info "下载字体: $font_name"
        if ! run_as_user "curl -fLo '$dest_path' '${FONT_URLS[$font_name]}'"; then
            log_error "下载字体 '$font_name' 失败。"
            all_success=false
        fi
    done

    if $all_success; then
        log_info "正在更新字体缓存..."
        if run_as_user "fc-cache -fv"; then
            log_success "字体安装和缓存更新成功。"
        else
            log_warn "字体缓存更新失败，可能需要手动运行 'fc-cache -fv' 或重启。"
        fi
    else
        handle_error "字体下载失败，中止操作。" 1
    fi
}

# _run_installation()
# @description 执行所有必要的安装操作
_run_installation() {
    display_header_section "安装 Zsh 组件" "box" 80

    # 1. 安装 Pacman 包
    local pkgs_to_install=()
    for key in "${!SOFTWARE_TO_CHECK[@]}"; do
        if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS[$key]}" == "未安装" ]]; then
            pkgs_to_install+=("${SOFTWARE_TO_CHECK[$key]}")
        fi
    done
    if [ ${#pkgs_to_install[@]} -gt 0 ]; then
        log_info "将通过 pacman 安装以下软件包: ${pkgs_to_install[*]}"
        install_pacman_pkg "${pkgs_to_install[@]}"
    else
        log_info "无需通过 pacman 安装新软件包。"
    fi

    # 2. 安装字体
    if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['meslolgs-font']}" == "未安装" ]]; then
        _install_fonts
    fi

    # 3. 安装 Oh My Zsh
    local oh_my_zsh_dir="${COMPONENTS_TO_CHECK['oh-my-zsh']}"
    if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['oh-my-zsh']}" == "未安装" ]]; then
        log_info "安装 Oh My Zsh..."
        if [ -d "$oh_my_zsh_dir" ]; then
            log_warn "Oh My Zsh 目录已存在，将删除后重新安装。"
            rm -rf "$oh_my_zsh_dir"
        fi
        # 使用 --unattended 自动安装，并用 --keep-zshrc 避免覆盖已有配置
        local install_script_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
        if ! run_as_user "sh -c \"\$(curl -fsSL $install_script_url)\" \"\" --unattended --keep-zshrc"; then
            handle_error "Oh My Zsh 安装失败！" 1
        fi
        log_success "Oh My Zsh 安装成功。"
    fi

    # 4. 安装 Oh My Zsh 插件和主题
    declare -A PLUGINS_TO_INSTALL=(
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
        ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git"
    )
    local p10k_repo="https://github.com/romkatv/powerlevel10k.git"

    # 确保 custom 目录存在
    run_as_user "mkdir -p '${ZSH_CUSTOM_DIR}/plugins' '${ZSH_CUSTOM_DIR}/themes'"

    for plugin in "${!PLUGINS_TO_INSTALL[@]}"; do
        if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS[$plugin]}" == "未安装" ]]; then
            local plugin_dir="${ZSH_CUSTOM_DIR}/plugins/${plugin}"
            log_info "安装插件: $plugin"
            if [ -d "$plugin_dir" ]; then rm -rf "$plugin_dir"; fi
            if ! run_as_user "git clone --depth=1 '${PLUGINS_TO_INSTALL[$plugin]}' '$plugin_dir'"; then
                log_error "安装插件 '$plugin' 失败！"
            else
                log_success "插件 '$plugin' 安装成功。"
            fi
        fi
    done
    
    # 安装 Powerlevel10k
    if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['powerlevel10k']}" == "未安装" ]]; then
        local theme_dir="${ZSH_CUSTOM_DIR}/themes/powerlevel10k"
        log_info "安装主题: Powerlevel10k"
        if [ -d "$theme_dir" ]; then rm -rf "$theme_dir"; fi
        if ! run_as_user "git clone --depth=1 '$p10k_repo' '$theme_dir'"; then
            log_error "安装 Powerlevel10k 失败！"
        else
            log_success "Powerlevel10k 主题安装成功。"
        fi
    fi
}

# _run_configuration()
# @description 修改 .zshrc 文件以启用主题和插件
_run_configuration() {
    display_header_section "配置 .zshrc 文件" "box" 80

    if [ ! -f "$ZSHRC_FILE" ]; then
        log_info "$ZSHRC_FILE 不存在，将从 Oh My Zsh 模板创建。"
        run_as_user "cp '${ORIGINAL_HOME}/.oh-my-zsh/templates/zshrc.zsh-template' '$ZSHRC_FILE'"
    fi

    log_info "备份当前 .zshrc 文件..."
    local backup_file="${ZSHRC_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_user "cp '$ZSHRC_FILE' '$backup_file'"
    log_success "已备份到: $backup_file"

    # 1. 配置主题
    log_info "设置 ZSH_THEME 为 'powerlevel10k/powerlevel10k'..."
    run_as_user "sed -i 's|^\\s*ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|' '$ZSHRC_FILE'"

    # 2. 配置插件
    local desired_plugins=("git" "zsh-syntax-highlighting" "zsh-autosuggestions" "fzf" "fzf-tab")
    log_info "设置启用的插件: ${desired_plugins[*]}"
    local plugins_str="plugins=(${desired_plugins[*]})"
    # 如果 .zshrc 中已有 plugins=(...) 行，则替换它；否则，在末尾添加。
    if run_as_user "grep -q '^\\s*plugins=(' '$ZSHRC_FILE'"; then
        run_as_user "sed -i 's|^\\s*plugins=(.*)|$plugins_str|' '$ZSHRC_FILE'"
    else
        run_as_user "echo -e '\n$plugins_str' >> '$ZSHRC_FILE'"
    fi

    # 3. 配置别名和其他
    log_info "添加 eza 和 bat 的别名..."
    local aliases_block="# Custom Aliases added by script
alias ls='eza --icons'
alias la='eza -a --icons'
alias ll='eza -al --git --icons'
alias tree='eza --tree'
alias cat='bat --paging=never'
# End Custom Aliases"
    # 避免重复添加
    if ! run_as_user "grep -q '# Custom Aliases added by script' '$ZSHRC_FILE'"; then
        run_as_user "echo -e '\n$aliases_block' >> '$ZSHRC_FILE'"
    fi

    # 4. 添加 Powerlevel10k 初始化代码（如果 p10k configure 没跑过）
    local p10k_init_block="# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh"
     if ! run_as_user "grep -q 'source ~/.p10k.zsh' '$ZSHRC_FILE'"; then
        run_as_user "echo -e '\n$p10k_init_block' >> '$ZSHRC_FILE'"
     fi

    log_success ".zshrc 文件配置完成。"
}

# _run_post_install_checks()
# @description 提供最终用户指导
_run_post_install_checks() {
    display_header_section "后续步骤和建议" "box" 80 "${COLOR_CYAN}"

    log_summary "Zsh 环境配置已完成！" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "1. 更改默认 Shell:"
    log_summary "   要将 Zsh 设为默认 Shell，请运行以下命令:"
    log_summary "   chsh -s $(command -v zsh) $ORIGINAL_USER"
    log_summary "   更改后需要重新登录才能生效。" "" "${COLOR_YELLOW}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "2. 应用配置:"
    log_summary "   重新启动终端，或在当前终端运行 'source ~/.zshrc'。"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "3. Powerlevel10k 个性化:"
    log_summary "   首次启动 Zsh 时，Powerlevel10k 可能会自动运行配置向导。"
    log_summary "   您也可以随时手动运行 'p10k configure' 来重新配置。" "" "${COLOR_YELLOW}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "4. 终端字体:"
    log_summary "   请确保您的终端模拟器已设置为使用 'MesloLGS NF' 字体。"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
}


# ==============================================================================
# 主函数
# ==============================================================================

main() {
    display_header_section "Zsh & Oh My Zsh & P10k 自动配置" "box" 80
    log_info "本模块将为用户 '$ORIGINAL_USER' 全面配置 Zsh 环境。"
    log_notice "所有操作将在 '$ORIGINAL_HOME' 目录下进行。"

    if ! _confirm_action "是否开始 Zsh 环境配置？" "y"; then
        log_warn "用户取消操作。"
        exit 0
    fi

    # 步骤 1: 检查环境
    if _perform_checks; then
        log_info "环境检查完毕，无需安装新组件，仅进行配置。"
    else
        # 步骤 2: 执行安装
        if [[ -n "$INSTALL_MODE" ]]; then
            _run_installation
        fi
    fi

    # 步骤 3: 执行配置
    _run_configuration

    # 步骤 4: 显示后续指导
    _run_post_install_checks

    log_success "Zsh 环境配置模块执行完毕！"
}

# --- 脚本入口 ---
main "$@"
exit 0