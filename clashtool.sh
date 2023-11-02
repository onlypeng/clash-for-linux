#!/bin/sh
# version:1.0.1

# 网页初始链接密码，不填写则随机生成
secret=''
# clash架构，默认自动获取，获取失败请自行填写
platform=''
# 使用中文提示输出语言
chinese=true
# 下在错误重试次数
max_retries=3
# 订阅使用github代理下载
sub_proxy=false
# github下载代理地址，clash和ui的下载使用该代理,最后携带/
github_proxy="https://gh.ylpproxy.eu.org/"
# 设置代理的环境变量
proxy_keys="http https ftp socks"
proxy_no="localhost,127.0.0.1,::1"

# 以下变量不可修改
# sudo命令
mysudo=''
if [ $USER != 'root' ];then
    mysudo='sudo '
fi
service_name="clash"
# clash安装目录
clash_dir="/opt/clash"
# 脚本存放位置
script_path="${clash_dir}/clashtool.sh"
# clash UI安装目录
clash_ui_dir="${clash_dir}/clash_gh_pages"
# clash 日志存放目录
logs_dir="${clash_dir}/logs"    
# clash 配置存放目录
config_dir="${clash_dir}/config"
# 订阅文件目录
subscribe_dir="${config_dir}/subscribe"
# 订阅文件备份目录
subscribe_backup_dir="${subscribe_dir}/backup"
# 用户环境变量存放地址
bashrc="$HOME/.bashrc"
if [ -n "$SUDO_USER" ]; then
    bashrc="/home/$SUDO_USER/.bashrc"
fi
# clash文件
clash_path="${clash_dir}/clash"
# clash配置文件
config_path="${config_dir}/config.yaml"
# 用户自定义配置
user_config_path="${config_dir}/user.yaml"
# clashtool 配置文件
clashtool_config_path="${config_dir}/clashtool.ini"

# 保存当前clash程序运行状态
pid=$(pgrep -f "^$clash_path -d ${config_dir}$")
if [ -z "$pid" ]; then
    state=false
else
    state=true
fi
# 英文提示文字开始——ChatGPT翻译，给不支持中文的linux系统使用
not_root_execute_msg="Please run the script with sudo or as the root user."
verify_failed_msg="Parameter can only be true, false, or ''. Default is true."
unsupported_linux_distribution_failed_msg="Unsupported Linux distribution."
recognition_system_failed_msg="Unable to determine the current operating system architecture. Please specify the platform parameter."
was_install_msg="was installed"
not_install_msg="Not installed"
install_start_msg="Starting installation"
install_success_msg="Installation successful"
install_failed_msg="Installation failed"
uninstall_start_msg="Starting uninstallation"
uninstall_success_msg="Uninstallation successful"
require_check_msg="Checking for dependencies"
require_install_failed_msg="Unable to recognize the package manager. Please install it manually."
init_config_start_msg="Initializing configuration file"
init_config_success_msg="Configuration file initialized successfully"
download_start_msg="Starting download"
download_waiting_msg="Download failed. Waiting 5 seconds before the next attempt..."
download_success_msg="Download successful"
download_failed_msg="Download failed"
get_version_failed_msg="Failed to retrieve version."
latest_version_msg="Latest Version:"
current_version_msg="Currently version:"
install_equal_versions_warn_msg="Newly installed version is the same as the current version"
install_ui_parameter_failed_msg="Parameter error. It can only be 'dashboard' or 'yacd'. Default is the currently installed version."
update_script_success_msg='Script Update Success'
clash_running_warn_msg="Clash service is already running"
clash_not_running_warn_msg="Clash service is not running"
clash_start_msg="Starting Clash service"
clash_start_success_msg="Clash service started successfully"
clash_start_failed_msg="Failed to start Clash service"
clash_yaml_failed_msg="Configuration file error"
clash_reload_success_msg="Clash configuration reloaded successfully"
clash_stop_success_msg="Clash service stopped successfully"
sub_url_check_msg="Checking subscription address validity..."
sub_url_invalid_msg="Invalid subscription address"
sub_url_effective_msg="Subscription address is valid"
add_sub_success_msg="Subscription information added successfully"
add_sub_parameter_failed_msg="Format error: Format should be 'Subscription name::Subscription address (or file path)::Subscription update interval (hours, can be empty)'"
delete_sub_success_msg="Subscription information deleted successfully"
update_sub_success_msg="Subscription information updated successfully"
auto_update_sub_success_msg="Successfully updated subscription settings automatically"
update_default_sub_failed_msg="Currently using the default configuration, unable to update"
update_local_sub_failed_msg="This configuration is a configuration and has been skipped"
not_sub_exists_msg="Subscription does not exist"
auto_start_enabled_success_msg="Auto-start enabled"
auto_start_turned_off_success_msg="Auto-start turned off"
status_running_msg="Status: Running"
status_not_running_msg="Status: Not running"
status_clash_version_msg="Clash version:"
status_sub_name_msg="Current subscription file:"
status_auto_start_msg="Auto-start on boot:"
status_clash_path_msg="Clash installation path:"
status_proxy_msg="proxy status:"
status_clash_address_msg="Clash access address:"
status_clash_secret_msg="Clash access token:"
status_clash_ui_address_msg="Clash ClashUI access address:"
list_sub_url_msg="Subscription address:"
list_sub_update_interval_msg="Update interval:"
proxy_port_update_msg="Detected that Clash http proxy port has changed and proxy is enabled. Please reset the proxy."
proxy_enable_reminder_msg="Detected agent on, please pay attention to closing it"
proxy_enable_faile_msg="Detected that proxy is enabled. Please disable proxy before uninstalling."
proxy_source_command_msg="Do not use source to execute commands other than 'proxy'."
proxy_not_source_command_msg="Please use source to execute the 'proxy' command."
proxy_on_success_msg="Proxy enabled"
proxy_off_success_msg="Proxy disabled"
help_msg="
    Command                    Parameters                            Description
    install          Version                  Optional    Install Clash (defaults to the latest version).
    uninstall        None                                 Uninstalling Clash while deleting related configurations.
    update           Version                  Optional    Update Clash (defaults to the latest version).
    install_ui       dashboard or yacd        Optional    Install the web UI (defaults to dashboard).
    uninstall_ui     None                     Optional    Uninstall Clash UI.
    update_ui        dashboard or yacd        Optional    Update or replace Clash UI (defaults to the currently used UI).
    update_script    None                                 Update clash-for-linux Script
    start            SubscriptionName         Optional    Start Clash, defaults to the current subscription.
    stop             None                     Optional    Stop Clash service.
    restart          SubscriptionName         Optional    Restart Clash, defaults to the current subscription.
    reload           SubscriptionName         Optional    Reload Clash, defaults to the current subscription.
    add              SubscriptionInfo                     Add or modify subscription info (format: 'SubscriptionName::SubscriptionURL(LocalFilePath)::UpdateInterval(hours, can be empty)').
    del              SubscriptionName                     Delete a subscription.
    update_sub       SubscriptionName or all  Optional    Update the subscription file (defaults to the current subscription); 'all' updates all subscriptions (excluding subscriptions).
    auto_update_sub  true or false                        Turn automatic update subscription on or off
    list             None                     Optional    List all subscription information.
    auto_start       true or false            Optional    Enable or disable auto-start on boot (defaults to true).
    status           None                     Optional    View Clash-related information.
    proxy            true or false            Optional    Enable or disable proxy (defaults to true); this command must be executed using 'source'.
    "
