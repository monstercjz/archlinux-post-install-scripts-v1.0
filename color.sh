#!/bin/bash

# color.sh - 演示终端颜色和样式组合

# ANSI 转义码前缀
ESC="\033["
# 重置所有属性
RESET="${ESC}0m"

# 定义基本的文本样式
BOLD="${ESC}1m"
DIM="${ESC}2m" # 较少终端支持
ITALIC="${ESC}3m" # 较少终端支持
UNDERLINE="${ESC}4m"
BLINK="${ESC}5m" # 很少使用，通常会禁用
REVERSE="${ESC}7m" # 前景色和背景色互换
HIDDEN="${ESC}8m" # 隐藏文本

# --- 前景色定义 (30-37) ---
BLACK_FG="${ESC}30m"
RED_FG="${ESC}31m"
GREEN_FG="${ESC}32m"
YELLOW_FG="${ESC}33m"
BLUE_FG="${ESC}34m"
MAGENTA_FG="${ESC}35m"
CYAN_FG="${ESC}36m"
WHITE_FG="${ESC}37m"

# --- 亮前景色定义 (90-97) ---
BRIGHT_BLACK_FG="${ESC}90m"
BRIGHT_RED_FG="${ESC}91m"
BRIGHT_GREEN_FG="${ESC}92m"
BRIGHT_YELLOW_FG="${ESC}93m"
BRIGHT_BLUE_FG="${ESC}94m"
BRIGHT_MAGENTA_FG="${ESC}95m"
BRIGHT_CYAN_FG="${ESC}96m"
BRIGHT_WHITE_FG="${ESC}97m"

# --- 背景色定义 (40-47) ---
BLACK_BG="${ESC}40m"
RED_BG="${ESC}41m"
GREEN_BG="${ESC}42m"
YELLOW_BG="${ESC}43m"
BLUE_BG="${ESC}44m"
MAGENTA_BG="${ESC}45m"
CYAN_BG="${ESC}46m"
WHITE_BG="${ESC}47m"

# --- 亮背景色定义 (100-107) ---
BRIGHT_BLACK_BG="${ESC}100m"
BRIGHT_RED_BG="${ESC}101m"
BRIGHT_GREEN_BG="${ESC}102m"
BRIGHT_YELLOW_BG="${ESC}103m"
BRIGHT_BLUE_BG="${ESC}104m"
BRIGHT_MAGENTA_BG="${ESC}105m"
BRIGHT_CYAN_BG="${ESC}106m"
BRIGHT_WHITE_BG="${ESC}107m"

# 清屏
clear

echo -e "${BOLD}--- 终端颜色和样式演示 ---${RESET}\n"
echo -e "说明: 并非所有终端都完全支持所有颜色和样式 (例如，斜体、闪烁或暗色可能不显示)。"
echo -e "      通常，亮色背景可能看起来与标准背景相似，取决于您的终端设置。"
echo -e "-------------------------------------------------------------------\n"

# 1. 基础前景色演示 (黑色背景)
echo -e "${BOLD}1. 基础前景色 (默认黑色背景):${RESET}"
echo -e "${BLACK_FG}黑色文字${RESET}"
echo -e "${RED_FG}红色文字${RESET}"
echo -e "${GREEN_FG}绿色文字${RESET}"
echo -e "${YELLOW_FG}黄色文字${RESET}"
echo -e "${BLUE_FG}蓝色文字${RESET}"
echo -e "${MAGENTA_FG}品红色文字${RESET}"
echo -e "${CYAN_FG}青色文字${RESET}"
echo -e "${WHITE_FG}白色文字${RESET}\n"

# 2. 基础背景色演示 (白色前景)
echo -e "${BOLD}2. 基础背景色 (白色前景):${RESET}"
echo -e "${BLACK_BG}${WHITE_FG}  黑色背景  ${RESET}"
echo -e "${RED_BG}${WHITE_FG}  红色背景  ${RESET}"
echo -e "${GREEN_BG}${WHITE_FG}  绿色背景  ${RESET}"
echo -e "${YELLOW_BG}${WHITE_FG}  黄色背景  ${RESET}"
echo -e "${BLUE_BG}${WHITE_FG}  蓝色背景  ${RESET}"
echo -e "${MAGENTA_BG}${WHITE_FG}  品红色背景  ${RESET}"
echo -e "${CYAN_BG}${WHITE_FG}  青色背景  ${RESET}"
echo -e "${WHITE_BG}${BLACK_FG}  白色背景  ${RESET}\n" # 白色背景用黑色字显示

