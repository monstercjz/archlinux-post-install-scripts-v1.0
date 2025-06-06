#!/bin/bash
# config/main_menu.sh
#
# 版本: 1.0.0
# 描述: Arch Linux 安装后设置的主交互式菜单。
#       它展示了高级别的功能分类，并调度到相应的模块特定子菜单。
#
# 用法:
#   此脚本通常由 run_setup.sh 调度。
#   不应直接执行此脚本。
#
# 依赖:
#   要求 utils.sh (以及间接的 main_config.sh) 被源引用，以获取辅助函数。

# 确保 utils.sh 已被源引用
# 通过检查一个已知函数是否存在来确认 utils.sh 是否已加载
if [[ -z "$(type -t log_info)" ]]; then
    echo "致命错误: utils.sh 未被源引用。中止 main_menu.sh。" >&2
    exit 1
fi

# main: 主菜单的主要函数。
# 此函数由 dispatch_module 调用。
function main() {
    local choice # 用于存储用户选择的局部变量

    while true; do
        clear # 清屏以呈现更整洁的菜单
        print_header "Arch Linux 安装后设置 - 主菜单"
        print_info "欢迎您, ${RAW_USER}! 让我们来定制您的 Arch Linux 系统。"
        echo ""
        print_prompt "请选择一个类别进行配置:"
        echo ""
        print_color "${C_YELLOW}" "  1) 系统基础配置       (镜像源, 网络设置等)"
        print_color "${C_YELLOW}" "  2) 包管理配置         (AUR 助手, Pacman Hooks)"
        print_color "${C_YELLOW}" "  3) 用户环境设置       (Shell, Dotfiles, 编辑器)"
        print_color "${C_YELLOW}" "  4) 软件安装           (必备软件, 常用应用程序)"
        print_color "${C_YELLOW}" "  5) 清理和完成         (最终收尾工作, 日志备份)"
        echo ""
        print_color "${C_RED}" "  0) 退出设置"
        echo ""
        print_prompt "请输入您的选择: "
        read -r choice # 读取用户输入

        log_info "主菜单选择: ${choice}" # 记录用户选择到日志

        case "${choice}" in
            1)
                dispatch_module "${PROJECT_ROOT_DIR}/config/modules/01_system_base/00_system_base_menu.sh"
                ;;
            2)
                dispatch_module "${PROJECT_ROOT_DIR}/config/modules/02_package_management/00_package_management_menu.sh"
                ;;
            3)
                dispatch_module "${PROJECT_ROOT_DIR}/config/modules/03_user_environment/00_user_environment_menu.sh"
                ;;
            4)
                dispatch_module "${PROJECT_ROOT_DIR}/config/modules/04_software_installation/00_software_installation_menu.sh"
                ;;
            5)
                dispatch_module "${PROJECT_ROOT_DIR}/config/modules/00_cleanup_and_finish.sh"
                ;;
            0)
                log_info "正在退出 Arch Linux 安装后设置。"
                print_success "感谢使用 Arch Linux 安装后设置脚本!"
                return 0 # 退出 main 函数，这将导致 run_setup.sh 完成
                ;;
            *)
                print_error "无效选择。请输入 0 到 5 之间的数字。"
                log_warn "主菜单中的无效选择: ${choice}"
                sleep 2 # 暂停 2 秒，让用户看到错误信息
                ;;
        esac
    done
}

# 当此脚本被源引用时，dispatch_module 将调用 'main' 函数。
# 不在此处直接执行。