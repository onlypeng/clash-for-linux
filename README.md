# clashtool.sh — Clash for Linux 管理工具

## 概述

`clashtool.sh` 是一个功能完备的 Clash for Linux 管理工具，以 POSIX shell 脚本实现，涵盖安装、配置、服务控制、代理管理、订阅管理、日志查看、备份恢复等全套功能。脚本同时提供 TUI 交互式菜单和 CLI 命令行两种操作方式，适配各种终端环境。

**核心特点**：

- **POSIX 兼容**：以 `#!/bin/sh` 编写，兼容 bash/dash
- **一键安装**：支持 `curl | sh` 管道安装模式，无需克隆仓库即可部署
- **双模式**：TUI 交互式菜单 + CLI 命令行，统一入口
- **模块化**：TUI 逻辑独立到 `clashtool_tui.sh`，多语言翻译独立到 `i18n/` 目录，主程序通过 source 加载
- **在线加载**：TUI 和 i18n 模块支持本地检测，本地缺失或管道安装时自动从 GitHub 在线加载
- **多语言**：i18n 目录架构支持任意语言扩展，自动检测系统语言（`LANG`），可通过 `language` 变量配置
- **分组命令**：9 大命令分组 + 5 个直接命令，语义清晰
- **权限自适应**：root 装到 `/opt/clash`，普通用户装到 `~/.local/clash`
- **五层代理**：Shell RC + 环境变量 + 系统级 + 桌面环境 + NetworkManager
- **9 种桌面环境**：GNOME / KDE Plasma 5&6 / XFCE / MATE / Cinnamon / Budgie / Deepin / LXQt / LXDE
- **3 种 Shell**：bash / zsh / fish 自动检测
- **幂等性**：所有状态切换函数先检查当前状态，避免重复操作
- **i18n**：多语言架构，英文为默认值，中文（`zh_CN.sh`）等语言作为独立模块

---

## 在线安装

### 一键在线安装（推荐）

**管道安装模式**：无需克隆仓库，一行命令直接安装。脚本会自动从 GitHub 下载主脚本、TUI 模块、i18n 语言文件，并完成核心、yq、GeoIP 数据库和 Web UI 的部署：

```bash
# 系统级安装（root，装到 /opt/clash）
curl -fsSL https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh | sudo sh

# 或用户级安装（普通用户，装到 ~/.local/clash）
curl -fsSL https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh | sh
```

> **管道模式说明**：
> - 无参数时自动触发安装流程
> - 主脚本、TUI 模块、i18n 文件均从 GitHub 在线下载到安装目录
> - 若需要 root 权限，请使用 `sudo sh`（脚本会提示重新执行命令）
> - 安装完成后通过 `clashtool` 命令使用，无需 clone 整个仓库

### 克隆仓库安装

将本项目克隆或下载到本地后执行安装命令：

```bash
# 下载项目
git clone https://github.com/onlypeng/clash-for-linux.git
cd clash-for-linux

# 系统级安装（root，装到 /opt/clash）
sudo sh clashtool.sh install

# 或用户级安装（普通用户，装到 ~/.local/clash）
sh clashtool.sh install
```

安装完成后，`clashtool` 命令会被软链接到 PATH（root 装到 `/usr/local/bin/clashtool`，用户装到 `~/.local/bin/clashtool`），可在任意目录直接使用。

### 在线更新已有安装

```bash
# 更新 clashtool 脚本本身（从 GitHub 拉取最新版）
clashtool update script

# 更新 Clash 核心 + Web UI
clashtool update

# 仅更新核心
clashtool update core
```

### 仅下载脚本（不克隆仓库）

如果只需要脚本本身（手动管理依赖文件），可以直接下载：

```bash
curl -O https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh
curl -O https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool_tui.sh
mkdir -p i18n
curl -o i18n/zh_CN.sh https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/i18n/zh_CN.sh
curl -o i18n/en.sh https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/i18n/en.sh
chmod +x clashtool.sh
sudo sh clashtool.sh install
```

