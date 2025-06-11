## fzf配置

```bash
# fzf-tab configuration
# 终极配置方案（添加至 ~/.zshrc）
zstyle ':fzf-tab:*' fzf-flags --height=60% --border --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \
    --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \
    --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796

zstyle ':fzf-tab:complete:*:*' fzf-preview '
  (bat --color=always --line-range :500 ${realpath} 2>/dev/null ||
   exa -al --git --icons ${realpath} ||
   ls -lAh --color=always ${realpath}) 2>/dev/null'
```

## p10k

```bash
# 顶部添加
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# 底部添加
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
```

## 动态添加plugins=(git)

```bash
# 读取当前的 plugins 配置
            local plugins_line=$(grep '^plugins=(' "$ZSHRC")
            if [[ -n "$plugins_line" ]]; then
                # 去掉 plugins=( 和 )，并将插件名称提取到数组中
                local plugins_content=$(echo "$plugins_line" | sed -E 's/^plugins=\((.*)\)/\1/')
                IFS=' ' read -r -a current_plugins <<< "$plugins_content"
            else
                # 如果没有找到 plugins=，则初始化为空数组
                current_plugins=()
            fi

            # 添加新的插件到数组中
            for plugin in "${!PLUGINS[@]}"; do
                if [[ ! " ${current_plugins[@]} " =~ " ${plugin} " ]]; then
                    current_plugins+=("$plugin")
                fi
            done

            # 更新 plugins 配置
            local updated_plugins_line="plugins=(${current_plugins[*]})"
            # 替换旧的 plugins 配置行
            if [[ -n "$plugins_line" ]]; then
                sed -i "s/^plugins=(.*)/$updated_plugins_line/" "$ZSHRC"
            else
                echo "$updated_plugins_line" >> "$ZSHRC"
            fi
```

## 动态删除plugins=(git)

```bash
# 读取当前的 plugins 配置
            local plugins_line=$(grep '^plugins=(' "$ZSHRC")
            if [[ -n "$plugins_line" ]]; then
                # 去掉 plugins=( 和 )，并将插件名称提取到数组中
                # 替换原有字符串处理逻辑
                local plugins_content=$(echo "$plugins_line" | sed -E 's/^plugins=\((.*)\)/\1/')
                IFS=' ' read -r -a current_plugins <<< "$plugins_content"
                # 移除已卸载的插件
                for plugin in "${!PLUGINS[@]}"; do
                    current_plugins=("${current_plugins[@]/$plugin}")
                done
                # 更新 plugins 配置
                local updated_plugins_line="plugins=(${current_plugins[*]})"
                # 替换旧的 plugins 配置行
                sed -i "s/^plugins=(.*)/$updated_plugins_line/" "$ZSHRC"
            fi
```

