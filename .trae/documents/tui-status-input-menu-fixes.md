# TUI 状态限制 / 输入滚动 / 表格颜色 / 安装菜单优化

## Context（背景）

当前 TUI 存在 4 类问题：
1. **无状态门禁**：TUI 菜单模式下，未安装时用户仍可进入服务控制/代理选择等菜单（命令行模式 `_dispatch_group` L6900 已有安装检查，但 TUI 菜单没有）
2. **输入溢出**：`tui_input`（L830）逐字符输出无宽度限制，输入超长时光标超出终端边缘无法显示；`tui_form` 值过长时超出表格边框
3. **表格颜色不一致**：`_tf_draw_form` 底部边框（L1044）缺少 `${COLOR_CYAN}`，渲染为白色；各组件边框 `COLOR_BOLD` 使用不统一
4. **安装菜单标签与行为不符**：option1 标"安装核心"但调用 `install`（实际是核心+UI）；缺少"完整安装"和"完全卸载(核心+UI)"的明确选项；`install_ui`/`update_ui`/`uninstall_ui` 命令不在 `_resolve_group` 中会被当作未知命令（现有 bug）

## 修改文件

- `clashtool.sh`（主文件）
- `i18n/en.sh`、`i18n/zh_CN.sh`（i18n 变量）

---

## 需求 1：状态限制（未安装/未运行门禁）

### 新增辅助函数（放在 `refresh_status` 之后，约 L214）

```sh
# 检查 Clash 是否已安装（未安装时提示并返回 1）
require_installed() {
    if [ ! -f "$clash_binary_path" ]; then
        tui_clear
        warn "$action_not_installed_msg" false
        pause_prompt
        return 1
    fi
    return 0
}

# 检查 Clash 是否正在运行（未运行时提示并返回 1）
require_running() {
    refresh_status
    if ! $clash_is_running; then
        tui_clear
        warn "$action_not_running_msg" false
        pause_prompt
        return 1
    fi
    return 0
}
```

### 新增 i18n 变量

- `action_not_installed_msg`：未安装提示
- `action_not_running_msg`：未运行提示

### 主菜单 `menu()` 门禁（L2262 case 分支）

| 选项 | 需要 installed | 需要 running | 说明 |
|------|---------------|-------------|------|
| 0 服务控制 | ✓ | — | 进入 service_menu 前检查 installed |
| 1 开机自启 | ✓ | — | 切换前检查 |
| 2 网关控制 | ✓ | — | 切换前检查 |
| 3 本机代理 | ✓ | — | 切换前检查 |
| 4 订阅配置 | ✓ | — | 进入 sub_config_menu 前检查 |
| 5 代理选择 | ✓ | ✓ | 需要 API 运行 |
| 6 安装 | — | — | 允许 |
| 7 工具维护 | ✓ | — | 进入 tools 前检查（子菜单内再按需检查 running） |
| 8 状态 | — | — | 允许（显示未安装/未运行状态） |
| 9 检查更新 | — | — | 允许（检查脚本更新，非 Clash） |

实现模式（每个需要检查的 case 分支开头）：
```sh
0) require_installed || continue; service_menu;;
```

### 子菜单门禁

**`service_menu()`（L1974）**：
- `0) start`：无 running 检查（start 本就是启动）
- `1) stop`：`require_running || continue`
- `2) restart`：无 running 检查（restart 可在未运行时启动）
- `3) reload`：`require_running || continue`

**`proxy_menu()`（L2048）**：
- 所有选项：`require_running || continue`（proxy_select_group/server 内部已有运行检查，但菜单层也拦截）

**`tools()`（L1591）**：
- `0) logs_menu`：`require_running || continue`
- `4) health_main`：`require_running || continue`
- `1-3) backup/rules/profiles`：无 running 检查

### 命令行模式 `_dispatch_group` 扩展（L6900）

当前已有安装检查。扩展 `need_install=false` 白名单保持不变。新增"需要运行"检查：
```sh
# 需要运行的操作
case "$_dg_group/$_dg_sub" in
    */stop|nodes/*|proxy/status|tools/logs|tools/health)
        # 这些需要 running
        ;;
esac
```
实际实现：在具体调用点（如 stop/nodes）前加 `refresh_status; $clash_is_running || { failed ...; return 1; }`。大部分操作函数内部已有运行检查（如 `proxy_select_group` L1622），只需补充 `stop` 等。

---

## 需求 2：输入过长水平滚动

### 新增辅助函数（放在 `str_display_width` 之后，约 L460）

