linux上clash工具脚本，需wget和curl支持 <br>

clashtool [command] command2 <br>
command: 参数1 必填 <br>
 command2: 参数2 选填 <br>

install：安装clash <br> 
    dashboard：安装clash 和 dashboardUI @https://github.com/Dreamacro/clash-dashboard <br>
    yacd：安装clash 和 yacd @https://github.com/haishanh/yacd <br>
    默认只安装clash,不安装ui <br>
install-ui：安装clashUI <br>
    dashboard：安装dashboardUI @https://github.com/Dreamacro/clash-dashboard <br>
    yacd：安装yacdUI @https://github.com/haishanh/yacd <br>
    默认安装dashboardUI <br>
uninstall：卸载clash <br>
    ui: 卸载clash 和 当前安装的UI <br>
    config： 卸载clash 和 当前各项配置文件 <br>
    all： 卸载clash全部相关文件 <br>
    默认只卸载clash <br>
uninstall-ui：卸载UI <br>
    没有参数 <br>
update：更新clash <br>
    ui：更新clash 和 当前安装的UI <br>
    all：更新clash 和 当前安装的UI <br>
    默认只更新clash <br>
update-ui: 更新UI <br>
    dashboard: 更新UI,如过当前不为dashboardUI则替换为dashboardUI <br>
    yacd: 更新UI,如过当前不为yacdUI则替换为yacdUI <br>
    默认更新当前安装ui <br>
start: 启动clash <br>
    <配置文件名称> <br>
    默认当前config <br>
stop: 停止clash <br>
    没有参数 <br>
restart: 重启clash <br>
    没有参数 <br>
reload: 重载clash配置文件 <br>
    <配置文件名称> <br>
    默认当前config <br>
help: 帮助文档 <br>
    没有参数 <br>