> **提示**：如需更简单的方式，直接使用上方的「管道安装模式」一行命令即可，脚本会自动下载所有依赖文件。
>
> **注意**：`clashtool_tui.sh` 和 `i18n/` 目录必须与 `clashtool.sh` 放在同一目录。
> - `clashtool_tui.sh` 提供 TUI 菜单功能（交互导航、按键处理）
> - `i18n/` 目录包含多语言模块（`zh_CN.sh` 中文、`en.sh` 英文等）
>
> 若本地缺失这些模块，脚本会自动从 GitHub 在线加载（需网络）；管道安装模式下则全部在线下载到安装目录。

---

## 快速开始

### 基本操作

```bash
# 启动 / 停止 / 重启 / 热重载（直接命令，无需分组）
clashtool start
clashtool stop
clashtool restart
clashtool reload

# 查看状态
clashtool status

# 交互式菜单（无参数直接运行）
clashtool

# 帮助
clashtool help
```

### 代理开关

```bash
# 开启 / 关闭系统代理（需 source 以影响当前 shell）
source clashtool proxy on
source clashtool proxy off

# 查看代理状态
clashtool proxy
```

### 订阅管理

```bash
# 添加订阅
clashtool subscribe add mysub::https://example.com/sub.yaml::24

# 列出 / 更新 / 删除
clashtool subscribe list
clashtool subscribe update mysub
clashtool subscribe del mysub
```

---

## 命令架构

### 命令格式

```bash
clashtool <直接命令>              # 常用操作：start/stop/restart/reload/status
clashtool <分组> <子命令> [参数]  # 分组命令
clashtool                         # 无参数进入 TUI 交互菜单
```

### 直接命令（常用操作）

| 命令 | 参数 | 说明 |
|------|------|------|
| `start` | [订阅名] | 启动 Clash |
| `stop` | — | 停止 Clash |
| `restart` | [订阅名] | 重启 Clash |
| `reload` | [订阅名] | 热重载配置 |
| `status` | — | 查看 Clash 运行状态 |

### 分组命令

#### subscribe — 订阅管理

| 命令 | 参数 | 说明 |
|------|------|------|
| `subscribe add` | 名称::地址::间隔(小时) | 添加/修改订阅 |
| `subscribe del` | 订阅名称 | 删除订阅 |
| `subscribe list` | — | 列出所有订阅 |
| `subscribe update` | [名称\|all] | 更新订阅文件 |
| `subscribe auto-update` | on\|off | 开启/关闭自动更新 |

#### nodes — 节点选择与测试

| 命令 | 说明 |
|------|------|
| `nodes select` | 选择代理规则组/服务器（交互式） |
| `nodes test` | 测试代理延迟（交互式） |
| `nodes urltest` | URL 连通性测试（交互式） |

#### proxy — 代理控制

| 命令 | 说明 |
|------|------|
| `proxy` | 查看代理状态（默认） |
| `proxy on` | 开启系统代理（**需 source**） |
| `proxy off` | 关闭系统代理（**需 source**） |
| `proxy status` | 查看代理状态 |

#### config — 配置管理

| 命令 | 参数 | 说明 |
|------|------|------|
| `config` | — | 查看所有配置项 |
| `config get` | 键 | 读取配置项值 |
| `config set` | 键::值 | 设置/修改配置项 |
| `config del` | 键 | 删除配置项 |
| `config edit` | — | 编辑器修改 user.yaml |
| `config tool` | 键::值 \| 键 | 编辑 clashtool 工具配置 |

**可编辑配置键**：`port` `socks-port` `redir-port` `tproxy-port` `mixed-port` `allow-lan` `bind-address` `mode` `log-level` `ipv6` `unified-delay` `external-controller` `global-client-fingerprint` `external-ui` `secret` `interface-name` `routing-mark`

#### install — 安装管理

