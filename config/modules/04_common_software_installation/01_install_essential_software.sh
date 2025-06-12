#!/bin/bash
# ==============================================================================
# 项目: archlinux-post-install-scripts
# 文件: config/modules/04_software_installation/01_install_essential_software.sh
# 版本: 2.0.0 (重构为从文件读取软件包列表)
# 日期: 2025-06-12
# 描述: 安装基础开发工具和系统实用程序。
# ------------------------------------------------------------------------------
# 变更记录:
# v2.0.0 - 2025-06-12 - 重构逻辑，不再使用硬编码数组，而是从外部 .list 文件
#                        读取要安装的软件包列表。
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
# 主函数
# ==============================================================================
main() {
    display_header_section "安装基础软件" "box" 80
    
    # 1. 构建软件包列表文件的完整路径
    local list_file="${ASSETS_DIR}/${PKG_LISTS_DIR_RELATIVE_TO_ASSETS}/essential.list"
    
    log_info "正在从文件读取基础软件包列表: $list_file"
    
    # 2. 调用辅助函数读取并格式化软件包列表
    local pkgs_to_install
    pkgs_to_install=$(_read_pkg_list_from_file "$list_file")

    # 3. 检查列表是否为空
    if [ -z "$pkgs_to_install" ]; then
        log_info "基础软件包列表为空，无需安装。跳过。"
        return 0
    fi

    log_notice "将要安装以下基础软件包:"
    log_summary "${pkgs_to_install}" # 使用 log_summary 格式化输出
    
    if ! _confirm_action "是否继续安装？" "y" "${COLOR_YELLOW}"; then
        log_info "用户已取消安装。"
        return 0
    fi
    
    # 4. 调用安装函数
    if ! install_pacman_pkg $pkgs_to_install; then
        log_error "安装部分基础软件包失败。请检查日志获取详细信息。"
        # 即使失败，也允许脚本继续，而不是中止整个流程
        return 1 
    fi

    log_success "基础软件安装完成。"
    return 0
}

# ==============================================================================
# 脚本入口点
# ==============================================================================
main "$@"

exit_script() {
    local exit_code=${1:-$?_}
    if [ "$exit_code" -eq 0 ]; then
        log_info "成功退出基础软件安装脚本。"
    else
        log_warn "基础软件安装脚本因错误退出 (退出码: $exit_code)。"
    fi
    exit "$exit_code"
}
exit_script $?