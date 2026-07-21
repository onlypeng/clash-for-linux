#!/bin/sh
# clashtool_tui.sh - TUI module for clashtool
# This file is sourced by clashtool.sh - do not execute directly
# Contains all TUI-related functions: menu rendering, key reading,
# proxy selection UI, and interactive menu navigation.

# === TUI constants (part 1) ===
# ==================== TUI Configuration ====================
TUI_ENABLED=false
# 检测当前是否支持交互式终端操作（stty + /dev/tty）
# 用于 tui_clear/pause_prompt/get_input/tui_confirm 等函数判断模式

# === TUI constants (part 2) ===
TUI_HIGHLIGHT_INVERT="\033[7m"
# 使用 printf 在运行时生成 UTF-8 箭头字符 ▶ (U+25B6)
TUI_ARROW=$(printf '\342\226\266')
TUI_ARROW_FALLBACK=">"
TUI_KEY=""
MENU_RESULT=""
TUI_CONFIRM_RESULT=""
TUI_INPUT_RESULT=""
GET_INPUT_RESULT=""

# === Menu border constants ===
# Used for menu rendering, defined here to keep TUI self-contained
MENU_BORDER_TOP="╔════════════════════════════════════════════════════════════╗"
MENU_BORDER_MID="╠════════════════════════════════════════════════════════════╣"
MENU_BORDER_BOT="╚════════════════════════════════════════════════════════════╝"
MENU_LINE="║"
MENU_CONTENT_WIDTH=78
MENU_RIGHT_COL=80

# === Menu messages (defaults, overridden by i18n) ===
menu_return="[Esc] Return to Previous Menu"
menu_exit="[Ctrl+C] Exit"
menu_invalid_choice="Invalid choice! Please try again."

# === TUI interaction prompts (defaults, overridden by i18n) ===
tui_confirm_prompt_msg="  [Y] Yes   [N] No   (default N): "
tui_input_skip_hint_msg="  [Enter] Skip  [Esc] Cancel"
tui_input_cancel_hint_msg="  [Esc] Cancel"
tui_press_any_key_msg="  Press any key to continue..."
tui_press_enter_msg="Press Enter to continue..."
tui_status_on_label="[ON]"
tui_status_off_label="[OFF]"
tui_status_na_root_label="[N/A - need root]"
tui_unavailable_msg="TUI mode unavailable. Missing dependencies or non-interactive terminal."
tui_use_cli_hint_msg="Please install required dependencies or use command line mode:"

# === TUI detection and rendering ===
# ==================== TUI 基础组件 ====================

# 检测终端是否支持 TUI 模式
# 综合检测：交互式终端 + stty 可用 + /dev/tty 可用
tui_detect_capability() {
    # 必须有 stty 命令
    if ! command -v stty >/dev/null 2>&1; then
        TUI_ENABLED=false
        return 1
    fi
    # 必须是交互式终端（stdin 是 TTY 或 /dev/tty 可用）
    if ! is_interactive_shell; then
        TUI_ENABLED=false
        return 1
    fi
    # /dev/tty 必须可读写（TUI 按键读取需要）
    if ! [ -c /dev/tty ] 2>/dev/null; then
        TUI_ENABLED=false
        return 1
    fi
    # 测试 stty 是否能正常工作
    if ! stty -g >/dev/null 2>&1; then
        TUI_ENABLED=false
        return 1
    fi
    TUI_ENABLED=true
    return 0
}

# 获取选中标记（根据终端编码能力）
tui_get_arrow() {
    # 检查 LC_ALL > LC_CTYPE > LANG 的优先级
    _ga_lc="${LC_ALL:-${LC_CTYPE:-$LANG}}"
    case "$_ga_lc" in
        *UTF-8*|*utf-8*|*UTF8*|*utf8*)
            printf "%s" "$TUI_ARROW"
            ;;
        *)
            printf "%s" "$TUI_ARROW_FALLBACK"
            ;;
    esac
}

# 读取单个按键（原始模式）
# 前提：调用前必须已设置 stty 原始模式（由 tui_menu_select 管理）
# 输出：通过全局变量 TUI_KEY 返回按键名称
tui_read_key() {
    # 直接将 dd 管道到 od，避免 $(...) 剥离换行符导致 Enter 键丢失
    _trk_code=$(dd bs=1 count=1 </dev/tty 2>/dev/null | od -An -to1 | tr -d ' \n')

    case "$_trk_code" in
        '')
            TUI_KEY=""
            ;;
        033)
            # ESC - 可能是 ESC 键或转义序列的开始
            # 切换到非阻塞模式读取后续字节 (min 0 = 不阻塞, time 1 = 100ms 超时)
            stty -echo -icanon onlcr min 0 time 1 </dev/tty 2>/dev/null
            # 只读2个字节（覆盖常见的方向键序列 ESC[A 等）
            _trk_rest=$(dd bs=1 count=2 </dev/tty 2>/dev/null)
            # 恢复阻塞模式
            stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null

            if [ -z "$_trk_rest" ]; then
                # 没有后续字节，是真正的 ESC 键
                TUI_KEY="ESC"
            else
                # 解析转义序列
                case "$_trk_rest" in
                    '[A') TUI_KEY="UP" ;;
                    '[B') TUI_KEY="DOWN" ;;
                    '[C') TUI_KEY="RIGHT" ;;
                    '[D') TUI_KEY="LEFT" ;;
                    '[H') TUI_KEY="HOME" ;;
                    '[F') TUI_KEY="END" ;;
                    'OH') TUI_KEY="HOME" ;;
                    'OF') TUI_KEY="END" ;;
                    '[1'|'[4'|'[5'|'[6')
                        # 需要读取第3个字节 (~)
                        stty -echo -icanon onlcr min 0 time 1 </dev/tty 2>/dev/null
                        _trk_c4=$(dd bs=1 count=1 </dev/tty 2>/dev/null)
                        stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null
                        _trk_rest="${_trk_rest}${_trk_c4}"
                        case "$_trk_rest" in
                            '[1~') TUI_KEY="HOME" ;;
                            '[4~') TUI_KEY="END" ;;
                            '[5~') TUI_KEY="PGUP" ;;
                            '[6~') TUI_KEY="PGDN" ;;
                            *) TUI_KEY="" ;;  # 未知序列，忽略不退出
                        esac
                        ;;
                    *)
                        # 未知序列，忽略（不当作ESC，避免误退出）
                        TUI_KEY=""
                        ;;
                esac
            fi
            ;;
        012|015) TUI_KEY="ENTER" ;;
        011) TUI_KEY="TAB" ;;
        0177|010) TUI_KEY="BACKSPACE" ;;
        003) TUI_KEY="CTRL_C" ;;
        021) TUI_KEY="CTRL_Q" ;;
        022) TUI_KEY="CTRL_R" ;;
        025) TUI_KEY="CTRL_U" ;;
        027) TUI_KEY="CTRL_W" ;;
        *)
            TUI_KEY=$(printf "\\$_trk_code" 2>/dev/null)
            ;;
    esac
}

