#!/bin/sh
# version:1.2.4
# Clash for Linux - A comprehensive Clash management tool
# Disable bash history expansion to prevent issues with ! character in strings
# (only works in bash, silently ignored in other shells)
if [ -n "$BASH_VERSION" ]; then
    set +H
fi

# ==================== 配置参数 ====================
# 外部控制器密码，不填写则随机生成
controller_secret=''
# 系统架构，默认自动获取，获取失败请自行填写（amd64/arm64等）
target_platform=''
# 界面语言（auto=自动检测, zh_CN=简体中文, en=English, zh_TW=繁体中文, ...）
# 添加新语言：在 i18n/ 目录创建 <lang>.sh 文件
language="auto"
# 向后兼容：use_chinese=true 等价于 language=zh_CN
use_chinese=true
# 当前已安装的yq版本（自动管理）
current_yq_version=''
# 当前已安装的mmdb版本（自动管理）
current_mmdb_version=''

# ==================== GitHub仓库配置 ====================
# Clash/Mihomo 核心仓库
clash_repo='MetaCubeX/mihomo'
# Clash 发布文件路径模板，支持变量: :version: :target_platform:
clash_release_pattern='v:version:/mihomo-linux-:target_platform:-v:version:.gz'

# yq 工具仓库
yq_repo='mikefarah/yq'
yq_release_pattern='v:version:/yq_linux_:target_platform:'

# MaxMind GeoIP 数据库仓库
mmdb_repo='Dreamacro/maxmind-geoip'
mmdb_release_pattern=':version:/Country.mmdb'

# ==================== UI界面配置 ====================
ui_url_yacd='https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip'
ui_url_dashboard='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'
ui_url_zashboard='https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip'

#本项目仓库地址
project_repo='onlypeng/clash-for-linux/test'

# ==================== 下载配置 ====================
# 下载失败重试次数
download_max_retries=3
# 订阅是否使用代理下载
subscription_use_proxy=false
# GitHub下载代理地址（末尾带/）
github_proxy_url="https://gh-proxy.com/"

# ==================== 代理配置 ====================
# 本地代理地址（纯IP，不带协议前缀）
local_proxy_host="127.0.0.1"
# 需要设置代理的协议
proxy_protocols="http https ftp socks"
# 不走代理的地址
proxy_bypass_hosts="localhost,127.0.0.1,::1"

# ==================== 路径配置（不建议修改） ====================
service_name="clash"
# 命令名（软链接名称）
cmd_name="clashtool"

# ==================== 权限检测 ====================
# 通过 UID/GID 验证当前用户权限状态
_is_root_user=false
_is_docker_env=false
_run_mode="user"

# 检测是否为 Docker 容器环境
detect_docker() {
    # 方法1: /.dockerenv 文件
    [ -f /.dockerenv ] && return 0
    # 方法2: /proc/1/cgroup 包含 docker
    if [ -f /proc/1/cgroup ] 2>/dev/null; then
        grep -qa 'docker' /proc/1/cgroup 2>/dev/null && return 0
    fi
    # 方法3: 环境变量
    [ -n "$container" ] && return 0
    return 1
}

# 初始化权限和路径
if [ "$(id -u)" -eq 0 ]; then
    _is_root_user=true
    _run_mode="root"
    # 通过 sudo 运行时，检测原始用户是否有用户级安装（避免找不到用户文件）
    if [ -n "$SUDO_USER" ] && [ -z "${CLASHTOOL_INSTALL_DIR:-}" ]; then
        _sudo_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        [ -z "$_sudo_home" ] && _sudo_home="/home/$SUDO_USER"
        if [ -d "${_sudo_home}/.local/${service_name}" ]; then
            # 原始用户有用户级安装，使用其路径（解决 sudo 运行找不到用户文件的问题）
            _is_root_user=false
            _run_mode="user"
            install_dir="${_sudo_home}/.local/${service_name}"
            symlink_dir="${_sudo_home}/.local/bin"
            symlink_path="${symlink_dir}/${cmd_name}"
        else
            # 原始用户无安装，使用 root 全局路径
            install_dir="/opt/${service_name}"
            symlink_dir="/usr/local/bin"
            symlink_path="${symlink_dir}/${cmd_name}"
        fi
    else
        # 直接 root 运行或指定了 CLASHTOOL_INSTALL_DIR
        install_dir="${CLASHTOOL_INSTALL_DIR:-/opt/${service_name}}"
        symlink_dir="/usr/local/bin"
        symlink_path="${symlink_dir}/${cmd_name}"
    fi
else
    _is_root_user=false
    _run_mode="user"
    # 用户级安装到 ~/.local/clash，软链接到 ~/.local/bin/clashtool
    install_dir="${CLASHTOOL_INSTALL_DIR:-${HOME}/.local/${service_name}}"
    symlink_dir="${HOME}/.local/bin"
    mkdir -p "$symlink_dir" 2>/dev/null
    chmod 0700 "$symlink_dir" 2>/dev/null
    symlink_path="${symlink_dir}/${cmd_name}"
fi

# Docker 环境适配
if detect_docker; then
    _is_docker_env=true
    # 容器中无 systemd，强制用户模式行为
    if $_is_root_user; then
        : # root in docker: 仍使用 /opt/clash 但跳过 systemd
    fi
fi

export SAFE_PATHS="$install_dir:${symlink_dir}"
# 脚本路径
script_path="${install_dir}/clashtool.sh"
# 当前执行脚本路径（用于菜单中调用自身）
# 转换为绝对路径，避免 "clashtool.sh: not found" 错误
case "$0" in
    /*) SCRIPT_PATH="$0" ;;
    */*) SCRIPT_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")" ;;
    *) SCRIPT_PATH="$(pwd)/$0" ;;
esac
# 解析符号链接，确保能找到同目录的 i18n 模块
if command -v readlink >/dev/null 2>&1; then
    _resolved_path=$(readlink -f "$SCRIPT_PATH" 2>/dev/null)
    [ -n "$_resolved_path" ] && [ -f "$_resolved_path" ] && SCRIPT_PATH="$_resolved_path"
fi
# 检测管道安装模式（curl ... | sh）
# 当 $0 是 shell 解释器路径时，说明通过管道执行，无法定位本地脚本
_is_piped_install=false
case "$0" in
    sh|bash|dash|*/sh|*/bash|*/dash)
        _is_piped_install=true
        SCRIPT_PATH=""
        ;;
esac
# UI安装目录
ui_install_dir="${install_dir}/ui"
# 日志目录
log_dir="${install_dir}/logs"
# 配置目录
config_dir="${install_dir}/config"
# 订阅目录
subscription_dir="${config_dir}/subscription"
# 订阅备份目录
subscription_backup_dir="${subscription_dir}/backup"

# 用户bash配置文件路径
user_bashrc="$HOME/.bashrc"
if [ -n "$SUDO_USER" ]; then
    user_bashrc="/home/$SUDO_USER/.bashrc"
fi

# 可执行文件路径
clash_binary_path="${install_dir}/clash"
yq_binary_path="${install_dir}/yq"

# 配置文件路径
main_config_path="${config_dir}/config.yaml"
user_config_path="${config_dir}/user.yaml"
gateway_config_path="${config_dir}/gateway.yaml"
tool_config_path="${config_dir}/clashtool.ini"

# Clash 基本配置键（仅支持简单键值对，复杂配置请使用编辑器直接修改）
clash_config_keys="port socks-port redir-port tproxy-port mixed-port allow-lan bind-address mode log-level ipv6 unified-delay external-controller global-client-fingerprint external-ui secret interface-name routing-mark"

# ==================== 运行状态 ====================
# 刷新Clash运行状态（重新检测进程）
refresh_status() {
    # 方法1: pgrep 匹配完整路径（排除自身脚本进程）
    clash_pid=$(pgrep -f "$clash_binary_path" 2>/dev/null | grep -v "^$$\$" | head -1)
    # 方法2: 如果方法1失败，精确匹配二进制进程名
    if [ -z "$clash_pid" ] && [ -f "$clash_binary_path" ]; then
        clash_pid=$(pgrep -x "$(basename "$clash_binary_path")" 2>/dev/null | head -1)
    fi
    # 方法3: 检查端口是否在监听（通过 mixed-port）
    if [ -z "$clash_pid" ] && [ -f "$user_config_path" ]; then
        local _rs_port=$("$yq_binary_path" e '.mixed-port' "$user_config_path" 2>/dev/null)
        if [ -n "$_rs_port" ] && [ "$_rs_port" -gt 0 ] 2>/dev/null; then
            clash_pid=$(ss -tlnp 2>/dev/null | grep ":${_rs_port}" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)
        fi
    fi
    if [ -z "$clash_pid" ]; then
        clash_is_running=false
    else
        clash_is_running=true
    fi
}

# 检查Clash是否正在运行
clash_is_running=false
refresh_status
# ==================== UI Format Configuration ====================
# ANSI color codes
COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_PURPLE="\033[35m"
COLOR_CYAN="\033[36m"
COLOR_WHITE="\033[37m"
COLOR_BOLD="\033[1m"
COLOR_DIM="\033[2m"


_is_interactive_terminal() {
    command -v stty >/dev/null 2>&1 && [ -c /dev/tty ] 2>/dev/null && { stty -g </dev/tty; } >/dev/null 2>&1
}

# 模块加载器：本地优先，本地不存在则从 GitHub 在线下载到临时文件并 source
# 参数: $1 - 模块文件名 (如 i18n/zh_CN.sh)
# 返回: 0 成功, 1 失败（在线加载失败时）
# 副作用: 加载成功后变量 _LOADED_MODULE_PATH 保存实际加载的文件路径
_LOAD_MODULE_OK=false
_LOADED_MODULE_PATH=""
_load_module() {
    _lm_name="$1"
    _LOAD_MODULE_OK=false
    _LOADED_MODULE_PATH=""
    # 1. 本地存在则直接加载（管道模式下跳过，SCRIPT_PATH 为空）
    if [ -n "$SCRIPT_PATH" ]; then
        _lm_local="$(dirname "$SCRIPT_PATH")/$_lm_name"
        if [ -f "$_lm_local" ]; then
            . "$_lm_local"
            _LOAD_MODULE_OK=true
            _LOADED_MODULE_PATH="$_lm_local"
            return 0
        fi
    fi
    # 2. 本地不存在，尝试从 GitHub 在线加载（静默）
    if [ -n "$module_local_missing_msg" ]; then
        normal "$(printf "$module_local_missing_msg" "$_lm_name")" 2>/dev/null
    fi
    _lm_url="${github_proxy_url}https://raw.githubusercontent.com/$project_repo/$_lm_name"
    # 使用 mktemp 创建临时文件，避免符号链接攻击
    _lm_temp=$(mktemp "${TMPDIR:-/tmp}/clashtool_${_lm_name}.XXXXXX" 2>/dev/null) || _lm_temp="${TMPDIR:-/tmp}/clashtool_${_lm_name}.$$"
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 20 -o "$_lm_temp" "$_lm_url" 2>/dev/null
        # 校验下载文件：非空且为 shell 脚本（含 # 注释行）
        if [ -f "$_lm_temp" ] && [ -s "$_lm_temp" ] && grep -q '^#' "$_lm_temp" 2>/dev/null; then
            . "$_lm_temp"
            _LOAD_MODULE_OK=true
            _LOADED_MODULE_PATH="$_lm_temp"
            if [ -n "$module_online_load_ok_msg" ]; then
                normal "$(printf "$module_online_load_ok_msg" "$_lm_name")" 2>/dev/null
            fi
            return 0
        fi
        rm -f "$_lm_temp" 2>/dev/null
    fi
    if [ -n "$module_online_load_fail_msg" ]; then
        normal "$(printf "$module_online_load_fail_msg" "$_lm_name")" 2>/dev/null
    fi
    return 1
}

# ==================== TUI 模块（合并自 clashtool_tui.sh） ====================
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
MENU_BORDER_TOP="╔══════════════════════════════════════════════════════════════════════════════╗"
MENU_BORDER_MID="╠══════════════════════════════════════════════════════════════════════════════╣"
MENU_BORDER_BOT="╚══════════════════════════════════════════════════════════════════════════════╝"
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



# Define menu and prompt text variables in English
# Main menu options
# i18n modules override menu variables after menu module is loaded

# Proxy management messages
proxy_not_running_msg="Clash is not running, please start Clash first"
proxy_api_failed_msg="Failed to connect to Clash API"
proxy_no_groups_msg="No proxy groups found in configuration"
proxy_select_group_msg="Select a proxy group:"
proxy_select_server_msg="Select a proxy server for '%s':"
proxy_switch_success_msg="Proxy switched: %s -> %s"
proxy_switch_failed_msg="Failed to switch proxy"
proxy_delay_testing_msg="Testing proxy delay..."
proxy_delay_result_msg="Delay: %s ms"
proxy_delay_timeout_msg="Proxy timeout"
proxy_delay_all_msg="Testing all servers in %s..."
proxy_status_title_msg="Current Proxy Status:"
proxy_group_label="Group"
proxy_server_label="Server"
proxy_delay_label="Delay"
proxy_current_label="(current)"
proxy_url_test_msg="URL testing %s..."
proxy_url_test_done_msg="%s URL test completed"
proxy_source_command_msg="Please use 'source' to execute the proxy command"

# Config editor messages
config_view_title_msg="Current Clash User Config (user.yaml):"
config_view_empty_msg="No config items found in user.yaml"
config_set_prompt_key_msg="Select a config key to set:"
config_set_prompt_val_msg="Enter the value for '%s':"
config_set_success_msg="Config item set successfully"
config_set_failed_msg="Failed to set config item"
validate_port_msg="%s must be a number"
validate_port_range_msg="%s must be between 1-65535"
validate_bool_msg="%s must be true or false"
validate_enum_msg="%s must be one of: %s"
validate_required_msg="%s cannot be empty"
validate_format_msg="%s format error, expected: %s"
validate_number_msg="%s must be a number"
validate_url_msg="Invalid URL format"
validate_name_msg="Name cannot be empty or contain special characters"
validate_rule_msg="Invalid rule format, expected: TYPE,MATCH,TARGET"
config_del_prompt_msg="Select a config key to delete:"
config_del_confirm_msg="Are you sure you want to delete '%s'?"
config_del_success_msg="Config item deleted successfully"
config_del_failed_msg="Failed to delete config item"
config_no_keys_msg="No config keys found"
config_key_label="Key"
config_value_label="Value"
config_select_key_title=" Select Config Key "
input_canceled_msg="Input canceled"
config_raw_title_msg="Raw user.yaml content:"
config_no_editor_msg="No editor found (GUI/nano/vim/vi)"
config_editor_msg="Opening user.yaml with %s..."
config_editor_fallback_msg="GUI editor failed, falling back to %s..."
config_edit_invalid_msg="Config validation failed after editing, please check your changes"
config_edit_valid_msg="Config validation passed"

# Prompt messages
prompt_choice_msg="Please choose an option (enter the number):"
prompt_version_msg="Enter the version number (default is the latest version):"
prompt_subscription_name_msg="Enter the subscription name:"
prompt_subscription_url_msg="Enter the subscription URL:"
prompt_subscription_update_msg="Enter the subscription auto-update interval (in hours):"
not_root_execute_msg="Please run the script with sudo or as the root user."
verify_failed_msg="Parameter can only be true, false, or ''. Default is true."
unsupported_linux_distribution_failed_msg="Unsupported Linux distribution."
recognition_system_failed_msg="Unable to determine the current operating system architecture. Please specify the target_platform parameter."
was_install_msg="was installed"
not_install_msg="Not installed"
file_does_not_exist='The downloaded file does not exist'
install_start_msg="Starting installation"
install_success_msg="Installation successful"
install_failed_msg="Installation failed"
uninstall_start_msg="Starting uninstallation"
uninstall_success_msg="Uninstallation successful"
uninstall_purge_success_msg="Uninstallation successful (config purged)"
uninstall_all_success_msg="Full uninstallation successful (core + UI + configs)"
require_check_msg="Checking for dependencies"
require_install_failed_msg="Unable to recognize the package manager. Please install it manually."
init_config_start_msg="Initializing configuration file"
init_config_success_msg="Configuration file initialized successfully"
migrate_config_success_msg="Configuration file migrated successfully"
download_start_msg="Starting download"
download_waiting_msg="Download failed. Waiting 5 seconds before the next attempt..."
download_success_msg="Download successful"
download_failed_msg="Download failed"
decompress_failed_msg="Decompression failed"
download_path_msg="Download Path:"
get_version_failed_msg="Failed to retrieve version."
latest_version_msg="Latest Version:"
current_version_msg="Currently version:"
install_equal_versions_warn_msg="Newly installed version is the same as the current version"
install_ui_parameter_failed_msg="Parameter error. It can only be 'dashboard' or 'yacd' or zashboard. Default is the currently installed version."
install_ui_failed_msg="ClashUI installation failed, index.html not found in archive"
ui_already_installed_skip_msg="ClashUI already installed, skip. Use 'update ui' to update."
ui_not_installed_skip_msg="ClashUI not installed, skip."
update_script_success_msg='Script Update Success'
update_script_failed_msg='Script update failed'
clash_running_warn_msg="Clash service is already running"
clash_not_running_warn_msg="Clash service is not running"
clash_start_msg="Starting Clash service"
clash_start_success_msg="Clash service started successfully"
clash_start_failed_msg="Failed to start Clash service"
clash_yaml_failed_msg="Configuration file error"
clash_reload_success_msg="Clash configuration reloaded successfully"
clash_reload_failed_msg="Clash configuration reloaded failed"
clash_stop_success_msg="Clash service stopped successfully"
clash_stop_failed_msg="Failed to stop Clash service"
sub_url_check_msg="Checking subscription address validity..."
sub_url_invalid_msg="Invalid subscription address"
sub_url_effective_msg="Subscription address is valid"
add_sub_success_msg="Subscription information added successfully"
add_sub_parameter_failed_msg="Format error: Format should be 'Subscription name::Subscription address (or file path)::Subscription update interval (hours, can be empty)'"
delete_sub_success_msg="Subscription information deleted successfully"
update_sub_success_msg="Subscription information updated successfully"
auto_update_sub_off_success_msg="Auto update subscription has been turned off"
auto_update_sub_on_success_msg="Auto update subscription has been turned on"
update_default_sub_failed_msg="Currently using default configuration, cannot update"
update_local_sub_failed_msg="This is a local configuration, skipping this operation"
not_sub_exists_msg="Subscription does not exist"
auto_start_enabled_success_msg="Auto start has been enabled"
auto_start_turned_off_success_msg="Auto start has been turned off"
status_running_msg="Status: Running"
status_not_running_msg="Status: Not running"
status_clash_version_msg="Clash version:"
status_sub_name_msg="Current subscription:"
status_auto_start_msg="Auto start on boot:"
status_clash_binary_path_msg="Clash installation path:"
status_proxy_msg="Local proxy status:"
status_gateway_msg="Gateway status:"
status_clash_address_msg="Clash access address:"
status_clash_controller_secret_msg="Clash access token:"
status_clash_ui_address_msg="Clash UI access address:"
list_sub_url_msg="Subscription URL:"
list_sub_update_interval_msg="Update interval:"
proxy_port_update_msg="Detected Clash HTTP proxy port has changed and proxy is enabled, please reset proxy"
proxy_enable_reminder_msg="Detected proxy is enabled, please remember to disable it"
proxy_enable_failed_msg="Detected proxy is enabled, please disable it before uninstalling"
non_proxy_source_msg="Do not use 'source' to execute commands other than 'proxy'"
proxy_source_required_msg="Please use 'source' to execute the proxy command"
proxy_bypass_hosts_source_command_msg="Please use 'source' to execute the proxy command"
proxy_on_success_msg="Proxy has been enabled"
proxy_off_success_msg="Proxy has been disabled"
proxy_system_profile_msg="System proxy profile written: %s"
proxy_system_env_msg="System environment updated: %s"
proxy_system_systemd_msg="Systemd proxy config written: %s"
proxy_nm_msg="NetworkManager proxy set for connection: %s"
proxy_lxde_env_msg="LXQt/LXDE: proxy set via environment variables (shell + system level)"
proxy_already_on_msg="Proxy is already enabled, skipping"
proxy_already_off_msg="Proxy is already disabled, skipping"
proxy_no_port_msg="No valid proxy port found in config"
proxy_invalid_port_msg="Invalid proxy port: %s"
proxy_port_unreachable_msg="Warning: port %s is not reachable (proxy may not be ready)"
proxy_root_needed_msg="Root privileges needed for system-level proxy settings (skipping)"
proxy_partial_msg="%d/%d steps had errors"
proxy_applied_msg="Applied to: %s"
proxy_cleanup_incomplete_msg="Proxy cleanup incomplete, some settings may remain"
gateway_enable_success_msg="Gateway has been enabled"
gateway_disable_success_msg="Gateway has been disabled"
gateway_set_failed_msg="Gateway setting failed"
config_key_error_msg="Configuration key does not exist"
conf_failed_msg="Configuration file error"
update_downgrade_warn_msg="Cannot downgrade from %s to %s"
update_confirm_msg="Update from %s to %s?"

logs_view_msg="Viewing Clash logs (last 50 lines, press q to exit):"
logs_empty_msg="No logs available"
logs_follow_msg="Following logs (Ctrl+C to exit)..."
logs_search_prompt_msg="Enter search keyword:"
logs_search_result_msg="Found %s matches for '%s':"
logs_filter_empty_msg="No logs found for this level"

autostart_status_enabled_msg="Auto Start: Enabled"
autostart_status_disabled_msg="Auto Start: Disabled"
gateway_status_enabled_msg="Gateway: Enabled"
gateway_status_disabled_msg="Gateway: Disabled"
proxy_status_enabled_msg="Local Proxy: Enabled"
proxy_status_disabled_msg="Local Proxy: Disabled"
toggle_autostart_msg="Toggle auto start"
toggle_gateway_msg="Toggle gateway"
toggle_proxy_msg="Toggle local proxy"
backup_success_msg="Backup created successfully"
backup_failed_msg="Backup failed"
backup_restore_success_msg="Configuration restored successfully"
backup_restore_failed_msg="Restore failed"
backup_list_empty_msg="No backups found"
backup_delete_success_msg="Backup deleted"
backup_name_msg="Enter backup name:"
backup_confirm_msg="Confirm restore this backup?"
backup_not_exist_msg="Backup does not exist"
health_check_running_msg="Running health check..."
health_check_ok_msg="Clash is healthy"
health_check_failed_msg="Clash health check failed"
health_check_auto_recovery_enabled_msg="Auto-recovery enabled"
health_check_auto_recovery_disabled_msg="Auto-recovery disabled"
health_check_auto_recovery_status_msg="Auto-recovery status:"
health_clash_uptime_msg="Clash uptime:"
health_clash_memory_msg="Clash memory usage:"
health_clash_cpu_msg="Clash CPU usage:"
health_clash_connections_msg="Active connections:"
rules_builtin_msg="Built-in Rules"
rules_custom_msg="Custom Rules"
rules_provider_msg="Rule Providers"
rules_enabled_msg="Enabled"
rules_disabled_msg="Disabled"
rules_not_found_msg="No rules found"
rules_add_prompt_msg="Enter rule (e.g. DOMAIN,example.com,Proxy):"
rules_add_success_msg="Rule added successfully"
rules_add_failed_msg="Failed to add rule"
rules_delete_success_msg="Rule deleted successfully"
profile_switch_success_msg="Profile switched successfully"
profile_create_success_msg="Profile created successfully"
profile_delete_success_msg="Profile deleted"
profile_not_exist_msg="Profile does not exist"
profile_name_msg="Enter profile name:"
profile_already_exists_msg="Profile already exists"
profile_failed_msg="Failed to create profile"
profile_switch_failed_msg="Failed to switch profile"
config_file_not_found_msg="Configuration file not found"
backup_list_title_msg="Available backups:"
backup_path_msg="Backup:"
profile_list_title_msg="Available profiles:"
backup_select_name_required_msg="Please specify backup name"
profile_select_name_required_msg="Please specify profile name"
config_key_required_msg="Please specify config key"

