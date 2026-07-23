# 改动 5：新增 _tui_pick_mode_flag + install_menu 接入安装级别选择

## Context（背景）

本次任务三项目标的实施进度（基于已批准的 `install-detection-tui-mode-params.md` 计划）：

- ✅ 改动 6：i18n 变量（`install_mode_title`/`install_mode_required_msg`/`install_mode_user_msg`/`install_mode_root_msg`）已落地于 `i18n/en.sh` L540-546 与 `i18n/zh_CN.sh` L532-538
- ✅ 改动 1：普通用户初始化路径切换（检测系统级 `/opt/clash`）已落地
- ✅ 改动 2：main 解析 `--user`/`--root` 标志（L7311-7318）已落地
- ✅ 改动 3：`prompt_install_mode` 三级分发（CLI 参数 → 管道 read → 报错 ret=2）已落地（L4154-4182）
- ✅ 改动 4：`_dispatch_group` install 分支重构（ret=2 处理 + `_cli_mode_flag` 透传）已落地（L7081-7145）
- ⏳ **改动 5（本计划）**：新增 `_tui_pick_mode_flag` 函数 + `install_menu` 接入
- ⬜ 验证

### 为什么需要改动 5

TUI 模式下 `install_menu` 的安装类选项（0/1/3/4/5 未安装分支）目前直接调用 `"$SCRIPT_PATH" install ...` 启动子进程，但**不携带级别标志**。子进程进入 `_dispatch_group` install 分支后调用 `prompt_install_mode`：

- 子进程的 `_cli_install_mode` 为空（未传 `--user`/`--root`）
- 子进程非管道安装（`_is_piped_install=false`）
- 因此落入分支 3：`failed "$install_mode_required_msg" false; return 2` → 子进程 exit 1

结果：**TUI 模式下用户无法完成安装**。必须在 TUI 菜单层先用 TUI 选择安装级别，再把级别标志透传给子进程，满足"所有选择都需要 TUI 选择"的需求。

`update`/`uninstall` 类操作基于已检测的 `install_dir` 路径（改动 1 已确保普通用户能检测到系统级安装），无需重新选级别。

## 修改文件

- `clashtool.sh`（主文件）

---

## 修改 1：新增 `_tui_pick_mode_flag` 函数

### 位置

`clashtool.sh` L4183（`prompt_install_mode` 函数结束 `}` 之后，`set_install_paths` 注释 L4184 之前）。

### 实现

```sh
# TUI 模式下选择安装级别（用户级/系统级）
# 返回：0=已选择（_TUI_MODE_FLAG 已设置），1=用户取消
# 设置全局变量：_TUI_MODE_FLAG（--user 或 --root）
_tui_pick_mode_flag() {
    # 确定用户级安装的目标路径（root+sudo 用 SUDO_USER 的家目录）
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

### 设计要点

1. **路径提示与 `prompt_install_mode` 管道分支一致**：复用 `install_mode_user_msg`/`install_mode_root_msg` 两个 i18n 变量（已含 `%s` 占位符），显示真实安装路径让用户知情决策。
2. **家目录推断与 `set_install_paths` 一致**：root+sudo 场景下用 `SUDO_USER` 的家目录，避免误把 `/root` 当作用户级目标。
3. **`menu_dispatch` 返回值语义**：`MENU_RESULT=0`→第一个选项（用户级），`=1`→第二个选项（系统级），其他（BACK/QUIT/INVALID）→取消返回 1。
4. **取消语义**：返回 1 后调用方 `continue` 回到 install_menu，符合 TUI"返回上级"交互习惯。

---

## 修改 2：`install_menu` 接入级别选择

### 位置

`clashtool.sh` L2082-2136（`install_menu` 函数）。

### 选项 0（完整安装，L2097-2099）

```sh
0)  # 完整安装 - 核心+默认UI（一键最新版）
    _tui_pick_mode_flag || continue
    "$SCRIPT_PATH" install $_TUI_MODE_FLAG; pause_prompt
    ;;
```

### 选项 1（安装核心，L2100-2104）

调整为**先选级别后输版本号**：若用户在输版本号时取消，重试时级别也重选（成本对称；反之先输版本号再选级别取消会导致版本号白输）。

```sh
1)  # 安装核心（可指定版本，空=最新）
    _tui_pick_mode_flag || continue
    get_input "$prompt_version_msg"
    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
    "$SCRIPT_PATH" install core "$GET_INPUT_RESULT" $_TUI_MODE_FLAG; pause_prompt
    ;;
```

### 选项 3|4|5（安装/切换 UI，L2110-2120）

仅在**未安装**分支（`install ui`）前选级别；已安装分支（`update ui`）基于现有路径更新，无需选级别。

```sh
3|4|5)  # 安装/切换 UI（yacd/dashboard/zashboard）
    _ui="yacd"
    [ "$MENU_RESULT" = "4" ] && _ui="dashboard"
    [ "$MENU_RESULT" = "5" ] && _ui="zashboard"
    if is_ui_installed; then
        "$SCRIPT_PATH" update ui "$_ui"
    else
        _tui_pick_mode_flag || continue
        "$SCRIPT_PATH" install ui "$_ui" $_TUI_MODE_FLAG
    fi
    pause_prompt
    ;;
