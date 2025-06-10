#!/bin/bash

# 01_configure_shell.sh
# 美化终端、设置 Shell 的原子功能脚本。

# 通用初始化块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT=""
current_dir="$SCRIPT_DIR"
while [[ "$current_dir" != "/" && ! -d "$current_dir/config" ]]; do
    current_dir="$(dirname "$current_dir")"
done
if [[ -d "$current_dir/config" ]]; then
    PROJECT_ROOT="$current_dir"
else
    echo "错误：无法找到项目根目录 (包含 config 目录)。" >&2
    exit 1
fi
source "$PROJECT_ROOT/config/main_config.sh"
source "$PROJECT_ROOT/config/lib/utils.sh"
get_original_user_info # 获取原始用户信息

configure_shell() {
    log_info "正在配置 Shell..."

    if [[ -z "$ORIGINAL_USER_HOME" ]]; then
        log_error "无法确定原始用户家目录，跳过 Shell 配置。"
        return 1
    fi

    local shell_choice=$(dialog --clear \
                                --backtitle "Arch Linux 后安装脚本" \
                                --title "Shell 配置" \
                                --menu "选择您想配置的 Shell:" 10 50 3 \
                                "1" "Zsh" \
                                "2" "Bash" \
                                "B" "返回" \
                                2>&1 >/dev/tty)

    case "$shell_choice" in
        1)
            log_info "配置 Zsh..."
            if ! command -v zsh &> /dev/null; then
                log_warn "Zsh 未安装。尝试安装..."
                if ! pacman -S --noconfirm zsh; then
                    log_error "无法安装 Zsh。请手动安装后重试。"
                    return 1
                fi
            fi

            if confirm_action "是否将 Zsh 设置为默认 Shell？"; then
                chsh -s /bin/zsh "$ORIGINAL_USER_NAME"
                if [[ $? -eq 0 ]]; then
                    log_success "Zsh 已设置为 ${ORIGINAL_USER_NAME} 的默认 Shell。"
                else
                    log_error "设置 Zsh 为默认 Shell 失败。"
                fi
            fi

            log_info "将 zshrc_snippet.txt 内容添加到 ~/.zshrc..."
            run_as_original_user "cat \"$PROJECT_ROOT/config/assets/shell/zshrc_snippet.txt\" >> \"$ORIGINAL_USER_HOME/.zshrc\""
            if [[ $? -eq 0 ]]; then
                log_success "zshrc_snippet.txt 内容已添加到 ~/.zshrc。"
            else
                log_error "添加 zshrc_snippet.txt 内容到 ~/.zshrc 失败。"
            fi
            ;;
        2)
            log_info "配置 Bash..."
            log_warn "Bash 配置示例暂未提供，请手动配置。"
            ;;
        B)
            log_info "返回上一级菜单。"
            return 0
            ;;
        *)
            log_warn "无效选项，请重新选择。"
            ;;
    esac

    log_success "Shell 配置完成。"
}

# 执行函数
configure_shell