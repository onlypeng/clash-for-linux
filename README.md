功能：<br>
 安装Clash、卸载Clash、 更新Clash、 安装webUI界面、卸载webUI界面、 更新或更换webUI界面 启动Clash、 停止Clash、 重启Clash、 重载Clash、 添加订阅、 删除订阅、 更新订阅(可自动更新)、 查询所有订阅、 开机自启动(已测试alpine、centos、Ubuntu、debian)、 查当前运行Clash相关信息、 启用或禁用本机代理<br>
<br>
脚本可自定义编辑参数<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 网页初始链接密码，不填写则随机生成<br>
&nbsp;&nbsp;&nbsp;&nbsp;secret=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# clash架构，默认自动获取，获取失败请自行填写<br>
&nbsp;&nbsp;&nbsp;&nbsp;platform=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 想在当前环境下运行多个clash时设置，不能重复<br>
&nbsp;&nbsp;&nbsp;&nbsp;script_name=''<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 使用中文提示输出语言<br>
&nbsp;&nbsp;&nbsp;&nbsp;chinese=true<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# 订阅使用github代理下载<br>
&nbsp;&nbsp;&nbsp;&nbsp;sub_proxy=false<br>
&nbsp;&nbsp;&nbsp;&nbsp;\# github下载代理地址<br>
&nbsp;&nbsp;&nbsp;&nbsp;github_proxy="https://ghproxy.com/"<br>
<br>
clash相关信息获取位置，例：https://github.com/Dreamacro/clash/releases 中的 clash-darwin-amd64-v1.16.0.gz<br>
&nbsp;&nbsp;&nbsp;&nbsp;版本 例如：v1.16.0<br>
&nbsp;&nbsp;&nbsp;&nbsp;架构 例如：darwin-amd64<br>
<br>
用户更改clash用户配置文件《位置：vi /$HOME/clashs/cript_name(你设置的变量，没有省略)/config/user.yaml》 ，该配置文件中数据会自动覆盖订阅文件数据，仅支持基本的单行数据，不支持复杂数组等数据<br>
<br>
详细命令可运行 ./clashtool help 查看<br>
<br>
使用Clash核心的项目地址：https://github.com/Dreamacro/clash/releases<br>
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