# 计算字符串的终端显示宽度（CJK字符占2列）
# 基于 UTF-8 字节模式分析，不依赖 locale 设置
str_display_width() {
    # 使用 %b 将字面量 \033 转换为真正的 ESC 字符，以便 sed 正确去除 ANSI 颜色代码
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g' | od -An -tu1 | awk '
    {
        for (i = 1; i <= NF; i++) {
            b = $i + 0
            if (b >= 240) width += 2      # 4字节字符 (emoji等)
            else if (b >= 224) width += 2  # 3字节字符 (CJK)
            else if (b >= 192) width += 1  # 2字节字符 (拉丁扩展)
            else if (b < 128) width += 1   # ASCII
            # 0x80-0xBF 是 UTF-8 续字节，不计数
        }
    }
    END { printf "%d", width + 0 }
    '
}

tui_draw_menu() {
    _tdm_title="$1"
    _tdm_selected="$2"
    _tdm_total="$3"
    shift 3
    _tdm_i=0
    _tdm_arrow=$(tui_get_arrow)

    # 隐藏光标 + 移动到左上角，不清屏（避免闪烁和光标残影）
    printf "\033[?25l\033[H"

    # 标题栏
    printf "%b" "${COLOR_CYAN}${COLOR_BOLD}"
    printf "%s\033[K\n" "$MENU_BORDER_TOP"
    _tw=$(str_display_width "$_tdm_title")
    _tp=$(( MENU_CONTENT_WIDTH - _tw ))
    [ "$_tp" -lt 0 ] && _tp=0
    _tpl=$(( _tp / 2 ))
    printf "%s" "$MENU_LINE"
    [ "$_tpl" -gt 0 ] && printf "%${_tpl}s" ""
    printf "%b" "$_tdm_title"
    _trp=$(( _tp - _tpl ))
    [ "$_trp" -gt 0 ] && printf "%${_trp}s" ""
    printf "%b\n" "\033[${MENU_RIGHT_COL}G${MENU_LINE}\033[K"
    printf "%s\033[K\n" "$MENU_BORDER_MID"
    printf "%b" "${COLOR_RESET}"

    # 菜单项
    for _tdm_item in "$@"; do
        if [ "$_tdm_i" -eq "$_tdm_selected" ]; then
            # 选中项：反色 + 箭头标记（不使用 COLOR_RESET 以避免中断反色效果）
            _tdm_prefix="${TUI_HIGHLIGHT_INVERT}${COLOR_CYAN}${_tdm_arrow} ${TUI_HIGHLIGHT_INVERT}"
            _tdm_item_color="${COLOR_BOLD}${COLOR_WHITE}"
            _tdm_pad_offset=0
        else
            _tdm_prefix="  "
            _tdm_item_color="$COLOR_WHITE"
            _tdm_pad_offset=0
        fi
        printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
        printf "%b" "${_tdm_prefix}${_tdm_item_color}${_tdm_item}${COLOR_RESET}"
        # 计算填充宽度：内容总宽 = prefix(2) + item(_iw) + padding = MENU_CONTENT_WIDTH
        _iw=$(str_display_width "$_tdm_item")
        _pad=$(( MENU_CONTENT_WIDTH - _iw - 2 + _tdm_pad_offset ))
        [ "$_pad" -lt 0 ] && _pad=0
        printf "%${_pad}s" ""
        printf "%b\n" "\033[${MENU_RIGHT_COL}G${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}\033[K"
        _tdm_i=$((_tdm_i + 1))
    done

    # 状态栏
    printf "%b" "${COLOR_CYAN}"
    printf "%s\033[K\n" "$MENU_BORDER_MID"
    if $clash_is_running; then
        _tdm_status=" [RUNNING] Clash PID: ${clash_pid:-N/A}"
    else
        _tdm_status=" [STOPPED] Clash not running"
    fi
    printf "%s%s" "$MENU_LINE" "$_tdm_status"
    _sw=$(str_display_width "$_tdm_status")
    _spad=$(( MENU_CONTENT_WIDTH - _sw ))
    [ "$_spad" -lt 0 ] && _spad=0
    printf "%${_spad}s" ""
    printf "%b\n" "\033[${MENU_RIGHT_COL}G${MENU_LINE}\033[K"
    printf "%s\033[K\n" "$MENU_BORDER_BOT"
    printf "%b" "${COLOR_RESET}"

    # 清除屏幕剩余内容（如果新内容比旧内容短）
    printf "\033[J"
}

# 结果通过全局变量 MENU_RESULT 返回
tui_menu_select() {
    _tms_title="$1"
    shift
    _tms_total=$#
    # 恢复上次选中位置（按菜单标题存储）
    _tms_selected=0
    _tms_key="_TMS_LAST_$(printf '%s' "$_tms_title" | tr -c 'a-zA-Z0-9' '_')"
    eval "_tms_saved=\"\${$_tms_key:-0}\""
    if [ "$_tms_saved" -ge 0 ] && [ "$_tms_saved" -lt "$_tms_total" ] 2>/dev/null; then
        _tms_selected="$_tms_saved"
    fi

    # 保存终端状态（明确操作 /dev/tty，与 dd 读取一致）
    _tms_old_tty=$(stty -g </dev/tty 2>/dev/null)
    # 设置原始模式：无回显、按字符读取（明确应用到 /dev/tty）
    stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null
    # Ctrl+C 时恢复终端并返回 QUIT（而非 exit，避免整个脚本退出）
    _tms_interrupted=false
    trap '_tms_interrupted=true' INT

    # 进入菜单前清屏一次，清除之前命令输出的残留
    printf "\033[2J"

    while true; do
        # 检查是否被中断
        if [ "$_tms_interrupted" = "true" ]; then
            MENU_RESULT="QUIT"
            break
        fi

        # 刷新Clash运行状态，确保状态栏准确
        refresh_status
        tui_draw_menu "$_tms_title" "$_tms_selected" "$_tms_total" "$@"
        tui_read_key

        case "$TUI_KEY" in
            UP|k)
                _tms_selected=$((_tms_selected - 1))
                [ "$_tms_selected" -lt 0 ] && _tms_selected=$((_tms_total - 1))
                ;;
            DOWN|j)
                _tms_selected=$((_tms_selected + 1))
                [ "$_tms_selected" -ge "$_tms_total" ] && _tms_selected=0
                ;;
            CTRL_C|CTRL_Q)
                MENU_RESULT="QUIT"
                break
                ;;
            ENTER)
                MENU_RESULT="$_tms_selected"
                break
                ;;
            ESC)
                MENU_RESULT="BACK"
                break
                ;;
            [0-9])
                _tms_idx=$((TUI_KEY + 0))
                if [ "$_tms_idx" -ge 0 ] && [ "$_tms_idx" -lt "$_tms_total" ]; then
                    MENU_RESULT="$_tms_idx"
                    break
                fi
                ;;
            HOME) _tms_selected=0 ;;
            END) _tms_selected=$((_tms_total - 1)) ;;
            PGUP)
                _tms_selected=$((_tms_selected - 5))
                [ "$_tms_selected" -lt 0 ] && _tms_selected=0
                ;;
            PGDN)
                _tms_selected=$((_tms_selected + 5))
                [ "$_tms_selected" -ge "$_tms_total" ] && _tms_selected=$((_tms_total - 1))
                ;;
            [a-z])
                # 字母键映射为数字快捷键：a=10, b=11, c=12, ...
                _tms_idx=$(printf '%d' "'$TUI_KEY")
                _tms_idx=$((_tms_idx - 97 + 10))
                if [ "$_tms_idx" -ge 0 ] && [ "$_tms_idx" -lt "$_tms_total" ]; then
                    MENU_RESULT="$_tms_idx"
                    break
                fi
                ;;
            [A-Z])
                # 大写字母键映射为数字快捷键：A=10, B=11, C=12, ...
                _tms_idx=$(printf '%d' "'$TUI_KEY")
                _tms_idx=$((_tms_idx - 65 + 10))
                if [ "$_tms_idx" -ge 0 ] && [ "$_tms_idx" -lt "$_tms_total" ]; then
                    MENU_RESULT="$_tms_idx"
                    break
                fi
                ;;
            *) ;;
        esac
    done

    # 保存当前选中位置（按菜单标题存储，返回时恢复）
    case "$MENU_RESULT" in
        BACK) ;;
        QUIT) ;;
        *) eval "$_tms_key=$_tms_selected" ;;
    esac

    # 恢复终端状态（明确操作 /dev/tty）
    stty "$_tms_old_tty" </dev/tty 2>/dev/null
    # 恢复光标显示
    printf "\033[?25h"
    trap - INT
    return 0
}