```sh
# 取字符串末尾指定显示宽度的子串（ASCII 精确，多字节按字符数近似）
# $1=字符串, $2=最大显示宽度
str_tail_by_width() {
    _stw_str="$1"
    _stw_maxw="$2"
    _stw_len=${#_stw_str}
    if [ "$_stw_len" -le "$_stw_maxw" ]; then
        printf '%s' "$_stw_str"
        return 0
    fi
    _stw_offset=$((_stw_len - _stw_maxw + 1))
    printf '%s' "$_stw_str" | awk -v o="$_stw_offset" -v l="$_stw_maxw" '{print substr($0, o, l)}'
}
```

### `tui_input`（L830）修改

当前逐字符输出（L927 `printf '%s' "$_ti_ch"`）无宽度限制。改为**重绘模式**：

1. 进入输入循环前获取终端宽度：
   ```sh
   _ti_cols=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
   [ -z "$_ti_cols" ] && _ti_cols=80
   _ti_prefix_w=$(( $(str_display_width "$_ti_arrow") + 1 ))  # 箭头+空格
   _ti_avail=$((_ti_cols - _ti_prefix_w))
   [ "$_ti_avail" -lt 10 ] && _ti_avail=10  # 最小可用宽度
   ```

2. 新增内部重绘函数 `_ti_redraw`：
   ```sh
   # 回到行首，清除行，重绘前缀+可见文本
   _ti_visible=$(str_tail_by_width "$_ti_buf" "$_ti_avail")
   printf "\r\033[K${COLOR_CYAN}%s ${COLOR_RESET}%s" "$_ti_arrow" "$_ti_visible"
   ```

3. 字符输入（L925-928）：追加到 buf 后调用 `_ti_redraw`（而非逐字符输出）
4. 退格（L916-921）：从 buf 删除末尾字符后调用 `_ti_redraw`（而非 `\b \b`）

### `tui_form` / `_tf_draw_form`（L948）修改

`_tf_draw_form` 已是重绘模式，只需在显示值时截取：

1. 计算值可用宽度（L991 附近）：
   ```sh
   _tfd_val_avail=$(( MENU_CONTENT_WIDTH - _tfd_prefix_w - _tfd_pw - 1 ))
   [ "$_tfd_val_avail" -lt 5 ] && _tfd_val_avail=5
   ```

2. 值显示宽度 > 可用宽度时截取：
   ```sh
   if [ "$_tfd_vw" -gt "$_tfd_val_avail" ]; then
       _tfd_display_value=$(str_tail_by_width "$_tfd_value" "$_tfd_val_avail")
       _tfd_display_w="$_tfd_val_avail"
   else
       _tfd_display_value="$_tfd_value"
       _tfd_display_w="$_tfd_vw"
   fi
   ```

3. 用 `_tfd_display_value` 替代原始 `_tfd_value` 在渲染中输出
4. 光标列计算（L1052）改用 `_tfd_display_w` 替代 `_tfd_active_vw`

---

## 需求 3：表头表尾颜色统一

### `_tf_draw_form` 底部边框修复（L1044）

**根因**：L1041 `${COLOR_RESET}` 清除了青色，L1044 `MENU_BORDER_BOT` 无颜色设置 → 白色

**修复**：
```sh
    # === 底部边框 ===
    printf "%b" "${COLOR_CYAN}"
    printf "%s\033[K\n" "$MENU_BORDER_BOT"
    printf "%b" "${COLOR_RESET}"
```

### 统一所有表格组件边框风格

统一规则：**顶部边框** `COLOR_CYAN + COLOR_BOLD`，**底部边框** `COLOR_CYAN`（与 `tui_draw_menu` 一致）

| 函数 | 顶部边框行 | 底部边框行 | 修改 |
|------|-----------|-----------|------|
| `tui_draw_menu` L487-488 | `${COLOR_CYAN}${COLOR_BOLD}` → TOP | `${COLOR_CYAN}` → BOT | ✓ 已正确 |
| `_tf_draw_form` L966-967 | `${COLOR_CYAN}${COLOR_BOLD}` → TOP | **添加 `${COLOR_CYAN}`** → BOT | 修复底部 |
| `tui_input` L843 | `${COLOR_CYAN}...TOP...` | `${COLOR_CYAN}...BOT...` | 添加 `COLOR_BOLD` 到顶部 |
| `tui_confirm` L802 | `${COLOR_CYAN}...TOP...` | `${COLOR_CYAN}...BOT...` | 添加 `COLOR_BOLD` 到顶部 |
| `tui_message` L1216 | `${COLOR_CYAN}...TOP...` | `${COLOR_CYAN}...BOT...` | 添加 `COLOR_BOLD` 到顶部 |

---

## 需求 4：安装菜单重新设计（11 选项）

