#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_config.sh
# 版本: 1.0.0
# 日期: 2025-06-08
# 描述: 整个项目的主配置文件。
#       定义了项目的核心参数、路径、日志设置、以及其他模块通用的默认配置。
#       此文件由 config/lib/environment_setup.sh 加载，不应包含可执行逻辑或函数定义，
#       只应包含变量声明。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本，定义了项目基本配置和路径。
# ==============================================================================

# 严格模式 (仅作为良好实践保留，实际加载此文件时，环境已由父脚本或 environment_setup.sh 设置)
# set -euo pipefail

# --- 项目信息 ---
export PROJECT_NAME="Arch Linux Post-Installation Setup"
export PROJECT_VERSION="v1.0"
export PROJECT_AUTHOR="Your Name/Organization"
export PROJECT_DESCRIPTION="A modular script project for automating Arch Linux post-installation configuration and software setup."

# --- 路径配置 ---
# BASE_DIR 会由顶部引导块自动设置。
# LOG_ROOT 基于 BASE_DIR 定义。其他目录路径在 environment_setup.sh 中定义。
export LOG_ROOT="${BASE_DIR}/logs"

# --- 日志和调试设置 ---
# ENABLE_COLORS: 控制终端输出是否带颜色 (true/false)
export ENABLE_COLORS="true"
# DEBUG_MODE: 控制是否开启调试日志 (true/false)
export DEBUG_MODE="true" # 建议开发阶段开启，发布时关闭

# --- 用户环境相关默认设置 ---
export DEFAULT_EDITOR="nano" # 默认文本编辑器 (例如: nano, vim, micro)
export DEFAULT_SHELL="zsh"   # 默认 shell (例如: bash, zsh)
export DOTFILES_REPO_URL="https://github.com/your-username/your-dotfiles.git" # 你的点文件仓库URL
export DOTFILES_LOCAL_PATH="${ORIGINAL_HOME}/.dotfiles" # 点文件在用户家目录的存放路径

# --- 包管理相关默认设置 ---
export AUR_HELPER="yay" # 默认的 AUR 助手 (例如: yay, paru)
export PACMAN_CONF_PATH="/etc/pacman.conf"
export PACMAN_MIRRORLIST_PATH="/etc/pacman.d/mirrorlist"
export PACMAN_HOOKS_DIR="/etc/pacman.d/hooks"

# --- 网络配置相关默认设置 ---
export NETWORK_MANAGER_TYPE="systemd-networkd" # 默认网络管理器类型 (例如: NetworkManager, systemd-networkd)
export SYSTEMD_NETWORKD_CONFIG_DIR="/etc/systemd/network"

# --- 软件安装默认列表 (示例，可根据实际需求扩展) ---
# 基础开发工具和常用工具
export PKG_ESSENTIAL_SOFTWARE=(
    "base-devel"
    "git"
    "curl"
    "wget"
    "unzip"
    "tar"
    "htop"
    "neofetch"
    "fastfetch"
)

# 常用桌面软件 (如果安装桌面环境)
export PKG_COMMON_SOFTWARE=(
    "firefox"
    "vlc"
    "thunderbird"
    "gimp"
    "inkscape"
    "code" # VS Code
)

# 特定应用程序 (根据需要选择)
export PKG_SPECIFIC_APPS=(
    # "docker"
    # "virtualbox"
    # "kde-applications" # 如果安装 KDE Plasma
    # "gnome-extra"      # 如果安装 GNOME
)

# --- 其他通用配置 ---
# 例如，是否在清理阶段删除构建缓存
export CLEAN_BUILD_CACHE="true"