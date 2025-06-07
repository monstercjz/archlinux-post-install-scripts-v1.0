#!/bin/bash
# config/main_config.sh

# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_config.sh
# 版本: 1.0
# 日期: 2025-06-06
# 描述: 全局配置变量。
#       此文件定义了整个脚本项目使用的全局设置，可根据用户偏好进行修改。
# ------------------------------------------------------------------------------
# 注意：此文件不应包含任何可执行逻辑，只定义变量。
# ==============================================================================

# 日志设置
# 脚本日志文件的根目录。建议使用 /var/log/ 下的路径，因为通常由 root 管理。
# 例如: "/var/log/archlinux_post_install_setup"
LOG_ROOT="/var/log/archlinux_post_install_setup" 

# 是否在终端输出中启用颜色（true/false）。
# 在非交互式或不支持颜色的环境中可设为 false。
ENABLE_COLORS="true"

# AUR 助手设置
# 默认的 AUR 助手（例如 "paru" 或 "yay"）。
DEFAULT_AUR_HELPER="paru"

# Pacman 镜像配置
# 生成 Pacman 镜像列表的默认国家，使用 pacman-mirrors 工具的国家代码。
# 例如: "China", "Germany", "United States"
PACMAN_MIRROR_COUNTRY="China"

# 用户交互设置
# 设置为 "true" 时，脚本会跳过部分确认提示，谨慎使用！
ASSUME_YES="false"

# Dotfiles 仓库设置
# 如果使用 Git 仓库管理 dotfiles，请在此处填写仓库 URL。
# 例如: "https://github.com/your-username/your-dotfiles.git"
DOTFILES_REPO="https://github.com/your-username/your-dotfiles.git"
# Dotfiles 仓库克隆到本地的目录（相对于用户主目录）。
# 例如: "$HOME/.dotfiles"
DOTFILES_LOCAL_DIR="$HOME/.dotfiles"

# 调试模式
# 设置为 "true" 会启用更多详细的调试信息输出。
DEBUG_MODE="false" 