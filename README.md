linux上clash工具脚本，需wget和curl支持 <br>

clashtool [功能] 参数<br>
fun: 功能 必填 <br>
var: 参数 根据fun选填 <br>

install：安装clash <br> 
    《clash版本，例：v1.11.8》 <br>
    默认安装clash最新版本 <br>
update：更新clash <br> 
    例：v1.11.8 更新clash版本 <br>
    默认更新clash最新版本 <br>
uninstall：卸载clash <br>
    不存在参数 <br>
install_ui：安装clashUI <br>
    dashboard：安装dashboardUI @https://github.com/Dreamacro/clash-dashboard <br>
    yacd：安装yacdUI @https://github.com/haishanh/yacd <br>
    默认安装dashboardUI <br>
update_ui：更新clashUI <br>
    dashboard：更新或更换dashboardUI @https://github.com/Dreamacro/clash-dashboard <br>
    yacd：更新或更换yacdUI @https://github.com/haishanh/yacd <br>
    默认更新当前安装UI <br>
uninstall_ui：卸载UI <br>
    不存在参数 <br>
uninstall_all：卸载并删除相关文件 <br>
    不存在参数 <br>
start: 启动clash <br>
    《配置文件名称》 <br>
    默认当前使用配置 <br>
stop: 停止clash <br>
    没有参数 <br>
restart: 重启clash <br>
    《配置文件名称》 <br>
    默认当前使用配置 <br>
reload: 重载clash配置文件 <br>
    《配置文件名称》 <br>
    默认当前使用配置 <br>
add：添加配置文件 <br>
    《配置信息，格式：配置名称::订阅地址::自动订阅时间(小时)::是否自动订阅(true/false)》 <br>
del：删除订阅配置 <br>
    《配置文件名称》 <br>
    默认当前使用配置 <br>
subscribe：更新配置文件 <br>
    《配置文件名称》 <br>
    默认更新全部配置 <br>
list：显示全部订阅配置 <br>
    没有参数 <br>
auto_start：设置开机自启（暂无法使用）<br>
    true：开启开机自启 <br>
    false：关闭开机自启 <br>
auto_subscribe：设置定时自动更新 <br>
    没有参数 <br>
help: 帮助文档 <br>
    没有参数 <br>