```

### 不修改的选项

| 选项 | 操作 | 不修改原因 |
|------|------|-----------|
| 2 | `update core` | 操作已安装路径，无需选级别 |
| 6 | `update ui` | 操作已安装路径，无需选级别 |
| 7 | `uninstall core` | 基于 `install_dir`（改动 1 已能检测系统级） |
| 8 | `uninstall ui` | 同上 |
| 9 | `uninstall` | 同上 |
| 10 | `uninstall all` | 同上 |

### 设计要点

1. **`$_TUI_MODE_FLAG` 作为末尾参数透传**：与改动 2（main 参数解析）约定的"标志作末尾参数"一致。`main` 的 case 分支同时检查 `$2`/`$3`/`$4` 位置，覆盖了：
   - 选项 0：`install --user`（标志在 $2）
   - 选项 1：`install core <ver> --user`（标志在 $4）
   - 选项 3/4/5：`install ui <ui> --user`（标志在 $4）
2. **`_tui_pick_mode_flag || continue` 守卫**：取消时回到 install_menu，不执行安装。
3. **`$_TUI_MODE_FLAG` 不加引号**：变量为空时不应产生空参数（`"$SCRIPT_PATH" install ""` 会把空串当 $2），故故意不加引号，让 shell 分词后消失。`_tui_pick_mode_flag` 成功返回时该变量必为 `--user` 或 `--root`（无空格），分词安全。

---

## Assumptions & Decisions

1. **`update`/`uninstall` 不选级别**：这些操作作用于已检测的 `install_dir`，改动 1 已确保普通用户能检测到系统级安装并通过 `check_and_elevate` 提权。无需在 TUI 层重新选级别。
2. **选项 1 顺序调整**：先选级别后输版本号，避免版本号白输。这与原"先输版本号"顺序不同，但体验更优，且不破坏功能。
3. **`_TUI_MODE_FLAG` 不加引号**：依赖 shell 分词让空值消失。变量值受控（仅 `--user`/`--root`），无注入风险。
4. **`menu_dispatch` 在子进程外的可用性**：`install_menu` 运行在父进程（TUI 模式，已通过 `_is_interactive_terminal` 检查），`menu_dispatch` 可正常渲染。

---

## 验证步骤

### 1. 语法检查（权威：sh/dash；bash -n 会有 `event not found` 噪音，运行时 `set +H` 已屏蔽）

```sh
/bin/sh -n /home/peng/Documents/trae_projects/clash-for-linux/clashtool.sh && echo "sh OK"
/bin/dash -n /home/peng/Documents/trae_projects/clash-for-linux/clashtool.sh && echo "dash OK"
bash -n /home/peng/Documents/trae_projects/clash-for-linux/clashtool.sh 2>&1 | grep -v "event not found" && echo "bash OK"
```

### 2. 静态 grep 确认

```sh
# _tui_pick_mode_flag 定义一次、调用三次
grep -c "_tui_pick_mode_flag" clashtool.sh  # 期望 4（1 定义 + 3 调用）
# _TUI_MODE_FLAG 在 install_menu 使用
grep -n "_TUI_MODE_FLAG" clashtool.sh
# 选项 0/1/3|4|5 均带 $_TUI_MODE_FLAG
grep -n 'install.*\$_TUI_MODE_FLAG\|install core.*\$_TUI_MODE_FLAG\|install ui.*\$_TUI_MODE_FLAG' clashtool.sh
```

### 3. 功能验证（手动 TUI 交互）

- TUI 主菜单 → [6] 安装 → [0] 完整安装 → 弹出"选择安装级别"菜单 → 选用户级 → 子进程以 `--user` 启动安装
- 同上选系统级 → 子进程以 `--root` 启动，普通用户触发 `check_and_elevate` 提权
- 安装级别菜单按 Esc → 返回 install_menu（不启动子进程）
- [1] 安装核心 → 先选级别 → 再输版本号 → 子进程带 `--user`/`--root` + 版本号启动
- [3/4/5] UI 未安装时 → 选级别 → `install ui <ui> --user/root`
- [3/4/5] UI 已安装时 → 直接 `update ui <ui>`（不选级别）
- [2/6/7-10] update/uninstall → 不选级别，直接执行

### 4. 命令行模式回归

```sh
# 带级别参数：直接执行，不进入 TUI 选级别
./clashtool.sh install --user
./clashtool.sh install core v1.2.4 --root
./clashtool.sh install ui dashboard --user
# 不带级别参数：报错（prompt_install_mode 分支 3）
./clashtool.sh install  # 期望：install_mode_required_msg 提示
```
