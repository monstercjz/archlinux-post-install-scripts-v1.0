#!/bin/bash

# 00_cleanup_and_finish.sh
# 清理和完成模块：在所有设置完成后执行的收尾工作。

# 通用初始化块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT=""
current_dir="$SCRIPT_DIR"
while [[ "$current_dir" != "/" && ! -d "$current_dir/config" ]]; do
    current_dir="$(dirname "$current_dir")"
done
if [[ -d "$current_dir/config" ]]; then
    PROJECT_ROOT="$current_dir"
else
    echo "错误：无法找到项目根目录 (包含 config 目录)。" >&2
    exit 1
fi
source "$PROJECT_ROOT/config/main_config.sh"
source "$PROJECT_ROOT/config/lib/utils.sh"
get_original_user_info # 获取原始用户信息

cleanup_and_finish() {
    log_info "正在执行清理和收尾工作..."

    if ! check_root_privileges; then
        return 1
    fi

    log_info "清理 Pacman 缓存..."
    pacman -Scc --noconfirm

    if [[ $? -eq 0 ]]; then
        log_success "Pacman 缓存清理成功。"
    else
        log_error "Pacman 缓存清理失败。"
    fi

    log_info "更新软件包数据库..."
    pacman -Syyu --noconfirm

    if [[ $? -eq 0 ]]; then
        log_success "软件包数据库更新成功。"
    else
        log_error "软件包数据库更新失败。"
    fi

    log_info "清理日志文件 (保留最近的5个日志文件)..."
    find "$LOG_DIR" -name "install_*.log" -type f -printf '%T@ %p\n' | sort -nr | tail -n +6 | cut -d' ' -f2- | xargs rm -f

    log_success "清理和收尾工作完成。系统已准备就绪！"
    log_info "建议您重启系统以应用所有更改。"
}

# 执行函数
cleanup_and_finish