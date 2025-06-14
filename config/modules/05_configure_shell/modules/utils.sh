#!/bin/bash

# --- 日志文件配置 ---
# 将日志文件放在脚本所在目录的上一级，避免被意外删除或包含在 git 中（如果项目被版本控制）
# 或者放在 /tmp 或 $HOME/.cache/zsh-plugins/
# 这里我们选择放在脚本目录内，方便查找
# LOG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)/../logs" # ../logs 目录
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/zsh-plugins-install_$(date +%Y%m%d_%H%M%S).log"
# 确保日志目录存在
sudo mkdir -p "$LOG_DIR" || echo "警告：无法创建日志目录 $LOG_DIR" >&2

# 日志记录函数
# 参数: $1: 日志级别 (INFO, WARN, ERROR, STEP)
# 参数: $2: 日志消息
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # 用于控制台输出的颜色代码
    local color_reset="\e[0m"
    local color_info="\e[34m" # Blue
    local color_warn="\e[33m" # Yellow
    local color_error="\e[31m" # Red
    local color_step="\e[32m" # Green

    # 格式化控制台消息
    local console_message=""
    case "$level" in
        INFO)
            console_message="${color_info}[${timestamp}] [INFO] ${message}${color_reset}"
            ;;
        WARN)
            console_message="${color_warn}[${timestamp}] [WARN] ${message}${color_reset}"
            ;;
        ERROR)
            console_message="${color_error}[${timestamp}] [ERROR] ${message}${color_reset}"
            ;;
        STEP)
            # STEP 级别递增全局计数器
            ((GLOBAL_STEP_COUNTER++))
            # STEP 级别在控制台添加换行以突出显示
            console_message="\n${color_step}>>> [STEP ${GLOBAL_STEP_COUNTER}] ${message}${color_reset}\n"
            ;;
        *)
            console_message="[${timestamp}] ${message}" # 无级别或未知级别
            ;;
    esac

    # 打印到控制台 (根据级别决定标准输出或标准错误)
    if [ "$level" == "ERROR" ] || [ "$level" == "WARN" ]; then
        echo -e "$console_message" >&2
    else
        echo -e "$console_message"
    fi

    # 格式化文件日志消息 (无颜色)
    local file_message=""
     case "$level" in
        INFO|WARN|ERROR)
             file_message="[${timestamp}] [${level}] ${message}"
             ;;
        STEP)
             # 文件日志也包含步骤编号
             file_message="[${timestamp}] [STEP ${GLOBAL_STEP_COUNTER}] ${message}"
             ;;
        *)
             file_message="[${timestamp}] ${message}"
             ;;
     esac

    # 追加到日志文件
    # 检查 LOG_FILE 变量是否已设置且非空
    if [ -n "$LOG_FILE" ]; then
        echo "$file_message" >> "$LOG_FILE"
    fi
}

# 检查命令是否存在
# 参数: $1: 命令名称
# 返回: 0 如果存在, 1 如果不存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检测包管理器
# 返回: 包管理器命令 (pacman, apt, dnf, brew, yum) 或 "unknown"
detect_package_manager() {
    if command_exists pacman; then
        echo "pacman"
    elif command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists brew; then
        echo "brew"
    elif command_exists yum; then
        echo "yum" # CentOS 旧版本
    else
        echo "unknown"
    fi
}

# 获取包管理器更新命令
# 参数: $1: 包管理器名称
get_update_command() {
    case "$1" in
        pacman) echo "sudo pacman -Syu --noconfirm" ;;
        apt) echo "sudo apt-get update" ;;
        dnf) echo "sudo dnf check-update" ;;
        brew) echo "brew update" ;;
        yum) echo "sudo yum check-update" ;;
        *) echo "" ;;
    esac
}

# 获取包管理器安装命令
# 参数: $1: 包管理器名称
# 参数: $@: 要安装的包列表 (从 $2 开始)
get_install_command() {
    local pm="$1"
    shift
    local packages="$@"
    case "$pm" in
        pacman) echo "sudo pacman -S --noconfirm --needed $packages" ;;
        apt) echo "sudo apt-get install -y $packages" ;;
        dnf) echo "sudo dnf install -y $packages" ;;
        brew) echo "brew install $packages" ;;
        yum) echo "sudo yum install -y $packages" ;;
        *) echo "" ;;
    esac
}

