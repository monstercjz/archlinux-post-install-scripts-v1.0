#!/bin/bash

# Source utility functions
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
UTILS_PATH="$SCRIPT_DIR/utils.sh"
FONTS_PATH="$SCRIPT_DIR/fonts.sh" # Path to fonts installation script

if [ ! -f "$UTILS_PATH" ]; then
    echo "错误：无法找到 utils.sh 脚本！路径: $UTILS_PATH"
    exit 1
fi
# shellcheck source=./utils.sh
source "$UTILS_PATH"

# 确保 fonts.sh 存在
if [ ! -f "$FONTS_PATH" ]; then
    log WARN "字体安装脚本 fonts.sh 未找到，将跳过字体安装。"
    # 可以选择退出 exit 1，或者继续但跳过字体
fi

# --- 安装函数 ---

# 使用包管理器安装软件包
# 参数: $1: 包管理器名称
# 参数: $@: 要安装的包列表 (从 $2 开始)
install_package_manager_pkgs() {
    local pm="$1"
    shift
    local pkgs_to_install=("$@")

    if [ ${#pkgs_to_install[@]} -eq 0 ]; then
        log INFO "没有需要通过包管理器安装的软件包。"
        return 0
    fi

    log STEP "使用 $pm 安装软件包: ${pkgs_to_install[*]}"
    local install_cmd
    install_cmd=$(get_install_command "$pm" "${pkgs_to_install[@]}")

    if [ -z "$install_cmd" ]; then
        log ERROR "无法为包管理器 '$pm' 生成安装命令。"
        return 1
    fi

    # 更新包列表 (对于 apt 和 dnf/yum 比较重要)
    local update_cmd
    update_cmd=$(get_update_command "$pm")
    if [[ "$pm" == "apt" || "$pm" == "dnf" || "$pm" == "yum" ]] && [ -n "$update_cmd" ]; then
        log INFO "更新包列表..."
        # if ! run_sudo_command $update_cmd; then
        if ! $update_cmd; then
            log WARN "包列表更新失败，但仍尝试继续安装。"
        fi
    fi

    if run_sudo_command $install_cmd; then
        log INFO "软件包安装成功: ${pkgs_to_install[*]}"
        return 0
    else
        log ERROR "软件包安装失败: ${pkgs_to_install[*]}"
        return 1
    fi
}

# 安装 Oh My Zsh
install_oh_my_zsh() {
    log STEP "安装 Oh My Zsh..."
    # 使用 USER_HOME
    local oh_my_zsh_dir="${USER_HOME}/.oh-my-zsh"

    if [ -d "$oh_my_zsh_dir" ]; then
        log INFO "Oh My Zsh 目录 '$oh_my_zsh_dir' 已存在，将尝试更新..."
        # 此处备份为后期手动添加
        log INFO "更新之前先备份.zshrc文件"
        if [ -f "${USER_HOME}/.zshrc" ]; then
            local backup_file="${USER_HOME}/.zshrc.backup.byohmyzshinstall.$(date +'%Y%m%d_%H%M%S')"
            log INFO "备份当前 .zshrc 文件到: $backup_file"
            if ! run_command cp "${USER_HOME}/.zshrc" "$backup_file"; then
                log ERROR "备份 .zshrc 文件失败！"
            fi
        else
            log ERROR "未找到 .zshrc 文件，无法备份。"
        fi
        # 更新操作需要在目标用户下执行
        local update_cmd="ZSH=\"$oh_my_zsh_dir\" sh \"$oh_my_zsh_dir/tools/upgrade.sh\""
        local update_success=false
        if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
            if run_command sudo runuser -l "$ORIGINAL_USER" -c "$update_cmd"; then
                update_success=true
            fi
        else
            if ZSH="$oh_my_zsh_dir" sh "$oh_my_zsh_dir/tools/upgrade.sh"; then
                update_success=true
            fi
        fi

        if $update_success; then
             log INFO "Oh My Zsh 更新成功。"
        else
             log WARN "Oh My Zsh 更新失败。可能需要手动干预。"
             # 即使更新失败，也可能可以继续安装插件
        fi
        # 注意：强制模式下，我们可能需要先删除旧目录
        # if [ "$INSTALL_MODE" == "force" ]; then
        #     log WARN "强制模式：正在删除旧的 Oh My Zsh 目录: $oh_my_zsh_dir"
        #     # 删除操作也需要考虑 sudo
        #     local rm_cmd="rm -rf \"$oh_my_zsh_dir\""
        #     if [ "$EUID" -eq 0 ]; then
        #         if ! run_sudo_command $rm_cmd; then log ERROR "删除旧的 Oh My Zsh 目录失败！"; return 1; fi
        #     else
        #         if ! run_command $rm_cmd; then log ERROR "删除旧的 Oh My Zsh 目录失败！"; return 1; fi
        #     fi
        # else
             return 0 # 非强制模式下，存在即视为成功（或已尝试更新）
        # fi
    fi

    # 使用官方安装脚本安装
    log INFO "尝试使用官方脚本安装 Oh My Zsh 到 '$oh_my_zsh_dir'..."
    # 此处备份为后期手动添加
    log INFO "安装之前先备份.zshrc文件"
        if [ -f "${USER_HOME}/.zshrc" ]; then
            local backup_file="${USER_HOME}/.zshrc.backup.byohmyzshinstall.$(date +'%Y%m%d_%H%M%S')"
            log INFO "备份当前 .zshrc 文件到: $backup_file"
            if ! run_command cp "${USER_HOME}/.zshrc" "$backup_file"; then
                log ERROR "备份 .zshrc 文件失败！"
            fi
        else
            log ERROR "未找到 .zshrc 文件，无法备份。"
        fi
    local install_script_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    local fetch_cmd=""

    if command_exists curl; then
        fetch_cmd="curl -fsSL $install_script_url"
    elif command_exists wget; then
        fetch_cmd="wget -O- $install_script_url"
    else
        log ERROR "未找到 curl 或 wget，无法下载 Oh My Zsh 安装脚本。"
        return 1
    fi

    local script_content
    script_content=$(eval "$fetch_cmd") # 获取脚本内容

    if [ -z "$script_content" ]; then
        log ERROR "无法下载 Oh My Zsh 安装脚本内容。"
        return 1
    fi

    # 使用 runuser 或 sh -c 在目标用户下执行安装脚本
    local install_success=false
    local install_shell_cmd="ZSH=\"$oh_my_zsh_dir\" sh -s -- --unattended --keep-zshrc" # 使用 --keep-zshrc

    if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
        log INFO "使用 'runuser -l $ORIGINAL_USER -c ...' 来为目标用户安装 Oh My Zsh"
        if echo "$script_content" | run_command sudo runuser -l "$ORIGINAL_USER" -c "$install_shell_cmd"; then
             install_success=true
             log INFO "Oh My Zsh 安装命令已为用户 '$ORIGINAL_USER' 执行。"
        else
             log ERROR "为用户 '$ORIGINAL_USER' 执行 Oh My Zsh 安装命令失败。"
        fi
    else
         # 普通用户直接运行
         if echo "$script_content" | run_command sh -s -- --unattended --keep-zshrc; then
            install_success=true
            log INFO "Oh My Zsh 安装成功。"
         else
            log ERROR "Oh My Zsh 安装失败。"
         fi
    fi

    # 验证安装
    if $install_success; then
        if [ ! -d "$oh_my_zsh_dir/.git" ]; then # 检查 .git 目录是否存在作为基本验证
            log ERROR "Oh My Zsh 安装后验证失败 (目录 '$oh_my_zsh_dir' 不是 git 仓库)。"
            return 1
        fi
        log INFO "Oh My Zsh 安装验证成功。"
        return 0
    else
        return 1
    fi
}

# 安装 Oh My Zsh 插件
# 参数: $1: 插件名称 (例如 zsh-syntax-highlighting)
# 参数: $2: 插件的 Git 仓库 URL
install_omz_plugin() {
    local plugin_name="$1"
    local repo_url="$2"
    # 使用 USER_HOME
    local plugin_dir="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}/plugins/${plugin_name}"
    local custom_plugins_dir
    custom_plugins_dir=$(dirname "$plugin_dir")

    log STEP "安装/更新 Oh My Zsh 插件: $plugin_name 到 $plugin_dir"

    # 确保目标目录的所有权正确（如果以 sudo 运行）
    if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
        # 确保 custom/plugins 目录存在且属于目标用户
        run_command sudo mkdir -p "$custom_plugins_dir"
        # chown 父目录 .oh-my-zsh/custom
        run_command sudo chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$(dirname "$custom_plugins_dir")" || log WARN "无法更改 '$custom_plugins_dir' 父目录的所有权"
    else
         mkdir -p "$custom_plugins_dir" # 普通用户直接创建
    fi


    if [ -d "$plugin_dir" ]; then
        log INFO "插件目录 '$plugin_dir' 已存在。"
        if [ "$INSTALL_MODE" == "force" ]; then
            log WARN "强制模式：正在删除旧的插件目录: $plugin_dir"
            # 删除操作也可能需要 sudo
            local rm_cmd="rm -rf \"$plugin_dir\""
            if [ "$EUID" -eq 0 ]; then
                if ! run_sudo_command $rm_cmd; then
                    log ERROR "删除旧插件目录 '$plugin_dir' 失败！"
                    return 1
                fi
            else
                 if ! run_command $rm_cmd; then
                    log ERROR "删除旧插件目录 '$plugin_dir' 失败！"
                    return 1
                fi
            fi
            # 删除后继续执行 git clone
        else
            log INFO "尝试更新插件 '$plugin_name'..."
            # 更新操作需要在目标用户下执行
            local update_cmd="cd \"$plugin_dir\" && git pull"
            local update_success=false
            if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
                 if run_command sudo runuser -l "$ORIGINAL_USER" -c "$update_cmd"; then
                     update_success=true
                 fi
            else
                 # 必须在子 shell 中执行 cd
                 if (cd "$plugin_dir" && git pull); then
                     update_success=true
                 fi
            fi

            if $update_success; then
                 log INFO "插件 '$plugin_name' 更新成功。"
                 return 0
            else
                 log WARN "插件 '$plugin_name' 更新失败。可能需要手动干预。"
                 # 如果更新失败，尝试删除并重新克隆
                 log WARN "尝试删除并重新克隆插件 '$plugin_name'..."
                 local rm_cmd="rm -rf \"$plugin_dir\""
                 local clone_failed=false
                 if [ "$EUID" -eq 0 ]; then
                      if ! run_sudo_command $rm_cmd; then clone_failed=true; fi
                 else
                      if ! run_command $rm_cmd; then clone_failed=true; fi
                 fi

                 if $clone_failed; then
                      log ERROR "删除插件目录 '$plugin_dir' 失败！无法重新克隆。"
                      return 1
                 fi
                 # 继续执行下面的 git clone
            fi
        fi
    fi

    # 如果目录不存在或已被删除，则克隆
    if [ ! -d "$plugin_dir" ]; then
        log INFO "克隆插件 '$plugin_name' 从 $repo_url 到 $plugin_dir"
        # 克隆操作需要在目标用户下执行
        local clone_cmd="git clone --depth=1 \"$repo_url\" \"$plugin_dir\""
        local clone_success=false
        if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
             if run_command sudo runuser -l "$ORIGINAL_USER" -c "$clone_cmd"; then
                 clone_success=true
             fi
        else
             if run_command git clone --depth=1 "$repo_url" "$plugin_dir"; then
                 clone_success=true
             fi
        fi

        if $clone_success; then
             log INFO "插件 '$plugin_name' 克隆成功。"
             return 0
        else
             log ERROR "插件 '$plugin_name' 克隆失败！"
             return 1
        fi
    fi
     return 0 # 如果更新成功或无需操作
}

# 安装 Powerlevel10k 主题
install_powerlevel10k() {
    local theme_name="powerlevel10k"
    local repo_url="https://github.com/romkatv/powerlevel10k.git"
    # 使用 USER_HOME
    local theme_dir="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}/themes/${theme_name}"
    local custom_themes_dir
    custom_themes_dir=$(dirname "$theme_dir")

    log STEP "安装/更新 Powerlevel10k 主题..."

     # 确保目标目录的所有权正确（如果以 sudo 运行）
    if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
        run_command sudo mkdir -p "$custom_themes_dir"
        run_command sudo chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$(dirname "$custom_themes_dir")" || log WARN "无法更改 '$custom_themes_dir' 父目录的所有权"
    else
         mkdir -p "$custom_themes_dir"
    fi

    if [ -d "$theme_dir" ]; then
        log INFO "主题目录 '$theme_dir' 已存在。"
         if [ "$INSTALL_MODE" == "force" ]; then
            log WARN "强制模式：正在删除旧的主题目录: $theme_dir"
            local rm_cmd="rm -rf \"$theme_dir\""
             if [ "$EUID" -eq 0 ]; then
                 if ! run_sudo_command $rm_cmd; then
                     log ERROR "删除旧主题目录 '$theme_dir' 失败！"
                     return 1
                 fi
             else
                 if ! run_command $rm_cmd; then
                     log ERROR "删除旧主题目录 '$theme_dir' 失败！"
                     return 1
                 fi
             fi
         else
             log INFO "尝试更新主题 '$theme_name'..."
             local update_cmd="cd \"$theme_dir\" && git pull"
             local update_success=false
             if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
                 if run_command sudo runuser -l "$ORIGINAL_USER" -c "$update_cmd"; then update_success=true; fi
             else
                 if (cd "$theme_dir" && git pull); then update_success=true; fi
             fi

             if $update_success; then
                 log INFO "主题 '$theme_name' 更新成功。"
                 return 0
             else
                 log WARN "主题 '$theme_name' 更新失败。可能需要手动干预。"
                 log WARN "尝试删除并重新克隆主题 '$theme_name'..."
                 local rm_cmd="rm -rf \"$theme_dir\""
                 local clone_failed=false
                 if [ "$EUID" -eq 0 ]; then
                     if ! run_sudo_command $rm_cmd; then clone_failed=true; fi
                 else
                     if ! run_command $rm_cmd; then clone_failed=true; fi
                 fi
                 if $clone_failed; then
                     log ERROR "删除主题目录 '$theme_dir' 失败！无法重新克隆。"
                     return 1
                 fi
                 # 继续执行下面的 git clone
             fi
         fi
    fi

    if [ ! -d "$theme_dir" ]; then
        log INFO "克隆主题 '$theme_name' 从 $repo_url 到 $theme_dir"
        # 克隆操作需要在目标用户下执行
        # Powerlevel10k 推荐克隆完整历史记录
        local clone_cmd="git clone \"$repo_url\" \"$theme_dir\""
        local clone_success=false
         if [ "$EUID" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
             if run_command sudo runuser -l "$ORIGINAL_USER" -c "$clone_cmd"; then
                 clone_success=true
             fi
         else
             if run_command git clone "$repo_url" "$theme_dir"; then
                 clone_success=true
             fi
         fi

         if $clone_success; then
             log INFO "主题 '$theme_name' 克隆成功。"
             return 0
         else
             log ERROR "主题 '$theme_name' 克隆失败！"
             return 1
         fi
    fi
    return 0
}

# 安装字体 (委托给 fonts.sh)
install_fonts() {
    log STEP "安装 Powerlevel10k 推荐字体 (MesloLGS NF)..."
    if [ -f "$FONTS_PATH" ]; then
        # shellcheck source=./fonts.sh
        source "$FONTS_PATH"
        # fonts.sh 内部需要处理 sudo 和 USER_HOME
        if install_meslolgs_fonts; then
            log INFO "字体安装/检查完成。"
            return 0
        else
            log ERROR "字体安装失败。"
            return 1
        fi
    else
        log WARN "字体安装脚本 fonts.sh 未找到，跳过字体安装。"
        return 1 # 标记为失败，因为字体是 p10k 的重要部分
    fi
}


# --- 主安装逻辑 ---

run_installation() {
    log STEP "开始执行安装流程..."

    # 检查必需的变量是否已设置 (由 check.sh 导出)
    if [ -z "$INSTALL_MODE" ] || [ -z "$PACKAGE_MANAGER" ] || [ -z "$CHECK_RESULTS_EXPORT" ] || [ -z "$SOFTWARE_CHECKS_EXPORT" ]; then
        log ERROR "安装模块缺少来自检查模块的必要信息！"
        log ERROR "请确保先运行检查模块。"
        exit 1
    fi

    # 重新加载检查结果和软件列表
    declare -A CHECK_RESULTS
    declare -Ag SOFTWARE_CHECKS # 使用 -g 声明为全局，以便在函数内部访问
    eval "$CHECK_RESULTS_EXPORT"
    eval "$SOFTWARE_CHECKS_EXPORT"

    # 定义安装顺序和细节
    local pm_pkgs_to_install=()
    local install_omz=false
    local install_syntax_highlighting=false
    local install_autosuggestions=false
    local install_fzf_tab=false
    local install_p10k=false
    local install_font=false

    # 1. 确定需要通过包管理器安装的包
    local pm_pkg_keys=("zsh" "fzf" "bat" "eza" "git" "curl" "wget") # 基础依赖也在此检查
    for key in "${pm_pkg_keys[@]}"; do
        local pkg_name="${SOFTWARE_CHECKS[$key]}" # 获取实际包名 (可能被 check.sh 修改为 batcat)
        if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[$key]}" == "未安装" ]]; then
             # 避免重复添加
             if [[ ! " ${pm_pkgs_to_install[*]} " =~ " ${pkg_name} " ]]; then
                 pm_pkgs_to_install+=("$pkg_name")
             fi
        fi
    done

    # 2. 确定是否安装 Oh My Zsh
    if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[oh-my-zsh]}" == "未安装" ]]; then
        install_omz=true
    fi

    # 3. 确定是否安装插件 (依赖 Oh My Zsh)
    if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[zsh-syntax-highlighting]}" == "未安装" ]]; then
        install_syntax_highlighting=true
    fi
    if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[zsh-autosuggestions]}" == "未安装" ]]; then
        install_autosuggestions=true
    fi
     if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[fzf-tab]}" == "未安装" ]]; then
        install_fzf_tab=true
    fi

    # 4. 确定是否安装 Powerlevel10k (依赖 Oh My Zsh)
    if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[powerlevel10k]}" == "未安装" ]]; then
        install_p10k=true
    fi

    # 5. 确定是否安装字体
    # 字体检查结果是 "可能已安装" 或 "未安装"
    if [ "$INSTALL_MODE" == "force" ] || [[ "${CHECK_RESULTS[meslolgs-font]}" != "已安装" && "${CHECK_RESULTS[meslolgs-font]}" != "可能已安装" ]]; then
         install_font=true
    elif [[ "${CHECK_RESULTS[meslolgs-font]}" == "可能已安装" ]]; then
        if prompt_confirm "字体 'MesloLGS' 可能已安装，是否仍然尝试安装/更新？"; then
             install_font=true
        fi
    fi


    # --- 执行安装 ---
    log INFO "安装计划:"
    log INFO "  - 包管理器 ($PACKAGE_MANAGER) 安装: ${pm_pkgs_to_install[*]:-(无)}"
    log INFO "  - 安装 Oh My Zsh: $install_omz"
    log INFO "  - 安装 zsh-syntax-highlighting: $install_syntax_highlighting"
    log INFO "  - 安装 zsh-autosuggestions: $install_autosuggestions"
    log INFO "  - 安装 fzf-tab: $install_fzf_tab"
    log INFO "  - 安装 Powerlevel10k: $install_p10k"
    log INFO "  - 安装 MesloLGS 字体: $install_font"

    # 步骤 1: 安装包管理器软件包
    if [ ${#pm_pkgs_to_install[@]} -gt 0 ]; then
        if ! install_package_manager_pkgs "$PACKAGE_MANAGER" "${pm_pkgs_to_install[@]}"; then
            log ERROR "基础软件包安装失败，后续安装可能受到影响。"
            # 可以选择退出或继续
            if ! prompt_confirm "基础软件包安装失败，是否继续尝试安装其他组件？"; then
                exit 1
            fi
        fi
    else
        log INFO "跳过包管理器安装步骤。"
    fi

    # 步骤 2: 安装 Oh My Zsh
    if $install_omz; then
        if ! install_oh_my_zsh; then
            log ERROR "Oh My Zsh 安装失败！无法继续安装插件和主题。"
            exit 1
        fi
        # Oh My Zsh 安装后，ZSH_CUSTOM 环境变量可能在当前脚本实例中未设置
        # 手动设置一个默认值以防万一
        # 使用 USER_HOME
        export ZSH_CUSTOM="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}"
        log INFO "设置 ZSH_CUSTOM 为: $ZSH_CUSTOM"

    elif ! command_exists omz &> /dev/null && ! [ -d "${USER_HOME}/.oh-my-zsh" ]; then
         # 如果不安装 OMZ，但检查发现它不存在，则无法安装插件
         log WARN "Oh My Zsh 未安装且未选择安装，将跳过所有 Oh My Zsh 插件和主题的安装。"
         install_syntax_highlighting=false
         install_autosuggestions=false
         install_fzf_tab=false
         install_p10k=false
    else
         log INFO "跳过 Oh My Zsh 安装步骤。"
         # 确保 ZSH_CUSTOM 已设置
         # 使用 USER_HOME
         export ZSH_CUSTOM="${ZSH_CUSTOM:-${USER_HOME}/.oh-my-zsh/custom}"
    fi

    # 步骤 3: 安装插件 (需要 Oh My Zsh)
    if $install_syntax_highlighting; then
        install_omz_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    else
         log INFO "跳过 zsh-syntax-highlighting 安装。"
    fi

    if $install_autosuggestions; then
        install_omz_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
    else
         log INFO "跳过 zsh-autosuggestions 安装。"
    fi

    if $install_fzf_tab; then
        install_omz_plugin "fzf-tab" "https://github.com/Aloxaf/fzf-tab.git"
    else
         log INFO "跳过 fzf-tab 安装。"
    fi


    # 步骤 4: 安装 Powerlevel10k (需要 Oh My Zsh)
    if $install_p10k; then
        install_powerlevel10k
    else
         log INFO "跳过 Powerlevel10k 安装。"
    fi

    # 步骤 5: 安装字体
    if $install_font; then
        install_fonts
    else
        log INFO "跳过字体安装步骤。"
    fi

    log STEP "安装流程执行完毕。"
}

# 如果直接运行此脚本，则执行安装 (需要先手动设置环境变量进行测试)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 用于测试 ---
    echo "直接运行 install.sh 进行测试..."
    # 手动设置环境变量进行测试
    export USER_HOME="$HOME" # 假设直接运行
    export ORIGINAL_USER="$USER"
    export INSTALL_MODE="missing" # 或者 "force"
    export PACKAGE_MANAGER=$(detect_package_manager)
    # 模拟 check.sh 的导出
    source "$SCRIPT_DIR/check.sh" # 加载 check_item 等函数
    perform_checks # 运行检查以填充 CHECK_RESULTS 和 SOFTWARE_CHECKS
    export CHECK_RESULTS_EXPORT=$(declare -p CHECK_RESULTS | sed "s/declare -A CHECK_RESULTS=/CHECK_RESULTS=(/; s/)$/)/")
    export SOFTWARE_CHECKS_EXPORT=$(declare -p SOFTWARE_CHECKS | sed 's/declare -A/declare -Ag/')

    echo "测试使用的 INSTALL_MODE: $INSTALL_MODE"
    echo "测试使用的 PACKAGE_MANAGER: $PACKAGE_MANAGER"
    echo "测试使用的 CHECK_RESULTS:"
    eval "$CHECK_RESULTS_EXPORT"
    declare -p CHECK_RESULTS
    echo "测试使用的 SOFTWARE_CHECKS:"
    eval "$SOFTWARE_CHECKS_EXPORT"
    declare -p SOFTWARE_CHECKS

    if [ "$PACKAGE_MANAGER" == "unknown" ]; then
        log ERROR "无法检测到包管理器，无法进行测试安装。"
        exit 1
    fi

    run_installation
    # --- 测试结束 ---
fi
