#!/bin/bash

# main_menu.sh
# 主菜单脚本：向用户展示主要功能分类，并调度到对应的二级菜单。

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

main_menu() {
    while true; do
        CHOICE=$(dialog --clear \
                        --backtitle "Arch Linux 后安装脚本" \
                        --title "主菜单" \
                        --menu "选择一个功能类别:" 15 60 7 \
                        "1" "系统基础配置" \
                        "2" "包管理配置" \
                        "3" "用户环境配置" \
                        "4" "软件安装" \
                        "C" "清理和完成" \
                        "Q" "退出" \
                        2>&1 >/dev/tty)

        case "$CHOICE" in
            1) dispatch_module "$PROJECT_ROOT/config/modules/01_system_base/00_system_base_menu.sh" ;;
            2) dispatch_module "$PROJECT_ROOT/config/modules/02_package_management/00_package_management_menu.sh" ;;
            3) dispatch_module "$PROJECT_ROOT/config/modules/03_user_environment/00_user_environment_menu.sh" ;;
            4) dispatch_module "$PROJECT_ROOT/config/modules/04_software_installation/00_software_installation_menu.sh" ;;
            C) dispatch_module "$PROJECT_ROOT/config/modules/00_cleanup_and_finish.sh" ;;
            Q) break ;;
            *) log_warn "无效选项，请重新选择。" ;;
        esac
    done
    log_info "脚本执行完毕，退出。"
}

# 执行主菜单
main_menu