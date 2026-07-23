# TUI 状态门禁 + 安装菜单重写（剩余任务）

## Context（背景）

本计划承接已批准的 `tui-status-input-menu-fixes.md`。前序任务 1-5 已完成并落盘（已通过 grep 验证）：
- ✅ i18n 变量（`tui_status_*`、`action_not_*_msg`、`tui_menu_nav_hint`）已在 `clashtool.sh` L357-362、`i18n/en.sh` L118-123、`i18n/zh_CN.sh` L120-125
- ✅ 辅助函数 `require_installed`(L217)、`require_running`(L229)、`str_tail_by_width`(L499)
- ✅ 表格颜色统一（`_tf_draw_form` 底部边框、`tui_confirm`/`tui_input`/`tui_message` 顶部 `COLOR_BOLD`）
- ✅ `tui_input` 水平滚动（L924-985）
- ✅ `_tf_draw_form` 值截取（L1048-1083）
- ✅ i18n 安装菜单 11 选项标签（`menu_install_option1-11`）已在 en.sh L31-41、zh_CN.sh L33-43

**剩余 3 项任务**：① TUI 各级菜单状态门禁；② `install_menu` 重写为 11 选项 + 修正命令格式；③ 语法检查与功能验证。

## 修改文件

- `clashtool.sh`（唯一修改文件，i18n 已就绪无需改动）

---

## 任务 6：TUI 菜单状态门禁

### 设计原则

- **未安装门禁**：在主菜单入口处拦截（`require_installed`），覆盖所有"安装后"功能入口。`install_menu`(选项6)、`status`(选项8)、`update_check`(选项9) 不拦截。
- **未运行门禁**：在子菜单内对"依赖运行实例"的具体操作拦截（`require_running`）；`proxy_menu` 因全部选项都依赖运行，在主菜单入口(选项5)一次性拦截。
- `require_installed`/`require_running` 失败时已自带 `tui_clear + warn + pause_prompt`，搭配 `|| continue` 返回当前菜单循环重绘。

### 改动 6-A：主菜单 `menu()` case 分支（L2330-2346）

当前代码：
```sh
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
```

修改为（选项 0,1,2,3,4,7 加 `require_installed`；选项 5 加 `require_installed`+`require_running`）：
```sh
case "$MENU_RESULT" in
    0) require_installed || continue; service_menu;;
    1) require_installed || continue; tui_clear; if is_auto_start; then auto_start false; else auto_start true; fi; pause_prompt;;
    2) 
        require_installed || continue
        if is_root; then
            tui_clear; if is_gateway; then gateway false; else gateway true; fi; pause_prompt
        else
            tui_clear; permission_denied_msg "gateway"; printf "\n"; pause_prompt
        fi
        ;;
    3) require_installed || continue; tui_clear; if is_proxy; then proxy_off; else proxy_on; fi; pause_prompt;;
    4) require_installed || continue; sub_config_menu;;
    5) require_installed || continue; require_running || continue; proxy_menu;;
    6) install_menu;;
    7) require_installed || continue; tools;;
    8) tui_clear; status; pause_prompt;;
    9) update_check; pause_prompt;;
    QUIT) break;;
```

### 改动 6-B：`service_menu()` case 分支（L2049-2059）

`start`(0) 与 `restart`(2) 不需要 running（可在未运行时启动）；`stop`(1) 与 `reload`(3) 需要 running。

当前：
```sh
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
```

修改为：
```sh
case "$MENU_RESULT" in
    0) tui_clear; start; pause_prompt;;
    1) require_running || continue; tui_clear; stop; pause_prompt;;
    2) tui_clear; restart; pause_prompt;;
    3)
        require_running || continue
        tui_clear
        if select_subscription; then
            reload "$SELECTED_SUB"
        fi
        pause_prompt
        ;;
```

### 改动 6-C：`tools()` case 分支（L1667-1672）

`logs_menu`(0) 与 `health_main`(4) 依赖运行实例；`backup_main`(1)/`rules_main`(2)/`profiles_main`(3) 操作配置文件，不需 running。

当前：
```sh
case "$MENU_RESULT" in
    0) logs_menu;;
    1) backup_main;;
    2) rules_main;;
    3) profiles_main;;
    4) health_main;;
```

