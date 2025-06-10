#!/bin/bash

# 01_install_essential_software.sh
# 安装必备软件的原子功能脚本。

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

install_essential_software() {
    log_info "正在安装必备软件..."

    if ! check_root_privileges; then
        return 1
    fi

    local essential_packages=(
        "base-devel" # 编译 AUR 包所需
        "git"
        "vim"
        "nano"
        "htop"
        "neofetch"
        "wget"
        "curl"
        "unzip"
        "tar"
        "rsync"
        "dialog" # 用于菜单
        "reflector" # 用于镜像源配置
    )

    log_info "安装以下必备软件包: ${essential_packages[*]}"
    pacman -S --noconfirm "${essential_packages[@]}"

    if [[ $? -eq 0 ]]; then
        log_success "必备软件安装成功。"
    else
        log_error "必备软件安装失败。"
    fi
}

# 执行函数
install_essential_software