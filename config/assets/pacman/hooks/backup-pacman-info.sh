#!/bin/bash

# --- 配置 ---
# 备份目标目录 (请确保此目录存在且 pacman (root) 有写入权限)
BACKUP_DIR="/mnt/arch_backups/hook_pacman_history"
# 日志文件 (记录此脚本的执行情况，可选)
LOG_FILE="/var/log/arch_backups_logs/hook_backup_pacman_info_logs/backup-pacman-info.log"
# --- End 配置 ---

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 记录日志开始
echo "-----------------------------------------" >> "$LOG_FILE"
echo "Starting pacman info backup at $(date)" >> "$LOG_FILE"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Could not create backup directory $BACKUP_DIR" >> "$LOG_FILE"
    exit 1 # 退出，指示错误
fi
echo "Backup directory: $BACKUP_DIR" >> "$LOG_FILE"

# 1. 备份显式安装的软件包列表 (原生包)
PKG_LIST_NATIVE_FILE="${BACKUP_DIR}/pkglist_native.${TIMESTAMP}.txt"
echo "Backing up native explicitly installed package list to $PKG_LIST_NATIVE_FILE" >> "$LOG_FILE"
if pacman -Qqe > "$PKG_LIST_NATIVE_FILE"; then
    echo "Native explicit package list backup successful." >> "$LOG_FILE"
else
    echo "Error: Failed to back up native explicit package list." >> "$LOG_FILE"
fi

# 2. 备份显式安装的软件包列表 (AUR/非官方源包, 可选)
PKG_LIST_FOREIGN_FILE="${BACKUP_DIR}/pkglist_foreign.${TIMESTAMP}.txt"
echo "Backing up foreign explicitly installed package list to $PKG_LIST_FOREIGN_FILE" >> "$LOG_FILE"
if pacman -Qqm > "$PKG_LIST_FOREIGN_FILE"; then
     echo "Foreign explicit package list backup successful (might be empty)." >> "$LOG_FILE"
else
    echo "Error: Failed to back up foreign explicit package list." >> "$LOG_FILE"
fi

# 3. 备份所有已安装的软件包及其版本 <--- 新增部分 ---
PKG_LIST_ALL_FILE="${BACKUP_DIR}/pkglist_all_versions.${TIMESTAMP}.txt"
echo "Backing up ALL installed packages with versions to $PKG_LIST_ALL_FILE" >> "$LOG_FILE"
if pacman -Q > "$PKG_LIST_ALL_FILE"; then
    echo "All packages with versions list backup successful." >> "$LOG_FILE"
else
    echo "Error: Failed to back up all packages with versions list." >> "$LOG_FILE"
fi
# --- 结束新增部分 ---

# 4. 备份 pacman 日志
PACMAN_LOG_SRC="/var/log/pacman.log"
PACMAN_LOG_DEST="${BACKUP_DIR}/pacman.${TIMESTAMP}.log"
echo "Backing up pacman log to $PACMAN_LOG_DEST" >> "$LOG_FILE"
if cp "$PACMAN_LOG_SRC" "$PACMAN_LOG_DEST"; then
    echo "Pacman log backup successful." >> "$LOG_FILE"
else
    echo "Error: Failed to back up pacman log." >> "$LOG_FILE"
fi

echo "Pacman info backup finished at $(date)" >> "$LOG_FILE"
echo "-----------------------------------------" >> "$LOG_FILE"

# 务必确保脚本成功退出，除非真的发生了严重错误
exit 0
