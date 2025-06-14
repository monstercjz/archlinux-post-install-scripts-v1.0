#!/bin/bash

# Source utility functions and potentially check.sh for check_item function
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
UTILS_PATH="$SCRIPT_DIR/utils.sh"
CHECK_PATH="$SCRIPT_DIR/check.sh" # Need check_item and SOFTWARE_CHECKS definition

if [ ! -f "$UTILS_PATH" ]; then
    echo "错误：无法找到 utils.sh 脚本！路径: $UTILS_PATH"
    exit 1
fi
# shellcheck source=./utils.sh
source "$UTILS_PATH"

if [ ! -f "$CHECK_PATH" ]; then
    echo "错误：无法找到 check.sh 脚本！路径: $CHECK_PATH"
    exit 1
fi
# shellcheck source=./check.sh
# Source check.sh carefully, avoid re-running its main logic if it has guards
# We mainly need the SOFTWARE_CHECKS definition and check_item function
# Let's redefine SOFTWARE_CHECKS here to be safe, or ensure check.sh sourcing is safe
declare -A SOFTWARE_CHECKS
SOFTWARE_CHECKS=(
    ["zsh"]="zsh"
    ["fzf"]="fzf"
    ["bat"]="bat" # Or batcat
    ["eza"]="eza"
    ["git"]="git" # Dependency
    ["curl"]="curl" # Dependency
    ["wget"]="wget" # Dependency
    ["oh-my-zsh"]="$HOME/.oh-my-zsh"
    ["zsh-syntax-highlighting"]="zsh-syntax-highlighting"
    ["zsh-autosuggestions"]="zsh-autosuggestions"
    ["fzf-tab"]="fzf-tab"
    ["powerlevel10k"]="powerlevel10k"
    ["meslolgs-font"]="MesloLGS"
)
# We also need the check_item function, is_omz_plugin_installed, etc.
# Sourcing check.sh should provide them if it's written correctly.
source "$CHECK_PATH"

# 使用 USER_HOME 定义配置文件路径
ZSHRC_FILE="${USER_HOME}/.zshrc"
P10K_CONFIG_FILE="${USER_HOME}/.p10k.zsh" # 虽然不直接修改，但检查时可能用到

