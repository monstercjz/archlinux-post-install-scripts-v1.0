#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/XX_system_tweaks/01_configure_xfce_autologin.sh (示例路径)
# 版本: 1.1.0 (集成到项目框架，处理 autologin 组)
# 日期: 2025-06-15
# 描述: 为 Arch Linux 上的 XFCE (使用 LightDM) 配置自动登录。
#       此脚本会检查并创建 'autologin' 组，并将用户添加到该组，
#       然后修改 LightDM 配置以启用自动登录。
# 警告: 自动登录会显著降低系统安全性，请仅在受信任的环境中使用。
# ------------------------------------------------------------------------------
# 依赖:
#   - environment_setup.sh: (间接) 项目环境初始化。
#   - utils.sh: (直接) 日志、确认、头部显示等。
#   - 系统命令: systemctl, getent, groupadd, usermod, awk, sed, cp, mv.
# ==============================================================================

# --- 脚本顶部引导块 START ---
# (与你项目中其他脚本一致的引导块，确保 BASE_DIR 和 environment_setup.sh 加载)
set -euo pipefail
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
if [ -z "${BASE_DIR+set}" ]; then
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""
    while [[ "$_project_root_candidate" != "/" ]]; do
        # 假设项目根目录有 run_setup.sh 和 config/ 目录作为标识
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate")
    done
    if [[ -z "$_found_base_dir" ]]; then
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        echo -e "\033[0;31mPlease ensure this script is run from within the project structure or BASE_DIR is set.\033[0m" >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# LightDM 配置文件路径
LIGHTDM_CONFIG_FILE="/etc/lightdm/lightdm.conf"
AUTOLOGIN_GROUP_NAME="autologin" # PAM 配置中可能要求的组名

# @description 检测系统是否正在使用 LightDM 作为显示管理器。
# @returns 0 如果是 LightDM, 1 如果不是或无法确定。
_check_lightdm_active() {
    log_info "正在检查 LightDM 是否为活动的显示管理器..."

    # 检查 display-manager 服务是否活动
    if ! systemctl -q is-active display-manager.service; then
        log_warn "未检测到活动的显示管理器服务 (display-manager.service)。"
        if pacman -Qs lightdm &>/dev/null && [ -f "$LIGHTDM_CONFIG_FILE" ]; then
            log_info "LightDM 软件包已安装，配置文件存在。"
            if _confirm_action "显示管理器服务当前不活动。是否仍要为 LightDM 配置自动登录 (假设它稍后会被启用)?" "n" "${COLOR_YELLOW}"; then
                log_info "用户选择继续配置非活动的 LightDM。"
                return 0
            else
                log_error "操作取消。LightDM 不是活动的或用户选择不配置。"
                return 1
            fi
        else
            log_error "LightDM 未安装，或其配置文件 '$LIGHTDM_CONFIG_FILE' 不存在。"
            log_info "请先安装并启用 LightDM: 'sudo pacman -S lightdm lightdm-gtk-greeter' 和 'sudo systemctl enable lightdm.service --force'"
            return 1
        fi
    fi

    # 如果 display-manager 服务活动，获取其指向的实际服务文件路径
    local dm_service_target_path
    # systemctl show -p LoadState display-manager.service (可以看到 linked to ...)
    # systemctl show -p FragmentPath display-manager.service (获取 .service 文件路径)
    # systemctl status display-manager.service (也可以解析输出)
    # 或者更直接地，获取 WantsBy 或 WantedBy display-manager.target，然后看哪个 .service 链接到它

    # 使用 systemctl cat display-manager.service 然后解析 ExecStart 是一种方式，但更通用的是检查服务名
    # 一个更可靠的方法是检查 display-manager.service 的软链接目标（如果它是软链接）
    # 或者直接检查服务单元文件的名称（如果它是直接启用的）

    # 尝试获取 display-manager.service 最终指向的单元文件名
    # systemctl get-default 会返回 graphical.target 或 multi-user.target
    # display-manager.service 通常是 graphical.target 的一个依赖

    # systemd 服务文件通常位于 /usr/lib/systemd/system/ 或 /etc/systemd/system/
    # display-manager.service 是一个通用别名，它会链接到具体的显示管理器服务文件
    # 例如 /etc/systemd/system/display-manager.service -> /usr/lib/systemd/system/lightdm.service

    local active_dm_service_file
    active_dm_service_file=$(systemctl show -p FragmentPath display-manager.service | cut -d'=' -f2)

    if [[ -z "$active_dm_service_file" ]]; then
        log_error "无法确定活动的显示管理器服务文件路径。"
        return 1
    fi

    # --- 修改判断逻辑 ---
    # 检查获取到的服务文件路径中是否包含 "lightdm.service" 作为文件名
    if [[ "$(basename "$active_dm_service_file")" == "lightdm.service" ]]; then
        log_success "LightDM 被检测为活动的显示管理器 (服务文件: $active_dm_service_file)。"
        return 0
    else
        log_error "活动的显示管理器不是 LightDM (当前服务文件: $active_dm_service_file)。"
        log_info "此脚本仅支持为 LightDM 配置自动登录。"
        # 可以尝试进一步检测，如果用户装了 lightdm 但没启用
        if pacman -Qs lightdm &>/dev/null && [ -f "$LIGHTDM_CONFIG_FILE" ]; then
             log_warn "LightDM 软件包已安装，但当前活动的显示管理器是 '$(basename "$active_dm_service_file")'。"
             if _confirm_action "是否仍要为 LightDM 配置文件进行修改 (您需要之后手动启用 LightDM 服务)?" "n" "${COLOR_YELLOW}"; then
                log_info "用户选择继续为非活动的 LightDM 修改配置文件。"
                return 0
             else
                log_info "操作取消。"
                return 1
             fi
        fi
        return 1
    fi
}