main_msg="Invalid command. Type 'help' to view available commands."
# 英文提示文字结束

# 函数：中文提示函数
chinese_language(){
    # 中文提示文字开始
    not_root_execute_msg="请使用sudo或root用户执行脚本"
    verify_failed_msg="参数只能是true、false 或 ''， ''默认为true"
    unsupported_linux_distribution_failed_msg="不支持的Linux发行版"
    recognition_system_failed_msg="无法确定当前操作系统架构类型。请自行填写platform参数"
    conf_failed_msg="配置文件错误"
    latest_version_msg="最新版本："
    current_version_msg="当前版本："
    was_install_msg="已安装"
    not_install_msg="未安装"
    install_start_msg="开始安装"
    install_success_msg="安装成功"
    install_failed_msg="安装失败"
    uninstall_start_msg="开始卸载"
    uninstall_success_msg="卸载成功"
    update_script_success_msg='脚本更新成功'
    require_check_msg="检测是否缺少依赖"
    require_install_failed_msg="无法识别包管理器，请自行安装"
    init_config_start_msg="初始化配置文件"
    init_config_success_msg="配置文件初始化成功"
    download_start_msg="开始下载"
    download_waiting_msg="下载失败，等待5秒后进行下一次尝试..."
    download_success_msg="下载成功"
    download_failed_msg="下载失败"
    get_version_failed_msg="获取版本失败"
    install_equal_versions_warn_msg="新安装版本与当前版本相同"
    install_ui_parameter_failed_msg="参数错误，只能为 dashboard 或 yacd，默认为当前安装版本"
    clash_running_warn_msg="Clash服务已运行"
    clash_not_running_warn_msg="Clash服务未启动"
    clash_start_msg="正在启动Clash服务"
    clash_start_success_msg="Clash服务启动成功"
    clash_start_failed_msg="Clash服务启动失败"
    clash_reload_success_msg="Clash重载配置成功"
    clash_stop_success_msg="Clash服务停止成功"
    sub_url_check_msg="正在检测订阅地址有效性..."
    sub_url_invalid_msg="订阅地址无效"
    sub_url_effective_msg="订阅地址有效"
    add_sub_success_msg="添加订阅信息成功"
    add_sub_parameter_failed_msg="格式错误：格式《订阅名称::订阅地址(或本地文件路径)::订阅更新时间（小时,可为空）》"
    delete_sub_success_msg="删除订阅信息成功"
    update_sub_success_msg="更新订阅信息成功"
    auto_update_sub_success_msg="自动更新订阅设置成功"
    update_default_sub_failed_msg="当前使用默认配置，无法更新"
    update_local_sub_failed_msg="该配置为本地配置，已跳过该操作"
    not_sub_exists_msg="不存在此订阅"
    auto_start_enabled_success_msg="自动启动已开启"
    auto_start_turned_off_success_msg="自动启动已关闭"
    status_running_msg="状态：运行中"
    status_not_running_msg="状态：未运行"
    status_clash_version_msg="Clash版本："
    status_sub_name_msg="当前订阅文件："
    status_auto_start_msg="开机自动启动："
    status_clash_path_msg="Clash安装路径："
    status_proxy_msg="本机代理状态："
    status_clash_address_msg="Clash访问地址："
    status_clash_secret_msg="Clash访问令牌："
    status_clash_ui_address_msg="ClashClashUI访问地址："
    list_sub_url_msg="订阅地址："
    list_sub_update_interval_msg="更新间隔："
    proxy_port_update_msg="检测到Clash http代理端口已更改并已开启代理,请重新设置代理"
    proxy_enable_reminder_msg="检测到代理开启，请注意关闭"
    proxy_enable_faile_msg="检测到代理已开启，关闭代理后再重新卸载"
    proxy_source_command_msg="不要使用source执行除proxy其他命令"
    proxy_not_source_command_msg="请使用source执行proxy命令"
    proxy_on_success_msg="代理已开启"
    proxy_off_success_msg="代理已关闭"
    help_msg="
      命令                   参数                         备注
    install         版本             可为空     安装Clash，默认为最新版本
    uninstall       空                          卸载Clash同时同时删除相关配置
    update          版本             可为空     更新Clash，默认为最新版本
    install_ui      dashboard或yacd  可为空     安装ClashUI界面，默认安装dashboard
    uninstall_ui    空               可为空     卸载ClashUI
    update_ui       dashboard或yacd  可为空     更新或更换ClashUI，默认当前使用UI
    update_script                               更新clash-for-linux脚本
    start           订阅名称         可为空     启动Clash，默认，使用当前订阅配置
    stop            空                          停止Clash运行
    restart         订阅名称         可为空     重启Clash，默认使用当前订阅配置
    reload          订阅名称         可为空     重载Clash，默认使用当前订阅配置
    add             订阅信息                    添加或修改订阅信息：格式《订阅名称::订阅地址(或本地文件路径)::订阅更新时间（小时,可为空）》
    del             订阅名称                    删除订阅
    update_sub      订阅名称或all    可为空     更新订阅文件，默认更新当前使用订阅，参数为all时更新所有订阅（不包括本地订阅）
    auto_update_sub true或false                 开启或关闭自动更新订阅
    list            空                          查询所有订阅信息
    auto_start      true或false      可为空     启用或禁用开机自启动功能，默认为true
    status          空                          查看Clash相关信息
    proxy           true或false      可为空     启用或禁用本机代理，默认为true，此命令需要使用source运行"
    main_msg="无效命令，相关命令输入help进行查看"
    # 中文提示文字结束
}

# 自动使用sudo
myunzip(){
    ${mysudo}unzip $@
}
mygunzip(){
    ${mysudo}gunzip $@
}
mysystemctl(){
    ${mysudo}systemctl $@
}
myrm(){
    ${mysudo}rm $@
}
mytee(){
    ${mysudo}tee $@
}
mycurl(){
    ${mysudo}curl $@
}
mymv(){
    ${mysudo}mv $@
}
mycp(){
    ${mysudo}cp $@
}
mysed(){
    ${mysudo}sed $@
}
mygrep(){
    ${mysudo}grep $@
}
myawk(){
    ${mysudo}awk $@
}
mymkdir(){
    ${mysudo}mkdir $@
}
mychmod(){
    ${mysudo}chmod $@
}
myrcupdate(){
    ${mysudo}rc-update $@
}

# 函数：判断指定节是否存在
# 参数：
#   $1: file - 文件名
#   $2: section - 指定节
section_exists() {
    file=$1
    section=$2
    # 使用 grep 搜索指定节
    grep -q "^\[$section\]$" "$file"
    return $?
}

