#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/05_configure_shell/00_configure_shell_menu.sh
# 版本: 1.0.0
# 日期: 2025-06-11
# 描述: Zsh 及插件配置模块的菜单脚本。
#       作为通用菜单框架的一个数据驱动实例。
# ------------------------------------------------------------------------------
# 职责:
#   1. 定义 Zsh 配置菜单的选项、描述和对应的模块/脚本路径。
#   2. 调用通用菜单框架 (_run_generic_menu) 来显示和处理菜单。
# ------------------------------------------------------------------------------
# 使用方法: (此脚本应通过主菜单或父级菜单调用)
#   source "${BASE_DIR}/config/lib/environment_setup.sh" "$0" # 确保环境已设置
#   source "${LIB_DIR}/menu_framework.sh" # 导入菜单框架
#   # 然后调用 main 函数
#   main
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-11 - 初始版本，适配项目菜单框架。
# ==============================================================================

# --- 脚本顶部引导块 START ---
# 这是所有入口脚本最开始执行的代码，用于健壮地确定项目根目录 (BASE_DIR)。
# 无论脚本从哪个位置被调用，都能正确找到项目根目录，从而构建其他文件的绝对路径。

# 严格模式：
set -euo pipefail

# === 核心优化：确保每次顶层启动都提示环境确认 ===
# 在脚本执行的最开始，清除 _SETUP_INITIAL_CONFIRMED 变量。
# 这可以确保当用户从终端手动运行此脚本时，环境确认提示会重新出现。
# unset _SETUP_INITIAL_CONFIRMED # 通常只在顶层入口脚本 (如 run_setup.sh, main_menu.sh) 中 unset

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
declare -A CONFIGURE_SHELL_MENU_ENTRIES=(
    # 使用 'core_modules' 键指向 MODULES_DIR (即 config/modules)
    # 这里我们将 zsh-plugins.sh 作为主要的 action 脚本来调用
    [1]="安装和配置 Zsh 及常用插件 (完整流程)|action:core_modules:05_configure_shell/zsh-plugins.sh"
    # 如果需要更细粒度的控制，可以为 modules/ 下的脚本创建单独的 action
    # [2]="仅安装 Zsh 和 Oh My Zsh|action:core_modules:05_configure_shell/modules/install.sh" # 需要修改 install.sh 使其可单独运行
    # [3]="仅安装字体|action:core_modules:05_configure_shell/modules/fonts.sh" # 需要修改 fonts.sh 使其可单独运行
    # ... 其他选项 ...
)

# ==============================================================================
# 主逻辑流程 (调用通用菜单框架)
# ==============================================================================

# main()
# 功能: 脚本的主函数，负责主菜单的循环显示和处理。
main() {
    log_info "Starting Configure Shell Menu loop."

    # 导入通用菜单框架。
    # 确保在调用 _run_generic_menu 之前，menu_framework.sh 已被 source。
    source "${LIB_DIR}/menu_framework.sh"

    # 调用通用菜单处理函数，传入菜单数据、标题、退出文本和颜色。
    # _run_generic_menu 函数会处理菜单的显示、用户输入和导航逻辑。
    _run_generic_menu \
        "CONFIGURE_SHELL_MENU_ENTRIES" \
        "Zsh 及插件配置（MENU NO.5）" \
        "返回主菜单" \
        "${COLOR_PURPLE}" \
        "${COLOR_BLUE_BG}${COLOR_BOLD}${COLOR_WHITE}"

    # _run_generic_menu 返回后，表示用户选择了退出或发生了框架级别的错误。
    # 根据 _run_generic_menu 的返回状态（0表示正常退出菜单循环），决定后续操作。
    log_info "Configure Shell Menu loop ended."
}

# exit_script()
# 功能: 统一的脚本退出处理函数。
# 参数: $1 (exit_code) - 退出码 (默认为 0)。
exit_script() {
    local exit_code=${1:-0}
    log_info "Exiting Configure Shell Menu script."
    exit "$exit_code"
}

# 调用主函数
main "$@"

# 脚本退出
exit_script 0