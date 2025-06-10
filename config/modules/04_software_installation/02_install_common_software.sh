#!/bin/bash

# 02_install_common_software.sh
# 安装常用软件的原子功能脚本。

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

install_common_software() {
    log_info "正在安装常用软件..."

    if ! check_root_privileges; then
        return 1
    fi

    local common_packages=(
        "firefox"
        "vlc"
        "gimp"
        "inkscape"
        "libreoffice-fresh"
        "thunderbird"
        "keepassxc"
        "flatpak" # 常用应用可能通过 Flatpak 安装
        "snapd"   # 常用应用可能通过 Snap 安装
    )

    log_info "安装以下常用软件包: ${common_packages[*]}"
    pacman -S --noconfirm "${common_packages[@]}"

    if [[ $? -eq 0 ]]; then
        log_success "常用软件安装成功。"
    else
        log_error "常用软件安装失败。"
    fi

    # 启用 snapd (如果安装了)
    if command -v snap &> /dev/null; then
        log_info "启用 snapd 服务..."
        systemctl enable --now snapd.socket
        if [[ $? -eq 0 ]]; then
            log_success "snapd 服务启用成功。"
            log_info "请运行 'sudo snap install core' 安装 snap 核心。"
        else
            log_error "snapd 服务启用失败。"
        fi
    fi
}

# 执行函数
install_common_software