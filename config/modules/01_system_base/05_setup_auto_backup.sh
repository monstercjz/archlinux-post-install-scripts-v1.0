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
readonly TARGET_CONF_DIR="/etc/arch_backup"

# 完整源路径
readonly SOURCE_BACKUP_SCRIPT_PATH="${ASSETS_DIR}/${SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE}/${SOURCE_BACKUP_SCRIPT_NAME}"
readonly SOURCE_BACKUP_CONF_PATH="${ASSETS_DIR}/${SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE}/${SOURCE_BACKUP_CONF_NAME}"

# 完整目标路径
readonly TARGET_BACKUP_SCRIPT_PATH="${TARGET_SCRIPT_DIR}/${SOURCE_BACKUP_SCRIPT_NAME}"
readonly TARGET_BACKUP_CONF_PATH="${TARGET_CONF_DIR}/${SOURCE_BACKUP_CONF_NAME}" # 系统级配置

# Cron 服务名称 (因发行版可能不同，Arch 一般是 cronie)
CRON_SERVICE_NAME="cronie"

# 用于存储 _get_cron_schedule 函数结果的变量
_SELECTED_CRON_SCHEDULE_RESULT=""

# 定义预设的钩子脚本及其目标事件目录
# 格式： "源文件在default_hooks下的相对路径=目标事件子目录名[|描述][|默认启用y/n]"
declare -A PRESET_HOOK_SCRIPTS=(
    ["finalization/99_cleanup_cron_exec_log.sh"]="finalization|清理Cron执行日志|y"
    # ["pre-backup/10_example_pre_hook.sh"]="pre-backup|示例：备份前执行的操作|n" # 默认不启用
    # ["post-backup-success/80_example_post_hook.sh"]="post-backup-success|示例：备份成功后执行的操作|n"
)
readonly PRESET_HOOKS_SOURCE_BASE_DIR="${ASSETS_DIR}/${SOURCE_BACKUP_SCRIPTS_DIR_RELATIVE}/default_hooks"

# ==============================================================================
# 辅助函数
# ==============================================================================

# (如果 utils.sh 中没有 _prompt_return_to_continue，可以在这里定义一个简单的版本)
# _prompt_return_to_continue()
# @description 显示一个提示消息，并等待用户按 Enter 键继续。
# @param $1 (string, optional) - 要显示的提示文本。默认为 "按 Enter 键继续..."。
# _prompt_return_to_continue() {
#     local message="${1:-按 Enter 键继续...}" # 如果未提供参数，使用默认消息
#     read -rp "$(echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}")"
#     echo # 输出一个空行
# }