# TUI 确认对话框
tui_confirm() {
    _tc_msg="$1"
    _tc_old_tty=$(stty -g </dev/tty 2>/dev/null)
    stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null
    _tc_interrupted=false
    trap '_tc_interrupted=true' INT

    while true; do
        if [ "$_tc_interrupted" = "true" ]; then
            TUI_CONFIRM_RESULT="NO"
            break
        fi
        # 清屏并定位到左上角（避免旧菜单内容残留）
        printf "\033[2J\033[H"
        printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_TOP}${COLOR_RESET}\033[K"
        printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
        _mw=$(str_display_width "$_tc_msg")
        _mp=$(( MENU_CONTENT_WIDTH - _mw ))
        [ "$_mp" -lt 0 ] && _mp=0
        _mpl=$(( _mp / 2 ))
        [ "$_mpl" -gt 0 ] && printf "%${_mpl}s" ""
        printf "%b" "${COLOR_YELLOW}${COLOR_BOLD}${_tc_msg}${COLOR_RESET}"
        printf "%b\n" "\033[${MENU_RIGHT_COL}G${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}\033[K"
        printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_BOT}${COLOR_RESET}\033[K"
        # 清除下方残留内容
        printf "\033[J"
        printf "%b" "${COLOR_YELLOW}  [Y] Yes   [N] No   (default N): ${COLOR_RESET}"

        tui_read_key
        case "$TUI_KEY" in
            y|Y|ENTER) TUI_CONFIRM_RESULT="YES"; break ;;
            n|N|q|Q|ESC|CTRL_C) TUI_CONFIRM_RESULT="NO"; break ;;
            *) ;;
        esac
    done

    stty "$_tc_old_tty" </dev/tty 2>/dev/null
    trap - INT
    return 0
}

# TUI 输入框
tui_input() {
    _ti_prompt="$1"
    _ti_default="${2:-}"
    _ti_allow_empty="${3:-false}"
    TUI_INPUT_CANCELED=false

    # 保存终端状态
    _ti_old_tty=$(stty -g </dev/tty 2>/dev/null)
    _ti_interrupted=false
    trap '_ti_interrupted=true' INT

    # 清屏并定位到左上角（避免旧菜单内容残留），每行末尾用 \033[K 清除残留
    printf "\033[2J\033[H"
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_TOP}${COLOR_RESET}\033[K"
    # 提示：ESC 取消输入，允许空输入时显示 Enter 跳过
    printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
    if [ "$_ti_allow_empty" = "true" ]; then
        _esc_hint="  [Enter] Skip  [Esc] Cancel"
    else
        _esc_hint="  [Esc] Cancel"
    fi
    printf " %s" "$_esc_hint"
    _ehw=$(str_display_width "$_esc_hint")
    _ehp=$(( MENU_CONTENT_WIDTH - _ehw - 3 ))
    [ "$_ehp" -lt 0 ] && _ehp=0
    printf "%${_ehp}s" ""
    printf "%b\n" "\033[${MENU_RIGHT_COL}G${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}\033[K"
    # 合并提示和默认值到一行，减少表单高度
    if [ -n "$_ti_default" ]; then
        _ti_full_prompt="${_ti_prompt} (${_ti_default})"
    else
        _ti_full_prompt="$_ti_prompt"
    fi
    printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
    _pw=$(str_display_width "$_ti_full_prompt")
    _pp=$(( MENU_CONTENT_WIDTH - _pw - 3 ))
    [ "$_pp" -lt 0 ] && _pp=0
    printf " %s" "$_ti_full_prompt"
    printf "%${_pp}s" ""
    printf "%b\n" "\033[${MENU_RIGHT_COL}G${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}\033[K"
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_BOT}${COLOR_RESET}\033[K"
    # 清除下方残留内容
    printf "\033[J"

    # 使用原始模式逐字符读取，检测 ESC 键
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
    printf "%b" "${COLOR_GREEN}> ${COLOR_RESET}"
    _ti_buf=""

    while true; do
        _ti_ch=$(dd bs=1 count=1 2>/dev/null </dev/tty)
        [ -z "$_ti_ch" ] && continue

        _ti_ch_val=$(printf '%d' "'$_ti_ch" 2>/dev/null || echo 0)

        case "$_ti_ch_val" in
            27)
                _ti_old_tout=$(stty -g </dev/tty 2>/dev/null)
                stty -echo -icanon min 0 time 1 </dev/tty 2>/dev/null
                _ti_next=$(dd bs=1 count=6 2>/dev/null </dev/tty)
                stty "$_ti_old_tout" </dev/tty 2>/dev/null
                if [ -z "$_ti_next" ]; then
                    TUI_INPUT_CANCELED=true
                    TUI_INPUT_RESULT=""
                    printf "\n"
                    stty "$_ti_old_tty" </dev/tty 2>/dev/null
                    trap - INT
                    return 1
                fi
                continue
                ;;
            10|13)
                printf "\n"
                break
                ;;
            3)
                TUI_INPUT_CANCELED=true
                TUI_INPUT_RESULT=""
                printf "\n"
                stty "$_ti_old_tty" </dev/tty 2>/dev/null
                trap - INT
                return 1
                ;;
            8|127)
                if [ -n "$_ti_buf" ]; then
                    _ti_buf=$(printf '%s' "$_ti_buf" | sed 's/.$//')
                    printf '\b \b'
                fi
                continue
                ;;
        esac

        if [ "$_ti_ch_val" -ge 32 ] 2>/dev/null; then
            _ti_buf="${_ti_buf}${_ti_ch}"
            printf '%s' "$_ti_ch"
        fi
    done

    if [ "$_ti_allow_empty" = "true" ]; then
        TUI_INPUT_RESULT="$_ti_buf"
    else
        [ -z "$_ti_buf" ] && _ti_buf="$_ti_default"
        TUI_INPUT_RESULT="$_ti_buf"
    fi

    # 恢复原始终端状态
    stty "$_ti_old_tty" </dev/tty 2>/dev/null
    trap - INT
    return 0
}