# help 行输出辅助：按显示宽度对齐
_help_row() {
    local _hr_cmd="$1" _hr_param="$2" _hr_desc="$3"
    local _hr_cmd_w=20 _hr_param_w=30
    local _hr_cw=$(str_display_width "$_hr_cmd")
    local _hr_pw=$(str_display_width "$_hr_param")
    local _hr_cp=$((_hr_cmd_w - _hr_cw))
    local _hr_pp=$((_hr_param_w - _hr_pw))
    [ "$_hr_cp" -lt 1 ] && _hr_cp=1
    [ "$_hr_pp" -lt 1 ] && _hr_pp=1
    printf "    %s%${_hr_cp}s%s%${_hr_pp}s%s\n" "$_hr_cmd" "" "$_hr_param" "" "$_hr_desc"
}

show_help() {
    printf "%b\n" "${COLOR_CYAN}${COLOR_BOLD}  Clash for Linux - Command Reference${COLOR_RESET}"
    printf "%b\n" "${COLOR_CYAN}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
    printf "%b\n" "${COLOR_GREEN}  Direct:  clashtool.sh start|stop|restart|reload|status${COLOR_RESET}"
    printf "%b\n" "${COLOR_GREEN}  Grouped: clashtool.sh <group> <subcommand> [args]${COLOR_RESET}"
    printf "%b\n" "${COLOR_GREEN}  Install: Root -> /opt/clash + /usr/local/bin/clashtool${COLOR_RESET}"
    printf "%b\n" "${COLOR_GREEN}          User -> ~/.local/clash + ~/.local/bin/clashtool${COLOR_RESET}"
    printf "%b\n" ""
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  Direct Commands (Common Operations)${COLOR_RESET}"
    _help_row "start" "[name]" "Start Clash (default: current sub)"
    _help_row "stop" "" "Stop Clash service"
    _help_row "restart" "[name]" "Restart Clash"
    _help_row "reload" "[name]" "Reload Clash config"
    _help_row "status" "" "View Clash running status"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  subscribe  - Subscription Management${COLOR_RESET}"
    _help_row "subscribe add" "name::url::interval" "Add/modify subscription"
    _help_row "subscribe del" "name" "Delete subscription"
    _help_row "subscribe list" "" "List all subscriptions"
    _help_row "subscribe update" "[name|all]" "Update subscription file(s)"
    _help_row "subscribe auto-update" "on|off" "Enable/disable auto-update"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  nodes  - Node Selection & Testing${COLOR_RESET}"
    _help_row "nodes select" "" "Select proxy group/server (interactive)"
    _help_row "nodes test" "" "Test proxy delay (interactive)"
    _help_row "nodes urltest" "" "URL connectivity test (interactive)"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  proxy  - Proxy Control${COLOR_RESET}"
    _help_row "proxy" "" "Show proxy status (default)"
    _help_row "proxy on" "" "Enable system proxy (must use 'source')"
    _help_row "proxy off" "" "Disable system proxy (must use 'source')"
    _help_row "proxy status" "" "Show proxy status (interactive)"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  config  - Configuration${COLOR_RESET}"
    _help_row "config" "" "View all config items"
    _help_row "config get" "key" "Get config item value"
    _help_row "config set" "key::value" "Set/modify config item"
    _help_row "config del" "key" "Delete config item"
    _help_row "config edit" "" "Edit user.yaml in editor"
    _help_row "config tool" "key::value | key" "Edit clashtool config"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  install  - Installation${COLOR_RESET}"
    _help_row "install" "" "Install Clash core + UI (default)"
    _help_row "install core" "[version]" "Install Clash core only"
    _help_row "install ui" "dashboard|yacd|zashboard" "Install web UI only"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  uninstall  - Uninstallation${COLOR_RESET}"
    _help_row "uninstall" "" "Uninstall Clash core + UI (default)"
    _help_row "uninstall all" "" "Full uninstall (core + UI + configs)"
    _help_row "uninstall core" "" "Uninstall Clash core only"
    _help_row "uninstall core purge" "" "Uninstall core and remove config"
    _help_row "uninstall ui" "" "Uninstall web UI only"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  update  - Updates${COLOR_RESET}"
    _help_row "update" "[version]" "Update Clash core + UI (default)"
    _help_row "update core" "[version]" "Update Clash core only"
    _help_row "update ui" "dashboard|yacd|zashboard" "Update/replace UI only"
    _help_row "update script" "" "Update clashtool script"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  system  - System Settings${COLOR_RESET}"
    _help_row "system autostart" "on|off" "Enable/disable auto-start"
    _help_row "system gateway" "on|off" "Enable/disable gateway mode"
    _help_row "system check" "" "Check for script updates"
    printf "%b\n" "${COLOR_YELLOW}${COLOR_BOLD}  tools  - Tools & Maintenance${COLOR_RESET}"
    _help_row "tools logs" "" "View/search/filter logs"
    _help_row "tools backup" "" "Backup configuration"
    _help_row "tools list-backups" "" "List available backups"
    _help_row "tools restore" "" "Restore from backup (interactive)"
    _help_row "tools delete-backup" "" "Delete a backup (interactive)"
    _help_row "tools profiles" "" "List configuration profiles"
    _help_row "tools create-profile" "" "Create new profile (interactive)"
    _help_row "tools switch-profile" "" "Switch profile (interactive)"
    _help_row "tools delete-profile" "" "Delete profile (interactive)"
    _help_row "tools rules" "" "List available rules"
    _help_row "tools add-rule" "" "Add custom rule (interactive)"
    _help_row "tools edit-rules" "" "Edit rules file"
    _help_row "tools health" "" "Health check & status"
    _help_row "tools toggle-recovery" "" "Toggle auto-recovery"
    _help_row "tools symlink" "" "Repair clashtool symlink"
    printf "%b\n" "${COLOR_CYAN}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
    printf "%b\n" "${COLOR_DIM}  Interactive menu: run 'clashtool' without arguments${COLOR_RESET}"
    printf "%b\n" "${COLOR_DIM}  Proxy commands require: source clashtool.sh proxy on/off${COLOR_RESET}"
    printf "%b\n" "${COLOR_CYAN}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
}
main_msg="Invalid command. Type 'help' to view available commands."
unknown_command_msg="Unknown command: %s"
unknown_subcommand_msg="Unknown %s subcommand: %s"
unknown_group_msg="Unknown command group: %s"
use_help_hint_msg="Use 'help' to see available commands."
cannot_elevate_sudo_noninteractive_msg="Cannot elevate privileges: sudo requires password and current shell is non-interactive. Please run as root."
cannot_elevate_no_sudo_msg="Cannot elevate privileges: sudo not available and not in interactive shell"
cannot_elevate_no_way_msg="Cannot elevate privileges: neither sudo nor su is available. Please run this script as root user."
enter_root_password_msg="Please enter root password when prompted:"

# TUI status messages (defaults)
tui_stty_check_msg="Checking for dependencies: stty not found, attempting to install..."
tui_module_not_found_msg="TUI module not found, attempting to download..."
tui_unavailable_msg="TUI mode unavailable. Missing dependencies or non-interactive terminal."
tui_use_cli_hint_msg="Please install required dependencies or use command line mode:"
symlink_repair_confirm_msg="Symlink 'clashtool' is missing or broken. Repair now?"
symlink_repair_success_msg="Symlink repaired."
symlink_check_ok_msg="Symlink OK: %s -> %s"
symlink_broken_msg="Symlink broken: %s"
symlink_not_found_msg="Symlink 'clashtool' not found in PATH"
symlink_repair_done_msg="Symlink created: %s -> %s"
gateway_root_needed_msg="Gateway mode requires root privileges"
install_pre_check_msg="Pre-installation check..."
install_progress_msg="Installing... [%d/%d]"
install_verify_msg="Verifying installation..."
install_verify_pass_msg="Installation verification passed"
install_verify_fail_msg="Installation verification failed"
install_step_core_msg="Installing Clash core..."
install_step_yq_msg="Installing yq..."
install_step_mmdb_msg="Installing GeoIP database..."
install_step_ui_msg="Installing Web UI..."
install_step_symlink_msg="Creating symlink..."
install_step_service_msg="Creating service file..."
permission_denied_root_msg="Permission denied for '%s'."
permission_denied_user_msg="Operation '%s' requires root privileges."
permission_try_sudo_msg="Try: sudo %s %s"
docker_limited_msg="(Running in Docker: some operations may be limited)"
unsupported_archive_msg="Unsupported archive format: %s"
pre_check_fail_abort_msg="Pre-installation check failed. Aborting."
invalid_download_msg="Invalid download file, update failed"
invalid_sub_name_msg="Invalid subscription name: %s"
gateway_root_forward_msg="Gateway mode requires root privileges (IP forwarding setup)"
symlink_create_fail_msg="Failed to create symlink: %s"
docker_gateway_warn_msg="Running in Docker: gateway mode may not work (requires --cap-add=NET_ADMIN)"
pre_check_header_msg="=== Pre-installation Environment Check ==="
pre_check_root_msg="Running as: root (system-level install)"
pre_check_user_msg="Running as: user (user-level install)"
pre_check_docker_msg="Docker container environment detected"
pre_check_dir_ok_msg="Install directory writable: %s"
pre_check_dir_fail_msg="Install directory not writable: %s"
pre_check_symlink_ok_msg="Symlink directory ready: %s"
pre_check_symlink_fail_msg="Cannot create symlink directory: %s"
pre_check_tool_found_msg="Found: %s"
pre_check_tool_missing_msg="Missing: %s (will attempt to install)"
pre_check_net_ok_msg="Network connectivity: OK"
pre_check_net_warn_msg="Network connectivity: limited (downloads may fail)"
pre_check_fail_summary_msg="Pre-installation check failed with %d error(s)."
pre_check_pass_msg="Pre-installation check passed."
post_verify_header_msg="=== Post-installation Verification ==="
post_verify_clash_ok_msg="Clash binary: %s"
post_verify_clash_fail_msg="Clash binary not found or not executable"
post_verify_yq_ok_msg="yq binary: %s"
post_verify_yq_fail_msg="yq binary not found or not executable"
post_verify_cfg_ok_msg="Config directory: %s"
post_verify_cfg_fail_msg="Config directory missing"
post_verify_mmdb_ok_msg="GeoIP database: OK"
post_verify_mmdb_warn_msg="GeoIP database missing (geolocation may not work)"
post_verify_symlink_ok_msg="Symlink: %s -> %s"
post_verify_symlink_warn_msg="Symlink not created (manual: ln -sf %s %s)"
post_verify_cmd_ok_msg="Command 'clashtool' is available"
post_verify_cmd_info_msg="Run 'hash -r' or start a new shell to use 'clashtool' command"
post_install_hint_hash_msg="TIP: Run 'hash -r' (bash/zsh) or reopen terminal to use 'clashtool' command"
post_install_hint_export_msg="TIP: Run 'export PATH=\"%s:\$PATH\"' or reopen terminal to use 'clashtool' command"
post_verify_version_msg="Clash version: %s"
post_verify_fail_summary_msg="Verification failed with %d error(s)."
post_verify_pass_msg="Verification passed."
install_step_deps_msg="Installing dependencies..."
install_step_service_create_msg="Creating service files..."
install_step_init_dirs_msg="Initializing directories..."
install_step_download_yq_msg="Downloading yq..."
install_step_download_core_msg="Downloading GeoIP & Clash..."
symlink_created_msg="Symlink created: %s -> %s"
symlink_removed_msg="Symlink removed: %s"
user_level_skip_service_msg="User-level installation: skipping service file creation (requires root)"
user_level_autostart_on_msg="User-level auto-start enabled via %s"
user_level_autostart_off_msg="User-level auto-start disabled"
script_backup_msg="Original script backed up to: %s"
module_local_missing_msg="Local module %s not found, loading from GitHub online..."
module_online_load_ok_msg="%s loaded online successfully"
module_online_load_fail_msg="%s online load failed, using built-in English text"
piped_install_title_msg="Clash for Linux - Pipeline Installation"
piped_install_start_msg="Starting pipeline installation..."
piped_install_version_msg="Installing version: %s"
piped_install_download_msg="Downloading %s..."
piped_install_retry_msg="Retrying %s (%d/%d)..."
piped_install_success_msg="Full clashtool installation completed successfully"
piped_install_partial_msg="Partial installation completed, some modules failed: %s"

# 提权相关消息默认值
piped_root_required_msg="Pipeline installation requires root privileges. Please re-run with the following command:"
piped_root_command_msg="  curl -fsSL https://raw.githubusercontent.com/%s/clashtool.sh | sudo sh"

# 安装模式选择消息默认值
install_mode_prompt_msg="Select installation mode:"
install_mode_user_msg="User-level install (%s) - no root required"
install_mode_root_msg="System-level install (%s) - root required"
install_mode_choice_msg="Choose [1/2] (default 1): "
install_mode_user_selected_msg="Selected: user-level install"
install_mode_root_selected_msg="Selected: system-level install, elevating..."

# 检测系统语言，返回语言代码（如 zh_CN / en / zh_TW）
# 检测优先级：language 变量 > use_chinese 变量 > LANG 环境变量
detect_language() {
    # 1. 优先使用用户配置的 language 变量
    if [ -n "$language" ] && [ "$language" != "auto" ]; then
        echo "$language"
        return 0
    fi
    # 2. 向后兼容：use_chinese=true 时使用中文
    if [ "$use_chinese" = "true" ]; then
        echo "zh_CN"
        return 0
    fi
    # 3. 从 LANG 环境变量自动检测
    case "${LANG:-}" in
        zh_CN*|zh_Hans*) echo "zh_CN" ;;
        zh_TW*|zh_HK*|zh_Hant*) echo "zh_TW" ;;
        en_*) echo "en" ;;
        *) echo "en" ;;
    esac
}

# 交互式语言选择（管道安装时使用，从 /dev/tty 读取）
# 返回语言代码到 stdout
prompt_language() {
    # 此时 i18n 尚未加载，消息用双语硬编码
    printf "%b\n" "${COLOR_CYAN}请选择语言 / Select language:${COLOR_RESET}"
    printf "%b\n" "  [1] 简体中文 (zh_CN)"
    printf "%b\n" "  [2] English"
    printf "%b" "${COLOR_CYAN}请选择 / Choose [1/2] (auto-detect): ${COLOR_RESET}"
    # 管道安装时 stdin 被 curl 占用，从 /dev/tty 读取
    read _pl_choice </dev/tty 2>/dev/null || _pl_choice=""
    case "$_pl_choice" in
        1) echo "zh_CN" ;;
        2) echo "en" ;;
        *) detect_language ;;
    esac
}

# 加载 i18n 语言模块
# 参数: $1 - 语言代码（如 zh_CN / en / zh_TW）
# 英文(en)模块包含完整 menu_* 文本定义，必须加载以确保 TUI 菜单正常显示
load_i18n() {
    _li_lang="$1"
    [ -z "$_li_lang" ] && _li_lang="en"
    # 优先从 i18n/ 目录加载（本地优先，在线回退）
    _load_module "i18n/${_li_lang}.sh" && return 0
    # 向后兼容：回退到旧版 clashtool_i18n.sh（仅 zh_CN）
    if [ "$_li_lang" = "zh_CN" ]; then
        _load_module "clashtool_i18n.sh" && return 0
    fi
    return 1
}

# 向后兼容：保留 use_chinese_language() 函数
use_chinese_language(){
    load_i18n "zh_CN"
}
# 获取值
get_dict_value() {
    dict_prefix="$1"
    key="$2"
    case "$key" in *[!A-Za-z0-9_]*) return 1;; esac
    eval "echo \"\$${dict_prefix}_${key}\""
}
# 参数：
#   $1: section - 指定节
#   $2: file - 文件名
# 返回值：如果存在返回 0，否则返回 1
section_exists() {
    section=$1
    file=$2
    [ -z "$file" ] && return 1
    [ ! -f "$file" ] && return 1
    grep -q "^\[$section\]$" "$file"
    return $?
}

# 参数：
#   $1: section - 指定节
#   $2: key - 指定键
#   $3: value - 新值
#   $4: file - 文件名
update_ini() {
    local section="$1"
    local key="$2"
    local value="$3"
    local file="$4"
    local temp_file="${file}.tmp"

    [ -z "$file" ] && return 1
    [ ! -f "$file" ] && return 1

    awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section = 0; key_written = 0 }
    /^\s*\[.*\]/ {
        if (in_section && !key_written) {
            print key "=" value
            key_written = 1
        }
        in_section = ($0 == "[" section "]")
    }
    {
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        eq = index(line, "=")
        if (in_section && eq > 0) {
            k = substr(line, 1, eq - 1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            if (k == key) {
                $0 = key "=" value
                key_written = 1
            }
        }
        print
    }
    END {
        if (!key_written && in_section) {
            print key "=" value
        } else if (!key_written) {
            print "[" section "]"
            print key "=" value
        }
    }' "$file" > "$temp_file" && mv "$temp_file" "$file"
}
# 参数：
#   $1: section - 指定节
#   $2: key - 指定键
#   $3: file - 文件名
# 参数：
#   $1: section - 指定节
#   $2: file - 文件名
delete_ini_section() {
    section="$1"
    file="$2"
    local temp_file="${file}.tmp"

    [ -z "$file" ] && return 1
    [ ! -f "$file" ] && return 1

    awk -v section="$section" '
    BEGIN { in_section = 0 }
    /^\[.*\]$/ {
        if (in_section) in_section = 0
        if ($0 == "[" section "]") in_section = 1
    }
    !in_section { print }
    ' "$file" > "$temp_file" && mv "$temp_file" "$file"
}

# 参数：
#   $1: section - 指定节
#   $2: key - 指定键
#   $3: file - 文件名
# 返回值：指定节和键的值
find_ini() {
    local section="$1"
    local key="$2"
    local file="$3"

    # 文件为空或不存在时直接返回，避免 awk 卡在 stdin
    [ -z "$file" ] && return 1
    [ ! -f "$file" ] && return 1

    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^\s*\[.*\]/ {
        in_section = ($0 == "[" section "]")
    }
    in_section {
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        eq = index(line, "=")
        if (eq > 0) {
            k = substr(line, 1, eq - 1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            if (k == key) {
                print substr(line, eq + 1)
                exit
            }
        }
    }' "$file"
}

# 参数：$1: key - 变量名
find_clashtool_config() {
    key=$1
    [ -z "$tool_config_path" ] && return 1
    [ ! -f "$tool_config_path" ] && return 1
    find_ini 'clashtool' "${key}" "${tool_config_path}"
}

# 参数：
#   $1: key - 变量名
#   $2: val - 值
update_clashtool_config() {
    key=$1
    val=$2
    update_ini "clashtool" "${key}" "${val}" "${tool_config_path}"
}

# 参数：$1: sub_name - 订阅名称
subscription_exists() {
    sub_name=$1
    section_exists "subscribe_${sub_name}" "${tool_config_path}"
    return $?
}

# 参数：
#   $1: sec_name - 订阅名称
#   $2: key - 订阅地址
#   $3：val - 更新间隔时间
update_subscription_config() {
    sec_name=$1
    key=$2
    val=$3
    if [ -z "$sec_name" ]; then
        sec="subscribe"
    else
        sec="subscribe_$sec_name"
    fi
    update_ini "$sec" "$key" "$val" "$tool_config_path"
}

# 参数：
#   $1: name - 订阅名称
#   $2: url - 订阅地址
#   $3：interval - 更新间隔时间
add_subscription_config() {
    name=$1
    url=$2
    interval=$3
    {
        echo "[subscribe_$name]"
        echo "url=$url"
        echo "interval=$interval"
    } >> "$tool_config_path"
    # 更新names名称
    names=$(find_subscription_config '' 'names')${name}','
    update_subscription_config '' 'names' "${names}"
}

# 参数：$1: name - 订阅名称
delete_subscription_config() {
    name=$1
    # 更新names
    names=$(find_subscription_config '' 'names' | sed "s/${name},//g")
    update_subscription_config '' 'names' "$names"
    # 删除订阅节点
    delete_ini_section "subscribe_$name" "${tool_config_path}"
}

# 获取订阅配置
# 参数：
#   $1: name - 订阅名称
#   $2: key - 变量名
find_subscription_config() {
    name=$1
    key=$2
    if [ -z "${name}" ]; then
        sec="subscribe"
    else
        sec="subscribe_${name}"
    fi
    find_ini "${sec}" "${key}" "${tool_config_path}"
}
# 检查配置项是否存在
# 参数: $1=键路径, $2=配置文件路径
# 返回值: 0=存在, 1=不存在
config_exists() {
    key="$1"
    file="$2"
    
    # 直接使用 yq 检查键是否存在，不转换为 JSON
    "$yq_binary_path" e ".$key | tag == \"!!null\" | not" "$file" 2>/dev/null | grep -q "true"
}

# 插入新的 YAML 配置项（只在键不存在时插入）
# 参数: $1=键路径, $2=值, $3=配置文件路径
# 返回值: 0=插入成功, 1=键已存在或插入失败
add_yaml() {
    key="$1"
    value="$2"
    file="$3"

    # 校验 key 仅含字母数字、.、-、_，防止 yq 表达式注入
    case "$key" in *[!A-Za-z0-9._-]*) return 1;; esac

    # 检查键是否已存在
    if config_exists "$key" "$file"; then
        update_yaml "$key" "$value" "$file"
        return $?
    fi

    # 键不存在，插入新键值对（根据值类型选择表达式）
    case "$value" in
        true|false|null)
            "$yq_binary_path" e ".$key = $value" -i "$file" 2>/dev/null
            ;;
        ''|*[!0-9-]*)
            "$yq_binary_path" e ".$key = \"$value\"" -i "$file" 2>/dev/null
            ;;
        *)
            "$yq_binary_path" e ".$key = $value" -i "$file" 2>/dev/null
            ;;
    esac
    return $?
}

# 删除 YAML 配置项
# 参数: $1=键路径, $2=配置文件路径
# 返回值: 0=成功, 1=失败
delete_yaml() {
    key="$1"
    file="$2"
    
    # 直接删除，不检查是否存在（yq 会自动处理不存在的键）
    "$yq_binary_path" e "del(.$key)" -i "$file" 2>/dev/null
}

# 更新 YAML 配置项
# 参数: $1=键路径, $2=值, $3=配置文件路径
# 返回值: 0=成功, 1=失败
update_yaml() {
    key="$1"
    value="$2"
    file="$3"

    # 校验 key 仅含字母数字、.、-、_，防止 yq 表达式注入
    case "$key" in *[!A-Za-z0-9._-]*) return 1;; esac

    # 根据值类型选择 yq 表达式（数字/布尔不加引号，字符串加引号）
    case "$value" in
        true|false|null)
            "$yq_binary_path" e ".$key = $value" -i "$file" 2>/dev/null
            ;;
        ''|*[!0-9-]*)
            "$yq_binary_path" e ".$key = \"$value\"" -i "$file" 2>/dev/null
            ;;
        *)
            "$yq_binary_path" e ".$key = $value" -i "$file" 2>/dev/null
            ;;
    esac
}

# 查找 YAML 配置项值
# 参数: $1=键路径, $2=配置文件路径
# 输出: 配置项的值（如果存在）
find_yaml() {
    key="$1"
    file="$2"
    
    # 直接输出 YAML 值，过滤 null 返回
    local _fy_val=$("$yq_binary_path" e ".$key" "$file" 2>/dev/null)
    [ "$_fy_val" = "null" ] && return 1
    [ -z "$_fy_val" ] && return 1
    printf '%s' "$_fy_val"
}

add_user_config() {
    key="$1"
    val="$2"
    add_yaml "$key" "$val" "$user_config_path"
}

# 参数：
#   $1: key - 订阅名称
delete_user_config() {
    # 使用 sed 删除键的范围，不包括终点行
    delete_yaml "$1" "$user_config_path"
}