# @description 确保 'autologin' 组存在，并将指定用户添加到该组。
# @param $1 (string) username - 要添加到组的用户名。
# @returns 0 如果成功, 1 如果失败。
_ensure_user_in_autologin_group() {
    local username="$1"

    log_info "确保用户 '$username' 属于 '$AUTOLOGIN_GROUP_NAME' 组..."

    # 1. 检查 'autologin' 组是否存在，不存在则创建
    if ! getent group "$AUTOLOGIN_GROUP_NAME" &>/dev/null; then
        log_notice "用户组 '$AUTOLOGIN_GROUP_NAME' 不存在，正在创建..."
        if groupadd "$AUTOLOGIN_GROUP_NAME"; then
            log_success "用户组 '$AUTOLOGIN_GROUP_NAME' 创建成功。"
        else
            log_error "创建用户组 '$AUTOLOGIN_GROUP_NAME' 失败！请检查权限或系统日志。"
            return 1
        fi
    else
        log_info "用户组 '$AUTOLOGIN_GROUP_NAME' 已存在。"
    fi

    # 2. 检查用户是否已在 'autologin' 组中
    if groups "$username" | grep -qw "$AUTOLOGIN_GROUP_NAME"; then
        log_success "用户 '$username' 已经是 '$AUTOLOGIN_GROUP_NAME' 组的成员。"
        return 0
    fi

    # 3. 将用户添加到 'autologin' 组
    log_notice "正在将用户 '$username' 添加到 '$AUTOLOGIN_GROUP_NAME' 组..."
    if usermod -a -G "$AUTOLOGIN_GROUP_NAME" "$username"; then
        log_success "用户 '$username' 已成功添加到 '$AUTOLOGIN_GROUP_NAME' 组。"
        log_warn "对用户组的更改通常在用户下次完全登录后生效。"
        return 0
    else
        log_error "将用户 '$username' 添加到 '$AUTOLOGIN_GROUP_NAME' 组失败！"
        return 1
    fi
}

