Clash for Linux 管理工具

一个功能强大的 Shell 脚本，用于在 Linux 系统上管理 Clash 代理客户端。支持多种功能，包括安装、配置、订阅管理和网络设置。
版本历史
1.2.2

    修复部分 BUG

    添加 zashboard UI 支持

    更换合并配置方式

    注意: 该版本升级后需保留配置卸载重装

1.2.1

    修复 Alpine 系统修改配置报错问题

1.2.0

    添加设置本机为网关功能

    修复部分 bug

    注意: 由于更新功能，需手动更新配置文件，请手动运行 clashtool.sh update_config

1.1.1

    修复卸载参数 all 无效 bug

    删除测试网关设置相关代码

1.1.0

    添加选择操作菜单

    修复部分 bug

    切换测试用 Clash 库

    切换 dashboard UI 库

1.0.3

    更新注解

    屏蔽部分压缩文件格式解压

    注意: 此版本不涉及功能更改，可不更新

1.0.2

    支持自定义 clash 储存库

    注意: 自定义储存库请修改脚本内部 clash_repo、download_clash_name 变量

    可直接使用脚本内部升级

1.0.1

    注意: 本次升级由于更换相关安装和存放位置，需完全卸载以前版本，记得保存以前代理地址或文件

功能特性

    ✅ 安装 Clash

    ✅ 卸载 Clash

    ✅ 更新 Clash

    ✅ 安装 webUI 界面

    ✅ 卸载 webUI 界面

    ✅ 更新或更换 webUI 界面

    ✅ 更新当前脚本

    ✅ 启动 Clash

    ✅ 停止 Clash

    ✅ 重启 Clash

    ✅ 重载 Clash 配置

    ✅ 添加订阅

    ✅ 删除订阅

    ✅ 更新订阅 (可自动更新)

    ✅ 查询所有订阅

    ✅ 开机自启动 (已测试 Alpine、CentOS、Ubuntu、Debian)

    ✅ 查当前运行 Clash 相关信息

    ✅ 启用或禁用本机代理

    ✅ 启用和禁用本地网关功能

配置选项

##### 网页初始链接密码，不填写则随机生成
secret=''

##### clash架构，默认自动获取，获取失败请自行填写
platform=''

##### 使用中文提示输出语言
chinese=true

##### clash项目库
yq_version=''

##### mmdb版本
mmdb_version=''

##### clash库 
repo_clash='MetaCubeX/mihomo'

##### clash download/后路径解析 可用变量 版本 :version: 架构 :platform:
releases_file_clash='v:version:/mihomo-linux-:platform:-v:version:.gz'

##### yq库
repo_yq='mikefarah/yq'

##### yq download/后路径解析 可用变量 版本 :version: 架构 :platform:
releases_file_yq='v:version:/yq_linux_:platform:'

##### Country.mmdb 库
repo_mmdb='Dreamacro/maxmind-geoip'

##### mmdb download/后路径解析 可用变量 版本 :version: 架构 :platform:
releases_file_mmdb=':version:/Country.mmdb'

##### UI项目
ui_yacd='https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip'</br>
ui_dashboard='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'</br>
ui_zashboard='https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip'

##### 下载错误重试次数
max_retries=3

##### 订阅使用github代理下载
sub_proxy=false

##### github下载代理地址，clash和ui下载默认使用该代理,地址最后携带/
github_proxy="https://gh-proxy.com/"

##### 设置代理的环境变量(一般为本机)
proxy_host="http://127.0.0.1"
proxy_keys="http https ftp socks"
proxy_no="localhost,127.0.0.1,::1"

clash配置说明

用户可更改 Clash 用户配置文件（位置：/opt/clash/config/user.yaml）。Clash 启动和重载使用的配置为用户配置与订阅配置合并生成的临时配置文件。
配合软件

使用以下软件可以获得更好的体验：

    浏览器插件: SwitchyOmega

    Windows代理软件: ProxifierPE

安装和使用教程
1. 下载脚本
bash

curl -O https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh

2. 给予运行权限
bash

chmod 755 clashtool.sh

3. 运行脚本

方式一: 交互式菜单
bash

./clashtool.sh

方式二: 命令行直接执行
bash

./clashtool.sh [命令] [参数]

查看所有可用命令：
bash

./clashtool.sh help

设置代理 (必须使用 source 或 . 命令):
bash

source ./clashtool.sh proxy [参数]

故障排除

如果遇到问题，请尝试：

    查看脚本输出错误信息

    检查 Clash 日志文件（通常位于 /var/log/clash.log）

    确保系统已安装必要的依赖（curl, wget, unzip 等）

    检查网络连接，特别是访问 GitHub 的能力

贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。
许可证

本项目采用 MIT 许可证。详情请查看 LICENSE 文件。

提示: 使用代理软件请遵守当地法律法规，仅用于合法用途。