# --- 步骤 2.6/4 (新增): 部署预设的钩子脚本 ---
# --- 步骤 2.6/4 (或者您调整后的步骤编号): 部署预设的钩子脚本 ---
# @description: 检查并部署项目中定义的预设钩子脚本到目标钩子目录。
#               如果目标位置已存在同名脚本，会提示用户是否覆盖。
#               如果用户同意覆盖，会使用框架的备份函数备份现有脚本。
# @param $1 (string) target_hooks_base_dir - 已创建的目标钩子根目录的绝对路径 
#                                           (例如 /etc/arch_backup/hooks.d)。
# @returns: 0 总是返回0，部署过程中的失败会记录为错误/警告，但不中止主设置流程，
#             除非是关键的目录创建失败。
# @depends: 全局数组 PRESET_HOOK_SCRIPTS, 全局变量 PRESET_HOOKS_SOURCE_BASE_DIR,
#           项目框架函数: log_*, _confirm_action, _create_directory_if_not_exists, create_backup_and_cleanup
_deploy_preset_hooks() {
    local target_hooks_base_dir="$1" 

    # 验证传入的钩子基础目录是否存在
    if [ ! -d "$target_hooks_base_dir" ]; then
        log_warn "[Preset Hooks] 目标钩子根目录 '$target_hooks_base_dir' 不存在。无法部署预设钩子。"
        return 1 # 可以考虑返回错误码，让调用者决定是否中止
    fi

    # 检查是否有预设钩子被定义
    if [ ${#PRESET_HOOK_SCRIPTS[@]} -eq 0 ]; then
        log_info "[Preset Hooks] 没有在脚本中定义预设的钩子脚本。无需部署。"
        return 0
    fi

    log_info "步骤 4/6: 检查并部署预设的钩子脚本到 '$target_hooks_base_dir'..." # 调整步骤编号

    # 遍历 PRESET_HOOK_SCRIPTS 关联数组中定义的所有预设钩子
    for preset_hook_source_relative_path in "${!PRESET_HOOK_SCRIPTS[@]}"; do
        local hook_details="${PRESET_HOOK_SCRIPTS[$preset_hook_source_relative_path]}"
        local target_event_subdir hook_description default_enable_char
        
        # 解析钩子详情: "源文件相对路径=目标事件子目录|描述|默认启用y/n"
        IFS='|' read -r target_event_subdir hook_description default_enable_char <<< "$hook_details"
        default_enable_char="${default_enable_char:-y}" # 如果未提供，默认为启用 (y)

        # 构建源脚本和目标脚本的完整路径
        local source_script_full_path="${PRESET_HOOKS_SOURCE_BASE_DIR%/}/${preset_hook_source_relative_path}"
        local target_script_dir="${target_hooks_base_dir%/}/${target_event_subdir}" # 确保目标事件子目录路径正确
        local target_script_filename
        target_script_filename=$(basename "$source_script_full_path")
        local target_script_full_path="${target_script_dir}/${target_script_filename}"

        log_debug "[Preset Hooks] 正在处理预设钩子..."
        log_debug "[Preset Hooks]   源脚本: '$source_script_full_path'"
        log_debug "[Preset Hooks]   目标位置: '$target_script_full_path'"
        log_debug "[Preset Hooks]   描述: '${hook_description:- (无描述)}'"
        log_debug "[Preset Hooks]   默认部署提示: '$default_enable_char'"

        # 检查源预设钩子脚本是否存在
        if [ ! -f "$source_script_full_path" ]; then
            log_warn "[Preset Hooks] 源预设钩子脚本 '$source_script_full_path' 未找到。跳过此钩子。"
            continue # 处理下一个预设钩子
        fi

        # 确保目标事件子目录存在 (通常应由之前的步骤创建，这里作为保险)
        if ! _create_directory_if_not_exists "$target_script_dir"; then
            log_warn "[Preset Hooks] 目标事件钩子目录 '$target_script_dir' 无法创建。跳过部署 '$target_script_filename'。"
            continue # 处理下一个预设钩子
        fi

        # 根据 default_enable_char 决定是否需要询问用户，或直接进行下一步判断
        local should_proceed_to_deploy=false
        if [[ "$default_enable_char" == "y" ]]; then
            should_proceed_to_deploy=true # 对于默认启用的，先假设要部署（后续会检查是否已存在）
        else
            # 对于默认不启用的，明确询问用户是否部署
            if _confirm_action "是否部署可选的预设钩子脚本 '${hook_description:-$target_script_filename}' 到 '$target_script_dir'?" "n" "${COLOR_GREEN}"; then
                should_proceed_to_deploy=true
            fi
        fi

        if ! $should_proceed_to_deploy; then
            log_info "[Preset Hooks] 跳过部署预设钩子脚本 '$target_script_filename' (基于默认设置或用户选择)。"
            echo # 添加空行以分隔不同钩子的处理日志
            continue # 处理下一个预设钩子
        fi

        # --- 核心逻辑：检查目标文件是否存在，并处理备份和覆盖 ---
        local copy_new_file_flag=true # 标志最终是否执行复制操作
        if [ -f "$target_script_full_path" ]; then
            log_warn "[Preset Hooks] 目标钩子脚本 '$target_script_full_path' 已存在。"
            if _confirm_action "是否用项目提供的版本覆盖现有的 '$target_script_filename'? (提示: 现有文件将被使用框架的备份函数进行备份)" "n" "${COLOR_RED}"; then
                # 用户同意覆盖，使用 create_backup_and_cleanup 备份现有文件
                # 定义用于存放此钩子脚本备份的子目录名 (相对于 GLOBAL_BACKUP_ROOT)
                local hook_script_backup_subdir="deployed_hooks_backup/${target_event_subdir}"
                # 定义为此类钩子脚本保留的最大备份数量
                local max_hook_script_backups_to_keep=3 

                log_info "[Preset Hooks] 使用框架备份函数备份现有文件 '$target_script_full_path'..."
                log_debug "[Preset Hooks]   备份将被存入 '${GLOBAL_BACKUP_ROOT%/}/$hook_script_backup_subdir' (最多保留 $max_hook_script_backups_to_keep 个版本)"
                
                # 调用 utils.sh 中的备份函数
                if create_backup_and_cleanup "$target_script_full_path" "$hook_script_backup_subdir" "$max_hook_script_backups_to_keep"; then
                    log_success "[Preset Hooks] 现有文件 '$target_script_filename' 已成功通过框架函数备份。"
                    # 因为 create_backup_and_cleanup 通常不删除源文件，我们需要手动删除它以便后续 cp 覆盖
                    log_info "[Preset Hooks] 准备删除旧的 '$target_script_full_path' 以便复制新版本..."
                    if ! rm -f "$target_script_full_path"; then
                        log_error "[Preset Hooks] 备份了现有文件，但删除原文件 '$target_script_full_path' 失败！将不会覆盖。"
                        copy_new_file_flag=false # 不要继续复制
                    fi
                else
                    log_error "[Preset Hooks] 使用框架备份函数备份现有文件 '$target_script_full_path' 失败！将不会覆盖。"
                    copy_new_file_flag=false # 不要继续复制
                fi
            else
                log_info "[Preset Hooks] 用户选择保留现有的 '$target_script_filename'。不进行覆盖。"
                copy_new_file_flag=false # 不要继续复制
            fi
        fi # 结束 if [ -f "$target_script_full_path" ]
        # --- 结束检查和备份逻辑 ---

        if $copy_new_file_flag; then
            # 执行部署 (复制新文件)
            log_info "[Preset Hooks] 部署预设钩子脚本 '$target_script_filename' 到 '$target_script_dir'..."
            # 使用 cp -v 来显示复制的详细信息
            if cp -v "$source_script_full_path" "$target_script_dir/"; then
                # 复制成功后，设置执行权限
                if chmod +x "$target_script_full_path"; then
                    log_success "[Preset Hooks] 预设钩子脚本 '$target_script_filename' 已成功部署并设置为可执行。"
                else
                    log_warn "[Preset Hooks] 预设钩子脚本 '$target_script_filename' 已复制，但设置执行权限失败。"
                fi
            else
                log_error "[Preset Hooks] 复制预设钩子脚本 '$target_script_filename' 到 '$target_script_dir/' 失败。"
            fi
        fi
        echo # 添加空行以分隔不同钩子的处理日志，使输出更清晰
    done # 结束 for preset_hook_source_relative_path 循环

    log_success "步骤 4/6: 预设钩子脚本部署流程已完成。" # 调整步骤编号
    return 0
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
    log_success "步骤 1/6: Cron 服务检查通过。"

    # --- 步骤 2: 复制备份脚本和配置文件 ---
    log_info "步骤 2/6: 复制备份脚本和配置文件到系统目录..."
    if [ ! -f "$SOURCE_BACKUP_SCRIPT_PATH" ]; then
        log_fatal "源备份脚本 '$SOURCE_BACKUP_SCRIPT_PATH' 未找到！请确保它位于项目的 assets 目录。"
    fi
    if [ ! -f "$SOURCE_BACKUP_CONF_PATH" ]; then
        log_fatal "源备份配置文件 '$SOURCE_BACKUP_CONF_PATH' 未找到！"
    fi

    _create_directory_if_not_exists "$TARGET_SCRIPT_DIR"
    _create_directory_if_not_exists "$TARGET_CONF_DIR"

    local BACKUP_SCRIPTS_PATH="arch_backup_scripts"
    local SCRIPTS_BACKUP_DIR="${GLOBAL_BACKUP_ROOT}/${BACKUP_SCRIPTS_PATH}"
    if [ -f "$TARGET_BACKUP_SCRIPT_PATH" ]; then
        log_warn "目标脚本文件 '$TARGET_BACKUP_SCRIPT_PATH' 已存在。"
        if ! _confirm_action "是否覆盖现有的脚本文件 (您的旧脚本将丢失)?" "n" "${COLOR_RED}"; then
            log_info "保留现有脚本文件。将基于现有脚本文件进行后续执行。"
        else
            
            # create_backup_and_cleanup "$TARGET_BACKUP_CONF_PATH" "$BACKUP_DIR"
            if create_backup_and_cleanup "$TARGET_BACKUP_SCRIPT_PATH" "$BACKUP_SCRIPTS_PATH"; then
                # 备份成功，函数可以成功返回
                log_info "成功备份 '$TARGET_BACKUP_SCRIPT_PATH' 到 '$SCRIPTS_BACKUP_DIR' 目录..."
            else
                log_warn "没能备份 '$TARGET_BACKUP_SCRIPT_PATH' 到 '$SCRIPTS_BACKUP_DIR' 目录..."
            fi
            log_info "开始复制 '$SOURCE_BACKUP_SCRIPT_PATH' 到 '$TARGET_BACKUP_SCRIPT_PATH' (覆盖)..."
            if cp -v "$SOURCE_BACKUP_SCRIPT_PATH" "$TARGET_SCRIPT_DIR/"; then
                chmod +x "$TARGET_BACKUP_SCRIPT_PATH"
                log_success "备份脚本已复制并设置为可执行: $TARGET_BACKUP_SCRIPT_PATH"
            else
                log_error "复制备份脚本失败。请检查权限。"
                return 1
            fi
        fi
    else
        log_info "复制 '$SOURCE_BACKUP_SCRIPT_NAME' 到 '$TARGET_SCRIPT_DIR'..."
        if cp -v "$SOURCE_BACKUP_SCRIPT_PATH" "$TARGET_SCRIPT_DIR/"; then
            chmod +x "$TARGET_BACKUP_SCRIPT_PATH"
            log_success "备份脚本已复制并设置为可执行: $TARGET_BACKUP_SCRIPT_PATH"
        else
            log_error "复制备份脚本失败。请检查权限。"
            return 1
        fi
    fi

    # log_info "复制 '$SOURCE_BACKUP_SCRIPT_NAME' 到 '$TARGET_SCRIPT_DIR'..."
    # if cp -v "$SOURCE_BACKUP_SCRIPT_PATH" "$TARGET_SCRIPT_DIR/"; then
    #     chmod +x "$TARGET_BACKUP_SCRIPT_PATH"
    #     log_success "备份脚本已复制并设置为可执行: $TARGET_BACKUP_SCRIPT_PATH"
    # else
    #     log_error "复制备份脚本失败。请检查权限。"
    #     return 1
    # fi

    local effective_target_conf_path="$TARGET_BACKUP_CONF_PATH"
    local BACKUP_DIR="arch_backup_conf"
    local CONF_BACKUP_DIR="${GLOBAL_BACKUP_ROOT}/${BACKUP_DIR}"
    if [ -f "$TARGET_BACKUP_CONF_PATH" ]; then
        log_warn "目标配置文件 '$TARGET_BACKUP_CONF_PATH' 已存在。"
        if ! _confirm_action "是否覆盖现有的配置文件 (您的旧配置将丢失)?" "n" "${COLOR_RED}"; then
            log_info "保留现有配置文件。将基于现有配置文件进行后续修改。"
        else
            
            # create_backup_and_cleanup "$TARGET_BACKUP_CONF_PATH" "$BACKUP_DIR"
            if create_backup_and_cleanup "$TARGET_BACKUP_CONF_PATH" "$BACKUP_DIR"; then
                # 备份成功，函数可以成功返回
                log_info "成功备份 '$TARGET_BACKUP_CONF_PATH' 到 '$CONF_BACKUP_DIR' 目录..."
            else
                log_warn "没能备份 '$TARGET_BACKUP_CONF_PATH' 到 '$CONF_BACKUP_DIR' 目录..."
            fi
            log_info "开始复制 '$SOURCE_BACKUP_CONF_PATH' 到 '$TARGET_BACKUP_CONF_PATH' (覆盖)..."
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
    log_success "步骤 2/6: 备份脚本和配置文件部署完成。"

     # --- 步骤 2.5/4 (新编号): 准备钩子目录结构 ---
    log_info "步骤 3/6: 准备钩子目录结构..."
    
    # effective_target_conf_path 应该是在步骤2中确定的最终配置文件路径
    # 例如: local effective_target_conf_path="$TARGET_BACKUP_CONF_PATH"
    # 确保这个变量在步骤2中被正确设置并在此处可用

    local hooks_enabled_from_conf="false"
    # 默认的钩子基础目录，应与 arch_backup.sh 中的默认值一致
    local hooks_base_dir_from_conf="/etc/arch_backup/hooks.d" 

    if [ -f "$effective_target_conf_path" ]; then
        # 从已部署的配置文件中读取钩子相关的设置
        hooks_enabled_from_conf=$(grep -Po '^CONF_HOOKS_ENABLE="\K[^"]*' "$effective_target_conf_path" 2>/dev/null || echo "false")
        hooks_base_dir_from_conf=$(grep -Po '^CONF_HOOKS_BASE_DIR="\K[^"]*' "$effective_target_conf_path" 2>/dev/null || echo "/etc/arch_backup/hooks.d")
        log_info "从 '$effective_target_conf_path' 读取到: CONF_HOOKS_ENABLE='$hooks_enabled_from_conf', CONF_HOOKS_BASE_DIR='$hooks_base_dir_from_conf'"
    else
        log_warn "配置文件 '$effective_target_conf_path' 未找到，无法读取钩子设置。将使用默认钩子基础目录 '$hooks_base_dir_from_conf' 并假设钩子未启用。"
        # 这种情况下，可能不应该继续创建钩子目录，或者只创建基础目录但不提示启用
    fi

    # 无论配置文件中 CONF_HOOKS_ENABLE 的值如何，我们都可以创建基础目录结构，
    # 以便用户后续如果想启用钩子，目录已经准备好了。
    # 或者，可以做得更严格：只有当 hooks_enabled_from_conf 为 "true" 时才创建。
    # 为了用户友好和后续使用的便利性，先创建好目录通常更好。
    
    log_info "将确保钩子基础目录 '$hooks_base_dir_from_conf' 存在。"
    if ! _create_directory_if_not_exists "$hooks_base_dir_from_conf"; then # _create_directory_if_not_exists 来自 utils.sh
        log_error "无法创建钩子根目录 '$hooks_base_dir_from_conf'。钩子功能可能无法使用。"
        # 可以考虑这里是否需要 return 1，取决于钩子是否被视为核心功能的一部分
    else
        # 创建一些常见的事件子目录作为示例或预备
        # 这些子目录名应与 arch_backup.sh 中 _run_hooks 函数期望的事件名一致
        local common_event_subdirs=("pre-backup" "post-backup-success" "post-backup-failure" "finalization") 
        # 如果有特定任务的钩子，也在此处添加，例如 "pre-task-system_config"
        
        for subdir in "${common_event_subdirs[@]}"; do
            local event_dir_path="${hooks_base_dir_from_conf%/}/${subdir}" # 确保路径正确拼接
            if ! _create_directory_if_not_exists "$event_dir_path"; then
                log_warn "无法创建事件钩子子目录 '$event_dir_path'。"
            else
                # 可选：设置目录权限，例如 root:root 755
                # sudo chown root:root "$event_dir_path" # 如果脚本以root运行，chown给自己是多余的，但可以确保
                # sudo chmod 755 "$event_dir_path"
                log_info "事件钩子子目录已创建/确认: $event_dir_path"
            fi
        done
        log_success "钩子目录结构已在 '$hooks_base_dir_from_conf' 中准备就绪。"
        
        # 根据配置文件中的实际启用状态给出提示
        if [[ "$hooks_enabled_from_conf" == "true" ]]; then
            log_info "钩子功能已在 '${effective_target_conf_path}' 中启用。"
            log_notice "您可以将可执行脚本放入 '${hooks_base_dir_from_conf}' 下相应的事件子目录中以激活它们。"
        else
            log_notice "提示: 钩子功能当前在 '${effective_target_conf_path}' 中为禁用状态 (CONF_HOOKS_ENABLE=\"${hooks_enabled_from_conf}\")."
            log_notice "如需使用，请在配置文件中将其设置为 \"true\"，然后将脚本放入上述子目录。"
        fi
    fi
    log_success "步骤 3/6: 钩子目录结构准备完成。"


 # --- 步骤 4/6 (新增): 部署预设的钩子脚本 ---
    # 只有当钩子目录实际存在时才尝试部署
    if [[ -n "$hooks_base_dir_from_conf" && -d "$hooks_base_dir_from_conf" ]]; then
        _deploy_preset_hooks "$hooks_base_dir_from_conf"
    else
        log_warn "钩子基础目录未正确设置或创建，跳过部署预设钩子脚本。"
    fi
    
    # --- 步骤 5: 引导用户配置备份设置 ---
    log_info "步骤 5/6: 配置备份脚本关键设置..."
    if ! _configure_backup_settings_interactive "$effective_target_conf_path"; then
        log_warn "备份配置引导未完全完成或被跳过。"
    fi
    log_success "步骤 5/6: 备份脚本配置引导完成。"

    # --- 步骤 6: 创建 Cron 任务 ---
    log_info "步骤 6/6: 创建 Cron 定时任务..."
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

    # 如果这个路径修改之后，应该同步修改99_cleanup_cron_exec_logs.sh中的清理路径
    local cron_log_dir="/var/log/arch_backups_logs/arch_system_backup_cron_logs"
    _create_directory_if_not_exists "$cron_log_dir"
    # ---修改单一日志文件模式，改为带时间戳的动态多文件日志----
    # local cron_output_log="${cron_log_dir}/cron_execution.log"
    # touch "$cron_output_log" && chmod 644 "$cron_output_log"

    local lock_file="/var/run/$(basename "$TARGET_BACKUP_SCRIPT_PATH").lock"
    # 确保cron命令中的路径是绝对的
    local cron_command_script_path="$TARGET_BACKUP_SCRIPT_PATH" 
    # ---修改部分开始------
    # local cron_command="flock -n ${lock_file} ${cron_command_script_path} >> ${cron_output_log} 2>&1"
    # --- 修改 cron_command 以包含动态时间戳文件名 ---
    # 我们需要在 cron 执行时动态获取时间戳。
    # cron 环境中直接使用 date 命令是可靠的。
    # 注意：cron 中的 '%' 字符有特殊含义，需要转义成 '\%'
    #       或者将整个日期格式字符串用单引号括起来，避免 cron 解释。
    # 使用单引号和反引号（或 $()）来嵌入 date 命令
    local cron_command="flock -n ${lock_file} ${cron_command_script_path} >> \"${cron_log_dir}/cron_exec_$(date '+%Y%m%d_%H%M%S').log\" 2>&1"
    # 或者，为了确保文件名中的特殊字符被正确处理，并避免 cron 对 % 的特殊解释：
    # cron_command="flock -n ${lock_file} ${cron_command_script_path} >> \"${cron_log_dir}/cron_exec_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).log\" 2>&1"
    # 上面这个版本更安全，对 % 进行了转义。

    # 一个更简洁且安全的版本，将日期格式化部分用单引号括起来，避免 cron 解释 %
    # 但在 bash -c "..." 内部，单引号和 $() 可能需要小心处理。
    # 对于直接的 cron 条目，以下方式更常见且安全：
    # The command string that will be put into crontab
    # We need to escape '%' for crontab, or ensure the command passed to bash -c handles it.
    # Since flock is the main command and redirection happens after, this should be fine.
    # Let's use a subshell for the redirection part to ensure date is evaluated at runtime.
    # This gets tricky because the whole command is one string for crontab.
    
    # 最简单且通常能工作的方式是让 date 命令在 cron 执行时被 shell 解释：
    # cron 会将整个 command 传递给 sh (通常是 /bin/sh) 来执行。
    # 所以 `date` 命令会在那时被评估。
    # 为了安全，文件名中的 `$(date ...)` 部分最好用双引号内的命令替换。
    # 关键是 cron 如何处理 %。在 cron 文件中，% 有特殊含义（表示换行，除非被转义为 \%）。
    # 但我们这里是构建一个将要被 sh 执行的命令字符串。
    
    # 推荐的方式，确保 date 在执行时被评估，并且 % 被正确处理：
    # cron_command="flock -n ${lock_file} ${cron_command_script_path} >> ${cron_log_dir}/cron_exec_\\`date +\\%Y\\%m\\%d_\\%H\\%M\\%S\\`.log 2>&1"
    # 上述命令使用了反引号和对%的转义，这是比较传统的cron写法。

    # 使用 $() 和对 % 的转义，更现代：
    cron_command="flock -n ${lock_file} ${cron_command_script_path} >> \"${cron_log_dir}/cron_exec_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).log\" 2>&1"
    # 解释：
    # \$(...) : $ 被转义，所以 $(date...) 这部分会作为字符串传递给 cron，然后在 cron 执行命令时，
    #           shell (通常是 sh) 会执行 date 命令。
    # \\%   : % 被转义两次。一次是为了 bash 字符串（如果用双引号），一次是为了 cron。
    #          如果整个 cron_command 字符串是用单引号构建的，则只需要转义一次 %。
    #          鉴于我们是用双引号构建的，这里用 \\% 是比较安全的。
    #          或者，如果 date 的格式字符串不包含特殊字符，可以直接用单引号：
    # cron_command="flock -n ${lock_file} ${cron_command_script_path} >> \"${cron_log_dir}/cron_exec_\$(date '+%Y%m%d_%H%M%S').log\" 2>&1"
    # 上面这个版本，date 的格式字符串用单引号包围，可以避免 % 的问题，推荐！
    # ---修改结束
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
            log_notice "手动修改方法: 以 root 用户执行 'sudo EDITOR="nano" crontab -e'，然后粘贴以下行:"
            log_info "当前作业内容如下："
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
    log_summary "Cron 执行日志: ${cron_log_dir}/目录下的日子文件 (如果配置了重定向)"
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