#!/bin/bash

# Source utility functions
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
UTILS_PATH="$SCRIPT_DIR/utils.sh"
if [ ! -f "$UTILS_PATH" ]; then
    echo "错误：无法找到 utils.sh 脚本！路径: $UTILS_PATH"
    exit 1
fi
# shellcheck source=./utils.sh
source "$UTILS_PATH"

# 定义需要检查的软件和插件
declare -A SOFTWARE_CHECKS
SOFTWARE_CHECKS=(
    ["zsh"]="zsh"
    ["fzf"]="fzf"
    ["bat"]="bat" # 或者 batcat 在某些发行版上
    ["eza"]="eza"
    ["git"]="git"
    ["curl"]="curl"
    ["wget"]="wget"
    ["oh-my-zsh"]="$HOME/.oh-my-zsh" # 检查目录
    ["zsh-syntax-highlighting"]="zsh-syntax-highlighting" # OMZ 插件
    ["zsh-autosuggestions"]="zsh-autosuggestions" # OMZ 插件
    ["fzf-tab"]="fzf-tab" # OMZ 插件
    ["powerlevel10k"]="powerlevel10k" # OMZ 主题
    ["meslolgs-font"]="MesloLGS" # 字体模式
)
# 使用 USER_HOME 更新 oh-my-zsh 检查路径
SOFTWARE_CHECKS["oh-my-zsh"]="${USER_HOME}/.oh-my-zsh"

# 定义必需的依赖项 (包管理器特定的名称)
declare -A DEPENDENCIES
# 添加不同包管理器的依赖项名称
# 例如: DEPENDENCIES["pacman"]="base-devel git curl wget"
#       DEPENDENCIES["apt"]="build-essential git curl wget"
#       DEPENDENCIES["dnf"]="@development-tools git curl wget"
#       DEPENDENCIES["brew"]="git curl wget" # macOS 通常自带开发工具
#       DEPENDENCIES["yum"]="@development git curl wget"
# 这里暂时只包含通用依赖，具体包管理器依赖在 check_dependencies 中处理
COMMON_DEPENDENCIES="git curl wget"

# 存储检查结果
declare -A CHECK_RESULTS
declare -A DEPENDENCY_RESULTS

# 检查单个软件/插件
# 参数: $1: 检查项的键名 (来自 SOFTWARE_CHECKS)
# 返回: 0 如果已安装, 1 如果未安装
check_item() {
    local key="$1"
    local value="${SOFTWARE_CHECKS[$key]}"
    local check_type="command" # 默认为检查命令

    # 根据键名判断检查类型
    if [[ "$key" == "oh-my-zsh" ]]; then
        check_type="directory"
    elif [[ "$key" == *"-font" ]]; then
        check_type="font"
    elif [[ "$key" == "zsh-syntax-highlighting" || "$key" == "zsh-autosuggestions" || "$key" == "fzf-tab" ]]; then
        check_type="omz_plugin"
    elif [[ "$key" == "powerlevel10k" ]]; then
        check_type="omz_theme"
    fi

    case "$check_type" in
        command)
            if command_exists "$value"; then
                CHECK_RESULTS["$key"]="已安装"
                return 0
            # 特殊处理 bat/batcat
            elif [ "$key" == "bat" ] && command_exists "batcat"; then
                 CHECK_RESULTS["$key"]="已安装 (batcat)"
                 # 将 bat 的值更新为 batcat 以便后续安装检查
                 SOFTWARE_CHECKS["bat"]="batcat"
                 return 0
            else
                CHECK_RESULTS["$key"]="未安装"
                return 1
            fi
            ;;
        directory)
            if [ -d "$value" ]; then
                CHECK_RESULTS["$key"]="已安装"
                return 0
            else
                CHECK_RESULTS["$key"]="未安装"
                return 1
            fi
            ;;
        omz_plugin)
            if is_omz_plugin_installed "$value"; then
                CHECK_RESULTS["$key"]="已安装"
                return 0
            else
                CHECK_RESULTS["$key"]="未安装"
                return 1
            fi
            ;;
        omz_theme)
             if is_p10k_theme_installed; then
                CHECK_RESULTS["$key"]="已安装"
                return 0
            else
                CHECK_RESULTS["$key"]="未安装"
                return 1
            fi
            ;;
        font)
            if is_font_installed_heuristic "$value"; then
                CHECK_RESULTS["$key"]="可能已安装" # 字体检查不完全可靠
                return 0
            else
                CHECK_RESULTS["$key"]="未安装"
                return 1
            fi
            ;;
        *)
            log ERROR "未知的检查类型: $check_type for key $key"
            CHECK_RESULTS["$key"]="检查错误"
            return 1
            ;;
    esac
}

