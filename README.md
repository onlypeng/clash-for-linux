linux上clash工具脚本，需wget和curl支持·

clashtool [command] command2
command 参数1
 command2 参数2

install：
  dashboard：@https://codeload.github.com/Dreamacro/clash-dashboard
  yacd： @https://codeload.github.com/haishanh/yacd
  默认不写为不安装ui 
install-ui：
 dashboard：@https://codeload.github.com/Dreamacro/clash-dashboard
 yacd： @https://codeload.github.com/haishanh/yacd
 默认不屑安装dashboardui        
uninstall         (ui 或 config or all) 默认只卸载clash
uninstall-ui      (not command2)参数为""
update            (ui 或 all) 默认只更新clash
update-ui         (dashboard 或 yacd) 默认更新当前安装ui
start             (config name) 默认当前config
