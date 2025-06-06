#!/bin/bash

# main_config.sh
# 全局配置变量：定义如日志根目录、默认 AUR 助手等全局设置。

# 项目根目录 (由通用初始化块设置)
# PROJECT_ROOT=""

# 日志配置
LOG_DIR="${PROJECT_ROOT}/log"
LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"

# AUR 助手
# 可选值: paru, yay, none
DEFAULT_AUR_HELPER="paru"

# 用户配置
# 脚本通常以 root 运行，但某些操作可能需要以原始用户身份执行
ORIGINAL_USER_NAME="" # 存储运行 sudo 的原始用户名
ORIGINAL_USER_HOME="" # 存储原始用户的主目录

# 颜色定义 (用于终端输出)
COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_MAGENTA="\033[0;35m"
COLOR_CYAN="\033[0;36m"
COLOR_WHITE="\033[0;37m"

# 其他通用配置
# 例如：默认编辑器、网络配置路径等
DEFAULT_EDITOR="nano"
SYSTEMD_NETWORKD_CONFIG_PATH="/etc/systemd/network"

# 确保日志目录存在
mkdir -p "$LOG_DIR" &>/dev/null