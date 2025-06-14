#!/usr/bin/env bash

# arch_backup.sh - 高级 Arch Linux 系统备份脚本
# 版本: 1.0.0_zh
# 作者: Your Name/AI (中文版由AI辅助)
# 许可证: MIT

# 严格模式
set -euo pipefail
IFS=$'\n\t'

# === 脚本信息 ===
SCRIPT_VERSION="1.0.0_zh"
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# === 全局变量 (默认值, 会被配置文件覆盖) ===
CONF_BACKUP_ROOT_DIR=""                     # 备份根目录
CONF_LOG_FILE="/tmp/${SCRIPT_NAME}.log"     # 日志文件路径
CONF_LOG_LEVEL="INFO"                       # 日志级别: DEBUG, INFO, WARN, ERROR

CONF_BACKUP_SYSTEM_CONFIG="true"            # 是否备份系统配置
CONF_BACKUP_USER_DATA="true"                # 是否备份用户数据
CONF_BACKUP_PACKAGES="true"                 # 是否备份软件包列表
CONF_BACKUP_LOGS="true"                     # 是否备份系统日志
CONF_BACKUP_CUSTOM_PATHS="true"             # 是否备份自定义路径

CONF_USER_HOME_INCLUDE=(".config" ".local/share" ".ssh" ".gnupg" ".bashrc") # 用户家目录包含项
CONF_USER_HOME_EXCLUDE=("*/.cache/*" "*/Cache/*")                           # 用户家目录排除项

CONF_CUSTOM_PATHS_INCLUDE=()                # 自定义路径包含项
CONF_CUSTOM_PATHS_EXCLUDE=()                # 自定义路径排除项

CONF_SYSTEM_LOG_FILES=("pacman.log" "Xorg.0.log") # 系统日志文件列表
CONF_BACKUP_JOURNALCTL="true"               # 是否备份 journalctl 输出
CONF_JOURNALCTL_ARGS=""                     # journalctl 参数

CONF_INCREMENTAL_BACKUP="true"              # 是否启用增量备份
CONF_COMPRESSION_ENABLE="true"              # 是否启用压缩
CONF_COMPRESSION_METHOD="xz"                # 压缩方法
CONF_COMPRESSION_LEVEL="6"                  # 压缩级别
CONF_COMPRESSION_EXT="tar.xz"               # 压缩文件扩展名

CONF_RETENTION_UNCOMPRESSED_COUNT="3"       # 保留未压缩快照数量
CONF_RETENTION_COMPRESSED_COUNT="10"        # 保留压缩归档数量
CONF_RETENTION_COMPRESSED_DAYS="90"         # 压缩归档保留天数

CONF_PARALLEL_JOBS="1"                      # 并行任务数
CONF_PROMPT_FOR_CONFIRMATION="true"         # 是否进行风险操作确认
CONF_MIN_FREE_DISK_SPACE_PERCENT="10"       # 最小剩余磁盘空间百分比

# 运行时变量
CURRENT_TIMESTAMP=""                        # 当前时间戳
BACKUP_TARGET_DIR_UNCOMPRESSED=""           # 当前未压缩备份目标完整路径
BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES=""    # 压缩归档存放目录
EFFECTIVE_UID=$(id -u)                      # 当前脚本执行的有效UID
EFFECTIVE_USER=$(id -un)                    # 当前脚本执行的有效用户名
ORIGINAL_USER="${SUDO_USER:-$USER}"         # 通过 sudo 执行时的原始用户 (或当前用户)
ORIGINAL_UID="${SUDO_UID:-$UID}"            # 通过 sudo 执行时的原始UID (或当前UID)
ORIGINAL_GID="${SUDO_GID:-$GID}"            # 通过 sudo 执行时的原始GID (或当前GID)
ORIGINAL_HOME=""                            # 原始用户的家目录

# 并行执行命令
PARALLEL_CMD=""

# 日志级别定义
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
declare -A LOG_LEVEL_NAMES=([0]="DEBUG" [1]="INFO" [2]="WARN" [3]="ERROR") # 日志级别名称映射 (保持英文关键字)
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO} # 默认日志级别, 会被配置覆盖

# 终端输出颜色
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

# === 辅助函数 ===

# 日志记录函数
# 用法: log_msg INFO "这是一条信息"
#       log_msg ERROR "这是一条错误"
log_msg() {
    local level_name="$1" # 日志级别名称 (DEBUG, INFO, WARN, ERROR)
    local message="$2"    # 日志消息
    local level_num

    case "$level_name" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO  ;;
        WARN)  level_num=$LOG_LEVEL_WARN  ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *)     level_num=$LOG_LEVEL_INFO; message="[无效日志级别] $message" ;;
    esac

    if [[ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]]; then
        local color="$COLOR_RESET"
        [[ "$level_name" == "ERROR" ]] && color="$COLOR_RED"
        [[ "$level_name" == "WARN" ]]  && color="$COLOR_YELLOW"
        [[ "$level_name" == "INFO" ]]  && color="$COLOR_GREEN"
        [[ "$level_name" == "DEBUG" ]] && color="$COLOR_CYAN"

        # 终端输出 (同时追加到日志文件)
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${color}${level_name}${COLOR_RESET}] $message" | tee -a "$CONF_LOG_FILE"
    else
        # 即使当前日志级别较高 (例如 INFO), DEBUG 信息仍然可以仅写入文件 (如果需要)
        # 为简化，目前统一处理，若要更细致控制，可扩展此部分。
        :
    fi
}

