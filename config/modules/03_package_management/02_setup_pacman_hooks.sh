#!/bin/bash

# 02_setup_pacman_hooks.sh
# 设置 Pacman Hooks 的原子功能脚本（会从 assets/ 中读取文件）。

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

setup_pacman_hooks() {
    log_info "正在设置 Pacman Hooks..."

    if ! check_root_privileges; then
        return 1
    fi

    local hook_source_dir="$PROJECT_ROOT/config/assets/pacman/hooks"
    local hook_target_dir="/etc/pacman.d/hooks"

    # 确保目标目录存在
    mkdir -p "$hook_target_dir"

    # 遍历 assets/pacman/hooks 目录下的所有 .hook 文件和 .sh 文件
    for file in "$hook_source_dir"/*; do
        local filename=$(basename "$file")
        local target_path="$hook_target_dir/$filename"

        if [[ -f "$file" ]]; then
            log_info "复制 $filename 到 $hook_target_dir..."
            cp "$file" "$target_path"
            if [[ $? -eq 0 ]]; then
                log_success "复制 $filename 成功。"
                # 对于 .sh 脚本，确保它们是可执行的
                if [[ "$filename" == *.sh ]]; then
                    log_info "设置 $filename 为可执行权限..."
                    chmod +x "$target_path"
                    if [[ $? -eq 0 ]]; then
                        log_success "设置 $filename 可执行权限成功。"
                    else
                        log_error "设置 $filename 可执行权限失败。"
                    fi
                fi
                # 对于 .hook 文件，需要替换其中的路径占位符
                if [[ "$filename" == *.hook ]]; then
                    log_info "更新 $filename 中的脚本路径..."
                    # 使用 sed 替换 /path/to/your/archlinux-post-install-scripts 为实际的 PROJECT_ROOT
                    sed -i "s|/path/to/your/archlinux-post-install-scripts|$PROJECT_ROOT|g" "$target_path"
                    if [[ $? -eq 0 ]]; then
                        log_success "更新 $filename 中的脚本路径成功。"
                    else
                        log_error "更新 $filename 中的脚本路径失败。"
                    fi
                fi
            else
                log_error "复制 $filename 失败。"
            fi
        fi
    done

    log_success "Pacman Hooks 设置完成。"
}

# 执行函数
setup_pacman_hooks