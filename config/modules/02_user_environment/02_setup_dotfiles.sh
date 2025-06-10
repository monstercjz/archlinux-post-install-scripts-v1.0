#!/bin/bash

# 02_setup_dotfiles.sh
# 自动部署 dotfiles 的原子功能脚本。

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

setup_dotfiles() {
    log_info "正在设置 Dotfiles..."

    if [[ -z "$ORIGINAL_USER_HOME" ]]; then
        log_error "无法确定原始用户家目录，跳过 Dotfiles 设置。"
        return 1
    fi

    local dotfiles_source_dir="$PROJECT_ROOT/config/assets/dotfiles"

    if [[ ! -d "$dotfiles_source_dir" ]]; then
        log_warn "Dotfiles 资产目录不存在: $dotfiles_source_dir。跳过 Dotfiles 设置。"
        return 0
    fi

    log_info "将 $dotfiles_source_dir 中的 dotfiles 部署到 $ORIGINAL_USER_HOME..."

    # 示例：遍历 dotfiles 目录并复制或链接
    # 实际应用中，你可能需要更复杂的 dotfiles 管理工具，例如 GNU Stow, YADM, dotbot 等
    # 这里仅作简单示例，直接复制
    run_as_original_user "cp -r \"$dotfiles_source_dir/.\" \"$ORIGINAL_USER_HOME/\""

    if [[ $? -eq 0 ]]; then
        log_success "Dotfiles 部署成功。"
        log_info "请检查您的家目录以确认更改。"
    else
        log_error "Dotfiles 部署失败。"
    fi
}

# 执行函数
setup_dotfiles