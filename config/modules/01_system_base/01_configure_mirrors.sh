#!/bin/bash

# 01_configure_mirrors.sh
# 配置 Pacman 镜像源的原子功能脚本。

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

configure_mirrors() {
    log_info "正在配置 Pacman 镜像源..."

    if ! check_root_privileges; then
        return 1
    fi

    # 备份当前的 mirrorlist
    log_info "备份当前的 /etc/pacman.d/mirrorlist 到 /etc/pacman.d/mirrorlist.bak"
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

    # 提示用户选择国家或地区
    log_info "请选择您希望使用的镜像源国家或地区（例如：China, Japan, United States）"
    read -p "输入国家或地区名称: " COUNTRY

    if [[ -z "$COUNTRY" ]]; then
        log_warn "未输入国家或地区，跳过镜像源配置。"
        return 0
    fi

    # 使用 reflector 生成新的 mirrorlist
    log_info "使用 reflector 生成新的 mirrorlist..."
    # 示例：选择最新的5个HTTP/HTTPS协议的中国镜像，并按速度排序
    # 注意：reflector 可能需要安装
    if ! command -v reflector &> /dev/null; then
        log_warn "reflector 未安装。尝试安装..."
        if ! pacman -S --noconfirm reflector; then
            log_error "无法安装 reflector。请手动安装后重试。"
            return 1
        fi
    fi

    reflector --country "$COUNTRY" --latest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

    if [[ $? -eq 0 ]]; then
        log_success "Pacman 镜像源配置成功。"
        log_info "请运行 'sudo pacman -Syy' 更新软件包数据库。"
    else
        log_error "Pacman 镜像源配置失败。"
        # 恢复备份
        log_info "正在恢复备份的 mirrorlist..."
        mv /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
    fi
}

# 执行函数
configure_mirrors