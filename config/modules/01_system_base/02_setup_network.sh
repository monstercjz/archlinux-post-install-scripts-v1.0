#!/bin/bash

# 02_setup_network.sh
# 设置IP信息、防火墙等（如果需要手动配置）的原子功能脚本。

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

setup_network() {
    log_info "正在设置网络..."

    if ! check_root_privileges; then
        return 1
    fi

    log_info "建议使用 systemd-networkd 进行网络配置。"
    log_info "将示例网络配置文件复制到 ${SYSTEMD_NETWORKD_CONFIG_PATH}/20-wired.network"

    # 确保目标目录存在
    mkdir -p "$SYSTEMD_NETWORKD_CONFIG_PATH"

    # 复制示例配置文件
    cp "$PROJECT_ROOT/config/assets/network/systemd-networkd-example.conf" "${SYSTEMD_NETWORKD_CONFIG_PATH}/20-wired.network"

    if [[ $? -eq 0 ]]; then
        log_success "示例网络配置文件复制成功。"
        log_info "请根据您的网络环境编辑 ${SYSTEMD_NETWORKD_CONFIG_PATH}/20-wired.network 文件。"
        log_info "编辑完成后，请运行 'sudo systemctl enable --now systemd-networkd' 启用网络服务。"
    else
        log_error "复制示例网络配置文件失败。"
    fi

    log_info "防火墙配置（可选）："
    log_info "建议安装并配置 UFW 或 firewalld。"
    log_info "例如，安装 UFW: sudo pacman -S ufw"
    log_info "启用 UFW: sudo systemctl enable --now ufw"
    log_info "允许 SSH: sudo ufw allow ssh"
    log_info "启用防火墙: sudo ufw enable"
}

# 执行函数
setup_network