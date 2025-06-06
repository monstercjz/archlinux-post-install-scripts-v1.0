#!/bin/bash

# run_setup.sh
# 主入口脚本：用户首次运行此脚本，负责权限检查并启动主菜单。

# 获取脚本的真实路径，即使通过软链接或从其他目录执行
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# 加载全局配置和工具函数
# 注意：run_setup.sh 不包含通用初始化块，因为它负责设置环境并启动主菜单。
# 它直接使用 PROJECT_ROOT 来定位 config 目录。
source "$PROJECT_ROOT/config/main_config.sh"
source "$PROJECT_ROOT/config/lib/utils.sh"

# 检查是否以 root 权限运行
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限才能运行。请使用 sudo 运行：sudo ./run_setup.sh"
        exit 1
    fi
}

# 检查并安装必要的依赖（如果需要）
# 例如：git, dialog, whiptail 等
install_dependencies() {
    log_info "检查并安装必要的依赖..."
    # 示例：检查并安装 dialog
    if ! command -v dialog &> /dev/null; then
        log_warn "dialog 未安装。尝试安装..."
        if ! pacman -S --noconfirm dialog; then
            log_error "无法安装 dialog。请手动安装后重试。"
            exit 1
        fi
    fi
    log_success "依赖检查完成。"
}

# 主函数
main() {
    log_info "Arch Linux 后安装脚本启动..."

    check_root_privileges
    install_dependencies

    # 启动主菜单
    log_info "启动主菜单..."
    "$PROJECT_ROOT/config/main_menu.sh"
    
    log_success "Arch Linux 后安装脚本完成。"
}

# 执行主函数
main