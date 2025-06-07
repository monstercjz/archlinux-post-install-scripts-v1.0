# Arch Linux 后安装脚本

这是一个模块化的 Arch Linux 后安装脚本项目，旨在简化和自动化 Arch Linux 安装后的配置和软件安装过程。

## 项目结构

```
archlinux-post-install-scripts-v1.0/
├── README.md
├── .gitignore
├── run_setup.sh
└── config/
    ├── main_config.sh
    ├── lib/
    │   └── utils.sh
    ├── assets/
    │   ├── pacman/
    │   │   └── hooks/
    │   │       ├── backup-manual_install_package-info.sh
    │   │       ├── backup-manual_install_package.hook
    │   │       ├── backup-pacman-info.sh
    │   │       └── backup-pkglist-log.hook
    │   ├── network/
    │   │   └── systemd-networkd-example.conf
    │   ├── shell/
    │   │   └── zshrc_snippet.txt
    │   └── dotfiles/
    ├── modules/
    │   ├── 01_system_base/
    │   │   ├── 00_system_base_menu.sh
    │   │   ├── 01_configure_mirrors.sh
    │   │   └── 02_setup_network.sh
    │   ├── 02_package_management/
    │   │   ├── 00_package_management_menu.sh
    │   │   ├── 01_install_aur_helper.sh
    │   │   └── 02_setup_pacman_hooks.sh
    │   ├── 03_user_environment/
    │   │   ├── 00_user_environment_menu.sh
    │   │   ├── 01_configure_shell.sh
    │   │   ├── 02_setup_dotfiles.sh
    │   │   └── 03_configure_nano.sh
    │   ├── 04_software_installation/
    │   │   ├── 00_software_installation_menu.sh
    │   │   ├── 01_install_essential_software.sh
    │   │   ├── 02_install_common_software.sh
    │   │   └── 03_install_specific_apps.sh
    │   └── 00_cleanup_and_finish.sh
    └── main_menu.sh
```
## 特点
1.  **入口多样化：** 可以从run_setup.sh开始，也可以从main_menu.sh开始,也可以从2级菜单开始，甚至从最基本的功能模块开始。
2.  **日志信息详尽：** 控制台带色彩输出，日志文件纯文字记录，输出信息中保留日志调用者信息，每个sh都有对应的日志文件。
3.  **功能模块化：** 各功能模块独立。
4.  **可扩展性：** 可以根据需要添加新的功能模块，或者修改现有的功能模块。
5.  **可维护性：** 代码结构清晰，函数命名符合规范，注释详细。
6.  **稳定性：** 代码健壮，符合最佳实践规范。
7.  **版本记录：** 顶部注释详细记录版本更新。
8.  **目录结构清晰：** 模块划分清晰，职能单一，功能模块之间减少依赖关系。
## 使用指南

1.  **克隆仓库：**
    ```bash
    git clone https://github.com/your-username/archlinux-post-install-scripts-v1.0.git
    cd archlinux-post-install-scripts-v1.0
    ```
2.  **运行设置脚本：**
    ```bash
    ./run_setup.sh
    ```
    此脚本将检查权限并引导您进入主菜单。

## 自定义

*   **全局配置：** 修改 `config/main_config.sh` 来调整全局变量，例如日志路径、默认 AUR 助手等。
*   **模块化功能：** 在 `config/modules/` 目录下，您可以根据需要添加、修改或删除模块脚本。每个模块都设计为独立且原子化。
*   **静态资产：** `config/assets/` 目录用于存放模块所需的静态文件、模板或配置文件片段。

## 前置条件

*   一个已安装的 Arch Linux 系统。
*   基本的网络连接。
*   `sudo` 权限。

## 贡献

欢迎贡献！如果您有任何改进建议或新功能，请随时提交 Pull Request。