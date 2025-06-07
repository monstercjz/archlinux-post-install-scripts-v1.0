# `config/lib/utils.sh` - 核心通用函数库

## 概述

`utils.sh` 是 `archlinux-post-install-scripts` 项目的核心通用函数库。它旨在提供项目运行所需的基础功能，确保脚本的健壮性、可维护性和高代码复用性。此文件被项目中的所有主要脚本 `source` 引入，为它们提供统一的环境和工具集。

## 文件信息

*   **文件**: `config/lib/utils.sh`
*   **版本**: 1.3.1 (日志核心逻辑更新为增强型基于索引，跳过工具函数)
*   **日期**: 2025-06-07
*   **描述**: 核心通用函数库。提供项目运行所需的基础功能，包括依赖加载、日志记录、权限检查、用户交互、文件操作等。

## 核心功能

`utils.sh` 封装了以下关键功能：

1.  **统一项目环境初始化 (`_initialize_project_environment`)**:
    *   确保 `utils.sh` 不被重复加载。
    *   在脚本早期执行强制性的 `root` 权限检查。
    *   动态确定项目的根目录 (`BASE_DIR`)。
    *   加载主配置文件 (`main_config.sh`)。
    *   识别调用 `sudo` 的原始用户 (`ORIGINAL_USER`) 及其家目录 (`ORIGINAL_HOME`)，此过程已进行安全性优化，避免 `eval`。
    *   确保日志根目录存在并对原始用户有写入权限。
    *   初始化统一的日志系统。

2.  **统一的日志系统**:
    *   **多级别支持**: 提供 `log_info` (信息)、`log_warn` (警告)、`log_error` (错误) 和 `log_debug` (调试) 四种日志级别。
    *   **终端彩色输出**: 日志信息在终端以不同颜色显示，可根据 `main_config.sh` 中的 `ENABLE_COLORS` 配置启用或禁用。
    *   **独立日志文件**: 每个脚本实例运行时都会生成一个独立的纯文本日志文件 (`/var/log/archlinux_post_install_setup/script_name-YYYYMMDD_HHMMSS.log`)。
    *   **文件所有权**: 尝试将生成的日志文件所有权调整为原始 `sudo` 调用用户 (`ORIGINAL_USER`)，便于非 `root` 用户查看日志。
    *   **精确日志源识别**: 这是该日志系统的亮点。它能够智能地识别并报告日志消息的**原始业务逻辑调用源**（即哪个脚本或哪个函数发出了日志），而不是内部的日志包装函数或辅助工具函数，极大地提升了日志的可读性和调试效率。

3.  **权限管理**:
    *   `_initial_check_root_and_exit`: 强制检查脚本是否以 `root` 权限运行，若否，则提示并退出。
    *   `_ensure_log_dir_user_owned`: 确保日志目录存在并具有正确权限，优先使用 `setfacl` 进行精细控制，并提供 `chmod`/`chown` 回退方案。

## 接口函数 (对外暴露)

`utils.sh` 通过 `source` 机制向项目中的其他脚本提供了以下接口函数，供其直接调用以实现特定功能。

### 1. 项目初始化

*   **`_initialize_project_environment <caller_script_path>`**
    *   **功能**: 这是所有入口脚本（如 `run_setup.sh`）调用的统一初始化函数。它执行所有必要的启动设置，包括权限检查、目录确定、配置加载、用户上下文获取和日志系统初始化。
    *   **参数**: `<caller_script_path>` - 传入调用此函数的脚本的完整路径，通常使用 `"${BASH_SOURCE[0]}"`。
    *   **效果**: 确保项目环境正确建立，所有全局变量（如 `BASE_DIR`, `ORIGINAL_USER` 等）被初始化，并启动日志系统。

### 2. 日志记录

所有日志函数都会自动通过 `_log_message_core` 进行格式化，并智能识别调用源。

