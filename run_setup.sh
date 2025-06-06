#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: run_setup.sh
# 版本: 1.0
# 日期: 2025-06-06
# 描述: 主入口脚本。负责项目的初始化设置，包括权限检查、日志系统准备，
#       并启动主菜单。用户应首次运行此脚本。
# ------------------------------------------------------------------------------
# 职责：
# - 执行严格的 Bash 模式设置。
# - 确定项目根目录 (BASE_DIR)。
# - 引入核心工具库 (utils.sh)。
# - 调用统一的项目环境初始化函数 (_initialize_project_environment)。
# - 启动项目的主菜单 (main_menu.sh)。
# ==============================================================================

# 严格模式：
set -euo pipefail

# --- 颜色常量 (仅用于这个脚本的初期致命错误输出，utils.sh 接管后续日志颜色) ---
# 定义标准 ANSI 颜色码，确保早期错误信息在终端中醒目。
readonly RED='\033[0;31m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# 确定项目根目录 (BASE_DIR)。
# `BASH_SOURCE[0]` 指向当前脚本的路径。`dirname` 取目录名，`cd ... && pwd -P` 获取规范路径。
# 这里直接导出，以便 utils.sh 在被引入时能够读取。
export BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 引入 utils.sh
# utils.sh 包含了所有的初始化逻辑 (_initialize_project_environment)
# 以及所有通用函数。
# 使用 BASE_DIR 来构建 utils.sh 的路径，确保路径的准确性。
utils_script="${BASE_DIR}/config/lib/utils.sh"
if [ -f "$utils_script" ]; then
    . "$utils_script"
else
    # 此时还不能使用 utils.sh 的颜色常量，直接 echo 致命错误。
    echo "${BOLD}${RED}Fatal Error: Required utility script not found at $utils_script. Exiting.${RESET}" >&2
    exit 1
fi

# 调用统一的项目环境初始化函数。
# 这个函数会处理所有早期启动任务，包括权限检查、配置加载、日志初始化等。
# 它内部会自行加载 main_config.sh、确定 ORIGINAL_USER/HOME，并准备日志目录。
_initialize_project_environment "${BASH_SOURCE[0]}"

# ==============================================================================
# 核心业务逻辑 (现在可以使用完整的日志系统和所有工具函数)
# ==============================================================================

display_header_section "Arch Linux Post-Install Setup"
log_info "Starting Arch Linux post-installation setup script."
log_info "Running as user: $(whoami)"
log_info "Original user (sudo caller): $ORIGINAL_USER (Home: $ORIGINAL_HOME)"

# 再次确认 root 权限，并记录到日志。
# 理论上这里的代码不会被执行到，因为 _initialize_project_environment 已经确保了权限。
if ! check_root_privileges; then
    log_error "Internal Error: Root privileges lost after initial check. Exiting."
    exit 1
fi
log_info "Root privileges confirmed (via full logging)."

# 启动主菜单脚本。
# 使用 `bash` 命令执行，而不是 `source`，以保持模块间的独立性。
log_info "Launching main setup menu..."
# 注意：main_menu.sh 内部也需要类似的引入 utils.sh 和调用 _initialize_project_environment 的逻辑
bash "${BASE_DIR}/config/main_menu.sh" || log_error "Main menu script exited with an error."

# ==============================================================================
# 脚本完成与退出
# ==============================================================================

log_info "Arch Linux Post-Install Setup Finished. You may need to reboot your system."
display_header_section "Setup Complete!"
exit 0