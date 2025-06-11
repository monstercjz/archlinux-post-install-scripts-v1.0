#!/bin/bash
# ==========================
# 脚本名称: package_stats_with_versions.sh
# 描述: 此脚本用于分析Arch Linux系统中手动安装的软件包，并提供详细的统计信息和报告，包括版本号。
# 功能:
#   1. 获取系统初始安装日期。
#   2. 获取用户首次执行命令的时间。
#   3. 统计手动安装的软件包列表，包括安装日期、软件包名称、版本号、大小和仓库来源。
#   4. 提供排序选项，按安装日期、软件包大小或软件包名称排序。
#   5. 将统计结果保存到文件，并生成一个仅包含软件包名称的列表文件，便于一键安装。
# 使用方法:
#   1. 建议以 sudo 运行脚本，以便写入 /var/log 目录: sudo ./package_stats_with_versions.sh
#   2. 根据提示选择排序方式。
#   3. 统计结果将保存到 save_dir="/var/backups/manual_install_packages" 目录。
#   4. 可以使用生成的软件包名称列表文件在新系统上一键安装所有软件包。
# 作者: [Your Name/AI Assistant]
# 版本: 4.1 (incorporating version info)
# 日期: 2024-07-16
# ==========================
# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; NC='\033[0m'

# 获取用户执行的第一条命令时间
get_first_command_time() {
    echo -e "${YELLOW}正在获取用户第一次执行命令的时间...${NC}" >&2
    
    if command -v journalctl &> /dev/null; then
        echo -e "${BLUE}尝试从journalctl日志获取最早的用户命令记录...${NC}" >&2
        earliest_session=$(journalctl _UID=1000 --output=short-iso --reverse | tail -n 1)
        if [ -n "$earliest_session" ]; then
            if [[ "$earliest_session" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)) ]]; then
                session_date_str="${BASH_REMATCH[1]}"
                session_date=$(date -d "$session_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
                if [ -n "$session_date" ]; then
                    echo -e "${GREEN}成功获取用户首次活动时间: $session_date (来源: journalctl用户会话记录)${NC}" >&2
                    echo "$session_date"
                    return 0
                fi
            fi
        fi
    fi

    if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试从pacman.log获取第一条pacman -S命令时间...${NC}" >&2
        first_install=$(grep -m 1 -E "\[PACMAN\] Running 'pacman -S" /var/log/pacman.log)
        if [ -n "$first_install" ]; then
            if [[ "$first_install" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
                install_time_str="${BASH_REMATCH[1]}"
                install_time=$(date -d "$install_time_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
                if [ -n "$install_time" ]; then
                    echo -e "${GREEN}成功获取用户首次安装软件时间: $install_time (来源: pacman.log第一条安装命令)${NC}" >&2
                    echo "$install_time"
                    return 0
                fi
            fi
        fi
    fi

    if [ -f "$HOME/.bash_history" ]; then
        echo -e "${BLUE}尝试从bash历史记录获取最早命令时间...${NC}" >&2
        history_date_str=$(stat -c %y "$HOME/.bash_history" | awk '{print $1 " " $2}')
        history_date=$(date -d "$history_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
        if [ -n "$history_date" ]; then
            echo -e "${GREEN}成功获取用户首次活动时间: $history_date (来源: bash历史记录创建时间)${NC}" >&2
            echo "$history_date"
            return 0
        fi
    fi

    echo -e "${YELLOW}无法获取用户首次活动时间，使用系统安装时间作为参考...${NC}" >&2
    install_date=$(get_install_date)
    echo "$install_date"
    return 1
}

# 获取系统初始安装日期
get_install_date() {
    echo -e "${YELLOW}正在获取系统初始安装日期...${NC}" >&2
    
    if [ -f "/etc/machine-id" ]; then
        echo -e "${BLUE}尝试从 /etc/machine-id 文件的创建时间获取系统安装日期...${NC}" >&2
        install_date_str=$(stat -c %y /etc/machine-id | awk '{print $1 " " $2}')
        install_date=$(date -d "$install_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
        if [ -n "$install_date" ]; then
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: /etc/machine-id 文件创建时间)${NC}" >&2
            echo "$install_date"
            return 0
        fi
    fi

    if [ -d "/lost+found" ]; then
        echo -e "${BLUE}尝试使用 /lost+found 目录的创建时间作为系统安装日期...${NC}" >&2
        install_date_str=$(stat -c %w /lost+found | awk '{print $1 " " $2}') # %w is birth time if available
        if [ -z "$install_date_str" ] || [[ "$install_date_str" == *"1970-01-01"* ]] || [[ "$install_date_str" == *"-"* ]]; then # Fallback if birth time is not supported or invalid
             install_date_str=$(stat -c %y /lost+found | awk '{print $1 " " $2}') # Use modification time
        fi
        install_date=$(date -d "$install_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
        if [ -n "$install_date" ]; then
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: /lost+found 目录创建/修改时间)${NC}" >&2
            echo "$install_date"
            return 0
        fi
    fi

    if command -v journalctl &> /dev/null; then
        echo -e "${BLUE}尝试从 journalctl 启动记录获取系统安装日期...${NC}" >&2
        earliest_boot=$(journalctl --list-boots | grep -E '^[[:space:]]*-?[0-9]+' | sort -n -k1 | head -n 1)
        if [ -n "$earliest_boot" ]; then
            # Extract date, handling different possible formats from journalctl --list-boots
            # Example: "   0  booted   Mon 2023-10-16 10:00:00 UTC - Mon 2023-10-16 10:05:00 UTC"
            # Or:    "   0 f1abc... Mon 2023-10-16 10:00:00 UTC ... "
            boot_date_str=$(echo "$earliest_boot" | sed -E 's/^[[:space:]]*-?[0-9]+[[:space:]]+([a-z0-9]+[[:space:]]+)?//' | awk '{print $2, $3, $4}') # $1 is day, $2 date, $3 time
            install_date=$(date -d "$boot_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
            if [ -n "$install_date" ]; then
                echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: journalctl 最早启动记录)${NC}" >&2
                echo "$install_date"
                return 0
            fi
        fi
    fi
    
    if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试从 pacman.log 日志文件获取系统初始安装日期...${NC}" >&2
        first_log_line=$(head -n 1 /var/log/pacman.log)
        if [[ "$first_log_line" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
            iso_date_str="${BASH_REMATCH[1]}"
            install_date=$(date -d "$iso_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
            if [ -n "$install_date" ]; then
                echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 第一行日志时间 - ISO 8601格式)${NC}" >&2
                echo "$install_date"
                return 0
            fi
        elif [[ "$first_log_line" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}) ]]; then # Old format YYYY-MM-DD HH:MM
            install_date_str="${BASH_REMATCH[1]}"
             install_date=$(date -d "$install_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
            if [ -n "$install_date" ]; then
                echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 第一行日志时间 - 旧格式)${NC}" >&2
                echo "$install_date"
                return 0
            fi
        fi
    fi
    
    if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试使用 pacman.log 文件的创建时间作为系统安装日期...${NC}" >&2
        install_date_str=$(stat -c %y /var/log/pacman.log | awk '{print $1 " " $2}')
        install_date=$(date -d "$install_date_str" "+%Y-%m-%d %H:%M" 2>/dev/null)
        if [ -n "$install_date" ]; then
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 文件创建时间)${NC}" >&2
            echo "$install_date"
            return 0
        fi
    fi
    
    echo -e "${YELLOW}无法获取准确的系统安装日期，使用当前时间减去30天作为估计值...${NC}" >&2
    install_date=$(date -d "30 days ago" "+%Y-%m-%d %H:%M")
    echo -e "${GREEN}估计的系统安装日期: $install_date (来源: 当前时间减去30天)${NC}" >&2
    echo "$install_date"
    return 1
}

# 获取手动安装的软件包列表
get_manually_installed_packages() {
    local reference_date_str=$1 # This is the date string like "YYYY-MM-DD HH:MM"
    local sort_by=$2
    
    local reference_date_epoch=$(date -d "$reference_date_str" +%s 2>/dev/null)
    if [ -z "$reference_date_epoch" ]; then
        echo -e "${RED}错误: 无法将参考日期 '$reference_date_str' 转换为时间戳。${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}参考日期 (系统安装/首次活动): $reference_date_str (Epoch: $reference_date_epoch)${NC}" >&2
    echo -e "${YELLOW}正在统计手动安装的软件包...${NC}" >&2
    
    declare -A is_aur_package
    declare -A aur_package_versions
    
    echo -e "${BLUE}正在获取AUR/本地软件包列表及其版本...${NC}" >&2
    while IFS=' ' read -r pkg_name pkg_version; do
        is_aur_package["$pkg_name"]=1
        aur_package_versions["$pkg_name"]="$pkg_version"
    done < <(pacman -Qm)

    echo -e "${BLUE}正在获取所有明确安装的软件包（非依赖）及其版本...${NC}" >&2
    mapfile -t explicit_packages_lines < <(pacman -Qe)
    
    local total_packages=${#explicit_packages_lines[@]}
    echo -e "${GREEN}找到 $total_packages 个明确安装的软件包${NC}" >&2
    
    declare -a results
    local counter=0
    
    echo -e "${BLUE}正在分析每个软件包的安装日期...${NC}" >&2
    for pkg_line in "${explicit_packages_lines[@]}"; do
        # pkg_line is "package-name version"
        local pkg_name="${pkg_line%% *}"
        local pkg_version="${pkg_line#* }"

        ((counter++))
        if [ $((counter % 10)) -eq 0 ] || [ $counter -eq 1 ] || [ $counter -eq $total_packages ]; then
            echo -e "${YELLOW}正在处理: $pkg_name ($counter / $total_packages - $(($counter * 100 / $total_packages))%)${NC}" >&2
        fi
        
        # 从pacman日志中获取该包名首次安装的日期
        # 加空格确保匹配完整包名，避免如 "nano" 匹配 "nano-syntax-highlighting"
        local install_log=$(grep -m 1 "\[ALPM\] installed ${pkg_name} " /var/log/pacman.log)
        
        if [ -n "$install_log" ]; then
            local pkg_install_date_epoch
            if [[ "$install_log" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
                pkg_install_date_epoch=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null)
            # elif [[ "$install_log" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}) ]]; then # Old format
            #    pkg_install_date_epoch=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null)
            else # Fallback if regex fails, try parsing the start of the line (less reliable)
                 local fallback_date_str=$(echo "$install_log" | awk '{print $1 " " $2}' | sed 's/\[//; s/\]//; s/T/ /')
                 pkg_install_date_epoch=$(date -d "$fallback_date_str" +%s 2>/dev/null)
            fi
            
            if [ -n "$pkg_install_date_epoch" ] && [ "$pkg_install_date_epoch" -gt "$reference_date_epoch" ]; then
                local pkg_size
                # 使用 LC_ALL=C 确保 grep "Installed Size" 能正常工作
                pkg_size_line=$(LC_ALL=C pacman -Qi "$pkg_name" | grep "Installed Size")
                if [[ "$pkg_size_line" =~ :\s*(.*) ]]; then
                    pkg_size=$(echo "${BASH_REMATCH[1]}" | tr -d ' ')
                else
                    pkg_size="N/A"
                fi

                local repo="Official"
                local current_version_to_display="$pkg_version" # Default to -Qe version

                if [ -n "${is_aur_package[$pkg_name]}" ]; then
                    repo="AUR/Local"
                    # For AUR packages, -Qm gives the correct current version
                    current_version_to_display="${aur_package_versions[$pkg_name]}"
                fi
                
                results+=("$(date -d @"$pkg_install_date_epoch" "+%Y-%m-%d %H:%M:%S")|$pkg_name|$current_version_to_display|$pkg_size|$repo")
            fi
        else
             echo -e "${YELLOW}警告: 未在pacman.log中找到软件包 '$pkg_name' 的安装记录。可能在日志轮转前安装或为基础包。${NC}" >&2
        fi
    done
    
    echo -e "${BLUE}正在按 '$sort_by' 对结果进行排序...${NC}" >&2
    case "$sort_by" in
        "date")
            echo -e "${GREEN}按安装日期排序（最新的在前）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -r -t'|' -k1,1
            ;;
        "size")
            echo -e "${GREEN}按软件包大小排序（最大的在前）${NC}" >&2
            # sort -h (human-readable) is GNU specific. tr to bytes first for portability or use a more complex sort.
            # For simplicity, sorting as string here. For true size sort, convert to bytes.
            # Example: 100MiB vs 2GiB. For now, let's use general human numeric sort on field 4 (size)
            printf "%s\n" "${results[@]}" | sort -t'|' -k4hr  # GNU sort specific for human numeric
            ;;
        "name")
            echo -e "${GREEN}按软件包名称排序（字母顺序）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -t'|' -k2,2
            ;;
        *)
            echo -e "${GREEN}使用默认排序方式：按安装日期排序（最新的在前）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -r -t'|' -k1,1
            ;;
    esac
}

# 显示软件包统计信息
show_package_stats() {
    echo -e "${CYAN}========== 开始软件包统计 ===========${NC}"
    
    echo -e "${GREEN}请选择排序方式:${NC}"
    echo -e "${GREEN}1. 按安装日期排序（最新的在前）${NC}"
    echo -e "${GREEN}2. 按软件包大小排序（最大的在前）${NC}"
    echo -e "${GREEN}3. 按软件包名称排序${NC}"
    
    local save_dir="/var/backups/manual_install_packages"
    if [ ! -d "$save_dir" ]; then
        echo -e "${YELLOW}创建保存目录: $save_dir (需要sudo权限)${NC}"
        mkdir -p "$save_dir" # Assumes script is run with sudo or user has rights
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建目录 $save_dir. 请确保您有足够权限或以sudo运行脚本。${NC}" >&2
            return 1
        fi
    else
        echo -e "${GREEN}保存目录已存在: $save_dir${NC}"
    fi
    
    read -rp "请输入选项 (1-3, 默认1): " choice
    choice=${choice:-1} # Default to 1 if empty

    local reference_date_str
    reference_date_str=$(get_first_command_time)
    if [ -z "$reference_date_str" ]; then
        echo -e "${RED}错误: 无法获取参考日期。脚本无法继续。${NC}" >&2
        return 1
    fi
    
    local sort_option_str
    local packages_output # To store the output of get_manually_installed_packages

    case $choice in
        1) 
            echo -e "${GREEN}您选择了: 按安装日期排序${NC}"
            sort_option_str="date"
            ;;
        2) 
            echo -e "${GREEN}您选择了: 按软件包大小排序${NC}"
            sort_option_str="size"
            ;;
        3) 
            echo -e "${GREEN}您选择了: 按软件包名称排序${NC}"
            sort_option_str="name"
            ;;
        *) 
            echo -e "${RED}无效选项，使用默认排序方式（按安装日期）${NC}"
            sort_option_str="date"
            choice=1 
            ;;
    esac

    packages_output=$(get_manually_installed_packages "$reference_date_str" "$sort_option_str")
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取软件包列表时发生错误。${NC}" >&2
        return 1
    fi
    
    echo -e "\n${CYAN}========== 手动安装的软件包 (晚于 $reference_date_str) ==========${NC}"
    echo -e "${YELLOW}安装日期        | 软件包名称                | 版本                      | 大小      | 仓库${NC}"
    echo -e "${YELLOW}------------------------------------------------------------------------------------${NC}"
    
    # Use a temporary file for counting to avoid issues with variable scope in pipes
    local temp_packages_file
    temp_packages_file=$(mktemp)
    echo "$packages_output" > "$temp_packages_file"

    if [ ! -s "$temp_packages_file" ]; then
        echo -e "${YELLOW}未找到符合条件的已安装软件包。${NC}"
    else
        # Display formatted packages
        while IFS='|' read -r install_dt pkg_name pkg_ver pkg_sz pkg_repo; do
            # Date is already formatted as YYYY-MM-DD HH:MM:SS by get_manually_installed_packages
            printf "%-17s | %-25s | %-25s | %-9s | %s\n" "$install_dt" "$pkg_name" "$pkg_ver" "$pkg_sz" "$pkg_repo"
        done < "$temp_packages_file"
    fi

    local total=0
    local official=0
    local aur=0

    if [ -s "$temp_packages_file" ]; then
        total=$(wc -l < "$temp_packages_file")
        official=$(grep -c "|Official$" "$temp_packages_file") # Match Official at the end of the line
        aur=$(grep -c "|AUR/Local$" "$temp_packages_file")    # Match AUR/Local at the end
    fi
     
    echo -e "\n${CYAN}========== 统计信息 ==========${NC}"
    echo -e "${GREEN}总共手动安装的软件包 (晚于 $reference_date_str): $total${NC}"
    echo -e "${GREEN}官方仓库软件包: $official${NC}"
    echo -e "${GREEN}AUR/本地软件包: $aur${NC}"
    
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local save_file="$save_dir/package_stats_v4.1_$timestamp.txt"
    local manual_list_file="$save_dir/manual_packages_v4.1_$timestamp.txt"
    
    echo -e "\n${BLUE}正在将统计结果保存到文件: ${CYAN}$save_file${NC}"
    {
        echo "========== 软件包统计 (v4.1) ==========="
        echo "报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "参考日期 (系统安装/首次活动): $reference_date_str"
        echo ""
        echo "========== 手动安装的软件包 (晚于 $reference_date_str) ==========="
        echo "排序方式: $sort_option_str"
        echo "安装日期        | 软件包名称                | 版本                      | 大小      | 仓库"
        echo "------------------------------------------------------------------------------------"
        if [ -s "$temp_packages_file" ]; then
            cat "$temp_packages_file" | while IFS='|' read -r install_dt pkg_name pkg_ver pkg_sz pkg_repo; do
                 printf "%-17s | %-25s | %-25s | %-9s | %s\n" "$install_dt" "$pkg_name" "$pkg_ver" "$pkg_sz" "$pkg_repo"
            done
        else
            echo "未找到符合条件的已安装软件包。"
        fi
        echo ""
        echo "========== 统计信息 ==========="
        echo "总共手动安装的软件包: $total"
        echo "官方仓库软件包: $official"
        echo "AUR/本地软件包: $aur"
    } > "$save_file" # Assumes sudo if writing to /var/log

    if [ $? -eq 0 ]; then
         echo -e "${GREEN}统计结果已成功保存!${NC}"
    else
         echo -e "${RED}错误: 保存统计结果失败。请检查权限。${NC}"
    fi

    echo -e "\n${BLUE}正在创建软件包名称列表文件: ${CYAN}$manual_list_file${NC}"
    if [ -s "$temp_packages_file" ]; then
        awk -F'|' '{print $2}' "$temp_packages_file" > "$manual_list_file" # Assumes sudo
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}软件包名称列表已成功创建!${NC}"
            echo -e "${BLUE}提示: 您可以使用此列表文件进行一键安装，例如:${NC}"
            echo -e "${CYAN}  sudo pacman -S --needed - < $manual_list_file${NC}"
        else
            echo -e "${RED}错误: 创建软件包列表失败。请检查权限。${NC}"
        fi
    else
        echo "" > "$manual_list_file" # Create an empty file
        echo -e "${YELLOW}没有要添加到列表的软件包。${NC}"
    fi

    # Clean up temporary file
    rm -f "$temp_packages_file"
    
    echo -e "\n${CYAN}========== 脚本执行完毕 ===========${NC}"
}

# --- Main Script Execution ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if running as root, as we are writing to /var/log
    # if [[ $EUID -ne 0 ]]; then
    #    echo -e "${RED}请以root权限 (sudo) 运行此脚本，以便写入 /var/log 目录。${NC}"
    #    exit 1
    # fi
    # Decided to let mkdir and file writes fail if not sudo, with error messages,
    # rather than enforcing sudo for the whole script immediately. User can decide.

    echo -e "${CYAN}========== 软件包统计工具 v4.1 ===========${NC}"
    show_package_stats
fi