# TUI 消息框
tui_message() {
    _tm_msg="$1"
    _tm_old_tty=$(stty -g </dev/tty 2>/dev/null)
    stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null
    _tm_interrupted=false
    trap '_tm_interrupted=true' INT

    # 清屏并定位到左上角（避免旧菜单内容残留）
    printf "\033[2J\033[H"
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_TOP}${COLOR_RESET}\033[K"
    echo "$_tm_msg" | while IFS= read -r line; do
        printf "%b" "${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}"
        _lw=$(str_display_width "$line")
        _lp=$(( MENU_CONTENT_WIDTH - _lw ))
        [ "$_lp" -lt 0 ] && _lp=0
        printf "%s%${_lp}s" "$line" ""
        printf "%b\n" "\033[${MENU_RIGHT_COL}G${COLOR_CYAN}${MENU_LINE}${COLOR_RESET}\033[K"
    done
    printf "%b\n" "${COLOR_CYAN}${MENU_BORDER_BOT}${COLOR_RESET}\033[K"
    # 清除下方残留内容
    printf "\033[J"
    printf "%b" "${COLOR_YELLOW}  Press any key to continue...${COLOR_RESET}"
    tui_read_key

    stty "$_tm_old_tty" </dev/tty 2>/dev/null
    trap - INT
    return 0
}

# TUI 暂停提示
tui_pause() {
    _tp_old_tty=$(stty -g </dev/tty 2>/dev/null)
    stty -echo -icanon onlcr min 1 time 0 </dev/tty 2>/dev/null
    _tp_interrupted=false
    trap '_tp_interrupted=true' INT

    # 不清屏，保留函数输出；只打印提示并等待按键
    printf "\n%b" "${COLOR_YELLOW}${tui_press_any_key_msg}${COLOR_RESET}\033[K\n"
    # 清除下方残留内容
    printf "\033[J"
    tui_read_key

    stty "$_tp_old_tty" </dev/tty 2>/dev/null
    trap - INT
    return 0
}

# 结果通过全局变量 MENU_RESULT 返回
menu_dispatch() {
    _md_title="$1"
    shift
    MENU_RESULT=""
    _md_total=$#

    # 尝试交互式菜单（支持上下导航、高亮选择、快捷键）
    # 需同时满足：/dev/tty 可用（stty 原始模式）且 stdout 是 TTY
    # 当 stdout 被重定向（如命令替换 $(...)、管道），TUI 绘制无法正常工作，
    # 直接报错，不再回退到非交互模式
    _md_interactive=false
    if _is_interactive_terminal && [ -t 1 ]; then
        _md_interactive=true
    fi

    if [ "$_md_interactive" = "true" ]; then
        # 交互式菜单模式（TUI 风格，支持导航和高亮）
        tui_menu_select "$_md_title" "$@"
        # 将数字索引转换为 BACK/QUIT 语义
        case "$MENU_RESULT" in
            ''|*[!0-9]*)
                # 非数字（QUIT/BACK/INVALID 等），直接使用
                ;;
            *)
                # 数字索引：查找对应的菜单项
                _md_idx=0
                _md_item=""
                for _md_item in "$@"; do
                    [ "$_md_idx" = "$MENU_RESULT" ] && break
                    _md_idx=$((_md_idx + 1))
                done
                # 检查是否为"返回"或"退出"项
                if [ "$_md_item" = "$menu_return" ]; then
                    MENU_RESULT="BACK"
                elif [ "$_md_item" = "$menu_exit" ]; then
                    MENU_RESULT="QUIT"
                fi
                ;;
        esac
    else
        # 非交互式终端：直接报错，不再回退到 show_menu
        printf "%b\n" "${COLOR_RED}$tui_unavailable_msg${COLOR_RESET}"
        printf "%b\n" "${COLOR_YELLOW}$tui_use_cli_hint_msg${COLOR_RESET}"
        MENU_RESULT="QUIT"
    fi
}

# 暂停提示（兼容 TUI 和传统模式）
# TUI 清屏辅助
tui_clear() {
    if _is_interactive_terminal; then
        printf "\033[2J\033[H"
    fi
}

pause_prompt() {
    if _is_interactive_terminal; then
        tui_pause
    else
        printf "%b" "${COLOR_YELLOW}"
        read -r -p "Press Enter to continue..." _
        printf "%b" "${COLOR_RESET}"
    fi
}

get_input() {
    _gi_prompt="$1"
    _gi_default="${2:-}"
    _gi_allow_empty="${3:-false}"
    GET_INPUT_RESULT=""
    GET_INPUT_CANCELED=false

    if _is_interactive_terminal; then
        tui_input "$_gi_prompt" "$_gi_default" "$_gi_allow_empty"
        GET_INPUT_RESULT="$TUI_INPUT_RESULT"
        if [ "$TUI_INPUT_CANCELED" = "true" ]; then
            GET_INPUT_CANCELED=true
            return 1
        fi
    else
        printf "%b" "${COLOR_YELLOW}${_gi_prompt}${COLOR_RESET}"
        if [ -n "$_gi_default" ]; then
            printf " (%s)" "$_gi_default"
        fi
        printf "%b" "${COLOR_RESET}"
        if ! read -r _gi_input; then
            GET_INPUT_CANCELED=true
            return 1
        fi
        if [ "$_gi_allow_empty" = "true" ]; then
            GET_INPUT_RESULT="$_gi_input"
        else
            GET_INPUT_RESULT="${_gi_input:-$_gi_default}"
        fi
    fi
}

# === select_subscription ===
# 选择订阅（列表选择）
# 结果通过全局变量 SELECTED_SUB 返回
# 返回值: 0=成功选择, 1=取消/无订阅
select_subscription(){
    SELECTED_SUB=""
    _ss_names=$(find_subscription_config '' 'names')
    if [ -z "$_ss_names" ]; then
        warn "$not_sub_exists_msg" false
        return 1
    fi
    # 将逗号分隔的列表转换为位置参数
    _old_ifs="$IFS"
    IFS=','
    set -f
    set -- $_ss_names
    set +f
    IFS="$_old_ifs"
    if [ $# -eq 0 ]; then
        warn "$not_sub_exists_msg" false
        return 1
    fi
    # 显示选择菜单
    menu_dispatch " 选择订阅 " "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            # 获取选择的订阅名
            _ss_idx=0
            for _ss_item in "$@"; do
                [ "$_ss_idx" = "$MENU_RESULT" ] && break
                _ss_idx=$((_ss_idx + 1))
            done
            SELECTED_SUB="$_ss_item"
            return 0
            ;;
    esac
}

# === logs_menu ===
logs_menu(){
    while true; do
        menu_dispatch "$menu_logs_title" \
            "$menu_logs_option1" \
            "$menu_logs_option2" \
            "$menu_logs_option3" \
            "$menu_logs_option4" \
            "$menu_logs_option5" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) tui_clear; view_logs; pause_prompt;;
            1)
                tui_clear
                local _lm_file=$(_logs_find_file)
                if [ -z "$_lm_file" ]; then
                    failed "$logs_empty_msg"; pause_prompt; continue
                fi
                get_input "$logs_search_prompt_msg" "" "true"
                if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                if [ -n "$GET_INPUT_RESULT" ]; then
                    local _lm_count
                    _lm_count=$(grep -Fc "$GET_INPUT_RESULT" "$_lm_file" 2>/dev/null) || _lm_count=0
                    printf "%b\n" "$(printf "$logs_search_result_msg" "$_lm_count" "$GET_INPUT_RESULT")"
                    grep -F --color=always "$GET_INPUT_RESULT" "$_lm_file" 2>/dev/null | tail -50
                fi
                pause_prompt
                ;;
            2)
                tui_clear
                local _lm_file=$(_logs_find_file)
                if [ -z "$_lm_file" ]; then
                    failed "$logs_empty_msg"; pause_prompt; continue
                fi
                menu_dispatch "$menu_logs_level_title" \
                    "$menu_logs_level_debug" \
                    "$menu_logs_level_info" \
                    "$menu_logs_level_warning" \
                    "$menu_logs_level_error" \
                    "$menu_logs_level_silent" \
                    "$menu_return"
                case "$MENU_RESULT" in
                    0) grep -i "\[DEBUG\]" "$_lm_file" 2>/dev/null | tail -50 || echo "$logs_empty_msg";;
                    1) grep -i "\[INFO\]" "$_lm_file" 2>/dev/null | tail -50 || echo "$logs_empty_msg";;
                    2) grep -i "\[WARNING\]" "$_lm_file" 2>/dev/null | tail -50 || echo "$logs_empty_msg";;
                    3) grep -i "\[ERROR\]" "$_lm_file" 2>/dev/null | tail -50 || echo "$logs_empty_msg";;
                    4) grep -i "\[SILENT\]" "$_lm_file" 2>/dev/null | tail -50 || echo "$logs_empty_msg";;
                    BACK) continue;;
                    *) continue;;
                esac
                pause_prompt
                ;;
            3)
                tui_clear
                local _lm_file=$(_logs_find_file)
                if [ -z "$_lm_file" ]; then
                    failed "$logs_empty_msg"; pause_prompt; continue
                fi
                normal "$logs_follow_msg"
                # 在子 shell 中跟踪日志，Ctrl+C 只退出子 shell，不影响主脚本
                ( trap 'exit 0' INT; tail -f "$_lm_file" 2>/dev/null ) || true
                ;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

