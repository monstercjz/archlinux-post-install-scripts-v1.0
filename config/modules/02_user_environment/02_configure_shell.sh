#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/03_user_environment/01_configure_shell.sh
# 版本: 1.3.0 (新增从模板文件快速配置的功能)
# 日期: 2025-06-12
# 描述: 配置 Zsh Shell 环境，包括 Oh My Zsh, Powerlevel10k 主题及常用插件。
#       提供“逐步配置”和“从模板快速配置”两种模式。
# ------------------------------------------------------------------------------
# 核心功能:
# - 检查系统环境和 Zsh 相关组件的安装状态。
# - 安装 Zsh, Oh My Zsh, fzf, bat, eza 等核心工具。
# - 安装 Powerlevel10k 推荐字体 (MesloLGS NF)。
# - 安装 zsh-syntax-highlighting, zsh-autosuggestions, fzf-tab 等插件。
# - 使用安全的文件更新策略，自动配置 .zshrc 文件。
# - 提供详细的安装后验证和用户指导。
# ------------------------------------------------------------------------------
# 版本 1.3.0 优化内容:
# - **新增配置模式**: 用户可以选择“逐步、安全地配置”或“从预设模板文件快速覆盖”。
# - **安全事务模型**: 所有对 .zshrc 的修改都在一个临时副本上进行，成功后才替换原始文件，杜绝文件丢失风险。
# - **职责分离**: 将庞大的配置函数拆分为多个独立的、职责单一的小函数。
# - **细化交互**: 当所有组件已安装时，提供“强制重装”、“仅配置”、“取消”选项。
# - **动态配置**: .zshrc 中的插件列表会根据实际安装成功的组件动态生成。
# - **优雅的错误处理**: Oh My Zsh 安装失败时，会跳过相关插件/主题安装，而不是直接退出。
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
ZSHRC_FILE="${ORIGINAL_HOME}/.zshrc"
ZSH_CUSTOM_DIR="${ORIGINAL_HOME}/.oh-my-zsh/custom"
ZSHRC_TEMPLATE_PATH="${ASSETS_DIR}/shell/zshrc.template"

declare -A SOFTWARE_TO_CHECK=(
    ["zsh"]="zsh" ["fzf"]="fzf" ["bat"]="bat" ["eza"]="eza"
    ["git"]="git" ["curl"]="curl" ["wget"]="wget"
)
declare -A COMPONENTS_TO_CHECK=(
    ["oh-my-zsh"]="${ORIGINAL_HOME}/.oh-my-zsh"
    ["zsh-syntax-highlighting"]="zsh-syntax-highlighting"
    ["zsh-autosuggestions"]="zsh-autosuggestions"
    ["fzf-tab"]="fzf-tab"
    ["powerlevel10k"]="powerlevel10k"
    ["meslolgs-font"]="MesloLGS"
)
declare -A CHECK_RESULTS
INSTALL_MODE="" # missing, force, skip


# ==============================================================================
# 辅助检查函数
# ==============================================================================

_is_omz_plugin_installed() { [ -d "${ZSH_CUSTOM_DIR}/plugins/${1}" ] && [ -n "$(ls -A "${ZSH_CUSTOM_DIR}/plugins/${1}" 2>/dev/null)" ]; }
_is_p10k_theme_installed() { [ -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ] && [ -f "${ZSH_CUSTOM_DIR}/themes/powerlevel10k/powerlevel10k.zsh-theme" ]; }
_is_font_installed() { find "${ORIGINAL_HOME}/.local/share/fonts" /usr/local/share/fonts /usr/share/fonts -iname "*${1}*" -print -quit 2>/dev/null | grep -q .; }


# ==============================================================================
# 核心业务逻辑函数
# ==============================================================================

