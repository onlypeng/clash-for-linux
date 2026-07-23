# 安装检测系统级 + TUI 级别选择 + 命令行级别参数

## Context（背景）

当前存在三个问题：

1. **检测不到系统级安装**：`require_installed`(L217) 只检查 `$clash_binary_path`，而该路径在初始化时按当前用户权限计算（普通用户 → `$HOME/.local/clash/clash`，root → `/opt/clash/clash`）。若 root 装了系统级 `/opt/clash`，普通用户运行时检测的是用户级路径，误判"未安装"，TUI 门禁错误拦截。

2. **TUI 流程中出现非 TUI 选择**：`prompt_install_mode`(L4139) 用 `printf`+`read` 选安装级别。TUI 的 `install_menu` 通过 `"$SCRIPT_PATH" install` spawn 子进程，子进程走 `_dispatch_group` → `prompt_install_mode`（read），破坏 TUI 一致性。

3. **命令行安装无法用参数指定级别**：`clashtool.sh install` 只能交互 prompt 选级别，无法通过参数携带。

## 决策（基于推荐方案，用户已确认直接推进）

- **参数格式**：`--user`/`--root` 标志，作为末尾参数（如 `install core 1.2.3 --root`）。Unix 惯例，可通过 `check_and_elevate` 的 `exec sudo sh "$SCRIPT_PATH" "$@"` 完整传递给提权后进程。
- **需求1范围**：检测 + 路径切换。普通用户初始化时检测用户级优先、其次系统级，自动切换 `install_dir`/`clash_binary_path` 到实际安装路径，使 `require_installed` 及后续 status/update/uninstall 都用正确路径。
- **无参数行为**：命令行 install 未携带 `--user`/`--root`（非管道）时报错提示；管道安装 `curl|sh` 保留 `read`（无 TUI 能力）；TUI 模式用 TUI 菜单选级别后传标志给子进程。

## 修改文件

- `clashtool.sh`（主文件）
- `i18n/en.sh`、`i18n/zh_CN.sh`（新增 2 个变量）

---

## 改动 1：普通用户初始化路径切换（需求1）

**位置**：`clashtool.sh` L114-123（`else` 普通用户分支）

当前：
```sh
else
    _is_root_user=false
    _run_mode="user"
    install_dir="${CLASHTOOL_INSTALL_DIR:-${HOME}/.local/${service_name}}"
    symlink_dir="${HOME}/.local/bin"
    mkdir -p "$symlink_dir" 2>/dev/null
    chmod 0700 "$symlink_dir" 2>/dev/null
    symlink_path="${symlink_dir}/${cmd_name}"
fi
```

修改为（检测用户级优先，其次系统级；都无则默认用户级供首次安装）：
```sh
else
    _is_root_user=false
    _run_mode="user"
    _user_install_dir="${CLASHTOOL_INSTALL_DIR:-${HOME}/.local/${service_name}}"
    _system_install_dir="/opt/${service_name}"
    if [ -f "${_user_install_dir}/clash" ]; then
        install_dir="$_user_install_dir"
        symlink_dir="${HOME}/.local/bin"
    elif [ -f "${_system_install_dir}/clash" ]; then
        # 系统级安装存在：普通用户用系统级路径（只读，写操作由 check_and_elevate 提权）
        install_dir="$_system_install_dir"
        symlink_dir="/usr/local/bin"
    else
        # 未安装：默认用户级路径（首次安装）
        install_dir="$_user_install_dir"
        symlink_dir="${HOME}/.local/bin"
    fi
    mkdir -p "$symlink_dir" 2>/dev/null
    chmod 0700 "$symlink_dir" 2>/dev/null
    symlink_path="${symlink_dir}/${cmd_name}"
fi
```

**效果**：`clash_binary_path="${install_dir}/clash"`(L176) 自动指向实际安装。`require_installed` 无需改动即检测到系统级安装。`refresh_status` 的 `pgrep -f "$clash_binary_path"` 也能匹配系统级进程。root+sudo 分支(L92-107)已有用户级检测，保持不动。

---

## 改动 2：main 解析 `--user`/`--root` 标志（需求3）

**位置**：`clashtool.sh` `main()` L7270-7272 及 `$3` 使用点（L7308、L7316）

当前：
```sh
main() {
    fun=$1
    var=$2
    ...
```

修改为（约定 `--user`/`--root` 作末尾标志，扫描 $2/$3/$4 提取，并清空对应位置）：
```sh
main() {
    fun=$1
    var=$2
    _arg3=$3
    _cli_install_mode=""
    # 从末尾参数提取安装级别标志（标志作末尾参数，出现即清空该位置）
    case "$var" in --user) _cli_install_mode="user"; var="";; --root) _cli_install_mode="root"; var="";; esac
    case "$_arg3" in --user) _cli_install_mode="user"; _arg3="";; --root) _cli_install_mode="root"; _arg3="";; esac
    case "$4" in --user) _cli_install_mode="user";; --root) _cli_install_mode="root";; esac
    # 派生标志字符串（供 check_and_elevate 透传给提权进程）
    _cli_mode_flag=""
    [ "$_cli_install_mode" = "user" ] && _cli_mode_flag="--user"
    [ "$_cli_install_mode" = "root" ] && _cli_mode_flag="--root"
    ...
```

