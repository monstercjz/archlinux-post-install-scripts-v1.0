#!/bin/bash
# ==============================================================================
# 脚本: p10k_config.sh
# 版本: 1.0.0
# 日期: 2025-06-12
# 描述: 交互式配置 Powerlevel10k (p10k) Zsh 主题
# ==============================================================================

# 严格模式
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 确认函数
confirm() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# 检查系统
check_system() {
    log_info "检查系统环境..."
    
    # 检查是否使用Zsh
    if [ "$SHELL" != "/usr/bin/zsh" ] && [ "$SHELL" != "/bin/zsh" ]; then
        log_warn "你当前没有使用Zsh作为默认shell。Powerlevel10k是Zsh主题，需要先切换到Zsh。"
        if confirm "是否现在安装并切换到Zsh?"; then
            install_zsh
        else
            log_warn "跳过Zsh安装，脚本将继续，但p10k可能无法正常工作。"
        fi
    else
        log_success "检测到已使用Zsh作为默认shell。"
    fi
    
    # 检查git是否安装
    if ! command_exists git; then
        log_warn "未检测到git，将无法克隆Powerlevel10k仓库。"
        if confirm "是否现在安装git?"; then
            install_git
        else
            log_error "必须安装git才能继续，脚本退出。"
            exit 1
        fi
    else
        log_success "git已安装。"
    fi
    
    # 检查Powerlevel10k是否已安装
    if [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
        log_info "检测到Powerlevel10k已安装。"
        if confirm "是否重新配置Powerlevel10k?"; then
            log_info "将重新配置Powerlevel10k..."
        else
            log_success "已取消配置，脚本退出。"
            exit 0
        fi
    fi
}

# 安装Zsh
install_zsh() {
    log_info "开始安装Zsh..."
    
    if command_exists apt; then
        sudo apt-get update
        sudo apt-get install -y zsh
        chsh -s $(which zsh)
        log_success "Zsh已安装并设置为默认shell。请重新登录使更改生效。"
    elif command_exists yum; then
        sudo yum install -y zsh
        chsh -s $(which zsh)
        log_success "Zsh已安装并设置为默认shell。请重新登录使更改生效。"
    elif command_exists dnf; then
        sudo dnf install -y zsh
        chsh -s $(which zsh)
        log_success "Zsh已安装并设置为默认shell。请重新登录使更改生效。"
    elif command_exists pacman; then
        sudo pacman -S zsh
        chsh -s $(which zsh)
        log_success "Zsh已安装并设置为默认shell。请重新登录使更改生效。"
    else
        log_error "无法检测到包管理器，无法安装Zsh。请手动安装Zsh后再运行此脚本。"
        exit 1
    fi
}

# 安装git
install_git() {
    log_info "开始安装git..."
    
    if command_exists apt; then
        sudo apt-get update
        sudo apt-get install -y git
    elif command_exists yum; then
        sudo yum install -y git
    elif command_exists dnf; then
        sudo dnf install -y git
    elif command_exists pacman; then
        sudo pacman -S git
    else
        log_error "无法检测到包管理器，无法安装git。请手动安装git后再运行此脚本。"
        exit 1
    fi
    
    log_success "git已安装。"
}

# 安装Powerlevel10k
install_p10k() {
    log_info "开始安装Powerlevel10k..."
    
    # 克隆Powerlevel10k仓库
    if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
        mkdir -p "$HOME/.oh-my-zsh/custom/themes"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
        log_success "Powerlevel10k已克隆到~/.oh-my-zsh/custom/themes/powerlevel10k"
    fi
    
    # 检查Oh My Zsh是否安装
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_warn "未检测到Oh My Zsh，Powerlevel10k需要Oh My Zsh才能工作。"
        if confirm "是否现在安装Oh My Zsh?"; then
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            log_success "Oh My Zsh已安装。"
        else
            log_error "必须安装Oh My Zsh才能继续，脚本退出。"
            exit 1
        fi
    else
        log_success "Oh My Zsh已安装。"
    fi
    
    # 备份当前.zshrc
    if [ -f "$HOME/.zshrc" ]; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
        log_info "已备份.zshrc到~/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 配置.zshrc使用p10k主题
    echo "source ~/.oh-my-zsh/oh-my-zsh.sh" > "$HOME/.zshrc"
    echo "ZSH_THEME=\"powerlevel10k/powerlevel10k\"" >> "$HOME/.zshrc"
    echo "# 为Powerlevel10k添加配置" >> "$HOME/.zshrc"
    echo "test -f ~/.p10k.zsh && source ~/.p10k.zsh" >> "$HOME/.zshrc"
    
    log_success "已配置.zshrc使用Powerlevel10k主题。"
}

# 运行p10k配置向导
configure_p10k() {
    log_info "现在将运行Powerlevel10k配置向导，这将帮助你设置喜欢的外观..."
    log_info "配置向导将询问一系列问题，根据你的喜好选择即可。"
    
    if confirm "是否现在运行配置向导?"; then
        # 启动配置向导
        zsh -c "source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme; p10k configure"
        
        log_success "Powerlevel10k配置已完成。"
        log_info "为了使更改生效，需要重新加载Zsh配置或打开新终端。"
        log_info "你可以使用以下命令重新加载配置: source ~/.zshrc"
    else
        log_warn "已跳过配置向导，你可以随时运行 'p10k configure' 来配置Powerlevel10k。"
    fi
}

# 检查字体
check_fonts() {
    log_info "检查Powerlevel10k所需字体..."
    
    # 检查Nerd Fonts是否安装
    if [ ! -d "$HOME/.local/share/fonts" ]; then
        mkdir -p "$HOME/.local/share/fonts"
    fi
    
    # 检查常用的Nerd Fonts
    font_files=("PowerlineSymbols.otf" "DejaVuSansMono for Powerline.otf")
    missing_fonts=()
    
    for font in "${font_files[@]}"; do
        if [ ! -f "$HOME/.local/share/fonts/$font" ]; then
            missing_fonts+=("$font")
        fi
    done
    
    if [ ${#missing_fonts[@]} -gt 0 ]; then
        log_warn "检测到缺少以下Powerlevel10k所需字体: ${missing_fonts[*]}"
        if confirm "是否现在安装推荐的Nerd Fonts?"; then
            install_nerd_fonts
        else
            log_warn "跳过字体安装，可能会导致Powerlevel10k显示异常。"
            log_info "如果看到乱码，请安装Nerd Fonts: https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k"
        fi
    else
        log_success "所需字体已安装。"
    fi
}

# 安装Nerd Fonts
install_nerd_fonts() {
    log_info "开始安装Nerd Fonts..."
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 克隆Nerd Fonts仓库
    git clone https://github.com/ryanoasis/nerd-fonts.git
    cd nerd-fonts
    
    # 安装常用的Powerlevel10k推荐字体
    log_info "安装Meslo Nerd Font..."
    ./install.sh Meslo
    
    log_info "安装DejaVu Sans Mono Nerd Font..."
    ./install.sh DejaVuSansMono
    
    # 安装Powerline符号
    log_info "安装Powerline符号..."
    if [ ! -f "$HOME/.local/share/fonts/PowerlineSymbols.otf" ]; then
        curl -fLo "$HOME/.local/share/fonts/PowerlineSymbols.otf" https://raw.githubusercontent.com/powerline/powerline/master/font/PowerlineSymbols.otf
    fi
    if [ ! -f "$HOME/.local/share/fonts/DejaVuSansMono for Powerline.otf" ]; then
        curl -fLo "$HOME/.local/share/fonts/DejaVuSansMono for Powerline.otf" https://raw.githubusercontent.com/powerline/powerline/master/font/DejaVuSansMono%20for%20Powerline.otf
    fi
    
    # 刷新字体缓存
    if command_exists fc-cache; then
        fc-cache -f -v
        log_success "字体缓存已刷新。"
    else
        log_warn "无法刷新字体缓存，请手动重启终端或运行fc-cache命令。"
    fi
    
    cd -
    rm -rf "$temp_dir"
    
    log_success "Nerd Fonts已安装。请在终端设置中选择Nerd Fonts字体。"
    log_info "例如: Meslo LG M DZ for Powerlevel10k"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}       Powerlevel10k 配置脚本        ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo ""
    
    check_system
    install_p10k
    #check_fonts
    configure_p10k
    
    echo ""
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}    Powerlevel10k 配置已完成!    ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${BLUE}提示:${NC} 打开新终端或运行 'source ~/.zshrc' 查看效果"
    echo -e "${BLUE}提示:${NC} 如需重新配置，运行 'p10k configure'"
}

# 执行主函数
main