# 执行所有软件和插件检查
perform_checks() {
    log STEP "开始检查系统环境和已安装的软件/插件..."
    local all_installed=true
    for key in "${!SOFTWARE_CHECKS[@]}"; do
        if ! check_item "$key"; then
            all_installed=false
        fi
    done

    echo "----------------------------------------"
    echo " 检查结果:"
    echo "----------------------------------------"
    printf "%-30s %s\n" "软件/插件" "状态"
    echo "----------------------------------------"
    for key in "${!SOFTWARE_CHECKS[@]}"; do
        printf "%-30s %s\n" "$key" "${CHECK_RESULTS[$key]}"
    done
    echo "----------------------------------------"

    if $all_installed && [[ ! " ${CHECK_RESULTS[*]} " =~ " 可能已安装 " ]]; then # 如果字体不是“可能已安装”
        log INFO "所有必需的软件和插件似乎都已安装。"
        INSTALL_MODE="skip" # 默认跳过
        prompt_choice "您想如何操作？" \
            "强制全部重新安装" \
            "跳过安装，仅执行配置检查" \
            "取消"
        local choice=$?
        case $choice in
            1) INSTALL_MODE="force";;
            2) INSTALL_MODE="skip_install";; # 新增模式，跳过安装但执行配置
            3) INSTALL_MODE="cancel";;
        esac
    else
        log INFO "部分软件/插件未安装或需要确认。"
         prompt_choice "请选择安装模式:" \
            "仅安装未安装的项" \
            "强制全部重新安装" \
            "取消本次安装"
        local choice=$?
        case $choice in
            1) INSTALL_MODE="missing";;
            2) INSTALL_MODE="force";;
            3) INSTALL_MODE="cancel";;
        esac
    fi

    if [ "$INSTALL_MODE" == "cancel" ]; then
        log INFO "用户选择取消安装。"
        exit 0
    fi

    log INFO "用户选择的安装模式: $INSTALL_MODE"
}

