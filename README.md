# 自定义参数 <br>
platform 根据自己平台选择下载的clash版本，必须根据自己平台填写 <br>
clash_catalog 程序存放目录，可默认 <br>
config_catalog 配置存放目录，可默认 <br>
用户更改clash配置文件config.yaml <br>
Clas默认登录地址http://ip:9090/ui
Clas默认登录密码：12123 <br>
下载：wget https://raw.githubusercontent.com/onlypeng/clashtools/main/clashtool.sh <br>
 <br>
linux上clash工具脚本，需wget和curl支持 <br>
 <br>
clashtool \[功能\] 参数 <br>
fun: 功能 必填 <br>
var: 参数 根据fun选填 <br>
 <br>
install：安装clash @https://github.com/Dreamacro/clash <br>
&emsp;&emsp;《clash版本，例：v1.11.8》 <br>
&emsp;&emsp;默认安装clash最新版本 <br>
update：更新clash <br>
&emsp;&emsp;例：v1.11.8 更新clash版本 <br>
&emsp;&emsp;默认更新clash最新版本 <br>
uninstall：卸载clash <br>
&emsp;&emsp;《all》 卸载同步删除配置 <br>
&emsp;&emsp;默认只卸载Clash <br>
swithc_ui：切换clashUI <br>
&emsp;&emsp;dashboard：更新或更换dashboardUI @https://github.com/Dreamacro/clash-dashboard <br>
&emsp;&emsp;yacd：更新或更换yacdUI @https://github.com/haishanh/yacd <br>
&emsp;&emsp;默认更新当前安装UI <br>
start: 启动clash <br>
&emsp;&emsp;《配置文件名称》 <br>
&emsp;&emsp;默认当前使用配置 <br>
stop: 停止clash <br>
&emsp;&emsp;没有参数 <br>
restart: 重启clash <br>
&emsp;&emsp;没有参数，使用前使用配置 <br>
reload: 重载clash配置文件 <br>
&emsp;&emsp;《配置文件名称》 <br>
&emsp;&emsp;默认当前使用配置 <br>
add：添加配置文件 <br>
&emsp;&emsp;《配置信息，格式：配置名称::订阅地址::自动订阅时间(小时)::是否自动订阅(true/false)》 <br>
del：删除订阅配置 <br>
&emsp;&emsp;《配置文件名称》 <br>
update_sub：更新配置文件 <br>
&emsp;&emsp;《配置文件名称》 <br>
&emsp;&emsp;默认更新全部配置 <br>
list：显示全部订阅配置 <br>
&emsp;&emsp;没有参数 <br>
auto_start：设置开机自启（暂无法使用 <br>
&emsp;&emsp;true：开启开机自启 <br>
&emsp;&emsp;false：关闭开机自启 <br>
auto_sub：设置定时自动更新 <br>
&emsp;&emsp;没有参数 <br>
help: 帮助文档 <br>
&emsp;&emsp;没有参数 <br>
