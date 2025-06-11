#!/bin/bash

# Source utility functions
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
UTILS_PATH="$SCRIPT_DIR/utils.sh"
if [ ! -f "$UTILS_PATH" ]; then
    echo "错误：无法找到 utils.sh 脚本！路径: $UTILS_PATH"
    exit 1
fi
# shellcheck source=./utils.sh
source "$UTILS_PATH"

# 使用 USER_HOME 定义配置文件路径
ZSHRC_FILE="${USER_HOME}/.zshrc"
P10K_CONFIG_FILE="${USER_HOME}/.p10k.zsh"

# 期望的插件列表 (根据安装的软件动态调整)
# 基础插件 'git' 通常由 oh-my-zsh 默认添加
DESIRED_PLUGINS=("git")

# 配置 Zsh 主题 (Powerlevel10k)
configure_theme() {
    log STEP "配置 Zsh 主题 (Powerlevel10k)..."
    local theme_line='ZSH_THEME="powerlevel10k/powerlevel10k"'

    if [ ! -f "$ZSHRC_FILE" ]; then
        log WARN "$ZSHRC_FILE 文件不存在。可能是 Oh My Zsh 未正确安装或初始化。"
        log INFO "将创建包含 Powerlevel10k 主题设置的 $ZSHRC_FILE。"
        echo "$theme_line" > "$ZSHRC_FILE"
        log INFO "$ZSHRC_FILE 已创建并设置主题。"
        return 0
    fi

    # 检查 ZSH_THEME 是否已设置为 powerlevel10k
    if grep -qE '^\s*ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC_FILE"; then
        log INFO "Powerlevel10k 主题已在 $ZSHRC_FILE 中配置。"
        return 0
    fi

    # 如果 ZSH_THEME 行存在但不是 p10k，则替换它
    if grep -qE '^\s*ZSH_THEME=' "$ZSHRC_FILE"; then
        log INFO "找到现有的 ZSH_THEME 设置，将其更新为 Powerlevel10k。"
        # 使用 sed 进行替换。注意 macOS sed 和 GNU sed 的差异 (-i 参数)
        # 修改文件操作需要在目标用户下进行（如果以 sudo 运行）
        local sed_cmd="sed -i.bak 's|^\\s*ZSH_THEME=.*|$theme_line|' \"$ZSHRC_FILE\""
        local rm_bak_cmd="rm -f \"${ZSHRC_FILE}.bak\""
        local sed_success=false
        if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
             # 确保文件所有权正确
             run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$ZSHRC_FILE" || log WARN "无法更改 $ZSHRC_FILE 的所有权"
             if run_command sudo runuser -l "$ORIGINAL_USER" -c "$sed_cmd"; then
                 sed_success=true
                 run_command sudo runuser -l "$ORIGINAL_USER" -c "$rm_bak_cmd" # 尝试删除备份
             fi
        else
             if run_command sed -i.bak "s|^\\s*ZSH_THEME=.*|$theme_line|" "$ZSHRC_FILE"; then
                 sed_success=true
                 run_command rm -f "${ZSHRC_FILE}.bak" # 删除备份
             fi
        fi

        if $sed_success; then
             log INFO "成功将 ZSH_THEME 更新为 Powerlevel10k。"
             return 0
        else
             log ERROR "使用 sed 更新 ZSH_THEME 失败！请手动修改 $ZSHRC_FILE。"
             # 恢复备份 (如果存在)
             local bak_file="${ZSHRC_FILE}.bak"
             if [ -f "$bak_file" ]; then
                 local mv_cmd="mv \"$bak_file\" \"$ZSHRC_FILE\""
                 if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
                     run_command sudo runuser -l "$ORIGINAL_USER" -c "$mv_cmd"
                 else
                     run_command mv "$bak_file" "$ZSHRC_FILE"
                 fi
             fi
             return 1
        fi
    else
        # 如果 ZSH_THEME 行不存在，则添加到文件末尾
        log INFO "未找到 ZSH_THEME 设置，在 $ZSHRC_FILE 末尾添加 Powerlevel10k 主题设置。"
        local append_cmd="echo -e \"\n# 设置 Powerlevel10k 主题\n$theme_line\" >> \"$ZSHRC_FILE\""
        local append_success=false
         if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
             # 确保文件所有权正确
             run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$ZSHRC_FILE" || log WARN "无法更改 $ZSHRC_FILE 的所有权"
             if run_command sudo runuser -l "$ORIGINAL_USER" -c "$append_cmd"; then
                 append_success=true
             fi
         else
              if echo -e "\n# 设置 Powerlevel10k 主题\n$theme_line" >> "$ZSHRC_FILE"; then
                  append_success=true
              fi
         fi

        if $append_success; then
             log INFO "成功添加 Powerlevel10k 主题设置。"
             return 0
        else
             log ERROR "向 $ZSHRC_FILE 添加 ZSH_THEME 失败！"
             return 1
        fi
    fi
}