# _perform_checks()
# @description 检查所有软件和组件的安装状态，并与用户交互决定安装模式
_perform_checks() {
    display_header_section "环境检查" "default" 80
    log_info "开始检查系统环境和 Zsh 相关组件..."

    local all_installed=true
    for key in "${!SOFTWARE_TO_CHECK[@]}"; do is_package_installed "${SOFTWARE_TO_CHECK[$key]}" && CHECK_RESULTS[$key]="已安装" || { CHECK_RESULTS[$key]="未安装"; all_installed=false; }; done
    [ -d "${COMPONENTS_TO_CHECK['oh-my-zsh']}" ] && CHECK_RESULTS["oh-my-zsh"]="已安装" || { CHECK_RESULTS["oh-my-zsh"]="未安装"; all_installed=false; }
    _is_omz_plugin_installed "zsh-syntax-highlighting" && CHECK_RESULTS["zsh-syntax-highlighting"]="已安装" || { CHECK_RESULTS["zsh-syntax-highlighting"]="未安装"; all_installed=false; }
    _is_omz_plugin_installed "zsh-autosuggestions" && CHECK_RESULTS["zsh-autosuggestions"]="已安装" || { CHECK_RESULTS["zsh-autosuggestions"]="未安装"; all_installed=false; }
    _is_omz_plugin_installed "fzf-tab" && CHECK_RESULTS["fzf-tab"]="已安装" || { CHECK_RESULTS["fzf-tab"]="未安装"; all_installed=false; }
    _is_p10k_theme_installed && CHECK_RESULTS["powerlevel10k"]="已安装" || { CHECK_RESULTS["powerlevel10k"]="未安装"; all_installed=false; }
    _is_font_installed "MesloLGS" && CHECK_RESULTS["meslolgs-font"]="可能已安装" || { CHECK_RESULTS["meslolgs-font"]="未安装"; all_installed=false; }

    log_info "检查结果汇总:"; echo "--------------------------------------------------"; for key in "${!SOFTWARE_TO_CHECK[@]}" "${!COMPONENTS_TO_CHECK[@]}"; do printf "  %-30s: %s\n" "$key" "${CHECK_RESULTS[$key]}"; done; echo "--------------------------------------------------"

    if $all_installed; then
        log_success "所有组件似乎都已安装。"
        while true; do
            read -rp "$(echo -e "${COLOR_YELLOW}请选择操作: [1] 强制重装 [2] 仅配置 [c] 取消: ${COLOR_RESET}")" choice; echo
            case "$choice" in
                1) INSTALL_MODE="force"; return 1 ;;
                2) INSTALL_MODE="skip"; return 0 ;;
                c|C) log_info "用户取消操作。"; exit 0 ;;
                *) log_warn "无效输入。" ;;
            esac
        done
    else
        log_notice "部分组件未安装。"
        if _confirm_action "是否安装/更新缺失的组件？ (选择'n'将只配置已安装部分)" "y"; then
            INSTALL_MODE="missing"; return 1
        else
            log_info "用户选择跳过安装，仅执行配置检查。"; INSTALL_MODE="skip"; return 0
        fi
    fi
}

