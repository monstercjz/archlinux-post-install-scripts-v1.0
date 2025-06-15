#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/main_config.sh
# 版本: 1.0.10 (新增通用备份文件数量配置)
# 日期: 2025-06-11
# 描述: 整个项目的主配置文件。
#       此文件作为所有项目级别全局变量的中心声明清单，并为可配置项提供默认值。
#       其所有 'export' 变量均可被后续脚本覆盖，动态派生变量在此处仅作声明。
# ------------------------------------------------------------------------------
# 变更记录:
# v1.0.0 - 2025-06-08 - 初始版本。
# v1.0.1 - 2025-06-08 - 集中定义所有 export 全局变量的初始/默认值，实现可覆盖机制。
# v1.0.2 - 2025-06-08 - 优化变量声明：只包含静态/初始配置，移除动态派生变量的声明。
# v1.0.3 - 2025-06-08 - 修正了 ORIGINAL_USER, ORIGINAL_HOME 和 DOTFILES_LOCAL_PATH 的声明逻辑，
#                        明确这些变量由 environment_setup.sh 在运行时动态赋值。
# v1.0.4 - 2025-06-08 - 进一步精简，只包含静态配置和默认值。移除了所有运行时动态派生的路径变量
#                        （如 CONFIG_DIR, MODULES_DIR, LOG_ROOT, DOTFILES_LOCAL_PATH）
#                        以及运行时确定的用户变量（ORIGINAL_USER, ORIGINAL_HOME）。
#                        引入 LOG_ROOT_RELATIVE_TO_BASE 来定义日志根目录相对于 BASE_DIR 的相对位置。
#                        软件安装数组不再使用 'export' 关键字。
# v1.0.5 - 2025-06-08 - 核心优化：将所有项目级全局变量在此处进行 'export' 声明，
#                        使其成为全局变量的中心清单。对于动态派生变量，在此处仅声明不赋值，
#                        其具体值仍由 environment_setup.sh 在运行时确定和赋值。
#                        新增 BASE_PATH_MAP 的声明。
# v1.0.6 - 2025-06-08 - 新增 CURRENT_LOG_LEVEL 和 DISPLAY_MODE 配置项，
#                        以更精细地控制日志输出级别和终端显示样式。
#                        对日志和调试设置部分进行重组和增强。
# v1.0.7 - 2025-06-08 - 新增 DEFAULT_MESSAGE_FORMAT_MODE 配置项，
#                        用于控制终端日志消息的默认前缀格式（时间戳、级别、调用者）。
#                        这为未来的消息格式定制（如简化“SUCCESS”消息）提供了基础。
# v1.0.8 - 2025-06-08 - 在 DEFAULT_MESSAGE_FORMAT_MODE 中新增 "timestamp_level" 模式，
#                        允许只显示时间戳和日志级别，不显示调用者信息。
# v1.0.9 - 2025-06-08 - **更新 DISPLAY_MODE 和 DEFAULT_MESSAGE_FORMAT_MODE 的可选值说明，**
#                        **使其支持使用数字代号 (1, 2, 3...) 来替代完整的字符串名称，方便用户输入。**
# v1.0.10 - 2025-06-11 - **新增 `MAX_BACKUP_FILES_PACMAN_CONF` 和 `MAX_BACKUP_FILES_MIRRORLIST` 配置项，**
#                        **用于控制 Pacman 配置文件和镜像列表的备份数量。**
# ==============================================================================

# 严格模式 (仅作为良好实践保留，实际加载此文件时，环境已由父脚本或 environment_setup.sh 设置)
# set -euo pipefail

# ==============================================================================
# 项目级全局变量声明与默认值赋值 (所有项目级变量在此处声明，可配置项赋默认值)
# ==============================================================================

# --- 项目信息 (通常为静态配置，在运行时不应被覆盖) ---
export PROJECT_NAME="Arch Linux Post-Installation Setup"
export PROJECT_VERSION="v1.0"
export PROJECT_AUTHOR="Your Name/Organization"
export PROJECT_DESCRIPTION="A modular script project for automating Arch Linux post-installation configuration and software setup."

# --- 核心路径变量 (由 environment_setup.sh 动态计算并赋值) ---
# 这些变量在此处声明，但在 environment_setup.sh 中根据 BASE_DIR 动态确定其绝对路径。
export BASE_DIR        # 项目根目录的绝对路径 (由调用脚本的顶部引导块确定并导出)
export CONFIG_DIR      # 项目配置目录的绝对路径 (例如: ${BASE_DIR}/config)
export LIB_DIR         # 项目库文件目录的绝对路径 (例如: ${CONFIG_DIR}/lib)
export MODULES_DIR     # 默认模块根目录的绝对路径 (例如: ${CONFIG_DIR}/modules)
export ASSETS_DIR      # 资产文件目录的绝对路径 (例如: ${CONFIG_DIR}/assets)
export ANOTHER_MODULES_DIR # 另一个模块根目录的绝对路径 (例如: ${BASE_DIR}/modules-another)

# --- 运行时用户和环境变量 (由 environment_setup.sh 动态确定并赋值) ---
# 这些变量在此处声明，但其值在 environment_setup.sh 中根据运行时环境动态确定。
export ORIGINAL_USER   # 调用 sudo 的原始用户的用户名
export ORIGINAL_HOME   # 调用 sudo 的原始用户的家目录
export DOTFILES_LOCAL_PATH # 点文件在本地克隆的绝对路径 (依赖 ORIGINAL_HOME)