# 参数：$1 - YAML 文件路径
# 说明：之前 bug 版本可能将数字保存为字符串（如 port: "7895"），
#       此函数遍历所有顶层键，将 !!str 类型的纯数字/布尔值转为正确类型
fix_yaml_value_types() {
    _fyt_file="$1"
    [ ! -f "$_fyt_file" ] && return 1

    # 获取所有顶层键
    _fyt_keys=$("$yq_binary_path" e 'keys | .[]' "$_fyt_file" 2>/dev/null)
    [ -z "$_fyt_keys" ] && return 0

    _fyt_old_ifs="$IFS"
    IFS="
"
    for _fyt_key in $_fyt_keys; do
        [ -z "$_fyt_key" ] && continue
        # 获取值的标签类型
        _fyt_tag=$("$yq_binary_path" e '.["'"$_fyt_key"'"] | tag' "$_fyt_file" 2>/dev/null)
        # 只处理字符串类型
        [ "$_fyt_tag" != "!!str" ] && continue
        # 获取字符串值
        _fyt_val=$("$yq_binary_path" e '.["'"$_fyt_key"'"]' "$_fyt_file" 2>/dev/null)
        [ -z "$_fyt_val" ] && continue
        # 根据值内容判断是否需要转换类型
        case "$_fyt_val" in
            true|false|null)
                # 布尔/null 值，转为正确类型
                "$yq_binary_path" e '.["'"$_fyt_key"'"] = '"$_fyt_val" -i "$_fyt_file" 2>/dev/null
                ;;
            ''|*[!0-9-]*)
                # 包含非数字字符，保持字符串类型
                ;;
            *)
                # 纯数字，转为 int 类型
                "$yq_binary_path" e '.["'"$_fyt_key"'"] = '"$_fyt_val" -i "$_fyt_file" 2>/dev/null
                ;;
        esac
    done
    IFS="$_fyt_old_ifs"
    return 0
}

# 参数：
#   $1: key - 订阅名称
#   $2: val - 订阅值
update_user_config() {
    temp_file="${user_config_path}.tmp"
    cp "$user_config_path" "$temp_file"
    update_yaml "$1" "$2" "$temp_file"
    # 静默校验，失败时不输出错误（可能因旧字符串类型值导致）
    check_config "$temp_file" true
    if [ $? -ne 0 ]; then
        # 校验失败，尝试修复旧的字符串类型值后重试
        fix_yaml_value_types "$temp_file"
        check_config "$temp_file"
        if [ $? -ne 0 ]; then
            rm -f "$temp_file"
            return 1
        fi
    fi
    mv "$temp_file" "$user_config_path"
}
# 参数：
#   $1: key - 订阅名称
#   $2: file - 订阅文件
find_user_config(){
    key="$1"
    find_yaml "$key" "$user_config_path"
}

# 验证配置键值
# 参数: $1=键 $2=值
# 返回: 0=有效 1=无效
validate_config_value() {
    local _vcv_key="$1"
    local _vcv_val="$2"
    case "$_vcv_key" in
        port|socks-port|redir-port|tproxy-port|mixed-port)
            # 端口号: 1-65535
            if ! echo "$_vcv_val" | grep -qE '^[0-9]+$'; then
                warn "$(printf "$validate_port_msg" "$_vcv_key")" false
                return 1
            fi
            if [ "$_vcv_val" -lt 1 ] || [ "$_vcv_val" -gt 65535 ]; then
                warn "$(printf "$validate_port_range_msg" "$_vcv_key")" false
                return 1
            fi
            ;;
        allow-lan|ipv6|unified-delay)
            # 布尔值: true/false
            case "$_vcv_val" in
                true|false) ;;
                *) warn "$(printf "$validate_bool_msg" "$_vcv_key")" false; return 1 ;;
            esac
            ;;
        mode)
            # 枚举值: rule/global/direct
            case "$_vcv_val" in
                rule|global|direct) ;;
                *) warn "$(printf "$validate_enum_msg" "$_vcv_key" "rule, global, direct")" false; return 1 ;;
            esac
            ;;
        log-level)
            # 枚举值: silent/error/warning/info/debug
            case "$_vcv_val" in
                silent|error|warning|info|debug) ;;
                *) warn "$(printf "$validate_enum_msg" "$_vcv_key" "silent, error, warning, info, debug")" false; return 1 ;;
            esac
            ;;
        bind-address|interface-name|secret|external-ui)
            # 字符串: 非空即可
            if [ -z "$_vcv_val" ]; then
                warn "$(printf "$validate_required_msg" "$_vcv_key")" false
                return 1
            fi
            ;;
        external-controller)
            # 格式: 127.0.0.1:9090 或 :9090
            if ! echo "$_vcv_val" | grep -qE '^[0-9a-zA-Z.:]+$'; then
                warn "$(printf "$validate_format_msg" "$_vcv_key" "127.0.0.1:9090")" false
                return 1
            fi
            ;;
        global-client-fingerprint)
            # 枚举值
            case "$_vcv_val" in
                chrome|firefox|safari|ios|android|edge|360|qq|random|randomized) ;;
                *) warn "$(printf "$validate_enum_msg" "$_vcv_key" "chrome, firefox, safari, ios, android, edge, 360, qq, random, randomized")" false; return 1 ;;
            esac
            ;;
        routing-mark)
            # 数字
            if ! echo "$_vcv_val" | grep -qE '^[0-9]+$'; then
                warn "$(printf "$validate_number_msg" "$_vcv_key")" false
                return 1
            fi
            ;;
    esac
    return 0
}

# ==================== 输出格式优化 ====================
# 分隔线样式
SEPARATOR_LINE="──────────────────────────────────────────────────────────────"
SEPARATOR_DOUBLE="══════════════════════════════════════════════════════════════"
SEPARATOR_STAR="★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★"

# 参数：
#   $1: color_code - 状态颜色码
#   $2: status - 状态文本（OK/FAILED/WARN/REMIND/NORMAL）
#   $3: msg - 消息
#   $4: is_exit - 是否退出脚本 (true/false)，默认 false
# 失败消息
failed() {
    printf "%b\n" "${COLOR_RED}${SEPARATOR_LINE}${COLOR_RESET}"
    printf "\033[1;31m[✖ FAILED]\033[0m %s\n" "$1"
    printf "%b\n" "${COLOR_RED}${SEPARATOR_LINE}${COLOR_RESET}"
    if [ "${2:-true}" = "true" ] && ! _is_interactive_terminal; then
        exit 1
    fi
    return 1
}

# 警告消息
warn() {
    printf "\033[1;33m[⚠ WARN ]\033[0m %s\n" "$1"
    if [ "${2:-true}" = "true" ] && ! _is_interactive_terminal; then
        exit 1
    fi
    return 0
}

# 提醒消息
remind() {
    printf "\033[1;36m[ℹ INFO ]\033[0m %s\n" "$1"
    if [ "${2:-false}" = "true" ]; then exit 0; fi
}

# 成功消息
success() {
    printf "\033[1;32m[✔  OK  ]\033[0m %s\n" "$1"
    if [ "${2:-false}" = "true" ]; then exit 0; fi
}

# 正常消息
normal() {
    printf "\033[1;37m[  INFO ]\033[0m %s\n" "$1"
    if [ "${2:-false}" = "true" ]; then exit 0; fi
}

# 标题消息
# 子标题消息
# 进度消息
# 完成进度
# 显示带缩进的列表项
# 显示键值对
# 显示成功操作列表
# 显示错误详情
clash_ui_link_info(){
    ips=$(ip -o -4 addr show | awk '!/127.0.0.1/ {print $4}' | cut -d'/' -f1)
    port=$(find_user_config "external-controller" | awk -F ':' '{print $2}')
    echo "$status_clash_address_msg"
    for ip in $ips; do
        echo "    http://$ip:${port}"
    done
    echo "${status_clash_controller_secret_msg}${controller_secret}"
    if [ -d "$ui_install_dir" ];then
        echo "$status_clash_ui_address_msg"
        for ip in $ips; do
            echo "    http://$ip:${port}/ui"
        done
    fi
}
 
# 参数：$1: - 参数
verify() {
    if [ "$1" != 'true' ] && [ "$1" != 'false' ]; then
        failed "$verify_failed_msg"
        return 1
    fi
    return 0
}

# 参数：
#   $1：url - 网址
#   $2:enable - 无效是否退出脚本
check_url(){
    url=$1
    enable=${2:-true}
    # 判断地址是否有效
    normal "$sub_url_check_msg"
    if $subscription_use_proxy;then
        curl -sSf --max-time 30 "${github_proxy_url}${url}" > /dev/null
    else
        curl -sSf --max-time 30 "$url" > /dev/null
    fi
    req=$?
    if [ "$req" -eq 0 ]; then
        success "$sub_url_effective_msg"
    else
        failed "$sub_url_invalid_msg" "$enable"
    fi
    return $req
}

is_sourced() {
    # 使用POSIX兼容方式检测是否以source运行
    # 如果 $0 是 shell 名称（sh/bash/ksh 等），说明是 source 执行
    # 管道安装模式（curl | sh）中 $0 也是 shell 名称，但不是 source 执行，需排除
    if [ "$_is_piped_install" = "true" ]; then
        return 1
    fi
    case "$0" in
        sh|bash|ksh|dash|-sh|-bash|-ksh|-dash|*/sh|*/bash|*/ksh|*/dash)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 检测 UI 是否真正安装（以 index.html 存在为准，而非空目录）
is_ui_installed() {
    [ -f "${ui_install_dir}/index.html" ]
}

get_download_filename() {
    url="$1"
    # 尝试从URL中提取文件名
    filename=$(basename "$url")
    # 如果无法从URL中提取文件名，则获取文件头信息
    if [ -z "$filename" ]; then
        headers=$(curl -sI "$url")
        filename=$(echo "$headers" | grep -i 'Content-Disposition' | sed -e 's/.*filename=//')
        filename="${filename%\"}"
        filename="${filename#\"}"
        filename=$(basename "$filename" 2>/dev/null || echo "download")
    fi
    echo "$filename"
}

# 参数：
#   $1: interval - 运行时间，为空则删除定时任务
#   $2: command - 需要执行的命令
crontab_tool() {
    interval=$1
    command=$2
    # 读取当前的 crontab
    current_crontab=$(crontab -l 2>/dev/null)

    if [ -z "$interval" ]; then
        # 删除定时任务
        if echo "$current_crontab" | grep -qF "$command"; then
            echo "$current_crontab" | grep -vF "$command" | crontab -
        fi
    else
        # 添加或修改定时任务
        if echo "$current_crontab" | grep -qF "$command"; then
            # 定时任务已存在，修改
            current_crontab=$(echo "$current_crontab" | sed -e "\|$command|d")
        fi
        # 添加或更新定时任务
        (
            echo "$current_crontab"
            echo "$interval $command"
        ) | crontab -
    fi
}

# 参数：$1:name 程序名称
install_procedure(){
    name="$1"
    # 检查并安装
    if ! command -v "$name" >/dev/null 2>&1; then
        echo "${install_start_msg} $name"
        if command -v apt >/dev/null 2>&1; then
            apt install "$name" -y
        elif command -v yum >/dev/null 2>&1; then
            yum install "$name" -y
        elif command -v dnf >/dev/null 2>&1; then
            dnf install "$name" -y
        elif command -v zypper >/dev/null 2>&1; then
            zypper install "$name" -y    
        elif command -v apk >/dev/null 2>&1; then
            apk add "$name"
        elif command -v pacman >/dev/null 2>&1;then
            pacman -Sy --noconfirm "$name" 2>/dev/null
        else
            failed "$require_install_failed_msg $name"
            return 1
        fi
        # 校验是否安装成功
        if command -v "$name" > /dev/null; then
            success "$name $install_success_msg"
        else
            failed "$name $install_failed_msg"
            return 1
        fi
    fi
}

decompression() {
    archive_file="$1"
    destination="$2"

    # 检测输出目录，不存在则创建ss
    if [ ! -d "$destination" ]; then
        mkdir -p "$destination"
    fi

    # 使用 case 语句来匹配文件后缀
    case "$archive_file" in
        *.tar.gz)
            tar -xzf "$archive_file" -C "$destination"
            ;;
        *.tar)
            tar -xf "$archive_file" -C "$destination"
            ;;
        *.gz)
            gunzip -ck "$archive_file" > "$destination/$(basename "$archive_file" .gz)"
            ;;
        *.zip)
            unzip -q "$archive_file" -d "$destination"
            ;;
        *.rar)
            unrar x "$archive_file" "$destination"
            ;;
        *.7z)
            7z x "$archive_file" -o"$destination"
            ;;
        *.bz2)
            bunzip2 -ck "$archive_file" > "$destination/$(basename "$archive_file" .bz2)"
            ;;
        *)
            failed "$(printf "$unsupported_archive_msg" "$archive_file")"
            return 1
            ;;
    esac
}
get_target_platform(){
    if [ -z "${target_platform}" ]; then
        machine_arch=$(uname -m)
        # 检查架构类型并输出相应的信息
        case $machine_arch in
        x86_64 | amd64)
            target_platform="amd64"
            ;;
        aarch64 | arm64)
            target_platform="arm64"
            ;;
        i*86 | x86)
            target_platform="386"
            ;;
        arm*)
            target_platform="${machine_arch}"
            ;;
        *)
            failed "$recognition_system_failed_msg"
        esac
    fi
}

get_linux_distribution() {
    if [ -f /etc/lsb-release ] || [ -f /etc/ubuntu-release ]; then
        distribution="ubuntu"
    elif [ -f /etc/debian_version ];then
        distribution="debian"
    elif [ -f /etc/arch-release ]; then
        distribution="arch"
    elif [ -f /etc/centos-release ]; then
        distribution="centos"
    elif [ -f /etc/redhat-release ];then
        distribution="redhat"
    elif [ -f /etc/alpine-release ];then
        distribution="alpine"
    else
        failed "$unsupported_linux_distribution_failed_msg"
    fi
    echo "$distribution"
}

