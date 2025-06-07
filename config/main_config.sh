#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_config.sh
# 版本: 1.0.3 (最终版：只声明由 main_config.sh 赋值的变量)
# 日期: 2025-06-08
# 描述: 整个项目的主配置文件。
#       定义了项目的核心参数、静态配置、以及其他模块通用的默认设置。
#       此文件由 config/lib/environment_setup.sh 加载，其所有 'export' 变量均可被后续覆盖。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# v1.0.1 - 2025-06-08 - 集中定义所有 export 全局变量的初始/默认值，实现可覆盖机制。
# v1.0.2 - 2025-06-08 - 优化变量声明：只包含静态/初始配置，移除动态派生变量的声明。
# v1.0.3 - 2025-06-08 - **最终优化：# CURRENT_SCRIPT_LOG_FILE,CURRENT_DAY_LOG_DIR
                        # 由 initialize_logging_system 函数内部定义并导出。
# ==============================================================================

# 严格模式 (仅作为良好实践保留，实际加载此文件时，环境已由父脚本或 environment_setup.sh 设置)
# set -euo pipefail

# ==============================================================================
# 全局变量声明与默认值赋值 (这些变量由 main_config.sh 负责声明和赋值)
# ------------------------------------------------------------------------------

# --- 项目信息 (通常为静态配置，在运行时不应被覆盖) ---
export PROJECT_NAME="Arch Linux Post-Installation Setup"
export PROJECT_VERSION="v1.0"
export PROJECT_AUTHOR="Your Name/Organization"
export PROJECT_DESCRIPTION="A modular script project for automating Arch Linux post-installation configuration and software setup."

# --- 路径配置 (可配置的根目录，动态派生路径) ---
# LOG_ROOT: 日志文件存放的根目录。可在此处设置默认值。
# 实际的 BASE_DIR (由顶部引导块提供) 
# 其他派生路径 (CONFIG_DIR, LIB_DIR, MODULES_DIR, ASSETS_DIR)
# 由 environment_setup.sh 动态赋值
export CONFIG_DIR
export LIB_DIR
export MODULES_DIR
export ASSETS_DIR
# export CURRENT_DAY_LOG_DIR=""
# export CURRENT_SCRIPT_LOG_FILE=""
export LOG_ROOT="${BASE_DIR}/logs" # 假设日志根目录默认在项目根目录下的 logs 文件夹

# --- 日志和调试设置 (可由用户在 main_config.sh 中自定义，或在运行时通过环境变量覆盖) ---
export ENABLE_COLORS="true"  # 控制终端输出是否带颜色 (true/false)
export DEBUG_MODE="true"     # 控制是否开启调试日志 (true/false)

# --- 用户环境相关默认设置 (可在 main_config.sh 中自定义) ---
export ORIGINAL_USER=""  # 由 initialize_logging_system 函数内部定义并导出。
export ORIGINAL_HOME=""  # 由 initialize_logging_system 函数内部定义并导出。
export DEFAULT_EDITOR="nano" # 默认文本编辑器 (例如: nano, vim, micro)
export DEFAULT_SHELL="zsh"   # 默认 shell (例如: bash, zsh)
export DOTFILES_REPO_URL="https://github.com/your-username/your-dotfiles.git" # 你的点文件仓库URL
# DOTFILES_LOCAL_PATH 依赖 ORIGINAL_HOME，其赋值在 ORIGINAL_HOME 确定后由 environment_setup.sh 进行。
# 此处提供一个基于模板的默认值，但实际赋值在 environment_setup.sh 完成。
export DOTFILES_LOCAL_PATH="${ORIGINAL_HOME:-/home/nonexistent}/.dotfiles" # 使用非扩展引用，防止 ORIGINAL_HOME 未定义时报错

# --- 包管理相关默认设置 (可在 main_config.sh 中自定义) ---
export AUR_HELPER="yay" # 默认的 AUR 助手 (例如: yay, paru)
export PACMAN_CONF_PATH="/etc/pacman.conf"
export PACMAN_MIRRORLIST_PATH="/etc/pacman.d/mirrorlist"
export PACMAN_HOOKS_DIR="/etc/pacman.d/hooks"

# --- 网络配置相关默认设置 (可在 main_config.sh 中自定义) ---
export NETWORK_MANAGER_TYPE="systemd-networkd" # 默认网络管理器类型 (例如: NetworkManager, systemd-networkd)
export SYSTEMD_NETWORKD_CONFIG_DIR="/etc/systemd/network"

# --- 软件安装默认列表 (可在 main_config.sh 中自定义) ---
# 注意：数组在 Bash 中导出行为复杂，通常建议在需要时重新赋值。此处仅为示例。
export PKG_ESSENTIAL_SOFTWARE=("base-devel" "git" "curl" "wget" "unzip" "tar" "htop" "neofetch" "fastfetch")
export PKG_COMMON_SOFTWARE=("firefox" "vlc" "thunderbird" "gimp" "inkscape" "code")
export PKG_SPECIFIC_APPS=()

# --- 其他通用配置 ---
export CLEAN_BUILD_CACHE="true"