然后将 `$3` 替换为 `$_arg3`：
- L7308 `check_and_elevate "$fun" "$var" "$3"` → `check_and_elevate "$fun" "$var" "$_arg3"`（start/stop 等不需级别）
- L7316 `_dispatch_group "$_group" "$var" "$3"` → `_dispatch_group "$_group" "$var" "$_arg3"`

**说明**：约定标志仅在末尾，避免位置参数歧义。`install --root`→var 清空；`install core --root`→_arg3 清空；`install core 1.2.3 --root`→$4 提取。`$_cli_mode_flag` 未加引号传参，空时展开为无。

---

## 改动 3：`prompt_install_mode` 改造（需求2+3）

**位置**：`clashtool.sh` L4139-4157

改造为三级分发：命令行参数优先 → 管道 read → 命令行报错。返回值：0=user, 1=root, 2=报错/取消。

```sh
prompt_install_mode() {
    # 1) 命令行参数已指定级别
    if [ -n "$_cli_install_mode" ]; then
        [ "$_cli_install_mode" = "user" ] && return 0
        return 1
    fi
    # 2) 管道安装模式：从 /dev/tty 读取（stdin 被 curl 占用）
    if [ "$_is_piped_install" = "true" ]; then
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
        read _pim_choice </dev/tty 2>/dev/null || _pim_choice=""
        case "$_pim_choice" in
            2) return 1 ;;
            *) return 0 ;;
        esac
    fi
    # 3) 命令行未指定级别：报错（failed 交互模式不 exit，返回 2）
    failed "$install_mode_required_msg" false
    return 2
}
```

**注意**：`failed "$msg" false` 第二参数 false 强制不 exit，随后显式 `return 2`。

---

## 改动 4：`_dispatch_group` install 分支重构（需求2+3）

**位置**：`clashtool.sh` L7053-7112（install 分支三个 `prompt_install_mode` 调用点）

将 `if prompt_install_mode; then ... else ... fi` 改为显式判断返回值，处理 ret=2（报错退出），并在 `check_and_elevate` 调用追加 `$_cli_mode_flag` 透传级别。

模式（以无子命令全安装 L7055-7082 为例）：
```sh
if [ -z "$_dg_sub" ]; then
    prompt_install_mode
    _pim_ret=$?
    if [ "$_pim_ret" = "2" ]; then return 1; fi
    if [ "$_pim_ret" = "0" ]; then
        # 用户级
        set_install_paths "user"
        install "$_dg_arg" || return 1
        if ! is_ui_installed; then
            install_ui "$_dg_arg" || return 1
        else
            normal "$ui_already_installed_skip_msg"
        fi
    else
        # 系统级 (ret=1)
        if is_root; then
            set_install_paths "root"
            install "$_dg_arg" || return 1
            if ! is_ui_installed; then
                install_ui "$_dg_arg" || return 1
            else
                normal "$ui_already_installed_skip_msg"
            fi
        else
            normal "$install_mode_root_selected_msg"
            check_and_elevate "$_dg_group" "all" "$_dg_arg" $_cli_mode_flag
        fi
    fi
    return 0
fi
```

同样模式应用到 `core`(L7084-7098) 和 `ui`(L7099-7112) 子命令分支：每处 `if prompt_install_mode; then` 改为 `prompt_install_mode; _pim_ret=$?; if [ "$_pim_ret" = "2" ]; then return 1; fi; if [ "$_pim_ret" = "0" ]; then ... else ...`，且 `check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg"` 改为 `check_and_elevate "$_dg_group" "$_dg_sub" "$_dg_arg" $_cli_mode_flag`。

**关键：root 分支补全 `_cli_mode_flag`（修复现有 bug）**。在每处 root 分支(ret=1)开头加：
```sh
[ -z "$_cli_mode_flag" ] && _cli_mode_flag="--root"
```
理由：管道安装经 `read` 选 root 时 `_cli_install_mode` 仍为空（read 不设置它），导致 `_cli_mode_flag` 空，`check_and_elevate` 不传 `--root`，sudo 重启后 `prompt_install_mode` 又走 read 重新询问（现有 bug）。补全后，无论级别来自 `--root` 参数还是 read 选择，`check_and_elevate` 都带 `--root`，重启后 `_cli_install_mode=root` 直接返回 1 不重问。

**说明**：`$_cli_mode_flag` 在 user 选 root 时为 `--root`，提权后 sudo 重启进程，main 重新解析 `--root` → `_cli_install_mode=root` → `prompt_install_mode` 直接返回 1 → is_root（sudo 后）→ set_install_paths root。链路自洽。

---

## 改动 5：新增 TUI 级别选择函数 + install_menu 接入（需求2）

**位置**：`clashtool.sh` 新增函数（放在 `prompt_install_mode` 之后约 L4158），及 `install_menu`(L2069-2123) 安装类选项。

