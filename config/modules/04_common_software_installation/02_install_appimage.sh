#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/04_common_software_installation/03_install_qq_appimage.sh
# 版本: 7.0.1 (最终完整版)
# 日期: 2025-06-16
# 描述: 智能集成 AppImage 应用。通过解析并适配 AppImage 内部的 .desktop 文件，
#       实现最准确、最完整的桌面集成。此版本为绝对完整的最终代码。
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
# appimage包存放地址
APP_STANDARD_INSTALL_DIR="${ORIGINAL_HOME}/Applications"
# appimage包对应图标存放地址
ICON_STANDARD_INSTALL_DIR="${ORIGINAL_HOME}/.local/share/icons/hicolor/256x256/apps"
# appimage包desktop文件存放地址
DESKTOP_ENTRY_DIR="${ORIGINAL_HOME}/.local/share/applications"
# appimage包对应终端命令存放地址
SYMLINK_TARGET_DIR="/usr/local/bin"

# 用于辅助函数返回元数据
_SOURCE_ICON_PATH=""
_SOURCE_DESKTOP_CONTENT=""

# ==============================================================================
# 辅助函数
# ==============================================================================

_find_appimages() {
    # 定义了一组寻找路径数据
    local search_dirs=("${ORIGINAL_HOME}/下载" "$APP_STANDARD_INSTALL_DIR" "${ORIGINAL_HOME}/Desktop")
    local found_files=(); log_info "正在搜索常见目录下的 AppImage 文件..." >&2
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d '' file; do if [ -n "$file" ]; then found_files+=("$file"); fi; done < <(find "$dir" -maxdepth 1 -type f -iname "*.AppImage" -print0 2>/dev/null)
        fi
    done
    if [ ${#found_files[@]} -gt 0 ]; then printf "%s\n" "${found_files[@]}"; fi
}

# _get_source_metadata (v8.0)
# @description: 采用最可靠的图标发现策略：优先在 .desktop 文件同级目录寻找同名图标。
# @param: $1 (string) - AppImage 文件的路径
# @returns: 无。通过全局变量 _SOURCE_ICON_PATH 和 _SOURCE_DESKTOP_CONTENT 返回结果。
_get_source_metadata() {
    local appimage_path="$1"; local app_name=$(basename "${appimage_path%.*}")
    _SOURCE_ICON_PATH=""; _SOURCE_DESKTOP_CONTENT=""

    # --- 策略 0: 在标准库寻找图标 ---
    log_info "策略 1/4: 正在标准用户图标库中寻找已安装的图标..." >&2
    run_as_user "mkdir -p '$ICON_STANDARD_INSTALL_DIR'"
    local std_icon_path=""; local std_icon_png="${ICON_STANDARD_INSTALL_DIR}/${app_name}.png"; local std_icon_svg="${ICON_STANDARD_INSTALL_DIR}/${app_name}.svg"
    if [ -f "$std_icon_png" ]; then std_icon_path="$std_icon_png"; elif [ -f "$std_icon_svg" ]; then std_icon_path="$std_icon_svg"; fi
    if [ -n "$std_icon_path" ]; then
        log_success "在标准库中找到了已安装的图标。" >&2
        _SOURCE_ICON_PATH="$std_icon_path"
    fi

    # --- 策略 1: 基于 .desktop 文件精确提取 (首选) ---
    log_info "策略 2/4: 尝试从 AppImage 内部精确提取元数据..." >&2
    if command -v unsquashfs &>/dev/null; then
        if _confirm_action "是否尝试从 AppImage 内部自动提取应用信息? (推荐)" "y"; then
            local temp_dir; temp_dir=$(mktemp -d); chown "${ORIGINAL_USER}:${ORIGINAL_USER_GROUP:-$ORIGINAL_USER}" "$temp_dir"
            if run_as_user "cd '$temp_dir' && '$appimage_path' --appimage-extract >/dev/null 2>&1"; then
                # 1. 在整个提取目录中寻找 .desktop 文件，因为它的位置不总是固定的
                local desktop_file; desktop_file=$(run_as_user "find '$temp_dir/squashfs-root' -type f -name '*.desktop' 2>/dev/null | head -n 1")
                
                if [ -n "$desktop_file" ]; then
                    log_info "在 AppImage 内部找到了 .desktop 文件: $desktop_file" >&2
                    _SOURCE_DESKTOP_CONTENT=$(cat "$desktop_file")
                    
                    # 2. **终极核心逻辑**: 在 .desktop 文件的同级目录下寻找同名图标
                    local desktop_dir; desktop_dir=$(dirname "$desktop_file")
                    local desktop_basename; desktop_basename=$(basename "${desktop_file%.*}") # 获取不带 .desktop 后缀的文件名
                    
                    local found_icon=""
                    local potential_png="${desktop_dir}/${desktop_basename}.png"
                    local potential_svg="${desktop_dir}/${desktop_basename}.svg"

                    if [ -f "$potential_png" ]; then
                        found_icon="$potential_png"
                    elif [ -f "$potential_svg" ]; then
                        found_icon="$potential_svg"
                    fi

                    if [ -n "$found_icon" ]; then
                        # 找到了同级目录下的图标文件（或符号链接）
                        local temp_copy="/tmp/appimage_icon_$(date +%s)_$(basename "$found_icon")"
                        # cp 会自动处理符号链接，复制其指向的源文件
                        if cp "$found_icon" "$temp_copy"; then
                            _SOURCE_ICON_PATH="$temp_copy"
                        fi
                    fi
                fi
            fi; rm -rf "$temp_dir"
        fi
    fi

    if [ -n "$_SOURCE_DESKTOP_CONTENT" ]; then
        log_success "成功从 AppImage 内部提取到 .desktop 元数据。" >&2
        if [ -n "$_SOURCE_ICON_PATH" ]; then
             log_success "并成功关联到了图标文件。" >&2
        else
             log_warn "但未能成功关联到图标文件。" >&2
        fi
        return 0
    fi
    
    # --- Fallback: 如果无法提取 .desktop, 则退回到只找图标的策略 ---
    log_warn "无法从内部提取 .desktop 文件, 将退回到仅寻找图标的模式。" >&2
    if [ -z "$_SOURCE_ICON_PATH" ]; then
        local base_name="${appimage_path%.*}"; local side_icon_path=""
        if [ -f "${base_name}.png" ]; then side_icon_path="${base_name}.png"; elif [ -f "${base_name}.svg" ]; then side_icon_path="${base_name}.svg"; fi
        if [ -n "$side_icon_path" ]; then log_success "在 AppImage 旁边找到了图标。" >&2; _SOURCE_ICON_PATH="$side_icon_path"; fi
    fi
    if [ -z "$_SOURCE_ICON_PATH" ]; then
        log_warn "所有自动查找图标的方法都已失败。" >&2
        if _confirm_action "是否要手动指定一个现有的图标文件路径?" "n"; then
            echo -e "${COLOR_CYAN}提示: 请提供一个您已准备好的、在本地磁盘上的图标文件 (如 .png 或 .svg) 的完整路径。${COLOR_RESET}"
            read -rp "请输入图标文件的完整路径: " manual_path; manual_path="${manual_path//\'/}"
            if [ -f "$manual_path" ]; then
                log_success "已接受手动指定的图标。" >&2
                _SOURCE_ICON_PATH="$manual_path"
            else
                log_error "路径无效或文件不存在: '$manual_path'" >&2
                # 此时，不再继续，而是给用户一个机会
            fi
        fi
    fi
    
    return 0
}

# # ==============================================================================
# # 主逻辑 (注释掉的是使用绝对路径的方法)
# # ==============================================================================
# main() {
#     display_header_section "AppImage 应用安装程序" "box" 80
#     if ! command -v unsquashfs &>/dev/null; then
#         if _confirm_action "未检测到 'squashfs-tools'，将无法使用图标自动提取功能。是否现在安装它?" "y"; then
#             install_packages "squashfs-tools"
#         fi
#     fi

#     # --- 1. 发现 AppImage ---
#     local source_appimage_path
#     mapfile -t found_files < <(_find_appimages); echo 
#     if [ ${#found_files[@]} -gt 0 ]; then
#         echo -e "${COLOR_BRIGHT_GREEN}✔ 检测到以下 ${#found_files[@]} 个 AppImage 文件:${COLOR_RESET}"
#         for i in "${!found_files[@]}"; do printf "  ${COLOR_GREEN}%2d.${COLOR_RESET} %s\n" "$((i+1))" "${found_files[$i]}"; done
#     else
#         echo -e "${COLOR_YELLOW}⚠ 在常见目录中未自动检测到任何 AppImage 文件。${COLOR_RESET}"
#     fi
#     echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
#     echo -e "  ${COLOR_CYAN}m. 手动输入路径 (Manual path)${COLOR_RESET}"
#     echo -e "  ${COLOR_RED}q. 退出 (Quit)${COLOR_RESET}"; echo 
#     read -rp "$(echo -e "${COLOR_YELLOW}请选择文件序号，或输入 'm' 手动指定, 'q' 退出: ${COLOR_RESET}")" choice

#     case "$choice" in
#         [qQ]) log_info "操作已取消。"; return 0 ;;
#         [mM])
#             read -rp "请输入 AppImage 文件的完整路径: " manual_path; manual_path="${manual_path//\'/}"
#             if [ -f "$manual_path" ]; then source_appimage_path="$manual_path";
#             else log_error "路径无效或文件不存在: '$manual_path'"; return 1; fi
#             ;;
#         *)
#             if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#found_files[@]}" ]; then
#                 source_appimage_path="${found_files[$((choice-1))]}"
#             else log_error "无效选择: '$choice'"; return 1; fi
#             ;;
#     esac
#     log_info "已选择 AppImage: '$source_appimage_path'"
    
#     # --- 2. 规范化 AppImage ---
#     local final_appimage_path; local app_filename=$(basename "$source_appimage_path")
#     local source_dir_abs; source_dir_abs=$(cd "$(dirname "$source_appimage_path")" && pwd -P)
#     run_as_user "mkdir -p '$APP_STANDARD_INSTALL_DIR'"; local standard_dir_abs; standard_dir_abs=$(run_as_user "cd '$APP_STANDARD_INSTALL_DIR' && pwd -P")
#     if [[ "$source_dir_abs" != "$standard_dir_abs" ]]; then
#         if _confirm_action "是否将文件复制到统一管理目录 '$standard_dir_abs'? (推荐)" "y"; then
#             if ! run_as_user "cp '$source_appimage_path' '$standard_dir_abs/$app_filename'"; then log_error "复制文件失败。"; return 1; fi
#             final_appimage_path="${standard_dir_abs}/${app_filename}"; log_success "文件已复制。"
#         else
#             final_appimage_path="$source_appimage_path"; log_warn "用户选择不复制文件，将直接使用原始路径。"
#         fi
#     else
#         final_appimage_path="$source_appimage_path"; log_info "文件已在标准管理目录中。"
#     fi

#     # --- 3. 获取源元数据 ---
#     _get_source_metadata "$final_appimage_path"

#     # --- 4. 核心安装与集成流程 ---
#     log_info "开始核心安装与集成流程..."
#     run_as_user "mkdir -p '$DESKTOP_ENTRY_DIR'"; run_as_user "chmod +x '$final_appimage_path'"
#     local app_logic_name=$(basename "${final_appimage_path%.*}");
    
#     # a. 安装图标
#     local final_icon_path=""
#     if [[ -n "$_SOURCE_ICON_PATH" ]]; then
#         local icon_ext="${_SOURCE_ICON_PATH##*.}";
#         local icon_target_path="${ICON_STANDARD_INSTALL_DIR}/${app_logic_name}.${icon_ext}"
#         run_as_user "mkdir -p '$ICON_STANDARD_INSTALL_DIR'"
#         if run_as_user "cp '$_SOURCE_ICON_PATH' '$icon_target_path'"; then
#              log_success "图标已成功安装到: $icon_target_path"
#              final_icon_path="$icon_target_path"
#         else
#              log_error "安装图标到 '$ICON_STANDARD_INSTALL_DIR' 失败。"
#         fi
#         if [[ "$_SOURCE_ICON_PATH" == /tmp/appimage_icon_* ]]; then rm -f "$_SOURCE_ICON_PATH"; fi
#     fi
    
#     # b. 创建快捷方式
#     if _confirm_action "是否创建桌面菜单快捷方式?" "y"; then
#         if [ -z "$final_icon_path" ] && ! _confirm_action "最终未能获取图标。是否继续创建无图标的快捷方式?" "y" "${COLOR_YELLOW}"; then
#             log_info "已取消创建快捷方式。";
#         else
#             local desktop_file_path="${DESKTOP_ENTRY_DIR}/${app_logic_name}.desktop"
#             local final_desktop_content=""

#             if [ -n "$_SOURCE_DESKTOP_CONTENT" ]; then
#                 final_desktop_content=$(echo "$_SOURCE_DESKTOP_CONTENT" | sed \
#                     -e "s|^Exec=.*|Exec=\"${final_appimage_path}\" %U|" \
#                     -e "s|^Icon=.*|Icon=${final_icon_path}|")
#             else
#                 final_desktop_content="[Desktop Entry]\nName=${app_logic_name}\nExec=\"${final_appimage_path}\" %U\n"
#                 if [ -n "$final_icon_path" ]; then final_desktop_content+="Icon=${final_icon_path}\n"; fi
#                 final_desktop_content+="Terminal=false\nType=Application\nCategories=Application;"
#             fi

#             if ! run_as_user "echo -e \"$final_desktop_content\" > '$desktop_file_path'"; then
#                 log_error "创建快捷方式失败。"
#             else
#                 log_success "桌面快捷方式文件已创建。"
#                 # **关键修正**: 在创建后立即、直接执行缓存更新
#                 if command -v update-desktop-database &>/dev/null; then
#                     log_info "正在更新桌面应用程序数据库..."
#                     # 直接使用 sudo -u 执行，不通过 run_as_user
#                     # $DESKTOP_ENTRY_DIR 是在 root shell 中定义的，其值包含了 /home/cjz，是正确的绝对路径
#                     if sudo -u "$ORIGINAL_USER" bash -c "update-desktop-database -q '$DESKTOP_ENTRY_DIR'"; then
#                         log_success "桌面数据库更新成功。"
#                     else
#                         log_warn "桌面数据库更新失败。"
#                     fi
#                 fi
#             fi
#         fi
#     fi

#     # c. 创建终端命令
#     if _confirm_action "是否创建终端命令?" "y"; then
#         read -rp "请输入终端命令的名称 (默认为 '${app_logic_name,,}'): " cmd_name; cmd_name="${cmd_name:-${app_logic_name,,}}"
#         local symlink_path="${SYMLINK_TARGET_DIR}/${cmd_name}"
#         if [ -e "$symlink_path" ]; then
#             log_warn "命令 '${cmd_name}' 已存在于 '${SYMLINK_TARGET_DIR}'，将跳过。"
#         else
#             if ln -s "$final_appimage_path" "$symlink_path"; then
#                 log_success "成功创建终端命令: '${cmd_name}'"
#             else
#                 log_error "创建命令失败，请检查 root 权限。"
#             fi
#         fi
#     fi
    
#     log_success "AppImage 应用 '${app_logic_name}' 安装配置流程结束！"
#     # **关键修正**: 在所有操作完成后，统一给出最终提示
#     log_notice "请注意：新的应用程序或其图标可能需要您注销并重新登录，或重启电脑后才能正确显示。"
#     return 0
# }

# ==============================================================================
# 主逻辑
# ==============================================================================
main() {
    display_header_section "AppImage 应用安装程序" "box" 80
    if ! command -v unsquashfs &>/dev/null; then
        if _confirm_action "未检测到 'squashfs-tools'，将无法使用图标自动提取功能。是否现在安装它?" "y"; then
            install_packages "squashfs-tools"
        fi
    fi

    # --- 1. 发现 AppImage ---
    local source_appimage_path
    mapfile -t found_files < <(_find_appimages); echo 
    if [ ${#found_files[@]} -gt 0 ]; then
        echo -e "${COLOR_BRIGHT_GREEN}✔ 检测到以下 ${#found_files[@]} 个 AppImage 文件:${COLOR_RESET}"
        for i in "${!found_files[@]}"; do printf "  ${COLOR_GREEN}%2d.${COLOR_RESET} %s\n" "$((i+1))" "${found_files[$i]}"; done
    else
        echo -e "${COLOR_YELLOW}⚠ 在常见目录中未自动检测到任何 AppImage 文件。${COLOR_RESET}"
    fi
    echo -e "${COLOR_PURPLE}--------------------------------------------------------------------------------${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}m. 手动输入路径 (Manual path)${COLOR_RESET}"
    echo -e "  ${COLOR_RED}q. 退出 (Quit)${COLOR_RESET}"; echo 
    read -rp "$(echo -e "${COLOR_YELLOW}请选择文件序号，或输入 'm' 手动指定, 'q' 退出: ${COLOR_RESET}")" choice

    case "$choice" in
        [qQ]) log_info "操作已取消。"; return 0 ;;
        [mM])
            read -rp "请输入 AppImage 文件的完整路径: " manual_path; manual_path="${manual_path//\'/}"
            if [ -f "$manual_path" ]; then source_appimage_path="$manual_path";
            else log_error "路径无效或文件不存在: '$manual_path'"; return 1; fi
            ;;
        *)
            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#found_files[@]}" ]; then
                source_appimage_path="${found_files[$((choice-1))]}"
            else log_error "无效选择: '$choice'"; return 1; fi
            ;;
    esac
    log_info "已选择 AppImage: '$source_appimage_path'"
    
    # --- 2. 规范化 AppImage ---
    local final_appimage_path; local app_filename=$(basename "$source_appimage_path")
    local source_dir_abs; source_dir_abs=$(cd "$(dirname "$source_appimage_path")" && pwd -P)
    run_as_user "mkdir -p '$APP_STANDARD_INSTALL_DIR'"; local standard_dir_abs; standard_dir_abs=$(run_as_user "cd '$APP_STANDARD_INSTALL_DIR' && pwd -P")
    if [[ "$source_dir_abs" != "$standard_dir_abs" ]]; then
        if _confirm_action "是否将文件复制到统一管理目录 '$standard_dir_abs'? (推荐)" "y"; then
            if ! run_as_user "cp '$source_appimage_path' '$standard_dir_abs/$app_filename'"; then log_error "复制文件失败。"; return 1; fi
            final_appimage_path="${standard_dir_abs}/${app_filename}"; log_success "文件已复制。"
        else
            final_appimage_path="$source_appimage_path"; log_warn "用户选择不复制文件，将直接使用原始路径。"
        fi
    else
        final_appimage_path="$source_appimage_path"; log_info "文件已在标准管理目录中。"
    fi

    # --- 3. 获取源元数据 ---
    _get_source_metadata "$final_appimage_path"

    # --- 4. 核心安装与集成流程 ---
    log_info "开始核心安装与集成流程..."
    run_as_user "mkdir -p '$DESKTOP_ENTRY_DIR'"; run_as_user "chmod +x '$final_appimage_path'"
    local app_logic_name=$(basename "${final_appimage_path%.*}");
    local final_icon_name=""

    # a. 安装图标
    if [[ -n "$_SOURCE_ICON_PATH" ]]; then
        # **关键修正**: 检查源图标是否已在标准目录，如果是，则无需复制
        local source_icon_dir_abs; source_icon_dir_abs=$(cd "$(dirname "$_SOURCE_ICON_PATH")" && pwd -P)
        local standard_icon_dir_abs; standard_icon_dir_abs=$(run_as_user "cd '$ICON_STANDARD_INSTALL_DIR' && pwd -P")
        
        if [[ "$source_icon_dir_abs" == "$standard_icon_dir_abs" ]]; then
            log_info "图标已在标准目录中，无需复制。"
            final_icon_name=$(basename "${_SOURCE_ICON_PATH%.*}")
        else
            # 源图标不在标准目录，需要复制安装
            local icon_ext="${_SOURCE_ICON_PATH##*.}";
            local icon_target_path="${ICON_STANDARD_INSTALL_DIR}/${app_logic_name}.${icon_ext}"
            run_as_user "mkdir -p '$ICON_STANDARD_INSTALL_DIR'"
            if run_as_user "cp '$_SOURCE_ICON_PATH' '$icon_target_path'"; then
                 log_success "图标已成功安装到: $icon_target_path"
                 final_icon_name="$app_logic_name"
            else
                 log_error "安装图标到 '$ICON_STANDARD_INSTALL_DIR' 失败。"
            fi
            # 如果源是/tmp下的临时文件，使用后立即清理
            if [[ "$_SOURCE_ICON_PATH" == /tmp/appimage_icon_* ]]; then
                rm -f "$_SOURCE_ICON_PATH"
            fi
        fi
    fi
    
    # b. 创建快捷方式
    if _confirm_action "是否创建桌面菜单快捷方式?" "y"; then
        if [ -z "$final_icon_name" ] && ! _confirm_action "最终未能获取图标。是否继续创建无图标的快捷方式?" "y" "${COLOR_YELLOW}"; then
            log_info "已取消创建快捷方式。";
        else
            local desktop_file_path="${DESKTOP_ENTRY_DIR}/${app_logic_name}.desktop"
            local final_desktop_content=""

            if [ -n "$_SOURCE_DESKTOP_CONTENT" ]; then
                final_desktop_content=$(echo "$_SOURCE_DESKTOP_CONTENT" | sed \
                    -e "s|^Exec=.*|Exec=\"${final_appimage_path}\" %U|" \
                    -e "s|^Icon=.*|Icon=${final_icon_name}|")
            else
                final_desktop_content="[Desktop Entry]\nName=${app_logic_name}\nExec=\"${final_appimage_path}\" %U\n"
                if [ -n "$final_icon_name" ]; then final_desktop_content+="Icon=${final_icon_name}\n"; fi
                final_desktop_content+="Terminal=false\nType=Application\nCategories=Application;"
            fi

            if ! run_as_user "echo -e \"$final_desktop_content\" > '$desktop_file_path'"; then
                log_error "创建快捷方式失败。"
            else
                log_success "桌面快捷方式文件已创建。"
            fi
        fi
    fi

    # c. 创建终端命令
    if _confirm_action "是否创建终端命令?" "y"; then
        read -rp "请输入终端命令的名称 (默认为 '${app_logic_name,,}'): " cmd_name; cmd_name="${cmd_name:-${app_logic_name,,}}"
        local symlink_path="${SYMLINK_TARGET_DIR}/${cmd_name}"
        if [ -e "$symlink_path" ]; then
            log_warn "命令 '${cmd_name}' 已存在于 '${SYMLINK_TARGET_DIR}'，将跳过。"
        else
            if ln -s "$final_appimage_path" "$symlink_path"; then
                log_success "成功创建终端命令: '${cmd_name}'"
            else
                log_error "创建命令失败，请检查 root 权限。"
            fi
        fi
    fi
    
    log_success "AppImage 应用 '${app_logic_name}' 安装配置流程结束！"
    
    # --- 5. 最终的用户指令 ---
    display_header_section "重要后续步骤" "box" 60 "${COLOR_YELLOW}"
    log_summary "所有文件已安装完毕。"
    log_summary "为了让新的应用程序及其图标在菜单中正确显示，您可能需要手动刷新系统缓存。"
    log_summary "请打开一个新的终端，并以普通用户(${ORIGINAL_USER})身份执行以下命令："
    echo # 空行
    log_summary "  ${COLOR_CYAN}update-desktop-database -v ~/.local/share/applications${COLOR_RESET}"
    log_summary "  ${COLOR_CYAN}gtk-update-icon-cache -f -v ~/.local/share/icons/hicolor${COLOR_RESET}"
    echo # 空行
    log_summary "如果图标仍然没有显示，最可靠的方法是 ${COLOR_BOLD}注销并重新登录${COLOR_RESET}，或重启电脑。"
    
    return 0
}

# --- 脚本入口 ---
main "$@"
exit $?