# === tools ===
# 备份与恢复子菜单
backup_main() {
    while true; do
        menu_dispatch "$menu_backup_title" \
            "$menu_backup_option1" \
            "$menu_backup_option2" \
            "$menu_backup_option3" \
            "$menu_backup_option4" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) tui_clear; backup_config; pause_prompt;;
            1) tui_clear; list_backups; pause_prompt;;
            2) tui_clear; restore_backup; pause_prompt;;
            3) tui_clear; delete_backup; pause_prompt;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

# 规则管理子菜单
rules_main() {
    while true; do
        menu_dispatch "$menu_rules_title" \
            "$menu_rules_option1" \
            "$menu_rules_option2" \
            "$menu_rules_option3" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) tui_clear; list_rules; pause_prompt;;
            1) tui_clear; rules_edit; pause_prompt;;
            2) tui_clear; rules_add; pause_prompt;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

# 配置文件管理子菜单
profiles_main() {
    while true; do
        menu_dispatch "$menu_profiles_title" \
            "$menu_profiles_option1" \
            "$menu_profiles_option2" \
            "$menu_profiles_option3" \
            "$menu_profiles_option4" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) tui_clear; list_profiles; pause_prompt;;
            1) tui_clear; create_profile; pause_prompt;;
            2) tui_clear; switch_profile; pause_prompt;;
            3) tui_clear; delete_profile; pause_prompt;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

# 健康检查子菜单
health_main() {
    while true; do
        menu_dispatch "$menu_health_title" \
            "$menu_health_option1" \
            "$menu_health_option2" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) tui_clear; health_check; pause_prompt;;
            1) tui_clear; toggle_auto_recovery; pause_prompt;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

tools(){
    while true; do
        menu_dispatch "$menu_tools_title" \
            "$menu_tools_option1" \
            "$menu_tools_option2" \
            "$menu_tools_option3" \
            "$menu_tools_option4" \
            "$menu_tools_option5" \
            "$menu_return" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) logs_menu;;
            1) backup_main;;
            2) rules_main;;
            3) profiles_main;;
            4) health_main;;
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
        esac
    done
}

# === proxy selection TUI ===
# 返回：设置 _pa_host 和 _pa_secret 变量
proxy_api_info() {
    _pa_port=$(find_user_config "external-controller" | awk -F ':' '{print $2}')
    _pa_secret=$(find_user_config "secret")
    _pa_host="${local_proxy_host}:${_pa_port}"
}