# 检查必需的依赖项
# 参数: $1: 包管理器名称
check_dependencies() {
    local pm="$1"
    log STEP "检查必需的依赖项..."

    local required_deps="$COMMON_DEPENDENCIES"
    local missing_deps=()
    local dep_install_cmd=""

    # 添加特定于包管理器的开发工具依赖
    case "$pm" in
        pacman) required_deps+=" base-devel" ;;
        apt)    required_deps+=" build-essential" ;;
        dnf)    required_deps+=" @development-tools" ;;
        yum)    required_deps+=" @development" ;;
        # brew 通常不需要显式安装 build tools
    esac

    log INFO "需要的依赖项: $required_deps"

    for dep in $required_deps; do
        if ! command_exists "$dep"; then
            # 特殊处理 dnf/yum 的组包
            if [[ ("$pm" == "dnf" || "$pm" == "yum") && "$dep" == "@"* ]]; then
                 # 检查组包是否安装比较复杂，这里简化为只要命令不存在就认为需要安装
                 # 更精确的检查可以使用类似 `dnf group info` 的命令
                 log WARN "依赖组 '$dep' 可能未完全安装 (检查命令 '$dep' 不存在)。"
                 missing_deps+=("$dep")
                 DEPENDENCY_RESULTS["$dep"]="未安装"
            elif [[ "$pm" == "apt" && "$dep" == "build-essential" ]]; then
                 # 检查 build-essential 是否安装
                 if ! dpkg -s build-essential &> /dev/null; then
                    log WARN "依赖包 '$dep' 未安装。"
                    missing_deps+=("$dep")
                    DEPENDENCY_RESULTS["$dep"]="未安装"
                 else
                    DEPENDENCY_RESULTS["$dep"]="已安装"
                 fi
            elif [[ "$pm" == "pacman" && "$dep" == "base-devel" ]]; then
                 # 检查 base-devel 组中的核心包，如 gcc make
                 if ! command_exists gcc || ! command_exists make; then
                    log WARN "依赖组 '$dep' 可能未完全安装 (gcc 或 make 不存在)。"
                    missing_deps+=("$dep")
                    DEPENDENCY_RESULTS["$dep"]="未安装"
                 else
                    DEPENDENCY_RESULTS["$dep"]="已安装"
                 fi
            else
                log WARN "依赖命令 '$dep' 未安装。"
                missing_deps+=("$dep")
                DEPENDENCY_RESULTS["$dep"]="未安装"
            fi
        else
             DEPENDENCY_RESULTS["$dep"]="已安装"
        fi
    done

    echo "----------------------------------------"
    echo " 依赖项检查结果:"
    echo "----------------------------------------"
    printf "%-30s %s\n" "依赖项" "状态"
    echo "----------------------------------------"
    for dep in $required_deps; do
        printf "%-30s %s\n" "$dep" "${DEPENDENCY_RESULTS[$dep]}"
    done
    echo "----------------------------------------"


    if [ ${#missing_deps[@]} -gt 0 ]; then
        log WARN "发现缺失的依赖项: ${missing_deps[*]}"
        dep_install_cmd=$(get_install_command "$pm" "${missing_deps[@]}")

        if [ -z "$dep_install_cmd" ]; then
             log ERROR "无法为您的包管理器 '$pm' 生成依赖安装命令。"
             log INFO "请手动安装以下依赖项: ${missing_deps[*]}"
             prompt_confirm "依赖项缺失，是否继续尝试安装主要软件？" || exit 1
             return 1 # 继续，但标记依赖不完整
        else
            prompt_choice "检测到缺失的依赖项。请选择操作：" \
                "尝试使用脚本自动安装依赖 (${missing_deps[*]})" \
                "提供手动安装指导并退出" \
                "忽略依赖问题并继续 (不推荐)" \
                "停止安装"
            local choice=$?
            case $choice in
                1)
                    log INFO "尝试自动安装依赖项..."
                    if run_sudo_command $dep_install_cmd; then
                        log INFO "依赖项安装成功。"
                        # 重新检查一次确保安装成功
                        local still_missing=()
                        for dep in "${missing_deps[@]}"; do
                            if ! command_exists "$dep"; then
                                # 再次处理特殊情况
                                if [[ ("$pm" == "dnf" || "$pm" == "yum") && "$dep" == "@"* ]]; then
                                    # 假设组包安装成功，除非有明确错误
                                    :
                                elif [[ "$pm" == "apt" && "$dep" == "build-essential" ]]; then
                                     if ! dpkg -s build-essential &> /dev/null; then still_missing+=("$dep"); fi
                                elif [[ "$pm" == "pacman" && "$dep" == "base-devel" ]]; then
                                     if ! command_exists gcc || ! command_exists make; then still_missing+=("$dep"); fi
                                elif ! command_exists "$dep"; then
                                    still_missing+=("$dep")
                                fi
                            fi
                        done
                        if [ ${#still_missing[@]} -gt 0 ]; then
                             log ERROR "自动安装后，以下依赖项仍然缺失: ${still_missing[*]}"
                             log INFO "请尝试手动安装它们。"
                             exit 1
                        else
                             log INFO "所有依赖项已满足。"
                             return 0
                        fi
                    else
                        log ERROR "依赖项自动安装失败！"
                        log INFO "请尝试手动安装以下依赖项: ${missing_deps[*]}"
                        log INFO "手动安装命令参考: $dep_install_cmd"
                        exit 1
                    fi
                    ;;
                2)
                    log INFO "请根据您的系统手动安装以下依赖项: ${missing_deps[*]}"
                    log INFO "常见的安装命令:"
                    log INFO "  Arch Linux: sudo pacman -S --needed base-devel ${missing_deps[*]}"
                    log INFO "  Debian/Ubuntu: sudo apt update && sudo apt install -y build-essential ${missing_deps[*]}"
                    log INFO "  Fedora: sudo dnf install -y @development-tools ${missing_deps[*]}"
                    log INFO "  CentOS: sudo yum groupinstall -y 'Development Tools' && sudo yum install -y ${missing_deps[*]}"
                    log INFO "  macOS (Homebrew): brew install ${missing_deps[*]}"
                    exit 0
                    ;;
                3)
                    log WARN "用户选择忽略依赖问题并继续。"
                    return 1 # 继续，但标记依赖不完整
                    ;;
                4)
                    log INFO "用户选择停止安装。"
                    exit 0
                    ;;
            esac
        fi
    else
        log INFO "所有必需的依赖项均已安装。"
        return 0
    fi
}

