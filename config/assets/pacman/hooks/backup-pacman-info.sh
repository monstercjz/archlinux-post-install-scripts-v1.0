#!/bin/bash

# backup-pacman-info.sh
# 这是一个示例脚本，用于在 Pacman hook 中调用，备份 Pacman 数据库信息。

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

log_info "正在备份 Pacman 数据库信息..."

# 示例：备份 Pacman 数据库
# 实际应用中，你可能需要更复杂的备份策略，例如压缩和定期清理
tar -czf "${LOG_DIR}/pacman_db_backup_$(date +%Y%m%d_%H%M%S).tar.gz" /var/lib/pacman/local

if [[ $? -eq 0 ]]; then
    log_success "Pacman 数据库信息备份成功。"
else
    log_error "Pacman 数据库信息备份失败。"
fi