require() {
    normal "$require_check_msg"
    for _req_dep in tar curl unzip gunzip; do
        install_procedure "$_req_dep"
    done
}
init_config() {
    normal "$init_config_start_msg"
    for _ic_dir in "$install_dir" "$config_dir" "$log_dir" "$subscription_dir" "$subscription_backup_dir" "$ui_install_dir"; do
        [ -d "$_ic_dir" ] || mkdir -p "$_ic_dir"
    done
    
    # 检查并创建 clashtool 配置文件
    if [ ! -f "$tool_config_path" ]; then
        cat <<EOF > "${tool_config_path}"
[clashtool]
ui=dashboard
yq_version=
mmdb_version=
clash_version=
gateway=false
auto_start=false
auto_update_sub=true
http_port=7890
socks_port=7891
[subscribe]
names=
use=default
EOF
    fi
    
    # 检查并创建默认用户自定义的 clash 配置文件
    if [ ! -f "$user_config_path" ]; then
        # 未自定义网页密码则产生随机密码
        if [ -z "$controller_secret" ]; then
            controller_secret=$(tr -dc a-zA-Z0-9#@ 2>/dev/null < /dev/urandom | head -c 12)
        fi
        cat <<EOF > "${user_config_path}"
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: error
external-controller: 0.0.0.0:9090
secret: ${controller_secret}
EOF
    fi
    # 检查并创建默认tun模式的clash 配置文件
    if [ ! -f "$gateway_config_path" ]; then
        cat <<EOF > "${gateway_config_path}"
tun:
  enable: true
  stack: mixed
  dns-hijack:
    - any:53
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  mtu: 1500
  udp-timeout: 60
dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localhost'
    - 'localhost'
    - 'localhost.*'
    - 'localhost.localdomain'
    - 'time.*.com'
    - 'time.*.gov'
    - 'ntp.*.com'
    - '*.ntp.org.cn'
    - '+.pool.ntp.org'
    - 'time1.cloud.tencent.com'
    - 'msftconnecttest.com'
    - 'msftncsi.com'
    - 'xbox.*.microsoft.com'
    - '*.xboxlive.com'
    - 'stun.*.*'
    - 'stun.*.*.*'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
    - '+.stun.*.*.*.*'
    - 'heartbeat.belkin.com'
    - '*.linksys.com'
    - '*.linksyssmartwifi.com'
    - '*.router.asus.com'
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
EOF
    fi
    success "$init_config_success_msg"
}

# 参数：
#   $1: file_path - 下载后保存的文件名
#   $2: url - 要下载的文件的URL
#   $3: tag - 输出提示标签
#   $4: enable - 是否使用github代理
download(){
    file_path=$1
    url=$2
    tag=$3
    enable=${4:-true}
    temp_file="${file_path}.download"
    normal "${download_start_msg}${tag}"
    # 关闭本shell进程代理
    if is_proxy;then
        for key in $proxy_protocols 'no'; do
            unset "${key}_proxy"
        done
    fi
    # 设置github代理
    if [ "$enable" = "true" ];then
        url="${github_proxy_url}${url}"
    fi
    # 重试计数
    retry_count=0
    # 使用curl下载文件
    while [ "$retry_count" -lt "$download_max_retries" ]; do
        curl "${url}" -o "$temp_file"
        # 检查curl命令的退出状态为0并且下载的文件存在
        # 兼容不同系统的stat命令
        if [ $? -eq 0 ] && [ -f "$temp_file" ]; then
            if command -v stat >/dev/null 2>&1; then
                if stat -c%s "$temp_file" >/dev/null 2>&1; then
                    file_size=$(stat -c%s "$temp_file")
                else
                    file_size=$(stat -f%z "$temp_file" 2>/dev/null || wc -c < "$temp_file")
                fi
            else
                file_size=$(wc -c < "$temp_file")
            fi
            if [ "$file_size" -gt 1024 ]; then
                # 下载成功，移动临时文件到目标位置
                mv "$temp_file" "$file_path"
                success "${tag}${download_success_msg}"
                break
            fi
        fi
        retry_count=$(expr "$retry_count" + 1)
        if [ "$retry_count" -lt "$download_max_retries" ]; then
            normal "$download_waiting_msg"
            sleep 5
        else
            # 清理临时文件
            rm -f "$temp_file"
            normal "${download_path_msg}${url}"
            failed "${tag}${download_failed_msg}"
            return 1
        fi
    done
}

get_repo_version(){
    api_url="https://api.github.com/repos/$1/releases/latest"
    version=$(curl -s "$api_url" 2>/dev/null | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':v?' '{print $2}' | tr -d '\n')
    echo "$version"
}

# 参数：
#   $1: repo - GitHub仓库地址（如 "MetaCubeX/mihomo"）
#   $2: releases_file - 发布文件路径模板（如 "v:version:/mihomo-linux-:target_platform:-v:version:.gz"）
#   $3: target_path - 最终目标路径
#   $4: version_key - 配置文件中的版本键名（如 "clash_version"）
#   $5: display_name - 显示名称（如 "Clash"）
#   $6: version - 指定版本（可选）
#   $7: is_archive - 是否为需要解压的压缩包（true/false）
download_github_release() {
    local repo="$1"
    local releases_file="$2"
    local target_path="$3"
    local version_key="$4"
    local display_name="$5"
    local version="$6"
    local is_archive="${7:-false}"
    
    # 获取系统型号
    get_target_platform
    
    # 没有指定版本则获取最新版本
    if [ -z "$version" ]; then
        version=$(get_repo_version "$repo")
        if [ -z "$version" ]; then
            failed "$get_version_failed_msg"
        fi
    fi
    
    # 显示版本信息
    normal "${latest_version_msg}${version}"
    local current=$(find_clashtool_config "$version_key")
    if [ -n "$current" ]; then
        normal "${current_version_msg}${current}"
    fi
    
    # 判断版本是否相等
    if [ "${current}" = "${version}" ]; then
        warn "$install_equal_versions_warn_msg" false
    fi
    
    # 构建下载URL
    local temp_releases_file=$(echo "$releases_file" | sed "s/:target_platform:/${target_platform}/g" | sed "s/:version:/${version}/g")
    local url="https://github.com/${repo}/releases/download/${temp_releases_file}"
    local download_name=$(get_download_filename "$url")
    local temp_file_path="${install_dir}/${download_name}"
    
    # 下载文件
    download "$temp_file_path" "$url" "$download_name"
    normal "${install_start_msg} ${display_name}"
    
    if [ "$is_archive" = "true" ]; then
        # 解压文件
        local temp_file_dir="${install_dir}/temp_${version_key}"
        decompression "$temp_file_path" "$temp_file_dir"
        
        # 查找可执行文件
        local find_result=$(find "$temp_file_dir" -type f \( -name "*clash*" -o -name "*mihomo*" \) -print)
        if [ -z "$find_result" ]; then
            rm -rf "$temp_file_path"
            rm -rf "$temp_file_dir"
            failed "${file_does_not_exist} ${display_name}"
            return 1
        fi
        
        # 移动到目标位置
        mv "$find_result" "$target_path"
        
        # 清理临时文件
        rm -rf "$temp_file_path"
        rm -rf "$temp_file_dir"
    else
        # 直接移动到目标位置
        mv "$temp_file_path" "$target_path"
    fi
    
    # 赋予运行权限（如果是可执行文件）
    if [ "$is_archive" = "true" ] || [ "${display_name}" = "yq" ]; then
        chmod +x "$target_path"
    fi
    
    # 更新版本配置
    update_clashtool_config "$version_key" "$version"
    success "${display_name} $install_success_msg"
}

# 参数：$1: version - Clash版本
download_clash(){
    download_github_release "$clash_repo" "$clash_release_pattern" "$clash_binary_path" "clash_version" "Clash" "$1" "true"
}

download_yq(){
    download_github_release "$yq_repo" "$yq_release_pattern" "$yq_binary_path" "yq_version" "yq" "$1" "false"
}

download_mmdb(){
    download_github_release "$mmdb_repo" "$mmdb_release_pattern" "${config_dir}/Country.mmdb" "mmdb_version" "mmdb" "$1" "false"
}

clear(){
    all=$1
    # 如果已安装则报错
    if [ -f "$clash_binary_path" ];then
        failed "Clash $was_install_msg"
        return 1
    fi
    # 如果存在残余则清零
    if [ -d "$install_dir" ];then
        # 删除Clash所有相关文件
        if [ "$all" = "all" ];then
            rm -rf "${install_dir}"
        else
            # 保留 log_dir、config_dir、ui_install_dir
            # ui_install_dir 由 uninstall_ui 单独管理，避免核心卸载后 UI 检测失效
            find "$install_dir" -mindepth 1 -maxdepth 1 \
            -not -path "$log_dir" \
            -not -path "$config_dir" \
            -not -path "$ui_install_dir" \
            -exec rm -rf {} +
            # 向clash配置文件写入版本为空
            update_clashtool_config 'yq_version' ""
            update_clashtool_config 'mmdb_version' ""
            update_clashtool_config 'clash_version' ""
        fi
    fi
}

# 检查目标路径、权限、依赖工具
pre_install_check() {
    local _pic_errors=0

    printf "%b\n" "${COLOR_CYAN}${pre_check_header_msg}${COLOR_RESET}"

    # 1. 检测运行模式
    if is_root; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$pre_check_root_msg"
    else
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$pre_check_user_msg"
    fi

    # 2. Docker 环境检测
    if is_docker; then
        printf "  [%bINFO%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$pre_check_docker_msg"
    fi

    # 3. 检查安装目录
    local _pic_parent
    _pic_parent=$(dirname "$install_dir" 2>/dev/null)
    if [ -n "$_pic_parent" ] && [ -w "$_pic_parent" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$pre_check_dir_ok_msg" "$install_dir")"
    elif [ -d "$install_dir" ] && [ -w "$install_dir" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$pre_check_dir_ok_msg" "$install_dir")"
    else
        printf "  [%bFAIL%b] %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$(printf "$pre_check_dir_fail_msg" "$install_dir")"
        _pic_errors=$((_pic_errors + 1))
    fi

    # 4. 检查软链接目录
    if ensure_dir "$symlink_dir" 755; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$pre_check_symlink_ok_msg" "$symlink_dir")"
    else
        printf "  [%bFAIL%b] %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$(printf "$pre_check_symlink_fail_msg" "$symlink_dir")"
        _pic_errors=$((_pic_errors + 1))
    fi

    # 5. 检查依赖工具
    for _pic_tool in curl tar unzip gunzip; do
        if command -v "$_pic_tool" >/dev/null 2>&1; then
            printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$pre_check_tool_found_msg" "$_pic_tool")"
        else
            printf "  [%bWARN%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$(printf "$pre_check_tool_missing_msg" "$_pic_tool")"
        fi
    done

    # 6. 检查网络连通性
    if curl -s --max-time 3 http://www.gstatic.com/generate_204 >/dev/null 2>&1; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$pre_check_net_ok_msg"
    else
        printf "  [%bWARN%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$pre_check_net_warn_msg"
    fi

    if [ "$_pic_errors" -gt 0 ]; then
        printf "\n%b\n" "${COLOR_RED}$(printf "$pre_check_fail_summary_msg" "$_pic_errors")${COLOR_RESET}"
        return 1
    fi
    printf "\n%b\n" "${COLOR_GREEN}${pre_check_pass_msg}${COLOR_RESET}"
    return 0
}

# 参数: $1 - 当前步骤, $2 - 总步骤数, $3 - 描述
show_progress() {
    local _sp_cur="$1"
    local _sp_total="$2"
    local _sp_desc="$3"
    local _sp_pct=$(( (_sp_cur * 100) / _sp_total ))
    local _sp_bar_len=30
    local _sp_filled=$(( (_sp_cur * _sp_bar_len) / _sp_total ))
    local _sp_empty=$((_sp_bar_len - _sp_filled))
    local _sp_bar=""
    local _sp_i=0
    while [ "$_sp_i" -lt "$_sp_filled" ]; do
        _sp_bar="${_sp_bar}#"
        _sp_i=$((_sp_i + 1))
    done
    _sp_i=0
    while [ "$_sp_i" -lt "$_sp_empty" ]; do
        _sp_bar="${_sp_bar}-"
        _sp_i=$((_sp_i + 1))
    done
    printf "\r  [%s] %3d%% %s" "$_sp_bar" "$_sp_pct" "$_sp_desc"
    [ "$_sp_cur" = "$_sp_total" ] && printf "\n"
}

post_install_verify() {
    local _piv_errors=0
    printf "%b\n" "${COLOR_CYAN}${post_verify_header_msg}${COLOR_RESET}"

    # 1. 验证 clash 二进制
    if [ -f "$clash_binary_path" ] && [ -x "$clash_binary_path" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$post_verify_clash_ok_msg" "$clash_binary_path")"
    else
        printf "  [%bFAIL%b] %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$post_verify_clash_fail_msg"
        _piv_errors=$((_piv_errors + 1))
    fi

    # 2. 验证 yq 工具
    if [ -f "$yq_binary_path" ] && [ -x "$yq_binary_path" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$post_verify_yq_ok_msg" "$yq_binary_path")"
    else
        printf "  [%bFAIL%b] %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$post_verify_yq_fail_msg"
        _piv_errors=$((_piv_errors + 1))
    fi

    # 3. 验证配置目录
    if [ -d "$config_dir" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$post_verify_cfg_ok_msg" "$config_dir")"
    else
        printf "  [%bFAIL%b] %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$post_verify_cfg_fail_msg"
        _piv_errors=$((_piv_errors + 1))
    fi

    # 4. 验证 GeoIP 数据库
    if [ -f "${config_dir}/Country.mmdb" ]; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$post_verify_mmdb_ok_msg"
    else
        printf "  [%bWARN%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$post_verify_mmdb_warn_msg"
    fi

    # 5. 验证软链接
    if check_symlink; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$post_verify_symlink_ok_msg" "$symlink_path" "$script_path")"
    else
        printf "  [%bWARN%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$(printf "$post_verify_symlink_warn_msg" "$script_path" "$symlink_path")"
    fi

    # 6. 验证命令可用性
    if check_cmd_available; then
        printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$post_verify_cmd_ok_msg"
    else
        printf "  [%bINFO%b] %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$post_verify_cmd_info_msg"
    fi

    # 7. 验证 clash 版本
    if [ -x "$clash_binary_path" ]; then
        local _piv_ver
        _piv_ver=$("$clash_binary_path" -v 2>&1 | head -1)
        if [ -n "$_piv_ver" ]; then
            printf "  [%bOK%b] %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$(printf "$post_verify_version_msg" "$_piv_ver")"
        fi
    fi

    if [ "$_piv_errors" -gt 0 ]; then
        printf "\n%b\n" "${COLOR_RED}$(printf "$post_verify_fail_summary_msg" "$_piv_errors")${COLOR_RESET}"
        return 1
    fi
    printf "\n%b\n" "${COLOR_GREEN}${post_verify_pass_msg}${COLOR_RESET}"
    return 0
}

# 优化的管道安装函数：下载完整版本的 clashtool（主脚本 + TUI + i18n）
# 参数: $1 - 目标脚本路径
# 返回: 0=成功, 1=失败
_install_piped_full() {
    _ipf_script_path="$1"
    _ipf_install_dir=$(dirname "$_ipf_script_path")
    _ipf_success=true
    _ipf_errors=""
    
    _ipf_base_url="${github_proxy_url}https://raw.githubusercontent.com/${project_repo}"
    
    _ipf_download_file() {
        _df_url="$1"
        _df_path="$2"
        _df_name="$3"
        _df_max_retries="${4:-3}"
        _df_timeout="${5:-20}"
        
        _df_retry=0
        _df_success=false
        while [ "$_df_retry" -lt "$_df_max_retries" ]; do
            rm -f "$_df_path.download" 2>/dev/null
            if [ "$_df_retry" -gt 0 ]; then
                warn "$(printf "$piped_install_retry_msg" "$_df_name" "$_df_retry" "$_df_max_retries")" false
            else
                normal "$(printf "$piped_install_download_msg" "$_df_name")"
            fi
            if curl -s --max-time "$_df_timeout" -o "$_df_path.download" "$_df_url" 2>/dev/null; then
                if [ -f "$_df_path.download" ] && [ -s "$_df_path.download" ] && grep -q '^#' "$_df_path.download" 2>/dev/null; then
                    mv "$_df_path.download" "$_df_path"
                    _df_success=true
                    break
                fi
            fi
            _df_retry=$((_df_retry + 1))
            [ "$_df_retry" -lt "$_df_max_retries" ] && sleep 3
        done
        
        if [ "$_df_success" = "true" ]; then
            normal "$(printf "$module_online_load_ok_msg" "$_df_name")"
            return 0
        else
            rm -f "$_df_path.download" 2>/dev/null
            _ipf_errors="${_ipf_errors}${_df_name} "
            _ipf_success=false
            return 1
        fi
    }
    
    normal "$(printf "$piped_install_title_msg")"
    normal "$(printf "$piped_install_start_msg")"
    
    normal "$(printf "$module_local_missing_msg" "clashtool modules")"
    
    _ipf_download_file "${_ipf_base_url}/clashtool.sh" "$_ipf_script_path" "clashtool.sh" 3 30
    chmod 755 "$_ipf_script_path" 2>/dev/null

    # TUI 模块已合并到 clashtool.sh 中，无需单独下载

    mkdir -p "${_ipf_install_dir}/i18n" 2>/dev/null
    for _ipf_lang in zh_CN en; do
        _ipf_download_file "${_ipf_base_url}/i18n/${_ipf_lang}.sh" "${_ipf_install_dir}/i18n/${_ipf_lang}.sh" "i18n/${_ipf_lang}.sh" 3 15
        chmod 644 "${_ipf_install_dir}/i18n/${_ipf_lang}.sh" 2>/dev/null
    done
    
    if [ "$_ipf_success" = "false" ]; then
        failed "$(printf "$piped_install_partial_msg" "$_ipf_errors")"
        return 1
    fi
    
    _ipf_ver=$(grep '^# version:' "$_ipf_script_path" | head -1 | sed 's/# version://')
    if [ -n "$_ipf_ver" ]; then
        normal "$(printf "$piped_install_version_msg" "$_ipf_ver")"
    fi
    
    normal "$(printf "$piped_install_success_msg")"
    
    return 0
}

# 安装模式选择
# 返回: 0=用户级安装, 1=系统级安装
prompt_install_mode() {
    # 确定用户级安装的目标路径
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        _pim_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        [ -z "$_pim_home" ] && _pim_home="/home/$SUDO_USER"
    else
        _pim_home="$HOME"
    fi
    printf "%b\n" "${COLOR_CYAN}${install_mode_prompt_msg}${COLOR_RESET}"
    printf "%b\n" "  [1] $(printf "$install_mode_user_msg" "${_pim_home}/.local/${service_name}")"
    printf "%b\n" "  [2] $(printf "$install_mode_root_msg" "/opt/${service_name}")"
    printf "%b" "${COLOR_CYAN}${install_mode_choice_msg}${COLOR_RESET}"
    # 管道安装时 stdin 被 curl 占用，从 /dev/tty 读取
    read _pim_choice </dev/tty 2>/dev/null || _pim_choice=""
    case "$_pim_choice" in
        2) return 1 ;;
        *) return 0 ;;
    esac
}

# 设置安装路径（覆盖脚本初始化时的路径变量）
# 参数: $1=mode (user/root)
set_install_paths() {
    _sip_mode="$1"
    if [ "$_sip_mode" = "user" ]; then
        # 自动确定目标家目录：root+sudo 用 SUDO_USER 的家目录，否则用 $HOME
        if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            _sip_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
            [ -z "$_sip_home" ] && _sip_home="/home/$SUDO_USER"
        else
            _sip_home="$HOME"
        fi
        _is_root_user=false
        _run_mode="user"
        install_dir="${_sip_home}/.local/${service_name}"
        symlink_dir="${_sip_home}/.local/bin"
        mkdir -p "$symlink_dir" 2>/dev/null
        chmod 0700 "$symlink_dir" 2>/dev/null
    else
        _is_root_user=true
        _run_mode="root"
        install_dir="/opt/${service_name}"
        symlink_dir="/usr/local/bin"
    fi
    symlink_path="${symlink_dir}/${cmd_name}"
    script_path="${install_dir}/clashtool.sh"
    ui_install_dir="${install_dir}/ui"
    log_dir="${install_dir}/logs"
    config_dir="${install_dir}/config"
    subscription_dir="${config_dir}/subscription"
    subscription_backup_dir="${subscription_dir}/backup"
    clash_binary_path="${install_dir}/clash"
    yq_binary_path="${install_dir}/yq"
}

# 参数: $1：version - clash版本 （可为空），默认为最新版本
install() {
    clash_version=$1
    # 如果已安装则报错
    if [ -f "$clash_binary_path" ];then
        failed "Clash $was_install_msg"
        return 1
    fi

    # 安装前环境检测
    if ! pre_install_check; then
        failed "$pre_check_fail_abort_msg"
        return 1
    fi
    
    local _inst_total=6
    
    # 步骤1: 检测安装依赖软件
    show_progress 1 "$_inst_total" "$install_step_deps_msg"
    require
    
    # 步骤2: 创建服务脚本
    show_progress 2 "$_inst_total" "$install_step_service_create_msg"
    create_service_file
    
    # 步骤3: 初始化目录配置
    show_progress 3 "$_inst_total" "$install_step_init_dirs_msg"
    init_config
    
    # 复制当前脚本到安装目录
    if [ "$_is_piped_install" = "true" ]; then
        _install_piped_full "$script_path"
    else
        # 正常模式：复制本地脚本
        cp "$(readlink -f "$0")" "$script_path"
        # TUI 模块已合并到 clashtool.sh 中，无需单独复制
        # 同时复制 i18n 目录到安装目录（多语言支持）
        _i18n_src_dir="$(dirname "$(readlink -f "$0" 2>/dev/null)")/i18n"
        if [ -d "$_i18n_src_dir" ]; then
            mkdir -p "${install_dir}/i18n"
            cp "${_i18n_src_dir}/"*.sh "${install_dir}/i18n/" 2>/dev/null
            chmod 644 "${install_dir}/i18n/"*.sh 2>/dev/null
        fi
    fi
    
    # 步骤4: 下载 yq
    show_progress 4 "$_inst_total" "$install_step_download_yq_msg"
    if [ ! -f "$yq_binary_path" ];then
        download_yq "$yq_version"
    fi
    
    # 步骤5: 下载 mmdb 和 clash
    show_progress 5 "$_inst_total" "$install_step_download_core_msg"
    if [ ! -f "${config_dir}/Country.mmdb" ];then
        download_mmdb "$mmdb_version"
    fi
    download_clash "$clash_version"
    
    # 步骤6: 创建软链接
    show_progress 6 "$_inst_total" "$install_step_symlink_msg"
    if repair_symlink; then
        normal "$(printf "$symlink_created_msg" "$symlink_path" "$script_path")"
    else
        warn "$(printf "$symlink_create_fail_msg" "$symlink_path")" false
    fi
    
    # 安装后功能验证
    post_install_verify

    success "Clash $install_success_msg"
    # 提示：clashtool.sh 作为子进程运行，无法直接修改父 shell 的 PATH 和 hash 表
    post_install_hint
}

# 参数: $1：all -（可为空），默认不删除配置信息
uninstall() {
    _un_arg=$1
    # 支持 purge 参数：卸载核心并删除配置文件
    case "$_un_arg" in
        purge|all)
            _un_clear_mode="all"
            ;;
        *)
            _un_clear_mode=""
            ;;
    esac
    # 开始卸载clash
    normal "$uninstall_start_msg Clash"
    # 刷新运行状态
    refresh_status
    # 关闭clash
    if $clash_is_running; then
        stop
    fi
    # 关闭自动启动
    if [ "$(find_clashtool_config 'auto_start')" = 'true' ];then
        auto_start false
    fi
    # 关闭自动更新订阅
    if [ "$(find_clashtool_config 'auto_update_sub')" = 'true' ];then
        auto_update_sub false
    fi
    # 删除服务脚本
    del_service_file

    # 删除符号链接
    if [ -L "$symlink_path" ] || [ -f "$symlink_path" ]; then
        rm -f "$symlink_path"
        normal "$(printf "$symlink_removed_msg" "$symlink_path")"
    fi

    # 清理 PATH 配置（可选：从 shell rc 中移除）
    # 不主动清理 shell rc，避免影响其他配置

    # 删除clash文件
    rm -rf "$clash_binary_path"
    clear "$_un_clear_mode"
    if [ "$_un_arg" = "all" ]; then
        success "Clash $uninstall_all_success_msg"
    elif [ "$_un_clear_mode" = "all" ]; then
        success "Clash $uninstall_purge_success_msg"
    else
        success "Clash $uninstall_success_msg"
    fi
}

# 参数: $1：version - clash版本 （可为空），默认为最新版本
update() {
    version=$1
    # 安装clash
    download_clash "$version"
    # 刷新运行状态，记录启动时重新启动clash
    refresh_status
    if $clash_is_running; then
        start
    fi
}

install_ui() {
    if is_ui_installed;then
        failed "ClashUI $was_install_msg"
        return 1
    fi
    ui_name=$1
    # 没有指定UI则使用配置中指定UI
    if [ -z "${ui_name}" ]; then
        ui_name=$(find_clashtool_config 'ui')
    fi
    # 下载UI安装包
    url=$(get_dict_value 'ui_url' "$ui_name" )
    if [ -z "$url" ]; then
        failed "$install_ui_parameter_failed_msg"
        return 1
    fi
    download_name=$(get_download_filename "$url")
    temp_file_path="${install_dir}/${download_name}"
    download "$temp_file_path" "$url" "$download_name"    
    normal "${install_start_msg} ClashUI"
    # 解压
    temp_file_dir=${install_dir}/temp_file_dir
    decompression "$temp_file_path" "$temp_file_dir"
    find_result=$(find "$temp_file_dir" -type f -name "index.html" -print -quit)
    if [ -z "$find_result" ]; then
        # 删除已下载和解压的文件
        rm -rf "$temp_file_path"
        rm -rf "$temp_file_dir"
        failed "$install_ui_failed_msg"
        return 1
    fi
    # 重命名（先清空目标目录，避免 mv 将源移入已存在的子目录）
    rm -rf "$ui_install_dir"
    mv "$(dirname "$find_result")" "$ui_install_dir"
    # 删除已下载和解压的文件
    rm -rf "$temp_file_path"
    rm -rf "$temp_file_dir"
    # 设置ui配置
    add_user_config 'external-ui' "$ui_install_dir"
    update_clashtool_config 'ui' "$ui_name"
    success "ClashUI $install_success_msg"
    # 刷新运行状态，如果正在运行则重新启动
    refresh_status
    if $clash_is_running;then
        restart
    fi
}

uninstall_ui(){
    if ! is_ui_installed; then
        failed "ClashUI $not_install_msg"
        return 1
    fi
    normal "$uninstall_start_msg ClashUI"
    # 删除当前已安装UI
    rm -rf "${ui_install_dir}"
    update_clashtool_config 'ui' 'dashboard'
    # 设置ui配置
    delete_user_config 'external-ui'
    success "ClashUI $uninstall_success_msg"
    # 刷新运行状态，如果状态为运行则重新启动
    refresh_status
    if $clash_is_running;then
        restart
    fi
}

# 参数：$1 - UI类型（yacd或dashboard或zashboard）可为空，默认当前使用的ui
update_ui(){
    if ! is_ui_installed;then
        failed "ClashUI $not_install_msg"
        return 1
    fi
    normal "$uninstall_start_msg ClashUI"
    rm -rf "${ui_install_dir}"
    success "ClashUI $uninstall_success_msg"
    install_ui "$1"
    # 刷新运行状态，如果状态为运行则重新启动
    refresh_status
    if $clash_is_running;then
        restart
    fi
}

# 函数: 更新clashtool脚本
update_script(){
    current_path=$(readlink -f "$0")
    current=$(grep '^# version:' "$current_path" | head -1 | sed 's/# version://')
    normal "${current_version_msg}$current"
    url="https://raw.githubusercontent.com/$project_repo/clashtool.sh"
    version=$(curl -s "${github_proxy_url}${url}" | grep '^# version:' | head -1 | sed 's/# version://')
    if [ -z "$version" ];then
        failed "$get_version_failed_msg"
    fi
    normal "${latest_version_msg}$version" 
    if [ "$version" = "$current" ];then
        warn "$install_equal_versions_warn_msg" false
    fi
    
    # 下载到临时文件
    temp_file="${current_path}.download"
    download "$temp_file" "$url" "Script"
    
    # 验证下载文件
    downloaded_version=$(grep '^# version:' "$temp_file" | head -1 | sed 's/# version://')
    if [ -z "$downloaded_version" ]; then
        rm -f "$temp_file"
        failed "$invalid_download_msg"
    fi
    
    # 备份原文件
    backup_file="${current_path}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$current_path" "$backup_file"
    
    # 更新当前脚本
    mv "$temp_file" "$current_path" || { rm -f "$temp_file"; failed "$update_script_failed_msg"; return 1; }
    chmod 755 "$current_path"

    # TUI 模块已合并到 clashtool.sh 中，无需单独更新

    # 同时下载并更新 i18n 目录（多语言支持）
    _us_i18n_dir="${current_path%/*}/i18n"
    mkdir -p "$_us_i18n_dir"
    for _us_i18n_lang in zh_CN en; do
        _us_i18n_url="https://raw.githubusercontent.com/$project_repo/i18n/${_us_i18n_lang}.sh"
        _us_i18n_temp="${_us_i18n_dir}/${_us_i18n_lang}.sh.download"
        download "$_us_i18n_temp" "$_us_i18n_url" "i18n/${_us_i18n_lang}" 2>/dev/null
        if [ -f "$_us_i18n_temp" ] && grep -q '^#' "$_us_i18n_temp" 2>/dev/null; then
            mv "$_us_i18n_temp" "${_us_i18n_dir}/${_us_i18n_lang}.sh"
            chmod 644 "${_us_i18n_dir}/${_us_i18n_lang}.sh"
        else
            rm -f "$_us_i18n_temp" 2>/dev/null
        fi
    done

    # 更新安装目录中的脚本
    if [ -d "$install_dir" ];then
        cp "$current_path" "$script_path"
        chmod 755 "$script_path"
        # TUI 模块已合并，无需单独同步
        # 同步 i18n 目录到安装目录
        _us_i18n_src_dir="${current_path%/*}/i18n"
        if [ -d "$_us_i18n_src_dir" ]; then
            mkdir -p "${install_dir}/i18n"
            cp "${_us_i18n_src_dir}/"*.sh "${install_dir}/i18n/" 2>/dev/null
            chmod 644 "${install_dir}/i18n/"*.sh 2>/dev/null
        fi
    fi

    success "$update_script_success_msg"
    normal "$(printf "$script_backup_msg" "$backup_file")"
}   

# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
load_config(){
    sub_name=$1
    # 未指定订阅，获取当前订阅
    if [ -z "$sub_name" ]; then
        sub_name=$(find_subscription_config '' 'use')
    fi

    if [ "$sub_name" = 'default' ]; then
        # 使用默认配置
        cp "$user_config_path" "$main_config_path"
    else
        if subscription_exists "${sub_name}";then
             # 文件不存在则更新订阅
            if [ ! -f "${subscription_dir}/${sub_name}.yaml" ];then
                update_sub "$sub_name"
            fi
            sub_main_config_path="${subscription_dir}/${sub_name}.yaml"
            # 合并用户配置文件和订阅配置文件生成Clash配置文件
            temp_file_path="${main_config_path}.tmp.yaml"
            $yq_binary_path eval-all '. as $item ireduce ({}; . *+ $item) | (.. | select(tag == "!!seq")) |= unique' \
                "$sub_main_config_path" "$user_config_path" > "$temp_file_path"
            
            gateway_status=$(find_clashtool_config "gateway")
            if [ "$gateway_status" = "true" ]; then
                $yq_binary_path eval-all '. as $item ireduce ({}; . *+ $item) | (.. | select(tag == "!!seq")) |= unique' \
                    "$temp_file_path" "$gateway_config_path" > "${temp_file_path}.merge"
                mv "${temp_file_path}.merge" "$temp_file_path"
            fi
            check_config "$temp_file_path" || { rm -f "$temp_file_path" "${temp_file_path}.merge"; return 1; }
            mv "$temp_file_path" "$main_config_path"
        else
             failed "$not_sub_exists_msg"
             return 1
        fi
    fi
}

# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
start() {
    sub_name=$1
    # 刷新运行状态，避免依赖过时的变量
    refresh_status
    # 判断是否正在运行
    if $clash_is_running; then
        warn "$clash_running_warn_msg" false
    else
        normal "$clash_start_msg"
        # 生成配置文件
        load_config "$sub_name" || return 1
        # 判断是否开启透明网关
        gateway_status=$(find_clashtool_config "gateway")
        if [ "$gateway_status" = 'true' ];then
            # 开启电脑网卡转发功能
            sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
            if [ -f '/proc/sys/net/ipv6/ip_forward' ]; then
               sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
            fi
        fi
        # 启动clash
        nohup "${clash_binary_path}" -d "${config_dir}" > "${log_dir}/clash.log" 2>&1 &
        # 等待启动成功
        sleep 3
        # 刷新状态并判断是否启动失败
        refresh_status
        if ! $clash_is_running; then
            failed "$clash_start_failed_msg"
            return 1
        fi
        if [ -n "$sub_name" ];then
            # 更改配置中默认使用的配置文件
            update_subscription_config '' 'use' "$sub_name"
        fi
        # 显示提示信息
        port=$(find_user_config "external-controller" | awk -F ':' '{print $2}')
        controller_secret=$(find_user_config "secret")
        success "$clash_start_success_msg"
        clash_ui_link_info

        if grep -q 'mixed-port:' "$main_config_path"; then
            mixed_port=$(find_user_config 'mixed-port')
            http_port="$mixed_port"
            socks_port="$mixed_port"
        else
            http_port=$(find_user_config 'port')
            socks_port=$(find_user_config 'socks-port')
        fi
        _http_port=$(find_clashtool_config 'http_port')
        _socks_port=$(find_clashtool_config 'socks_port')
        # 判断用户是否修改监http听端口
        if ([ "$http_port" != "$_http_port" ] || [ "$socks_port" != "$_socks_port" ]) && is_proxy;then
            remind "$proxy_port_update_msg"
        fi
    fi
}

stop() {
    # 刷新运行状态
    refresh_status
    # 判断程序是否运行
    if $clash_is_running; then
        # 收集所有要停止的PID：refresh_status 检测到的 + 完整路径匹配的
        # refresh_status 可能通过进程名或端口检测到非本安装目录的 clash 进程，
        # 需一并停止以保证 stop 与 status/refresh_status 行为一致
        local _stop_pids=""
        if [ -n "$clash_pid" ]; then
            _stop_pids="$clash_pid"
        fi
        for temp_pid in $(pgrep -f "$clash_binary_path" 2>/dev/null | grep -v "^$$\$"); do
            case " $_stop_pids " in
                *" $temp_pid "*) ;;
                *) _stop_pids="$_stop_pids $temp_pid" ;;
            esac
        done
        # 停止所有PID
        for temp_pid in $_stop_pids; do
            [ -n "$temp_pid" ] && kill "${temp_pid}" 2>/dev/null
        done
        # 等待进程结束（最多3秒）
        local _s_wait=0
        local _still_alive=false
        while [ "$_s_wait" -lt 30 ]; do
            _still_alive=false
            for temp_pid in $_stop_pids; do
                if [ -n "$temp_pid" ] && kill -0 "${temp_pid}" 2>/dev/null; then
                    _still_alive=true
                    break
                fi
            done
            [ "$_still_alive" = "false" ] && break
            sleep 1
            _s_wait=$((_s_wait + 1))
        done
        # 验证是否真正停止
        _still_alive=false
        for temp_pid in $_stop_pids; do
            if [ -n "$temp_pid" ] && kill -0 "${temp_pid}" 2>/dev/null; then
                _still_alive=true
                break
            fi
        done
        if [ "$_still_alive" = "true" ]; then
            # 普通kill失败，尝试 SIGKILL
            for temp_pid in $_stop_pids; do
                [ -n "$temp_pid" ] && kill -9 "${temp_pid}" 2>/dev/null
            done
            sleep 1
            # 再次验证
            _still_alive=false
            for temp_pid in $_stop_pids; do
                if [ -n "$temp_pid" ] && kill -0 "${temp_pid}" 2>/dev/null; then
                    _still_alive=true
                    break
                fi
            done
            if [ "$_still_alive" = "true" ]; then
                failed "$clash_stop_failed_msg"
                return 1
            fi
        fi
        # 清理状态
        clash_pid=""
        clash_is_running=false
        # 提醒关闭系统代理
        if is_proxy; then
            remind "$proxy_enable_reminder_msg"
        fi
        success "$clash_stop_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 参数: $1 - 订阅名称 （可为空），默认为当前使用订阅
restart() {
    stop
    start "$1"
}

# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
reload() {
    sub_name=$1
    # 刷新运行状态
    refresh_status
    if ! $clash_is_running; then
        warn "$clash_not_running_warn_msg" false
        return 1
    fi
    # 生成配置
    load_config "$sub_name" || return 1
    # 重载配置
    port=$(find_user_config "external-controller" | awk -F ':' '{print $2}')
    controller_secret=$(find_user_config "secret")
    if [ -z "$controller_secret" ]; then
        result=$(curl -s --max-time 5 -X PUT "http://${local_proxy_host}:${port}/configs" -H "Content-Type: application/json" -d "{\"path\": \"${main_config_path}\"}")
    else
        result=$(curl -s --max-time 5 -X PUT "http://${local_proxy_host}:${port}/configs" -H "Content-Type: application/json" -H "Authorization: Bearer ${controller_secret}" -d "{\"path\": \"${main_config_path}\"}")
    fi
    # 解析返回数据判断重载是否成功
    if [ -n "$result" ];then
        printf '%s\n' "$result" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p'
        failed "$clash_yaml_failed_msg"
        return 1
    else
        # 重载成功，更新当前使用订阅
        update_subscription_config '' 'use' "${sub_name}"
        success "$clash_reload_success_msg"
    fi
}

status() {
    # 刷新运行状态
    refresh_status
    ui_name=$(find_clashtool_config 'ui')
    version=$(find_clashtool_config 'clash_version')
    autostart=$(find_clashtool_config 'auto_start')
    sub_name=$(find_subscription_config '' 'use')
    gateway_status=$(find_clashtool_config 'gateway')
    controller_secret=$(find_user_config 'secret')
    if $clash_is_running; then
        echo "$status_running_msg"
    else
        echo "$status_not_running_msg"
    fi
    echo "${status_clash_version_msg}${version}"
    echo "${status_sub_name_msg}${sub_name}"
    echo "${status_auto_start_msg}${autostart}"
    if is_proxy;then
        echo "${status_proxy_msg}true"
        for key in $proxy_protocols 'no'; do
            proxy_key="${key}_proxy"
            echo "    $proxy_key=$(eval "echo \${$proxy_key}")"
        done
    else
        echo "${status_proxy_msg}false"
        
    fi
    echo "${status_gateway_msg}${gateway_status}"
    clash_ui_link_info
    echo "${status_clash_binary_path_msg}${clash_binary_path}"
}

list() {
    names=$(find_subscription_config '' 'names')
    echo "$names" | tr ',' '\n' | while IFS= read -r name; do
        if [ -n "$name" ]; then
            url=$(find_subscription_config "$name" "url")
            interval=$(find_subscription_config "$name" "interval")
            echo ""
            echo "      $name"
            echo "====================="
            echo "${list_sub_url_msg}${url}"
            echo "${list_sub_update_interval_msg}${interval}"
            echo "====================="
        fi
    done
}

# 参数：$1:file 文件路径, $2:quiet(可选) true=静默模式不输出错误不退出
# 返回值: 0=成功, 1=失败
check_config(){
    file=$1
    _cc_quiet="${2:-false}"
    expected="configuration file $file test is successful"
    req=$("$clash_binary_path" -d "$config_dir" -t -f "$file" 2>&1)
    # 提取最后一行输出的记录
    last_line=$(echo "$req" | awk 'END {print}')
    # 检查最后一行文本是否匹配期望的文本
    if [ "$last_line" != "$expected" ]; then
        if [ "$_cc_quiet" != "true" ]; then
            failed "$conf_failed_msg
        $req"
        fi
        return 1
    fi
}

# 参数: $1：input - 订阅信息 格式《订阅名称::订阅地址(或本地文件路径)::订阅更新时间（小时,可为空）》
add(){
    input=$1
    name=$(echo "${input}" | awk -F '::' '{print $1}')
    url=$(echo "${input}" | awk -F '::' '{print $2}')
    interval=$(echo "${input}" | awk -F '::' '{print $3}')
    # 校验订阅名称，拒绝包含路径穿越或特殊字符的名称
    case "$name" in
        *[..\\/:\*\?\<\>\|]*|"")
            failed "$(printf "$invalid_sub_name_msg" "$name")"
            return 1
            ;;
    esac
    # 验证参数
    if [ -z "$name" ] || [ -z "$url" ]; then
        failed "$add_sub_parameter_failed_msg"
        return 1
    fi
    # 校验 interval：必须为空或非负整数（仅由数字组成，拒绝负数/小数/特殊字符）
    if [ -n "$interval" ]; then
        case "$interval" in
            *[!0-9]*)
                failed "$add_sub_parameter_failed_msg:${interval}"
                return 1
                ;;
        esac
    fi
    # 判断url是否是网址
    if  [ "${url#http}" != "$url" ]; then
        check_url "$url" || return 1
        # 下载配置
        download_sub "$name" "$url" || return 1
        if [ -z "$interval" ];then
            interval=0
        fi
        if subscription_exists "$name"; then
            # 更新配置
            update_subscription_config "$name" 'url' "$url"
            update_subscription_config "$name" 'interval' "$interval"
            success "$update_sub_success_msg"
        else
            # 创建配置
            add_subscription_config "$name" "$url" "$interval"
            success "$add_sub_success_msg"
        fi
        # 更新配置定时任务
        auto_update_sub '' "$name"
    else
        # 判断本地是否存在此文件
        if [ ! -f "$url" ];then
            failed "$not_sub_exists_msg"
            return 1
        fi
        # 校验配置文件
        check_config "$url"
        # 复制文件到配置目录
        cp "$url" "${subscription_dir}/${name}.yaml"
        # 如果配置文件不存在此信息则添加
        if ! subscription_exists "${name}"; then
            add_subscription_config "$name" "---" "0"
            success "$add_sub_success_msg"
        else
            success "$update_sub_success_msg"
        fi
    fi
}