修改为：
```sh
case "$MENU_RESULT" in
    0) require_running || continue; logs_menu;;
    1) backup_main;;
    2) rules_main;;
    3) profiles_main;;
    4) require_running || continue; health_main;;
```

### 改动 6-D：`proxy_menu()` 无需内部改动

`proxy_menu` 全部选项依赖运行，已在主菜单选项 5 入口处 `require_running` 一次性拦截。`proxy_select_group`(L1688) 内部亦已有运行检查（防御性，保留不动）。

### 不改动的菜单

- `sub_config_menu()`(L2204)：操作订阅/配置文件，不需 running；入口已 `require_installed`（主菜单选项4）。
- `logs_menu()`/`health_main()`：入口已在 `tools()` 拦截 `require_running`，无需内部重复。
- `subscription()`(L2136)：经 grep 确认为**死代码**（无任何调用点，与 `sub_config_menu` 重复），不在本次范围，保持不动。
- `install_menu()`：安装/卸载菜单，安装类选项允许未安装执行；更新类由 `_dispatch_group` 的 `_dg_need_install` 白名单拦截；卸载类由各函数内部 `is_*_installed` 检查兜底。无需 TUI 层门禁。

---

## 任务 7：`install_menu()` 重写为 11 选项

### 当前问题（L2068-2113）

1. 仅 dispatch 9 个选项（`menu_install_option1-9`），但 i18n 已定义 11 个标签 → 选项 10/11 不可达。
2. 使用旧直调命令 `install_ui`/`update_ui`/`uninstall_ui`（L2100/2102/2106/2107），这些**不在** `_resolve_group` 白名单（L6320 仅作参数校验用），通过 `"$SCRIPT_PATH" install_ui` 调用会被当作未知命令。
3. 旧 option1 标"安装核心"却调用 `install`（实为核心+UI），标签与行为不符。

### 命令映射（基于 `_dispatch_group` 实测，L6947-7190）

| 新选项(索引) | 标签 | 分组命令 | dispatch 行为 |
|---|---|---|---|
| 0 | 完整安装-核心+默认UI | `install` | `prompt_install_mode` + install core + install_ui |
| 1 | 安装核心 | `install core <ver>` | 仅 install |
| 2 | 更新核心 | `update core <ver>` | 仅 update（需已安装） |
| 3 | 安装/切换 yacd | `install ui yacd` 或 `update ui yacd` | 见下 |
| 4 | 安装/切换 dashboard | `install ui dashboard` 或 `update ui dashboard` | 见下 |
| 5 | 安装/切换 zashboard | `install ui zashboard` 或 `update ui zashboard` | 见下 |
| 6 | 更新当前UI | `update ui` | update_ui("")→用配置中 ui 名 |
| 7 | 卸载核心 | `uninstall core` | 仅 uninstall("") |
| 8 | 卸载UI | `uninstall ui` | uninstall_ui("") |
| 9 | 完全卸载-核心+UI | `uninstall` | uninstall + uninstall_ui（保留配置） |
| 10 | 完全卸载含配置 | `uninstall all` | clear "all" 删整个 install_dir |

**UI 切换逻辑**：`install_ui`(L4322) 在已安装时报错退出，故"安装/切换"需判断：已安装→`update ui <name>`（先删后装，实现切换）；未安装→`install ui <name>`。沿用原 L2099 判断 `is_ui_installed` 的逻辑，但改用分组命令。

### 重写后的 `install_menu()`（替换 L2068-2113）

