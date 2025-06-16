## `arch_backup.sh` 钩子 (Hooks) 指南

`arch_backup.sh` 提供了一个钩子机制，允许用户在备份流程的特定阶段执行自定义脚本，以扩展或修改备份行为。

### 1. 如何启用钩子

要启用钩子功能，您需要在 `arch_backup.sh` 的配置文件 (通常是 `/etc/arch_backup/arch_backup.conf` 或用户家目录下的 `~/.config/arch_backup.conf`) 中进行如下设置：

```ini
# arch_backup.conf
CONF_HOOKS_ENABLE="true"
CONF_HOOKS_BASE_DIR="/etc/arch_backup/hooks.d" # 默认路径，可自定义
```

*   `CONF_HOOKS_ENABLE`: 设置为 `"true"` 以启用钩子功能。
*   `CONF_HOOKS_BASE_DIR`: 指定存放钩子脚本的根目录。脚本会在此目录下查找对应事件的子目录。

### 2. 钩子脚本的存放位置和命名

钩子脚本需要放置在 `CONF_HOOKS_BASE_DIR` 下以**事件名称命名的子目录**中。

例如，如果 `CONF_HOOKS_BASE_DIR="/etc/arch_backup/hooks.d"`，那么：

*   在**整个备份流程开始前**执行的脚本，应放在：
    `/etc/arch_backup/hooks.d/pre-backup/`
*   在**整个备份流程成功结束后**执行的脚本，应放在：
    `/etc/arch_backup/hooks.d/post-backup-success/`
*   在**整个备份流程失败结束后**执行的脚本，应放在：
    `/etc/arch_backup/hooks.d/post-backup-failure/`
*   在**所有操作（包括备份、备份清理、日志清理）都完成后，无论成功与否都会执行**的脚本，应放在：
    `/etc/arch_backup/hooks.d/finalization/`
*   (如果实现了特定任务钩子) 在**`system_config`任务开始前**执行的脚本，应放在：
    `/etc/arch_backup/hooks.d/pre-task-system_config/`
*   (如果实现了特定任务钩子) 在**`user_data`任务成功结束后**执行的脚本，应放在：
    `/etc/arch_backup/hooks.d/post-task-user_data-success/`

**重要要求：**

*   钩子脚本文件必须具有**可执行权限** (`chmod +x your_script.sh`)。
*   脚本应该有正确的 Shebang，例如 `#!/bin/bash` 或 `#!/usr/bin/env bash`。
*   如果一个事件子目录下有多个钩子脚本，它们将按照**文件名的字母数字顺序**执行。建议使用数字前缀来控制执行顺序，例如 `01_first_script.sh`, `02_second_script.sh`。

### 3. 传递给钩子脚本的上下文信息

当 `arch_backup.sh` 执行钩子脚本时，它会通过**环境变量**和**命令行参数**向钩子脚本传递一些有用的上下文信息。

**A. 环境变量 (由 `_run_hooks` 函数导出)：**

钩子脚本可以直接访问以下环境变量：

*   `HOOK_EVENT_NAME`: (字符串) 当前触发的钩子事件的名称。
    *   例如："pre-backup", "post-backup-success", "finalization", "pre-task-system_config", "post-task-user_data-success"。
*   `HOOK_CURRENT_TIMESTAMP`: (字符串) 本次备份操作的全局统一时间戳 (格式 `YYYYMMDD_HHMMSS`)。
    *   可用于钩子脚本生成与本次备份相关联的文件或日志。
    *   注意：对于非常早期的 `pre-backup` 钩子，如果此时主脚本的 `CURRENT_TIMESTAMP` （即 `GLOBAL_RUN_TIMESTAMP`）还未被 `run_backup` 正式使用来创建快照目录，此变量可能指向的是即将创建的快照的时间戳。
