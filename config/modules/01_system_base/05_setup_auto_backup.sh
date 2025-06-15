#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/01_system_base/05_setup_auto_backup.sh
# 版本: 1.0.1 (修正 cron 调度选择交互问题)
# 日期: 2025-06-17
# 描述: 设置 arch_backup.sh 自动定时备份任务。
# ------------------------------------------------------------------------------
# 功能说明:
# - 将备份脚本和配置文件从项目 assets 目录复制到系统位置。
# - 引导用户配置备份脚本的关键参数。
# - 创建一个 cron 作业来实现定时备份。
# - 提供管理和检查备份任务的说明。
# ==============================================================================

# --- 脚本顶部引导块 START ---
set -euo pipefail
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
if [ -z "${BASE_DIR+set}" ]; then
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P)
    _found_base_dir=""
    while [[ "$_project_root_candidate" != "/" ]]; do
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then
            _found_base_dir="$_project_root_candidate"
            break
        fi
        _project_root_candidate=$(dirname "$_project_root_candidate")
    done
    if [[ -z "$_found_base_dir" ]]; then
        echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory for '$_current_script_entrypoint'." >&2
        exit 1
    fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 全局变量和定义
# ==============================================================================
# 源备份脚本和配置文件的路径 (相对于 ASSETS_DIR)
readonly SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE="backup_scripts"
readonly SOURCE_BACKUP_SCRIPT_NAME="arch_backup.sh"
readonly SOURCE_BACKUP_CONF_NAME="arch_backup.conf"

# 目标系统安装路径 (推荐)
readonly TARGET_SCRIPT_DIR="/usr/local/sbin" # 脚本通常放在 sbin 给 root 用
readonly TARGET_CONF_DIR="/etc"

# 完整路径
readonly SOURCE_BACKUP_SCRIPT_PATH="${ASSETS_DIR}/${SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE}/${SOURCE_BACKUP_SCRIPT_NAME}"
readonly SOURCE_BACKUP_CONF_PATH="${ASSETS_DIR}/${SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE}/${SOURCE_BACKUP_CONF_NAME}"

readonly TARGET_BACKUP_SCRIPT_PATH="${TARGET_SCRIPT_DIR}/${SOURCE_BACKUP_SCRIPT_NAME}"
readonly TARGET_BACKUP_CONF_PATH="${TARGET_CONF_DIR}/${SOURCE_BACKUP_CONF_NAME}" # 系统级配置

# Cron 服务名称 (因发行版可能不同，Arch 一般是 cronie)
CRON_SERVICE_NAME="cronie"

# 用于存储 _get_cron_schedule 函数结果的变量
_SELECTED_CRON_SCHEDULE_RESULT=""

# ==============================================================================
# 辅助函数
# ==============================================================================

# (如果 utils.sh 中没有 _prompt_return_to_continue，可以在这里定义一个简单的版本)
# _prompt_return_to_continue()
# @description 显示一个提示消息，并等待用户按 Enter 键继续。
# @param $1 (string, optional) - 要显示的提示文本。默认为 "按 Enter 键继续..."。
_prompt_return_to_continue() {
    local message="${1:-按 Enter 键继续...}" # 如果未提供参数，使用默认消息
    read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
    echo # 输出一个空行
}


