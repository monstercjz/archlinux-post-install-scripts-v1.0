#!/bin/bash

# Source utility functions if run standalone, or rely on parent script sourcing
if [ -z "$UTILS_PATH" ]; then
    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    UTILS_PATH="$SCRIPT_DIR/utils.sh"
    if [ ! -f "$UTILS_PATH" ]; then
        echo "错误：无法找到 utils.sh 脚本！路径: $UTILS_PATH"
        exit 1
    fi
    # shellcheck source=./utils.sh
    source "$UTILS_PATH"
fi

# Powerlevel10k 推荐字体下载链接 (来自 p10k 官方仓库)
# 确保这些 URL 是最新的
declare -A FONT_URLS
FONT_URLS=(
    ["MesloLGS NF Regular.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    ["MesloLGS NF Bold.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    ["MesloLGS NF Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    ["MesloLGS NF Bold Italic.ttf"]="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)

# 检测操作系统类型
get_os_type() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        CYGWIN*|MINGW*|MSYS*) echo "windows";; # Git Bash 等环境
        *)          echo "unknown";;
    esac
}

# 获取字体安装目录
# 参数: $1: 操作系统类型 (linux, macos)
get_font_install_dir() {
    local os_type="$1"
    local font_dir=""

    if [ "$os_type" == "linux" ]; then
        # 优先使用用户目录，使用 USER_HOME
        font_dir="${USER_HOME}/.local/share/fonts"
        # 如果不存在，尝试系统目录 (需要 sudo)
        # if [ ! -d "$font_dir" ]; then
        #     font_dir="/usr/local/share/fonts"
        # fi
         # 如果用户目录不存在，则创建它
        if [ ! -d "$font_dir" ]; then
            log INFO "创建用户字体目录: $font_dir"
            # 创建目录时也考虑 sudo
            if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
                 run_command sudo mkdir -p "$font_dir"
                 run_command sudo chown "$ORIGINAL_USER:$ORIGINAL_USER" "$font_dir" # 确保所有权
            else
                 mkdir -p "$font_dir" || { log ERROR "创建目录 $font_dir 失败！"; return 1; }
            fi
        fi

    elif [ "$os_type" == "macos" ]; then
        # 使用 USER_HOME
        font_dir="${USER_HOME}/Library/Fonts"
    else
        log ERROR "不支持的操作系统类型 '$os_type' 用于字体安装。"
        return 1
    fi

    echo "$font_dir"
    return 0
}

# 下载字体文件
# 参数: $1: 字体文件名
# 参数: $2: 下载 URL
# 参数: $3: 目标目录
download_font() {
    local font_name="$1"
    local url="$2"
    local dest_dir="$3"
    local dest_path="$dest_dir/$font_name"

    log INFO "下载字体 '$font_name' 从 $url 到 $dest_path"

    # 检查字体是否已存在
    if [ -f "$dest_path" ]; then
        log INFO "字体 '$font_name' 已存在于 '$dest_dir'。跳过下载。"
        # 在强制模式下可以考虑覆盖
        # if [ "$INSTALL_MODE" == "force" ]; then
        #    log WARN "强制模式：覆盖现有字体 '$font_name'"
        # else
             return 0 # 非强制模式下，存在即成功
        # fi
    fi

    # 使用 curl 或 wget 下载
    if command_exists curl; then
        if run_command curl -fLo "$dest_path" "$url"; then
            log INFO "字体 '$font_name' 下载成功 (使用 curl)。"
            return 0
        else
            log ERROR "字体 '$font_name' 下载失败 (使用 curl)。"
            # 清理可能不完整的文件
            rm -f "$dest_path"
            return 1
        fi
    elif command_exists wget; then
        if run_command wget -O "$dest_path" "$url"; then
            log INFO "字体 '$font_name' 下载成功 (使用 wget)。"
            return 0
        else
            log ERROR "字体 '$font_name' 下载失败 (使用 wget)。"
            rm -f "$dest_path"
            return 1
        fi
    else
        log ERROR "未找到 curl 或 wget，无法下载字体。"
        return 1
    fi
}