# 函数：添加或修改INI配置文件
# 参数：
#   $1: section - 指定节
#   $2: key - 变量名
#   $3: value - 值
#   $4: file - 文件名
write_ini() {
    section=$1
    key=$2
    value=$3
    file=$4

    # 判断指定节是否存在
    if section_exists "$file" "$section"; then
        awk -F "=" -v section="$section" -v key="$key" -v value="$value" '
            $0 ~ /^\[.*\]$/ { in_section=($0 == "["section"]") }  # 进入指定节
            in_section && $1 == key {  # 在指定节中找到指定键
                $0=key"="value  # 修改键的值
                found=1
            }
            { print $0 }  # 输出每一行
            END {
                if (found != 1) {
                    print key"="value  # 在节中找不到键时添加新键值对
                }
            }
        ' "$file" | mytee temp.yaml >/dev/null && mymv temp.yaml "$file"
    else
        # 如果节不存在，则添加新节和键值对
        {
            echo "[$section]"
            echo "$key=$value"
        } | mytee -a "$file" >/dev/null
    fi
}

# 函数：删除INI配置项或指定节
# 参数：
#   $1: section - 指定节
#   $2: key - 变量名
#   $3: file - 文件名
delete_ini() {
    section=$1
    key=$2
    file=$3

    # 判断指定节是否存在
    if section_exists "$file" "$section"; then
        if [ -z "$key" ]; then
            # 删除整个节
            mysed -i "/\[$section\]/,/^$/d" "$file"
        else
            # 删除指定节下的指定键的配置项
            mysed -i "/\[$section\]/,+1 { /^\[$section\]/! { /$key=/d } }" "$file"
        fi
    fi
}

# 函数：获取INI配置文件
# 参数：
#   $1: file - 文件名
#   $2: section - 指定节
#   $3: key - 变量名
read_ini() {
    section=$1
    key=$2
    file=$3

    # 判断指定节是否存在
    if section_exists "$file" "$section"; then
        # 使用 awk 解析配置文件
        awk -F "=" -v section="$section" -v key="$key" '
            $0 ~ /^\[.*\]$/ { in_section=($0 == "["section"]") }
            in_section && $1 == key {
                print $2
                found=1
                exit
            }
            END {
                if (found != 1) {
                    exit 1
                }
            }
        ' "$file" || echo "Key not found: $key"
    fi
}

# 函数：获取clashtool配置
# 参数：$1: key - 变量名
get_clashtool_config() {
    key=$1
    read_ini 'clashtool' "${key}" "${clashtool_config_path}"
}

# 函数：添加或更改clashtool配置文件
# 参数：
#   $1: key - 变量名
#   $2: val - 值
set_clashtool_config() {
    key=$1
    val=$2
    write_ini "clashtool" "${key}" "${val}" "${clashtool_config_path}"
}

# 函数：判断订阅是否存在
# 参数：$1: sub_name - 订阅名称
existence_subscrib_config() {
    sub_name=$1
    section_exists "${clashtool_config_path}" "subscribe_${sub_name}"
    return $?
}

# 函数：添加修改订阅配置
# 参数：
#   $1: sec_name - 订阅名称
#   $2: key - 订阅地址
#   $3：val - 更新间隔时间
set_subscribe_config() {
    sec_name=$1
    key=$2
    val=$3
    if [ -z "$sec_name" ]; then
        sec="subscribe"
    else
        sec="subscribe_$sec_name"
    fi
    write_ini "$sec" "$key" "$val" "$clashtool_config_path"
}

# 函数：添加订阅配置
# 参数：
#   $1: name - 订阅名称
#   $2: url - 订阅地址
#   $3：interval - 更新间隔时间
add_subscribe_config() {
    name=$1
    url=$2
    interval=$3
    {
        echo "[subscribe_$name]"
        echo "url=$url"
        echo "interval=$interval"
    } | mytee -a "$clashtool_config_path" >/dev/null
    # 更新names名称
    names=$(get_subscribe_config '' 'names')${name}','
    set_subscribe_config '' 'names' "${names}"
}

# 函数：删除订阅
# 参数：$1: name - 订阅名称
del_subscribe_config() {
    name=$1
    # 更新names
    names=$(get_subscribe_config '' 'names' | sed "s/${name},//g")
    set_subscribe_config '' 'names' "$names"
    # 删除订阅节点
    delete_ini "subscribe_$name" '' "${clashtool_config_path}"
}

# 获取订阅配置
# 函数：添加订阅配置
# 参数：
#   $1: name - 订阅名称
#   $2: key - 变量名
get_subscribe_config() {
    name=$1
    key=$2
    if [ -z "${name}" ]; then
        sec="subscribe"
    else
        sec="subscribe_${name}"
    fi
    read_ini "${sec}" "${key}" "${clashtool_config_path}"
}

# 函数：获取yaml配置,只能简单的读取单行key: value
# 参数：
#   $1: key - 订阅名称
#   $2: file - 订阅文件
get_yaml_value() {
    key="$1"
    file="$2"
    mysed -n "/^$key:/s/^$key:[[:space:]]*//p" "$file"
}

# 函数：获取yaml配置,只能简单的读取单行key: value
# 参数：
#   $1: key - 订阅名称
#   $2: val - 订阅名称
#   $3: file - 订阅文件
set_yaml_value() {
    key="$1"
    val="$2"
    file="$3"
    # 使用awk进行YAML文件的编辑
    awk -v key="$key" -v value="$val" '{
        if ($1 == key ":") {
            print key ":", value
        } else {
            print $0
        }
    }' "$file" | mytee temp.yaml >/dev/null && mymv temp.yaml "$file"
}

# 函数：失败消息
# 参数：
#   $1: msg - 消息
#   $2: is_true - 是否退出脚本(true/false),默认true
failed() {
    msg=$1
    is_true=${2:-true}
    printf "\\033[88G[\\033[1;31mFAILED\\033[0;39m]\r"
    echo "$msg"
    if $is_true;then
        exit 1
    fi
}

# 函数：警告消息
# 参数：
#   $1: msg - 消息
#   $2: is_true - 是否退出脚本(true/false),默认true
warn() {
    msg=$1
    is_true=${2:-true}
    printf "\\033[88G[\\033[1;33m WARN \\033[0;39m]\r"
    echo "$msg"
    if $is_true;then
        exit 0
    fi
}

# 函数：提醒消息
# 参数：
#   $1: msg - 消息
#   $2: is_true - 是否退出脚本(true/false),默认false
remind(){
    msg=$1
    is_true=${2:-false}
    printf "\\033[88G[\\033[1;36mREMIND\\033[0;39m]\r"
    echo "$msg"
    if $is_true;then
        exit 0
    fi
}

# 函数：成功消息
# 参数：
#   $1: msg - 消息
#   $2: is_true - 是否退出脚本(true/false),默认false
success() {
    msg=$1
    is_true=${2:-true}
    printf "\\033[88G[\\033[1;32m  OK  \\033[0;39m]\r"
    echo "$msg"
    is_true=${2:-false}
    if $is_true;then
        exit 0
    fi
}

