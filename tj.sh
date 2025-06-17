#!/bin/bash

# 脚本功能：统计 config/lib/*.sh 中定义的函数被项目中其他 .sh 文件调用的次数

PROJECT_ROOT="."
LIB_DIR="$PROJECT_ROOT/config/lib"

declare -A func_def_files
declare -A func_call_counts

echo "正在扫描 $LIB_DIR 中的函数定义 ..."

# 1. 查找 config/lib/*.sh 文件中定义的所有函数
while IFS= read -r lib_file; do
    # echo "  正在处理库文件: $lib_file" # 可以取消注释以进行调试输出

    mapfile -t extracted_func_names < <( \
        grep -E '^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*\)\s*\{' "$lib_file" | \
        sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*\)\s*\{.*/\2/' \
    )

    for func_name_raw in "${extracted_func_names[@]}"; do
        if [[ -n "$func_name_raw" ]]; then
            func_name=$(echo "$func_name_raw" | tr -d '[:space:]')
            if [[ -z "$func_name" ]]; then
                continue
            fi

            # 只有在第一次遇到函数定义时才打印 "提取到的..."，避免重复
            if [[ -z "${func_def_files[$func_name]}" ]]; then
                echo "      提取到的潜在函数名: '$func_name' (来自 $lib_file)"
                func_def_files["$func_name"]="$lib_file"
                func_call_counts["$func_name"]=0
            
                # 如果需要，可以保留警告重复定义的逻辑，但对于仅用于统计的脚本，可以简化
                # echo "      警告: 函数 '$func_name' 重复定义或已找到 (已在 ${func_def_files[$func_name]} 中定义, 又在 $lib_file 中匹配到). 将使用首次定义."
            fi
        fi
    done

    if [ ${#extracted_func_names[@]} -eq 0 ]; then
         if ! grep -qE '^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*\)\s*\{' "$lib_file"; then
            # echo "    在 $lib_file 中未找到匹配函数定义模式的行." # 可以取消注释以进行调试输出
            : # No-op, or a less verbose message if needed
        fi
    fi

done < <(find "$LIB_DIR" -maxdepth 1 -name "*.sh" -type f)


if [ ${#func_def_files[@]} -eq 0 ]; then
    echo -e "\n在扫描 $LIB_DIR 后未找到任何函数定义. 脚本退出."
    # ... (错误信息)
    exit 1
fi

echo -e "\n共找到 ${#func_def_files[@]} 个唯一的函数进行追踪:"
sorted_found_funcs=($(for func in "${!func_def_files[@]}"; do echo "$func"; done | sort))
for func_name in "${sorted_found_funcs[@]}"; do
    echo "  - $func_name (定义于 ${func_def_files[$func_name]})"
done

echo -e "\n正在扫描项目中的 .sh 文件以统计函数调用次数..."

mapfile -t all_sh_files < <(find "$PROJECT_ROOT" -name "*.sh" -type f)

for func_name in "${!func_def_files[@]}"; do
    for script_to_scan in "${all_sh_files[@]}"; do
        if [[ "$script_to_scan" == "${func_def_files[$func_name]}" ]]; then
            continue
        fi

        call_count_in_file=$(cat "$script_to_scan" | \
            grep -v '^[[:space:]]*#' | \
            grep -vP "^\s*(?:function\s+)?\Q$func_name\E\s*\(\s*\)\s*\{" | \
            grep -oP "\b\Q$func_name\E\b" | \
            wc -l)

        if [[ "$call_count_in_file" -gt 0 ]]; then
            func_call_counts["$func_name"]=$(( ${func_call_counts["$func_name"]} + call_count_in_file ))
        fi
    done
done

echo -e "\n--- 函数调用次数统计 (从高到低排序) ---"
# 4. 准备数据并排序输出
# 创建一个临时数组或直接通过管道处理
# 格式: 调用次数 函数名 (定义于 文件)
# 然后使用 sort -rn 进行数值反向排序
temp_output=()
for func_name in "${!func_call_counts[@]}"; do
    count=${func_call_counts[$func_name]}
    defined_in=${func_def_files[$func_name]}
    # 注意：为了让 sort -n 正确工作，数字应该在字符串的开头
    # 并且为了保持对齐，我们可以在最后用 printf 重新格式化，或者接受 sort 后的原始对齐
    temp_output+=("$(printf "%5d %-45s (定义于 %s)" "$count" "$func_name" "$defined_in")")
done

# 对 temp_output 数组中的内容进行排序
# IFS=$'\n' 是为了处理函数名中可能包含空格的情况 (虽然你的例子中没有)
# sort -rn 会根据行首的数字进行反向数值排序
IFS=$'\n' sorted_output=($(sort -rn <<<"${temp_output[*]}"))
unset IFS

# 打印排序后的结果
for line in "${sorted_output[@]}"; do
    # 由于 sort 可能会改变空格，我们直接打印排序后的行
    # 如果需要严格按照之前的 printf 格式，可以在这里重新解析和 printf，但通常直接打印即可
    echo "$line 次调用" # 在末尾加上 "次调用"
done


echo -e "\n注意: 此脚本通过查找看起来像函数调用的函数名出现次数进行统计."
# ... (末尾提示信息)