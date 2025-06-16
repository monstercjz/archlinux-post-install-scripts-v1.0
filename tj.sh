#!/bin/bash

# count_lib_function_calls.sh
# Description: Counts the number of times functions defined in lib/ a
#              directory are called in other .sh files within the project.

# 严格模式
set -euo pipefail

# 项目根目录 (假设脚本在根目录运行)
PROJECT_ROOT="." 
LIB_DIR="${PROJECT_ROOT}/config/lib"

# 存储函数名及其调用次数的关联数组
declare -A function_counts

# --- 步骤 1: 获取 lib/ 目录下所有 .sh 文件中定义的函数名 ---
echo "INFO: Gathering function definitions from ${LIB_DIR} ..."
defined_functions=() # 初始化为空数组
declare -A seen_functions_for_definition # 用于确保函数只被添加一次（基于函数名）

# 使用一个循环来处理 find 的输出，并在主 shell 中处理每个文件
# find ... -print0 和 read -d $'\0' 用于安全处理可能包含特殊字符的文件名
while IFS= read -r -d $'\0' lib_file_path; do
    lib_filename=$(basename "$lib_file_path")
    echo "  Processing lib file: $lib_filename"
    
    # 从每个 lib 文件中提取函数名
    # 模式：匹配 "function_name () {" 或 "function function_name () {"
    # sed：移除 "function " 前缀和 "() {..." 后缀，得到函数名
    # grep -Ev '^_'：排除以 "_" 开头的函数名（通常视为内部/私有）
    # || true：确保即使 grep 链没有输出（例如文件为空或所有函数都以下划线开头），
    #          整个命令替换也不会因 set -e 或 pipefail 而中止脚本。
    while IFS= read -r func_name; do
        if [[ -n "$func_name" ]]; then # 确保 func_name 非空
            # 使用关联数组检查函数是否已被定义，比遍历普通数组高效
            if [[ -z "${seen_functions_for_definition[$func_name]}" ]]; then
                defined_functions+=("$func_name")
                function_counts["$func_name"]=0 # 初始化调用次数为0
                seen_functions_for_definition["$func_name"]=1 # 标记此函数名已处理
                echo "    Found unique function definition: $func_name"
            fi
        fi
    done < <(grep -E '^[a-zA-Z0-9_][a-zA-Z0-9_[:space:]]*\s*\(\s*\)\s*\{|^function\s+[a-zA-Z0-9_][a-zA-Z0-9_[:space:]]*\s*\(\s*\)\s*\{' "$lib_file_path" | \
             sed -E 's/^[[:space:]]*function[[:space:]]+//; s/\s*\(\s*\)\s*\{.*//; s/[[:space:]]*$//' | \
             grep -Ev '^_' || true)

done < <(find "$LIB_DIR" -type f -name "*.sh" -print0 2>/dev/null) # 2>/dev/null 抑制 find 在 LIB_DIR 不存在时的错误

# 检查是否找到了任何函数定义
if [ ${#defined_functions[@]} -eq 0 ]; then
    echo "ERROR: No valid functions (or an error occurred during discovery) found in ${LIB_DIR}. Exiting."
    exit 1
fi
echo "INFO: Total unique function definitions found in lib/: ${#defined_functions[@]}"
# 可选的调试输出，查看所有找到的函数名：
# echo "DEBUG: List of defined functions: ${defined_functions[*]}"
echo "--------------------------------------------------"


# --- 步骤 2 & 3: 遍历项目中所有其他 .sh 文件，并搜索函数调用 ---
echo "INFO: Searching for function calls in other project .sh files..."

# 查找所有 .sh 文件，排除 lib 目录自身，也排除本统计脚本
# 使用 -print0 和 read -d $'\0' 保证文件名安全
find "$PROJECT_ROOT" -type f -name "*.sh" \
    ! -path "${LIB_DIR}/*" \
    ! -name "$(basename "$0")" \
    -print0 | \
while IFS= read -r -d $'\0' target_file_path; do
    target_filename=$(basename "$target_file_path")
    # 移除 PROJECT_ROOT 前缀以获得相对路径，使输出更简洁
    relative_target_path="${target_file_path#${PROJECT_ROOT}/}" 
    echo "  Scanning file: $relative_target_path"
    
    for func_to_find in "${defined_functions[@]}"; do
        # 搜索函数调用：
        #   \b${func_to_find}\b : 匹配作为独立单词的函数名
        #   grep -Ev "..."     : 排除掉函数定义和注释行中的匹配
        #
        # 这个 grep 链的目的是：
        # 1. `grep -Eo "\b${func_to_find}\b"`: 找出所有作为独立单词出现的函数名。
        # 2. `grep -Ev "^\s*#.*\b${func_to_find}\b"`: 排除掉那些在注释行中找到的。
        # 3. `grep -Ev "^\s*function\s+${func_to_find}\b|^\s*${func_to_find}\s*\(\s*\)\s*\{"`: 排除掉函数定义本身。
        #
        # `|| true` 确保即使某个 grep 步骤没有匹配（例如，文件不包含该函数），
        # `wc -l` 也能正确得到 0，并且不会因 set -e 或 pipefail 中止。
        count=$( (grep -Eo "\b${func_to_find}\b" "$target_file_path" || true) | \
                 (grep -Ev "^\s*#.*\b${func_to_find}\b" || true) | \
                 (grep -Ev "^\s*function\s+${func_to_find}\b|^\s*${func_to_find}\s*\(\s*\)\s*\{" || true) | \
                 wc -l)
        
        # 如果 wc -l 意外失败或输出非数字，进行简单校验
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "    WARN: Could not determine count for '$func_to_find' in '$target_filename'. Assuming 0."
            count=0
        fi

        if [[ "$count" -gt 0 ]]; then
            # log_msg DEBUG "    Found '$func_to_find' $count time(s) in $target_filename" # 可选调试
            function_counts["$func_to_find"]=$((function_counts["$func_to_find"] + count))
        fi
    done
done

echo "--------------------------------------------------"
echo "INFO: Function call counts from lib/ directory (sorted by call count desc):"
printf "%-45s %s\n" "Function Name" "Call Count"
printf "%-45s %s\n" "---------------------------------------------" "----------"

# 按调用次数排序输出 (降序)
# 将关联数组转换为可排序的格式 (每行: count func_name)
sorted_output_lines=()
for func_name_out in "${!function_counts[@]}"; do
    sorted_output_lines+=("${function_counts[$func_name_out]} $func_name_out")
done

# 排序并打印
if [[ ${#sorted_output_lines[@]} -gt 0 ]]; then
    printf '%s\n' "${sorted_output_lines[@]}" | sort -k1,1nr -k2,2 | while IFS=' ' read -r count_val name_val; do
        printf "%-45s %s\n" "$name_val" "$count_val"
    done
else
    echo "No function calls were counted." # 如果没有任何函数被调用
fi

echo "--------------------------------------------------"
echo "INFO: Scan complete."