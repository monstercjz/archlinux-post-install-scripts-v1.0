#!/bin/bash

# 定义日志级别
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4
LOG_LEVEL_NONE=5 # 不输出任何日志

# 默认日志级别
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

# 设置日志文件目录
LOG_DIR="/home/cjz/archlinux-post-install-scripts-v1.0/log"

# 确保日志目录存在
mkdir -p "${LOG_DIR}"

# 日志函数
# 参数: $1 - 日志级别 (DEBUG, INFO, WARN, ERROR, FATAL)
# 参数: $2 - 调用脚本名称 (使用 basename "$0" 传递)
# 参数: $3 - 日志消息
log_message() {
    local level_str="$1"
    local caller_script="$2"
    local message="$3"
    local level_int

    case "${level_str}" in
        "DEBUG") level_int=${LOG_LEVEL_DEBUG} ;;
        "INFO")  level_int=${LOG_LEVEL_INFO}  ;;
        "WARN")  level_int=${LOG_LEVEL_WARN}  ;;
        "ERROR") level_int=${LOG_LEVEL_ERROR} ;;
        "FATAL") level_int=${LOG_LEVEL_FATAL} ;;
        *)       level_int=${LOG_LEVEL_INFO}  # 默认为INFO
                 level_str="INFO"
                 ;;
    esac

    # 检查当前日志级别是否允许输出
    if [ "${level_int}" -ge "${CURRENT_LOG_LEVEL}" ]; then
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        local formatted_message="[${timestamp}] [${level_str}] [${caller_script}] ${message}"

        # 输出到控制台
        echo "${formatted_message}"

        # 输出到日志文件
        local log_file="${LOG_DIR}/${caller_script}.log"
        echo "${formatted_message}" >> "${log_file}"
    fi
}

# 方便调用的日志函数
log_debug() { log_message "DEBUG" "${__SCRIPT_NAME}" "$1"; }
log_info()  { log_message "INFO"  "${__SCRIPT_NAME}" "$1"; }
log_warn()  { log_message "WARN"  "${__SCRIPT_NAME}" "$1"; }
log_error() { log_message "ERROR" "${__SCRIPT_NAME}" "$1"; }
log_fatal() { log_message "FATAL" "${__SCRIPT_NAME}" "$1"; }

# 示例用法 (在实际使用时，需要在调用脚本中 source 这个文件)
# source "/path/to/log.sh"
# __SCRIPT_NAME=$(basename "$0") # 在主脚本中设置此变量
# log_info "这是一个信息日志"
# log_debug "这是一个调试日志"