# 主检查流程
run_checks() {
    perform_checks # 执行软件检查并获取 INSTALL_MODE

    # 如果用户选择跳过安装，则直接返回
    if [ "$INSTALL_MODE" == "skip_install" ]; then
        log INFO "跳过安装步骤，直接进入配置检查。"
        # 设置一个全局变量或返回特定值，让主脚本知道跳过安装
        export SKIP_INSTALLATION="true"
        return 0
    fi
     export SKIP_INSTALLATION="false"


    local pm
    pm=$(detect_package_manager)
    if [ "$pm" == "unknown" ]; then
        log ERROR "无法检测到支持的包管理器 (pacman, apt, dnf, brew, yum)。"
        log INFO "请确保您的系统已安装其中之一。"
        exit 1
    else
        log INFO "检测到包管理器: $pm"
        export PACKAGE_MANAGER="$pm" # 导出供其他模块使用
    fi

    # 检查依赖项
    if ! check_dependencies "$pm"; then
        # check_dependencies 内部处理了退出或继续的逻辑
        # 如果返回 1，表示用户选择忽略依赖问题继续
        log WARN "依赖项检查未完全通过，但用户选择继续。"
    fi

    log INFO "检查阶段完成。"
    # 将检查结果导出或写入临时文件供 install 模块使用
    # 为了简单起见，这里使用全局变量（需要主脚本 source 这个文件）
    # 或者，可以将 CHECK_RESULTS 写入一个临时文件
    # 例如: declare -p CHECK_RESULTS > /tmp/check_results.dat
    # 为了在模块间传递状态，我们将 INSTALL_MODE 和 CHECK_RESULTS 导出
    export INSTALL_MODE
    # 将关联数组转换为可导出的格式
    local check_results_export=""
    for key in "${!CHECK_RESULTS[@]}"; do
        check_results_export+="CHECK_RESULTS[$key]='${CHECK_RESULTS[$key]}' "
    done
    export CHECK_RESULTS_EXPORT="$check_results_export"
    export SOFTWARE_CHECKS_EXPORT=$(declare -p SOFTWARE_CHECKS | sed 's/declare -A/declare -Ag/') # 导出关联数组定义

}

# 如果直接运行此脚本，则执行检查
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_checks
    echo "INSTALL_MODE=$INSTALL_MODE"
    echo "PACKAGE_MANAGER=$PACKAGE_MANAGER"
    echo "CHECK_RESULTS:"
    eval "$CHECK_RESULTS_EXPORT" # 重新加载导出的关联数组
    declare -p CHECK_RESULTS
fi