# 检查 cron 服务是否安装并运行
_check_cron_service() {
    log_info "检查 cron 服务 ($CRON_SERVICE_NAME) 状态..."
    if ! is_package_installed "$CRON_SERVICE_NAME"; then
        log_warn "$CRON_SERVICE_NAME 服务未安装。"
        if _confirm_action "是否现在尝试安装 $CRON_SERVICE_NAME?" "y" "${COLOR_YELLOW}"; then
            if ! install_packages "$CRON_SERVICE_NAME"; then # 使用项目提供的 install_packages
                log_error "安装 $CRON_SERVICE_NAME 失败。无法继续设置定时任务。"
                return 1
            fi
            log_success "$CRON_SERVICE_NAME 安装成功。"
        else
            log_error "未安装 $CRON_SERVICE_NAME。无法设置定时任务。"
            return 1
        fi
    fi

    if ! systemctl is-active --quiet "$CRON_SERVICE_NAME"; then
        log_warn "$CRON_SERVICE_NAME 服务未运行。"
        if _confirm_action "是否现在尝试启动并启用 $CRON_SERVICE_NAME 服务?" "y" "${COLOR_YELLOW}"; then
            if systemctl start "$CRON_SERVICE_NAME" && systemctl enable "$CRON_SERVICE_NAME"; then
                log_success "$CRON_SERVICE_NAME 服务已启动并设置为开机自启。"
            else
                log_error "启动或启用 $CRON_SERVICE_NAME 服务失败。"
                return 1
            fi
        else
            log_error "$CRON_SERVICE_NAME 服务未运行。定时任务将无法执行。"
            return 1
        fi
    else
        log_success "$CRON_SERVICE_NAME 服务已安装并正在运行。"
    fi
    return 0
}

# 引导用户修改备份配置文件中的关键项
_configure_backup_settings_interactive() {
    local conf_file_path="$1"
    log_info "准备引导您配置备份脚本的关键设置: $conf_file_path"

    # 1. 配置 CONF_BACKUP_ROOT_DIR
    local current_backup_root_dir
    current_backup_root_dir=$(grep -Po '^CONF_BACKUP_ROOT_DIR="\K[^"]*' "$conf_file_path" || echo "/mnt/arch_backups/auto_backup_systems") # 从文件读取或默认
    
    local new_backup_root_dir
    read -rp "$(echo -e "${COLOR_YELLOW}请输入备份文件存放的根目录 (当前: ${COLOR_CYAN}${current_backup_root_dir}${COLOR_YELLOW}): ${COLOR_RESET}")" new_backup_root_dir
    new_backup_root_dir="${new_backup_root_dir:-$current_backup_root_dir}" # 为空则使用当前值

    if [[ "$new_backup_root_dir" != "$current_backup_root_dir" ]] || [ ! -d "$new_backup_root_dir" ]; then
        log_info "尝试创建/验证备份根目录: $new_backup_root_dir"
        if ! mkdir -p "$new_backup_root_dir"; then
            log_error "无法创建备份根目录 '$new_backup_root_dir'。请检查权限或手动创建。"
            log_warn "备份配置中的 CONF_BACKUP_ROOT_DIR 可能不正确。"
        else
            log_success "备份根目录 '$new_backup_root_dir' 已确认/创建。"
            sed -i "s|^CONF_BACKUP_ROOT_DIR=.*|CONF_BACKUP_ROOT_DIR=\"${new_backup_root_dir}\"|" "$conf_file_path"
            log_info "配置文件中的 CONF_BACKUP_ROOT_DIR 已更新为: $new_backup_root_dir"
        fi
    fi

    # 2. 配置 CONF_TARGET_USERNAME (用于家目录备份)
    local current_target_user
    current_target_user=$(grep -Po '^CONF_TARGET_USERNAME="\K[^"]*' "$conf_file_path" || echo "")
    
    local new_target_user
    read -rp "$(echo -e "${COLOR_YELLOW}请输入要备份其家目录的用户名 (空表示自动判断SUDO_USER, 当前: ${COLOR_CYAN}${current_target_user:-无}${COLOR_YELLOW}): ${COLOR_RESET}")" new_target_user
    if [[ -z "$new_target_user" && -n "$current_target_user" ]]; then
        new_target_user="$current_target_user" 
    elif [[ -z "$new_target_user" && -z "$current_target_user" ]]; then
        new_target_user="" 
    fi 

    if [[ "$new_target_user" != "$current_target_user" ]]; then
        if [[ -n "$new_target_user" ]] && ! id "$new_target_user" &>/dev/null; then
            log_warn "用户 '$new_target_user' 不存在。家目录备份可能失败。"
        fi
        sed -i "s|^CONF_TARGET_USERNAME=.*|CONF_TARGET_USERNAME=\"${new_target_user}\"|" "$conf_file_path"
        log_info "配置文件中的 CONF_TARGET_USERNAME 已更新为: ${new_target_user:-自动判断}"
    fi

    # 3. 配置 CONF_PROMPT_FOR_CONFIRMATION (对于定时任务，应为 false)
    log_info "对于定时任务，备份脚本通常应以非交互模式运行。"
    local current_prompt_confirm
    current_prompt_confirm=$(grep -Po '^CONF_PROMPT_FOR_CONFIRMATION="\K[^"]*' "$conf_file_path" || echo "true")
    if [[ "$current_prompt_confirm" == "true" ]]; then
        if _confirm_action "是否将 CONF_PROMPT_FOR_CONFIRMATION 设置为 'false' 以便非交互式运行?" "y" "${COLOR_YELLOW}"; then
            sed -i 's|^CONF_PROMPT_FOR_CONFIRMATION="true"|CONF_PROMPT_FOR_CONFIRMATION="false"|' "$conf_file_path"
            log_success "CONF_PROMPT_FOR_CONFIRMATION 已设置为 'false'."
        else
            log_warn "保留 CONF_PROMPT_FOR_CONFIRMATION=\"true\"。定时备份可能会因等待用户输入而失败！"
        fi
    else
        log_info "CONF_PROMPT_FOR_CONFIRMATION 已为 'false'，适合定时任务。"
    fi

    log_success "备份配置文件关键项审查/修改完毕。"
    log_notice "您可以稍后手动编辑 '$conf_file_path' 以进行更详细的配置。"
}

