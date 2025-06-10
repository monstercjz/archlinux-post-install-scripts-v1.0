#!/bin/bash

# 03_configure_nano.sh
# 配置 nano 编辑器的原子功能脚本。

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

configure_nano() {
    log_info "正在配置 Nano 编辑器..."

    if ! command -v nano &> /dev/null; then
        log_warn "Nano 未安装。尝试安装..."
        if ! pacman -S --noconfirm nano; then
            log_error "无法安装 Nano。请手动安装后重试。"
            return 1
        fi
    fi

    # 备份原始的 nano 配置文件
    if [[ -f "/etc/nanorc" ]]; then
        log_info "备份 /etc/nanorc 到 /etc/nanorc.bak"
        cp /etc/nanorc /etc/nanorc.bak
    fi

    # 示例：添加一些基本的 nano 配置
    # 实际应用中，你可以提供一个更完整的 nanorc 文件在 assets 中
    log_info "添加基本 Nano 配置到 /etc/nanorc..."
    cat << EOF | tee -a /etc/nanorc
# Enable syntax highlighting
include "/usr/share/nano/*.nanorc"

# Enable line numbers
set linenumbers

# Enable softwrap
set softwrap

# Set tab size
set tabsize 4

# Convert tabs to spaces
set tabstospaces
EOF

    if [[ $? -eq 0 ]]; then
        log_success "Nano 编辑器配置成功。"
    else
        log_error "Nano 编辑器配置失败。"
    fi
}

# 执行函数
configure_nano