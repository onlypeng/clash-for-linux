linux上clash工具脚本，需wget和curl支持

clashtool [功能] 参数
fun: 功能 必填
var: 参数 根据fun选填

install：安装clash 
    《clash版本，例：v1.11.8》
    默认安装clash最新版本
update：更新clash 
    例：v1.11.8 更新clash版本
    默认更新clash最新版本
uninstall：卸载clash
    不存在参数
install_ui：安装clashUI
    dashboard：安装dashboardUI @https://github.com/Dreamacro/clash-dashboard
    yacd：安装yacdUI @https://github.com/haishanh/yacd
    默认安装dashboardUI
update_ui：更新clashUI
    dashboard：更新或更换dashboardUI @https://github.com/Dreamacro/clash-dashboard
    yacd：更新或更换yacdUI @https://github.com/haishanh/yacd
    默认更新当前安装UI
uninstall_ui：卸载UI
    不存在参数
uninstall_all：卸载并删除相关文件
    不存在参数
start: 启动clash
    《配置文件名称》
    默认当前使用配置
stop: 停止clash
    没有参数
restart: 重启clash
    《配置文件名称》
    默认当前使用配置
reload: 重载clash配置文件
    《配置文件名称》
    默认当前使用配置
add：添加配置文件
    《配置信息，格式：配置名称::订阅地址::自动订阅时间(小时)::是否自动订阅(true/false)》
del：删除订阅配置
    《配置文件名称》
    默认当前使用配置
subscribe：更新配置文件
    《配置文件名称》
    默认更新全部配置
list：显示全部订阅配置
    没有参数
auto_start：设置开机自启（暂无法使用）
    true：开启开机自启
    false：关闭开机自启
auto_subscribe：设置定时自动更新
    没有参数
help: 帮助文档
    没有参数