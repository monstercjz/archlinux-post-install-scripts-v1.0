#!/bin/bash

# 01_install_aur_helper.sh
# 安装 AUR 助手（例如 paru 或 yay）的原子功能脚本。

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

install_aur_helper() {
    log_info "正在安装 AUR 助手..."

    if ! check_root_privileges; then
        return 1
    fi

    local aur_helper="$DEFAULT_AUR_HELPER"

    if [[ "$aur_helper" == "none" ]]; then
        log_info "main_config.sh 中未指定 AUR 助手，跳过安装。"
        return 0
    fi

    if command -v "$aur_helper" &> /dev/null; then
        log_info "$aur_helper 已经安装，跳过安装。"
        return 0
    fi

    log_info "尝试安装 $aur_helper..."

    # 安装 git 和 base-devel (构建 AUR 包所需)
    log_info "安装 git 和 base-devel..."
    pacman -S --noconfirm git base-devel

    if [[ $? -ne 0 ]]; then
        log_error "无法安装 git 或 base-devel。请手动安装后重试。"
        return 1
    fi

    # 克隆 AUR 助手仓库并构建安装
    local aur_helper_repo=""
    local aur_helper_dir=""

    case "$aur_helper" in
        "paru")
            aur_helper_repo="https://aur.archlinux.org/paru.git"
            aur_helper_dir="/tmp/paru-build"
            ;;
        "yay")
            aur_helper_repo="https://aur.archlinux.org/yay.git"
            aur_helper_dir="/tmp/yay-build"
            ;;
        *)
            log_error "不支持的 AUR 助手: $aur_helper"
            return 1
            ;;
    esac

    log_info "克隆 $aur_helper 仓库到 $aur_helper_dir..."
    if [[ -d "$aur_helper_dir" ]]; then
        rm -rf "$aur_helper_dir"
    fi
    git clone "$aur_helper_repo" "$aur_helper_dir"

    if [[ $? -ne 0 ]]; then
        log_error "克隆 $aur_helper 仓库失败。"
        return 1
    fi

    log_info "进入 $aur_helper_dir 并构建安装..."
    (
        cd "$aur_helper_dir" || exit 1
        run_as_original_user "makepkg -si --noconfirm"
    )

    if [[ $? -eq 0 ]]; then
        log_success "$aur_helper 安装成功。"
    else
        log_error "$aur_helper 安装失败。"
    fi

    # 清理构建目录
    log_info "清理构建目录 $aur_helper_dir..."
    rm -rf "$aur_helper_dir"
}

# 执行函数
install_aur_helper