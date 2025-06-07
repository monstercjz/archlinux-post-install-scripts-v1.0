#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_menu.sh
# 版本: 1.0
# 日期: 2025-06-06
# 描述: 主菜单脚本。向用户展示主要功能分类，并调度到对应的二级菜单。
# ==============================================================================

# 严格模式：
set -euo pipefail

# 引入 utils.sh
# utils.sh 包含了所有的初始化逻辑 (_initialize_project_environment)
# 以及所有通用函数。
# 使用相对路径来找到 utils.sh (main_menu.sh 在 config/ 下，lib/ 在 config/ 下)。
utils_script="$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
if [ -f "$utils_script" ]; then
    . "$utils_script"
else
    # 此时还不能使用 utils.sh 的颜色常量，直接 echo 致命错误。
    echo "Fatal Error: Required utility script not found at $utils_script. Exiting." >&2
    exit 1
fi

# 调用统一的项目环境初始化函数。
# 它会处理所有早期启动任务，包括权限检查、配置加载、日志初始化等。
_initialize_project_environment "${BASH_SOURCE[0]}"

# ==============================================================================
# 脚本核心逻辑
# ==============================================================================

display_header_section "主菜单"
log_info "Welcome to the main setup menu."

# 示例菜单选项
menu_options=(
    "01_System_Base_Config"
    "02_Package_Management"
    "03_User_Environment"
    "04_Software_Installation"
    "05_Cleanup_and_Finish"
    "Exit"
)

# 使用 utils.sh 中的 display_menu 函数
# 注意：display_menu 函数本身还需要在 utils.sh 中被实现
# 这是一个占位符，假定 display_menu 已经存在并工作
# 你需要在 utils.sh 中添加 display_menu 函数的实现
# selected_choice=$(display_menu "请选择一个类别进行配置" "${menu_options[@]}")
# 由于 display_menu 尚未在 utils.sh 中实现，这里先用一个简化的 select 替代
echo "请选择一个类别进行配置:"
select selected_choice in "${menu_options[@]}"; do
    if [[ -n "$selected_choice" ]]; then
        log_info "Selected option: $selected_choice"
        break
    else
        log_warn "Invalid selection. Please try again."
    fi
done


case "$selected_choice" in
    "01_System_Base_Config")
        log_info "进入系统基础配置模块..."
        # 确保这里调用子脚本时，也使用 bash 执行，并传递 BASE_DIR
        bash "${BASE_DIR}/config/modules/01_system_base/00_system_base_menu.sh" || log_error "系统基础配置模块执行失败。"
        ;;
    "02_Package_Management")
        log_info "进入包管理模块..."
        bash "${BASE_DIR}/config/modules/02_package_management/00_package_management_menu.sh" || log_error "包管理模块执行失败。"
        ;;
    "03_User_Environment")
        log_info "进入用户环境模块..."
        bash "${BASE_DIR}/config/modules/03_user_environment/00_user_environment_menu.sh" || log_error "用户环境模块执行失败。"
        ;;
    "04_Software_Installation")
        log_info "进入软件安装模块..."
        bash "${BASE_DIR}/config/modules/04_software_installation/00_software_installation_menu.sh" || log_error "软件安装模块执行失败。"
        ;;
    "05_Cleanup_and_Finish")
        log_info "执行清理和完成任务..."
        bash "${BASE_DIR}/config/modules/00_cleanup_and_finish.sh" || log_error "清理和完成任务执行失败。"
        ;;
    "Exit")
        log_info "退出主菜单。感谢使用！"
        ;;
    *)
        log_warn "无效的菜单选择: $selected_choice"
        ;;
esac

log_info "主菜单执行完毕。"