*   `HOOK_BACKUP_SNAPSHOT_DIR`: (字符串) 未压缩备份快照的根目录路径 (例如 `/mnt/backups/snapshots`)。
*   `HOOK_CURRENT_SNAPSHOT_PATH`: (字符串) 本次备份操作创建（或将要创建）的未压缩快照的完整路径 (例如 `/mnt/backups/snapshots/YYYYMMDD_HHMMSS`)。
    *   对于 `pre-backup` 钩子，这个目录可能尚未创建或为空。
    *   对于 `post-backup-*` 和 `finalization` 钩子，这个目录应该已经存在并包含备份数据（如果备份成功）。
*   `HOOK_MAIN_LOG_FILE`: (字符串) `arch_backup.sh` 本次运行的主要日志文件的完整路径。钩子脚本可以向此文件追加自己的日志信息。
*   `HOOK_OVERALL_BACKUP_STATUS`: (字符串, 仅用于 "finalization" 或类似的最终钩子) 主备份流程的整体状态。
    *   可能的值："success", "failure"。
*   `HOOK_MAIN_BACKUP_EXIT_CODE`: (数字, 仅用于 "finalization" 或类似的最终钩子) 主备份流程 (`run_backup` 函数) 的退出码。
    *   `0` 表示成功，非 `0` 表示失败。

**B. 命令行参数 (由 `_run_hooks` 函数调用时传递)：**

`_run_hooks` 函数会将其接收到的除第一个参数（事件名）之外的所有额外参数原样传递给每个钩子脚本。

*   **对于全局钩子 (例如 `pre-backup`, `post-backup-success`, `post-backup-failure`, `finalization`)**:
    *   `$1`: 通常是本次备份的统一时间戳 (`GLOBAL_RUN_TIMESTAMP` / `CURRENT_TIMESTAMP`)。
    *   `$2` (对于 `post-backup-failure` 和 `finalization`): 可能是主备份流程的退出码。
    *   钩子脚本内部可以通过 `$1`, `$2` 等来访问这些参数。

*   **对于特定任务的钩子 (例如 `pre-task-system_config`, `post-task-user_data-success`)**:
    *   `$1`: 通常是本次备份的统一时间戳。
    *   `$2` (对于 `post-task-*-*`): 可能是该特定任务的退出码。
    *   钩子脚本的编写者需要知道调用该特定事件钩子时传递了哪些参数。

**建议钩子脚本开头获取参数和环境变量：**

```bash
#!/bin/bash

# 事件名 (来自环境变量)
event_name="${HOOK_EVENT_NAME:-unknown_event}"
# 本次备份的时间戳 (来自环境变量，或作为第一个参数)
backup_timestamp="${HOOK_CURRENT_TIMESTAMP:-$1}"
# 主备份脚本的日志文件 (来自环境变量)
main_log_file="${HOOK_MAIN_LOG_FILE:-/dev/null}" # 回退到 /dev/null 如果未设置

# 示例：获取特定钩子传递的额外参数
task_exit_code="${2:-}" # 如果这是个 post-task 或 post-backup-failure/finalization 钩子

# 简单的日志函数，追加到主备份日志
hook_log() {
    echo "[HOOK $(date '+%T')] [$event_name/$(basename "$0")] $1" >> "$main_log_file"
}

hook_log "INFO - Script started. Backup Timestamp: $backup_timestamp"
if [[ -n "$task_exit_code" ]]; then
    hook_log "INFO - Received task/main exit code: $task_exit_code"
fi

# --- 您的钩子脚本逻辑开始 ---

# if [[ "$event_name" == "post-backup-success" ]]; then  这是一个条件判断，确保这段逻辑只在当前钩子脚本是因为 finalization 事件被调用时才执行。
# 这允许同一个钩子脚本文件（如果被软链接到多个事件子目录，虽然不常见）或一个包含多种事件处理逻辑的复杂钩子脚本，能够根据当前是什么事件来执行不同的代码块。
# 例如，对于 "post-backup-success" 事件：
if [[ "$event_name" == "post-backup-success" ]]; then  
    hook_log "INFO - Main backup was successful. Performing post-success actions..."
    # 在这里执行您的 rclone 日志清理或其他操作
    # 您可以使用 $HOOK_CURRENT_SNAPSHOT_PATH 来访问本次备份的快照数据
fi


# 这个条件判断检查主备份流程 (arch_backup.sh 的 run_backup 函数以及相关的清理）是否成功完成
# HOOK_OVERALL_BACKUP_STATUS 是一个由 arch_backup.sh（在调用 finalization 钩子之前）导出的环境变量，其值为 "success" 或 "failure"。
# 例如，对于 "finalization" 事件，检查备份是否成功：
if [[ "$event_name" == "finalization" ]]; then
    if [[ "${HOOK_OVERALL_BACKUP_STATUS:-failure}" == "success" ]]; then #HOOK_OVERALL_BACKUP_STATUS由主脚本export而来
        hook_log "INFO - Overall backup process was successful."
        # 执行只有在整体成功时才做的清理
        # /path/to/cleanup_rclone_cron_log.sh # 调用您的 cron 日志清理脚本
    else
        hook_log "WARN - Overall backup process reported a failure (exit code: ${HOOK_MAIN_BACKUP_EXIT_CODE:-?})."
        # 可能执行不同的操作，或不执行清理
    fi
fi


# --- 您的钩子脚本逻辑结束 ---

hook_log "INFO - Script finished."
exit 0 # 除非发生严重错误，否则钩子脚本应以0退出，避免不必要地标记主流程失败
```