# @description 修改 LightDM 配置文件以启用自动登录。
_configure_lightdm_autologin() {
    local username="$1"
    # ... (xfce_session_name 的确定逻辑不变) ...
    local xfce_session_name="xfce"
    if [ -f "/usr/share/xsessions/xfce.desktop" ]; then xfce_session_name="xfce";
    elif [ -f "/usr/share/xsessions/xfce4-session.desktop" ]; then xfce_session_name="xfce4-session";
    elif [ -f "/usr/share/xsessions/Xfce.desktop" ]; then xfce_session_name="Xfce";
    else log_warn "无法确定 XFCE 会话文件名，将使用默认 'xfce'。"; fi
    log_info "将使用会话名: '$xfce_session_name'"

    log_info "正在为用户 '$username' 配置 LightDM 自动登录 (会话: $xfce_session_name)..."
    if ! create_backup_and_cleanup "$LIGHTDM_CONFIG_FILE" "lightdm_conf_autologin_backup"; then
        log_error "备份 LightDM 配置文件失败。中止操作。"; return 1;
    fi
    # ... (创建基础 lightdm.conf 和 [Seat:*] 的逻辑不变) ...
    if [ ! -f "$LIGHTDM_CONFIG_FILE" ]; then
        log_info "配置文件 '$LIGHTDM_CONFIG_FILE' 不存在，将创建。"
        mkdir -p "$(dirname "$LIGHTDM_CONFIG_FILE")"
        echo -e "# LightDM conf created by script\n[Seat:*]" > "$LIGHTDM_CONFIG_FILE"
    elif ! grep -q "^\s*\[Seat:\*\]" "$LIGHTDM_CONFIG_FILE"; then
        log_info "配置文件中未找到 '[Seat:*]'，将添加。"
        echo -e "\n[Seat:*]" >> "$LIGHTDM_CONFIG_FILE"
    fi

    local temp_lightdm_conf; temp_lightdm_conf=$(mktemp)

    # --- awk 脚本核心修改 ---
    awk -v user="$username" -v session="$xfce_session_name" '
    BEGIN {
        in_seat_section = 0; # 标记是否在 [Seat:*] 或 [SeatDefaults] 内部
        # 标记我们的配置是否已经被打印过，防止在多个Seat节中重复添加
        autologin_config_printed_for_target_seat = 0;
    }

    # 匹配 [Seat:*] 或 [SeatDefaults] 行
    /^\s*\[Seat:\*\]|^\s*\[SeatDefaults\]/ {
        print; # 打印节头，例如 [Seat:*]
        in_seat_section = 1;
        # 在节头之后立即打印我们的配置，并且只打印一次
        if (!autologin_config_printed_for_target_seat) {
            print "autologin-user=" user
            print "autologin-session=" session
            print "autologin-user-timeout=0"
            autologin_config_printed_for_target_seat = 1; # 标记已打印
        }
        next; # 处理下一行
    }

    # 如果在目标节内部，并且当前行是我们要控制的自动登录相关配置，则跳过它（不打印）
    # 这样就有效地移除了所有旧的这些行
    in_seat_section && /^\s*#?\s*autologin-user\s*=/ { next; }
    in_seat_section && /^\s*#?\s*autologin-session\s*=/ { next; }
    in_seat_section && /^\s*#?\s*autologin-user-timeout\s*=/ { next; }
    # 也跳过 autologin-guest，我们不主动设置它
    in_seat_section && /^\s*#?\s*autologin-guest\s*=/ { next; }


    # 如果遇到新的节开始（不是 [Seat:*] 或 [SeatDefaults]），则重置 in_seat_section 标志
    /^\s*\[.*\]/ && !(/^\s*\[Seat:\*\]|^\s*\[SeatDefaults\]/) {
        in_seat_section = 0;
    }

    { print } # 打印所有其他行

    END {
        # 如果遍历完整个文件，我们的配置都还没有被打印（例如，文件是空的，或者没有 [Seat:*] 节）
        # （虽然之前的逻辑应该已经创建了 [Seat:*]，但这里作为最终保险）
        if (!autologin_config_printed_for_target_seat) {
            print "\n[Seat:*]" # 确保有一个 Seat 段
            print "autologin-user=" user
            print "autologin-session=" session
            print "autologin-user-timeout=0"
        }
    }
    ' "$LIGHTDM_CONFIG_FILE" > "$temp_lightdm_conf"
    # --- awk 脚本核心修改结束 ---


    if [ ! -s "$temp_lightdm_conf" ] && [ -s "$LIGHTDM_CONFIG_FILE" ]; then
        log_error "Awk 处理失败，临时文件为空。保留原文件。"; rm -f "$temp_lightdm_conf"; return 1;
    fi
    if mv "$temp_lightdm_conf" "$LIGHTDM_CONFIG_FILE"; then log_debug "LightDM 配置已更新。";
    else log_error "移回临时文件失败！"; rm -f "$temp_lightdm_conf"; return 1; fi

    # 验证逻辑保持不变
    if grep -q "^\s*autologin-user=$username" "$LIGHTDM_CONFIG_FILE" && \
       grep -q "^\s*autologin-session=$xfce_session_name" "$LIGHTDM_CONFIG_FILE" && \
       grep -q "^\s*autologin-user-timeout=0" "$LIGHTDM_CONFIG_FILE"; then
        log_success "LightDM 配置文件成功修改。"; return 0;
    else
        log_error "修改后验证失败。请手动检查 '$LIGHTDM_CONFIG_FILE'。"; return 1;
    fi
}
# @description 显示手动配置 XFCE (LightDM) 自动登录的说明。
_display_manual_configuration_info() {
    clear
    display_header_section "手动配置 XFCE (LightDM) 自动登录说明" "box" 80

    log_summary "${COLOR_BOLD}警告: 自动登录会降低系统安全性。请谨慎操作。${COLOR_RESET}" "" "${COLOR_RED}"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "${COLOR_YELLOW}步骤 1: 确保 LightDM 是您的显示管理器${COLOR_RESET}"
    log_summary "  - 检查命令: ${COLOR_CYAN}sudo systemctl status display-manager${COLOR_RESET}"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "${COLOR_YELLOW}步骤 2: 处理 '$AUTOLOGIN_GROUP_NAME' 用户组 (PAM 要求)${COLOR_RESET}"
    log_summary "  1. 检查组是否存在: ${COLOR_CYAN}getent group $AUTOLOGIN_GROUP_NAME${COLOR_RESET}"
    log_summary "  2. 如果不存在，创建组: ${COLOR_CYAN}sudo groupadd $AUTOLOGIN_GROUP_NAME${COLOR_RESET}"
    log_summary "  3. 将用户添加到组: ${COLOR_CYAN}sudo usermod -a -G $AUTOLOGIN_GROUP_NAME YOUR_USERNAME${COLOR_RESET}"
    log_summary "  4. 验证添加: ${COLOR_CYAN}groups YOUR_USERNAME${COLOR_RESET}"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "${COLOR_YELLOW}步骤 3: 修改 LightDM 配置文件 (${LIGHTDM_CONFIG_FILE})${COLOR_RESET}"
    log_summary "  1. 编辑: ${COLOR_CYAN}sudo nano $LIGHTDM_CONFIG_FILE${COLOR_RESET}"
    log_summary "  2. 在 ${COLOR_GREEN}[Seat:*]${COLOR_RESET} (或 ${COLOR_GREEN}[SeatDefaults]${COLOR_RESET}) 部分，确保有:"
    log_summary "     ${COLOR_PURPLE}autologin-user=YOUR_USERNAME${COLOR_RESET}"
    log_summary "     ${COLOR_PURPLE}autologin-user-timeout=0${COLOR_RESET}"
    log_summary "     ${COLOR_PURPLE}autologin-session=xfce${COLOR_RESET} (或 xfce4-session, Xfce)"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "${COLOR_YELLOW}步骤 4: 生效更改${COLOR_RESET}"
    log_summary "  - ${COLOR_BOLD}完全注销重登录，或重启计算机。${COLOR_RESET}"
    log_summary "  - 或重启 LightDM: ${COLOR_CYAN}sudo systemctl restart lightdm.service${COLOR_RESET}"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "${COLOR_YELLOW}密钥环 (Keyring) 注意事项:${COLOR_RESET}"
    log_summary "  - 自动登录后可能仍需输入密钥环密码。可在 '密码和密钥' (Seahorse) 中处理。"
    log_summary "--------------------------------------------------------------------------------"
    log_summary "问题排查: 检查系统日志 (journalctl -xe) 和 LightDM 日志 (/var/log/lightdm/*)。"

    if type -t _prompt_return_to_continue &>/dev/null; then
        _prompt_return_to_continue "按 Enter 返回..." # 使用项目中可能的函数
    else
        read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回...${COLOR_RESET}")"
    fi
}
# @description (原 main 函数，现重命名) 执行自动登录的完整配置流程。
_run_automatic_configuration() {
    display_header_section "XFCE 自动登录配置工具 (LightDM)" "box" 80

    # 步骤 1: 检查 Root 权限 (utils.sh 中已有 check_root_privileges, 此处演示独立检查)
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "此脚本需要 root 权限才能修改系统配置文件。请使用 sudo 运行。"
        exit 1
    fi
    log_info "Root 权限检查通过。"

    # 步骤 2: 检查 LightDM 是否为活动显示管理器
    if ! _check_lightdm_active; then
        exit 1 # _check_lightdm_active 内部会打印错误信息
    fi

    # 步骤 3: 获取并选择要自动登录的用户
    # awk 命令解释:
    # -F: 设置字段分隔符为冒号
    # $3 >= 1000 && $3 < 60000: 选择 UID 在此范围内的用户 (通常是普通用户)
    # $7 !~ /nologin|false/: 确保用户有一个有效的登录 shell (不是 /sbin/nologin 或 /bin/false)
    # {print $1}: 打印用户名
    mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /nologin|false|true/ {print $1}' /etc/passwd | sort)
    
    if [ ${#users[@]} -eq 0 ]; then
        log_error "系统中未找到可用于自动登录的普通用户 (UID 1000-59999 且有有效shell)。"
        exit 1
    fi

    log_info "以下是系统中可用的普通用户列表:"
    for i in "${!users[@]}"; do
        echo -e "  ${COLOR_GREEN}$((i+1)).${COLOR_RESET} ${users[$i]}"
    done
    echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消"

    local choice
    while true; do
        read -rp "$(echo -e "${COLOR_YELLOW}请选择要为其设置自动登录的用户名序号 [1-${#users[@]}, 0 取消]: ${COLOR_RESET}")" choice
        if [[ "$choice" == "0" ]]; then
            log_info "操作已由用户取消。"
            exit 0
        fi
        # 验证输入是否为有效数字且在选项范围内
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#users[@]} )); then
            break # 有效选择，跳出循环
        else
            log_warn "无效选择: '$choice'。请重新输入。"
        fi
    done

    local selected_user="${users[$((choice-1))]}" # 数组索引从0开始
    log_info "您选择了用户: ${COLOR_CYAN}$selected_user${COLOR_RESET}"

    # 步骤 4: 再次确认操作 (因为有安全风险)
    if ! _confirm_action "警告！您确定要为用户 '${COLOR_CYAN}$selected_user${COLOR_RESET}' 设置自动登录吗? 这会显著降低系统安全性。" "n" "${COLOR_RED}"; then
        log_info "操作已由用户取消。"
        exit 0
    fi

    # 步骤 5: 确保用户在 'autologin' 组中
    if ! _ensure_user_in_autologin_group "$selected_user"; then
        log_error "未能将用户 '$selected_user' 配置到 '$AUTOLOGIN_GROUP_NAME' 组。自动登录可能因此失败。"
        # 根据 PAM 配置，这可能是硬性要求，所以中止
        exit 1
    fi

    # 步骤 6: 配置 LightDM 文件
    if _configure_lightdm_autologin "$selected_user"; then
        log_notice "${COLOR_GREEN}自动登录配置成功完成。${COLOR_RESET}"
        log_warn "请 ${COLOR_YELLOW}重启计算机${COLOR_RESET} 或 ${COLOR_YELLOW}重启显示管理器服务${COLOR_RESET} (例如: sudo systemctl restart lightdm) 以使更改生效。"
        log_info "---"
        log_info "${COLOR_BOLD}如何撤销自动登录:${COLOR_RESET}"
        log_info "1. 以 root 权限编辑文件: ${COLOR_CYAN}$LIGHTDM_CONFIG_FILE${COLOR_RESET}"
        log_info "2. 在 ${COLOR_GREEN}[Seat:*]${COLOR_RESET} (或 ${COLOR_GREEN}[SeatDefaults]${COLOR_RESET}) 部分，注释掉 (行首加 '#') 或删除以下行:"
        log_info "   ${COLOR_PURPLE}autologin-user=$selected_user${COLOR_RESET}"
        log_info "   ${COLOR_PURPLE}autologin-user-timeout=0${COLOR_RESET}"
        log_info "   ${COLOR_PURPLE}autologin-session=...${COLOR_RESET} (您配置的会话名)"
        log_info "3. 或者，如果您有备份，可以恢复 ${COLOR_CYAN}${LIGHTDM_CONFIG_FILE}.bak.*${COLOR_RESET} 文件。"
        log_info "4. 更改后同样需要重启显示管理器或计算机。"
    else
        log_error "自动登录配置过程中发生错误。请检查以上日志。系统未作更改或更改不完整。"
        exit 1
    fi
}
# @description 新的主函数，提供顶层菜单选择。
main() {
    while true; do
        clear
        display_header_section "XFCE 自动登录配置 (LightDM)" "box" 80

        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} ${COLOR_BOLD}自动配置${COLOR_RESET} XFCE (LightDM) 免密登录"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 查看 ${COLOR_BOLD}手动配置${COLOR_RESET} LightDM 自动登录的说明"
        echo -e ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 返回上一级菜单"
        echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"

        local main_choice
        read -rp "$(echo -e "${COLOR_YELLOW}请输入您的选择 [0-2]: ${COLOR_RESET}")" main_choice
        echo # 换行

        local op_status=0
        case "$main_choice" in
            1)
                # 调用之前的自动配置流程
                _run_automatic_configuration; op_status=$?
                ;;
            2)
                # 显示手动配置说明
                _display_manual_configuration_info; op_status=0 # 显示说明通常视为成功
                ;;
            0)
                log_info "退出 XFCE 自动登录配置。"
                break # 退出主循环
                ;;
            *)
                log_warn "无效选择: '$main_choice'。请重新输入。"
                op_status=99 # 特殊标记，非错误但需提示
                ;;
        esac

        # 如果不是退出选项，则提示用户按键继续
        if [[ "$main_choice" != "0" ]]; then
            if (( op_status != 0 && op_status != 99 )); then # 如果是实际操作失败
                log_error "之前的操作未成功完成 (状态: $op_status)。"
            fi
            # 使用项目中已有的 _prompt_return_to_continue 或类似函数
            if type -t _prompt_return_to_continue &>/dev/null; then
                _prompt_return_to_continue "按 Enter 返回自动登录主菜单..."
            else
                read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回自动登录主菜单...${COLOR_RESET}")"
            fi
        fi
    done
}
# --- 脚本入口 ---
# 只有当脚本被直接执行时才运行 main 函数。
# 如果此脚本是被其他脚本 source 的 (理论上不太可能)，则不自动执行 main。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

exit 0 # 脚本正常结束