# _install_fonts()
# @description 下载并安装 MesloLGS NF 字体
_install_fonts() {
    display_header_section "安装字体 (MesloLGS NF)" "default" 80
    local font_dir="${ORIGINAL_HOME}/.local/share/fonts"
    log_info "字体将安装到: $font_dir"; run_as_user "mkdir -p '$font_dir'"
    declare -A FONT_URLS=(
        ["MesloLGS NF Regular.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
        ["MesloLGS NF Bold.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
        ["MesloLGS NF Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
        ["MesloLGS NF Bold Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    )
    local all_success=true
    for font_name in "${!FONT_URLS[@]}"; do
        if [ -f "$font_dir/$font_name" ] && [[ "$INSTALL_MODE" != "force" ]]; then
            log_info "字体 '$font_name' 已存在，跳过下载。"; continue
        fi
        log_info "下载字体: $font_name"
        if ! run_as_user "curl -fLo '$font_dir/$font_name' '${FONT_URLS[$font_name]}'"; then
            log_error "下载字体 '$font_name' 失败。"; all_success=false
        fi
    done
    if $all_success; then
        log_info "正在更新字体缓存..."; if run_as_user "fc-cache -fv"; then log_success "字体安装和缓存更新成功。"; else log_warn "字体缓存更新失败，可能需要手动运行。"; fi
    else
        handle_error "字体下载失败，中止操作。" 1
    fi
}

# _run_installation()
# @description 执行所有必要的安装操作
_run_installation() {
    display_header_section "安装 Zsh 组件" "box" 80
    local pkgs_to_install=(); for key in "${!SOFTWARE_TO_CHECK[@]}"; do if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS[$key]}" == "未安装" ]]; then pkgs_to_install+=("${SOFTWARE_TO_CHECK[$key]}"); fi; done
    if [ ${#pkgs_to_install[@]} -gt 0 ]; then log_info "将通过 pacman 安装以下软件包: ${pkgs_to_install[*]}"; install_pacman_pkg "${pkgs_to_install[@]}"; else log_info "无需通过 pacman 安装新软件包。"; fi
    if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['meslolgs-font']}" == "未安装" ]]; then _install_fonts; fi

    local omz_installed_successfully=false
    if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['oh-my-zsh']}" == "未安装" ]]; then
        log_info "安装 Oh My Zsh..."; local oh_my_zsh_dir="${COMPONENTS_TO_CHECK['oh-my-zsh']}"
        if [ -d "$oh_my_zsh_dir" ]; then log_warn "Oh My Zsh 目录已存在，将删除后重新安装。"; rm -rf "$oh_my_zsh_dir"; fi
        local install_script_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
        if run_as_user "sh -c \"\$(curl -fsSL $install_script_url)\" '' --unattended --keep-zshrc"; then omz_installed_successfully=true; log_success "Oh My Zsh 安装成功。"; else log_error "Oh My Zsh 安装失败！将跳过所有插件和主题的安装。"; fi
    else
        omz_installed_successfully=true
    fi

    if $omz_installed_successfully; then
        declare -A PLUGINS_TO_INSTALL=( ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git" ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git" ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git" )
        local p10k_repo="https://github.com/romkatv/powerlevel10k.git"
        run_as_user "mkdir -p '${ZSH_CUSTOM_DIR}/plugins' '${ZSH_CUSTOM_DIR}/themes'"
        for plugin in "${!PLUGINS_TO_INSTALL[@]}"; do
            if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS[$plugin]}" == "未安装" ]]; then
                local plugin_dir="${ZSH_CUSTOM_DIR}/plugins/${plugin}"; log_info "安装插件: $plugin"
                if [ -d "$plugin_dir" ]; then rm -rf "$plugin_dir"; fi
                if ! run_as_user "git clone --depth=1 '${PLUGINS_TO_INSTALL[$plugin]}' '$plugin_dir'"; then log_error "安装插件 '$plugin' 失败！"; else log_success "插件 '$plugin' 安装成功。"; fi
            fi
        done
        if [[ "$INSTALL_MODE" == "force" ]] || [[ "${CHECK_RESULTS['powerlevel10k']}" == "未安装" ]]; then
            local theme_dir="${ZSH_CUSTOM_DIR}/themes/powerlevel10k"; log_info "安装主题: Powerlevel10k"
            if [ -d "$theme_dir" ]; then rm -rf "$theme_dir"; fi
            if ! run_as_user "git clone --depth=1 '$p10k_repo' '$theme_dir'"; then log_error "安装 Powerlevel10k 失败！"; else log_success "Powerlevel10k 主题安装成功。"; fi
        fi
    fi
}

# _configure_from_template()
# @description 从模板文件快速配置 .zshrc
_configure_from_template() {
    display_header_section "从模板快速配置 .zshrc" "box" 80
    
    if [ ! -f "$ZSHRC_TEMPLATE_PATH" ]; then
        log_error "模板文件未找到: $ZSHRC_TEMPLATE_PATH"
        log_error "无法进行快速配置。请检查项目文件是否完整。"
        return 1
    fi

    log_warn "此操作将完全覆盖您现有的 .zshrc 文件！"
    if ! _confirm_action "您确定要从模板文件覆盖 '$ZSHRC_FILE' 吗？" "n" "${COLOR_RED}"; then
        log_info "用户取消了从模板覆盖的操作。"; return 1
    fi
    # **新增：获取原始文件的权限**
    local original_perms
    if [ -f "$ZSHRC_FILE" ]; then
        # stat 命令需要由能够读取文件的用户执行。root可以，但让用户自己执行更符合逻辑。
        original_perms=$(run_as_user "stat -c %a '$ZSHRC_FILE'")
        if [ -z "$original_perms" ]; then
            log_warn "无法获取 '$ZSHRC_FILE' 的原始权限，将使用默认权限 644。"
            original_perms="644"
        else
            log_notice "记录到 '$ZSHRC_FILE' 的原始权限为: $original_perms"
        fi
        log_info "备份当前的 .zshrc 文件..."
        # local backup_file="${ZSHRC_FILE}.bak_before_template_overwrite_$(date +%Y%m%d_%H%M%S)"
        # run_as_user "cp '$ZSHRC_FILE' '$backup_file'"
        # log_success "已备份到: $backup_file"
        # if ! run_as_user "source '${LIB_DIR}/utils.sh' && create_backup_and_cleanup '$ZSHRC_FILE' 'zshrc_template_overwrite'"; then
        if ! create_backup_and_cleanup "$ZSHRC_FILE" "zshrc_template_overwrite"; then
            log_error "Backup of .zshrc before template overwrite failed. Aborting."
            return 1
        fi
    else
        log_error "当前 '$ZSHRC_FILE' 不存在，无需备份！"
    fi

    log_info "正在从 '$ZSHRC_TEMPLATE_PATH' 复制配置..."
    if cp -a "$ZSHRC_TEMPLATE_PATH" "$ZSHRC_FILE"; then
        # **关键修正：复制后，立即 chown 和恢复/设置权限**
        chown "$ORIGINAL_USER:$ORIGINAL_USER" "$ZSHRC_FILE" &&
        run_as_user "chmod '$original_perms' '$ZSHRC_FILE'"
        log_success "成功使用模板文件覆盖 .zshrc 并设置权限为 $original_perms。"
    else
        log_error "从模板文件复制到 '$ZSHRC_FILE' 失败！"
        return 1
    fi
}


# ==============================================================================
# .zshrc 配置协调函数 (安全事务模型)
# ==============================================================================

# _run_configuration()
# @description 主协调函数，使用安全的文件更新策略来调用所有 .zshrc 的配置任务。
_run_configuration() {
    display_header_section "逐步配置 .zshrc 文件" "box" 80
    
    # --- 步骤 1: 前置检查、获取原始权限、备份 ---
    if [ ! -f "$ZSHRC_FILE" ]; then
        if [ ! -d "${ORIGINAL_HOME}/.oh-my-zsh/templates" ]; then log_error "Oh My Zsh 模板目录不存在，无法创建 .zshrc。"; return 1; fi
        log_info "$ZSHRC_FILE 不存在，将从模板创建。";
        run_as_user "cp '${ORIGINAL_HOME}/.oh-my-zsh/templates/zshrc.zsh-template' '$ZSHRC_FILE'" || { log_error "创建 .zshrc 失败！"; return 1; }
    fi

    # **新增：获取原始文件的权限**
    local original_perms
    # stat 命令需要由能够读取文件的用户执行。root可以，但让用户自己执行更符合逻辑。
    original_perms=$(run_as_user "stat -c %a '$ZSHRC_FILE'")
    if [ -z "$original_perms" ]; then
        log_warn "无法获取 '$ZSHRC_FILE' 的原始权限，将使用默认权限 644。"
        original_perms="644"
    else
        log_notice "记录到 '$ZSHRC_FILE' 的原始权限为: $original_perms"
    fi
    # log_info "备份当前 .zshrc 文件..."; local backup_file="${ZSHRC_FILE}.bak.$(date +%Y%m%d_%H%M%S)"; run_as_user "cp '$ZSHRC_FILE' '$backup_file'"; log_success "已备份到: $backup_file"
    # *** 新的、简洁的备份调用 ***
    # 我们需要在普通用户有权限读取 .zshrc 的情况下调用备份
    # 所以我们使用 run_as_user 来执行 create_backup_and_cleanup
    # create_backup_and_cleanup 内部的 cp 将由普通用户执行
    # if ! run_as_user "source '${LIB_DIR}/utils.sh' && create_backup_and_cleanup '$ZSHRC_FILE' 'zshrc'"; then
    if ! create_backup_and_cleanup "$ZSHRC_FILE" "zshrc"; then
         log_error "Backup of .zshrc failed. Aborting configuration."
         return 1
    fi

    # --- 步骤 2: 创建一个临时工作副本 ---
    local temp_zshrc; temp_zshrc=$(run_as_user "mktemp")
    if [ -z "$temp_zshrc" ]; then log_error "无法为 .zshrc 创建临时工作文件！"; return 1; fi
    run_as_user "cp -p '$ZSHRC_FILE' '$temp_zshrc'"; log_info "创建临时工作文件: $temp_zshrc"

    # --- 步骤 3: 在临时副本上执行所有修改 ---
    local config_ok=true
    if ! _configure_p10k_instant_prompt "$temp_zshrc"; then config_ok=false; fi
    if ! _configure_zsh_theme "$temp_zshrc"; then config_ok=false; fi
    if ! _configure_plugins_line "$temp_zshrc"; then config_ok=false; fi
    if ! _configure_fzf_tab "$temp_zshrc"; then config_ok=false; fi
    if ! _configure_aliases "$temp_zshrc"; then config_ok=false; fi
    if ! _configure_p10k_init "$temp_zshrc"; then config_ok=false; fi

    # --- 步骤 4: 如果所有修改都成功，则“提交”更改并恢复权限 ---
    if $config_ok; then
        log_info "所有配置已成功应用到临时文件，现在替换原始 .zshrc ..."
        
        # **关键修正：在移动文件后，恢复记录下来的原始权限**
        if run_as_user "
            mv '$temp_zshrc' '$ZSHRC_FILE' &&
            chmod '$original_perms' '$ZSHRC_FILE'
        "; then
            log_success "成功更新 .zshrc 文件并恢复原始权限为 $original_perms。"
        else
            log_error "最终替换或恢复 .zshrc 文件权限失败！"
            log_error "原始文件可能已被一个权限不正确的文件替换。请检查 '$ZSHRC_FILE'。"
            return 1
        fi
    else
        log_error "在修改 .zshrc 的过程中发生错误。原始文件未被修改。"; run_as_user "rm '$temp_zshrc'"; return 1
    fi
}


# ==============================================================================
# .zshrc 具体配置函数 (接收临时文件路径作为参数)
# ==============================================================================

_configure_p10k_instant_prompt() {
    local target_file="$1"
    log_info "检查并配置 Powerlevel10k Instant Prompt..."; if ! _is_p10k_theme_installed; then log_info "Powerlevel10k 未安装，跳过。"; return 0; fi

    if ! run_as_user "grep -q 'p10k-instant-prompt' '$target_file'"; then
        log_notice "在 .zshrc 顶部添加 Instant Prompt 配置..."
        
        local p10k_block_file; p10k_block_file=$(mktemp)
        cat > "$p10k_block_file" <<'EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

EOF
        chown "$ORIGINAL_USER:$ORIGINAL_USER" "$p10k_block_file"

        if ! run_as_user "
            temp_combined_file=\$(mktemp)
            cat '$p10k_block_file' '$target_file' > \"\$temp_combined_file\" &&
            mv \"\$temp_combined_file\" '$target_file' &&
            rm '$p10k_block_file'
        "; then
            log_error "添加 Instant Prompt 配置失败！"
            rm -f "$p10k_block_file"
            return 1
        fi
    else
      log_info "Instant Prompt 配置已存在，跳过。"
    fi
}

_configure_zsh_theme() {
    local target_file="$1"
    log_info "检查并配置 Zsh 主题..."; if ! _is_p10k_theme_installed; then log_info "Powerlevel10k 未安装，跳过。"; return 0; fi
    run_as_user "sed -i 's|^\\s*ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|' '$target_file'"
}

_configure_plugins_line() {
    local target_file="$1"
    log_info "检查并配置 Oh My Zsh 插件列表..."; local desired_plugins=("git" "sudo")
    if is_package_installed "fzf"; then desired_plugins+=("fzf"); fi
    if _is_omz_plugin_installed "fzf-tab"; then desired_plugins+=("fzf-tab"); fi
    if _is_omz_plugin_installed "zsh-autosuggestions"; then desired_plugins+=("zsh-autosuggestions"); fi
    if _is_omz_plugin_installed "zsh-syntax-highlighting"; then desired_plugins+=("zsh-syntax-highlighting"); fi
    log_info "将启用的插件: ${desired_plugins[*]}"; local plugins_str="plugins=(${desired_plugins[*]})"
    if run_as_user "grep -q '^\\s*plugins=(' '$target_file'"; then
        run_as_user "sed -i 's|^\\s*plugins=(.*)|$plugins_str|' '$target_file'"
    else
        run_as_user "echo -e '\n$plugins_str' >> '$target_file'"
    fi
}

_configure_fzf_tab() {
    local target_file="$1"
    log_info "检查并配置 fzf-tab 高级选项..."; if ! _is_omz_plugin_installed "fzf-tab"; then log_info "fzf-tab 未安装，跳过。"; return 0; fi

    if ! run_as_user "grep -q 'fzf-tab:complete' '$target_file'"; then
        log_notice "添加 fzf-tab 的高级 zstyle 配置..."

        local fzf_block_file; fzf_block_file=$(mktemp)
        cat > "$fzf_block_file" <<'EOF'

# fzf-tab configuration (added by script)
zstyle ':fzf-tab:*' fzf-flags --height=60% --border --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \
    --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \
    --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796

zstyle ':fzf-tab:complete:*:*' fzf-preview '
  (bat --color=always --line-range :500 ${realpath} 2>/dev/null ||
   eza -al --git --icons ${realpath} 2>/dev/null ||
   ls -lAh --color=always ${realpath}) 2>/dev/null'
# End fzf-tab configuration
EOF
        chown "$ORIGINAL_USER:$ORIGINAL_USER" "$fzf_block_file"

        if ! run_as_user "
            cat '$fzf_block_file' >> '$target_file' &&
            rm '$fzf_block_file'
        "; then
            log_error "添加 fzf-tab 高级配置失败！"
            rm -f "$fzf_block_file"
            return 1
        fi
    else
      log_info "fzf-tab 高级配置已存在，跳过。"
    fi
}

_configure_aliases() {
    local target_file="$1"
    log_info "检查并配置常用别名和环境变量..."
    
    if is_package_installed "eza" && ! run_as_user "grep -q \"# eza aliases\" '$target_file'"; then
        log_notice "添加 eza 别名..."
        local eza_aliases_block="# eza aliases
alias ls='eza --icons'
alias l='eza -l'
alias la='eza -a --icons'
alias ll='eza -al --git --icons'
alias tree='eza --tree'"
        run_as_user "echo -e '\n' >> '$target_file' && printf '%s\n' '$eza_aliases_block' >> '$target_file'"
    fi

    if is_package_installed "bat" && ! run_as_user "grep -q \"# bat alias and theme\" '$target_file'"; then
        log_notice "添加 bat 别名和主题..."
        local bat_config_block="# bat alias and theme
alias cat='bat --paging=never'
export BAT_THEME=\"TwoDark\""
        run_as_user "echo -e '\n' >> '$target_file' && printf '%s\n' '$bat_config_block' >> '$target_file'"
    fi

    if is_package_installed "fzf" && ! run_as_user "grep -q \"# fzf default options\" '$target_file'"; then
        log_notice "添加 fzf 默认选项..."
        local fzf_opts_block="# fzf default options
export FZF_DEFAULT_OPTS=\"--height 40% --layout=reverse --border\""
        run_as_user "echo -e '\n' >> '$target_file' && printf '%s\n' '$fzf_opts_block' >> '$target_file'"
    fi
}

_configure_p10k_init() {
    local target_file="$1"
    log_info "检查并配置 Powerlevel10k 初始化脚本..."; if ! _is_p10k_theme_installed; then log_info "Powerlevel10k 未安装，跳过。"; return 0; fi
    local p10k_init_block="# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh.\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh"
    if ! run_as_user "grep -q 'source ~/.p10k.zsh' '$target_file'"; then run_as_user "echo -e '\n$p10k_init_block' >> '$target_file'"; fi
}


# ==============================================================================
# 安装后指导函数
# ==============================================================================
_run_post_install_checks() {
    display_header_section "后续步骤和建议" "box" 80 "${COLOR_CYAN}"
    log_summary "Zsh 环境配置已完成！" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "1. 更改默认 Shell:"; log_summary "   要将 Zsh 设为默认 Shell，请运行以下命令:"; log_summary "   chsh -s $(command -v zsh) $ORIGINAL_USER"; log_summary "   更改后需要重新登录才能生效。" "" "${COLOR_YELLOW}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "2. 应用配置:"; log_summary "   重新启动终端，或在当前终端运行 'source ~/.zshrc'。"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "3. Powerlevel10k 个性化:"; log_summary "   首次启动 Zsh 时，Powerlevel10k 可能会自动运行配置向导。"; log_summary "   您也可以随时手动运行 'p10k configure' 来重新配置。" "" "${COLOR_YELLOW}"
    log_summary "--------------------------------------------------" "" "${COLOR_CYAN}"
    log_summary "4. 终端字体:"; log_summary "   请确保您的终端模拟器已设置为使用 'MesloLGS NF' 字体。"
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
        log_warn "用户取消操作。"; exit 0
    fi

    # --- 安装阶段 ---
    if _perform_checks; then
        if [[ "$INSTALL_MODE" == "skip" ]]; then
            log_info "环境检查完毕，跳过安装步骤。"
        else
            log_info "环境检查完毕，所有组件已安装。"
        fi
    else
        if [[ -n "$INSTALL_MODE" ]]; then
            _run_installation
        fi
    fi

    # --- 配置阶段 ---
    local config_choice
    while true; do
        log_info "请选择 .zshrc 的配置方式:"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 逐步、安全地修改现有 .zshrc 文件 (推荐)"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 从预设模板快速覆盖 .zshrc 文件 (警告: 将丢失现有配置)"
        echo -e "  ${COLOR_RED}c.${COLOR_RESET} 跳过配置"
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 (1/2/c): ${COLOR_RESET}")" config_choice; echo
        
        case "$config_choice" in
            1)
                if ! _run_configuration; then
                    handle_error "逐步配置 .zshrc 过程中发生严重错误，已中止。" 1
                fi
                break
                ;;
            2)
                if ! _configure_from_template; then
                     handle_error "从模板配置 .zshrc 过程中发生错误，已中止。" 1
                fi
                break
                ;;
            c|C)
                log_info "用户选择跳过 .zshrc 配置。"
                break
                ;;
            *)
                log_warn "无效输入，请输入 1, 2 或 c。"
                ;;
        esac
    done
    
    # --- 指导阶段 ---
    _run_post_install_checks

    log_success "Zsh 环境配置模块执行完毕！"
}

# --- 脚本入口 ---
main "$@"
exit 0