# 修改订阅 URL（保留原 interval，仅更新 URL 和下载内容）
# 参数: $1 - 订阅名称, $2 - 新 URL
modify() {
    _md_name="$1"
    _md_url="$2"
    # 校验订阅名称
    case "$_md_name" in
        *[..\\/:\*\?\<\>\|]*|"")
            failed "$(printf "$invalid_sub_name_msg" "$_md_name")"
            return 1
            ;;
    esac
    if [ -z "$_md_name" ] || [ -z "$_md_url" ]; then
        failed "$add_sub_parameter_failed_msg"
        return 1
    fi
    if ! subscription_exists "$_md_name"; then
        failed "$not_sub_exists_msg"
        return 1
    fi
    # 判断 url 类型并下载/复制
    if [ "${_md_url#http}" != "$_md_url" ]; then
        check_url "$_md_url" || return 1
        download_sub "$_md_name" "$_md_url" || return 1
    else
        if [ ! -f "$_md_url" ]; then
            failed "$not_sub_exists_msg"
            return 1
        fi
        check_config "$_md_url" || return 1
        cp "$_md_url" "${subscription_dir}/${_md_name}.yaml"
    fi
    # 仅更新 URL 配置，interval 保持不变
    update_subscription_config "$_md_name" 'url' "$_md_url"
    success "$update_sub_success_msg"
}

# 参数: $1：sub_name - 订阅名称
del() {
    sub_name=$1
    # 校验订阅名称，拒绝包含路径穿越或特殊字符的名称
    case "$sub_name" in
        *[..\\/:\*\?\<\>\|]*|"")
            failed "$(printf "$invalid_sub_name_msg" "$sub_name")"
            return 1
            ;;
    esac
    if subscription_exists "${sub_name}"; then

        # 关闭自动更新定时任务
        update_subscription_config "$sub_name" "interval" "0"
        auto_update_sub '' "${sub_name}"

        # 删除订阅配置信息
        delete_subscription_config "${sub_name}"
        # 删除下载订阅文件
        if [ -f "${subscription_dir}/${sub_name}.yaml" ]; then
            rm -rf "${subscription_dir}/${sub_name}.yaml"
        fi
        # 判断当前订阅是否正在使用
        use=$(find_subscription_config '' 'use')
        if [ "$use" = "${sub_name}" ]; then
            # 设置订阅配置为default
            update_subscription_config '' 'use' 'default'
            # 刷新运行状态，重载配置
            refresh_status
            if $clash_is_running; then
                reload "default"
            fi
        fi
        success "$delete_sub_success_msg"
    else
        failed "$not_sub_exists_msg"
        return 1
    fi
}

# 参数: $1：sub_name - 订阅名称或all（可为空）， 默认为当前使用订阅
update_sub() {
    sub_name=$1
    # 是否更新所有订阅
    if [ "${sub_name}" = "all" ]; then
        # 更新所有订阅配置
        names=$(find_subscription_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                download_sub "${name}"
            fi
        done
        # all 模式下使用当前订阅进行 reload，未配置则跳过
        use=$(find_subscription_config '' 'use')
    else
        # 当前使用配置文件
        use=$(find_subscription_config '' 'use')
        # 更新当前使用配置
        if [ -z "${sub_name}" ]; then
            if [ "$use" = "default" ];then
                warn "$update_default_sub_failed_msg" false
                return 1
            fi
            download_sub "${use}"
        else
            # 更新指定订阅配置
            if subscription_exists "${sub_name}"; then
                download_sub "${sub_name}"
            else
                failed "$not_sub_exists_msg"
                return 1
            fi
        fi
    fi
    success "$update_sub_success_msg"
    # 刷新运行状态，重载配置文件
    refresh_status
    if $clash_is_running && [ -n "$use" ]; then
        reload "$use"
    fi
}

# 
# 参数: 
#   $1：name - 订阅名称
#   $2: url - 订阅地址 可为空，自动获取配置中url
download_sub() {
    name=$1
    url=${2:-$(find_subscription_config "${name}" "url")}
    # 校验订阅名称，拒绝包含路径穿越或特殊字符的名称
    case "$name" in
        *[..\\/:\*\?\<\>\|]*|"")
            failed "$(printf "$invalid_sub_name_msg" "$name")"
            return 1
            ;;
    esac
    if [ -z "$url" ];then
        warn "$update_local_sub_failed_msg" false
    else
        # 获取下载地址
        temp_sub_path="${subscription_dir}/${name}.new.yaml"
        # 下载订阅文件
        download "${temp_sub_path}" "${url}" "${name}" $subscription_use_proxy || return 1
        # 检查订阅文件是否有效
        check_config "$temp_sub_path" || { rm -f "$temp_sub_path"; return 1; }
        # 如果已存在则备份原先订阅
        if [ -f "${subscription_dir}/${name}.yaml" ];then
            mv "${subscription_dir}/${name}.yaml" "${subscription_backup_dir}/${name}$(date +'%Y%m%d%H%M').yaml"
        fi
        # 重命名订阅文件
        mv "${temp_sub_path}" "${subscription_dir}/${name}.yaml"
    fi
}

# 参数：$1：enable - 设置自动更新总开关，默认根据配置文件重新设置
#      $2：sub_name - 订阅名称（可选），默认根据配置文件重新设置全部
auto_update_sub() {
    enable=$1
    sub_name=$2
    if [ "$enable" = 'true' ]; then
        update_clashtool_config "auto_update_sub" true
        success "$auto_update_sub_on_success_msg"
    elif [ "$enable" = 'false' ];then
        update_clashtool_config "auto_update_sub" false
        success "$auto_update_sub_off_success_msg"
    elif [ "$enable" = '' ];then
        enable=$(find_clashtool_config 'auto_update_sub')
    else
        failed "$verify_failed_msg"
        return 1
    fi
    # 判断是否存在订阅配置
    if [ -n "$sub_name" ] && ! subscription_exists "$sub_name"; then
        failed "$not_sub_exists_msg"
        return 1
    fi
    if [ -z "$sub_name" ]; then
        # 为空则根据配置和enable重新设置全部定时任务
        names=$(find_subscription_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                interval=$(find_subscription_config "$name" 'interval')
                if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
                    crontab_tool '' "$script_path update_sub \"${name}\" >> \"${log_dir}\"/crontab.log 2>&1"
                else
                    crontab_tool "0 */$interval * * *" "$script_path update_sub \"${name}\" >> \"${log_dir}\"/crontab.log 2>&1"
                fi
            fi
        done
    else
        interval=$(find_subscription_config "$sub_name" 'interval')
        # 设置指定定时任务
        if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
            crontab_tool '' "$script_path update_sub \"${sub_name}\" >> \"${log_dir}\"/crontab.log 2>&1"
        else
            crontab_tool "0 */$interval * * *" "$script_path update_sub \"${sub_name}\" >> \"${log_dir}\"/crontab.log 2>&1"
        fi
    fi
}
gateway(){
    enable=${1:-true}
    verify $enable || return 1
    # 网关模式需要 root 权限（设置 IP 转发）
    if ! is_root; then
        permission_denied_msg "gateway"
        printf "\n"
        failed "$gateway_root_forward_msg"
        return 1
    fi
    # Docker 环境下网关模式可能受限
    if is_docker && $enable; then
        warn "$docker_gateway_warn_msg" false
    fi
    gateway_status=$(find_clashtool_config 'gateway')
    if [ "$gateway_status" != "$enable" ];then
        update_clashtool_config "gateway" "$enable"
        # 启用网关时设置IP转发
        if $enable; then
            sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
            # IPv6转发
            sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
            success "$gateway_enable_success_msg"
        else
            success "$gateway_disable_success_msg"
        fi
        # 刷新运行状态
        refresh_status
        if $clash_is_running; then
            restart
        fi
    else
        if $enable; then
            success "$gateway_enable_success_msg"
        else
            success "$gateway_disable_success_msg"
        fi
    fi
}
get_service_file(){
    case "$(get_linux_distribution)" in
        "alpine")
            echo "/etc/init.d/${service_name}"
            ;;
        "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
            echo "/etc/systemd/system/${service_name}.service"
            ;;
        *)
            echo ""
            ;;
    esac
}

create_service_file(){
    if ! is_root; then
        normal "$user_level_skip_service_msg"
        return 0
    fi
    service_file="$(get_service_file)"
    case "$(get_linux_distribution)" in
        "alpine") 
            if [ ! -f "$service_file" ];then
                {
                    echo "#!/sbin/openrc-run"
                    echo "name=\"$service_name\""
                    echo "description=\"$service_name Service\""
                    echo ""
                    echo "command=\"$script_path\""
                    echo "command_args=\"start\""
                    echo "command_background=\"true\""
                    echo ""
                    echo "depend(){"
                    echo "    after network"
                    echo "}"
                    echo ""
                    echo "start() {"
                    echo "    \$command start"
                    echo "}"
                    echo ""
                    echo "stop() {"
                    echo "    \$command stop"
                    echo "}"
                } > "$service_file"
                chmod +x "$service_file"
            fi
            ;;
        "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
            if [ ! -f "$service_file" ];then
                {
                    echo "[Unit]"
                    echo "Description=$service_name Service"
                    echo "After=network.target"
                    echo ""
                    echo "[Service]"
                    echo "Type=simple"
                    echo "KillMode=process"
                    echo "ExecStart=$script_path start"
                    # echo "Restart=always"
                    echo "User=root"
                    echo ""
                    echo "[Install]"
                    echo "WantedBy=multi-user.target"
                } > "$service_file"
                chmod +x "$service_file"
                systemctl daemon-reload
            fi
            ;;
        *)
            failed "$unsupported_linux_distribution_failed_msg"
            return 1
    esac
}

del_service_file(){
    # 与 create_service_file 对称：非 root 跳过（用户级安装不创建系统服务文件）
    if ! is_root; then
        return 0
    fi
    service_file=$(get_service_file)
    if [ -f "$service_file" ];then
        rm -rf "$service_file"
    fi
}

# 参数: $1：enable - 是否启用开机运行 （可选），默认为 true（true/false）
auto_start() {
    # 是否开机运行
    enable=${1:-true}
    verify "$enable"
    # 用户级安装使用桌面自动启动或bashrc
    if ! is_root; then
        _as_autostart_dir="${HOME}/.config/autostart"
        _as_desktop_file="${_as_autostart_dir}/clash.desktop"
        
        if [ "$enable" = 'true' ];then
            mkdir -p "$_as_autostart_dir" 2>/dev/null
            cat > "$_as_desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Clash
Comment=Clash Proxy Service
Exec=${script_path} start
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
            chmod +x "$_as_desktop_file" 2>/dev/null
            normal "$(printf "$user_level_autostart_on_msg" "${_as_desktop_file}")"
        else
            rm -f "$_as_desktop_file" 2>/dev/null
            normal "$user_level_autostart_off_msg"
        fi
        update_clashtool_config 'auto_start' "$enable"
        return 0
    fi
    
    # root权限安装使用systemd/openrc
    linux_distribution=$(get_linux_distribution)
    # 启用或禁用开机运行
    if [ "$enable" = 'true' ];then
        case "$linux_distribution" in
            "alpine")
                rc-update add "$service_name" default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                systemctl enable "$service_name" >/dev/null 2>&1
            ;;
        *)
            failed "$unsupported_linux_distribution_failed_msg"
            return 1
        esac
        success "$auto_start_enabled_success_msg"
    else
        case "$linux_distribution" in
            "alpine")
                rc-update del "$service_name" default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                systemctl disable "$service_name" >/dev/null 2>&1
                ;;
            *)
                failed "$unsupported_linux_distribution_failed_msg"
                return 1
        esac
        success "$auto_start_turned_off_success_msg"
    fi
    update_clashtool_config 'auto_start' "$enable"
}

# ==================== 代理设置辅助函数 ====================

# 检测当前桌面环境
detect_desktop_environment() {
    _dde_desktop="${XDG_CURRENT_DESKTOP:-}"
    _dde_session="${DESKTOP_SESSION:-}"
    case "$_dde_desktop" in
        *GNOME*|*gnome*|*Ubuntu*) echo "gnome" ;;
        *KDE*|*kde*) echo "kde" ;;
        *XFCE*|*xfce*) echo "xfce" ;;
        *MATE*|*mate*) echo "mate" ;;
        *X-Cinnamon*|*cinnamon*) echo "cinnamon" ;;
        *Budgie*|*budgie*) echo "budgie" ;;
        *Deepin*|*deepin*) echo "deepin" ;;
        *LXQt*|*lxqt*) echo "lxqt" ;;
        *LXDE*|*lxde*) echo "lxde" ;;
        *) case "$_dde_session" in
            gnome*|ubuntu*|pop*) echo "gnome" ;;
            kde*|plasma*) echo "kde" ;;
            xfce*) echo "xfce" ;;
            mate*) echo "mate" ;;
            cinnamon*) echo "cinnamon" ;;
            budgie*) echo "budgie" ;;
            deepin*) echo "deepin" ;;
            lxqt*) echo "lxqt" ;;
            lxde*) echo "lxde" ;;
            *) echo "unknown" ;;
        esac ;;
    esac
}

# 检测 KDE Plasma 版本（5 或 6）
detect_kde_version() {
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        echo "6"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        echo "5"
    else
        echo "5"
    fi
}

# 获取 KDE 配置写入命令
_kde_config_cmd() {
    local _kcc_ver=$(detect_kde_version)
    if [ "$_kcc_ver" = "6" ]; then
        echo "kwriteconfig6"
    else
        echo "kwriteconfig5"
    fi
}

# 检测当前用户的 shell 配置文件列表
detect_shell_rc_files() {
    _dsr_user_home="$HOME"
    [ -n "$SUDO_USER" ] && _dsr_user_home="/home/$SUDO_USER"
    _dsr_files=""
    # bash
    if [ -f "${_dsr_user_home}/.bashrc" ]; then
        _dsr_files="${_dsr_files} ${_dsr_user_home}/.bashrc"
    fi
    # zsh
    if [ -f "${_dsr_user_home}/.zshrc" ]; then
        _dsr_files="${_dsr_files} ${_dsr_user_home}/.zshrc"
    fi
    # fish
    _dsr_fish_dir="${_dsr_user_home}/.config/fish"
    if command -v fish >/dev/null 2>&1 || [ -f "${_dsr_fish_dir}/config.fish" ]; then
        mkdir -p "$_dsr_fish_dir" 2>/dev/null
        _dsr_files="${_dsr_files} ${_dsr_fish_dir}/config.fish"
    fi
    echo "$_dsr_files"
}

# 获取协议对应端口: $1=proto, $2=http_port, $3=socks_port
_get_proto_port() {
    [ "$1" = "socks" ] && echo "$3" || echo "$2"
}

# 向一个 shell rc 文件写入代理环境变量
_proxy_set_shell_rc() {
    _psrc_file="$1"
    _psrc_http_port="$2"
    _psrc_socks_port="$3"
    [ ! -f "$_psrc_file" ] && return 1

    # 备份
    _psrc_bak="${_psrc_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$_psrc_file" "$_psrc_bak" 2>/dev/null

    # 清理旧备份，只保留最新一个
    _psrc_old_baks=$(ls -t "${_psrc_file}.bak."* 2>/dev/null | tail -n +2)
    [ -n "$_psrc_old_baks" ] && echo "$_psrc_old_baks" | xargs rm -f 2>/dev/null

    _psrc_tmp="${_psrc_file}.tmp"
    cp "$_psrc_file" "$_psrc_tmp"

    # 判断是否为 fish 配置文件
    case "$_psrc_file" in
        */config.fish)
            # fish 语法：set -gx xxx_proxy value
            for proto in $proxy_protocols; do
                _psrc_key="${proto}_proxy"
                if [ "$proto" = "socks" ]; then
                    _psrc_val="socks5://${local_proxy_host}:${_psrc_socks_port}"
                else
                    _psrc_val="http://${local_proxy_host}:${_psrc_http_port}"
                fi
                if grep -q "set -gx ${_psrc_key} " "$_psrc_tmp" 2>/dev/null; then
                    sed -i "s|set -gx ${_psrc_key} .*|set -gx ${_psrc_key} ${_psrc_val}|" "$_psrc_tmp"
                else
                    echo "set -gx ${_psrc_key} ${_psrc_val}" >> "$_psrc_tmp"
                fi
            done
            # no_proxy
            if grep -q "set -gx no_proxy " "$_psrc_tmp" 2>/dev/null; then
                sed -i "s|set -gx no_proxy .*|set -gx no_proxy ${proxy_bypass_hosts}|" "$_psrc_tmp"
            else
                echo "set -gx no_proxy ${proxy_bypass_hosts}" >> "$_psrc_tmp"
            fi
            ;;
        *)
            # bash/zsh 语法：export xxx_proxy=value
            for proto in $proxy_protocols; do
                _psrc_key="${proto}_proxy"
                if [ "$proto" = "socks" ]; then
                    _psrc_val="socks5://${local_proxy_host}:${_psrc_socks_port}"
                else
                    _psrc_val="http://${local_proxy_host}:${_psrc_http_port}"
                fi
                if grep -q "export ${_psrc_key}=" "$_psrc_tmp" 2>/dev/null; then
                    sed -i "s|export ${_psrc_key}=.*|export ${_psrc_key}=${_psrc_val}|" "$_psrc_tmp"
                elif grep -q "${_psrc_key}=" "$_psrc_tmp" 2>/dev/null; then
                    sed -i "s|${_psrc_key}=.*|export ${_psrc_key}=${_psrc_val}|" "$_psrc_tmp"
                else
                    echo "export ${_psrc_key}=${_psrc_val}" >> "$_psrc_tmp"
                fi
            done
            # no_proxy
            if grep -q "export no_proxy=" "$_psrc_tmp" 2>/dev/null; then
                sed -i "s|export no_proxy=.*|export no_proxy=${proxy_bypass_hosts}|" "$_psrc_tmp"
            elif grep -q "no_proxy=" "$_psrc_tmp" 2>/dev/null; then
                sed -i "s|no_proxy=.*|export no_proxy=${proxy_bypass_hosts}|" "$_psrc_tmp"
            else
                echo "export no_proxy=${proxy_bypass_hosts}" >> "$_psrc_tmp"
            fi
            ;;
    esac

    mv "$_psrc_tmp" "$_psrc_file" 2>/dev/null || return 1
    return 0
}

