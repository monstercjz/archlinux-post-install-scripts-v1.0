#!/bin/bash

# 03_install_specific_apps.sh
# 安装特定应用程序的原子功能脚本（可选）。

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

install_specific_apps() {
    log_info "正在安装特定应用程序..."

    if ! check_root_privileges; then
        return 1
    fi

    local specific_packages_input=$(dialog --clear \
                                            --backtitle "Arch Linux 后安装脚本" \
                                            --title "安装特定应用程序" \
                                            --inputbox "请输入要安装的软件包名称（空格分隔，例如：vscode docker）:" 10 60 "" \
                                            2>&1 >/dev/tty)

    if [[ -z "$specific_packages_input" ]]; then
        log_info "未输入特定应用程序，跳过安装。"
        return 0
    fi

    # 将输入字符串转换为数组
    IFS=' ' read -r -a specific_packages <<< "$specific_packages_input"

    if [[ ${#specific_packages[@]} -eq 0 ]]; then
        log_info "未输入特定应用程序，跳过安装。"
        return 0
    fi

    log_info "安装以下特定软件包: ${specific_packages[*]}"
    pacman -S --noconfirm "${specific_packages[@]}"

    if [[ $? -eq 0 ]]; then
        log_success "特定应用程序安装成功。"
    else
        log_error "特定应用程序安装失败。"
    fi
}

# 执行函数
install_specific_apps