proxy_select_group() {
    refresh_status
    if ! $clash_is_running; then
        warn "$proxy_not_running_msg" false
        return 1
    fi
    proxy_api_info
    _psg_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    if [ -z "$_psg_result" ]; then
        failed "$proxy_api_failed_msg" false
        return 1
    fi
    # 提取所有代理组（排除内置 DIRECT/REJECT/GLOBAL）
    _psg_groups=$(printf '%s\n' "$_psg_result" | "$yq_binary_path" e '.proxies | keys | .[]' - 2>/dev/null | grep -v '^DIRECT$' | grep -v '^REJECT$' | grep -v '^GLOBAL$')
    if [ -z "$_psg_groups" ]; then
        warn "$proxy_no_groups_msg" false
        return 1
    fi
    # 构建菜单项：组名 + 当前服务器（高亮显示当前选择）
    _psg_items=""
    _old_ifs="$IFS"
    IFS="
"
    set -f
    for _psg_g in $_psg_groups; do
        _psg_type=$(printf '%s\n' "$_psg_result" | "$yq_binary_path" e ".proxies[\"${_psg_g}\"].type" - 2>/dev/null)
        _psg_now=$(printf '%s\n' "$_psg_result" | "$yq_binary_path" e ".proxies[\"${_psg_g}\"].now" - 2>/dev/null)
        # 构建显示文本
        if [ -n "$_psg_now" ] && [ "$_psg_now" != "null" ]; then
            # 有当前选择的组，用绿色高亮当前服务器
            _psg_item=" ${_psg_g}  ${COLOR_GREEN}${_psg_now}${COLOR_RESET}"
        else
            _psg_item=" ${_psg_g}"
        fi
        if [ -z "$_psg_items" ]; then
            _psg_items="$_psg_item"
        else
            _psg_items="${_psg_items}
${_psg_item}"
        fi
    done
    set +f
    IFS="$_old_ifs"
    # 用位置参数传递菜单项
    _old_ifs="$IFS"
    IFS="
"
    set -f
    set -- $_psg_items
    set +f
    IFS="$_old_ifs"
    if [ $# -eq 0 ]; then
        warn "$proxy_no_groups_msg" false
        return 1
    fi
    # 同步构建组名数组
    PROXY_GROUP_NAMES=""
    for _psg_g in $_psg_groups; do
        if [ -z "$PROXY_GROUP_NAMES" ]; then
            PROXY_GROUP_NAMES="$_psg_g"
        else
            PROXY_GROUP_NAMES="${PROXY_GROUP_NAMES}
${_psg_g}"
        fi
    done
    menu_dispatch "$proxy_select_group_msg" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            # 通过 PROXY_GROUP_NAMES 获取真实组名
            _psg_idx=0
            _psg_real_name=""
            _old_ifs="$IFS"
            IFS="
"
            for _psg_ng in $PROXY_GROUP_NAMES; do
                if [ "$_psg_idx" = "$MENU_RESULT" ]; then
                    _psg_real_name="$_psg_ng"
                    break
                fi
                _psg_idx=$((_psg_idx + 1))
            done
            IFS="$_old_ifs"
            if [ -z "$_psg_real_name" ]; then
                return 1
            fi
            SELECTED_PROXY_GROUP="$_psg_real_name"
            return 0
            ;;
    esac
}

proxy_select_server() {
    refresh_status
    if ! $clash_is_running; then
        warn "$proxy_not_running_msg" false
        return 1
    fi
    # 选择规则组（显示所有组及当前服务器）
    if ! proxy_select_group; then
        return 1
    fi
    _pss_group="$SELECTED_PROXY_GROUP"
    proxy_api_info
    # 获取该组信息
    _pss_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_pss_group}" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    if [ -z "$_pss_result" ]; then
        failed "$proxy_api_failed_msg" false
        return 1
    fi
    # 提取当前选择
    _pss_current=$(printf '%s\n' "$_pss_result" | "$yq_binary_path" e '.now' - 2>/dev/null)
    # 提取该组的 all 列表
    _pss_all=$(printf '%s\n' "$_pss_result" | "$yq_binary_path" e '.all[]' - 2>/dev/null)
    if [ -z "$_pss_all" ]; then
        # 非 Selector 类型组（无子服务器列表），显示当前信息
        if [ -n "$_pss_current" ] && [ "$_pss_current" != "null" ]; then
            success "$(printf "$proxy_switch_success_msg" "$_pss_group" "$_pss_current")"
        else
            warn "$proxy_no_groups_msg" false
        fi
        return 0
    fi
    # 构建带高亮标记的菜单项
    _pss_items=""
    _old_ifs="$IFS"
    IFS="
"
    set -f
    for _pss_s in $_pss_all; do
        if [ "$_pss_s" = "$_pss_current" ]; then
            # 当前选择的服务器用绿色+粗体高亮
            _pss_item=" ${COLOR_GREEN}${COLOR_BOLD}${_pss_s} ${proxy_current_label}${COLOR_RESET}"
        else
            _pss_item=" ${_pss_s}"
        fi
        if [ -z "$_pss_items" ]; then
            _pss_items="$_pss_item"
        else
            _pss_items="${_pss_items}
${_pss_item}"
        fi
    done
    set +f
    IFS="$_old_ifs"
    # 用位置参数传递菜单项
    _old_ifs="$IFS"
    IFS="
"
    set -f
    set -- $_pss_items
    set +f
    IFS="$_old_ifs"
    if [ $# -eq 0 ]; then
        warn "$proxy_no_groups_msg" false
        return 1
    fi
    # 同步构建服务器名数组
    PROXY_SERVER_NAMES=""
    for _pss_s in $_pss_all; do
        if [ -z "$PROXY_SERVER_NAMES" ]; then
            PROXY_SERVER_NAMES="$_pss_s"
        else
            PROXY_SERVER_NAMES="${PROXY_SERVER_NAMES}
${_pss_s}"
        fi
    done
    _pss_prompt=$(printf "$proxy_select_server_msg" "$_pss_group")
    menu_dispatch "$_pss_prompt" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            # 通过 PROXY_SERVER_NAMES 获取真实服务器名
            _pss_idx=0
            _pss_real_name=""
            _old_ifs="$IFS"
            IFS="
"
            for _pss_ns in $PROXY_SERVER_NAMES; do
                if [ "$_pss_idx" = "$MENU_RESULT" ]; then
                    _pss_real_name="$_pss_ns"
                    break
                fi
                _pss_idx=$((_pss_idx + 1))
            done
            IFS="$_old_ifs"
            if [ -z "$_pss_real_name" ]; then
                return 1
            fi
            # 如果选择的就是当前服务器，无需切换
            if [ "$_pss_real_name" = "$_pss_current" ]; then
                warn "$(printf "$proxy_switch_success_msg" "$_pss_group" "$_pss_real_name")" false
                return 0
            fi
            # 切换代理服务器（对服务器名做 JSON 字符串转义，防止破坏 JSON）
            _pss_json_name=$(printf '%s' "$_pss_real_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
            curl -s --max-time 5 -X PUT "http://${_pa_host}/proxies/${_pss_group}" -H "Content-Type: application/json" -H "Authorization: Bearer ${_pa_secret}" -d "{\"name\":\"$_pss_json_name\"}" >/dev/null 2>&1
            # 验证切换是否成功
            _pss_verify=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_pss_group}" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
            _pss_verify_now=$(printf '%s\n' "$_pss_verify" | "$yq_binary_path" e '.now' - 2>/dev/null)
            if [ "$_pss_verify_now" = "$_pss_real_name" ]; then
                success "$(printf "$proxy_switch_success_msg" "$_pss_group" "$_pss_real_name")"
            else
                failed "$proxy_switch_failed_msg" false
                return 1
            fi
            return 0
            ;;
    esac
}

proxy_test_delay() {
    refresh_status
    if ! $clash_is_running; then
        warn "$proxy_not_running_msg" false
        return 1
    fi
    # 选择规则组
    if ! proxy_select_group; then
        return 1
    fi
    _ptd_group="$SELECTED_PROXY_GROUP"
    proxy_api_info
    # 获取该组所有服务器
    _ptd_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_ptd_group}" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    _ptd_all=$(printf '%s\n' "$_ptd_result" | "$yq_binary_path" e '.all[]' - 2>/dev/null)
    _ptd_now=$(printf '%s\n' "$_ptd_result" | "$yq_binary_path" e '.now' - 2>/dev/null)
    if [ -z "$_ptd_all" ]; then
        # 非选择组，直接测当前代理延迟
        normal "$proxy_delay_testing_msg"
        _ptd_delay_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_ptd_group}/delay?url=http://www.gstatic.com/generate_204&timeout=5000" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
        _ptd_delay=$(printf '%s\n' "$_ptd_delay_result" | "$yq_binary_path" e '.delay' - 2>/dev/null)
        if [ -n "$_ptd_delay" ] && [ "$_ptd_delay" != "null" ]; then
            success "$(printf "$proxy_delay_result_msg" "$_ptd_delay")"
        else
            warn "$proxy_delay_timeout_msg" false
        fi
        return 0
    fi
    # 遍历所有服务器测试延迟
    normal "$(printf "$proxy_delay_all_msg" "$_ptd_group")"
    printf "%-30s %s\n" "$proxy_server_label" "$proxy_delay_label"
    printf "%-30s %s\n" "------------------------------" "----------"
    _old_ifs="$IFS"
    IFS="
"
    set -f
    for _ptd_s in $_ptd_all; do
        _ptd_is_current=""
        [ "$_ptd_s" = "$_ptd_now" ] && _ptd_is_current=" *"
        _ptd_sr=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_ptd_s}/delay?url=http://www.gstatic.com/generate_204&timeout=3000" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
        _ptd_sd=$(printf '%s\n' "$_ptd_sr" | "$yq_binary_path" e '.delay' - 2>/dev/null)
        if [ -n "$_ptd_sd" ] && [ "$_ptd_sd" != "null" ]; then
            printf "%-30s %s%s\n" "${_ptd_s}${_ptd_is_current}" "${_ptd_sd}ms"
        else
            printf "%-30s %s%s\n" "${_ptd_s}${_ptd_is_current}" "timeout"
        fi
    done
    set +f
    IFS="$_old_ifs"
}

