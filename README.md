1.1.1修复卸载参数all无效bug,删除测试网关设置相关代码<br>
1.1.0添加选择操作菜单，修复部分bug,切换测试用Clahs库，切换dashboard UI库。<br>
1.0.3更新注解，屏蔽部分压缩文件格式解压，此版本不涉及功能更改，可不更新。<br>
1.0.2本次升级可自定义clash储存库，自定义储存库请修改脚本内部clash_repo、download_clash_name变量。可直接使用脚本内部升级。<br>
1.0.1本次升级由于更换相关安装和存放位置，需完全卸载以前版本，记得保存以前代理地址或文件。<br>

功能：<br>
 安装Clash、卸载Clash、 更新Clash、 安装webUI界面、卸载webUI界面、 更新或更换webUI界面、更新当前脚本、启动Clash、 停止Clash、 重启Clash、 重载Clash配置、 添加订阅、 删除订阅、 更新订阅(可自动更新)、 查询所有订阅、 开机自启动(已测试alpine、centos、Ubuntu、debian)、 查当前运行Clash相关信息、 启用或禁用本机代理<br>
<br>
#脚本可自定义编辑参数<br>
&nbsp;&nbsp;&nbsp;&nbsp;# 网页初始链接密码，不填写则随机生成<br>
&nbsp;&nbsp;&nbsp;&nbsp;secret=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;# clash架构，默认自动获取，获取失败请自行填写<br>
&nbsp;&nbsp;&nbsp;&nbsp;platform=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;# 使用中文提示输出语言<br>
&nbsp;&nbsp;&nbsp;&nbsp;chinese=true<br>
&nbsp;&nbsp;&nbsp;&nbsp;# clash项目库<br>
&nbsp;&nbsp;&nbsp;&nbsp;# https://github.com/MetaCubeX/mihomo/releases/download/v1.18.9/mihomo-linux-amd64-v1.18.9.gz<br>
&nbsp;&nbsp;&nbsp;&nbsp;clash_repo='MetaCubeX/mihomo'<br>
&nbsp;&nbsp;&nbsp;&nbsp;# clash download/后路径解析 可用变量 版本 :version: 架构 :platform:<br>
&nbsp;&nbsp;&nbsp;&nbsp;clash_releases_file='v:version:/mihomo-linux-:platform:-v:version:.gz'<br>
&nbsp;&nbsp;&nbsp;&nbsp;# yacd UI项目<br>
&nbsp;&nbsp;&nbsp;&nbsp;yacd_url='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'<br>
&nbsp;&nbsp;&nbsp;&nbsp;# clash-dashboardUI项目<br>
&nbsp;&nbsp;&nbsp;&nbsp;dashboard_url='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'<br>
&nbsp;&nbsp;&nbsp;&nbsp;# 下在错误重试次数<br>
&nbsp;&nbsp;&nbsp;&nbsp;max_retries=3<br>
&nbsp;&nbsp;&nbsp;&nbsp;# 订阅使用github代理下载<br>
&nbsp;&nbsp;&nbsp;&nbsp;sub_proxy=false<br>
&nbsp;&nbsp;&nbsp;&nbsp;# github下载代理地址，clash和ui下载默认使用该代理,地址最后携带/<br>
&nbsp;&nbsp;&nbsp;&nbsp;github_proxy="https://ghp.ci/"<br>
&nbsp;&nbsp;&nbsp;&nbsp;# 设置代理的环境变量(一般为本机)<br>
&nbsp;&nbsp;&nbsp;&nbsp;proxy_host="http://127.0.0.1"<br>
&nbsp;&nbsp;&nbsp;&nbsp;proxy_keys="http https ftp socks"<br>
&nbsp;&nbsp;&nbsp;&nbsp;proxy_no="localhost,127.0.0.1,::1"<br>
<br>
用户更改clash用户配置文件《位置：vi /opt/clash/config/user.yaml》 ，该配置为clash启动时默认加载配置，订阅配置通过clash重载方式加载<br>
<br>

配合这些软件食用效果更佳<br>
&nbsp;&nbsp;&nbsp;&nbsp;浏览器插件：SwitchyOmega<br>
&nbsp;&nbsp;&nbsp;&nbsp;Windows代理软件:ProxifierPE<br>
<br>
使用教程:<br>
1、下载脚本：curl -O https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh<br>
2、给予运行权限：chmod 755 clashtool.sh<br>
3、运行脚本：<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;方式一：./clashtool.sh<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;方式二：./clashtool.sh 命令 参数（详细命令./clashtool.sh help进行查看）<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;设置代理（proxy命令），必须使用source或.命令，例如：source clashtool.sh proxy 参数<br>