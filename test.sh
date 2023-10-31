#!/bin/sh
echo "测试开始"
path="$(dirname "$(readlink -f "$BASH_SOURCE")")"
${path}/clashtool.sh install 'v1.16.0'
${path}/clashtool.sh update
${path}/clashtool.sh install_ui
${path}/clashtool.sh update_ui yacd
${path}/clashtool.sh add pp::https://raw.githubusercontent.com/snakem982/proxypool/main/clashd0932.yaml::24
crontab -l
${path}/clashtool.sh add pp::https://raw.githubusercontent.com/snakem982/proxypool/main/clashd0932.yaml::0
crontab -l
${path}/clashtool.sh list
${path}/clashtool.sh update_sub pp
${path}/clashtool.sh start
${path}/clashtool.sh reload pp
${path}/clashtool.sh restart
${path}/clashtool.sh status
${path}/clashtool.sh stop
${path}/clashtool.sh del pp
${path}/clashtool.sh list
${path}/clashtool.sh auto_start true
${path}/clashtool.sh auto_start false
${path}/clashtool.sh uninstall_ui
${path}/clashtool.sh uninstall all
echo "测试结束"
