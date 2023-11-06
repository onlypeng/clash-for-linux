1.0.2本次升级可自定义clash储存库，自定义储存库请修改脚本内部clash_repo、download_clash_name变量。可直接使用脚本内部升级<br>
1.0.1本次升级由于更换相关安装和存放位置，需完全卸载以前版本，记得保存以前代理地址或文件。<br>

功能：<br>
 安装Clash、卸载Clash、 更新Clash、 安装webUI界面、卸载webUI界面、 更新或更换webUI界面、更新当前脚本、启动Clash、 停止Clash、 重启Clash、 重载Clash、 添加订阅、 删除订阅、 更新订阅(可自动更新)、 查询所有订阅、 开机自启动(已测试alpine、centos、Ubuntu、debian)、 查当前运行Clash相关信息、 启用或禁用本机代理<br>
<br>
脚本可自定义编辑参数<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 网页初始链接密码，不填写则随机生成<br>
&nbsp;&nbsp;&nbsp;&nbsp;secret=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# clash架构，默认自动获取，获取失败请自行填写<br>
&nbsp;&nbsp;&nbsp;&nbsp;platform=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# clash库，默认库不能用时写备份库<br>
&nbsp;&nbsp;&nbsp;&nbsp;clash_repo='Dreamacro/clash'<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 使用中文提示输出语言<br>
&nbsp;&nbsp;&nbsp;&nbsp;chinese=true<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# clash项目库<br>
&nbsp;&nbsp;&nbsp;&nbsp;clash_repo='doreamon-design/clash'<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# clash releases名称规则  变量 版本 :version: 架构 :platform:<br>
&nbsp;&nbsp;&nbsp;&nbsp;download_clash_name='clash_:version:_linux_:platform:.tar.gz'<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# github下载代理地址<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 订阅使用github代理下载<br>
&nbsp;&nbsp;&nbsp;&nbsp;sub_proxy=false<br>
&nbsp;&nbsp;&nbsp;&nbsp;github_proxy=""<br>
<br>
clash相关信息获取位置 从Clash库Releases中的文件名称 clash-darwin-amd64-v1.16.0.gz<br>
&nbsp;&nbsp;&nbsp;&nbsp;版本 例如：1.16.0<br>
&nbsp;&nbsp;&nbsp;&nbsp;架构 例如：amd64<br>    
<br>
用户更改clash用户配置文件《位置：vi /opt/clash/config/user.yaml》 ，该配置文件中数据会自动覆盖订阅文件数据，仅支持基本的单行数据，不支持复杂数组等数据<br>
<br>
详细命令可运行 ./clashtool help 查看<br>
<br>
#测试用储存库：<br>
&nbsp;&nbsp;&nbsp;&nbsp;clash:https://github.com/doreamon-design/clash/releases<br>

使用ClashUI的项目地址：<br>
&nbsp;&nbsp;&nbsp;&nbsp;yacd：https://github.com/haishanh/yacd/tree/gh-pages<br>
&nbsp;&nbsp;&nbsp;&nbsp;dashboard：https://github.com/Dreamacro/clash-dashboard/tree/gh-pages<br>
<br>
配合这些软件食用效果更佳<br>
&nbsp;&nbsp;&nbsp;&nbsp;浏览器插件：SwitchyOmega<br>
&nbsp;&nbsp;&nbsp;&nbsp;Windows代理软件:ProxifierPE<br>
<br>
使用教程:<br>
1、下载脚本：curl -O https://ghproxy.com/https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh<br>
2、给予运行权限：chmod 755 clashtool.sh<br>
3、运行脚本（非proxy命令）：./clashtool.sh 命令 参数<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;运行脚本（proxy命令）：source clashtool.sh proxy 参数<br>