### 新 i18n 变量（en.sh + zh_CN.sh）

```
menu_install_option1=" [1] 完整安装       - 核心+默认UI"
menu_install_option2=" [2] 安装核心       - 仅Clash核心"
menu_install_option3=" [3] 更新核心       - 更新到新版本"
menu_install_option4=" [4] 安装/切换 yacd"
menu_install_option5=" [5] 安装/切换 dashboard"
menu_install_option6=" [6] 安装/切换 zashboard"
menu_install_option7=" [7] 更新当前UI"
menu_install_option8=" [8] 卸载核心       - 仅Clash核心"
menu_install_option9=" [9] 卸载UI"
menu_install_option10=" [a] 完全卸载      - 核心+UI"
menu_install_option11=" [b] 完全卸载含配置 - 核心+UI+配置"
```

### `install_menu()`（L2000）重写

```sh
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
            0) "$SCRIPT_PATH" install; pause_prompt;;                        # 完整安装
            1) # 安装核心（输入版本号）
                get_input "$prompt_version_msg"
                [ "$GET_INPUT_CANCELED" = "true" ] && continue
                [ -z "$GET_INPUT_RESULT" ] && { warn ...; pause_prompt; continue; }
                "$SCRIPT_PATH" install core "$GET_INPUT_RESULT"; pause_prompt;;
            2) # 更新核心（输入版本号）
                get_input "$prompt_version_msg"
                ...同上...
                "$SCRIPT_PATH" update core "$GET_INPUT_RESULT"; pause_prompt;;
            3|4|5) # 安装/切换 UI
                _ui="yacd"; [ "$MENU_RESULT" = "4" ] && _ui="dashboard"; [ "$MENU_RESULT" = "5" ] && _ui="zashboard"
                if [ -d "$ui_install_dir" ]; then
                    "$SCRIPT_PATH" update ui "$_ui"
                else
                    "$SCRIPT_PATH" install ui "$_ui"
                fi
                pause_prompt;;
            6) "$SCRIPT_PATH" update ui; pause_prompt;;                       # 更新当前UI
            7) "$SCRIPT_PATH" uninstall core; pause_prompt;;                  # 卸载核心
            8) "$SCRIPT_PATH" uninstall ui; pause_prompt;;                    # 卸载UI
            9) "$SCRIPT_PATH" uninstall; pause_prompt;;                       # 完全卸载(核心+UI)
            10) "$SCRIPT_PATH" uninstall all; pause_prompt;;                  # 完全卸载含配置
            BACK) break;;
            QUIT) exit 0;;
            INVALID|*) ...;;
        esac
    done
}
```

### 关键修正

1. **命令格式统一为分组命令**：`install ui`/`update ui`/`uninstall ui`（而非 `install_ui`/`update_ui`/`uninstall_ui`），因为后者不在 `_resolve_group` 中会被当作未知命令
2. **标签与行为一致**：option1 "完整安装" 调用 `install`（核心+UI），option2 "安装核心" 调用 `install core`
3. **完全卸载分离**：option10 `uninstall`（核心+UI，保留配置），option11 `uninstall all`（核心+UI+配置）

---

## 验证方法

### 语法检查
```sh
/bin/sh -n clashtool.sh && echo "sh OK"
/bin/dash -n clashtool.sh && echo "dash OK"
bash -n clashtool.sh && echo "bash OK"
/bin/sh -n i18n/en.sh && /bin/sh -n i18n/zh_CN.sh && echo "i18n OK"
```

### 功能验证
```sh
# help 和 status 不受影响
/bin/sh clashtool.sh help | head -5
/bin/sh clashtool.sh status | head -3

# i18n 变量一致性（en.sh 和 zh_CN.sh 变量集相同）
diff <(grep -oP '^\w+' i18n/en.sh | sort) <(grep -oP '^\w+' i18n/zh_CN.sh | sort)
```

### TUI 交互验证（需手动）
1. **状态门禁**：卸载 Clash 后运行 TUI，选择"服务控制"应提示未安装；选择"安装"可正常进入
2. **输入滚动**：TUI 中添加订阅，输入超长 URL（>80字符），应水平滚动显示末尾内容，不破坏表格边框
3. **表格颜色**：表单底部边框应为青色（非白色）；各级菜单/表单/输入框/消息框边框风格统一
4. **安装菜单**：11 个选项正确显示，"完整安装"执行核心+UI，"完全卸载"执行核心+UI（保留配置），"完全卸载含配置"删除全部

### 视觉验证
用 `od -c` 确认 `_tf_draw_form` 底部边框输出包含 ESC[36m（青色）序列