# 配置 Oh My Zsh 插件
configure_plugins() {
    log STEP "配置 Oh My Zsh 插件..."

    if [ ! -f "$ZSHRC_FILE" ]; then
        log WARN "$ZSHRC_FILE 文件不存在。无法配置插件。"
        return 1
    fi

    # --- 重新检查插件和工具的安装状态 ---
    log INFO "重新检查需要启用的插件和工具的安装状态..."
    # 基础插件 git 总是需要
    local current_desired_plugins=("git")

    # 检查 OMZ 插件
    if is_omz_plugin_installed "zsh-syntax-highlighting"; then
        log INFO "检测到 zsh-syntax-highlighting 已安装。"
        current_desired_plugins+=("zsh-syntax-highlighting")
    else
        log WARN "zsh-syntax-highlighting 未安装，将不会在 .zshrc 中启用。"
    fi
    if is_omz_plugin_installed "zsh-autosuggestions"; then
        log INFO "检测到 zsh-autosuggestions 已安装。"
        current_desired_plugins+=("zsh-autosuggestions")
    else
        log WARN "zsh-autosuggestions 未安装，将不会在 .zshrc 中启用。"
    fi
     if is_omz_plugin_installed "fzf-tab"; then
        log INFO "检测到 fzf-tab 已安装。"
        current_desired_plugins+=("fzf-tab")
    else
        log WARN "fzf-tab 未安装，将不会在 .zshrc 中启用。"
    fi

    # 检查相关工具 (fzf, bat, eza) 是否安装，决定是否添加它们的 OMZ 插件（如果适用）
    # 注意：OMZ 的 fzf 插件通常用于加载 fzf 的配置和按键绑定
    if command_exists fzf; then
        log INFO "检测到 fzf 命令已安装。"
        current_desired_plugins+=("fzf") # 添加 fzf 插件
    else
         log WARN "fzf 命令未安装，fzf 插件将不会在 .zshrc 中启用。"
    fi
    # bat 和 eza 通常不需要特定的 OMZ 插件来启用，别名在 configure_aliases_and_extras 中处理
    # 但如果将来有需要，可以在这里添加检查

    # 去重 (虽然上面的逻辑应该避免了重复，但保险起见)
    local unique_plugins_str
    # 使用正确填充的 current_desired_plugins 数组进行去重
    unique_plugins_str=$(echo "${current_desired_plugins[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    # !!! 移除下面这行错误的代码，它错误地使用了旧的 DESIRED_PLUGINS 数组 !!!
    # unique_plugins_str=$(echo "${DESIRED_PLUGINS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    # 转换为数组
    read -r -a UNIQUE_DESIRED_PLUGINS <<< "$unique_plugins_str"


    log INFO "期望启用的插件: ${UNIQUE_DESIRED_PLUGINS[*]}"

    local temp_zshrc=$(mktemp)
    local plugins_line_found_in_original=false
    local current_plugins=() # 初始化为空数组
    local added_plugins=()
    local modified=false

    # 尝试使用 grep 查找 plugins 行
    local plugins_line
    plugins_line=$(grep -E '^\s*plugins=\(' "$ZSHRC_FILE")

    if [[ -n "$plugins_line" ]]; then
        plugins_line_found_in_original=true
        # 去掉 plugins=( 和 )，移除行尾注释，提取插件名称
        local plugins_content
        plugins_content=$(echo "$plugins_line" | sed -E 's/^\s*plugins=\(\s*(.*?)\s*\)\s*(#.*)?$/\1/')
        # 按空格分割现有插件
        IFS=' ' read -r -a current_plugins <<< "$plugins_content"
        log INFO "找到现有的插件列表: ${current_plugins[*]}"
    else
        log WARN "未在 $ZSHRC_FILE 中找到有效的 'plugins=(...)' 行。"
        current_plugins=() # 确保是空数组
    fi

    # 添加缺失的期望插件
    for plugin in "${UNIQUE_DESIRED_PLUGINS[@]}"; do
        local found=false
        for existing in "${current_plugins[@]}"; do
            if [[ "$plugin" == "$existing" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            current_plugins+=("$plugin")
            added_plugins+=("$plugin")
            modified=true # 标记需要修改
        fi
    done

    # 如果插件列表有变动或原始文件中没有找到 plugins 行，则需要重写文件
    if $modified || ! $plugins_line_found_in_original; then
        if [ ${#added_plugins[@]} -gt 0 ]; then
             log INFO "添加以下新插件到列表: ${added_plugins[*]}"
        elif ! $plugins_line_found_in_original; then
             log INFO "将在文件末尾添加新的插件列表。"
        else
             log INFO "插件列表无需添加新插件，但可能需要重新格式化或写入。"
        fi

        local new_plugins_line="plugins=(${current_plugins[*]})"
        local processed=false # 标记是否已处理（替换或添加）plugins 行

        # 逐行读取原文件，写入临时文件，并在适当位置替换或添加 plugins 行
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 尝试匹配原始的 plugins 行（即使它格式不规范或有注释）
            if $plugins_line_found_in_original && [[ "$line" == "$plugins_line" ]] && ! $processed; then
                 echo "$new_plugins_line" >> "$temp_zshrc"
                 processed=true
            # 尝试匹配一个更通用的 plugins 行模式，以防原始行被其他方式修改过
            elif [[ "$line" =~ ^\s*plugins=\( ]] && ! $processed; then
                 echo "$new_plugins_line" >> "$temp_zshrc"
                 processed=true
            else
                 # 写入其他行
                 echo "$line" >> "$temp_zshrc"
            fi
        done < "$ZSHRC_FILE"

        # 如果遍历完文件仍未处理（意味着原文件没有找到任何形式的 plugins 行）
        if ! $processed; then
             log INFO "在文件末尾添加新的插件列表: ${current_plugins[*]}"
             echo -e "\n# Oh My Zsh 插件列表 (由脚本添加/更新)" >> "$temp_zshrc"
             echo "$new_plugins_line" >> "$temp_zshrc"
        fi

        # 用修改后的临时文件覆盖原始文件
        # 需要确保目标文件所有权正确
        local mv_cmd="mv \"$temp_zshrc\" \"$ZSHRC_FILE\""
        local chmod_cmd="chmod 644 \"$ZSHRC_FILE\""
        local mv_success=false
        if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
             # 先设置所有权再移动
             run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$temp_zshrc" || log WARN "无法更改临时文件的所有权"
             if run_command sudo runuser -l "$ORIGINAL_USER" -c "$mv_cmd"; then
                 mv_success=true
                 run_command sudo runuser -l "$ORIGINAL_USER" -c "$chmod_cmd" # 设置权限
             fi
        else
             if run_command mv "$temp_zshrc" "$ZSHRC_FILE"; then
                 mv_success=true
                 run_command chmod 644 "$ZSHRC_FILE" # 设置权限
             fi
        fi

        if $mv_success; then
            log INFO "插件配置成功更新到 $ZSHRC_FILE。"
        else
            log ERROR "无法将插件更改写回 $ZSHRC_FILE！"
            rm -f "$temp_zshrc" # 尝试清理临时文件
            return 1
        fi
    else
        log INFO "插件列表已包含所有期望的插件，且无需修改 $ZSHRC_FILE。"
        rm -f "$temp_zshrc" # 清理未使用的临时文件
        return 0
    # 移除多余的 else 块
    # else
    #    log ERROR "无法将更改写回 $ZSHRC_FILE！"
    #    rm -f "$temp_zshrc" # 清理临时文件
    #    return 1
    fi
}

# 添加别名和特定配置
configure_aliases_and_extras() {
    log STEP "配置别名和其他设置..."

    if [ ! -f "$ZSHRC_FILE" ]; then
        log WARN "$ZSHRC_FILE 文件不存在。无法配置别名。"
        return 1
    fi

    local changes_made=false
    local temp_zshrc=$(mktemp)
    cp "$ZSHRC_FILE" "$temp_zshrc" # 复制一份用于修改

    # 检查 bat 是否安装并添加别名
    if command_exists bat || command_exists batcat; then
        local bat_cmd="bat"
        command_exists batcat && bat_cmd="batcat" # 优先使用 batcat 如果存在
        local bat_alias="alias cat='$bat_cmd'"
        if ! grep -qF "$bat_alias" "$temp_zshrc"; then
            log INFO "添加 bat 别名: $bat_alias"
            echo -e "\n# 使用 bat 替代 cat" >> "$temp_zshrc"
            echo "$bat_alias" >> "$temp_zshrc"
            # 可选：添加 bat 主题设置
            local bat_theme_export='export BAT_THEME="TwoDark"' # 或其他主题
             if ! grep -qF 'export BAT_THEME=' "$temp_zshrc"; then
                 echo "$bat_theme_export" >> "$temp_zshrc"
             fi
            changes_made=true
        else
            log INFO "bat 别名已存在。"
        fi
    fi

    # 检查 eza 是否安装并添加别名
    if command_exists eza; then
        local eza_alias_ls="alias ls='eza'"
        local eza_alias_l="alias l='eza -l'"
        local eza_alias_la="alias la='eza -la'"
        local eza_alias_ll="alias ll='eza -l --git --icons'" # 示例：带 git 和图标
        local eza_alias_tree="alias tree='eza --tree'"

        if ! grep -qF "$eza_alias_ls" "$temp_zshrc"; then
            log INFO "添加 eza 别名..."
            echo -e "\n# 使用 eza 替代 ls" >> "$temp_zshrc"
            echo "$eza_alias_ls" >> "$temp_zshrc"
            echo "$eza_alias_l" >> "$temp_zshrc"
            echo "$eza_alias_la" >> "$temp_zshrc"
            echo "$eza_alias_ll" >> "$temp_zshrc"
            echo "$eza_alias_tree" >> "$temp_zshrc"
            changes_made=true
        else
            log INFO "eza 别名似乎已存在。"
        fi
    fi

    # 检查 fzf 是否安装并添加推荐配置
    if command_exists fzf; then
         # fzf 的 Oh My Zsh 插件通常会处理基础配置
         # 但可以添加一些额外的环境变量或按键绑定
         local fzf_options_export='export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"'
         if ! grep -qF 'export FZF_DEFAULT_OPTS=' "$temp_zshrc"; then
             log INFO "添加 FZF 默认选项配置。"
             echo -e "\n# FZF 配置" >> "$temp_zshrc"
             echo "$fzf_options_export" >> "$temp_zshrc"
             changes_made=true
         else
             log INFO "FZF_DEFAULT_OPTS 配置已存在。"
         fi
         # fzf 的按键绑定通常由其安装脚本或插件处理，这里不再添加
         # 例如: source /path/to/fzf/shell/key-bindings.zsh
    fi

    # 检查 fzf-tab 是否安装并添加 zstyle 配置
    if is_omz_plugin_installed "fzf-tab"; then
        log INFO "检测到 fzf-tab 插件已安装，检查其 zstyle 配置..."
        local fzf_tab_config_block="# fzf-tab configuration (added by script)
zstyle ':fzf-tab:*' fzf-flags --height=60% --border --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \\
    --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \\
    --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796

zstyle ':fzf-tab:complete:*:*' fzf-preview '
  (bat --color=always --line-range :500 \${realpath} 2>/dev/null ||
   exa -al --git --icons \${realpath} ||
   ls -lAh --color=always \${realpath}) 2>/dev/null'
# End fzf-tab configuration"

        # 检查配置块是否已存在 (检查第一行特征即可)
        if ! grep -qF "zstyle ':fzf-tab:*' fzf-flags" "$temp_zshrc"; then
            log INFO "添加 fzf-tab 的 zstyle 配置..."
            echo -e "\n${fzf_tab_config_block}" >> "$temp_zshrc"
            changes_made=true
        else
            log INFO "fzf-tab 的 zstyle 配置似乎已存在。"
        fi
    fi


    # 如果做了修改，则替换原文件
    if $changes_made; then
        if mv "$temp_zshrc" "$ZSHRC_FILE"; then
            log INFO "别名和其他配置成功更新到 $ZSHRC_FILE。"
            chmod 644 "$ZSHRC_FILE"
            return 0
        else
            log ERROR "无法将别名更改写回 $ZSHRC_FILE！"
            rm -f "$temp_zshrc"
            return 1
        fi
    else
        log INFO "无需添加新的别名或额外配置。"
        rm -f "$temp_zshrc" # 清理临时文件
        return 0
    fi
}


# 主配置函数
run_configuration() {
    log STEP "开始配置 Zsh 环境 (目标: $ZSHRC_FILE)..."

    # 备份 .zshrc
    # backup_file 内部需要处理 sudo
    if ! backup_file "$ZSHRC_FILE"; then
        log ERROR "备份 $ZSHRC_FILE 失败！配置中止。"
        return 1
    fi

    # 备份 .p10k.zsh (如果存在)
    backup_file "$P10K_CONFIG_FILE"

    # 确保 .zshrc 文件存在且所有权正确（如果 sudo）
    if [ ! -f "$ZSHRC_FILE" ]; then
        log INFO "$ZSHRC_FILE 不存在，将创建它。"
        touch "$ZSHRC_FILE" || { log ERROR "创建 $ZSHRC_FILE 失败！"; return 1; }
    fi
    if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
        run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$ZSHRC_FILE" || log WARN "无法设置 $ZSHRC_FILE 的所有权"
        if [ -f "$P10K_CONFIG_FILE" ]; then
             run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$P10K_CONFIG_FILE" || log WARN "无法设置 $P10K_CONFIG_FILE 的所有权"
        fi
    fi


    local config_ok=true

    # 配置主题
    if ! configure_theme; then
        config_ok=false
    fi

    # 配置插件
    if ! configure_plugins; then
        config_ok=false
    fi

    # 配置别名和其他
    if ! configure_aliases_and_extras; then
        config_ok=false
    fi

    if $config_ok; then
        log INFO "Zsh 配置完成。请重新启动 Zsh 或运行 'source ~/.zshrc' 来应用更改。"
        # 提示用户运行 p10k configure
        if command_exists p10k; then
             log INFO "Powerlevel10k 已安装。为了获得最佳体验，建议运行 'p10k configure' 进行个性化配置。"
        fi
        return 0
    else
        log ERROR "Zsh 配置过程中遇到错误。请检查上面的日志并手动检查 $ZSHRC_FILE 文件。"
        return 1
    fi
}

# 如果直接运行此脚本，则执行配置 (需要先手动设置环境变量进行测试)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 用于测试 ---
    echo "直接运行 config.sh 进行测试..."
    # 模拟 check.sh 的导出结果 (假设所有都安装了)
    export CHECK_RESULTS_EXPORT="CHECK_RESULTS[zsh]='已安装' CHECK_RESULTS[fzf]='已安装' CHECK_RESULTS[bat]='已安装' CHECK_RESULTS[eza]='已安装' CHECK_RESULTS[git]='已安装' CHECK_RESULTS[curl]='已安装' CHECK_RESULTS[wget]='已安装' CHECK_RESULTS[oh-my-zsh]='已安装' CHECK_RESULTS[zsh-syntax-highlighting]='已安装' CHECK_RESULTS[zsh-autosuggestions]='已安装' CHECK_RESULTS[fzf-tab]='已安装' CHECK_RESULTS[powerlevel10k]='已安装' CHECK_RESULTS[meslolgs-font]='已安装'"
    run_configuration
    # --- 测试结束 ---
fi