# 用户确认提示函数
# 用法: confirm_action "确定要删除旧备份吗?" && echo "正在删除..."
confirm_action() {
    local prompt_message="$1"
    if [[ "$CONF_PROMPT_FOR_CONFIRMATION" != "true" ]]; then
        log_msg INFO "由于CONF_PROMPT_FOR_CONFIRMATION=false，自动确认操作: $prompt_message"
        return 0 # 返回 true (是)
    fi

    while true; do
        # 使用英文提示符 y/N，因为这是跨文化常见的
        read -r -p "$prompt_message [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;; # True
            [nN][oO]|[nN]|"") return 1 ;; # False
            *) echo "请输入 yes (y) 或 no (n)。" ;;
        esac
    done
}

# 检查必要的依赖工具
# 用法: check_dependencies rsync tar gzip xz
check_dependencies() {
    local missing_deps=0
    for dep in "$@"; do
        if ! command -v "$dep" &>/dev/null; then
            log_msg ERROR "必需的依赖工具 '$dep' 未安装。"
            missing_deps=1
        else
            # 可选: 版本检查 (较复杂, 仅在关键时添加)
            # local version=$(rsync --version | head -n1)
            # log_msg DEBUG "'$dep' 已找到。版本: $version"
            :
        fi
    done
    if [[ "$missing_deps" -eq 1 ]]; then
        log_msg ERROR "请安装缺失的依赖项后重试。"
        log_msg INFO "在 Arch Linux 上, 通常可以使用以下命令安装: sudo pacman -S <软件包名称>"
        exit 1
    fi
    log_msg DEBUG "所有核心依赖项均已存在: $@"
}

# 获取原始用户的家目录
get_original_user_home() {
    if [[ -n "$SUDO_USER" ]]; then # 如果通过 sudo 执行
        ORIGINAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else # 否则使用当前用户的 HOME
        ORIGINAL_HOME="$HOME"
    fi
    if [[ ! -d "$ORIGINAL_HOME" ]]; then
        log_msg ERROR "无法确定或访问原始用户的家目录: $ORIGINAL_HOME"
        exit 1
    fi
    log_msg DEBUG "原始用户 '$ORIGINAL_USER' 的家目录是: $ORIGINAL_HOME"
}

# === 配置加载 ===
load_config() {
    # 配置文件搜索路径顺序
    local config_file_paths=(
        # 优先用户家目录下的 .config (按脚本名)
        "${HOME}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
        # 备用名 (与请求一致)
        "${HOME}/.config/arch_backup.conf"
        # 系统级配置 (按脚本名)
        "/etc/$(basename "$SCRIPT_NAME" .sh).conf"
        # 系统级备用名
        "/etc/arch_backup.conf"
    )
    local loaded_config_file=""

    get_original_user_home # 确保 ORIGINAL_HOME 已设置

    # 如果使用 sudo 执行，调整家目录相关的配置文件路径
    if [[ -n "$SUDO_USER" ]]; then
      config_file_paths=(
          "${ORIGINAL_HOME}/.config/$(basename "$SCRIPT_NAME" .sh).conf"
          "${ORIGINAL_HOME}/.config/arch_backup.conf"
          "/etc/$(basename "$SCRIPT_NAME" .sh).conf"
          "/etc/arch_backup.conf"
      )
    fi

    for cf_path in "${config_file_paths[@]}"; do
        if [[ -f "$cf_path" ]]; then
            log_msg INFO "加载配置文件: $cf_path"
            # shellcheck source=/dev/null
            source "$cf_path" # 加载配置文件，覆盖默认设置
            loaded_config_file="$cf_path"
            break
        fi
    done

    if [[ -z "$loaded_config_file" ]]; then
        log_msg WARN "未找到配置文件，将使用默认设置。搜索路径:"
        for cf_path in "${config_file_paths[@]}"; do
             log_msg WARN "  - $cf_path"
        done
    fi

    # 根据配置设置日志级别
    case "${CONF_LOG_LEVEL^^}" in # 转换为大写
        DEBUG) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        INFO)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO  ;;
        WARN)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN  ;;
        ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *)     log_msg WARN "无效的 CONF_LOG_LEVEL '${CONF_LOG_LEVEL}'。将使用默认级别 INFO。"
               CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac

    # 确保日志文件目录存在，如果由脚本创建，则设置权限
    local log_dir
    log_dir=$(dirname "$CONF_LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
        # 如果以 root 身份运行且原始用户存在，则将日志目录所有权赋予原始用户
        if [[ "$EFFECTIVE_UID" -eq 0 && -n "$SUDO_USER" ]]; then
            chown "$ORIGINAL_UID:$ORIGINAL_GID" "$log_dir" || log_msg WARN "无法更改日志目录 '$log_dir' 的所有权。"
        fi
    fi
    # 创建日志文件并设置权限
    touch "$CONF_LOG_FILE"
    if [[ "$EFFECTIVE_UID" -eq 0 && -n "$SUDO_USER" ]]; then
        chown "$ORIGINAL_UID:$ORIGINAL_GID" "$CONF_LOG_FILE" || log_msg WARN "无法更改日志文件 '$CONF_LOG_FILE' 的所有权。"
    fi

    # 验证关键配置项
    if [[ -z "$CONF_BACKUP_ROOT_DIR" ]]; then
        log_msg ERROR "CONF_BACKUP_ROOT_DIR 未设置，请配置此项。"
        exit 1
    fi
    mkdir -p "$CONF_BACKUP_ROOT_DIR" # 确保备份根目录存在
    BACKUP_TARGET_DIR_UNCOMPRESSED="${CONF_BACKUP_ROOT_DIR}/snapshots"     # 未压缩快照目录
    BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES="${CONF_BACKUP_ROOT_DIR}/archives" # 压缩归档目录
    mkdir -p "$BACKUP_TARGET_DIR_UNCOMPRESSED"
    mkdir -p "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES"

    # 根据压缩方法设置压缩扩展名 (如果未正确设置)
    case "$CONF_COMPRESSION_METHOD" in
        gzip) CONF_COMPRESSION_EXT="tar.gz" ;;
        bzip2) CONF_COMPRESSION_EXT="tar.bz2" ;;
        xz) CONF_COMPRESSION_EXT="tar.xz" ;;
        *) log_msg WARN "未知的压缩方法 '$CONF_COMPRESSION_METHOD'。归档可能会失败。";;
    esac

    # 如果并行任务数 > 1，检查 GNU Parallel
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 ]]; then
        if command -v parallel &>/dev/null; then
            PARALLEL_CMD="parallel --no-notice --jobs $CONF_PARALLEL_JOBS --halt soon,fail=1"
            log_msg INFO "找到 GNU Parallel。将使用 $CONF_PARALLEL_JOBS 个并行任务。"
        else
            log_msg WARN "未找到 GNU Parallel，但 CONF_PARALLEL_JOBS > 1。将回退到串行执行。"
            CONF_PARALLEL_JOBS=1 # 强制串行
            PARALLEL_CMD=""
        fi
    else
        PARALLEL_CMD="" # 串行执行
    fi
}

