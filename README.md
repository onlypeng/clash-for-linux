脚本可自定义编辑参数
&nbsp;&nbsp;&nbsp;&nbsp;\# 网页初始链接密码，不填写则随机生成
&nbsp;&nbsp;&nbsp;&nbsp;secret=''
&nbsp;&nbsp;&nbsp;&nbsp;\# clash架构，默认自动获取，获取失败请自行填写
&nbsp;&nbsp;&nbsp;&nbsp;platform=''
&nbsp;&nbsp;&nbsp;&nbsp;\# 使用中文提示输出语言
&nbsp;&nbsp;&nbsp;&nbsp;chinese=true
&nbsp;&nbsp;&nbsp;&nbsp;\# 订阅使用github代理下载
&nbsp;&nbsp;&nbsp;&nbsp;sub_proxy=false
&nbsp;&nbsp;&nbsp;&nbsp;\# github下载代理地址
&nbsp;&nbsp;&nbsp;&nbsp;github_proxy="https://gh.ylpproxy.eu.org/"

clash相关信息获取位置，例：https://github.com/Dreamacro/clash/releases 中的 clash-darwin-amd64-v1.16.0.gz<br>
&nbsp;&nbsp;&nbsp;&nbsp;版本 例如：v1.16.0<br>
&nbsp;&nbsp;&nbsp;&nbsp;架构 例如：darwin-amd64<br>

用户更改clash用户配置文件《位置：/clashtool地址/clash/config/user.yaml ，该配置文件中数据会自动覆盖订阅文件数据，仅支持单行数据，不支持复杂数组等数据 

详细命令可运行 ./clashtool help 查看 

使用Clash核心的项目地址：https://github.com/Dreamacro/clash/releases<br>
使用ClashUI的项目地址：
&nbsp;&nbsp;&nbsp;&nbsp;yacd：https://github.com/haishanh/yacd/tree/gh-pages<br>
&nbsp;&nbsp;&nbsp;&nbsp;dashboard：https://github.com/Dreamacro/clash-dashboard/tree/gh-pages