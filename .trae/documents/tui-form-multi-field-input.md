# TUI 多字段表单（tui_form）实现计划

## Context

当前 TUI 添加订阅时，用户需要逐个输入字段（名称 → URL），每输入一个就清屏进入下一步。用户希望将无强关联的输入项（订阅名称、地址、自动更新时间）显示在同一界面，一次填写完成后提交，无需逐个进入下一步。

现有 TUI 模式的添加订阅只传 `name::url`（无 interval），而命令行模式支持 `name::url::interval`。本次同时补齐 interval 字段。

## 实现方案

### 1. 新增 `_tf_draw_form()` 内部绘制函数

**位置**: clashtool.sh L898（`tui_input` 之后、`tui_message` 之前）

渲染逻辑（与 `tui_draw_menu` 风格一致）：
- `\033[H` 定位 + `\033[K` 清行 + `\033[J` 清底部，避免闪烁
- 布局：顶边框 → 标题(居中) → 分隔线 → 字段行(N行) → 分隔线 → 状态行(错误/提示) → 底边框
- 活动字段：`tui_get_arrow()` 标记 + `COLOR_BOLD + COLOR_WHITE` 高亮
- 非活动字段：空格前缀 + `COLOR_DIM` 暗色
- 绘制末尾用 ANSI 定位光标到活动字段值末尾，并 `\033[?25h` 显示光标

光标定位公式（1-indexed）：
- 行 = `4 + _tf_current`（顶边框1 + 标题1 + 分隔线1 + 字段偏移）
- 列 = `5 + prompt_width + value_width`（║1 + prefix2 + prompt + 空格1 + value）
- 超出右边界时钳制到 `MENU_RIGHT_COL - 1`

### 2. 新增 `tui_form()` 主函数

**位置**: 紧接 `_tf_draw_form` 之后

**参数**: `$1`=标题, `$2..$N`=字段定义 `"提示::默认值::允许空"` 或 `"提示::允许空"`

**字段定义解析**: 用 `awk -F'::'` 按 NF 区分 2 段/3 段格式，eval 存储到 `_tf_prompt_N`、`_tf_value_N`、`_tf_allow_empty_N`

**终端设置**: `stty -echo -icanon onlcr min 1 time 0`（与 `tui_menu_select` 一致，不需 `-icrnl`，因 `tui_read_key` 用 `od` 读取原始字节）

**主循环**: 绘制 → `tui_read_key` → 按键分发：
- `TAB`/`DOWN`: 下一字段（循环到第一个）
- `UP`: 上一字段（循环到最后一个）
- `ENTER`: 验证必填字段，全通过则提交；否则设 `_tf_error` 并跳转到第一个空必填字段
- `ESC`/`CTRL_C`: 取消
- `BACKSPACE`: `sed 's/.$//'` 删除当前字段末尾字节
- `''`: 忽略（未知转义序列）
- `*)`: `${#TUI_KEY} -eq 1` 过滤命名键 + `printf '%d' "'$TUI_KEY"` 过滤控制字符，可打印字符追加到当前字段

**eval 安全**: `eval "_tf_value_N=\$_tf_new"` 模式——赋值语句右侧变量只展开一次，值中的 `$()` / `` ` `` 不会被二次执行

**输出全局变量**: `FORM_CANCELED`, `FORM_FIELD_COUNT`, `FORM_FIELD_0..N-1`

**清理**: 返回前 `unset` 所有 `_tf_prompt_N`、`_tf_value_N`、`_tf_allow_empty_N`，恢复 stty 和光标

### 3. 新增 `get_form()` 包装器

**位置**: clashtool.sh L1044（`get_input` 之后）

**交互模式**: 调用 `tui_form`，复制结果到 `GET_FORM_*` 变量
**非交互模式**: 逐行 `read -r`，与 `get_input` 逻辑一致

**输出**: `GET_FORM_CANCELED`, `GET_FORM_FIELD_COUNT`, `GET_FORM_FIELD_0..N-1`

### 4. 修改添加订阅流程

**两处修改**（L1737 `subscription` case 0、L1806 `sub_config_menu` case 0）：

替换原有的两个 `get_input` 调用为单个 `get_form` 调用：
```sh
get_form "$form_add_sub_title" \
    "${prompt_subscription_name_msg}::false" \
    "${prompt_subscription_url_msg}::false" \
    "${prompt_subscription_update_msg}::0::true"
if [ "$GET_FORM_CANCELED" = "true" ]; then continue; fi
eval "_var=\"\$GET_FORM_FIELD_0\""
eval "_sub_url=\"\$GET_FORM_FIELD_1\""
eval "_interval=\"\$GET_FORM_FIELD_2\""
if [ -z "$_var" ] || [ -z "$_sub_url" ]; then
    warn "$validate_name_msg" false; pause_prompt; continue
fi
[ -z "$_interval" ] && _interval="0"
add "${_var}::${_sub_url}::${_interval}"
```

### 5. 新增 i18n 变量（3个）

| 变量名 | 英文 | 中文 |
|---|---|---|
| `form_add_sub_title` | ` Add Subscription ` | ` 添加订阅 ` |
| `tui_form_nav_hint` | `[Tab/Down] Next  [Up] Prev  [Enter] Submit  [Esc] Cancel` | `[Tab/↓] 下一项  [↑] 上一项  [Enter] 提交  [Esc] 取消` |
| `tui_form_field_required_msg` | `%s cannot be empty` | `%s 不能为空` |

**插入位置**:
- clashtool.sh L324 后（TUI 提示区）: `tui_form_nav_hint`, `tui_form_field_required_msg`
- clashtool.sh L2003 后（订阅提示区）: `form_add_sub_title`
- i18n/en.sh L181 后: 全部 3 个
- i18n/zh_CN.sh L183 后: 全部 3 个

## 修改文件

1. **clashtool.sh** — 新增 `_tf_draw_form`、`tui_form`、`get_form` 函数；修改 L1737 和 L1806 添加订阅流程；L324 和 L2003 后新增 i18n 默认值
2. **i18n/en.sh** — L181 后新增 3 个变量
3. **i18n/zh_CN.sh** — L183 后新增 3 个变量

## 验证

1. `sh -n clashtool.sh` 语法检查
2. `sh -n i18n/en.sh` 和 `sh -n i18n/zh_CN.sh` 语法检查
3. `bash clashtool.sh help` 确认脚本正常启动
4. `bash clashtool.sh subscribe add test::http://example.com::24` 确认命令行模式仍正常
5. 验证 i18n 变量集一致: `diff <(grep -oP '^\w+' i18n/en.sh | sort) <(grep -oP '^\w+' i18n/zh_CN.sh | sort)`
6. 交互测试需在真实终端进行：进入 TUI → 订阅管理 → 添加订阅 → 确认三字段同屏显示、Tab/Up/Down 切换、Enter 提交、Esc 取消