# 从一个 shell rc 文件删除代理环境变量
_proxy_unset_shell_rc() {
    _purc_file="$1"
    [ ! -f "$_purc_file" ] && return 1

    # 备份
    _purc_bak="${_purc_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$_purc_file" "$_purc_bak" 2>/dev/null

    # 清理旧备份
    _purc_old_baks=$(ls -t "${_purc_file}.bak."* 2>/dev/null | tail -n +2)
    [ -n "$_purc_old_baks" ] && echo "$_purc_old_baks" | xargs rm -f 2>/dev/null

    _purc_tmp="${_purc_file}.tmp"
    cp "$_purc_file" "$_purc_tmp"

    case "$_purc_file" in
        */config.fish)
            # fish：删除 set -gx xxx_proxy 和 set -gx no_proxy
            sed -i '/set -gx .*_proxy /d' "$_purc_tmp"
            sed -i '/set -gx no_proxy /d' "$_purc_tmp"
            ;;
        *)
            # bash/zsh：删除 export xxx_proxy= 和 xxx_proxy=
            sed -i '/_proxy=/d' "$_purc_tmp"
            ;;
    esac

    mv "$_purc_tmp" "$_purc_file" 2>/dev/null || return 1
    return 0
}

# 设置系统级代理（/etc/profile.d/proxy.sh + /etc/environment + systemd）
_proxy_set_system() {
    _pss_http_port="$1"
    _pss_socks_port="$2"

    # /etc/profile.d/proxy.sh — 登录时自动加载（所有 shell 通用）
    if [ -d /etc/profile.d ]; then
        _pss_proxy_sh="/etc/profile.d/clash-proxy.sh"
        printf "#!/bin/sh\n# Clash proxy settings - auto-generated by clashtool\n" > "$_pss_proxy_sh"
        for proto in $proxy_protocols; do
            if [ "$proto" = "socks" ]; then
                echo "export ${proto}_proxy=socks5://${local_proxy_host}:${_pss_socks_port}" >> "$_pss_proxy_sh"
            else
                echo "export ${proto}_proxy=http://${local_proxy_host}:${_pss_http_port}" >> "$_pss_proxy_sh"
            fi
        done
        echo "export no_proxy=${proxy_bypass_hosts}" >> "$_pss_proxy_sh"
        chmod 644 "$_pss_proxy_sh" 2>/dev/null
        remind "$(printf "$proxy_system_profile_msg" "$_pss_proxy_sh")"
    fi

    # /etc/environment — PAM 读取，对 GUI 登录和 cron 生效
    if [ -f /etc/environment ]; then
        _pss_env_tmp="/etc/environment.tmp.$$"
        cp /etc/environment "$_pss_env_tmp" 2>/dev/null
        for proto in $proxy_protocols; do
            if [ "$proto" = "socks" ]; then
                _pss_val="socks5://${local_proxy_host}:${_pss_socks_port}"
            else
                _pss_val="http://${local_proxy_host}:${_pss_http_port}"
            fi
            _pss_key="${proto}_proxy"
            if grep -q "^${_pss_key}=" "$_pss_env_tmp" 2>/dev/null; then
                sed -i "s|^${_pss_key}=.*|${_pss_key}=\"${_pss_val}\"|" "$_pss_env_tmp"
            else
                echo "${_pss_key}=\"${_pss_val}\"" >> "$_pss_env_tmp"
            fi
        done
        if grep -q "^no_proxy=" "$_pss_env_tmp" 2>/dev/null; then
            sed -i "s|^no_proxy=.*|no_proxy=\"${proxy_bypass_hosts}\"|" "$_pss_env_tmp"
        else
            echo "no_proxy=\"${proxy_bypass_hosts}\"" >> "$_pss_env_tmp"
        fi
        mv "$_pss_env_tmp" /etc/environment 2>/dev/null
        remind "$(printf "$proxy_system_env_msg" "/etc/environment")"
    fi

    # systemd 环境变量（对 systemd 服务生效）
    if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd ]; then
        _pss_sysd_dir="/etc/systemd/system.conf.d"
        mkdir -p "$_pss_sysd_dir" 2>/dev/null
        _pss_sysd_conf="${_pss_sysd_dir}/clash-proxy.conf"
        printf "# Clash proxy settings - auto-generated by clashtool\n[Manager]\n" > "$_pss_sysd_conf"
        _pss_env_line=""
        for proto in $proxy_protocols; do
            if [ "$proto" = "socks" ]; then
                _pss_env_line="${_pss_env_line} ${proto}_proxy=socks5://${local_proxy_host}:${_pss_socks_port}"
            else
                _pss_env_line="${_pss_env_line} ${proto}_proxy=http://${local_proxy_host}:${_pss_http_port}"
            fi
        done
        _pss_env_line="${_pss_env_line} no_proxy=${proxy_bypass_hosts}"
        echo "DefaultEnvironment=${_pss_env_line}" >> "$_pss_sysd_conf"
        systemctl daemon-reload 2>/dev/null
        remind "$(printf "$proxy_system_systemd_msg" "$_pss_sysd_conf")"
    fi
}

# 清除系统级代理
_proxy_unset_system() {
    # /etc/profile.d/clash-proxy.sh
    rm -f /etc/profile.d/clash-proxy.sh 2>/dev/null

    # /etc/environment
    if [ -f /etc/environment ]; then
        _pus_env_tmp=$(mktemp /etc/environment.tmp.XXXXXX 2>/dev/null) || _pus_env_tmp="/etc/environment.tmp.$$"
        cp /etc/environment "$_pus_env_tmp" 2>/dev/null
        for proto in $proxy_protocols; do
            sed -i "/^${proto}_proxy=/d" "$_pus_env_tmp"
        done
        sed -i '/^no_proxy=/d' "$_pus_env_tmp"
        mv "$_pus_env_tmp" /etc/environment 2>/dev/null
    fi

    # systemd
    rm -f /etc/systemd/system.conf.d/clash-proxy.conf 2>/dev/null
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null
    fi
}

# 在 sudo 环境下为 gsettings/dconf/xfconf-query 设置 D-Bus 会话环境
# 这些工具需要通过 D-Bus 连接到用户会话总线，sudo 下默认缺少相关环境变量
# 影响 GNOME/MATE/Cinnamon/Budgie/Deepin（gsettings/dconf）和 XFCE（xfconf-query）
_setup_dbus_env() {
    if [ -n "$SUDO_USER" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        _sde_uid=$(id -u "$SUDO_USER" 2>/dev/null)
        if [ -n "$_sde_uid" ] && [ -d "/run/user/$_sde_uid" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${_sde_uid}/bus"
            export XDG_RUNTIME_DIR="/run/user/${_sde_uid}"
        fi
    fi
}

# 设置 GNOME 系代理（含 dconf 兼容）
# 同时适用于 MATE/Cinnamon/Budgie/Deepin（均使用 gsettings/dconf）
_proxy_set_gnome() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _setup_dbus_env

    if command -v gsettings >/dev/null 2>&1; then
        for proto in $proxy_protocols; do
            gsettings set org.gnome.system.proxy.${proto} host "$local_proxy_host" 2>/dev/null
            gsettings set org.gnome.system.proxy.${proto} port "$(_get_proto_port "$proto" "$1" "$2")" 2>/dev/null
        done
        _psg_ignore="[$(echo "$proxy_bypass_hosts" | sed "s/[^,]\+/'&'/g")]"
        gsettings set org.gnome.system.proxy ignore-hosts "$_psg_ignore" 2>/dev/null
        gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null
    elif command -v dconf >/dev/null 2>&1; then
        for proto in $proxy_protocols; do
            dconf write /system/proxy/${proto}/host "'${local_proxy_host}'" 2>/dev/null
            dconf write /system/proxy/${proto}/port "$(_get_proto_port "$proto" "$1" "$2")" 2>/dev/null
        done
        dconf write /system/proxy/mode "'manual'" 2>/dev/null
    fi
}

# 清除 GNOME 系代理
_proxy_unset_gnome() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _setup_dbus_env
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null
        for proto in $proxy_protocols; do
            gsettings reset org.gnome.system.proxy.${proto} host 2>/dev/null
            gsettings reset org.gnome.system.proxy.${proto} port 2>/dev/null
        done
        gsettings reset org.gnome.system.proxy ignore-hosts 2>/dev/null
    elif command -v dconf >/dev/null 2>&1; then
        dconf write /system/proxy/mode "'none'" 2>/dev/null
        for proto in $proxy_protocols; do
            dconf reset /system/proxy/${proto}/host 2>/dev/null
            dconf reset /system/proxy/${proto}/port 2>/dev/null
        done
    fi
}

# 设置 KDE 系代理（支持 Plasma 5/6）
_proxy_set_kde() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _psk_cmd=$(_kde_config_cmd)
    command -v "$_psk_cmd" >/dev/null 2>&1 || return
    "$_psk_cmd" --file kioslaverc --group 'Proxy Settings' --key ProxyType 1 2>/dev/null
    for proto in $proxy_protocols; do
        "$_psk_cmd" --file kioslaverc --group 'Proxy Settings' --key ${proto}Proxy "${local_proxy_host}:$(_get_proto_port "$proto" "$1" "$2")" 2>/dev/null
    done
    "$_psk_cmd" --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "${proxy_bypass_hosts}" 2>/dev/null
    [ "$_psk_cmd" = "kwriteconfig6" ] && "$_psk_cmd" --file kioslaverc --group 'Proxy Settings' --key Authmode 0 2>/dev/null
}

# 清除 KDE 系代理
_proxy_unset_kde() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _puk_cmd=$(_kde_config_cmd)
    command -v "$_puk_cmd" >/dev/null 2>&1 || return
    "$_puk_cmd" --file kioslaverc --group 'Proxy Settings' --key ProxyType 0 2>/dev/null
    for proto in $proxy_protocols; do
        "$_puk_cmd" --file kioslaverc --group 'Proxy Settings' --key ${proto}Proxy '' 2>/dev/null
    done
    "$_puk_cmd" --file kioslaverc --group 'Proxy Settings' --key NoProxyFor '' 2>/dev/null
}

# 设置 XFCE 系代理
_proxy_set_xfce() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _setup_dbus_env
    command -v xfconf-query >/dev/null 2>&1 || return
    for proto in $proxy_protocols; do
        _psxf_p=$(_get_proto_port "$proto" "$1" "$2")
        xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/${proto}/Host -s "$local_proxy_host" 2>/dev/null || \
            xfconf-query -c xfce4-session -n -p /xfce4/session/Net/Proxy/${proto}/Host -t string -s "$local_proxy_host" 2>/dev/null
        xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/${proto}/Port -s "$_psxf_p" 2>/dev/null || \
            xfconf-query -c xfce4-session -n -p /xfce4/session/Net/Proxy/${proto}/Port -t int -s "$_psxf_p" 2>/dev/null
    done
    xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/Mode -s "manual" 2>/dev/null || \
        xfconf-query -c xfce4-session -n -p /xfce4/session/Net/Proxy/Mode -t string -s "manual" 2>/dev/null
}

# 清除 XFCE 系代理
_proxy_unset_xfce() {
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return
    _setup_dbus_env
    command -v xfconf-query >/dev/null 2>&1 || return
    for proto in $proxy_protocols; do
        xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/${proto}/Host -r 2>/dev/null
        xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/${proto}/Port -r 2>/dev/null
    done
    xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/Mode -s "none" 2>/dev/null
}

# 设置 NetworkManager 代理
_proxy_set_nm() {
    command -v nmcli >/dev/null 2>&1 || return
    _psn_conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$_psn_conn" ] && return
    nmcli con modify "$_psn_conn" proxy.method "manual" 2>/dev/null
    for proto in $proxy_protocols; do
        nmcli con modify "$_psn_conn" "proxy.${proto}" "${local_proxy_host}:$(_get_proto_port "$proto" "$1" "$2")" 2>/dev/null
    done
    nmcli con modify "$_psn_conn" proxy.no-proxy-for "$proxy_bypass_hosts" 2>/dev/null
    nmcli con up "$_psn_conn" 2>/dev/null
    remind "$(printf "$proxy_nm_msg" "$_psn_conn")"
}

# 清除 NetworkManager 代理
_proxy_unset_nm() {
    if ! command -v nmcli >/dev/null 2>&1; then
        return
    fi
    _pun_conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$_pun_conn" ] && return
    nmcli con modify "$_pun_conn" proxy.method "none" 2>/dev/null
    for proto in $proxy_protocols; do
        nmcli con modify "$_pun_conn" "proxy.${proto}" "" 2>/dev/null
    done
    nmcli con modify "$_pun_conn" proxy.no-proxy-for "" 2>/dev/null
    nmcli con up "$_pun_conn" 2>/dev/null
}

# 设置当前 shell 环境变量（即时生效）
_proxy_set_env() {
    _pse_http_port="$1"
    _pse_socks_port="$2"
    for proto in $proxy_protocols; do
        if [ "$proto" = "socks" ]; then
            export "${proto}_proxy=socks5://${local_proxy_host}:${_pse_socks_port}"
        else
            export "${proto}_proxy=http://${local_proxy_host}:${_pse_http_port}"
        fi
    done
    export no_proxy="$proxy_bypass_hosts"
}

# 清除当前 shell 环境变量
_proxy_unset_env() {
    for proto in $proxy_protocols; do
        unset "${proto}_proxy"
    done
    unset no_proxy
}

# ==================== 代理主函数 ====================

# 优化：端口验证 + 错误追踪 + 幂等性 + 原子操作 + 详细日志
proxy_on() {
    _po_errors=0
    _po_steps=0
    _po_applied=""

    refresh_status
    if ! $clash_is_running; then
        warn "$clash_not_running_warn_msg" false
        return 1
    fi

    # 幂等性检查：如果代理已开启，不重复操作
    if is_proxy; then
        remind "$proxy_already_on_msg"
        return 0
    fi

    # 获取并验证代理端口
    _po_mixed=$(find_user_config 'mixed-port' 2>/dev/null)
    if [ -n "$_po_mixed" ] && [ "$_po_mixed" != "null" ]; then
        _po_http_port="$_po_mixed"
        _po_socks_port="$_po_mixed"
    else
        _po_http_port=$(find_user_config 'port' 2>/dev/null)
        _po_socks_port=$(find_user_config 'socks-port' 2>/dev/null)
    fi

    # 端口有效性验证
    if [ -z "$_po_http_port" ] || [ "$_po_http_port" = "null" ]; then
        if [ -z "$_po_socks_port" ] || [ "$_po_socks_port" = "null" ]; then
            failed "$proxy_no_port_msg"
            return 1
        fi
        _po_http_port="$_po_socks_port"
    fi
    if [ -z "$_po_socks_port" ] || [ "$_po_socks_port" = "null" ]; then
        _po_socks_port="$_po_http_port"
    fi
    # 确保端口是数字且在有效范围
    for _po_p in "$_po_http_port" "$_po_socks_port"; do
        if ! echo "$_po_p" | grep -qE '^[0-9]+$' 2>/dev/null; then
            failed "$(printf "$proxy_invalid_port_msg" "$_po_p")"
            return 1
        fi
        if [ "$_po_p" -lt 1 ] || [ "$_po_p" -gt 65535 ] 2>/dev/null; then
            failed "$(printf "$proxy_invalid_port_msg" "$_po_p")"
            return 1
        fi
    done

    # 验证端口是否可连接（快速超时检测）
    if command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
        if ! timeout 2 bash -c "echo > /dev/tcp/${local_proxy_host}/${_po_http_port}" 2>/dev/null; then
            warn "$(printf "$proxy_port_unreachable_msg" "$_po_http_port")" false
        fi
    fi

    # 1. Shell 级别：写入所有已安装 shell 的配置文件
    _po_rc_files=$(detect_shell_rc_files)
    for _po_rc in $_po_rc_files; do
        _po_steps=$((_po_steps + 1))
        if _proxy_set_shell_rc "$_po_rc" "$_po_http_port" "$_po_socks_port"; then
            _po_applied="${_po_applied}shell(${_po_rc##*/}) "
        else
            _po_errors=$((_po_errors + 1))
        fi
    done

    # 2. 当前 shell 环境变量即时生效
    _po_steps=$((_po_steps + 1))
    _proxy_set_env "$_po_http_port" "$_po_socks_port"
    _po_applied="${_po_applied}env "

    # 3. 系统级别（需要 root 权限）
    if [ "$(id -u)" = "0" ] || [ -n "$SUDO_USER" ]; then
        _po_steps=$((_po_steps + 1))
        _proxy_set_system "$_po_http_port" "$_po_socks_port"
        _po_applied="${_po_applied}system "
    else
        remind "$proxy_root_needed_msg"
    fi

    # 4. 桌面环境级别
    _po_de=$(detect_desktop_environment)
    _po_steps=$((_po_steps + 1))
    case "$_po_de" in
        gnome|mate|cinnamon|budgie|deepin)
            _proxy_set_gnome "$_po_http_port" "$_po_socks_port"
            _po_applied="${_po_applied}gnome "
            ;;
        kde)
            _proxy_set_kde "$_po_http_port" "$_po_socks_port"
            _po_applied="${_po_applied}kde "
            ;;
        xfce)
            _proxy_set_xfce "$_po_http_port" "$_po_socks_port"
            _po_applied="${_po_applied}xfce "
            ;;
        lxqt|lxde)
            remind "$proxy_lxde_env_msg"
            ;;
        *)
            _po_applied="${_po_applied}de(none) "
            ;;
    esac

    # 5. NetworkManager
    _po_steps=$((_po_steps + 1))
    _proxy_set_nm "$_po_http_port" "$_po_socks_port"
    _po_applied="${_po_applied}nm"

    # 结果汇总
    if [ "$_po_errors" -gt 0 ]; then
        warn "$(printf "$proxy_partial_msg" "$_po_errors" "$_po_steps")" false
    fi
    success "$proxy_on_success_msg"
    normal "$(printf "$proxy_applied_msg" "$_po_applied")"
}

# 优化：幂等性 + 错误追踪 + 强制清理 + 详细日志
proxy_off() {
    _pof_errors=0
    _pof_steps=0
    _pof_cleaned=""

    # 幂等性检查：如果代理已关闭，不重复操作
    if ! is_proxy; then
        remind "$proxy_already_off_msg"
        return 0
    fi

    # 1. Shell 级别：清除所有 shell 配置文件中的代理设置
    _pof_rc_files=$(detect_shell_rc_files)
    for _pof_rc in $_pof_rc_files; do
        _pof_steps=$((_pof_steps + 1))
        if _proxy_unset_shell_rc "$_pof_rc"; then
            _pof_cleaned="${_pof_cleaned}shell(${_pof_rc##*/}) "
        else
            _pof_errors=$((_pof_errors + 1))
        fi
    done

    # 2. 当前 shell 环境变量
    _pof_steps=$((_pof_steps + 1))
    _proxy_unset_env
    _pof_cleaned="${_pof_cleaned}env "

    # 3. 系统级别（需要 root 权限）
    if [ "$(id -u)" = "0" ] || [ -n "$SUDO_USER" ]; then
        _pof_steps=$((_pof_steps + 1))
        _proxy_unset_system
        _pof_cleaned="${_pof_cleaned}system "
    fi

    # 4. 桌面环境级别
    _pof_de=$(detect_desktop_environment)
    _pof_steps=$((_pof_steps + 1))
    case "$_pof_de" in
        gnome|mate|cinnamon|budgie|deepin)
            _proxy_unset_gnome
            _pof_cleaned="${_pof_cleaned}gnome "
            ;;
        kde)
            _proxy_unset_kde
            _pof_cleaned="${_pof_cleaned}kde "
            ;;
        xfce)
            _proxy_unset_xfce
            _pof_cleaned="${_pof_cleaned}xfce "
            ;;
        *)
            _pof_cleaned="${_pof_cleaned}de(none) "
            ;;
    esac

    # 5. NetworkManager
    _pof_steps=$((_pof_steps + 1))
    _proxy_unset_nm
    _pof_cleaned="${_pof_cleaned}nm"

    # 验证清理是否完整
    _pof_steps=$((_pof_steps + 1))
    if is_proxy; then
        _pof_errors=$((_pof_errors + 1))
        warn "$proxy_cleanup_incomplete_msg" false
    fi

    # 结果汇总
    if [ "$_pof_errors" -gt 0 ]; then
        warn "$(printf "$proxy_partial_msg" "$_pof_errors" "$_pof_steps")" false
    fi
    success "$proxy_off_success_msg"
    normal "$(printf "$proxy_applied_msg" "$_pof_cleaned")"
}

is_proxy() {
    # 1. 检查当前 shell 环境变量
    for _ip_key in $proxy_protocols; do
        if [ -n "$(eval "echo \"\$${_ip_key}_proxy\"")" ]; then
            return 0
        fi
    done

    # 2. 检查 shell 配置文件
    _ip_rc_files=$(detect_shell_rc_files)
    for _ip_rc in $_ip_rc_files; do
        if [ -f "$_ip_rc" ] && grep -q '_proxy=' "$_ip_rc" 2>/dev/null; then
            return 0
        fi
    done

    # 3. 检查系统级代理
    if [ -f /etc/profile.d/clash-proxy.sh ]; then
        return 0
    fi

    # 4. 检查桌面环境代理
    _ip_de=$(detect_desktop_environment)
    case "$_ip_de" in
        gnome|mate|cinnamon|budgie|deepin)
            if command -v gsettings >/dev/null 2>&1; then
                _ip_mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null)
                [ "$_ip_mode" = "'manual'" ] && return 0
            elif command -v dconf >/dev/null 2>&1; then
                _ip_mode=$(dconf read /system/proxy/mode 2>/dev/null)
                [ "$_ip_mode" = "'manual'" ] && return 0
            fi
            ;;
        kde)
            _ip_kde_cmd=$(_kde_config_cmd)
            if command -v "$_ip_kde_cmd" >/dev/null 2>&1; then
                _ip_mode=$("$_ip_kde_cmd" --file kioslaverc --group "Proxy Settings" --key ProxyType 2>/dev/null)
                [ "$_ip_mode" = "1" ] && return 0
            fi
            ;;
        xfce)
            if command -v xfconf-query >/dev/null 2>&1; then
                _ip_mode=$(xfconf-query -c xfce4-session -p /xfce4/session/Net/Proxy/Mode 2>/dev/null)
                [ "$_ip_mode" = "manual" ] && return 0
            fi
            ;;
    esac

    return 1
}

is_auto_start(){
    local _ias_val=$(find_clashtool_config "auto_start" 2>/dev/null)
    [ "$_ias_val" = "true" ] && return 0
    # 也检查 systemd/rc-update 实际状态
    case "$(get_linux_distribution)" in
        "alpine")
            rc-update show default 2>/dev/null | grep -q "$service_name" && return 0
            ;;
        "centos"|"redhat"|"ubuntu"|"debian"|"kylin"|"deepin")
            systemctl is-enabled "$service_name" 2>/dev/null | grep -q "enabled" && return 0
            ;;
    esac
    return 1
}

is_gateway(){
    local _igw_val=$(find_clashtool_config "gateway" 2>/dev/null)
    [ "$_igw_val" = "true" ] && return 0
    return 1
}

