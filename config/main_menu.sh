#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_menu.sh
# 版本: 1.0.6 (适配通用菜单框架和多模块路径)
# 日期: 2025-06-08
# 描述: Arch Linux 后安装脚本的主菜单。
#       现在作为通用菜单框架的一个数据驱动实例。
# ------------------------------------------------------------------------------
# 职责:
#   1. 定义主菜单的选项、描述和对应的模块/脚本路径，使用新的多路径约定。
#   2. 调用通用菜单框架 (_run_generic_menu) 来显示和处理菜单。
# ------------------------------------------------------------------------------
# 使用方法: (此脚本可被 run_setup.sh 调用，也可直接执行)
#   bash main_menu.sh
#   sudo bash main_menu.sh (推荐通过 run_setup.sh 统一入口)
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本，实现主菜单功能。
# v1.0.1 - 2025-06-08 - 优化：使用关联数组集中管理菜单选项到模块路径的映射。
# v1.0.2 - 2025-06-08 - 深度优化：将菜单项的描述文本也整合到关联数组中。
# v1.0.3 - 2025-06-08 - 修复 Bash 语法错误：`local IFS='|' read ...`。
# v1.0.4 - 2025-06-08 - 重构为适配通用菜单框架 (menu_framework.sh)。
#                        现在仅负责定义菜单数据和调用框架函数。
# v1.0.5 - 2025-06-08 - 适配新的多模块路径配置模式 (BASE_PATH_MAP)。
#                        更新菜单数据格式为 "描述|类型:基础路径键:相对路径"。
#                        新增一个 'extra_modules' 示例。
# v1.0.6 - 2025-06-08 - **版本号更新，无功能性修改，仅与 menu_framework.sh 优化同步。**
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 这是所有入口脚本最开始执行的代码，用于健壮地确定项目根目录 (BASE_DIR)。
# 无论脚本从哪个位置被调用，都能正确找到项目根目录，从而构建其他文件的绝对路径。

# 严格模式：
set -euo pipefail

# === 核心优化：确保每次顶层启动都提示环境确认 ===
# 在脚本执行的最开始，清除 _SETUP_INITIAL_CONFIRMED 变量。
# 这可以确保当用户从终端手动运行此脚本时，环境确认提示会重新出现。
# unset _SETUP_INITIAL_CONFIRMED

# 获取当前正在执行（或被 source）的脚本的绝对路径。
# BASH_SOURCE[0] 指向当前文件自身。如果此文件被 source，则 BASH_SOURCE[1] 指向调用者。
# 我们需要的是原始调用脚本的路径来确定项目根目录。
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

# 动态查找项目根目录 (仅当 BASE_DIR 尚未设置时执行查找)
if [ -z "${BASE_DIR+set}" ]; then # 检查 BASE_DIR 是否已设置 (无论值是否为空)
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""

    while [[ "$_project_root_candidate" != "/" ]]; do
        # 检查项目根目录的“签名”：存在 run_setup.sh 文件和 config/ 目录
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate") # 向上移动一层目录
    done

    if [[ -z "$_found_base_dir" ]]; then
        # 此时任何日志或颜色变量都不可用，直接输出致命错误并退出。
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        echo -e "\033[0;31mPlease ensure 'run_setup.sh' and 'config/' directory are present in the project root.\033[0m" >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi

# 在 BASE_DIR 确定后，立即 source environment_setup.sh
# 这样 environment_setup.sh 和它内部的所有路径引用（如 utils.sh, main_config.sh）
# 都可以基于 BASE_DIR 进行绝对引用，解决了 'source' 路径写死的痛点。
# 同时，_current_script_entrypoint 传递给 environment_setup.sh 以便其内部用于日志等。
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 菜单配置 (仅数据定义)
# ==============================================================================

# 声明一个关联数组，映射菜单选项到其对应的模块菜单脚本的描述和相对路径。
# 格式为: [菜单选项数字]="菜单描述文本|类型:基础路径键:相对路径/到/脚本.sh"
# 类型可以是: "menu:" (子菜单) 或 "action:" (功能脚本)
# 基础路径键: BASE_PATH_MAP 中定义的键 (例如 "core_modules", "extra_modules")
declare -A MAIN_MENU_ENTRIES=(
    # 使用 'core_modules' 键指向 MODULES_DIR (即 config/modules)
    [1]="系统环境配置 (Mirrors, Network, System Time)|menu:core_modules:01_system_base/00_system_base_menu.sh"
    [2]="用户环境配置 (Shell, Dotfiles, Editor)|menu:core_modules:02_user_environment/00_user_environment_menu.sh"
    [3]="基础软件安装 (AUR Helper, Pacman Hooks)|menu:core_modules:03_base_software_installation/00_base_software_installation_menu.sh"
    [4]="常用软件安装 (Essential, Common, Specific Apps)|menu:core_modules:04_common_software_installation/00_common_software_installation_menu.sh"
    [5]="Perform Cleanup and Finish|action:core_modules:00_cleanup_and_finish.sh"

    # 示例: 使用 'extra_modules' 键指向 ANOTHER_MODULES_DIR (即 modules-another/)
    [6]="Run Extra Tools (from another module dir)|action:extra_modules:my_extra_tool.sh"
    # 请确保 'modules-another/my_extra_tool.sh' 文件存在，以便此选项能正常工作
)

# ==============================================================================
# 主逻辑流程 (调用通用菜单框架)
# ==============================================================================

# main()
# 功能: 脚本的主函数，负责主菜单的循环显示和处理。
main() {
    log_info "Starting Main Menu loop."

    # 导入通用菜单框架。
    # 确保在调用 _run_generic_menu 之前，menu_framework.sh 已被 source。
    source "${LIB_DIR}/menu_framework.sh"

    # 调用通用菜单处理函数，传入菜单数据、标题、退出文本和颜色。
    # _run_generic_menu 函数会处理菜单的显示、用户输入和导航逻辑。
    _run_generic_menu \
        "MAIN_MENU_ENTRIES" \
        "Arch Linux Post-Install Main Menu" \
        "Exit Setup" \
        "${COLOR_PURPLE}" \
        "${COLOR_YELLOW_BG}${COLOR_BOLD}${COLOR_WHITE}"
    
    # _run_generic_menu 返回后，表示用户选择了退出或发生了框架级别的错误。
    # 根据 _run_generic_menu 的返回状态（0表示正常退出菜单循环），决定后续操作。
    log_info "Main Menu loop ended."
}

# exit_script()
# 功能: 统一的脚本退出处理函数。
# 参数: $1 (exit_code) - 退出码 (默认为 0)。
exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Arch Linux Post-Installation Main Menu script."
    exit "$exit_code"
}

# 调用主函数
main "$@"

# 脚本退出
exit_script 0