# 用户确认提示
# 参数: $1: 提示信息
# 返回: 0 如果用户确认 (y/Y), 1 如果用户取消 (n/N)
prompt_confirm() {
    local message="$1"
    local response
    while true; do
        read -p "$message [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"") # 默认为 No
                return 1
                ;;
            *)
                log WARN "请输入 'y' 或 'n'."
                ;;
        esac
    done
}

# 用户选择提示
# 参数: $1: 提示信息
# 参数: $@: 选项列表 (从 $2 开始)
# 返回: 用户选择的选项索引 (从 1 开始)
prompt_choice() {
    local message="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local choice

    echo "$message"
    for i in "${!options[@]}"; do
        echo "  $(($i + 1)). ${options[$i]}"
    done

    while true; do
        read -p "请输入选项编号 (1-$num_options): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_options" ]; then
            return "$choice"
        else
            log WARN "无效的输入，请输入 1 到 $num_options 之间的数字。"
        fi
    done
}

# 检查目录是否存在且为 Oh My Zsh 插件目录
# 参数: $1: 插件名称 (例如 zsh-syntax-highlighting)
is_omz_plugin_installed() {
    local plugin_name="$1"
    # 使用 USER_HOME
    local plugin_dir="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}/plugins/${plugin_name}"
    [ -d "$plugin_dir" ] && [ -n "$(ls -A "$plugin_dir")" ]
}

# 检查 Powerlevel10k 主题是否存在
is_p10k_theme_installed() {
    # 使用 USER_HOME
    local theme_dir="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}/themes/powerlevel10k"
    [ -d "$theme_dir" ] && [ -f "${theme_dir}/powerlevel10k.zsh-theme" ]
}

# 检查字体是否可能已安装 (基于常见名称模式)
# 注意: 这只是一个启发式检查，不保证完全准确
# 参数: $1: 字体名称模式 (例如 MesloLGS)
is_font_installed_heuristic() {
    local font_pattern="$1"
    # 检查 Linux/macOS 的常见字体目录
    # 使用 USER_HOME
    local font_dirs=(
        "${USER_HOME}/.local/share/fonts"
        "${USER_HOME}/.fonts"
        "/usr/local/share/fonts"
        "/usr/share/fonts"
        "/Library/Fonts" # macOS 系统字体
        "${USER_HOME}/Library/Fonts" # macOS 用户字体
    )
    for dir in "${font_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # 使用 find 查找包含模式的文件名，忽略大小写
            if find "$dir" -iname "*${font_pattern}*" -print -quit | grep -q .; then
                return 0 # 找到匹配的字体文件
            fi
        fi
    done
    return 1 # 未找到
}

# 运行命令并记录日志
# 参数: $@: 要执行的命令及其参数
run_command() {
    log INFO "执行命令: $@"
    if "$@"; then
        log INFO "命令成功执行: $@"
        return 0
    else
        log ERROR "命令执行失败: $@"
        return 1
    fi
}

# 运行需要 sudo 的命令并记录日志
# 参数: $@: 要执行的命令及其参数
run_sudo_command() {
    log INFO "执行需要 sudo 的命令: $@"
    if sudo "$@"; then
        log INFO "命令成功执行: sudo $@"
        return 0
    else
        log ERROR "命令执行失败: sudo $@"
        return 1
    fi
}

# 备份文件
# 参数: $1: 要备份的文件路径
backup_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local backup_path="${filepath}.backup_$(date +%Y%m%d_%H%M%S)"
        log INFO "备份文件 '$filepath' 到 '$backup_path'"
        if cp "$filepath" "$backup_path"; then
            log INFO "备份成功。"
            return 0
        else
            log ERROR "备份文件 '$filepath' 失败！"
            return 1
        fi
    elif [ -e "$filepath" ]; then
        log WARN "路径 '$filepath' 存在但不是一个普通文件，无法备份。"
        return 1
    else
        # log INFO "文件 '$filepath' 不存在，无需备份。"
        return 0 # 文件不存在，视为成功（无需操作）
    fi
}