# 函数：输出UI链接相关信息
clash_ui_link_info(){
    ips=$(ip -o -4 addr show | awk '!/127.0.0.1/ {print $4}' | cut -d'/' -f1)
    port=$(get_yaml_value "external-controller" "${config_path}" | awk -F ':' '{print $2}')
    echo "$status_clash_address_msg"
    for ip in $ips; do
        echo "    http://$ip:${port}"
    done
    echo "${status_clash_secret_msg}${secret}"
    if [ -d "$clash_ui_dir" ];then
        echo "$status_clash_ui_address_msg"
        for ip in $ips; do
            echo "    http://$ip:${port}/ui"
        done
    fi
}
 
# 函数：判断是否为true或false
# 参数：$1: - 参数
verify() {
    if [ "$1" != 'true' ] && [ "$1" != 'false' ]; then
        failed "$verify_failed_msg"
    fi
}

# 函数：检测URL是否有效
# 参数：
#   $1：url - 网址
#   $2:enable - 无效是否退出脚本
check_url(){
    url=$1
    enable=${2:-true}
    # 判断地址是否有效
    echo "$sub_url_check_msg"
    if $sub_proxy;then
        curl -sSf --max-time 15 "${github_proxy}${url}" > /dev/null
    else
        curl -sSf --max-time 15 "$url" > /dev/null
    fi
    req=$?
    if [ $req -eq 0 ]; then
        success "$sub_url_effective_msg"
    else
        failed "$sub_url_invalid_msg" "$enable"
    fi
    return $req
}
# 函数：判断是否使用source命令
is_sourced() {
    # 获取脚本的绝对路径
    if [ -z $BASH_SOURCE ];then
        return 1
    fi
    script_path="$(realpath "${BASH_SOURCE[0]}")"
    current_path="$(realpath "$0")"
    # 检查是否以source命令运行
    if [ "$script_path" != "$current_path" ]; then
        return 0
    else
        return 1
    fi
}

# 函数：设置定时任务
# 参数：
#   $1: interval - 运行时间，为空则删除定时任务
#   $2: command - 需要执行的命令
crontab_tool() {
    interval=$1
    command=$2
    if [ -z "$interval" ]; then
        # 检查定时任务是否已存在
        if crontab -l | grep -qF "$command"; then
            # 定时任务存在,删除定时任务
            crontab -l | grep -v "$command" | crontab -
        fi
    else
        # 检查定时任务是否已存在
        if crontab -l | grep -qF "$command"; then
            # 定时任务已存在，执行修改操作
            crontab -l | sed -e "\|$command|d" | crontab -
            (
                crontab -l
                echo "$interval" "$command"
            ) | crontab -
        else
            # 定时任务不存在，执行添加操作
            (
                crontab -l
                echo "$interval" "$command"
            ) | crontab -
        fi
    fi
}

# 函数：安装依赖程序
# 参数：$1:name 程序名称
install_procedure(){
    name="$1"
    # 检查并安装
    if ! command -v "$name" >/dev/null 2>&1; then
        ${mysudo}echo "${install_start_msg} $name"
        if command -v apt >/dev/null 2>&1; then
            ${mysudo}apt install "$name" -y
        elif command -v yum >/dev/null 2>&1; then
            ${mysudo}yum install "$name" -y
        elif command -v dnf >/dev/null 2>&1; then
            ${mysudo}dnf install "$name" -y
        elif command -v zypper >/dev/null 2>&1; then
            ${mysudo}zypper install "$name" -y    
        elif command -v apk >/dev/null 2>&1; then
            ${mysudo}apk add "$name"
        else
            failed "$require_install_failed_msg $name"
        fi
        # 校验是否安装成功
        if command -v "$name" > /dev/null; then
            success "$name $install_success_msg"
        else
            failed "$name $install_failed_msg"
        fi
    fi
}

# 函数：获取当前操作系统的架构
get_platform(){
    if [ -z "${platform}" ]; then
        machine_arch=$(uname -m)
        # 检查架构类型并输出相应的信息
        case $machine_arch in
        x86_64 | amd64)
            platform="amd64"
            ;;
        aarch64 | arm64)
            echo "arm64"
            ;;
        i*86 | x86)
            platform="386"
            ;;
        arm*)
            platform="${machine_arch}"
            ;;
        *)
            failed "$recognition_system_failed_msg"
        esac

    fi
}

# 函数：获取当前系统发行版
get_linux_distribution() {
    if [ -f /etc/lsb-release ] || [ -f /etc/ubuntu-release ]; then
        echo "ubuntu"
    elif [ -f /etc/debian_version ];then
        echo "debian"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/centos-release ]; then
        echo "centos"
    elif [ -f /etc/redhat-release ];then
        echo "redhat"
    elif [ -f /etc/alpine-release ];then
        echo "alpine"
    else
        failed $unsupported_linux_distribution_failed_msg
    fi
}