# 检查磁盘空间
check_disk_space() {
    local path_to_check="$1"        # 需要检查的路径
    local required_percent="$2"     # 要求的最小剩余百分比
    local available_space_used_percent
    # 获取已用百分比
    available_space_used_percent=$(df --output=pcent "$path_to_check" | tail -n 1 | sed 's/%//' | xargs)
    local free_space_percent=$((100 - available_space_used_percent))

    if [[ "$free_space_percent" -lt "$required_percent" ]]; then
        log_msg ERROR "路径 '$path_to_check' 磁盘空间不足。可用: ${free_space_percent}%, 要求: ${required_percent}%。"
        exit 1
    else
        log_msg INFO "路径 '$path_to_check' 磁盘空间检查通过。可用: ${free_space_percent}%。"
    fi
}


# === 备份功能函数 ===

# 通用 rsync 备份函数
# $1: 备份任务名称 (用于日志)
# $2: 目标子目录名称 (例如 "etc", "home_user")
# $3: --link-dest 选项字符串 (例如 "--link-dest=../previous_backup/") 或空字符串
# $4+: 源路径数组
_perform_rsync_backup() {
    local task_name="$1"
    local dest_subdir_name="$2"
    local link_dest_opt="$3"
    shift 3 # 移除前三个参数，剩下的是源路径
    local sources=("$@")
    local rsync_dest_path="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/${dest_subdir_name}/"

    mkdir -p "$rsync_dest_path"

    local rsync_opts=(
        "-aH"               # 归档模式, 保留硬链接
        "--delete"          # 删除目标目录中源目录不存在的文件
        "--numeric-ids"     # 按数字形式保留UID/GID
        "--info=progress2"  # 显示进度 (rsync自身进度，非脚本整体)
        # 可选: --exclude-from=FILE 或更多 --exclude 模式 (如果每个任务需要)
    )
    [[ -n "$link_dest_opt" ]] && rsync_opts+=("$link_dest_opt") # 如果link_dest_opt非空，则添加

    log_msg INFO "开始备份: $task_name"
    
    # 如果是用户家目录备份且有排除项，创建排除文件
    local user_exclude_file=""
    if [[ "$task_name" == "用户数据" && ${#CONF_USER_HOME_EXCLUDE[@]} -gt 0 ]]; then
        user_exclude_file=$(mktemp) # 创建临时文件
        printf "%s\n" "${CONF_USER_HOME_EXCLUDE[@]}" > "$user_exclude_file"
        rsync_opts+=("--exclude-from=$user_exclude_file")
    fi
    
    # 如果是自定义路径备份且有排除项，创建排除文件
    local custom_exclude_file=""
    if [[ "$task_name" == "自定义路径" && ${#CONF_CUSTOM_PATHS_EXCLUDE[@]} -gt 0 ]]; then
        custom_exclude_file=$(mktemp)
        printf "%s\n" "${CONF_CUSTOM_PATHS_EXCLUDE[@]}" > "$custom_exclude_file"
        rsync_opts+=("--exclude-from=$custom_exclude_file")
    fi

    # 执行 rsync
    # 注意: rsync 的输出（如进度条）会直接显示在终端，也会被 tee 捕获到日志文件
    if rsync "${rsync_opts[@]}" "${sources[@]}" "$rsync_dest_path"; then
        log_msg INFO "成功备份: $task_name"
    else
        log_msg ERROR "备份失败: $task_name (rsync 退出码: $?)"
        # 根据 PARALLEL_CMD，此错误可能由 GNU Parallel 的 --halt 处理
        # 如果未使用 GNU Parallel，我们应考虑退出或标记失败。
        # 目前，如果使用 GNU Parallel，它会处理。否则，记录日志并继续。
        # 可以将其设置为更严格，以便在任何 rsync 失败时立即退出。
        return 1 # 表示失败
    fi

    # 清理临时排除文件
    [[ -n "$user_exclude_file" ]] && rm -f "$user_exclude_file"
    [[ -n "$custom_exclude_file" ]] && rm -f "$custom_exclude_file"
    return 0 # 表示成功
}

backup_system_config() {
    if [[ "$CONF_BACKUP_SYSTEM_CONFIG" != "true" ]]; then log_msg INFO "跳过系统配置备份。"; return 0; fi
    if [[ "$EFFECTIVE_UID" -ne 0 ]]; then # 检查是否为 root 用户
        log_msg WARN "跳过系统配置备份: 备份 /etc 需要 root 权限。"
        return 1 # 返回1表示失败或未执行
    fi
    # $1 是传递给 _perform_rsync_backup 的 link_dest_opt
    _perform_rsync_backup "系统配置 (/etc)" "etc" "$1" "/etc/"
}

backup_user_data() {
    if [[ "$CONF_BACKUP_USER_DATA" != "true" ]]; then log_msg INFO "跳过用户数据备份。"; return 0; fi
    if [[ ${#CONF_USER_HOME_INCLUDE[@]} -eq 0 ]]; then # 检查是否有要包含的项目
        log_msg WARN "跳过用户数据备份: CONF_USER_HOME_INCLUDE 为空。"
        return 0
    fi

    local user_sources=() # 存储用户家目录下的源路径
    for item in "${CONF_USER_HOME_INCLUDE[@]}"; do
        user_sources+=("${ORIGINAL_HOME}/${item}") # 使用原始用户的家目录
    done
    _perform_rsync_backup "用户数据" "home_${ORIGINAL_USER}" "$1" "${user_sources[@]}"
}

backup_packages() {
    if [[ "$CONF_BACKUP_PACKAGES" != "true" ]]; then log_msg INFO "跳过软件包列表备份。"; return 0; fi
    log_msg INFO "正在备份软件包列表..."
    local pkg_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/packages/"
    mkdir -p "$pkg_dest_dir"

    pacman -Qqe > "${pkg_dest_dir}/packages_official.list" # 官方仓库包
    pacman -Qqm > "${pkg_dest_dir}/packages_aur_foreign.list" # AUR 和其他非官方包
    # 可选: 包含版本的完整软件包信息
    pacman -Q > "${pkg_dest_dir}/packages_all_versions.list"

    log_msg INFO "软件包列表已备份至 $pkg_dest_dir"
}

backup_logs() {
    if [[ "$CONF_BACKUP_LOGS" != "true" ]]; then log_msg INFO "跳过系统日志备份。"; return 0; fi
    log_msg INFO "正在备份系统日志..."
    local logs_dest_dir="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}/logs/"
    mkdir -p "$logs_dest_dir"

    if [[ "$CONF_BACKUP_JOURNALCTL" == "true" ]]; then
        if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
            log_msg WARN "跳过 journalctl 备份: 完全访问 journal 可能需要 root 权限。"
        fi
        # shellcheck disable=SC2086 # 允许 CONF_JOURNALCTL_ARGS 中的参数被分割
        journalctl ${CONF_JOURNALCTL_ARGS} > "${logs_dest_dir}/journal.log" \
            || log_msg WARN "备份 journalctl 失败 (非关键错误)。"
    fi

    if [[ "$EFFECTIVE_UID" -ne 0 && ${#CONF_SYSTEM_LOG_FILES[@]} -gt 0 ]]; then
         log_msg WARN "跳过 /var/log/* 文件备份: 需要 root 权限。"
    elif [[ ${#CONF_SYSTEM_LOG_FILES[@]} -gt 0 ]]; then
        for log_file in "${CONF_SYSTEM_LOG_FILES[@]}"; do
            if [[ -e "/var/log/${log_file}" ]]; then
                # 使用 cp -a 来保留属性，但对于单个文件，rsync 也可以
                cp -a "/var/log/${log_file}" "${logs_dest_dir}/" || log_msg WARN "复制日志文件 ${log_file} 失败 (非关键错误)。"
            else
                log_msg WARN "日志文件 /var/log/${log_file} 未找到。"
            fi
        done
    fi
    log_msg INFO "系统日志已备份至 $logs_dest_dir"
}

backup_custom_paths() {
    if [[ "$CONF_BACKUP_CUSTOM_PATHS" != "true" ]]; then log_msg INFO "跳过自定义路径备份。"; return 0; fi
    if [[ ${#CONF_CUSTOM_PATHS_INCLUDE[@]} -eq 0 ]]; then
        log_msg WARN "跳过自定义路径备份: CONF_CUSTOM_PATHS_INCLUDE 为空。"
        return 0
    fi

    # 检查是否有自定义路径需要 root 权限
    local needs_root=0
    for path_item in "${CONF_CUSTOM_PATHS_INCLUDE[@]}"; do
        if [[ ! -r "$path_item" ]]; then # 简单的可读性检查
             if sudo -n true 2>/dev/null; then # 是否可以无密码 sudo?
                if ! sudo test -r "$path_item"; then # 用 sudo 检查是否可读
                    log_msg WARN "自定义路径 '$path_item' 即使用 sudo 可能也无法读取。"
                fi
             elif [[ "$EFFECTIVE_UID" -ne 0 ]]; then # 如果不能无密码 sudo 且当前不是 root
                needs_root=1
                break # 一旦发现一个需要 root 的就跳出
             fi
        fi
    done

    if [[ "$needs_root" -eq 1 && "$EFFECTIVE_UID" -ne 0 ]]; then
        log_msg WARN "跳过部分或全部自定义路径备份: 某些路径需要 root 权限，但脚本未以 root 身份运行。"
        # 可选: 可以只备份可访问的路径
        return 1
    fi
    _perform_rsync_backup "自定义路径" "custom" "$1" "${CONF_CUSTOM_PATHS_INCLUDE[@]}"
}

# === 压缩和清理 ===

compress_and_verify_backup() {
    local uncompressed_dir_path="$1" # 未压缩备份目录的完整路径
    local uncompressed_dir_name     # 未压缩备份目录的名称 (时间戳)
    uncompressed_dir_name=$(basename "$uncompressed_dir_path")
    local archive_path="${BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES}/${uncompressed_dir_name}.${CONF_COMPRESSION_EXT}" # 压缩后归档文件的完整路径

    if [[ ! -d "$uncompressed_dir_path" ]]; then
        log_msg WARN "无法压缩: 未找到未压缩目录 '$uncompressed_dir_path'。"
        return 1
    fi
    if [[ -f "$archive_path" ]]; then
        log_msg INFO "归档文件 '$archive_path' 已存在。跳过对 '$uncompressed_dir_name' 的压缩。"
        # 可以考虑验证已存在的归档文件是否完好
        return 0 # 或返回2表示已存在
    fi

    log_msg INFO "正在压缩备份: $uncompressed_dir_name 到 $archive_path"
    local tar_opts=""       # tar 命令选项
    local comp_test_cmd=""  # 压缩测试命令

    # 根据配置的压缩方法设置 tar 选项和测试命令
    # 注意: tar 的 J/j/z 选项通常会自动选择对应的压缩程序，这里用它来简化
    case "$CONF_COMPRESSION_METHOD" in
        gzip)  tar_opts="-czf"; comp_test_cmd="gzip -t" ;; # c: create, z: gzip, f: file
        bzip2) tar_opts="-cjf"; comp_test_cmd="bzip2 -t" ;; # j: bzip2
        xz)    tar_opts="-cJf"; comp_test_cmd="xz -t" ;;    # J: xz. tar 通常会传递 -T0 给 xz 以使用多线程
        *) log_msg ERROR "不支持的压缩方法: $CONF_COMPRESSION_METHOD"; return 1 ;;
    esac

    # 使用 tar 内建的压缩功能，简化操作并确保原子性
    # cd 到待压缩目录的父目录，以避免在 tar 归档中包含完整路径
    # tar 的压缩级别参数通常通过环境变量传递 (XZ_OPT, GZIP 等) 或某些 tar 版本支持特定选项
    # 为了简化，这里依赖 tar 对压缩工具的默认级别，或用户已在环境中设置
    # 如果需要精确控制级别，可能需要 tar | compress_tool 的管道方式
    local compress_env_opts=""
    if [[ "$CONF_COMPRESSION_METHOD" == "xz" && -n "$CONF_COMPRESSION_LEVEL" ]]; then
        compress_env_opts="XZ_OPT=\"-${CONF_COMPRESSION_LEVEL} -T0\"" # -T0 使用所有可用核心
    elif [[ "$CONF_COMPRESSION_METHOD" == "gzip" && -n "$CONF_COMPRESSION_LEVEL" ]]; then
        compress_env_opts="GZIP=\"-${CONF_COMPRESSION_LEVEL}\""
    elif [[ "$CONF_COMPRESSION_METHOD" == "bzip2" && -n "$CONF_COMPRESSION_LEVEL" ]]; then
        compress_env_opts="BZIP2=\"-${CONF_COMPRESSION_LEVEL}\""
    fi
    
    # 执行压缩命令，注意eval用于正确处理包含空格的环境变量设置
    if (cd "$(dirname "$uncompressed_dir_path")" && eval "$compress_env_opts tar '$tar_opts' '$archive_path' '$uncompressed_dir_name'"); then
        log_msg INFO "成功压缩: $uncompressed_dir_name"

        log_msg INFO "正在校验归档文件: $archive_path"
        if $comp_test_cmd "$archive_path"; then
            log_msg INFO "归档文件 '$archive_path' 校验成功。"
            if confirm_action "压缩成功后是否删除未压缩目录 '$uncompressed_dir_path'？"; then
                log_msg INFO "正在删除未压缩目录: $uncompressed_dir_path"
                rm -rf "$uncompressed_dir_path"
            else
                log_msg INFO "保留未压缩目录: $uncompressed_dir_path"
            fi
        else
            log_msg ERROR "归档文件校验失败: '$archive_path'。将保留未压缩目录。"
            rm -f "$archive_path" # 删除损坏的归档文件
            return 1
        fi
    else
        log_msg ERROR "压缩失败: '$uncompressed_dir_name'。"
        rm -f "$archive_path" # 删除可能不完整的归档文件
        return 1
    fi
    return 0
}

cleanup_backups() {
    log_msg INFO "开始清理旧备份..."

    # 1. 清理未压缩的快照 (按数量保留最新的 N 个)
    if [[ "$CONF_RETENTION_UNCOMPRESSED_COUNT" -gt 0 ]]; then
        log_msg INFO "正在清理未压缩快照。将保留最近 $CONF_RETENTION_UNCOMPRESSED_COUNT 个。"
        local uncompressed_snapshots_list # 存储快照列表
        # 查找所有快照目录，按修改时间（这里用%T@表示秒数）降序排序
        # find ... -printf "%T@ %p\n" 输出时间戳和路径，然后 sort -nr
        uncompressed_snapshots_list=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr)

        local count=0
        local snapshots_to_process=() # 存储需要压缩或删除的快照路径
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local snap_path
            snap_path=$(echo "$line" | cut -d' ' -f2-) # 提取路径部分
            count=$((count + 1))
            if [[ "$count" -gt "$CONF_RETENTION_UNCOMPRESSED_COUNT" ]]; then
                snapshots_to_process+=("$snap_path")
            fi
        done <<< "$uncompressed_snapshots_list" # 使用herestring输入

        for snap_path_to_process in "${snapshots_to_process[@]}"; do
            if [[ "$CONF_COMPRESSION_ENABLE" == "true" ]]; then
                log_msg INFO "快照 '$snap_path_to_process' 超出保留数量，尝试压缩。"
                # compress_and_verify_backup 函数会在成功压缩和校验后处理删除
                compress_and_verify_backup "$snap_path_to_process"
            else
                if confirm_action "压缩功能已禁用 (CONF_COMPRESSION_ENABLE=false)。是否永久删除旧的未压缩快照 '$snap_path_to_process'？"; then
                    log_msg INFO "正在删除旧的未压缩快照: $snap_path_to_process"
                    rm -rf "$snap_path_to_process"
                else
                    log_msg INFO "保留旧的未压缩快照: $snap_path_to_process"
                fi
            fi
        done
    else
        log_msg INFO "跳过未压缩快照的清理 (CONF_RETENTION_UNCOMPRESSED_COUNT 小于或等于 0)。"
    fi

    # 2. 清理已压缩的归档文件
    log_msg INFO "正在清理已压缩的归档文件..."
    local archives_to_delete=() # 存储待删除的归档文件路径

    # 按时间清理 (删除早于 X 天的归档)
    if [[ "$CONF_RETENTION_COMPRESSED_DAYS" -gt 0 ]]; then
        log_msg INFO "查找超过 $CONF_RETENTION_COMPRESSED_DAYS 天的压缩归档。"
        # find ... -mtime +N 表示修改时间在 N*24 小时之前的文件。
        # N 应该是 CONF_RETENTION_COMPRESSED_DAYS - 1 来匹配 "超过 X 天"
        local days_for_find=$((CONF_RETENTION_COMPRESSED_DAYS - 1))
        if [[ $days_for_find -lt 0 ]]; then days_for_find=0; fi # 确保是非负数

        # 使用进程替换和while循环读取find的输出，避免子shell问题
        while IFS= read -r archive_file; do
            [[ -z "$archive_file" ]] && continue
            archives_to_delete+=("$archive_file")
            log_msg DEBUG "标记为待删除 (按时间): $archive_file"
        done < <(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -mtime "+${days_for_find}")
    fi

    # 按数量清理 (如果设置了数量限制，并且在按时间清理后，归档数量仍超出)
    if [[ "$CONF_RETENTION_COMPRESSED_COUNT" -gt 0 ]]; then
        log_msg INFO "检查压缩归档数量。将最多保留 $CONF_RETENTION_COMPRESSED_COUNT 个。"
        local current_archives_list
        # 获取所有归档文件，按时间升序排序 (最旧的在前)
        current_archives_list=$(find "$BACKUP_TARGET_DIR_COMPRESSED_ARCHIVES" -maxdepth 1 -type f -name "*.${CONF_COMPRESSION_EXT}" -printf "%T@ %p\n" | sort -n)
        
        local archives_not_marked_by_age=() # 存储未被时间策略标记删除的归档
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local arc_path
            arc_path=$(echo "$line" | cut -d' ' -f2-)
            
            local already_marked_for_deletion=0
            for marked_arc in "${archives_to_delete[@]}"; do
                if [[ "$marked_arc" == "$arc_path" ]]; then
                    already_marked_for_deletion=1
                    break
                fi
            done

            if [[ "$already_marked_for_deletion" -eq 0 ]]; then
                archives_not_marked_by_age+=("$arc_path")
            fi
        done <<< "$current_archives_list"

        local num_to_delete_by_count=0
        # 计算需要按数量删除多少个 (从archives_not_marked_by_age中)
        num_to_delete_by_count=$((${#archives_not_marked_by_age[@]} - CONF_RETENTION_COMPRESSED_COUNT))

        if [[ "$num_to_delete_by_count" -gt 0 ]]; then
            log_msg INFO "需要删除 $num_to_delete_by_count 个最旧的归档以满足数量限制。"
            # 将 archives_not_marked_by_age 中最旧的几个添加到 archives_to_delete
            for ((i=0; i<num_to_delete_by_count; i++)); do
                archives_to_delete+=("${archives_not_marked_by_age[i]}") # 添加最旧的
                log_msg DEBUG "标记为待删除 (按数量): ${archives_not_marked_by_age[i]}"
            done
        fi
    fi
    
    # 对 archives_to_delete 列表去重 (可能某个文件同时满足了时间和数量策略)
    local unique_archives_to_delete_list
    if [[ ${#archives_to_delete[@]} -gt 0 ]]; then
        unique_archives_to_delete_list=$(printf "%s\n" "${archives_to_delete[@]}" | sort -u)
    else
        unique_archives_to_delete_list=""
    fi

    if [[ -z "$unique_archives_to_delete_list" ]]; then
        log_msg INFO "没有标记为待删除的压缩归档。"
    else
        log_msg INFO "以下压缩归档将被删除:"
        echo "$unique_archives_to_delete_list" # 显示列表
        local num_unique_to_delete
        num_unique_to_delete=$(echo "$unique_archives_to_delete_list" | wc -l)
        if confirm_action "是否继续删除这 $num_unique_to_delete 个压缩归档文件？"; then
            while IFS= read -r archive_to_delete; do
                [[ -z "$archive_to_delete" ]] && continue
                log_msg INFO "正在删除压缩归档: $archive_to_delete"
                rm -f "$archive_to_delete"
            done <<< "$unique_archives_to_delete_list"
        else
            log_msg INFO "用户取消了旧压缩归档的删除操作。"
        fi
    fi
    log_msg INFO "备份清理完成。"
}


# === 主备份流程控制 ===
run_backup() {
    log_msg INFO "开始 Arch Linux 备份 (版本 $SCRIPT_VERSION)"
    CURRENT_TIMESTAMP=$(date '+%Y%m%d_%H%M%S') # 生成当前时间戳
    local current_backup_path_uncompressed="${BACKUP_TARGET_DIR_UNCOMPRESSED}/${CURRENT_TIMESTAMP}"
    mkdir -p "$current_backup_path_uncompressed" # 创建当前备份的未压缩目录
    log_msg INFO "当前备份目标 (未压缩): $current_backup_path_uncompressed"

    # 检查备份目标磁盘空间
    check_disk_space "$CONF_BACKUP_ROOT_DIR" "$CONF_MIN_FREE_DISK_SPACE_PERCENT"

    local link_dest_option="" # rsync 的 --link-dest 选项
    if [[ "$CONF_INCREMENTAL_BACKUP" == "true" ]]; then
        # 查找最新的已存在的未压缩快照目录 (按时间顺序)
        local latest_snapshot_dir
        # find ... ! -name "$CURRENT_TIMESTAMP" 排除当前正在创建的目录
        latest_snapshot_dir=$(find "$BACKUP_TARGET_DIR_UNCOMPRESSED" -mindepth 1 -maxdepth 1 -type d ! -name "$CURRENT_TIMESTAMP" -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)

        if [[ -n "$latest_snapshot_dir" && -d "$latest_snapshot_dir" ]]; then
            # 为 --link-dest 使用相对路径，这样如果备份根目录移动了，链接依然有效
            local relative_link_dest
            # rsync 的 --link-dest 路径是相对于目标目录的，所以是 ../<上一个快照名>
            relative_link_dest="../$(basename "$latest_snapshot_dir")"
            link_dest_option="--link-dest=${relative_link_dest}"
            log_msg INFO "已启用增量备份。使用 '$latest_snapshot_dir' 作为基础 (通过 $link_dest_option)。"
        else
            log_msg INFO "已启用增量备份，但未找到先前的快照。将执行完整备份。"
        fi
    else
        log_msg INFO "未启用增量备份。将执行完整备份。"
    fi

    # 准备备份任务列表 (函数名称字符串)
    # 格式: "function_name '参数1' '参数2'"
    # link_dest_option 需要被正确引用传递
    local backup_tasks=()
    # 根据配置决定添加哪些备份任务
    [[ "$CONF_BACKUP_SYSTEM_CONFIG" == "true" ]] && backup_tasks+=("backup_system_config \"$link_dest_option\"")
    [[ "$CONF_BACKUP_USER_DATA" == "true" ]] && backup_tasks+=("backup_user_data \"$link_dest_option\"")
    [[ "$CONF_BACKUP_PACKAGES" == "true" ]] && backup_tasks+=("backup_packages") # 此任务不使用rsync或link-dest
    [[ "$CONF_BACKUP_LOGS" == "true" ]] && backup_tasks+=("backup_logs")         # 同上
    [[ "$CONF_BACKUP_CUSTOM_PATHS" == "true" ]] && backup_tasks+=("backup_custom_paths \"$link_dest_option\"")

    if [[ ${#backup_tasks[@]} -eq 0 ]]; then
        log_msg WARN "没有启用的备份类别。无需执行任何操作。"
        rm -rf "$current_backup_path_uncompressed" # 清理空的时间戳目录
        return 0
    fi

    local overall_backup_success="true" # 标记整体备份是否成功
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 && -n "$PARALLEL_CMD" ]]; then
        log_msg INFO "正在并行执行备份任务..."
        # 将每个任务作为命令字符串传递给 GNU Parallel
        # 每个任务函数必须自行处理错误并记录日志。
        # GNU Parallel 的 --halt soon,fail=1 会在任何作业失败时停止。
        # 这要求任务在失败时以非零状态退出。
        # 使用 printf 和管道将任务传递给 parallel
        if ! printf "%s\n" "${backup_tasks[@]}" | $PARALLEL_CMD {}; then
             overall_backup_success="false"
             log_msg ERROR "一个或多个并行备份任务失败。GNU Parallel 返回错误。"
        fi
        # GNU Parallel 会等待所有任务完成或因--halt而中止。
        # 检查每个任务的成功与否比较复杂，因为parallel本身有--halt机制。
        # 如果parallel因为--halt而提前退出，它会返回非0。
        # _perform_rsync_backup 返回非0可以触发 parallel 的 --halt soon,fail=1
    else
        log_msg INFO "正在串行执行备份任务..."
        for task_cmd_str in "${backup_tasks[@]}"; do
            # 小心使用 eval，因为 task_cmd_str 可能包含带参数的函数调用
            # 确保 task_cmd_str 中的参数已正确引用 (如 \"$link_dest_option\")
            if ! eval "$task_cmd_str"; then # 执行任务
                overall_backup_success="false"
                log_msg ERROR "任务 '$task_cmd_str' 执行失败。后续任务可能受影响。"
                # 决定: 继续还是中止? 目前选择继续尝试其他备份。
                # 如果需要严格的错误处理, 在这里添加 'exit 1' 或使 _perform_rsync_backup 退出。
            fi
        done
    fi

    if [[ "$overall_backup_success" == "false" ]]; then
        log_msg ERROR "一个或多个备份任务失败。位于 $current_backup_path_uncompressed 的备份可能不完整。"
        # 可选: 删除失败的备份尝试
        # if confirm_action "是否删除不完整的备份目录 $current_backup_path_uncompressed？"; then
        #    rm -rf "$current_backup_path_uncompressed"
        #    log_msg INFO "不完整的备份已删除。"
        # fi
        # exit 1 # 如果任何部分失败，则以错误退出
    else
        log_msg INFO "所有备份任务均已成功完成: $CURRENT_TIMESTAMP。"
        # 基本验证: 检查备份目录是否为空
        if [ -z "$(ls -A "$current_backup_path_uncompressed")" ]; then # ls -A 列出除 . 和 .. 外的所有条目
            log_msg WARN "备份目录 $current_backup_path_uncompressed 为空。这可能表示存在问题。"
            overall_backup_success="false" # 如果目录为空，也认为备份不完全成功
        else
            log_msg INFO "基本验证: 备份目录 $current_backup_path_uncompressed 非空。"
            # 此处可以添加更复杂的验证，例如检查特定的标记文件。
        fi
    fi

    # 清理旧备份 (此函数也会处理将超出未压缩保留期限的快照进行压缩)
    cleanup_backups

    log_msg INFO "Arch Linux 备份完成: $CURRENT_TIMESTAMP。"
    # 如果 overall_backup_success 为 false，脚本会因为 set -e (如果命令失败) 或我们显式返回1而以错误状态退出
    if [[ "$overall_backup_success" == "false" ]]; then
        return 1 # 返回1表示备份过程有失败
    fi
    return 0 # 返回0表示成功
}


# === 脚本入口点 ===
main() {
    # 提示: 除非确实需要备份 /etc, /var/log 等，否则不建议直接以 root 运行
    # 这个检查更多是信息性的，具体函数会处理权限。
    if [[ "$EFFECTIVE_UID" -eq 0 && -z "$SUDO_USER" ]]; then
        log_msg WARN "脚本正以 root 用户直接运行。如果计划进行用户特定数据备份，请考虑使用 sudo。"
    fi

    # 首先加载配置, 以便获取日志路径和级别
    load_config # 此函数也会设置 CURRENT_LOG_LEVEL 和初始化日志文件

    # 日志系统已配置完毕, 现在检查依赖
    # 核心工具列表
    local required_system_deps=("rsync" "tar" "find" "sort" "df" "getent" "cut" "head" "tail" "sed" "grep" "wc" "mkdir" "rm" "id" "date" "basename" "dirname" "mktemp")
    local compression_tool_to_check=""
    # 只检查配置中指定的压缩工具
    case "$CONF_COMPRESSION_METHOD" in
        gzip)  compression_tool_to_check="gzip" ;;
        bzip2) compression_tool_to_check="bzip2" ;;
        xz)    compression_tool_to_check="xz" ;;
    esac
    [[ -n "$compression_tool_to_check" ]] && required_system_deps+=("$compression_tool_to_check")

    # 如果配置了并行任务且数量大于1，则检查 parallel
    if [[ "$CONF_PARALLEL_JOBS" -gt 1 ]]; then
        # parallel 通常是 GNU Parallel 的命令名
        required_system_deps+=("parallel")
    fi
    check_dependencies "${required_system_deps[@]}"

    # 执行实际的备份工作
    if run_backup; then
        log_msg INFO "$SCRIPT_NAME 执行成功。"
    else
        log_msg ERROR "$SCRIPT_NAME 执行过程中遇到错误。"
        exit 1 # 以错误状态退出
    fi

    exit 0 # 正常退出
}

# 可选: 捕获中断信号进行清理 (例如临时文件，尽管此脚本目前不大量使用)
# trap "echo '脚本被中断。正在清理...'; exit 1" SIGINT SIGTERM

# 执行 main 函数, 并传递所有命令行参数 (虽然此脚本目前不处理它们)
main "$@"