# 3. 亮前景色演示 (黑色背景)
echo -e "${BOLD}3. 亮前景色 (默认黑色背景):${RESET}"
echo -e "${BRIGHT_BLACK_FG}亮黑色文字${RESET}"
echo -e "${BRIGHT_RED_FG}亮红色文字${RESET}"
echo -e "${BRIGHT_GREEN_FG}亮绿色文字${RESET}"
echo -e "${BRIGHT_YELLOW_FG}亮黄色文字${RESET}"
echo -e "${BRIGHT_BLUE_FG}亮蓝色文字${RESET}"
echo -e "${BRIGHT_MAGENTA_FG}亮品红色文字${RESET}"
echo -e "${BRIGHT_CYAN_FG}亮青色文字${RESET}"
echo -e "${BRIGHT_WHITE_FG}亮白色文字${RESET}\n"

# 4. 亮背景色演示 (白色前景)
echo -e "${BOLD}4. 亮背景色 (白色前景):${RESET}"
echo -e "${BRIGHT_BLACK_BG}${WHITE_FG}  亮黑色背景  ${RESET}"
echo -e "${BRIGHT_RED_BG}${WHITE_FG}  亮红色背景  ${RESET}"
echo -e "${BRIGHT_GREEN_BG}${WHITE_FG}  亮绿色背景  ${RESET}"
echo -e "${BRIGHT_YELLOW_BG}${WHITE_FG}  亮黄色背景  ${RESET}"
echo -e "${BRIGHT_BLUE_BG}${WHITE_FG}  亮蓝色背景  ${RESET}"
echo -e "${BRIGHT_MAGENTA_BG}${WHITE_FG}  亮品红色背景  ${RESET}"
echo -e "${BRIGHT_CYAN_BG}${WHITE_FG}  亮青色背景  ${RESET}"
echo -e "${BRIGHT_WHITE_BG}${BLACK_FG}  亮白色背景  ${RESET}\n"

# 5. 常见样式组合
echo -e "${BOLD}5. 常见文本样式:${RESET}"
echo -e "${BOLD}粗体文字${RESET}"
echo -e "${DIM}暗色文字 (可能不显示)${RESET}"
echo -e "${ITALIC}斜体文字 (可能不显示)${RESET}"
echo -e "${UNDERLINE}下划线文字${RESET}"
echo -e "${BLINK}闪烁文字 (可能不显示或被忽略)${RESET}"
echo -e "${REVERSE}反转颜色 (前景变背景，背景变前景)${RESET}"
echo -e "${HIDDEN}隐藏文字 (看不到，但它在那里)${RESET}"
echo -e "${BOLD}${UNDERLINE}粗体和下划线文字${RESET}"
echo -e "${RED_FG}${BOLD}粗体红色文字${RESET}"
echo -e "${YELLOW_BG}${BLACK_FG}${UNDERLINE}下划线黑色文字在黄色背景上${RESET}\n"

# 6. 组合演示: 遍历所有基础前景和背景色
echo -e "${BOLD}6. 所有标准前景色与所有标准背景色组合:${RESET}"
echo -e "   (格式: [前景色码;背景色码] 示例文字)\n"

# 遍历所有背景色 (40-47)
for bg_code in {40..47}; do
    printf "  BG %-3s: " "${bg_code}"
    # 遍历所有前景色 (30-37)
    for fg_code in {30..37}; do
        # 针对白色背景，使用黑色前景，避免看不清
        if [ "$bg_code" -eq 47 ]; then # 白色背景
            current_fg="30" # 黑色前景
        else
            current_fg="$fg_code"
        fi
        echo -en "${ESC}${current_fg};${bg_code}m [${fg_code};${bg_code}] Example ${RESET}"
    done
    echo -e "\n"
done

echo -e "\n${BOLD}7. 所有亮前景色与所有亮背景色组合:${RESET}"
echo -e "   (格式: [前景色码;背景色码] 示例文字)\n"

# 遍历所有亮背景色 (100-107)
for bg_code in {100..107}; do
    printf "  BG %-3s: " "${bg_code}"
    # 遍历所有亮前景色 (90-97)
    for fg_code in {90..97}; do
        # 针对亮白色背景，使用亮黑色前景，避免看不清
        if [ "$bg_code" -eq 107 ]; then # 亮白色背景
            current_fg="90" # 亮黑色前景
        else
            current_fg="$fg_code"
        fi
        echo -en "${ESC}${current_fg};${bg_code}m [${fg_code};${bg_code}] Example ${RESET}"
    done
    echo -e "\n"
done

echo -e "\n${BOLD}--- 演示结束 ---${RESET}"
echo -e "您可以通过修改脚本中的颜色代码来探索更多组合。"
echo -e "例如，${ESC}38;5;208m256色${RESET}或${ESC}38;2;255;0;0m真彩色${RESET}需要更复杂的代码。"
echo -e "-------------------------------------------------------------------\n"