# 函数：检查并安装依赖
require() {
    echo "$require_check_msg"
    # 检查并安装curl
    install_procedure curl
    # 检查安装unzip，竟然有linux没预安装
    install_procedure unzip
}
# 函数：初始化配置
init_config() {
    echo "$init_config_start_msg"
    # 创建clash目录
    mymkdir -p "${clash_dir}"
    # 创建配置目录
    mymkdir "${config_dir}"
    # 创建logs目录
    mymkdir "${logs_dir}"
    # 创建subscribe配置目录
    mymkdir "${subscribe_dir}"
    # 创建subscribe_backup_dir目录
    mymkdir "${subscribe_backup_dir}"
    # 创建clashtool和订阅配置文件
    {   
        echo "[clashtool]"
        echo "ui=dashboard"
        echo "version="
        echo "autoStart=false"
        echo "autoUpdateSub=true"
        echo "httpPort=7890"
        echo "socksPort=7891"
        echo ""
        echo "[subscribe]"
        echo "names="
        echo "use=default"
    } | mytee "${clashtool_config_path}" >/dev/null
    # 未自定义网页密码则产生随机密码
    if [ -z "$secret" ];then
        secret=$(tr -dc a-zA-Z0-9#@ 2>/dev/null < /dev/urandom | head -c 12)
    fi
    # 创建默认clash配置文件
    {
        echo "port: 7890"
        echo "socks-port: 7891"
        echo "allow-lan: true"
        echo "mode: Rule"
        echo "log-level: error"
        echo "external-controller: 0.0.0.0:9090"
        echo "external-ui: "
        echo "secret: ${secret}"
    } | mytee "${user_config_path}" >/dev/null

    success "$init_config_success_msg"
}

# 函数：下载通用脚本
# 参数：
#   $1: file_path - 下载后保存的文件名
#   $2: url - 要下载的文件的URL
#   $3: tag - 输出提示标签
#   $4: enable - 是否使用github代理
download(){
    file_path=$1
    url=$2
    tag=$3
    enable=${4:-true}
    echo "${download_start_msg}${tag}"
    # 关闭本shell进程代理
    if is_proxy;then
        for key in $proxy_keys 'no'; do
            unset "${key}_proxy"
        done
    fi
    # 重试计数
    retry_count=0
    # 使用curl下载文件
    while [ $retry_count -lt $max_retries ]; do
        if [ "$enable" = "true" ];then
            mycurl "${github_proxy}${url}" -o "$file_path"
        else
            mycurl "${url}" -o "$file_path"
        fi
        # 检查curl命令的退出状态为0并且下载的文件存在
        if [ $? -eq 0 ] && [ -f "$file_path" ] && [ $(stat -c%s "$1") -gt 1024 ]; then
            success "${tag}${download_success_msg}"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo "$download_waiting_msg"
                sleep 5
            else
                failed "${tag}${download_failed_msg}"
            fi
        fi
    done
}

# 函数：下载clash
# 参数：$1: version - Clash版本
download_clash(){
    version=$1
    # 获取系统型号
    get_platform
    # 获取配置中当前安装的版本
    current=$(get_clashtool_config 'version')
    if [ -n "$current" ];then
        echo "${current_version_msg}${current}"
    fi
    # 没有指定版本则更新最新版本
    if [ -z "$version" ]; then
        # 获取clash最新版本号
        api_url=https://api.github.com/repos/Dreamacro/clash/releases/latest
        version=$(curl -k -s $api_url | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':' '{print $2}')
        if [ -z "$version" ]; then
            failed "$get_version_failed_msg"
        fi
    fi
    # 要安装的版本
    echo "${latest_version_msg}${version}"
    # 判断版本是否相等
    if [ "${current}" = "${version}" ]; then
        warn "$install_equal_versions_warn_msg"
    fi
    # 下载clash
    clash_temp_path="${clash_dir}/temp_clash"
    clash_url="https://github.com/Dreamacro/clash/releases/download/${version}/clash-linux-${platform}-${version}.gz"
    download "${clash_temp_path}.gz" "$clash_url" "Clash"
    echo "${install_start_msg} Clash"
    # 解压clash
    mygunzip -f "${clash_temp_path}.gz"
    # 重命名clash
    mymv "${clash_temp_path}" "${clash_path}"
    # 赋予运行权限
    mychmod +x "${clash_path}"
    # 向clash配置文件写入当前版本
    set_clashtool_config 'version' "${version}"
}

# 函数：安装clash内核
# 参数: $1：version - clash版本 （可为空），默认为最新版本
install() {
    version=$1
    if [ -d $clash_dir ];then
        failed "Clash $was_install_msg"
    fi
    # 检测安装依赖软件
    require
    # 创建服务脚本
    create_service_file
    # 初始化目录配置
    init_config
    # 复制当前脚本到安装目录
    mycp "$(readlink -f "$0")" "$script_path"
    # 下载安装clash
    download_clash "${version}"
    success "Clash $install_success_msg"
}

# 函数：卸载clash
# 参数: $1：all -（可为空），默认不删除配置信息
uninstall() {
    # 开始删除clash
    echo "$uninstall_start_msg Clash"
    # 关闭clash
    if $state; then
        stop
    fi
    # 关闭自动启动
    if [ "$(get_clashtool_config 'autoStart')" = 'true' ];then
        auto_start false
    fi
    # 关闭自动更新订阅
    if [ "$(get_clashtool_config 'autoUpdateSub')" = 'true' ];then
        auto_update_sub false
    fi
    # 删除服务脚本
    del_service_file
    # 删除Clash所有相关文件
    myrm -rf "${clash_dir}"
    success "Clash $uninstall_success_msg"
}

# 函数：更新clash
# 参数: $1：version - clash版本 （可为空），默认为最新版本
update() {
    version=$1
    # 安装clash
    download_clash "$version"
    # 记录运行状态为启动时重新启动clash
    if $state; then
        start
    fi
}

# 函数：安装ClashUI
# 参数: $1：ui_name - 订阅名称 （可为空），默认为当前使用订阅
install_ui() {
    if [ -d $clash_ui_dir ];then
        failed "ClashUI $was_install_msg"
    fi
    ui_name=$1
    # 没有指定UI则使用配置中指定UI
    if [ -z "${ui_name}" ]; then
        ui_name=$(get_clashtool_config 'ui')
    fi
    # 下载UI安装包
    if [ "${ui_name}" = "dashboard" ]; then
        set_clashtool_config 'ui' "dashboard"
        ui_name="clash-dashboard-gh-pages"
        url="https://github.com/Dreamacro/clash-dashboard/archive/refs/heads/gh-pages.zip"
    elif [ "${ui_name}" = "yacd" ]; then
        # 在clashtool配置文件中写入ui
        set_clashtool_config 'ui' "yacd"
        ui_name="yacd-gh-pages"
        url="https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip"
    else
        failed "$install_ui_parameter_failed_msg"
    fi
    download "${clash_dir}/gh-pages.zip" "$url" "${ui_name}"
    
    echo "${install_start_msg} ClashUI"
    # 解压
    myunzip -q -d "${clash_dir}" "${clash_dir}/gh-pages.zip"
    # 重命名
    mymv "${clash_dir}/${ui_name}" "$clash_ui_dir"
    # 删除已下载文件
    myrm -rf "${clash_dir}/gh-pages.zip"
    # 设置ui配置
    set_yaml_value 'external-ui' "$clash_ui_dir" "$user_config_path"
    success "ClashUI $install_success_msg"
    # 如果正在运行则重新启动
    if $state;then
        restart
    fi
}

# 函数：卸载UI
uninstall_ui(){
    # 删除当前已安装UI
    if [ ! -d "${clash_ui_dir}" ]; then
        failed "ClashUI $not_install_msg"
    fi
    echo "$uninstall_start_msg ClashUI" 
    myrm -rf "${clash_ui_dir}"
    set_clashtool_config 'ui' 'dashboard'
    # 设置ui配置
    set_yaml_value 'external-ui' ''  "$user_config_path"
    success "ClashUI $uninstall_success_msg"
    # 如果状态为运行则重新启动
    if $state;then
        restart
    fi
}

# 函数：更新或更换ClashUI
# 参数：$1 - UI类型（yacd或dashboard）可为空，默认当前使用的ui
update_ui(){
    if [ ! -d "$clash_ui_dir" ];then
        failed "ClashUI $not_install_msg"
    fi
    echo "$uninstall_start_msg ClashUI" 
    myrm -rf "${clash_ui_dir}"
    success "ClashUI $uninstall_success_msg"
    install_ui "$1"
    # 如果状态为运行则重新启动
    if $state;then
        restart
    fi
}
# 函数: 更新clashtool脚本
update_script(){
    current_path=$(readlink -f "$0")
    current=$(grep '^# version:' "$current_path" | head -1 | sed 's/# version://')
    echo "${current_version_msg}$current"
    url='https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh'
    version=$(curl -k -s ${github_proxy}${url} | grep '^# version:' | head -1 | sed 's/# version://')
    if [ -z $version ];then
        failed $get_version_failed_msg
    fi
    echo "${latest_version_msg}$version" 
    if [ $version = $current ];then
        warn "$install_equal_versions_warn_msg"
    fi
    download "${current_path}.temp" "$url" "Script"
    cp "${current_path}.temp" $current_path
    if [ -d $clash_dir ];then
        mycp "${current_path}.temp" $script_path
    fi
    myrm "${current_path}.temp"
    success $update_script_success_msg
}   

# 函数：处理订阅配置文件,用户自定义配置覆盖订阅配置
# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
processing_config(){
    sub_name=$1
    # 未指定订阅，获取当前订阅
    if [ -z "$sub_name" ]; then
        sub_name=$(get_subscribe_config '' 'use')
    fi

    if [ "$sub_name" = 'default' ]; then
        # 使用默认配置
        mycp "${user_config_path}" "${config_path}"
    else
        if existence_subscrib_config "${sub_name}";then
             # 文件不存在则更新订阅
            if [ ! -f "${subscribe_dir}/${sub_name}.yaml" ];then
                update_sub "$sub_name"
            fi
            # 把自定义文件覆写到下载的配置文件中生成临时配置文件
            awk '
                NR==FNR { a[$1]=$2; next }
                ($1 in a) { $2=a[$1]; delete a[$1] }
                { print }
                END { for (k in a) print k, a[k] }
            ' "${user_config_path}" "${subscribe_dir}/${sub_name}.yaml" | mytee "${subscribe_dir}/temp-${sub_name}.yaml" >/dev/null
            # 校验生成的配置
            check_conf "${subscribe_dir}/temp-${sub_name}.yaml"
            # 覆盖当前配置
            mymv "${subscribe_dir}/temp-${sub_name}.yaml" "${config_path}"
        else
             # 不存在该订阅配置
            failed "$not_sub_exists_msg"
        fi  
    fi
}

# 函数：启动clash
# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
start() {
    sub_name=$1
    # 判断是否正在运行
    if [ -n "$pid" ]; then
        warn "$clash_running_warn_msg"
    else
        processing_config "$sub_name"
        echo "$clash_start_msg"
        # 判断是否第一次启动
        if [ ! -f "$config_dir/Country.mmdb" ];then
            # 下载初始文件
            "${mysudo}${clash_path}" -d "${config_dir}" 2>&1 | mytee "${logs_dir}/clash.log" >/dev/null
        fi
        # 启动clash
        ${mysudo}nohup "${clash_path}" -d "${config_dir}" 2>&1 | mytee "${logs_dir}/clash.log" >/dev/null &
        # 等待启动成功
        sleep 3
        # 判断是否启动失败
        pid=$(pgrep -f "$clash_path")
        if [ -z "$pid" ];then
            failed "$clash_start_failed_msg"
        fi
        # 修运行状态
        state=true
        if [ -n "$sub_name" ];then
            # 更改配置中默认使用的配置文件
            set_subscribe_config '' 'use' "$sub_name"
        fi
        # 显示提示信息
        port=$(get_yaml_value "external-controller" "${config_path}" | awk -F ':' '{print $2}')
        secret=$(get_yaml_value "secret" "${config_path}")
        success "$clash_start_success_msg"
        clash_ui_link_info

        if grep -q 'mixed-port:' "$user_config_path"; then
            mixed_port=$(get_yaml_value 'mixed-port' "$user_config_path")
            http_port="$mixed_port"
            mixed_port="$mixed_port"
        else
            http_port=$(get_yaml_value 'port' "$user_config_path")
            socks_port=$(get_yaml_value 'socks-port' "$user_config_path")
        fi
        _http_port=$(get_clashtool_config 'httpPort')
        _socks_port=$(get_clashtool_config 'socksPort')
        # 判断用户是否修改监http听端
        if ([ "$http_port" != "$_http_port" ] || [ "$socks_port" != "$_socks_port" ]) && is_proxy;then
            remind "$proxy_port_update_msg"
        fi
    fi
}

# 函数：停止clash
stop() {
    # 判断程序是否运行
    if [ -n "${pid}" ] ; then
        # 根据clash PID 结束Clash
        for temp_pid in $pid; do
            ${mysudo}kill "${temp_pid}"
        done
        pid=""
        # 提醒关闭系统代理
        if is_proxy;then
            remind "$proxy_enable_reminder_msg"
        fi
        success "$clash_stop_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 函数：重启clash
# 参数: $1 - 订阅名称 （可为空），默认为当前使用订阅
restart() {
    stop
    start "$1"
}

# 函数：重载clash配置文件
# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
reload() {
    sub_name=$1
    if ! $state; then
        warn "$clash_not_running_warn_msg"
    fi
    processing_config "$sub_name"
    port=$(get_yaml_value "external-controller" "${config_path}" | awk -F ':' '{print $2}')
    secret=$(get_yaml_value "secret" "${config_path}")
    # 重载配置
    if [ -z "$secret" ]; then
        result=$(curl -s -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -d "{\"path\": \"${config_path}\"}")
    else
        result=$(curl -s -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -H "Authorization: Bearer ${secret}" -d "{\"path\": \"${config_path}\"}")
    fi
    # 解析返回数据判断使用重载成功
    if [ -n "$result" ];then
        echo "$result" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p'
        failed "$clash_yamsh -x cl_failed_msg"
    fi
    # 修改启用配置文件名
    set_subscribe_config '' 'use' "${sub_name}"
    success "$clash_reload_success_msg"
}

# 函数：获取Clash信息
status() {
    ui_name=$(get_clashtool_config 'ui')
    version=$(get_clashtool_config 'version')
    autostart=$(get_clashtool_config 'autoStart')
    sub_name=$(get_subscribe_config '' 'use')
    secret=$(get_yaml_value 'secret' "$user_config_path")
    if $state; then
        echo "$status_running_msg"
    else
        echo "$status_not_running_msg"
    fi
    echo "${status_clash_version_msg}${version}"
    echo "${status_sub_name_msg}${sub_name}"
    echo "${status_auto_start_msg}${autostart}"
    if is_proxy;then
        echo "${status_proxy_msg}true"
        for key in $proxy_keys 'no'; do
            proxy_key="${key}_proxy"
            echo "    $proxy_key=$(eval "echo \${$proxy_key}")"
        done
    else
        echo "${status_proxy_msg}false"
        
    fi
    clash_ui_link_info
    echo "${status_clash_path_msg}${clash_path}"
}

# 函数：显示当所有订阅
list() {
    names=$(get_subscribe_config '' 'names')
    echo "$names" | tr ',' '\n' | while IFS= read -r name; do
        if [ -n "$name" ]; then
            url=$(get_subscribe_config "$name" "url")
            interval=$(get_subscribe_config "$name" "interval")
            echo ""
            echo "      $name"
            echo "====================="
            echo "${list_sub_url_msg}${url}"
            echo "${list_sub_update_interval_msg}${interval}"
            echo "====================="
        fi
    done
}

# 函数：校验配置文件
# 参数：$1:file 文件路径
check_conf(){
    file=$1
    expected="configuration file $file test is successful"
    req=$(${mysudo}$clash_path -t -f "$file")
    # 提取最后一行输出的记录
    last_line=$(echo "$req" | awk 'END {print}')
    # 检查最后一行文本是否匹配期望的文本
    if [ "$last_line" != "$expected" ]; then
        failed "$conf_failed_msg
        $req"
    fi
}

# 函数：添加订阅
# 参数: $1：input - 订阅信息 格式《订阅名称::订阅地址(或本地文件路径)::订阅更新时间（小时,可为空）》
add(){
    input=$1
    name=$(echo "${input}" | awk -F '::' '{print $1}')
    url=$(echo "${input}" | awk -F '::' '{print $2}')
    interval=$(echo "${input}" | awk -F '::' '{print $3}')
    # 验证参数
    if [ -z "$name" ] || [ -z "$url" ]; then
        failed "$add_sub_parameter_failed_msg"
    fi
    # 判断url是否是网址
    if  [ "${url#http}" != "$url" ]; then
        check_url "$url"
        # 下载配置
        download_sub "$name" "$url"
        if [ -z "$interval" ];then
            interval=0
        fi
        if existence_subscrib_config "$name"; then
            # 更新配置
            set_subscribe_config "$name" 'url' "$url"
            set_subscribe_config "$name" 'interval' "$interval"
            success "$update_sub_success_msg"
        else
            # 创建配置
            add_subscribe_config "$name" "$url" "$interval"
            success "$add_sub_success_msg"
        fi
        # 更新配置定时任务
        auto_update_sub '' "$name"
    else
        # 判断本地是否存在此文件
        if [ ! -f "$url" ];then
            failed "$not_sub_exists_msg"
        fi
        # 校验配置文件
        check_conf "$url"
        # 复制文件到配置目录
        mycp "$url" "${subscribe_dir}/${name}.yaml"
        # 如果配置文件不存在此信息则添加
        if ! existence_subscrib_config "${name}"; then
            add_subscribe_config "$name" "" "0"
            success "$add_sub_success_msg"
        else
            success "$update_sub_success_msg"
        fi
    fi
}

# 函数：删除订阅
# 参数: $1：sub_name - 订阅名称
del() {
    sub_name=$1
    if existence_subscrib_config "${sub_name}"; then

        # 关闭自动更新定时任务
        set_subscribe_config "$sub_name" "$interval" '0'
        auto_update_sub '' "${sub_name}"

        # 删除订阅配置信息
        del_subscribe_config "${sub_name}"
        # 删除下载订阅文件
        if [ -f "${subscribe_dir}/${sub_name}.yaml" ]; then
            myrm -rf "${subscribe_dir}/${sub_name}.yaml"
        fi
        # 判断当前订阅是否正在使用
        use=$(get_subscribe_config '' 'use')
        if [ "$use" = "${sub_name}" ]; then
            # 设置订阅配置为default
            set_subscribe_config '' 'use' 'default'
            # 重载配置
            if $state; then
                reload "default"
            fi
        fi
        success "$delete_sub_success_msg"
    else
        failed "$not_sub_exists_msg"
    fi
}

# 函数：更新订阅
# 参数: $1：sub_name - 订阅名称或all（可为空）， 默认为当前使用订阅
update_sub() {
    sub_name=$1
    # 是否更新所有订阅
    if [ "${sub_name}" = "all" ]; then
        # 更新所有订阅配置
        names=$(get_subscribe_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                download_sub "${name}"
            fi
        done
    else
        # 当前使用配置文件
        use=$(get_subscribe_config '' 'use')
        # 更新当前使用配置
        if [ -z "${sub_name}" ]; then
            if [ "$use" = "default" ];then
                warn "$update_default_sub_failed_msg"
            fi
            download_sub "${use}"
        else
            # 更新指定订阅配置
            if existence_subscrib_config "${sub_name}"; then
                download_sub "${sub_name}"
            else
                failed "$not_sub_exists_msg"
            fi
        fi
    fi
    success "$update_sub_success_msg"
    # 重载配置文件
    if $state; then
        reload "$use"
    fi
}

# 
# 函数：下载订阅配置
# 参数: 
#   $1：name - 订阅名称
#   $2: url - 订阅地址 可为空，自动获取配置中url
download_sub() {
    name=$1
    url=${2:-$(get_subscribe_config "${name}" "url")}
    if [ -z "$url" ];then
        warn "$update_local_sub_failed_msg"
    else
        # 获取下载地址
        temp_sub_path="${subscribe_dir}/${name}.new.yaml"
        # 下载订阅文件
        download "${temp_sub_path}" "${url}" "${name}" $sub_proxy
        # 检查订阅文件是否有效
        check_conf "$temp_sub_path"
        # 备份原先订阅
        mymv "${subscribe_dir}/${name}.yaml" "${subscribe_backup_dir}/${name}$(date +'%Y%m%d%H%M').yaml"
        # 重命名订阅文件
        mymv "${temp_sub_path}" "${subscribe_dir}/${name}.yaml"
    fi
}

# 函数：设置自动更新订阅
# 参数：$1：enable - 设置自动更新总开关，默认根据配置文件重新设置
#      $2：sub_name - 订阅名称（可选），默认根据配置文件重新设置全部
auto_update_sub() {
    enable=$1
    sub_name=$2
    if [ "$enable" = 'true' ];then
        set_clashtool_config "autoUpdateSub" 'true'
        success $auto_update_sub_success_msg
    elif [ "$enable" = 'false' ];then
        set_clashtool_config "autoUpdateSub" 'false'
        success $auto_update_sub_success_msg
    elif [ "$enable" = '' ];then
        enable=$(get_subscribe_config 'autoUpdateSub')
    else
        failed $verify_failed_msg
    fi
    # 判断是否存在订阅配置
    if [ -n "$sub_name" ] && ! existence_subscrib_config "$sub_name"; then
        failed "$not_sub_exists_msg"
    fi
    if [ -z "$sub_name" ]; then
        # 为空则根据配置和enable重新设置全部定时任务
        names=$(get_subscribe_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                interval=$(get_subscribe_config "$name" 'interval')
                if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
                    crontab_tool '' "$script_path update_sub ${name} >> ${logs_dir}/crontab.log 2>&1"
                else
                    crontab_tool "0 */$interval * * *" "$script_path update_sub ${name} >> ${logs_dir}/crontab.log 2>&1"
                fi
            fi
        done
    else
        interval=$(get_subscribe_config "$sub_name" 'interval')
        # 设置指定定时任务
        if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
            crontab_tool '' "$script_path update_sub ${sub_name} >> ${logs_dir}/crontab.log 2>&1"
        else
            crontab_tool "0 */$interval * * *" "$script_path update_sub ${sub_name} >> ${logs_dir}/crontab.log 2>&1"
        fi
    fi
}

# 函数：获取服务文件路径
get_service_file(){
    case "$(get_linux_distribution)" in
        "alpine")
            echo "/etc/init.d/${service_name}"
            ;;
        "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
            echo "/etc/systemd/system/${service_name}.service"
            ;;
    esac
}

# 函数：创建systemctl服务文件
create_service_file(){
    service_file="$(get_service_file)"
    case "$(get_linux_distribution)" in
        "alpine") 
            if [ ! -f "$service_file" ];then
                {
                    echo "#!/sbin/openrc-run"
                    echo "name=\"$service_name\""
                    echo "description=\"$service_name Service\""
                    echo ""
                    echo "command=\"$script_path\""
                    echo "command_args=\"start\""
                    echo "command_background=\"true\""
                    echo ""
                    echo "depend(){"
                    echo "    after network"
                    echo "}"
                    echo ""
                    echo "start() {"
                    echo "    \$command start"
                    echo "}"
                    echo ""
                    echo "stop() {"
                    echo "    \$command stop"
                    echo "}"
                } | mytee "$service_file" >/dev/null
                mychmod +x "$service_file"
            fi
            ;;
        "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
            if [ ! -f "$service_file" ];then
                {
                    echo "[Unit]"
                    echo "Description=$service_name Service"
                    echo "After=network.target"
                    echo ""
                    echo "[Service]"
                    echo "ExecStart=$script_path start"
                    echo "Restart=always"
                    echo "User=root"
                    echo ""
                    echo "[Install]"
                    echo "WantedBy=multi-user.target"
                } | mytee "$service_file" >/dev/null
                mychmod +x "$service_file"
            fi
            ;;
        *)
            failed "$unsupported_linux_distribution_failed_msg"
    esac
}

# 函数：删除服务脚本
del_service_file(){
    service_file=$(get_service_file)
    if [ -f "$service_file" ];then
        myrm -rf "$service_file"
    fi
}

# 函数：设置开机运行脚本 （由于各linux系统环境差异原因可能会无效）
# 参数: $1：enable - 是否启用开机运行 （可选），默认为 true（true/false）
auto_start() {
    # 是否开机运行
    enable=${1:-true}
    verify "$enable"
    linux_distribution=$(get_linux_distribution)
    # 启用或禁用开机运行
    if [ "$enable" = 'true' ];then
        # 
        case "$linux_distribution" in
            "alpine")
                myrcupdate add "$service_name" default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                mysystemctl enable "$service_name"
            ;;
        *)
            failed "$unsupported_linux_distribution_failed_msg"
        esac
        success "$auto_start_enabled_success_msg"
    else
        case "$linux_distribution" in
            "alpine")
                myrcupdate del $service_name default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                mysystemctl disable $service_name
                ;;
            *)
                failed "$unsupported_linux_distribution_failed_msg"
        esac
        success "$auto_start_turned_off_success_msg"
    fi
    set_clashtool_config 'autoStart' "$enable"
}