| 命令 | 参数 | 说明 |
|------|------|------|
| `install` | — | 安装核心+UI（默认全安装） |
| `install core` | [版本号] | 仅安装 Clash 核心 |
| `install ui` | dashboard\|yacd\|zashboard | 仅安装 Web 界面 |

#### uninstall — 卸载管理

| 命令 | 参数 | 说明 |
|------|------|------|
| `uninstall` | — | 卸载核心+UI（默认全卸载，保留配置） |
| `uninstall all` | — | 完全卸载（核心 + UI + 所有配置） |
| `uninstall core` | — | 仅卸载 Clash 核心（保留配置和 UI） |
| `uninstall core purge` | — | 卸载核心并删除配置文件 |
| `uninstall ui` | — | 仅卸载 Web 界面 |

#### update — 更新管理

| 命令 | 参数 | 说明 |
|------|------|------|
| `update` | [版本号] | 更新核心+UI（默认全更新） |
| `update core` | [版本号] | 仅更新 Clash 核心 |
| `update ui` | dashboard\|yacd\|zashboard | 更新/更换 UI |
| `update script` | — | 更新 clashtool 脚本本身 |

#### system — 系统设置

| 命令 | 参数 | 说明 |
|------|------|------|
| `system autostart` | on\|off | 开启/关闭开机自启 |
| `system gateway` | on\|off | 开启/关闭网关模式 |
| `system check` | — | 检查脚本更新 |

#### tools — 工具维护

| 命令 | 说明 |
|------|------|
| `tools logs` | 查看/搜索/过滤日志 |
| `tools backup` | 备份配置 |
| `tools restore` | 从备份恢复 |
| `tools health` | 健康检查与恢复 |
| `tools symlink` | 修复 clashtool 软链接 |

---

## 功能说明

### 1. 状态检测

采用 3 级 fallback 检测 Clash 进程：完整路径匹配 → 进程名匹配 → 端口监听检测。脚本加载时及每次操作前自动刷新状态。

### 2. 服务控制

| 操作 | 说明 |
|------|------|
| 启动 | 加载配置 → 网关检测 → nohup 启动 → 状态校验 |
| 停止 | SIGTERM → 3秒超时 → SIGKILL → 验证停止 |
| 重启 | stop + start |
| 热重载 | 通过 Clash REST API 热重载配置（无需重启） |

### 3. 开机自启

- **root 安装**：通过 systemd 服务文件实现，支持 `systemctl enable/disable`
- **用户级安装**：通过桌面自启动文件（`.desktop`）实现

### 4. 网关控制

启用时设置 `sysctl net.ipv4.ip_forward=1`（含 IPv6），写入网关配置。禁用时反向操作。Clash 运行中切换网关会自动 restart。

### 5. 代理设置

**五层架构**（从上到下）：

| 层级 | 作用范围 | 持久性 |
|------|---------|--------|
| Shell RC 文件 | bash/zsh/fish 用户 | 持久（写入 ~/.bashrc 等） |
| 当前 Shell 环境变量 | 当前会话 | 即时生效，关闭终端失效 |
| 系统级 | /etc/profile.d + /etc/environment + systemd | 持久，全局生效 |
| 桌面环境 | GNOME/KDE/XFCE/Cinnamon 等的代理设置 | 持久，桌面会话生效 |
| NetworkManager | nmcli 网络连接级代理 | 持久 |

**支持的桌面环境**：

| 桌面 | 代理设置方式 |
|------|-------------|
| GNOME / MATE / Cinnamon / Budgie / Deepin | gsettings → dconf（`org.gnome.system.proxy`） |
| KDE Plasma 5/6 | kwriteconfig5/6 |
| XFCE | xfconf-query |

**安全特性**：幂等性检查、端口范围验证（1-65535）、TCP 可达性检测、错误追踪汇总。

### 6. 代理选择

通过 Clash REST API 实现代理组和服务器选择：