proxy_show_status() {
    refresh_status
    if ! $clash_is_running; then
        warn "$proxy_not_running_msg" false
        return 1
    fi
    proxy_api_info
    _pst_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    if [ -z "$_pst_result" ]; then
        failed "$proxy_api_failed_msg" false
        return 1
    fi
    printf "%b\n" "${COLOR_CYAN}${COLOR_BOLD}${proxy_status_title_msg}${COLOR_RESET}"
    # 提取 Selector/URLTest/Fallback 类型的组
    _pst_groups=$(printf '%s\n' "$_pst_result" | "$yq_binary_path" e '.proxies | to_entries[] | select(.value.type == "Selector" or .value.type == "URLTest" or .value.type == "Fallback") | .key' - 2>/dev/null)
    if [ -z "$_pst_groups" ]; then
        warn "$proxy_no_groups_msg" false
        return 1
    fi
    # 表头（使用 _help_row 对齐方式处理 CJK）
    _pst_gw=20; _pst_sw=30
    _pst_g_pad=$((_pst_gw - $(str_display_width "$proxy_group_label")))
    _pst_s_pad=$((_pst_sw - $(str_display_width "$proxy_server_label")))
    [ "$_pst_g_pad" -lt 1 ] && _pst_g_pad=1
    [ "$_pst_s_pad" -lt 1 ] && _pst_s_pad=1
    printf "%b%b%b\n" "${COLOR_BOLD}" "${proxy_group_label}$(printf "%${_pst_g_pad}s")${proxy_server_label}$(printf "%${_pst_s_pad}s")${proxy_delay_label}" "${COLOR_RESET}"
    printf "%-20s %-30s %s\n" "--------------------" "------------------------------" "----------"
    _old_ifs="$IFS"
    IFS="
"
    set -f
    for _pst_g in $_pst_groups; do
        _pst_now=$(printf '%s\n' "$_pst_result" | "$yq_binary_path" e ".proxies[\"${_pst_g}\"].now" - 2>/dev/null)
        _pst_type=$(printf '%s\n' "$_pst_result" | "$yq_binary_path" e ".proxies[\"${_pst_g}\"].type" - 2>/dev/null)
        # 测试当前选择的延迟
        _pst_delay=""
        if [ -n "$_pst_now" ] && [ "$_pst_now" != "null" ]; then
            _pst_dr=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_pst_now}/delay?url=http://www.gstatic.com/generate_204&timeout=3000" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
            _pst_dv=$(printf '%s\n' "$_pst_dr" | "$yq_binary_path" e '.delay' - 2>/dev/null)
            if [ -n "$_pst_dv" ] && [ "$_pst_dv" != "null" ]; then
                _pst_delay="${_pst_dv}ms"
            else
                _pst_delay="timeout"
            fi
        else
            _pst_delay="N/A"
        fi
        # 按 CJK 宽度对齐
        _pst_gw_cur=$(str_display_width "$_pst_g")
        _pst_gp=$((_pst_gw - _pst_gw_cur))
        [ "$_pst_gp" -lt 1 ] && _pst_gp=1
        _pst_now_disp="${_pst_now:-N/A}"
        _pst_sw_cur=$(str_display_width "$_pst_now_disp")
        _pst_sp=$((_pst_sw - _pst_sw_cur))
        [ "$_pst_sp" -lt 1 ] && _pst_sp=1
        printf "%s%${_pst_gp}s%s%${_pst_sp}s%s\n" "$_pst_g" "" "$_pst_now_disp" "" "$_pst_delay"
    done
    set +f
    IFS="$_old_ifs"
}

proxy_url_test() {
    refresh_status
    if ! $clash_is_running; then
        warn "$proxy_not_running_msg" false
        return 1
    fi
    # 选择规则组
    if ! proxy_select_group; then
        return 1
    fi
    _put_group="$SELECTED_PROXY_GROUP"
    proxy_api_info
    normal "$(printf "$proxy_url_test_msg" "$_put_group")"
    # 触发 URL 测试
    _put_result=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_put_group}/delay?url=http://www.gstatic.com/generate_204&timeout=5000" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    # 获取测试后的当前选择
    sleep 1
    _put_verify=$(curl -s --max-time 5 "http://${_pa_host}/proxies/${_put_group}" -H "Authorization: Bearer ${_pa_secret}" 2>/dev/null)
    _put_now=$(printf '%s\n' "$_put_verify" | "$yq_binary_path" e '.now' - 2>/dev/null)
    _put_delay=$(printf '%s\n' "$_put_result" | "$yq_binary_path" e '.delay' - 2>/dev/null)
    if [ -n "$_put_delay" ] && [ "$_put_delay" != "null" ]; then
        success "$(printf "$proxy_switch_success_msg" "$_put_group" "$_put_now") ($(printf "$proxy_delay_result_msg" "$_put_delay"))"
    else
        success "$(printf "$proxy_url_test_done_msg" "$_put_group")"
    fi
}