# 更新字体缓存 (仅 Linux)
update_font_cache() {
    if command_exists fc-cache; then
        log INFO "更新字体缓存..."
        if run_command fc-cache -fv; then
            log INFO "字体缓存更新成功。"
            return 0
        else
            log WARN "字体缓存更新失败 (fc-cache -fv)。可能需要手动运行。"
            return 1
        fi
    else
        log WARN "未找到 'fc-cache' 命令，无法自动更新字体缓存。"
        log INFO "您可能需要重新登录或重启系统以使新字体生效。"
        return 1 # 标记为未完成
    fi
}

# 主字体安装函数
install_meslolgs_fonts() {
    log STEP "开始安装 MesloLGS Nerd Font..."
    local os_type
    os_type=$(get_os_type)

    if [ "$os_type" == "windows" ] || [ "$os_type" == "unknown" ]; then
        log ERROR "此脚本不支持在 '$os_type' 上自动安装字体。"
        log INFO "请手动下载并安装 MesloLGS Nerd Font:"
        for name in "${!FONT_URLS[@]}"; do
            echo "  - $name: ${FONT_URLS[$name]}"
        done
        log INFO "下载后，双击字体文件并点击 '安装'。"
        return 1 # 标记为失败，因为需要手动操作
    fi

    local font_install_dir
    font_install_dir=$(get_font_install_dir "$os_type")
    if [ $? -ne 0 ] || [ -z "$font_install_dir" ]; then
        log ERROR "无法确定字体安装目录。"
        return 1
    fi

    log INFO "字体将安装到: $font_install_dir"
    # 确保目录存在 (get_font_install_dir 已处理)
    # mkdir -p "$font_install_dir"

    local all_success=true
    for name in "${!FONT_URLS[@]}"; do
        if ! download_font "$name" "${FONT_URLS[$name]}" "$font_install_dir"; then
            all_success=false
        fi
    done

    if ! $all_success; then
        log ERROR "部分或全部字体下载失败。"
        # 不一定是致命错误，但需要告知用户
    fi

    # 更新字体缓存 (仅 Linux)
    # fc-cache 通常需要以普通用户身份运行才能更新用户缓存
    if [ "$os_type" == "linux" ]; then
        if command_exists fc-cache; then
            log INFO "更新字体缓存..."
            local fc_cmd="fc-cache -fv"
            if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
                 log INFO "尝试以用户 '$ORIGINAL_USER' 身份运行 fc-cache..."
                 if run_command sudo runuser -l "$ORIGINAL_USER" -c "$fc_cmd"; then
                     log INFO "字体缓存更新成功 (以用户 $ORIGINAL_USER 运行)。"
                 else
                     log WARN "以用户 '$ORIGINAL_USER' 身份运行 fc-cache 失败。可能需要手动运行。"
                     all_success=false # 标记为未完全成功
                 fi
            else
                 if run_command $fc_cmd; then
                     log INFO "字体缓存更新成功。"
                 else
                     log WARN "字体缓存更新失败 (fc-cache -fv)。可能需要手动运行。"
                     all_success=false # 标记为未完全成功
                 fi
            fi
        else
             log WARN "未找到 'fc-cache' 命令，无法自动更新字体缓存。"
             log INFO "您可能需要重新登录或重启系统以使新字体生效。"
             all_success=false # 标记为未完全成功
        fi
    elif [ "$os_type" == "macos" ]; then
        log INFO "在 macOS 上，字体通常会自动被识别。如果终端未立即显示新字体，请尝试重启终端或系统。"
    fi

    if $all_success; then
        log INFO "MesloLGS Nerd Font 安装完成。"
        log INFO "请确保在您的终端模拟器设置中选择 'MesloLGS NF' 字体以获得最佳 Powerlevel10k 显示效果。"
        return 0
    else
        log WARN "字体安装过程中遇到问题。请检查日志。"
        return 1
    fi
}

# 如果直接运行此脚本，则执行安装
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_meslolgs_fonts
fi