| 功能 | 说明 |
|------|------|
| 选择规则组 | 列出所有代理组，当前选择高亮 |
| 选择服务器 | 选定组内切换服务器，切换后验证 |
| 测试延迟 | 对组或单个服务器测速 |
| 查看状态 | 显示所有代理组及当前选择 |
| URL 批量测试 | 批量延迟测试 |

### 7. 配置管理

所有配置值经类型校验后写入，自动修正 YAML 类型。支持 `config get` 读取单值、`config set` 设置键值对、`config edit` 调用编辑器（GUI→nano→vim→vi 回退）修改。

### 8. 订阅管理

订阅配置通过 INI 持久化存储，支持自动定时更新。订阅地址格式为 `名称::URL::间隔(小时)`，间隔可选。

### 9. 安装管理

| 操作 | 命令 | 说明 |
|------|------|------|
| 管道安装 | `curl ... \| sh` | 一键在线安装（无需克隆仓库） |
| 全安装 | `install` | 核心 + UI（默认） |
| 仅核心 | `install core` | 下载 Clash + yq + GeoIP |
| 仅 UI | `install ui` | dashboard / yacd / zashboard |
| 全卸载 | `uninstall` | 核心 + UI（默认） |
| 卸载核心 | `uninstall core` | 保留配置和 UI |
| 清除卸载 | `uninstall core purge` | 卸载核心并删除配置 |
| 更新全部 | `update` | 核心 + UI |
| 更新脚本 | `update script` | 从 GitHub 拉取最新脚本 |

下载特性：GitHub 代理加速、自动重试 3 次、多架构支持、管道模式全在线部署。

### 10. 日志查看

| 功能 | 说明 |
|------|------|
| 最近 50 行 | 快速查看最新日志 |
| 关键词搜索 | 高亮匹配内容 |
| 按级别筛选 | DEBUG / INFO / WARNING / ERROR / SILENT |
| 实时跟踪 | 类似 `tail -f` |
| 查看全部 | 完整日志 |

### 11. 备份恢复

| 操作 | 说明 |
|------|------|
| 备份 | tar 打包整个配置目录 |
| 恢复 | 从备份文件解压恢复 |
| 列出备份 | 显示所有备份及大小 |
| 删除备份 | 移除指定备份 |

### 12. 健康检查

检查 Clash 运行健康状态（内存/CPU/连接数），支持自动恢复切换。

---

## 主菜单结构

```
[0] 服务控制   - 启动/停止/重启/重载
[1] 开机自启   - 当前状态 & 一键切换
[2] 网关控制   - 当前状态 & 一键切换
[3] 本机代理   - 当前状态 & 一键切换
[4] 订阅配置   - 管理订阅和配置
[5] 代理选择   - 规则组/服务器/延迟/状态
[6] 安装       - 安装/更新/卸载 核心&界面
[7] 工具维护   - 日志/备份/规则/配置/健康
[8] 状态       - 显示 Clash 信息
[9] 更新       - 检查/更新脚本
```

- 选项 1-3：动态显示当前状态（`[ON]` / `[OFF]`），直接选择切换
- 选项 0/4-9：进入对应子菜单或执行操作

---

## 文件与目录

### 项目文件

| 文件 | 说明 |
|------|------|
| `clashtool.sh` | 主脚本（业务逻辑 + 命令分发 + 菜单定义） |
| `clashtool_tui.sh` | TUI 模块（菜单渲染、按键读取、交互组件） |
| `i18n/zh_CN.sh` | 简体中文语言模块 |
| `i18n/en.sh` | 英文语言模块（基础/翻译模板） |
| `test_all.sh` | 统一测试脚本（静态单元测试 + 端到端测试） |

### 多语言架构

脚本支持多语言国际化，语言文件位于 `i18n/` 目录：

| 文件 | 语言 | 说明 |
|------|------|------|
| `i18n/en.sh` | English | 英文基础模块（同时在主脚本中定义为默认值） |
| `i18n/zh_CN.sh` | 简体中文 | 简体中文翻译模块 |