# --- 日志配置 (LOG_ROOT_RELATIVE_TO_BASE 为可配置默认值，LOG_ROOT 为动态派生) ---
export LOG_ROOT_RELATIVE_TO_BASE="arch_post_installation_logs" # 日志文件存放的根目录，相对于项目根目录 (BASE_DIR) 的路径
export LOG_ROOT        # 日志文件根目录的绝对路径 (由 environment_setup.sh 动态计算并赋值)
export CURRENT_DAY_LOG_DIR # 当前日期日志目录的绝对路径 (由 initialize_logging_system 动态计算并赋值)
export CURRENT_SCRIPT_LOG_FILE # 当前脚本日志文件的绝对路径 (由 initialize_logging_system 动态计算并赋值)

# --- 菜单框架基础路径映射 (由 environment_setup.sh 动态计算并赋值) ---
# 这是一个关联数组，映射逻辑名称到实际的绝对路径。
# 关联数组无法直接通过 'export' 继承到子进程，但在此处声明其存在性。
# 实际的填充和使用在 environment_setup.sh 和 menu_framework.sh 中。
declare -A BASE_PATH_MAP # 声明为关联数组，供后续在 environment_setup.sh 中填充

# --- 日志和调试设置 (可配置的默认值) ---
# 控制是否开启所有颜色输出 (true/false)。如果为 false，则所有终端输出将不带颜色。
export ENABLE_COLORS="true"

# 定义日志输出的最低级别（仅影响终端显示，不影响文件记录）。
# 可选值: "DEBUG", "INFO", "NOTICE", "SUCCESS", "WARN", "ERROR", "FATAL", "SUMMARY"
export CURRENT_LOG_LEVEL="INFO" 

# 定义终端日志的默认显示模式。
# 可选值:
#   "no_color" (1):        终端输出完全不带色彩。
#   "prefix_only_color" (2): 日志级别前缀（如 [INFO]）带颜色，消息内容不带颜色。
#   "all_color" (3):       日志级别前缀和消息内容都带颜色（消息内容使用其默认颜色，或由函数调用时指定）。
export DISPLAY_MODE="all_color"

# 定义终端日志消息的默认格式模式（时间戳、级别、调用者信息的显示）。
# 可选值:
#   "full" (1):            标准格式，显示 [时间戳] [级别] [调用者] 消息。
#   "level_only" (2):      简化格式，只显示 [级别] 消息 (例如用于 SUCCESS)。
#   "no_prefix" (3):       最简格式，只显示 消息 (无任何前缀)。
#   "timestamp_level" (4): 显示 [时间戳] [级别] 消息 (无调用者)。
export DEFAULT_MESSAGE_FORMAT_MODE="timestamp_level"

# --- 备份文件管理默认设置 (可配置的默认值) ---
# 定义 Pacman 配置文件和镜像列表的备份文件最大保留数量
export MAX_BACKUP_FILES_PACMAN_CONF=5
export MAX_BACKUP_FILES_MIRRORLIST=5
# *** 新增：统一备份配置框架 ***
export GLOBAL_BACKUP_ROOT_RELATIVE_TO_BASE="backups" # 备份文件存放的根目录，相对于项目根目录 (BASE_DIR) 的路径
export GLOBAL_BACKUP_ROOT  # 统一的备份文件根目录的绝对上层路径 (由 environment_setup.sh 动态计算并赋值)
export DEFAULT_MAX_BACKUPS=5                 # 默认的最大备份数量


# --- 用户环境相关默认设置 (可配置的默认值) ---
export DEFAULT_EDITOR="nano" # 默认文本编辑器 (例如: nano, vim, micro)
export DEFAULT_SHELL="zsh"   # 默认 shell (例如: bash, zsh)
export DOTFILES_REPO_URL="https://github.com/your-username/your-dotfiles.git" # 你的点文件仓库URL

# --- 包管理相关默认设置 (可配置的默认值) ---
export AUR_HELPER="yay" # 默认的 AUR 助手 (例如: yay, paru)
export PACMAN_CONF_PATH="/etc/pacman.conf"
export PACMAN_MIRRORLIST_PATH="/etc/pacman.d/mirrorlist"
export PACMAN_HOOKS_DIR="/etc/pacman.d/hooks"

# --- 网络配置相关默认设置 (可配置的默认值) ---
export NETWORK_MANAGER_TYPE="systemd-networkd" # 默认网络管理器类型 (例如: NetworkManager, systemd-networkd)
export SYSTEMD_NETWORKD_CONFIG_DIR="/etc/systemd/network"

# --- 软件安装默认列表 (注意：Bash 数组无法通过 'export' 继承到子进程，仅在当前 shell 可用) ---
# declare -a PKG_ESSENTIAL_SOFTWARE=("base-devel" "git" "curl" "wget" "unzip" "tar" "htop" "neofetch" "fastfetch")
# --- 软件安装列表 (从外部文件读取) ---
# 定义存放软件包列表文件的目录，路径相对于 ASSETS_DIR
export PKG_LISTS_DIR_RELATIVE_TO_ASSETS="package_lists"

# --- 其他通用配置 (可配置的默认值) ---
export CLEAN_BUILD_CACHE="true"