*   **`log_info <message>`**
    *   **功能**: 记录一条信息级别（INFO）的日志消息。用于记录正常的操作流程和状态更新。
    *   **参数**: `<message>` - 要记录的字符串消息。
    *   **效果**: 日志以绿色（如果启用颜色）打印到终端，并写入到当前脚本的日志文件。
    *   **示例**: `log_info "Configuration loaded successfully."`
    *   **日志示例**: `[YYYY-MM-DD HH:MM:SS] [INFO] [my_script.sh] Configuration loaded successfully.`

*   **`log_warn <message>`**
    *   **功能**: 记录一条警告级别（WARN）的日志消息。用于提示潜在的问题或非致命的错误。
    *   **参数**: `<message>` - 要记录的字符串消息。
    *   **效果**: 日志以黄色（如果启用颜色）打印到终端的**标准错误流**，并写入到日志文件。
    *   **示例**: `log_warn "Optional package 'xyz' not found."`
    *   **日志示例**: `[YYYY-MM-DD HH:MM:SS] [WARN] [install_packages.sh] Optional package 'xyz' not found.`

*   **`log_error <message>`**
    *   **功能**: 记录一条错误级别（ERROR）的日志消息。用于记录导致操作失败或需要立即关注的问题。
    *   **参数**: `<message>` - 要记录的字符串消息。
    *   **效果**: 日志以红色（如果启用颜色）打印到终端的**标准错误流**，并写入到日志文件。
    *   **示例**: `log_error "Failed to create directory '/opt/app'."`
    *   **日志示例**: `[YYYY-MM-DD HH:MM:SS] [ERROR] [setup_dirs_function] Failed to create directory '/opt/app'.`

*   **`log_debug <message>`**
    *   **功能**: 记录一条调试级别（DEBUG）的日志消息。仅在 `main_config.sh` 中的 `DEBUG_MODE` 设置为 `true` 时才输出。用于开发和问题排查。
    *   **参数**: `<message>` - 要记录的字符串消息。
    *   **效果**: 日志以蓝色（如果启用颜色）打印到终端，并写入到日志文件（仅在调试模式下）。
    *   **示例**: `log_debug "Variable 'MY_VAR' is set to: $MY_VAR"`
    *   **日志示例**: `[YYYY-MM-DD HH:MM:SS] [DEBUG] [some_utility_function] Variable 'MY_VAR' is set to: value.`

### 3. 权限检查

*   **`check_root_privileges`**
    *   **功能**: 检查当前脚本是否以 `root` 权限运行。
    *   **参数**: 无。
    *   **效果**: 返回状态码。
        *   `0` (成功): 表示当前用户是 `root`。
        *   `1` (失败): 表示当前用户不是 `root`。
    *   **注意**: 此函数只进行检查并返回状态码，不直接输出错误或退出。调用者需根据其返回值自行处理。
    *   **示例**:
        ```bash
        if ! check_root_privileges; then
            log_error "Insufficient privileges. This operation requires root access."
            exit 1
        fi
        ```

### 4. 通用辅助

*   **`display_header_section <title>`**
    *   **功能**: 在终端和日志中打印一个格式化的标题或部分分隔符，用于提高日志和终端输出的可读性。
    *   **参数**: `<title>` - 要显示的标题文本。
    *   **效果**: 在终端和日志中显示带有 `=====` 包裹的标题。日志源将智能地追溯到调用 `display_header_section` 的原始业务逻辑代码。
    *   **示例**: `display_header_section "System Update and Clean"`
    *   **日志示例**:
        ```
        [YYYY-MM-DD HH:MM:SS] [INFO] [main_script.sh] ==================================================
        [YYYY-MM-DD HH:MM:SS] [INFO] [main_script.sh] >>> System Update and Clean
        [YYYY-MM-DD HH:MM:SS] [INFO] [main_script.sh] ==================================================
        ```

## 许可证

本项目使用 MIT 许可证。详见 `LICENSE` 文件 (如果项目包含)。

---