# 获取用户选择的 cron 调度时间
_get_cron_schedule() {
    local schedule_choice
    local cron_minute="0"
    local cron_hour="2" # 默认凌晨2点
    local cron_day_of_month="*"
    local cron_month="*"
    local cron_day_of_week="*"

    _SELECTED_CRON_SCHEDULE_RESULT="" # 清空之前的结果

    while true; do
        # 清晰地打印选项含义
        echo -e "${COLOR_PURPLE}-------------------- 定时备份频率选择 --------------------${COLOR_RESET}"
        echo -e "${COLOR_CYAN}请选择备份执行的频率:${COLOR_RESET}"
        echo -e "  ${COLOR_GREEN}1.${COLOR_RESET} 每日定时执行"
        echo -e "  ${COLOR_GREEN}2.${COLOR_RESET} 每周定时执行 (指定星期几)"
        echo -e "  ${COLOR_GREEN}3.${COLOR_RESET} 每月定时执行 (指定日期)"
        echo -e ""
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 取消设置并返回"
        echo -e "${COLOR_PURPLE}----------------------------------------------------------${COLOR_RESET}"

        read -rp "$(echo -e "${COLOR_YELLOW}您的选择 [0-3]: ${COLOR_RESET}")" schedule_choice

        case "$schedule_choice" in
            1) # 每日
                echo -e "${COLOR_CYAN}您选择了【每日】备份。现在请设置执行时间:${COLOR_RESET}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每日备份的小时 (0-23, 默认: 2 即凌晨2点): ${COLOR_RESET}")" cron_hour_input
                cron_hour="${cron_hour_input:-2}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每日备份的分钟 (0-59, 默认: 0 即整点): ${COLOR_RESET}")" cron_minute_input
                cron_minute="${cron_minute_input:-0}"
                cron_day_of_week="*"
                cron_day_of_month="*"
                cron_month="*"
                break
                ;;
            2) # 每周
                echo -e "${COLOR_CYAN}您选择了【每周】备份。现在请设置执行时间和星期:${COLOR_RESET}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每周备份的星期几 (0=周日, 1=周一,... 6=周六, 默认: 0 即周日): ${COLOR_RESET}")" cron_day_of_week_input
                cron_day_of_week="${cron_day_of_week_input:-0}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每周备份的小时 (0-23, 默认: 2): ${COLOR_RESET}")" cron_hour_input
                cron_hour="${cron_hour_input:-2}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每周备份的分钟 (0-59, 默认: 0): ${COLOR_RESET}")" cron_minute_input
                cron_minute="${cron_minute_input:-0}"
                cron_day_of_month="*"
                cron_month="*"
                break
                ;;
            3) # 每月
                echo -e "${COLOR_CYAN}您选择了【每月】备份。现在请设置执行时间和日期:${COLOR_RESET}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每月备份的日期 (1-28, 为避免月末问题建议1-28, 默认: 1 即每月1号): ${COLOR_RESET}")" cron_day_of_month_input
                cron_day_of_month="${cron_day_of_month_input:-1}"
                if ! [[ "$cron_day_of_month" =~ ^([1-9]|[12][0-9]|2[0-8])$ ]]; then
                    log_warn "输入的日期 '$cron_day_of_month' 无效或超出1-28范围，将使用默认值 1。"
                    cron_day_of_month="1"
                fi
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每月备份的小时 (0-23, 默认: 2): ${COLOR_RESET}")" cron_hour_input
                cron_hour="${cron_hour_input:-2}"
                read -rp "$(echo -e "  ${COLOR_YELLOW}请输入每月备份的分钟 (0-59, 默认: 0): ${COLOR_RESET}")" cron_minute_input
                cron_minute="${cron_minute_input:-0}"
                cron_day_of_week="*"
                cron_month="*"
                break
                ;;
            0)
                log_info "取消设置 cron 任务。"
                return 1 # 返回1表示用户取消
                ;;
            *)
                log_warn "无效选择 '$schedule_choice'，请重新输入。"
                _prompt_return_to_continue "按 Enter 键重新选择..." # 使用项目提供的函数或直接 read
                clear # 清屏以重新显示选项
                ;;
        esac
    done

    # 将结果赋值给全局变量，而不是 echo
    _SELECTED_CRON_SCHEDULE_RESULT="${cron_minute} ${cron_hour} ${cron_day_of_month} ${cron_month} ${cron_day_of_week}"
    return 0 # 返回0表示成功获取到调度
}