# 参数: $1：enable - 是否启用 （可选），默认为 true（true/false）
proxy(){
    enable=${1:-true}
    if [ "$enable" = "true" ];then
        if [ -f "${clash_binary_path}" ]; then
            # 刷新运行状态
            refresh_status
            if $clash_is_running ;then
                proxy_on
            else
                failed "$clash_not_running_warn_msg" false
            fi
        else
            failed "Clash $not_install_msg" false
        fi
    elif [ "$enable" = "false" ];then
        proxy_off
    else
        failed "$verify_failed_msg" false
    fi
}

backup_dir="${config_dir}/backups"

backup_config(){
    if [ ! -d "$backup_dir" ]; then
        if ! mkdir -p "$backup_dir" 2>/dev/null; then
            failed "$backup_failed_msg"
            return 1
        fi
    fi
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="${backup_dir}/${backup_name}.tar.gz"
    # 临时文件放在 backup_dir 之外（同文件系统父目录），避免 tar 递归打包自身
    # 同时用 --exclude 排除 backups 目录，避免包含旧备份导致归档越来越大
    local parent_dir
    parent_dir=$(dirname "$config_dir")
    local cfg_base
    cfg_base=$(basename "$config_dir")
    local tmp_path="${parent_dir}/.${backup_name}.tar.gz.tmp"
    if tar -czf "$tmp_path" -C "$parent_dir" --exclude="${cfg_base}/backups" "$cfg_base" 2>/dev/null && [ -s "$tmp_path" ]; then
        mv "$tmp_path" "$backup_path" 2>/dev/null
        success "$backup_success_msg"
        normal "$backup_path_msg $backup_path"
    else
        rm -f "$tmp_path" 2>/dev/null
        failed "$backup_failed_msg"
        return 1
    fi
}

# proxy_show_status 定义在下方 TUI 模块中（详细版：显示规则组/服务器/延迟）
# 如需查看本机代理/网关/自启状态，请使用 'clashtool status' 命令

# CLI 命令别名
backup() { backup_config "$@"; }
restore() { restore_backup "$@"; }
proxy_status() { proxy_show_status "$@"; }

list_backups(){
    if [ ! -d "$backup_dir" ]; then
        echo "$backup_list_empty_msg"
        return
    fi
    local backups=$(ls -t "$backup_dir"/*.tar.gz 2>/dev/null)
    if [ -z "$backups" ]; then
        echo "$backup_list_empty_msg"
    else
        printf "%b\n" "${COLOR_CYAN}$backup_list_title_msg${COLOR_RESET}"
        ls -lh "$backup_dir"/*.tar.gz 2>/dev/null | awk '{print $9, "(" $5 ")"}'
    fi
}

# 选择备份（列表选择）
# 结果通过全局变量 SELECTED_BACKUP 返回
# 返回值: 0=成功选择, 1=取消/无备份
select_backup(){
    SELECTED_BACKUP=""
    if [ ! -d "$backup_dir" ]; then
        warn "$backup_list_empty_msg" false
        return 1
    fi
    # 收集备份文件名到位置参数
    set --
    for _sb_file in $(ls -t "$backup_dir"/*.tar.gz 2>/dev/null); do
        set -- "$@" "$(basename "$_sb_file" .tar.gz)"
    done
    if [ $# -eq 0 ]; then
        warn "$backup_list_empty_msg" false
        return 1
    fi
    # 显示选择菜单
    menu_dispatch "$backup_select_title" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            # 获取选择的备份名
            _sb_idx=0
            for _sb_item in "$@"; do
                [ "$_sb_idx" = "$MENU_RESULT" ] && break
                _sb_idx=$((_sb_idx + 1))
            done
            SELECTED_BACKUP="$_sb_item"
            return 0
            ;;
    esac
}

restore_backup(){
    if ! select_backup; then
        return 1
    fi
    local backup_path="${backup_dir}/${SELECTED_BACKUP}.tar.gz"
    if [ ! -f "$backup_path" ]; then
        failed "$backup_not_exist_msg"
        return 1
    fi
    # 交互式终端兼容的确认方式
    if _is_interactive_terminal; then
        tui_confirm "$backup_confirm_msg"
        local confirm=$TUI_CONFIRM_RESULT
    else
        printf "%b" "${COLOR_YELLOW}${backup_confirm_msg} (y/n): ${COLOR_RESET}"
        read -r confirm
    fi
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || [ "$confirm" = "YES" ]; then
        tar -xzf "$backup_path" -C "$(dirname "$config_dir")" 2>/dev/null
        if [ $? -eq 0 ]; then
            success "$backup_restore_success_msg"
        else
            failed "$backup_restore_failed_msg"
            return 1
        fi
    fi
}

delete_backup(){
    if ! select_backup; then
        return 1
    fi
    local backup_path="${backup_dir}/${SELECTED_BACKUP}.tar.gz"
    if [ ! -f "$backup_path" ]; then
        failed "$backup_not_exist_msg"
        return 1
    fi
    rm -f "$backup_path"
    success "$backup_delete_success_msg"
}

# select_subscription moved to TUI section below

view_logs(){
    refresh_status
    $clash_is_running || { failed "$clash_not_running_warn_msg"; return 1; }
    # 查找 Clash 日志文件
    local _vl_log_path=$(find_user_config "log-file" 2>/dev/null)
    if [ -n "$_vl_log_path" ] && [ -f "$_vl_log_path" ]; then
        tail -50 "$_vl_log_path" 2>/dev/null || failed "$logs_empty_msg"
    elif [ -f "${log_dir}/clash.log" ]; then
        tail -50 "${log_dir}/clash.log" 2>/dev/null || failed "$logs_empty_msg"
    else
        local _vl_tmp
        _vl_tmp=$(mktemp /tmp/clash_log.XXXXXX 2>/dev/null) || _vl_tmp="/tmp/clash_log.$$"
        sh "$script_path" status > "$_vl_tmp" 2>&1
        if [ -f "$_vl_tmp" ]; then cat "$_vl_tmp"; rm -f "$_vl_tmp"
        else failed "$logs_empty_msg"; fi
    fi
}

_logs_find_file() {
    local _llf_path=$(find_user_config "log-file" 2>/dev/null)
    if [ -n "$_llf_path" ] && [ -f "$_llf_path" ]; then
        echo "$_llf_path"
    elif [ -f "${log_dir}/clash.log" ]; then
        echo "${log_dir}/clash.log"
    else
        echo ""
    fi
}

# logs_menu moved to TUI section below

health_check(){
    refresh_status
    # 显示自动恢复状态
    local auto_recovery=$(find_clashtool_config "auto_recovery" 2>/dev/null)
    echo "$health_check_auto_recovery_status_msg ${auto_recovery:-disabled}"
    # 显示运行状态
    if $clash_is_running; then
        local mem=$(ps -o rss= -p "$clash_pid" 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
        local cpu=$(ps -p "$clash_pid" -o %cpu= 2>/dev/null)
        printf "%b\n" "${COLOR_GREEN}$health_check_ok_msg${COLOR_RESET}"
        echo "$health_clash_uptime_msg $(ps -p "$clash_pid" -o etime= 2>/dev/null)"
        echo "$health_clash_memory_msg $mem"
        echo "$health_clash_cpu_msg ${cpu}%"
        # 统计活动连接数：读取配置端口（mixed-port / socks-port / port）
        local _hc_ports=""
        local _hc_mixed=$(find_user_config "mixed-port" 2>/dev/null)
        local _hc_socks=$(find_user_config "socks-port" 2>/dev/null)
        local _hc_http=$(find_user_config "port" 2>/dev/null)
        [ -n "$_hc_mixed" ] && _hc_ports="$_hc_ports:$_hc_mixed"
        [ -n "$_hc_socks" ] && _hc_ports="$_hc_ports:$_hc_socks"
        [ -n "$_hc_http" ] && _hc_ports="$_hc_ports:$_hc_http"
        local connections=0
        if [ -n "$_hc_ports" ]; then
            connections=$(ss -tn 2>/dev/null | grep -cE "$(echo "$_hc_ports" | sed 's/^://; s/:/|/g')" 2>/dev/null) || connections=0
        fi
        echo "$health_clash_connections_msg $connections"
    else
        failed "$clash_not_running_warn_msg"
        return 1
    fi
}

get_health_status(){
    health_check
}

toggle_auto_recovery(){
    local _tar_current=$(find_clashtool_config "auto_recovery" 2>/dev/null)
    if [ "$_tar_current" = "enabled" ]; then
        update_clashtool_config "auto_recovery" "disabled"
        success "$health_check_auto_recovery_disabled_msg"
    else
        update_clashtool_config "auto_recovery" "enabled"
        success "$health_check_auto_recovery_enabled_msg"
    fi
}

profiles_dir="${config_dir}/profiles"

list_profiles(){
    if [ ! -d "$profiles_dir" ]; then
        mkdir -p "$profiles_dir"
        echo "$profile_not_exist_msg"
        return
    fi
    printf "%b\n" "${COLOR_CYAN}$profile_list_title_msg${COLOR_RESET}"
    ls -1 "$profiles_dir" 2>/dev/null || echo "$profile_not_exist_msg"
}

# 选择配置文件（列表选择）
# 结果通过全局变量 SELECTED_PROFILE 返回
# 返回值: 0=成功选择, 1=取消/无配置文件
select_profile(){
    SELECTED_PROFILE=""
    if [ ! -d "$profiles_dir" ]; then
        warn "$profile_not_exist_msg" false
        return 1
    fi
    # 收集配置文件名到位置参数
    set --
    for _sp_file in "$profiles_dir"/*; do
        [ -f "$_sp_file" ] && set -- "$@" "$(basename "$_sp_file")"
    done
    if [ $# -eq 0 ]; then
        warn "$profile_not_exist_msg" false
        return 1
    fi
    # 显示选择菜单
    menu_dispatch "$profile_select_title" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            # 获取选择的配置文件名
            _sp_idx=0
            for _sp_item in "$@"; do
                [ "$_sp_idx" = "$MENU_RESULT" ] && break
                _sp_idx=$((_sp_idx + 1))
            done
            SELECTED_PROFILE="$_sp_item"
            return 0
            ;;
    esac
}

create_profile(){
    get_input "$profile_name_msg"
    if [ "$GET_INPUT_CANCELED" = "true" ]; then
        warn "$input_canceled_msg" false; return 1
    fi
    local profile_name="$GET_INPUT_RESULT"
    # 验证名称: 非空且不含特殊字符
    if [ -z "$profile_name" ]; then
        warn "$validate_name_msg" false
        return 1
    fi
    if echo "$profile_name" | grep -qE '[/\\:*?"<>|[:space:]]'; then
        warn "$validate_name_msg" false
        return 1
    fi
    local profile_path="${profiles_dir}/${profile_name}"
    if [ -f "$profile_path" ]; then
        failed "$profile_already_exists_msg"
        return 1
    fi
    cp "$main_config_path" "$profile_path" 2>/dev/null && success "$profile_create_success_msg" || failed "$profile_failed_msg"
}

switch_profile(){
    if ! select_profile; then
        return 1
    fi
    local profile_path="${profiles_dir}/${SELECTED_PROFILE}"
    if [ ! -f "$profile_path" ]; then
        failed "$profile_not_exist_msg"
        return 1
    fi
    cp "$profile_path" "$main_config_path" && success "$profile_switch_success_msg" || failed "$profile_switch_failed_msg"
}

delete_profile(){
    if ! select_profile; then
        return 1
    fi
    local profile_path="${profiles_dir}/${SELECTED_PROFILE}"
    if [ ! -f "$profile_path" ]; then
        failed "$profile_not_exist_msg"
        return 1
    fi
    rm -f "$profile_path" && success "$profile_delete_success_msg"
}

list_rules(){
    # list_rules 仅读取配置文件，不需要 Clash 运行
    if [ ! -f "$main_config_path" ]; then
        failed "$config_file_not_found_msg"
        return 1
    fi
    printf "%b\n" "${COLOR_CYAN}$rules_builtin_msg:${COLOR_RESET}"
    grep -E "^- RULE" "$main_config_path" 2>/dev/null | head -20 || echo "$rules_not_found_msg"
    echo ""
    printf "%b\n" "${COLOR_CYAN}$rules_provider_msg:${COLOR_RESET}"
    grep -E "rule-providers:" -A 20 "$main_config_path" 2>/dev/null | grep -E "name:|type:" | paste - - || echo "$rules_not_found_msg"
}

# 编辑规则文件
rules_edit(){
    if [ ! -f "$main_config_path" ]; then
        failed "$config_file_not_found_msg"
        return 1
    fi
    config_edit_file "$main_config_path"
}

# 添加自定义规则
rules_add(){
    if [ ! -f "$main_config_path" ]; then
        failed "$config_file_not_found_msg"
        return 1
    fi
    get_input "$rules_add_prompt_msg"
    if [ "$GET_INPUT_CANCELED" = "true" ]; then
        warn "$input_canceled_msg" false; return 1
    fi
    local _ra_rule="$GET_INPUT_RESULT"
    if [ -z "$_ra_rule" ]; then
        return 1
    fi
    # 验证规则格式: 至少包含两个逗号分隔的字段
    local _ra_count=$(echo "$_ra_rule" | awk -F',' '{print NF}')
    if [ "$_ra_count" -lt 3 ]; then
        warn "$validate_rule_msg" false
        return 1
    fi
    # 使用 yq 在 rules 数组末尾追加规则（通过 stdin 传入避免表达式注入）
    _ra_escaped=$(printf '%s' "$_ra_rule" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '%s' ".rules += [\"$_ra_escaped\"]" | "$yq_binary_path" e - -i "$main_config_path" 2>/dev/null
    if [ $? -eq 0 ]; then
        success "$rules_add_success_msg"
    else
        failed "$rules_add_failed_msg"
        return 1
    fi
}

# tools moved to TUI section below

is_root() {
    [ "$(id -u)" -eq 0 ]
}

is_docker() {
    detect_docker
}

# 参数: $1 - 命令名
# 返回: 0=需要root, 1=不需要
requires_root() {
    case "$1" in
        "gateway"|"create_service_file"|"del_service_file")
            # 网关模式和服务文件管理需要 root
            is_root || return 0
            return 1
            ;;
        "system_proxy"|"install_ui"|"update_ui"|"uninstall_ui")
            # 系统级代理设置和系统目录下的 UI 安装/更新/卸载需要 root
            is_root || return 0
            return 1
            ;;
    esac
    return 1
}

check_dir_writable() {
    local dir="$1"
    [ -w "$dir" ]
}

check_dir_readable() {
    local dir="$1"
    [ -r "$dir" ] && [ -x "$dir" ]
}

ensure_dir() {
    local dir="$1"
    local perm="${2:-755}"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || return 1
        chmod "$perm" "$dir" 2>/dev/null
    fi
    [ -d "$dir" ] && [ -w "$dir" ]
}

# 参数: $1 - 要添加的路径
# 返回: 0=成功, 1=失败
add_to_path() {
    local _atp_dir="$1"
    # 检查是否已在PATH中
    case ":${PATH}:" in
        *:"${_atp_dir}":*) return 0 ;;
    esac
    # 添加到当前会话
    PATH="${_atp_dir}:${PATH}"
    export PATH
    return 0
}

# 参数: $1 - 要添加的路径
update_shell_rc() {
    local _usr_dir="$1"
    local _usr_rc=""
    local _usr_marker="# clashtool PATH"
    
    # 检测当前shell类型
    case "${SHELL:-}" in
        */zsh) _usr_rc="${HOME}/.zshrc" ;;
        */bash) _usr_rc="${HOME}/.bashrc" ;;
        */sh) _usr_rc="${HOME}/.profile" ;;
        *) 
            # 回退到 .profile
            _usr_rc="${HOME}/.profile"
            ;;
    esac
    
    # 如果是 root 用户，也更新 /etc/profile
    if is_root; then
        local _usr_etcp="/etc/profile.d/clashtool.sh"
        if [ ! -f "$_usr_etcp" ] || ! grep -q "$_usr_dir" "$_usr_etcp" 2>/dev/null; then
            cat > "$_usr_etcp" <<EOF
$_usr_marker
if [ -d "$_usr_dir" ]; then
    case ":\${PATH}:" in
        *:"${_usr_dir}":*) ;;
        *) PATH="${_usr_dir}:\${PATH}" ;;
    esac
    export PATH
fi
EOF
            chmod 0644 "$_usr_etcp" 2>/dev/null
        fi
        return 0
    fi
    
    # 普通用户更新 ~/.bashrc 或 ~/.zshrc
    if [ -n "$_usr_rc" ]; then
        if [ ! -f "$_usr_rc" ] || ! grep -q "$_usr_dir" "$_usr_rc" 2>/dev/null; then
            {
                echo ""
                echo "$_usr_marker"
                echo "if [ -d \"$_usr_dir\" ]; then"
                echo "    case \"\${PATH}:\" in"
                echo "        *:\"${_usr_dir}\":*) ;;"
                echo "        *) PATH=\"${_usr_dir}:\${PATH}\" ;;"
                echo "    esac"
                echo "    export PATH"
                echo "fi"
            } >> "$_usr_rc"
        fi
    fi
}

# 返回: 0=正常, 1=需要修复
check_symlink() {
    if [ -z "$symlink_path" ] || [ -z "$script_path" ]; then
        return 1
    fi
    # 检查软链接是否存在且指向正确
    if [ -L "$symlink_path" ]; then
        local _cs_target
        _cs_target=$(readlink -f "$symlink_path" 2>/dev/null)
        if [ "$_cs_target" = "$script_path" ]; then
            return 0
        fi
    fi
    return 1
}

# 返回: 0=成功, 1=失败
repair_symlink() {
    if [ -z "$symlink_path" ] || [ -z "$script_path" ]; then
        return 1
    fi
    # 确保目标目录存在
    ensure_dir "$symlink_dir" 755 || return 1
    # 删除旧链接（如果存在）
    rm -f "$symlink_path" 2>/dev/null
    # 创建新链接
    ln -sf "$script_path" "$symlink_path" 2>/dev/null || return 1
    # 更新PATH
    add_to_path "$symlink_dir"
    # 更新shell配置
    update_shell_rc "$symlink_dir"
    return 0
}

check_cmd_available() {
    command -v "$cmd_name" >/dev/null 2>&1
}

# 安装/修复符号链接后提示用户如何在当前 shell 中使用 clashtool 命令
# clashtool.sh 作为子进程运行，无法直接修改父 shell 的 PATH 和 hash 表
# - root 安装：/usr/local/bin 通常已在 PATH 中，bash/zsh 需要 hash -r
# - 用户级安装：~/.local/bin 可能不在 PATH 中，需要 export PATH
post_install_hint() {
    if is_root; then
        remind "$post_install_hint_hash_msg" false
    else
        remind "$(printf "$post_install_hint_export_msg" "$symlink_dir")" false
    fi
}

# 参数: $1 - 操作名称
permission_denied_msg() {
    local _pdm_op="$1"
    if is_root; then
        printf "%b" "${COLOR_RED}$(printf "$permission_denied_root_msg" "$_pdm_op")${COLOR_RESET}"
    else
        printf "%b" "${COLOR_RED}$(printf "$permission_denied_user_msg" "$_pdm_op")${COLOR_RESET}"
        printf "\n%b" "${COLOR_YELLOW}$(printf "$permission_try_sudo_msg" "$SCRIPT_PATH" "$_pdm_op")${COLOR_RESET}"
        if is_docker; then
            printf "\n%b" "${COLOR_YELLOW}${docker_limited_msg}${COLOR_RESET}"
        fi
    fi
}

has_sudo() {
    command -v sudo >/dev/null 2>&1
}

has_su() {
    command -v su >/dev/null 2>&1
}

# 综合检测：$- 变量、stdin TTY、/dev/tty 可用性
is_interactive_shell() {
    # 方法1: 检查 $- 变量是否包含 i
    echo "$-" | grep -q i && return 0
    # 方法2: 检查 stdin 是否是 TTY（更可靠）
    [ -t 0 ] && return 0
    # 方法3: 检查 /dev/tty 是否可实际打开并操作（不只是权限检查，容器中 /dev/tty 权限可过但无法打开）
    if [ -c /dev/tty ] 2>/dev/null && command -v stty >/dev/null 2>&1; then
        { stty -g </dev/tty; } >/dev/null 2>&1 && return 0
    fi
    return 1
}

# TUI detection and rendering moved to TUI section below

check_and_elevate() {
    if is_root; then
        return 0
    fi

    # 管道安装模式：无本地脚本文件，需先下载到临时文件再提权执行
    if [ "$_is_piped_install" = "true" ]; then
        _ce_temp=$(mktemp "/tmp/clashtool_elevate.XXXXXX" 2>/dev/null) || _ce_temp="/tmp/clashtool_elevate.$$"
        if curl -s --max-time 30 -o "$_ce_temp" "${github_proxy_url}https://raw.githubusercontent.com/${project_repo}/clashtool.sh" 2>/dev/null && [ -s "$_ce_temp" ] && grep -q '^#' "$_ce_temp" 2>/dev/null; then
            if has_sudo; then
                if ! is_interactive_shell && ! sudo -n true 2>/dev/null; then
                    rm -f "$_ce_temp" 2>/dev/null
                    failed "$cannot_elevate_sudo_noninteractive_msg"
                    return 1
                fi
                exec sudo sh "$_ce_temp" "$@"
            elif has_su; then
                if is_interactive_shell; then
                    printf "%b\n" "${COLOR_CYAN}${enter_root_password_msg}${COLOR_RESET}"
                    _ce_cmd="sh '$_ce_temp'"
                    for _ce_arg in "$@"; do
                        _ce_cmd="$_ce_cmd '$(printf '%s' "$_ce_arg" | sed "s/'/'\\\\''/g")'"
                    done
                    exec su -c "$_ce_cmd"
                fi
            fi
        fi
        rm -f "$_ce_temp" 2>/dev/null
        printf "%b\n" "${COLOR_RED}$(printf "$piped_root_required_msg")${COLOR_RESET}"
        printf "%b\n" "${COLOR_YELLOW}$(printf "$piped_root_command_msg" "$project_repo")${COLOR_RESET}"
        return 1
    fi

    if has_sudo; then
        # 非交互 shell 下先测试 passwordless sudo，避免 exec 后 sudo 失败无法捕获错误
        if ! is_interactive_shell && ! sudo -n true 2>/dev/null; then
            failed "$cannot_elevate_sudo_noninteractive_msg"
            return 1
        fi
        # 重新以sudo方式执行当前脚本（exec成功不会返回）
        if echo "$-" | grep -q x; then
            exec sudo sh -x "$SCRIPT_PATH" "$@"
        else
            exec sudo sh "$SCRIPT_PATH" "$@"
        fi
        # exec失败才会执行到这里
        failed "${not_root_execute_msg}"
    elif has_su; then
        if is_interactive_shell; then
            printf "%b\n" "${COLOR_CYAN}${enter_root_password_msg}${COLOR_RESET}"
            # 构造单字符串命令，对每个参数做单引号转义以处理空格和特殊字符
            _ce_cmd="sh '$SCRIPT_PATH'"
            for _ce_arg in "$@"; do
                _ce_cmd="$_ce_cmd '$(printf '%s' "$_ce_arg" | sed "s/'/'\\\\''/g")'"
            done
            exec su -c "$_ce_cmd"
            failed "${not_root_execute_msg}"
        else
            failed "$cannot_elevate_no_sudo_msg"
        fi
    else
        failed "$cannot_elevate_no_way_msg"
    fi
}
# 参数：
#   $1: input - 输入字符串，格式 "key::value"
#   $2: get_func - 获取配置的函数名
#   $3: set_func - 设置配置的函数名
#   $4: error_msg - 错误消息
config_operation() {
    local input="$1"
    local get_func="$2"
    local set_func="$3"
    local error_msg="$4"
    
    local key=$(echo "${input}" | awk -F '::' '{print $1}')
    local val=$(echo "${input}" | awk -F '::' '{print $2}')
    
    if [ -z "$val" ]; then
        # 获取配置值
        local current_val=$($get_func "$key")
        echo "$current_val"
        return 0
    fi
    
    # 验证键是否存在
    local temp_val=$($get_func "$key")
    if [ -z "$temp_val" ]; then
        failed "$error_msg"
        return 1
    fi
    
    # 验证输入值
    if ! validate_config_value "$key" "$val"; then
        return 1
    fi
    
    # 更新配置
    $set_func "$key" "$val"
}