# 函数：开启系统代理
proxy_on() {
    if $state;then
        proxy_host="http://127.0.0.1"
        if grep -q 'mixed-port:' "$user_config_path"; then
            mixed_port=$(get_yaml_value 'mixed-port' "$user_config_path")
            http_port="$mixed_port"
            socks_port="$mixed_port"
        else
            http_port=$(get_yaml_value 'port' "$user_config_path")
            socks_port=$(get_yaml_value 'socks-port' "$user_config_path")
        fi
        # 检查 "$bashrc" 是否存在
        if [ ! -f "$bashrc" ]; then
            printf "" >> "$bashrc"
        fi
        # 循环添加或修改代理
        for key in $proxy_keys; do
            proxy_key="${key}_proxy"
            if [ $key = 'socks' ];then
                proxy_port="$socks_port"
            else
                proxy_port="$http_port"
            fi

            # 判断是否存在
            if grep -q "${proxy_key}=" "$bashrc"; then
                # 如果已存在，则进行修改
                sed -i "s|${proxy_key}=.*|${proxy_key}=${proxy_host}:${proxy_port}|" "$bashrc"
            else
                # 如果不存在，则添加设置
                echo "export ${proxy_key}=${proxy_host}:${proxy_port}" >> "$bashrc"
            fi
            # 如果安装proxychains则使用proxychains设置全局代理，安装桌面此处有用处
            if command -v proxychains >/dev/null 2>&1; then
                gsettings set org.gnome.system.proxy.${key} host $proxy_host
                gsettings set org.gnome.system.proxy.${key} port $proxy_port
            fi
        done
        # 添加或修改排除代理地址
        if grep -q "no_proxy=" "$bashrc"; then
            sed -i "s|no_proxy=.*|no_proxy=${proxy_no}|" "$bashrc"
        else
            echo "export no_proxy=$proxy_no" >> "$bashrc"      
        fi
        # 生效设置
        source $bashrc
        if command -v proxychains >/dev/null 2>&1; then
            gsettings set org.gnome.system.proxy ignore-hosts "[$(echo $proxy_no | sed "s/[^,]\+/'&'/g")]"
            gsettings set org.gnome.system.proxy mode 'manual'
        fi
        set_clashtool_config 'httpPort' "$http_port"
        set_clashtool_config 'socksPort' "$socks_port"
        success "$proxy_on_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 函数：关闭系统代理
proxy_off(){
    # 删除代理设置
    for key in $proxy_keys 'no'; do
        proxy_key="${key}_proxy"
        if [ -f "$bashrc" ];then
            sed -i "/${proxy_key}=/d" "$bashrc"
        fi
        unset "${proxy_key}"
    done
    # 生效设置
    source $bashrc
    if command -v proxychains >/dev/null 2>&1; then
        gsettings set org.gnome.system.proxy mode 'none'
    fi
	success "$proxy_off_success_msg"
}

# 函数：判断是否设置代理
is_proxy(){
    if command -v proxychains >/dev/null 2>&1 && [ "$(gsettings get org.gnome.system.proxy mode)" = "'manual'" ]; then
        return 0
    fi
    for key in $proxy_keys 'no'; do
        # 检查HTTPS代理设置
        if [ -n "$(eval "echo \$${key}_proxy")" ]; then
            eval "echo \$${key}_proxy"
            return 0
        fi
    done
    return 1
}

# 函数：设置系统代理
# 参数: $1：enable - 是否启用 （可选），默认为 true（true/false）
proxy(){
    enable=${1:-true}
    if [ "$enable" = "true" ];then
        if [ -f "${clash_path}" ]; then
            if $state ;then
                proxy_on
            else
                failed "$clash_not_running_warn_msg" false
            fi
        else
            failed "Clash $not_install_msg" false
        fi
    elif [ "$enable" = "false" ];then
        proxy_off
    else
        failed "$verify_failed_msg" false
    fi
}

# 函数：入口主函数
# 参数: 
#   $1：fun - 命令（详细看help）
#   $2：var - 参数（详细看help)
main() {
    fun=$1
    var=$2
    # 更新chinese参数设置是否汉化提示信息
    if $chinese;then
        chinese_language
    fi
    # 判断使用的命令类型
    if is_sourced;then
        if [ "$fun" = "proxy" ];then
            proxy "$var"
        else
            failed "$proxy_source_command_msg" false
        fi
    else
        case "${fun}" in
        "install"| "update_script")
            $fun "$var"
            ;;
        "uninstall"|"update"|"install_ui"|"uninstall_ui"|"update_ui"|"start"|"stop"|"restart"|"reload"|"add"|"list"|"del"|"update_sub"|"auto_update_sub"|"status"|"auto_start")
            if [ ! -d $clash_dir ];then
                failed $not_install_msg
            fi
            $fun "$var"
            ;;
        "proxy")
            failed "$proxy_not_source_command_msg" false
            ;;
        "help")
            echo "$help_msg"
            ;;
        *)
            echo "$main_msg"
            ;;
        esac 
    fi
}

# 执行主函数
main "$1" "$2"