# === main menu and sub-menus ===
# 定义菜单函数
menu() {
    # 服务控制菜单
    service_menu() {
        while true; do
            menu_dispatch "$menu_service_title" \
                "$menu_service_option1" \
                "$menu_service_option2" \
                "$menu_service_option3" \
                "$menu_service_option4" \
                "$menu_return" \
                "$menu_exit"
            case "$MENU_RESULT" in
                0) tui_clear; start; pause_prompt;;
                1) tui_clear; stop; pause_prompt;;
                2) tui_clear; restart; pause_prompt;;
                3)
                    tui_clear
                    if select_subscription; then
                        reload "$SELECTED_SUB"
                    fi
                    pause_prompt
                    ;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }

    # 安装与设置菜单
    install_menu() {
        while true; do
            menu_dispatch "$menu_install_title" \
                "$menu_install_option1" \
                "$menu_install_option2" \
                "$menu_install_option3" \
                "$menu_install_option4" \
                "$menu_install_option5" \
                "$menu_install_option6" \
                "$menu_install_option7" \
                "$menu_install_option8" \
                "$menu_install_option9" \
                "$menu_return" \
                "$menu_exit"
            case "$MENU_RESULT" in
                0)
                    get_input "$prompt_version_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    if [ -z "$GET_INPUT_RESULT" ]; then warn "$validate_required_msg" "version" false; pause_prompt; continue; fi
                    "$SCRIPT_PATH" install "$GET_INPUT_RESULT"; pause_prompt
                    ;;
                1)
                    get_input "$prompt_version_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    if [ -z "$GET_INPUT_RESULT" ]; then warn "$validate_required_msg" "version" false; pause_prompt; continue; fi
                    "$SCRIPT_PATH" update "$GET_INPUT_RESULT"; pause_prompt
                    ;;
                2) "$SCRIPT_PATH" uninstall; pause_prompt;;
                3) "$SCRIPT_PATH" uninstall all; pause_prompt;;
                4|5|6)
                    _ui="yacd"
                    [ "$MENU_RESULT" = "5" ] && _ui="dashboard"
                    [ "$MENU_RESULT" = "6" ] && _ui="zashboard"
                    if [ -d "$ui_install_dir" ];then
                        "$SCRIPT_PATH" update_ui "$_ui"
                    else
                        "$SCRIPT_PATH" install_ui "$_ui"
                    fi
                    pause_prompt
                    ;;
                7) "$SCRIPT_PATH" update_ui; pause_prompt;;
                8) "$SCRIPT_PATH" uninstall_ui; pause_prompt;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }

    # 代理选择菜单
    proxy_menu() {
        while true; do
            menu_dispatch "$menu_proxy_title" \
                "$menu_proxy_option1" \
                "$menu_proxy_option2" \
                "$menu_proxy_option3" \
                "$menu_proxy_option4" \
                "$menu_return" \
                "$menu_exit"
            case "$MENU_RESULT" in
                0) tui_clear; proxy_select_server; pause_prompt;;
                1) tui_clear; proxy_show_status; pause_prompt;;
                2) tui_clear; proxy_test_delay; pause_prompt;;
                3) tui_clear; proxy_url_test; pause_prompt;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }

    # 订阅管理菜单
    subscription() {
        while true; do
            menu_dispatch "$menu_subscription_title" \
                "$menu_subscription_option1" \
                "$menu_subscription_option2" \
                "$menu_subscription_option3" \
                "$menu_subscription_option4" \
                "$menu_subscription_option5" \
                "$menu_subscription_option6" \
                "$menu_subscription_option7" \
                "$menu_return" \
                "$menu_exit"
            case "$MENU_RESULT" in
                0)
                    get_input "$prompt_subscription_name_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    _var="$GET_INPUT_RESULT"
                    if [ -z "$_var" ]; then
                        warn "$validate_name_msg" false; pause_prompt; continue
                    fi
                    get_input "$prompt_subscription_url_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    _sub_url="$GET_INPUT_RESULT"
                    if [ -z "$_sub_url" ]; then
                        warn "$validate_url_msg" false; pause_prompt; continue
                    fi
                    add "${_var}::${_sub_url}"
                    pause_prompt
                    ;;
                1)
                    if select_subscription; then
                        _sub_name="$SELECTED_SUB"
                        get_input "$prompt_subscription_url_msg"
                        if [ "$GET_INPUT_CANCELED" = "true" ]; then pause_prompt; continue; fi
                        _sub_url="$GET_INPUT_RESULT"
                        if [ -z "$_sub_url" ]; then
                            warn "$validate_url_msg" false; pause_prompt; continue
                        fi
                        modify "$_sub_name" "$_sub_url"
                    fi
                    pause_prompt
                    ;;
                2)
                    if select_subscription; then
                        del "$SELECTED_SUB"
                    fi
                    pause_prompt
                    ;;
                3) list; pause_prompt;;
                4)
                    if select_subscription; then
                        update_sub "$SELECTED_SUB"
                    fi
                    pause_prompt
                    ;;
                5) auto_update_sub false; pause_prompt;;
                6) auto_update_sub true; pause_prompt;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }

    # 订阅与配置菜单
    sub_config_menu() {
        while true; do
            menu_dispatch "$menu_sub_config_title" \
                "$menu_sub_config_option1" \
                "$menu_sub_config_option2" \
                "$menu_sub_config_option3" \
                "$menu_sub_config_option4" \
                "$menu_sub_config_option5" \
                "$menu_sub_config_option6" \
                "$menu_sub_config_option7" \
                "$menu_sub_config_option8" \
                "$menu_sub_config_option9" \
                "$menu_sub_config_option10" \
                "$menu_sub_config_option11" \
                "$menu_return" \
                "$menu_exit"
            case "$MENU_RESULT" in
                0) # Add subscription
                    get_input "$prompt_subscription_name_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    _var="$GET_INPUT_RESULT"
                    if [ -z "$_var" ]; then
                        warn "$validate_name_msg" false; pause_prompt; continue
                    fi
                    get_input "$prompt_subscription_url_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    _sub_url="$GET_INPUT_RESULT"
                    if [ -z "$_sub_url" ]; then
                        warn "$validate_url_msg" false; pause_prompt; continue
                    fi
                    add "${_var}::${_sub_url}"
                    pause_prompt
                    ;;
                1) # Modify subscription
                    if select_subscription; then
                        _sub_name="$SELECTED_SUB"
                        get_input "$prompt_subscription_url_msg"
                        if [ "$GET_INPUT_CANCELED" = "true" ]; then pause_prompt; continue; fi
                        _sub_url="$GET_INPUT_RESULT"
                        if [ -z "$_sub_url" ]; then
                            warn "$validate_url_msg" false; pause_prompt; continue
                        fi
                        modify "$_sub_name" "$_sub_url"
                    fi
                    pause_prompt
                    ;;
                2) # Delete subscription
                    if select_subscription; then
                        del "$SELECTED_SUB"
                    fi
                    pause_prompt
                    ;;
                3) list; pause_prompt;;
                4) # Update subscription
                    if select_subscription; then
                        update_sub "$SELECTED_SUB"
                    fi
                    pause_prompt
                    ;;
                5) auto_update_sub false; pause_prompt;;
                6) auto_update_sub true; pause_prompt;;
                7) tui_clear; config_view; pause_prompt;;
                8) tui_clear; config_set; pause_prompt;;
                9) tui_clear; config_del; pause_prompt;;
                10) tui_clear; config_edit_raw; pause_prompt;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }

    # 主菜单循环
    while true; do
        # 构建权限状态标识
        local _mm_mode_label
        if is_root; then
            _mm_mode_label="${COLOR_RED}[ROOT]${COLOR_RESET}"
        else
            _mm_mode_label="${COLOR_GREEN}[USER]${COLOR_RESET}"
        fi
        if is_docker; then
            _mm_mode_label="${_mm_mode_label} ${COLOR_YELLOW}[DOCKER]${COLOR_RESET}"
        fi
        # 将权限模式加入菜单标题
        local _mm_title="${menu_header} ${_mm_mode_label}"

        # 动态生成开机自启/网关/本机代理的状态显示
        local _mm_autostart_label _mm_gateway_label _mm_proxy_label
        if is_auto_start; then
            _mm_autostart_label="$menu_main_option1 ${COLOR_GREEN}${tui_status_on_label}${COLOR_RESET}"
        else
            _mm_autostart_label="$menu_main_option1 ${COLOR_RED}${tui_status_off_label}${COLOR_RESET}"
        fi
        
        # 网关选项：用户级安装时标记为不可用
        if is_root; then
            if is_gateway; then
                _mm_gateway_label="$menu_main_option2 ${COLOR_GREEN}${tui_status_on_label}${COLOR_RESET}"
            else
                _mm_gateway_label="$menu_main_option2 ${COLOR_RED}${tui_status_off_label}${COLOR_RESET}"
            fi
        else
            _mm_gateway_label="$menu_main_option2 ${COLOR_DIM}${tui_status_na_root_label}${COLOR_RESET}"
        fi

        if is_proxy; then
            _mm_proxy_label="$menu_main_option3 ${COLOR_GREEN}${tui_status_on_label}${COLOR_RESET}"
        else
            _mm_proxy_label="$menu_main_option3 ${COLOR_RED}${tui_status_off_label}${COLOR_RESET}"
        fi

        menu_dispatch "$_mm_title" \
            "$menu_main_option0" \
            "$_mm_autostart_label" \
            "$_mm_gateway_label" \
            "$_mm_proxy_label" \
            "$menu_main_option4" \
            "$menu_main_option5" \
            "$menu_main_option6" \
            "$menu_main_option7" \
            "$menu_main_option8" \
            "$menu_main_option9" \
            "$menu_exit"
        case "$MENU_RESULT" in
            0) service_menu;;
            1) tui_clear; if is_auto_start; then auto_start false; else auto_start true; fi; pause_prompt;;
            2) 
                if is_root; then
                    tui_clear; if is_gateway; then gateway false; else gateway true; fi; pause_prompt
                else
                    tui_clear; permission_denied_msg "gateway"; printf "\n"; pause_prompt
                fi
                ;;
            3) tui_clear; if is_proxy; then proxy_off; else proxy_on; fi; pause_prompt;;
            4) sub_config_menu;;
            5) proxy_menu;;
            6) install_menu;;
            7) tools;;
            8) tui_clear; status; pause_prompt;;
            9) update_check; pause_prompt;;
            QUIT) break;;
            INVALID|*)
                printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"
                if ! _is_interactive_terminal; then sleep 1; fi
                ;;
        esac
    done
}