**语言检测优先级**（`detect_language()` 函数）：
1. `language` 变量（用户配置，如 `zh_CN` / `en` / `auto`）
2. `use_chinese` 变量（向后兼容，`true` 等价于 `language=zh_CN`）
3. `LANG` 环境变量（自动检测，如 `zh_CN.UTF-8` → `zh_CN`）

**添加新语言**：
1. 复制 `i18n/en.sh` 为 `i18n/<新语言代码>.sh`（如 `i18n/zh_TW.sh`）
2. 翻译所有变量值为对应语言
3. 设置 `language="<新语言代码>"` 或依赖 `LANG` 自动检测

**配置语言**：修改 `clashtool.sh` 顶部的 `language` 变量：
```sh
language="zh_CN"   # 强制中文
language="en"      # 强制英文
language="auto"    # 自动检测（根据 LANG 环境变量）
```

### 安装目录结构

**root 安装**（`/opt/clash/`）：

```
/opt/clash/
├── clash                      # 核心二进制
├── yq                         # YAML 工具
├── clashtool.sh               # 主脚本
├── clashtool_tui.sh           # TUI 模块
├── i18n/                      # 多语言目录
│   ├── zh_CN.sh              # 简体中文
│   └── en.sh                 # English
├── ui/                        # Web UI
│   └── index.html
├── config/
│   ├── config.yaml            # 主配置（自动生成）
│   ├── user.yaml              # 用户配置（可编辑）
│   ├── gateway.yaml           # 网关配置
│   ├── clashtool.ini          # 工具配置（INI 格式）
│   ├── subscriptions/         # 订阅文件
│   └── backups/               # 备份文件
└── logs/
    └── clash.log              # 日志文件
```

**用户级安装**（`~/.local/clash/`）结构相同，软链接到 `~/.local/bin/clashtool`。

### 配置文件说明

| 文件 | 格式 | 用途 |
|------|------|------|
| `config.yaml` | YAML | Clash 主配置（自动合并生成，不直接编辑） |
| `user.yaml` | YAML | 用户可编辑配置 |
| `gateway.yaml` | YAML | 网关配置 |
| `clashtool.ini` | INI | 工具配置（订阅记录、自启状态等） |

---

## 权限模型

| 安装方式 | 安装目录 | 软链接位置 | systemd 服务 |
|---------|---------|-----------|-------------|
| root 安装 | `/opt/clash/` | `/usr/local/bin/clashtool` | 支持 |
| 用户级安装 | `~/.local/clash/` | `~/.local/bin/clashtool` | 不支持（用桌面自启动） |

- 常用操作（start/stop/restart/reload/status）两种安装方式都可直接执行
- 网关控制（`system gateway`）需要 root 权限
- 安装/卸载/更新操作会根据当前权限自动选择目标目录

---

## 测试

```bash
# 全部测试（建议 root 以获得完整覆盖）
sudo sh test_all.sh

# 详细模式
sudo sh test_all.sh --verbose

# 指定测试
sudo sh test_all.sh -t test_command_groups

# 列出所有测试
sh test_all.sh --list

# 交互式按键测试（需要真实终端）
sh test_all.sh -i
```

测试覆盖：基础验证、终端能力、环境检测、配置操作、代理开关、桌面集成、TUI 组件、国际化、端到端功能测试。

---

## 从旧版本迁移

如果从旧版本（v1.4 及以前）升级，请参阅 [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) 了解命令映射和迁移步骤。

主要变化：
- 旧扁平命令（如 `add`、`auto_start`、`proxy_select_group`）已移除，改用分组命令
- 删除所有简写命令（`-se`、`-su`、`-px` 等）
- 新增 `uninstall`、`update` 独立分组
- `install symlink` 移至 `tools symlink`
- 新增 `config get` 子命令、`uninstall core purge` 参数、`update script` 子命令
