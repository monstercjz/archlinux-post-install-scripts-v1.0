#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/04_common_software_installation/04_uninstall_appimage.sh
# 版本: 1.0.0
# 日期: 2025-06-16
# 描述: 卸载通过本框架安装的 AppImage 应用。
# ------------------------------------------------------------------------------
# 功能:
# - 自动扫描标准目录，列出所有已安装的 AppImage 应用。
# - 允许用户选择要卸载的应用。
# - 自动定位并列出所有相关文件（AppImage、.desktop、图标、终端符号链接）。
# - 获取用户最终确认后，安全、彻底地删除所有相关文件。
# - 提示用户刷新缓存或注销以使更改完全生效。
# ==============================================================================

# --- 脚本顶部引导块 START ---
set -euo pipefail
_current_script_entrypoint="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
if [ -z "${BASE_DIR+set}" ]; then
    _project_root_candidate=$(cd "$(dirname "$_current_script_entrypoint")" && pwd -P); _found_base_dir=""
    while [[ "$_project_root_candidate" != "/" ]]; do
        if [[ -f "$_project_root_candidate/run_setup.sh" && -d "$_project_root_candidate/config" ]]; then _found_base_dir="$_project_root_candidate"; break; fi
        _project_root_candidate=$(dirname "$_project_root_candidate")
    done
    if [[ -z "$_found_base_dir" ]]; then echo -e "\033[0;31mFatal Error:\033[0m Could not determine project base directory." >&2; exit 1; fi
    export BASE_DIR="$_found_base_dir"
fi
source "${BASE_DIR}/config/lib/environment_setup.sh" "$_current_script_entrypoint"
# --- 脚本顶部引导块 END ---

# ==============================================================================
# 全局变量和定义
# ==============================================================================

APP_STANDARD_INSTALL_DIR="${ORIGINAL_HOME}/Applications"
ICON_STANDARD_INSTALL_DIR="${ORIGINAL_HOME}/.local/share/icons/hicolor/256x256/apps"
DESKTOP_ENTRY_DIR="${ORIGINAL_HOME}/.local/share/applications"
SYMLINK_TARGET_DIR="/usr/local/bin"

# ==============================================================================
# 主逻辑
# ==============================================================================
main() {
    while true; do
        clear
        display_header_section "AppImage 应用卸载程序" "box" 80

        # --- 1. 扫描并列出已安装的应用 ---
        local installed_apps=()
        if [ -d "$APP_STANDARD_INSTALL_DIR" ]; then
            while IFS= read -r -d '' file; do
                if [ -n "$file" ]; then installed_apps+=("$file"); fi
            done < <(find "$APP_STANDARD_INSTALL_DIR" -maxdepth 1 -type f -iname "*.AppImage" -print0 2>/dev/null)
        fi
        
        if [ ${#installed_apps[@]} -eq 0 ]; then
            log_warn "在 '$APP_STANDARD_INSTALL_DIR' 目录中未找到任何已安装的 AppImage 应用。"
            read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回...${COLOR_RESET}")"
            return 0
        fi

        log_info "发现以下 ${#installed_apps[@]} 个已安装的应用:"
        for i in "${!installed_apps[@]}"; do
            printf "  ${COLOR_GREEN}%2d.${COLOR_RESET} %s\n" "$((i+1))" "$(basename "${installed_apps[$i]}")"
        done
        echo "--------------------------------------------------"
        echo -e "  ${COLOR_RED}0.${COLOR_RESET} 退出卸载程序"

        # --- 2. 用户选择 ---
        read -rp "$(echo -e "${COLOR_YELLOW}请输入要卸载的应用序号: ${COLOR_RESET}")" choice
        if [[ "$choice" == "0" ]]; then
            log_info "退出卸载程序。"
            return 0
        fi
        if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || [ "$choice" -gt "${#installed_apps[@]}" ]; then
            log_error "无效选择: '$choice'"
            read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 重试...${COLOR_RESET}")"
            continue
        fi

        local app_to_uninstall_path="${installed_apps[$((choice-1))]}"
        local app_logic_name=$(basename "${app_to_uninstall_path%.*}")

        # --- 3. 定位所有相关文件 ---
        clear
        display_header_section "确认卸载: ${app_logic_name}" "box" 80
        log_warn "将要删除以下所有与此应用相关的文件和链接："
        
        local files_to_delete=()
        
        # a. AppImage 文件
        if [ -f "$app_to_uninstall_path" ]; then files_to_delete+=("$app_to_uninstall_path"); fi
        
        # b. .desktop 文件
        local desktop_file="${DESKTOP_ENTRY_DIR}/${app_logic_name}.desktop"
        if [ -f "$desktop_file" ]; then files_to_delete+=("$desktop_file"); fi

        # c. 图标文件 (检查 .png 和 .svg)
        local icon_png="${ICON_STANDARD_INSTALL_DIR}/${app_logic_name}.png"
        local icon_svg="${ICON_STANDARD_INSTALL_DIR}/${app_logic_name}.svg"
        if [ -f "$icon_png" ]; then files_to_delete+=("$icon_png"); fi
        if [ -f "$icon_svg" ]; then files_to_delete+=("$icon_svg"); fi
        
        # d. 终端符号链接
        # 使用 find 来安全地查找指向该 AppImage 的符号链接
        local symlinks
        mapfile -t symlinks < <(find "$SYMLINK_TARGET_DIR" -type l -lname "$app_to_uninstall_path" 2>/dev/null)
        if [ ${#symlinks[@]} -gt 0 ]; then
            files_to_delete+=("${symlinks[@]}")
        fi

        if [ ${#files_to_delete[@]} -eq 0 ]; then
             log_warn "未找到任何与 '${app_logic_name}' 相关联的文件可供删除。"
             read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回...${COLOR_RESET}")"
             continue
        fi

        # 打印待删除列表
        for file in "${files_to_delete[@]}"; do
            echo -e "  - ${COLOR_RED}${file}${COLOR_RESET}"
        done
        echo

        # --- 4. 最终确认并执行删除 ---
        if _confirm_action "此操作不可恢复！是否确认删除以上所有文件?" "n" "${COLOR_RED}"; then
            log_info "正在执行卸载操作..."
            local all_deleted=true
            for file in "${files_to_delete[@]}"; do
                log_info "正在删除: $file"
                # 用户目录下的文件用 run_as_user, 系统目录下的用 root (脚本本身权限)
                if [[ "$file" == ${SYMLINK_TARGET_DIR}* ]]; then
                    if ! rm -f "$file"; then
                        log_error "删除 '$file' 失败。"; all_deleted=false
                    fi
                else
                    if ! run_as_user "rm -f '$file'"; then
                        log_error "删除 '$file' 失败。"; all_deleted=false
                    fi
                fi
            done
            
            if $all_deleted; then
                log_success "应用 '${app_logic_name}' 已成功卸载。"
            else
                log_error "部分文件卸载失败，请检查上面的日志。"
            fi

            # --- 5. 提示刷新缓存 ---
            log_notice "为了让更改完全生效，建议您手动刷新缓存或注销/重启。"
            log_info "您可以手动执行: update-desktop-database -q ~/.local/share/applications"

        else
            log_info "卸载操作已取消。"
        fi
        
        read -rp "$(echo -e "${COLOR_YELLOW}按 Enter 返回列表或退出...${COLOR_RESET}")"
    done
}

# --- 脚本入口 ---
main "$@"
exit $?