# 函数:修改用户配置
userconfig(){
    config_operation "$1" "find_user_config" "update_user_config" "$config_key_error_msg"
}

# 函数:获取或修改clashtool配置
clashtool() {
    config_operation "$1" "find_clashtool_config" "update_clashtool_config" "$config_key_error_msg"
}

# ==================== Clash 用户配置编辑功能 ====================

# 查看所有用户配置项
config_view() {
    if [ ! -f "$user_config_path" ]; then
        warn "$config_view_empty_msg" false
        return 1
    fi
    _cv_content=$("$yq_binary_path" e '.' "$user_config_path" 2>/dev/null)
    if [ -z "$_cv_content" ]; then
        warn "$config_view_empty_msg" false
        return 1
    fi
    printf "%b\n" "${COLOR_CYAN}${config_view_title_msg}${COLOR_RESET}"
    printf "%s\n" "$_cv_content"
}

# 选择配置键（从 clash_config_keys 列表）
# 结果通过全局变量 SELECTED_CONFIG_KEY 返回
# 返回值: 0=成功选择, 1=取消
select_config_key() {
    SELECTED_CONFIG_KEY=""
    # 将空格分隔的键名转为位置参数
    _old_ifs="$IFS"
    IFS=' '
    set -f
    set -- $clash_config_keys
    set +f
    IFS="$_old_ifs"
    if [ $# -eq 0 ]; then
        warn "$config_no_keys_msg" false
        return 1
    fi
    menu_dispatch "$config_select_key_title" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            _sck_idx=0
            for _sck_item in "$@"; do
                [ "$_sck_idx" = "$MENU_RESULT" ] && break
                _sck_idx=$((_sck_idx + 1))
            done
            SELECTED_CONFIG_KEY="$_sck_item"
            return 0
            ;;
    esac
}

# 设置/修改配置项
# 参数（可选）: key::value - 非交互式设置；无参数则进入交互式选择
config_set() {
    # 非交互式模式：参数格式 key::value
    if [ -n "$1" ]; then
        case "$1" in
            *::*)
                _cs_key="${1%%::*}"
                _cs_val="${1#*::}"
                ;;
            *)
                failed "$add_sub_parameter_failed_msg: key::value"
                return 1
                ;;
        esac
        if [ -z "$_cs_key" ] || [ -z "$_cs_val" ]; then
            failed "$config_set_failed_msg"
            return 1
        fi
        if ! validate_config_value "$_cs_key" "$_cs_val"; then
            return 1
        fi
        update_user_config "$_cs_key" "$_cs_val"
        if [ $? -eq 0 ]; then
            success "$config_set_success_msg"
        else
            failed "$config_set_failed_msg" false
        fi
        return $?
    fi
    # 交互式模式
    if ! select_config_key; then
        return 1
    fi
    _cs_key="$SELECTED_CONFIG_KEY"
    # 获取当前值作为默认值
    _cs_current=$(find_user_config "$_cs_key")
    # 构建提示信息
    _cs_prompt=$(printf "$config_set_prompt_val_msg" "$_cs_key")
    get_input "$_cs_prompt" "$_cs_current"
    if [ "$GET_INPUT_CANCELED" = "true" ]; then
        warn "$input_canceled_msg" false; return 1
    fi
    _cs_val="$GET_INPUT_RESULT"
    if [ -z "$_cs_val" ]; then
        warn "$config_set_failed_msg" false
        return 1
    fi
    # 验证输入值
    if ! validate_config_value "$_cs_key" "$_cs_val"; then
        return 1
    fi
    update_user_config "$_cs_key" "$_cs_val"
    if [ $? -eq 0 ]; then
        success "$config_set_success_msg"
    else
        failed "$config_set_failed_msg" false
    fi
}

# 删除配置项
# 参数（可选）: key - 非交互式删除；无参数则进入交互式选择
config_del() {
    # 非交互式模式：直接指定 key
    if [ -n "$1" ]; then
        _cd_key="$1"
        if [ ! -f "$user_config_path" ]; then
            failed "$config_no_keys_msg"
            return 1
        fi
        delete_user_config "$_cd_key"
        if [ $? -eq 0 ]; then
            success "$config_del_success_msg"
        else
            failed "$config_del_failed_msg" false
        fi
        return $?
    fi
    # 交互式模式
    if [ ! -f "$user_config_path" ]; then
        warn "$config_no_keys_msg" false
        return 1
    fi
    # 获取 user.yaml 中已有的顶层键列表
    _cd_keys=$(grep '^[^[:space:]#]' "$user_config_path" 2>/dev/null | sed 's/:.*//' | sed 's/[[:space:]]*$//')
    if [ -z "$_cd_keys" ]; then
        warn "$config_no_keys_msg" false
        return 1
    fi
    # 转换为位置参数
    _old_ifs="$IFS"
    IFS="
"
    set -f
    set -- $_cd_keys
    set +f
    IFS="$_old_ifs"
    if [ $# -eq 0 ]; then
        warn "$config_no_keys_msg" false
        return 1
    fi
    menu_dispatch "$config_del_prompt_msg" "$@" "$menu_return"
    case "$MENU_RESULT" in
        BACK|QUIT|''|*[!0-9]*) return 1 ;;
        *)
            _cd_idx=0
            for _cd_item in "$@"; do
                [ "$_cd_idx" = "$MENU_RESULT" ] && break
                _cd_idx=$((_cd_idx + 1))
            done
            _cd_key="$_cd_item"
            # 确认删除
            _cd_confirm_msg=$(printf "$config_del_confirm_msg" "$_cd_key")
            if _is_interactive_terminal; then
                tui_confirm "$_cd_confirm_msg"
                _cd_confirm="$TUI_CONFIRM_RESULT"
            else
                printf "%b" "${COLOR_YELLOW}${_cd_confirm_msg} (y/n): ${COLOR_RESET}"
                read -r _cd_choice
                case "$_cd_choice" in
                    y|Y|yes|YES) _cd_confirm="YES" ;;
                    *) _cd_confirm="NO" ;;
                esac
            fi
            if [ "$_cd_confirm" = "YES" ]; then
                delete_user_config "$_cd_key"
                if [ $? -eq 0 ]; then
                    success "$config_del_success_msg"
                else
                    failed "$config_del_failed_msg" false
                fi
            fi
            ;;
    esac
}

# 查看原始配置文件
config_view_raw() {
    if [ ! -f "$user_config_path" ]; then
        warn "$config_view_empty_msg" false
        return 1
    fi
    printf "%b\n" "${COLOR_CYAN}${config_raw_title_msg}${COLOR_RESET}"
    cat "$user_config_path"
}

# 使用编辑器打开配置文件
# 编辑指定配置文件（通用版）
# 参数: $1=文件路径
config_edit_file(){
    local _cef_file="$1"
    if [ ! -f "$_cef_file" ]; then
        warn "$config_view_empty_msg" false
        return 1
    fi
    # 检测可用的编辑器（优先级：GUI编辑器 > nano > vim > vi）
    _cef_editor=""
    _cef_fallback=false
    # 有图形环境时优先使用 GUI 编辑器
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        for _cef_cmd in gedit kate mousepad xed pluma geany; do
            if command -v "$_cef_cmd" >/dev/null 2>&1; then
                _cef_editor="$_cef_cmd"
                break
            fi
        done
        # 尝试 GUI 编辑器，失败则回退到终端编辑器
        if [ -n "$_cef_editor" ]; then
            printf "%b\n" "$(printf "$config_editor_msg" "$_cef_editor")"
            "$_cef_editor" "$_cef_file" 2>/dev/null
            if [ $? -ne 0 ]; then
                _cef_editor=""
                _cef_fallback=true
            fi
        fi
    fi
    # 无 GUI 编辑器或 GUI 编辑器失败时，使用终端编辑器
    if [ -z "$_cef_editor" ]; then
        for _cef_cmd in nano vim vi; do
            if command -v "$_cef_cmd" >/dev/null 2>&1; then
                _cef_editor="$_cef_cmd"
                break
            fi
        done
        if [ -z "$_cef_editor" ]; then
            failed "$config_no_editor_msg" false
            return 1
        fi
        if [ "$_cef_fallback" = "true" ]; then
            printf "%b\n" "$(printf "$config_editor_fallback_msg" "$_cef_editor")"
        else
            printf "%b\n" "$(printf "$config_editor_msg" "$_cef_editor")"
        fi
        "$_cef_editor" "$_cef_file"
    fi
    # 编辑后校验配置
    check_config "$_cef_file"
    if [ $? -ne 0 ]; then
        warn "$config_edit_invalid_msg" false
    else
        success "$config_edit_valid_msg"
    fi
}

config_edit_raw() {
    config_edit_file "$user_config_path"
}

# 参数:
#   $1: 空 - 显示所有配置; "key::value" - 设置值; "key" - 获取值
config() {
    if [ -n "$1" ]; then
        config_operation "$1" "find_user_config" "update_user_config" "$config_key_error_msg"
    else
        config_view
    fi
}

# proxy selection TUI moved to TUI section below

update_check() {
    current_path=$(readlink -f "$0")
    current=$(grep '^# version:' "$current_path" | head -1 | sed 's/# version://')
    normal "${current_version_msg}$current"
    url="https://raw.githubusercontent.com/${project_repo}/clashtool.sh"
    version=$(curl -k -s "${github_proxy_url}${url}" | grep '^# version:' | head -1 | sed 's/# version://')
    if [ -z "$version" ];then
        failed "$get_version_failed_msg"
        return 1
    fi
    normal "${latest_version_msg}$version"

    # 版本比较：仅允许升级，禁止降级
    if [ "$version" = "$current" ];then
        warn "$install_equal_versions_warn_msg" false
        return 0
    fi

    # 简单版本比较（假设版本号为 x.y.z 格式）
    _uc_current_major=$(printf '%s' "$current" | cut -d. -f1)
    _uc_current_minor=$(printf '%s' "$current" | cut -d. -f2)
    _uc_current_patch=$(printf '%s' "$current" | cut -d. -f3)
    _uc_remote_major=$(printf '%s' "$version" | cut -d. -f1)
    _uc_remote_minor=$(printf '%s' "$version" | cut -d. -f2)
    _uc_remote_patch=$(printf '%s' "$version" | cut -d. -f3)

    # 补零对齐
    _uc_current_minor=$(printf '%02d' "$_uc_current_minor" 2>/dev/null || echo "00")
    _uc_current_patch=$(printf '%02d' "$_uc_current_patch" 2>/dev/null || echo "00")
    _uc_remote_minor=$(printf '%02d' "$_uc_remote_minor" 2>/dev/null || echo "00")
    _uc_remote_patch=$(printf '%02d' "$_uc_remote_patch" 2>/dev/null || echo "00")

    _uc_current_num="${_uc_current_major}${_uc_current_minor}${_uc_current_patch}"
    _uc_remote_num="${_uc_remote_major}${_uc_remote_minor}${_uc_remote_patch}"

    if [ "$_uc_remote_num" -lt "$_uc_current_num" ] 2>/dev/null; then
        warn "$(printf "$update_downgrade_warn_msg" "$current" "$version")" false
        return 1
    fi

    # 确认更新
    if _is_interactive_terminal; then
        tui_confirm "$(printf "$update_confirm_msg" "$current" "$version")"
        _uc_confirm="$TUI_CONFIRM_RESULT"
    else
        printf "%b" "${COLOR_YELLOW}$(printf "$update_confirm_msg" "$current" "$version") (y/n): ${COLOR_RESET}"
        read -r _uc_choice
        case "$_uc_choice" in
            y|Y|yes|YES) _uc_confirm="YES" ;;
            *) _uc_confirm="NO" ;;
        esac
    fi

    if [ "$_uc_confirm" != "YES" ]; then
        return 0
    fi

    # 执行更新
    update_script
}
# main menu and sub-menus moved to TUI section below

# Resolve command group name
# Returns group name via stdout, or empty if not a group prefix
_resolve_group() {
    case "$1" in
        subscribe) echo "subscribe" ;;
        nodes) echo "nodes" ;;
        proxy) echo "proxy" ;;
        config) echo "config" ;;
        install) echo "install" ;;
        uninstall) echo "uninstall" ;;
        update) echo "update" ;;
        system) echo "system" ;;
        tools) echo "tools" ;;
        *) echo "" ;;
    esac
}

# Dispatch grouped command to underlying function
# $1=group, $2=subcommand, $3=args
_dispatch_group() {
    _dg_group="$1"
    _dg_sub="$2"
    _dg_arg="$3"
    # Check if Clash is installed for most commands
    _dg_need_install=true
    case "$_dg_group/$_dg_sub" in
        install/|install/core|install/ui|uninstall/|uninstall/core|uninstall/ui|update/script|tools/symlink|system/check|proxy/on|proxy/off) _dg_need_install=false ;;
    esac
    if [ "$_dg_need_install" = "true" ] && [ ! -f "$clash_binary_path" ]; then
        failed "$not_install_msg"
        return 1
    fi

    case "$_dg_group" in
    subscribe)
        case "$_dg_sub" in
            add) add "$_dg_arg" ;;
            del) del "$_dg_arg" ;;
            list) list ;;
            update) update_sub "$_dg_arg" ;;
            auto-update)
                case "$_dg_arg" in
                    on|true) auto_update_sub true ;;
                    off|false) auto_update_sub false ;;
                    *) auto_update_sub "$_dg_arg" ;;
                esac
                ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "subscribe" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    nodes)
        # nodes 子命令依赖 TUI 交互（菜单选择），需要交互式终端
        case "$_dg_sub" in
            select|test|urltest)
                if ! _is_interactive_terminal; then
                    failed "$tui_unavailable_msg" false
                    printf "%b\n" "${COLOR_YELLOW}$tui_use_cli_hint_msg${COLOR_RESET}"
                    return 1
                fi
                ;;
        esac
        case "$_dg_sub" in
            # proxy_select_server 内部已调用 proxy_select_group，无需重复调用
            select) proxy_select_server ;;
            test) proxy_test_delay ;;
            urltest) proxy_url_test ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "nodes" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    proxy)
        # proxy on/off 必须通过 source 执行以影响当前 shell 环境
        if ! is_sourced; then
            case "$_dg_sub" in
                on|off)
                    failed "$proxy_source_required_msg" false
                    return 1
                    ;;
            esac
        fi
        case "$_dg_sub" in
            on) proxy true ;;
            off) proxy false ;;
            status|"") proxy_show_status ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "proxy" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    config)
        case "$_dg_sub" in
            view|"") config_view ;;
            get) config "$_dg_arg" ;;
            set) config_set "$_dg_arg" ;;
            del) config_del "$_dg_arg" ;;
            edit) config_edit_raw ;;
            tool) clashtool "$_dg_arg" ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "config" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    install)
        # install 无子命令时默认安装核心+UI
        if [ -z "$_dg_sub" ]; then
            # 不管什么权限都询问安装模式
            if prompt_install_mode; then
                # 用户级安装
                set_install_paths "user"
                install "$_dg_arg" || return 1
                if ! is_ui_installed; then
                    install_ui "$_dg_arg" || return 1
                else
                    normal "$ui_already_installed_skip_msg"
                fi
            else
                # 系统级安装
                if is_root; then
                    set_install_paths "root"
                    install "$_dg_arg" || return 1
                    if ! is_ui_installed; then
                        install_ui "$_dg_arg" || return 1
                    else
                        normal "$ui_already_installed_skip_msg"
                    fi
                else
                    # 非 root 用户需要提权
                    normal "$install_mode_root_selected_msg"
                    check_and_elevate "$_dg_group" "all" "$_dg_arg"
                fi
            fi
            return 0
        fi
        case "$_dg_sub" in
            core)
                if prompt_install_mode; then
                    set_install_paths "user"
                    install "$_dg_arg"
                else
                    if is_root; then
                        set_install_paths "root"
                        install "$_dg_arg"
                    else
                        normal "$install_mode_root_selected_msg"
                        check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                    fi
                fi
                ;;
            ui)
                if prompt_install_mode; then
                    set_install_paths "user"
                    install_ui "$_dg_arg"
                else
                    if is_root; then
                        set_install_paths "root"
                        install_ui "$_dg_arg"
                    else
                        normal "$install_mode_root_selected_msg"
                        check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                    fi
                fi
                ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "install" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    uninstall)
        # uninstall 无子命令时默认卸载全部（核心+UI）
        if [ -z "$_dg_sub" ]; then
            if is_root || ! requires_root "uninstall"; then
                uninstall "$_dg_arg" || return 1
                # UI 未安装则跳过（避免 failed 退出）
                if is_ui_installed; then
                    uninstall_ui "$_dg_arg" || return 1
                else
                    normal "$ui_not_installed_skip_msg"
                fi
            else
                # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                check_and_elevate "$_dg_group" "all" "$_dg_arg"
            fi
            return 0
        fi
        case "$_dg_sub" in
            all)
                # 完全卸载：核心 + UI + 所有配置
                # uninstall "all" 会通过 clear "all" 删除整个 install_dir（含 UI 和配置）
                # uninstall() 内部已打印成功消息，此处无需重复
                if is_root || ! requires_root "uninstall"; then
                    uninstall "all"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "all" "$_dg_arg"
                fi
                ;;
            core)
                # uninstall core 仅接受 purge 参数（删除配置），拒绝 all（避免误删 UI）
                case "$_dg_arg" in
                    purge|"") _un_core_arg="$_dg_arg" ;;
                    *)
                        printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "uninstall core" "$_dg_arg")${COLOR_RESET}"
                        return 1
                        ;;
                esac
                if is_root || ! requires_root "uninstall"; then
                    uninstall "$_un_core_arg"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "$_dg_sub" "$_un_core_arg"
                fi
                ;;
            ui)
                if is_root || ! requires_root "uninstall"; then
                    uninstall_ui "$_dg_arg"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                fi
                ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "uninstall" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    update)
        # update 无子命令时默认更新核心+UI
        if [ -z "$_dg_sub" ]; then
            if is_root || ! requires_root "update"; then
                update "$_dg_arg" || return 1
                # UI 未安装则跳过
                if is_ui_installed; then
                    update_ui "$_dg_arg" || return 1
                else
                    normal "$ui_not_installed_skip_msg"
                fi
            else
                # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                check_and_elevate "$_dg_group" "all" "$_dg_arg"
            fi
            return 0
        fi
        case "$_dg_sub" in
            core)
                if is_root || ! requires_root "update"; then
                    update "$_dg_arg"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                fi
                ;;
            ui)
                if is_root || ! requires_root "update_ui"; then
                    update_ui "$_dg_arg"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                fi
                ;;
            script) update_script ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "update" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    system)
        case "$_dg_sub" in
            autostart)
                case "$_dg_arg" in
                    on|true) auto_start true ;;
                    off|false) auto_start false ;;
                    *) auto_start "$_dg_arg" ;;
                esac
                ;;
            gateway)
                if ! is_root; then
                    permission_denied_msg "gateway"
                    printf "\n"
                    failed "$gateway_root_needed_msg"
                    return 1
                fi
                case "$_dg_arg" in
                    on|true) gateway true ;;
                    off|false) gateway false ;;
                    *) gateway "$_dg_arg" ;;
                esac
                ;;
            check)
                if is_root || ! requires_root "update_check"; then
                    update_check
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"
                fi
                ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "system" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    tools)
        case "$_dg_sub" in
            logs) view_logs ;;
            backup) backup_config ;;
            list-backups) list_backups ;;
            restore) restore_backup ;;
            delete-backup) delete_backup ;;
            profiles) list_profiles ;;
            create-profile) create_profile ;;
            switch-profile) switch_profile ;;
            delete-profile) delete_profile ;;
            rules) list_rules ;;
            add-rule) rules_add ;;
            edit-rules) rules_edit ;;
            health) health_check ;;
            toggle-recovery) toggle_auto_recovery ;;
            symlink) repair_symlink && post_install_hint ;;
            *) printf "%b\n" "${COLOR_RED}$(printf "$unknown_subcommand_msg" "tools" "$_dg_sub")${COLOR_RESET}"; return 1 ;;
        esac
        ;;
    *)
        printf "%b\n" "${COLOR_RED}$(printf "$unknown_group_msg" "$_dg_group")${COLOR_RESET}"
        return 1
        ;;
    esac
}

main() {
    fun=$1
    var=$2
    # 管道安装模式：无参数时自动触发安装（curl ... | sh）
    if [ "$_is_piped_install" = "true" ] && [ -z "$fun" ]; then
        fun="install"
        # 管道安装时先选择语言（从 /dev/tty 读取，因为 stdin 被 curl 占用）
        _main_lang=$(prompt_language)
    else
        # 加载国际化语言模块（自动检测或使用用户配置）
        _main_lang=$(detect_language)
    fi
    load_i18n "$_main_lang"
    # 判断使用的命令类型
    if is_sourced;then
        # source 模式仅支持 proxy on/off
        if [ "$fun" = "proxy" ]; then
            # 将 on/off 转换为 true/false（proxy() 函数期望的参数）
            case "$var" in
                on|true) proxy true ;;
                off|false) proxy false ;;
                *) proxy "$var" ;;
            esac
        else
            failed "$non_proxy_source_msg" false
        fi
    else
        # 常用直接命令: clashtool.sh start|stop|restart|reload|status
        case "$fun" in
            start|stop|restart|reload|status)
                if [ ! -f "$clash_binary_path" ]; then
                    failed "$not_install_msg"
                    exit 1
                fi
                if is_root || ! requires_root "$fun"; then
                    "$fun" "$var"
                else
                    # check_and_elevate 会通过 sudo 重新执行整个脚本，成功后直接退出
                    check_and_elevate "$fun" "$var" "$3"
                fi
                return
                ;;
        esac
        # 分组命令系统: clashtool.sh <group> <subcommand> [args]
        _group=$(_resolve_group "$fun")
        if [ -n "$_group" ]; then
            _dispatch_group "$_group" "$var" "$3"
        elif [ "$fun" = "help" ]; then
            show_help
        elif [ -z "$fun" ]; then
            # 进入 TUI 交互模式
            # 检查并自动安装 TUI 依赖
            _tui_ready=true

            # 检查 stty 命令（TUI 需要）
            if ! command -v stty >/dev/null 2>&1; then
                remind "$tui_stty_check_msg" false
                if is_root || check_and_elevate "install" "util-linux"; then
                    install_procedure "util-linux"
                    if ! command -v stty >/dev/null 2>&1; then
                        _tui_ready=false
                    fi
                else
                    _tui_ready=false
                fi
            fi

            # TUI 模块已合并到本文件中，无需外部加载
            # 检查终端能力
            if [ "$_tui_ready" = "true" ]; then
                tui_detect_capability
                if [ "$TUI_ENABLED" = "false" ]; then
                    _tui_ready=false
                fi
            fi
            
            # 根据检查结果决定行为
            if [ "$_tui_ready" = "true" ]; then
                # TUI 可用：启动交互菜单
                # 启动时检查软链接
                if ! check_symlink && [ -f "$script_path" ]; then
                    if _is_interactive_terminal; then
                        tui_confirm "$symlink_repair_confirm_msg"
                        if [ "$TUI_CONFIRM_RESULT" = "YES" ]; then
                            repair_symlink && success "$symlink_repair_success_msg"
                        fi
                    else
                        repair_symlink 2>/dev/null
                    fi
                fi
                # 进入 TUI 菜单（无需强制 root，各操作函数内部按需提权）
                menu
            else
                # TUI 不可用：报错退出
                failed "$tui_unavailable_msg" false
                printf "%b\n" "${COLOR_YELLOW}$tui_use_cli_hint_msg${COLOR_RESET}"
                printf "%b\n" "${COLOR_YELLOW}  clashtool start|stop|restart|reload|status${COLOR_RESET}"
                printf "%b\n" "${COLOR_YELLOW}  clashtool install|update|uninstall${COLOR_RESET}"
                printf "%b\n" "${COLOR_YELLOW}  clashtool help${COLOR_RESET}"
                exit 1
            fi
        else
            printf "%b\n" "${COLOR_RED}$(printf "$unknown_command_msg" "$fun")${COLOR_RESET}"
            printf "%b\n" "${COLOR_YELLOW}${use_help_hint_msg}${COLOR_RESET}"
            exit 1
        fi
    fi
}

# 执行主函数
main "$@"