```sh
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
                "$menu_install_option10" \
                "$menu_install_option11"
            case "$MENU_RESULT" in
                0)  # 完整安装 - 核心+默认UI（一键最新版）
                    "$SCRIPT_PATH" install; pause_prompt
                    ;;
                1)  # 安装核心（可指定版本，空=最新）
                    get_input "$prompt_version_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    "$SCRIPT_PATH" install core "$GET_INPUT_RESULT"; pause_prompt
                    ;;
                2)  # 更新核心（可指定版本，空=最新）
                    get_input "$prompt_version_msg"
                    if [ "$GET_INPUT_CANCELED" = "true" ]; then continue; fi
                    "$SCRIPT_PATH" update core "$GET_INPUT_RESULT"; pause_prompt
                    ;;
                3|4|5)  # 安装/切换 UI（yacd/dashboard/zashboard）
                    _ui="yacd"
                    [ "$MENU_RESULT" = "4" ] && _ui="dashboard"
                    [ "$MENU_RESULT" = "5" ] && _ui="zashboard"
                    if is_ui_installed; then
                        "$SCRIPT_PATH" update ui "$_ui"
                    else
                        "$SCRIPT_PATH" install ui "$_ui"
                    fi
                    pause_prompt
                    ;;
                6)  # 更新当前UI
                    "$SCRIPT_PATH" update ui; pause_prompt;;
                7)  # 卸载核心
                    "$SCRIPT_PATH" uninstall core; pause_prompt;;
                8)  # 卸载UI
                    "$SCRIPT_PATH" uninstall ui; pause_prompt;;
                9)  # 完全卸载 - 核心+UI（保留配置）
                    "$SCRIPT_PATH" uninstall; pause_prompt;;
                10) # 完全卸载含配置 - 核心+UI+配置
                    "$SCRIPT_PATH" uninstall all; pause_prompt;;
                BACK) break;;
                QUIT) exit 0;;
                INVALID|*) printf "%b\n" "${COLOR_RED}${menu_invalid_choice}${COLOR_RESET}"; sleep 1;;
            esac
        done
    }
```

### 决策点（已定）

1. **option0 完整安装不提示版本号**：一键安装最新版，符合"完整安装"语义；版本指定由 option1/option2 承担。
2. **option1/option2 允许空版本号**：移除原 `[ -z "$GET_INPUT_RESULT" ] && warn...` 拒绝逻辑。理由：① 提示文案 `prompt_version_msg` 已写"默认最新版本"；② `download_github_release`(L3789) 已支持空参数（自动取最新）；③ 修复提示与行为矛盾的 bug。空输入 → `install core ""` → 最新版。
3. **UI 切换用分组命令**：`update ui <name>`/`install ui <name>` 替代旧 `update_ui`/`install_ui` 直调，避免被 `_resolve_group` 当未知命令。
4. **`_ui` 变量未 unset**：与原代码一致（原 L2096-2098 也未 unset），属局部一次性使用，影响可忽略。

---

## 任务 8：语法检查与功能验证

### 语法检查
```sh
/bin/sh -n clashtool.sh && echo "sh OK"
/bin/dash -n clashtool.sh && echo "dash OK"
bash -n clashtool.sh && echo "bash OK"
```

### 功能验证（非交互）
```sh
/bin/sh clashtool.sh help | head -5
/bin/sh clashtool.sh status | head -3
```

### 门禁逻辑验证（grep 静态确认）
- 确认 `require_installed` 出现在主菜单 0,1,2,3,4,7 分支
- 确认 `require_running` 出现在主菜单 5 分支、service_menu 1/3 分支、tools 0/4 分支
- 确认 `install_menu` dispatch 11 个选项、case 0-10 完整

### TUI 交互验证（需手动）
1. **未安装门禁**：卸载后进入 TUI，选"服务控制/订阅配置/工具维护"应提示"尚未安装"；选"安装"可进入；选"状态/更新"可执行。
2. **未运行门禁**：已安装未启动时，选"代理选择"应提示"未运行"；进入"服务控制"选"停止/重载"应提示"未运行"；选"启动/重启"可执行。
3. **安装菜单 11 选项**：选项 1-9 + a + b 全部显示；"完整安装"执行核心+UI；"完全卸载"保留配置，"完全卸载含配置"删 install_dir。
4. **版本号留空**：选"安装核心"直接回车，应安装最新版（不再报"不能为空"）。

---

## 假设与决策汇总

| 项 | 决策 |
|---|---|
| proxy_menu 拦截位置 | 主菜单入口一次性 `require_running`，不在子菜单内重复 |
| subscription() 死代码 | 不处理（超出本次范围） |
| install_menu 版本号 | option0 不提示；option1/2 提示但允许空（=最新），修复提示与行为矛盾 |
| UI 切换命令 | `update ui`/`install ui` 分组命令，按 `is_ui_installed` 分流 |
| install_menu 门禁 | 不加 TUI 层门禁，由 `_dispatch_group` 白名单 + 各函数内部检查兜底 |

## 执行顺序

1. 改动 6-A（主菜单门禁）
2. 改动 6-B（service_menu 门禁）
3. 改动 6-C（tools 门禁）
4. 任务 7（install_menu 重写）
5. 任务 8（语法检查 + 功能验证）