### 4. 钩子脚本的执行和错误处理

*   **执行**：`_run_hooks` 函数会查找指定事件子目录下的所有可执行文件，并按文件名（通常是字母数字顺序，因此 `01_`, `02_` 等前缀有效）依次执行它们。
*   **错误处理**：
    *   默认情况下，如果一个钩子脚本以非零状态退出，`_run_hooks` 函数会记录一个警告，并将 `overall_hook_status` 标记为1。
    *   **通常，单个钩子脚本的失败不应导致整个备份流程中止**，除非该钩子是关键的预处理步骤（例如，`pre-backup` 钩子）。
    *   `arch_backup.sh` 的 `main()` 函数中，对于 `pre-backup` 钩子的失败，目前是设计为直接退出主脚本。对于其他钩子点的失败，通常只记录警告。您可以根据需要调整此行为。
    *   钩子脚本自身应该做好错误处理，并决定在什么情况下返回非零退出码。

### 5. 示例用例

*   **`pre-backup`**:
    *   停止需要静默的数据库服务 (`systemctl stop mysqld`)。
    *   使用 `pg_dump` 或 `mysqldump` 创建数据库的逻辑备份文件，并将其放置到会被 `arch_backup.sh` 备份的自定义路径中。
    *   挂载外部备份驱动器。
    *   创建 LVM 快照。
*   **`post-backup-success`**:
    *   重启之前停止的服务。
    *   发送备份成功的邮件通知。
    *   触发一个远程同步脚本（例如，将本地备份快照 `rclone sync` 到云存储）。
*   **`post-backup-failure`**:
    *   发送备份失败的警报邮件。
    *   尝试回滚 LVM 快照（如果之前创建了）。
*   **`finalization`**:
    *   **清理 `cron` 执行 `arch_backup.sh` 时产生的外部日志文件 (您的需求)。**
    *   执行最终的校验和或摘要生成。
    *   卸载备份驱动器。
    *   发送包含完整备份状态（包括所有钩子执行情况）的最终报告。

### 6. 预设钩子脚本的部署

如果您的 `archlinux-post-install-scripts` 项目中的 `01_setup_auto_backup.sh` 脚本负责部署 `arch_backup.sh`，它也应该：
1.  创建 `CONF_HOOKS_BASE_DIR` 定义的钩子根目录。
2.  创建一些常见的事件子目录（如 `pre-backup`, `post-backup-success`, `finalization`）。
3.  可选地，它可以将一些项目提供的、通用的、有用的示例钩子脚本（例如您之前提到的 `99_cleanup_cron_exec_log.sh`）自动复制到相应的事件子目录中，并设置执行权限。部署时应检查同名文件是否存在，并提示用户是否覆盖（最好先备份旧的）。

---

这份指南应该能帮助用户理解如何为您增强后的 `arch_backup.sh` 编写和使用钩子脚本。您可以根据您最终实现的钩子事件名称和传递的上下文信息来调整这份文档。