# ==============================================================================
# 主流程函数
# ==============================================================================
main() {
    display_header_section "设置自动定时备份" "box" 80

    # --- 步骤 1: 检查 cron 服务 ---
    if ! _check_cron_service; then
        log_error "Cron 服务未能正确配置或启动。无法继续设置定时备份。"
        return 1
    fi
    log_success "步骤 1/4: Cron 服务检查通过。"

    # --- 步骤 2: 复制备份脚本和配置文件 ---
    log_info "步骤 2/4: 复制备份脚本和配置文件到系统目录..."
    if [ ! -f "$SOURCE_BACKUP_SCRIPT_PATH" ]; then
        log_fatal "源备份脚本 '$SOURCE_BACKUP_SCRIPT_PATH' 未找到！请确保它位于项目的 assets 目录。"
    fi
    if [ ! -f "$SOURCE_BACKUP_CONF_PATH" ]; then
        log_fatal "源备份配置文件 '$SOURCE_BACKUP_CONF_PATH' 未找到！"
    fi

    _create_directory_if_not_exists "$TARGET_SCRIPT_DIR"
    _create_directory_if_not_exists "$TARGET_CONF_DIR"

    log_info "复制 '$SOURCE_BACKUP_SCRIPT_NAME' 到 '$TARGET_SCRIPT_DIR'..."
    if cp -v "$SOURCE_BACKUP_SCRIPT_PATH" "$TARGET_SCRIPT_DIR/"; then
        chmod +x "$TARGET_BACKUP_SCRIPT_PATH"
        log_success "备份脚本已复制并设置为可执行: $TARGET_BACKUP_SCRIPT_PATH"
    else
        log_error "复制备份脚本失败。请检查权限。"
        return 1
    fi

    local effective_target_conf_path="$TARGET_BACKUP_CONF_PATH"
    if [ -f "$TARGET_BACKUP_CONF_PATH" ]; then
        log_warn "目标配置文件 '$TARGET_BACKUP_CONF_PATH' 已存在。"
        if ! _confirm_action "是否覆盖现有的配置文件 (您的旧配置将丢失)?" "n" "${COLOR_RED}"; then
            log_info "保留现有配置文件。将基于现有配置文件进行后续修改。"
        else
            log_info "复制 '$SOURCE_BACKUP_CONF_NAME' 到 '$TARGET_CONF_DIR' (覆盖)..."
            if cp -vf "$SOURCE_BACKUP_CONF_PATH" "$TARGET_CONF_DIR/"; then
                log_success "备份配置文件已复制: $TARGET_BACKUP_CONF_PATH"
            else
                log_error "复制备份配置文件失败。请检查权限。"
                return 1
            fi
        fi
    else
        log_info "复制 '$SOURCE_BACKUP_CONF_NAME' 到 '$TARGET_CONF_DIR'..."
        if cp -v "$SOURCE_BACKUP_CONF_PATH" "$TARGET_CONF_DIR/"; then
            log_success "备份配置文件已复制: $TARGET_BACKUP_CONF_PATH"
        else
            log_error "复制备份配置文件失败。请检查权限。"
            return 1
        fi
    fi
    log_success "步骤 2/4: 备份脚本和配置文件部署完成。"

    # --- 步骤 3: 引导用户配置备份设置 ---
    log_info "步骤 3/4: 配置备份脚本关键设置..."
    if ! _configure_backup_settings_interactive "$effective_target_conf_path"; then
        log_warn "备份配置引导未完全完成或被跳过。"
    fi
    log_success "步骤 3/4: 备份脚本配置引导完成。"

    # --- 步骤 4: 创建 Cron 任务 ---
    log_info "步骤 4/4: 创建 Cron 定时任务..."
    if ! _confirm_action "是否要设置一个 cron 定时任务来自动运行备份脚本?" "y" "${COLOR_GREEN}"; then
        log_info "跳过创建 cron 任务。您可以稍后手动设置。"
        log_notice "要手动运行备份，请使用命令: sudo $TARGET_BACKUP_SCRIPT_PATH"
        log_notice "要手动编辑任务，请使用命令: 'sudo EDITOR="nano" crontab -e' "
        return 0
    fi

    # 调用 _get_cron_schedule。它会显示菜单并与用户交互。
    # 如果用户取消，它会 return 1。如果成功，它会 return 0 并将结果设置到 _SELECTED_CRON_SCHEDULE_RESULT。
    _SELECTED_CRON_SCHEDULE_RESULT="" # 确保在调用前清空
    if ! _get_cron_schedule; then
        # _get_cron_schedule 内部已打印 "取消设置 cron 任务。"
        # log_info "Cron 调度时间设置已由用户取消。" # 可选的额外日志
        return 0 # 用户取消被视为此模块的一个正常完成路径
    fi

    # 检查 _SELECTED_CRON_SCHEDULE_RESULT 是否有值
    if [[ -z "$_SELECTED_CRON_SCHEDULE_RESULT" ]]; then
        log_error "未能获取有效的 cron 调度时间，尽管函数指示成功。内部错误。"
        return 1
    fi

    local cron_schedule_string="$_SELECTED_CRON_SCHEDULE_RESULT" # 使用全局变量的结果

    local cron_log_dir="/var/log/arch_backups_logs/arch_system_backup_cron_logs"
    _create_directory_if_not_exists "$cron_log_dir"
    local cron_output_log="${cron_log_dir}/cron_execution.log"
    touch "$cron_output_log" && chmod 644 "$cron_output_log"

    local lock_file="/var/run/$(basename "$TARGET_BACKUP_SCRIPT_PATH").lock"
    # 确保cron命令中的路径是绝对的
    local cron_command_script_path="$TARGET_BACKUP_SCRIPT_PATH" 
    local cron_command="flock -n ${lock_file} ${cron_command_script_path} >> ${cron_output_log} 2>&1"
    local cron_job_entry="${cron_schedule_string} ${cron_command}"

    log_info "生成的 cron 作业条目为:"
    log_summary "$cron_job_entry" "" "${COLOR_CYAN}"

    log_notice "推荐将此 cron 任务添加到 root 用户的 crontab 中，以确保备份脚本有足够权限。"
    if _confirm_action "是否尝试将此作业自动添加到 root 用户的 crontab?" "y" "${COLOR_YELLOW}"; then
        local temp_crontab_file
        temp_crontab_file=$(mktemp)
        
        # 以 root 身份执行 crontab -l
        # 如果当前用户已经是 root，则不需要 sudo。否则，理论上此脚本应由 root 运行。
        crontab -l > "$temp_crontab_file" 2>/dev/null || true 
        
        if grep -Fq "$cron_command" "$temp_crontab_file"; then # 使用 -F 进行固定字符串匹配
            log_warn "类似的 cron 作业似乎已存在于 root 的 crontab 中。跳过添加以避免重复。"
            log_info "内容如下："
            grep -F "$cron_command" "$temp_crontab_file" | while IFS= read -r line; do log_info "  $line"; done
        else
            echo "$cron_job_entry" >> "$temp_crontab_file"
            if crontab "$temp_crontab_file"; then
                log_success "Cron 作业已成功添加到 root 用户的 crontab。"
            else
                log_error "添加到 root crontab 失败。请手动添加。"
                log_notice "手动添加方法: 以 root 用户执行 'sudo EDITOR="nano" crontab -e'，然后粘贴以下行:"
                log_summary "$cron_job_entry" "" "${COLOR_CYAN}"
            fi
        fi
        rm -f "$temp_crontab_file"
    else
        log_info "请手动将作业添加到 crontab。"
        log_notice "对于 root 用户，执行 'sudo EDITOR="nano" crontab -e' 并粘贴以下行:"
        log_summary "$cron_job_entry" "" "${COLOR_CYAN}"
    fi
    log_success "步骤 4/4: Cron 定时任务设置引导完成。"

    display_header_section "自动备份设置完成" "box" 80 "${COLOR_GREEN}"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_summary "自动备份已配置！" "" "${COLOR_BRIGHT_GREEN}"
    log_summary "备份脚本位置: ${TARGET_BACKUP_SCRIPT_PATH}"
    log_summary "配置文件位置: ${effective_target_conf_path}"
    log_summary "Cron 作业计划: ${cron_schedule_string}" # 使用包含实际值的变量
    log_summary "备份脚本日志: (请查看 ${effective_target_conf_path} 中的 CONF_LOG_FILE 设置)"
    log_summary "Cron 执行日志: ${cron_output_log} (如果配置了重定向)"
    log_summary "--------------------------------------------------------------------------------" "" "${COLOR_GREEN}"
    log_notice "您可以使用 'sudo crontab -l' 查看 root 用户的 cron 任务列表。"
    log_notice "如果您的 cron 服务配置为发送邮件，您可能会在备份执行后收到邮件通知。"

    return 0
}

# --- 脚本入口 ---
main "$@"
exit_script_code=$?
if [ "$exit_script_code" -ne 0 ]; then
    # _current_script_entrypoint 可能未定义如果直接执行此文件且未通过引导块
    # 使用一个安全的回退
    # 这里被我去除掉了一个local
    script_basename
    script_basename=$(basename "${BASH_SOURCE[0]}")
    log_error "${script_basename} 执行失败，退出码: $exit_script_code"
fi
exit "$exit_script_code"