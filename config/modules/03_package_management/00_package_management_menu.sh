#!/bin/bash

# 00_package_management_menu.sh
# 包管理配置模块的二级菜单脚本。

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

package_management_menu() {
    while true; do
        CHOICE=$(dialog --clear \
                        --backtitle "Arch Linux 后安装脚本" \
                        --title "包管理配置菜单" \
                        --menu "选择一个选项:" 15 60 5 \
                        "1" "安装 AUR 助手" \
                        "2" "设置 Pacman Hooks" \
                        "B" "返回主菜单" \
                        2>&1 >/dev/tty)

        case "$CHOICE" in
            1) dispatch_module "$SCRIPT_DIR/01_install_aur_helper.sh" ;;
            2) dispatch_module "$SCRIPT_DIR/02_setup_pacman_hooks.sh" ;;
            B) break ;;
            *) log_warn "无效选项，请重新选择。" ;;
        esac
    done
}

# 执行菜单
package_management_menu