新增函数（用全局变量 `_TUI_MODE_FLAG` 避免命令替换破坏 menu_dispatch 终端渲染）：
```sh
# TUI 选择安装级别，结果存 _TUI_MODE_FLAG（--user/--root）
# 返回：0=已选择，1=取消
_tui_pick_mode_flag() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        _tpm_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        [ -z "$_tpm_home" ] && _tpm_home="/home/$SUDO_USER"
    else
        _tpm_home="$HOME"
    fi
    menu_dispatch "$install_mode_title" \
        "$(printf "$install_mode_user_msg" "${_tpm_home}/.local/${service_name}")" \
        "$(printf "$install_mode_root_msg" "/opt/${service_name}")"
    case "$MENU_RESULT" in
        0) _TUI_MODE_FLAG="--user"; return 0 ;;
        1) _TUI_MODE_FLAG="--root"; return 0 ;;
        *) _TUI_MODE_FLAG=""; return 1 ;;
    esac
}
```

`install_menu` 安装类选项接入级别选择（仅 install 类需级别；update/uninstall 用已安装路径不需级别）：
- 选项0（完整安装）：`_tui_pick_mode_flag || continue` → `"$SCRIPT_PATH" install $_TUI_MODE_FLAG`
- 选项1（安装核心）：输版本后 → `_tui_pick_mode_flag || continue` → `"$SCRIPT_PATH" install core "$GET_INPUT_RESULT" $_TUI_MODE_FLAG`
- 选项3/4/5（安装/切换UI）：仅在**未安装**分支（`install ui`）前选级别 → `_tui_pick_mode_flag || continue` → `"$SCRIPT_PATH" install ui "$_ui" $_TUI_MODE_FLAG`；已安装分支（`update ui`）不选级别
- 选项2（更新核心）、6（更新UI）、7-10（卸载）：不变（用已安装路径）

示例（选项0）：
```sh
0)  # 完整安装 - 核心+默认UI
    _tui_pick_mode_flag || continue
    "$SCRIPT_PATH" install $_TUI_MODE_FLAG; pause_prompt
    ;;
```

---

## 改动 6：i18n 新增变量

`i18n/zh_CN.sh` 与 `i18n/en.sh` 各新增（保持两文件变量集一致）：
- `install_mode_title`：TUI 级别选择菜单标题
  - zh: `install_mode_title=" 选择安装级别 "`
  - en: `install_mode_title=" Select Install Level "`
- `install_mode_required_msg`：命令行缺级别报错
  - zh: `install_mode_required_msg="命令行安装需指定级别：使用 --user（用户级）或 --root（系统级），或直接运行 clashtool.sh 进入 TUI 选择"`
  - en: `install_mode_required_msg="Command-line install requires a level: use --user or --root, or run clashtool.sh to choose in TUI"`

同时检查 `clashtool.sh` 内置默认 i18n 区（L2790 附近）补同名默认值。

---

## 验证

### 语法检查
```sh
/bin/sh -n clashtool.sh && echo "sh OK"
/bin/dash -n clashtool.sh && echo "dash OK"
bash -n clashtool.sh && echo "bash OK"
/bin/sh -n i18n/en.sh && /bin/sh -n i18n/zh_CN.sh && echo "i18n OK"
```

### 功能验证（非交互）
```sh
/bin/sh clashtool.sh help | head -5
/bin/sh clashtool.sh status | head -3
# 命令行无级别应报错（非管道、未指定 --user/--root）
/bin/sh clashtool.sh install 2>&1 | grep -i "level\|级别" | head -2
```

### 静态确认（grep）
- 普通用户初始化含 `_system_install_dir` 检测分支
- main 含 `_cli_install_mode` 与 `_cli_mode_flag`
- `prompt_install_mode` 含 `_cli_install_mode`、`_is_piped_install`、`return 2`
- install 分支三处 `check_and_elevate` 含 `$_cli_mode_flag`
- `install_menu` 选项0/1/3-5 含 `_tui_pick_mode_flag`
- i18n 两文件含 `install_mode_title`、`install_mode_required_msg`

### 场景验证（需手动）
1. **系统级检测**：root 装系统级后，普通用户运行 `clashtool.sh status` 应显示已安装信息（非"未安装"）；TUI 不被门禁拦截。
2. **命令行参数**：`clashtool.sh install --user` 走用户级不提示；`install --root`（非root）触发提权并装系统级；`install`（无参）报错提示。
3. **TUI 选级别**：TUI 安装菜单选"完整安装"→弹出级别菜单→选用户级/系统级→执行对应安装，全程 TUI 无 read。
4. **管道安装**：`curl ... | sh` 仍用 read 选级别（从 /dev/tty）。
5. **提权链路**：`install --root`（非root）→ sudo 重启 → main 解析 --root → 系统级安装。

## 执行顺序

1. 改动 6（i18n 变量）
2. 改动 1（初始化路径切换）
3. 改动 2（main 参数解析）
4. 改动 3（prompt_install_mode 改造）
5. 改动 4（_dispatch_group install 分支重构）
6. 改动 5（_tui_pick_mode_flag + install_menu 接入）
7. 验证