# 验证安装和配置状态
verify_installation() {
    log STEP "开始验证安装和配置状态..."
    local all_verified=true
    declare -A VERIFICATION_RESULTS

    # 重新检查所有项目
    log INFO "重新检查软件和插件安装状态..."
    for key in "${!SOFTWARE_CHECKS[@]}"; do
        # Reuse check_item from check.sh
        if check_item "$key"; then
             # Handle bat/batcat case again if needed
             if [ "$key" == "bat" ] && [[ "${CHECK_RESULTS[$key]}" == *"batcat"* ]]; then
                 VERIFICATION_RESULTS["$key"]="已安装 (batcat)"
             elif [[ "${CHECK_RESULTS[$key]}" == *"可能已安装"* ]]; then
                 VERIFICATION_RESULTS["$key"]="可能已安装 (请手动确认)"
             else
                 VERIFICATION_RESULTS["$key"]="已安装"
             fi
        else
            VERIFICATION_RESULTS["$key"]="验证失败 (未安装或检查出错)"
            all_verified=false
        fi
    done

    # 检查 .zshrc 配置
    log INFO "检查 .zshrc 配置..."
    if [ ! -f "$ZSHRC_FILE" ]; then
        VERIFICATION_RESULTS[".zshrc"]="验证失败 (文件不存在)"
        all_verified=false
    else
        local zshrc_ok=true
        # 检查主题
        if ! grep -qE '^\s*ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC_FILE"; then
            log WARN ".zshrc 中未正确配置 Powerlevel10k 主题。"
            VERIFICATION_RESULTS["ZSH_THEME"]="验证失败 (未设置为 p10k)"
            zshrc_ok=false
        else
             VERIFICATION_RESULTS["ZSH_THEME"]="已配置"
        fi

        # 检查插件 (检查几个关键插件是否在 plugins=() 中)
        local plugins_line
        plugins_line=$(grep -E '^\s*plugins=\(' "$ZSHRC_FILE")
        local missing_rc_plugins=()
        if [ -n "$plugins_line" ]; then
             VERIFICATION_RESULTS["plugins_line"]="存在"
             # Check for specific plugins expected to be enabled
             local expected_rc_plugins=("git" "zsh-syntax-highlighting" "zsh-autosuggestions" "fzf" "fzf-tab")
             for plugin in "${expected_rc_plugins[@]}"; do
                 # Only check if the plugin itself was verified as installed
                 if [[ "${VERIFICATION_RESULTS[$plugin]}" == "已安装" ]] || \
                    [[ "$plugin" == "git" && "${VERIFICATION_RESULTS[git]}" == "已安装" ]] || \
                    [[ "$plugin" == "zsh-syntax-highlighting" && "${VERIFICATION_RESULTS[zsh-syntax-highlighting]}" == "已安装" ]] || \
                    [[ "$plugin" == "zsh-autosuggestions" && "${VERIFICATION_RESULTS[zsh-autosuggestions]}" == "已安装" ]] || \
                    [[ "$plugin" == "fzf" && "${VERIFICATION_RESULTS[fzf]}" == "已安装" ]] || \
                    [[ "$plugin" == "fzf-tab" && "${VERIFICATION_RESULTS[fzf-tab]}" == "已安装" ]] ; then

                     # --- 更可靠的插件检查 ---
                     # 1. 提取括号内的内容
                     local plugins_content
                     plugins_content=$(echo "$plugins_line" | sed -E 's/^\s*plugins=\(\s*(.*?)\s*\)\s*(#.*)?$/\1/')
                     # 2. 将内容读入数组
                     local enabled_plugins_array=()
                     IFS=' ' read -r -a enabled_plugins_array <<< "$plugins_content"
                     # 3. 检查插件是否存在于数组中
                     local plugin_found_in_rc=false
                     for enabled_plugin in "${enabled_plugins_array[@]}"; do
                         if [[ "$plugin" == "$enabled_plugin" ]]; then
                             plugin_found_in_rc=true
                             break
                         fi
                     done

                     if ! $plugin_found_in_rc; then
                         log WARN "插件 '$plugin' 已安装但似乎未在 .zshrc 的 plugins=(...) 数组中启用。"
                         missing_rc_plugins+=("$plugin")
                         zshrc_ok=false
                     # else
                         # log INFO "插件 '$plugin' 已在 .zshrc 中启用。" # 可选的成功日志
                     fi
                 fi
             done
             if [ ${#missing_rc_plugins[@]} -gt 0 ]; then
                 VERIFICATION_RESULTS["enabled_plugins"]="验证失败 (缺少: ${missing_rc_plugins[*]})"
             else
                 VERIFICATION_RESULTS["enabled_plugins"]="已配置"
             fi
        else
            log WARN ".zshrc 中未找到 'plugins=(...)' 行。"
            VERIFICATION_RESULTS["plugins_line"]="验证失败 (未找到)"
            zshrc_ok=false
        fi

        # 检查别名 (检查一个代表性的别名)
        if command_exists eza && ! grep -q "alias ls='eza'" "$ZSHRC_FILE"; then
             log WARN ".zshrc 中缺少 eza 的 'ls' 别名。"
             VERIFICATION_RESULTS["aliases"]="验证失败 (缺少 eza 别名)"
             zshrc_ok=false
        elif command_exists bat && ! grep -q "alias cat='bat" "$ZSHRC_FILE" && ! grep -q "alias cat='batcat" "$ZSHRC_FILE"; then
             log WARN ".zshrc 中缺少 bat/batcat 的 'cat' 别名。"
             VERIFICATION_RESULTS["aliases"]="验证失败 (缺少 bat/cat 别名)"
             zshrc_ok=false
        else
             VERIFICATION_RESULTS["aliases"]="已配置 (部分检查)"
        fi

        if $zshrc_ok; then
             VERIFICATION_RESULTS[".zshrc"]="验证成功"
        else
             all_verified=false
             # Keep the detailed results from above
        fi
    fi

    # 显示验证结果
    echo "----------------------------------------"
    echo " 验证结果:"
    echo "----------------------------------------"
    printf "%-30s %s\n" "项目" "状态"
    echo "----------------------------------------"
    # Print software/plugin checks first
    for key in "${!SOFTWARE_CHECKS[@]}"; do
         printf "%-30s %s\n" "$key" "${VERIFICATION_RESULTS[$key]:-未检查}"
    done
    # Print config checks
    printf "%-30s %s\n" ".zshrc 文件" "${VERIFICATION_RESULTS[".zshrc"]:-未检查}"
    if [ -n "${VERIFICATION_RESULTS[".zshrc"]}" ] && [[ "${VERIFICATION_RESULTS[".zshrc"]}" != "验证成功" ]]; then
        printf "%-30s %s\n" "  - ZSH_THEME" "${VERIFICATION_RESULTS[ZSH_THEME]:-未检查}"
        printf "%-30s %s\n" "  - plugins=(...)" "${VERIFICATION_RESULTS[plugins_line]:-未检查}"
        if [[ "${VERIFICATION_RESULTS[enabled_plugins]}" == *"失败"* ]]; then
             printf "%-30s %s\n" "    - 启用的插件" "${VERIFICATION_RESULTS[enabled_plugins]}"
        fi
         if [[ "${VERIFICATION_RESULTS[aliases]}" == *"失败"* ]]; then
             printf "%-30s %s\n" "  - 别名" "${VERIFICATION_RESULTS[aliases]}"
         fi
    fi
    echo "----------------------------------------"


    if $all_verified; then
        log INFO "所有主要项目已成功安装和配置！"
        return 0
    else
        log WARN "部分项目未能成功验证。请检查上面的日志。"
        return 1
    fi
}

# 提供最终用户指导
provide_guidance() {
    log STEP "后续步骤和建议"

    echo ""
    log INFO "1. 应用更改:"
    log INFO "   请重新启动您的终端，或者在当前 Zsh 会话中运行以下命令来加载新的配置:"
    echo "     source ~/.zshrc"
    echo ""

    log INFO "2. Powerlevel10k 配置:"
    if command_exists p10k; then
        log INFO "   Powerlevel10k 主题已安装。为了获得最佳视觉效果和个性化提示符，强烈建议运行配置向导:"
        echo "     p10k configure"
        log INFO "   该向导将引导您完成字体检查和样式选择。"
    else
        log WARN "   未检测到 p10k 命令，Powerlevel10k 可能未正确安装或配置。"
    fi
    echo ""

    log INFO "3. 终端字体设置:"
    if [[ "${VERIFICATION_RESULTS[meslolgs-font]}" == *"安装"* ]]; then # Check if font installation was attempted/verified
        log INFO "   脚本已尝试安装 'MesloLGS NF' 字体。请确保在您的终端模拟器 (例如 GNOME Terminal, Konsole, iTerm2, Windows Terminal) 的设置中选择此字体。"
        log INFO "   如果字体未显示或字符显示不正确 (例如出现方框或问号)，请确保:"
        log INFO "     a) 字体已成功安装 (您可能需要重启系统或运行 'fc-cache -fv' (仅Linux))。"
        log INFO "     b) 您已在终端的配置文件中正确选择了 'MesloLGS NF' 或类似名称的字体。"
        log INFO "     c) 您的终端支持 Nerd Fonts 或 Powerline 符号。"
    else
        log INFO "   未安装或验证 MesloLGS 字体。如果您打算使用 Powerlevel10k，请手动安装推荐字体并配置终端。"
    fi
    echo ""

    log INFO "4. 检查配置文件:"
    log INFO "   您可以检查 '$ZSHRC_FILE' 文件以查看所做的更改。备份文件位于 '${ZSHRC_FILE}.backup_...'。"
    if [ -f "$P10K_CONFIG_FILE" ]; then
        log INFO "   Powerlevel10k 的配置文件位于 '$P10K_CONFIG_FILE'。"
    fi
    echo ""

    log INFO "5. 享受您的新 Zsh 环境！"
    echo ""
}

# 主函数
run_post_install_checks() {
    if verify_installation; then
        provide_guidance
        return 0
    else
        log ERROR "安装或配置验证失败。请仔细检查日志以了解详细信息。"
        provide_guidance # 仍然提供指导，因为部分可能成功了
        return 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 用于测试 ---
    echo "直接运行 post_install.sh 进行测试..."
    # 模拟 check.sh 的导出结果 (假设所有都安装了)
    export CHECK_RESULTS_EXPORT="CHECK_RESULTS[zsh]='已安装' CHECK_RESULTS[fzf]='已安装' CHECK_RESULTS[bat]='已安装' CHECK_RESULTS[eza]='已安装' CHECK_RESULTS[git]='已安装' CHECK_RESULTS[curl]='已安装' CHECK_RESULTS[wget]='已安装' CHECK_RESULTS[oh-my-zsh]='已安装' CHECK_RESULTS[zsh-syntax-highlighting]='已安装' CHECK_RESULTS[zsh-autosuggestions]='已安装' CHECK_RESULTS[fzf-tab]='已安装' CHECK_RESULTS[powerlevel10k]='已安装' CHECK_RESULTS[meslolgs-font]='已安装'"
    # 确保 .zshrc 文件存在且包含一些预期的内容用于测试
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' > ~/.zshrc
    echo 'plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf fzf-tab)' >> ~/.zshrc
    echo "alias ls='eza'" >> ~/.zshrc
    echo "alias cat='bat'" >> "$ZSHRC_FILE" # Use variable

    run_post_install_checks
    # --- 测试结束 ---
fi
