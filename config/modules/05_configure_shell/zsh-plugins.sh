#!/bin/bash

# 脚本选项：
# -e: 如果命令以非零状态退出，则立即退出。
# -o pipefail: 如果管道中的任何命令失败，则整个管道的退出状态为非零。
# set -e
# set -o pipefail

# --- 定义脚本目录和模块路径 ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
MODULES_DIR="$SCRIPT_DIR/modules"


# --- 加载模块 ---
# 依赖于调用脚本已 source 项目核心的 environment_setup.sh 和 utils.sh
# 因此，项目通用的日志函数、命令执行函数以及 ORIGINAL_USER, ORIGINAL_HOME 等变量已可用。

log_info "用户家目录确定为: $ORIGINAL_HOME (用户: $ORIGINAL_USER)"

# 加载其他模块
MODULES=("check.sh" "install.sh" "fonts.sh" "config.sh" "post_install.sh")
log_info "开始加载模块..."
for module in "${MODULES[@]}"; do
    MODULE_PATH="$MODULES_DIR/$module"
    log_info "尝试加载模块: $module ($MODULE_PATH)"
    if [ ! -f "$MODULE_PATH" ]; then
        log_error "模块 $module 未找到！路径: $MODULE_PATH"
        exit 1
    fi
    # shellcheck source=/dev/null
    if source "$MODULE_PATH"; then
        log_info "模块 $module 加载成功。"
    else
        # 即使 set -e 被注释，source 失败也可能返回非零状态
        log_error "加载模块 $module 时发生错误！脚本可能无法正常运行。"
        # 可以选择在这里退出 exit 1，或者继续尝试加载其他模块
    fi
done
log_info "所有模块尝试加载完毕。"

# --- 主函数 ---
main() {
    # 全局步骤计数器在 utils.sh 中初始化和管理
    # export GLOBAL_STEP_COUNTER=0 # 在 utils.sh 中完成

    log_notice "欢迎使用 Zsh 及插件增强安装脚本"
    echo "========================================"
    echo "本脚本将尝试安装和配置以下组件:"
    echo "  - Zsh (Shell)"
    echo "  - Oh My Zsh (Zsh 配置框架)"
    echo "  - fzf (命令行模糊查找器)"
    echo "  - bat (带语法高亮的 cat 替代品)"
    echo "  - eza (现代化的 ls 替代品)"
    echo "  - zsh-syntax-highlighting (命令语法高亮插件)"
    echo "  - zsh-autosuggestions (命令历史建议插件)"
    echo "  - fzf-tab (使用 fzf 的 Tab 补全插件)"
    echo "  - Powerlevel10k (强大的 Zsh 主题)"
    echo "  - MesloLGS NF (Powerlevel10k 推荐字体)"
    echo "========================================"
    echo ""

    # 捕获中断信号 (使用项目统一的日志函数)
    # trap 'log_error "脚本被用户中断。"; exit 1' SIGINT SIGTERM # 移除 trap，依赖 set -euo pipefail

    # 1. 运行检查和依赖项处理 (check.sh)
    # log STEP 调用将自动处理步骤计数
    # run_checks 会进行检查、用户交互并导出必要的环境变量
    if ! run_checks; then
         # run_checks 内部应该已经处理了用户取消或依赖问题的退出逻辑
         # 如果它返回非零，通常意味着用户选择忽略依赖问题继续
         log_warn "检查阶段未完全成功，但用户选择继续。"
    fi

    # 检查 check.sh 是否设置了跳过安装的标志
    if [[ "$SKIP_INSTALLATION" == "true" ]]; then
        log_info "根据用户选择，跳过安装步骤。"
    else
        # 2. 运行安装 (install.sh)
        # log STEP 调用将自动处理步骤计数
        # run_installation 使用由 run_checks 导出的环境变量
        if ! run_installation; then
            log_error "安装过程中发生错误。请检查日志。"
            # 即使安装失败，也尝试进行配置和验证，因为部分可能已安装
            # exit 1 # 或者选择在这里退出
        fi
    fi

    # 3. 运行配置 (config.sh)
    # log STEP 调用将自动处理步骤计数
    # run_configuration 使用由 run_checks 导出的环境变量 (主要是 CHECK_RESULTS_EXPORT)
    if ! run_configuration; then
        log_error "配置过程中发生错误。请检查日志。"
        # 配置失败也继续进行最终检查和指导
    fi

    # 4. 运行安装后检查和提供指导 (post_install.sh)
    # log STEP 调用将自动处理步骤计数
    if ! run_post_install_checks; then
         log_warn "安装后验证发现一些问题。"
    fi

    # 完成所有步骤后，记录完成信息
    log_info "脚本主要流程执行完毕！"
    echo "========================================"
    echo "请仔细阅读上面的 '后续步骤和建议' 部分以完成最终设置。"
    echo "如果您遇到任何问题，请检查脚本输出的日志信息。"
    echo "========================================"

    # 提示用户切换到 Zsh (如果当前不是 Zsh)
    if [ -n "$SHELL" ] && [ ! "$(basename "$SHELL")" == "zsh" ]; then
        if command_exists zsh; then
            log_info "您的默认 Shell 不是 Zsh。"
            if prompt_confirm "是否现在尝试将 Zsh 设置为默认 Shell (需要 sudo 权限)？"; then
                 if command_exists chsh; then
                     log_info "尝试使用 'chsh -s $(command -v zsh)' 为用户 '$ORIGINAL_USER' 更改默认 Shell..."
                     # 使用原始用户名执行 chsh
                     if run_sudo_command chsh -s "$(command -v zsh)" "$ORIGINAL_USER"; then
                         log_info "用户 '$ORIGINAL_USER' 的默认 Shell 已更改为 Zsh。用户 '$ORIGINAL_USER' 需要重新登录才能生效。"
                     else
                         log_error "为用户 '$ORIGINAL_USER' 更改默认 Shell 失败。请尝试手动运行 'sudo chsh -s $(command -v zsh) $ORIGINAL_USER'。"
                     fi
                 else
                     log_warn "未找到 'chsh' 命令，无法自动更改默认 Shell。"
                     log_info "请参考您的系统文档手动更改默认 Shell 为: $(command -v zsh)"
                 fi
            else
                 log_info "您可以稍后手动更改默认 Shell。"
                 log_info "Zsh 的路径是: $(command -v zsh)"
            fi
        fi
    fi

}

# --- 执行主函数 ---
main "$@"

exit 0
