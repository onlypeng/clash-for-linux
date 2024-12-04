#!/bin/sh  
# version:1.2.0

# 网页初始链接密码，不填写则随机生成
secret=''
# clash架构，默认自动获取，获取失败请自行填写
platform=''
# 使用中文提示输出语言
chinese=true
# clash项目库
# https://github.com/MetaCubeX/mihomo/releases/download/v1.18.9/mihomo-linux-amd64-v1.18.9.gz
clash_repo='MetaCubeX/mihomo'
# clash download/后路径解析 可用变量 版本 :version: 架构 :platform:
clash_releases_file='v:version:/mihomo-linux-:platform:-v:version:.gz'
#Country.mmdb下载地址https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
# yacd UI项目
yacd_url='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'
# clash-dashboardUI项目
dashboard_url='https://github.com/ayanamist/clash-dashboard/archive/refs/heads/gh-pages.zip'
# 下在错误重试次数
max_retries=3
# 订阅使用github代理下载
sub_proxy=false
# github下载代理地址，clash和ui下载默认使用该代理,地址最后携带/
github_proxy="https://ghp.ci/"
# 设置代理的环境变量(一般为本机)
proxy_host="http://127.0.0.1"
proxy_keys="http https ftp socks"
proxy_no="localhost,127.0.0.1,::1"

# 以下变量不建议修改
service_name="clash"
# clash安装目录
clash_dir="/opt/${service_name}"
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
# 用户自定义配置文件
user_config_path="${config_dir}/user.yaml"
# clash tun模式使用的配置文件
gateway_config_path="${config_dir}/gateway.yaml"
# clashtool 配置文件
clashtool_config_path="${config_dir}/clashtool.ini"
# clash配置文件支持的多有变量
clash_config_keys="port socks-port redir-port tproxy-port mixed-port authentication allow-lan bind-address mode log-level ipv6 unified-delay external-controller global-client-fingerprint external-ui secret interface-name routing-mark hosts profile dns tun proxies proxy-groups proxy-providers tunnels rules"

# 保存当前clash程序运行状态
pid=$(pgrep -f "^$clash_path -d ${config_dir}$")
if [ -z "$pid" ]; then
    state=false
else
    state=true
fi
# Define menu and prompt text variables in English
menu_start="=============== Options ==============="
menu_main_option1="1. Clash Core Functions"
menu_main_option2="2. Clash UI Functions"
menu_main_option3="3. Clash Running Functions"
menu_main_option4="4. Clash Subscription Functions"
menu_main_option5="5. Clash Auto Start Settings"
menu_main_option6="6. Display Clash Information"
menu_main_option7="7. Update Current Clash Tool Script"
menu_main_option8="8. Proxy Settings, currently only supported via command"
menu_main_option9="9. Gateway Settings"
menu_main_help="9. Display Available Commands for Clash Tool"
menu_core="========= Clash Core Functions ========="
menu_core_option1="1. Install Clash Core"
menu_core_option2="2. Update Clash Core"
menu_core_option3="3. Uninstall Clash Core"
menu_core_option4="4. Uninstall Clash Core and Delete Configuration Files"
menu_ui="========= Clash UI Functions ========="
menu_ui_option1="1. Install/Switch Clash UI yacd"
menu_ui_option2="2. Install/Switch Clash UI dashboard"
menu_ui_option3="3. Update Clash UI"
menu_ui_option4="4. Uninstall Clash UI"
menu_subscription="========== Clash Subscription Functions =========="
menu_subscription_option1="1. Add Clash Subscription"
menu_subscription_option2="2. Modify Clash Subscription"
menu_subscription_option3="3. Delete Clash Subscription"
menu_subscription_option4="4. List All Subscriptions"
menu_subscription_option5="5. Update subscription profile"
menu_subscription_option6="6. Turn off automatic subscription renewal"
menu_subscription_option7="7. Turn on automatic subscription renewal"
menu_running="========== Clash Running Functions =========="
menu_running_option1="1. Start Clash"
menu_running_option2="2. Reload Clash Configuration File"
menu_running_option3="3. Stop Clash"
menu_running_option4="4. Restart Clash"
menu_autostart="=============== Auto Start Options ==============="
menu_autostart_option1="1. Enable Auto Start"
menu_autostart_option2="2. Disable Auto Start"
menu_gateway="================= Gateway Options ================="
menu_gateway_option1="1. Enable Gateway"
menu_gateway_option2="2. Disable Gateway"
menu_return="r. Return to Previous Menu"
menu_exit="q. Exit"
menu_end="==================================="
menu_invalid_choice="Invalid choice!"

# Prompt messages
prompt_choice_msg="Please choose an option (enter the number):"
prompt_version_msg="Enter the version number (default is the latest version):"
prompt_subscription_name_msg="Enter the subscription name:"
prompt_subscription_url_msg="Enter the subscription URL:"
prompt_subscription_update_msg="Enter the subscription auto-update interval (in hours):"
not_root_execute_msg="Please run the script with sudo or as the root user."
verify_failed_msg="Parameter can only be true, false, or ''. Default is true."
unsupported_linux_distribution_failed_msg="Unsupported Linux distribution."
recognition_system_failed_msg="Unable to determine the current operating system architecture. Please specify the platform parameter."
was_install_msg="was installed"
not_install_msg="Not installed"
file_does_not_exist='The downloaded file does not exist'
install_start_msg="Starting installation"
install_success_msg="Installation successful"
install_failed_msg="Installation failed"
uninstall_start_msg="Starting uninstallation"
uninstall_success_msg="Uninstallation successful"
require_check_msg="Checking for dependencies"
require_install_failed_msg="Unable to recognize the package manager. Please install it manually."
init_config_start_msg="Initializing configuration file"
init_config_success_msg="Configuration file initialized successfully"
migrate_config_success_msg="Configuration file migrated successfully"
download_start_msg="Starting download"
download_waiting_msg="Download failed. Waiting 5 seconds before the next attempt..."
download_success_msg="Download successful"
download_failed_msg="Download failed"
download_path_msg="Download Path:"
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
clash_reload_failed_msg="Clash configuration reloaded failed"
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
status_gateway_msg="gateway status:"
status_clash_address_msg="Clash access address:"
status_clash_secret_msg="Clash access token:"
status_clash_ui_address_msg="ClashUI access address:"
list_sub_url_msg="Subscription address:"
list_sub_update_interval_msg="Update interval:"
proxy_port_update_msg="Detected that Clash http proxy port has changed and proxy is enabled. Please reset the proxy."
proxy_enable_reminder_msg="Detected agent on, please pay attention to closing it"
proxy_enable_faile_msg="Detected that proxy is enabled. Please disable proxy before uninstalling."
proxy_source_command_msg="Do not use source to execute commands other than 'proxy'."
proxy_not_source_command_msg="Please use source to execute the 'proxy' command."
proxy_on_success_msg="Proxy enabled"
proxy_off_success_msg="Proxy disabled"
gateway_enable_success_msg="Gateway enabled success"
gateway_disable_success_msg="Gateway disabled success"
gateway_set_failed_msg="Gateway set failed"
confg_key_error_msg="Variable does not exist"

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
    auto_update_sub  true or false                        Turn automatic update subscription on or off.
    list             None                     Optional    List all subscription information.
    auto_start       true or false            Optional    Enable or disable auto-start on boot (defaults to true).
    status           None                     Optional    View Clash-related information.
    proxy            true or false            Optional    Enable or disable proxy (defaults to true); this command must be executed using 'source'.
    gateway          true or false            Optional    Enable or disable gateway (defaults to true)."
main_msg="Invalid command. Type 'help' to view available commands."

# 函数：中文提示函数
chinese_language(){
    # 定义菜单和提示文本的变量
    menu_start="=============== 选项 ==============="
    menu_main_option1="1.Clash核心相关功能"
    menu_main_option2="2.ClashUI相关功能"
    menu_main_option3="3.Clash运行相关功能"
    menu_main_option4="4.Clash订阅相关功能"
    menu_main_option5="5.Clash自动启动设置"
    menu_main_option6="6.显示Clash相关信息"
    menu_main_option7="7.更新当前Clash工具脚本"
    menu_main_option8="8.代理设置，目前只支持命令设置"
    menu_main_option9="9.网关设置相功能"
    menu_main_help="h.显示clash工具命令方式可使用的命令"
    menu_core="========= Clash核心相关功能 ========="
    menu_core_option1="1. 安装Clash核心"
    menu_core_option2="2. 更新Clash核心"
    menu_core_option3="3. 卸载Clash核心"
    menu_core_option4="4. 卸载Clash核心，并删除配置文件"
    menu_ui="========= ClashUI相关功能 ========="
    menu_ui_option1="1. 安装/切换ClashUI yacd"
    menu_ui_option2="2. 安装/切换ClashUI dashboard"
    menu_ui_option3="3. 更新ClashUI"
    menu_ui_option4="4. 卸载ClashUI"
    menu_subscription="========== Clash订阅相关功能 =========="
    menu_subscription_option1="1. 添加Clash订阅"
    menu_subscription_option2="2. 修改Clash订阅"
    menu_subscription_option3="3. 删除Clash订阅"
    menu_subscription_option4="4. 列出所有订阅"
    menu_subscription_option5="5. 更新订阅配置文件(名称all为更新全部)"
    menu_subscription_option6="6. 关闭订阅自动更新"
    menu_subscription_option7="7. 开启订阅自动更新"
    menu_running="========== Clash运行相关功能 =========="
    menu_running_option1="1. 启动Clash"
    menu_running_option2="2. 重载Clash配置文件"
    menu_running_option3="3. 停止Clash"
    menu_running_option4="4. 重新启动Clash"
    menu_autostart="=============== 开机自启动选项 ==============="
    menu_autostart_option1="1. 启动开机自起"
    menu_autostart_option2="2. 关闭开机自起"
    menu_end="==================================="
    menu_gateway="================= 网关选项 ================="
    menu_gateway_option1="1. 启动网关"
    menu_gateway_option2="2. 禁用网关"
    menu_return="r. 返回上级"
    menu_exit="q.退出"
    menu_end="==================================="
    menu_invalid_choice="无效的选择！"

    # 提示信息
    prompt_choice_msg="请选择操作（输入编号,Ctrl+C直接退出）："
    prompt_version_msg="请输入版本号(默认最新版本)："
    prompt_subscription_name_msg="输入订阅名称："
    prompt_subscription_url_msg="输入订阅地址："
    prompt_subscription_update_msg="输入订阅自动更新时间（单位小时）："
    not_root_execute_msg="请使用sudo或root用户执行脚本"
    verify_failed_msg="参数只能是true、false 或 ''， ''默认为true"
    unsupported_linux_distribution_failed_msg="不支持的Linux发行版"
    recognition_system_failed_msg="无法确定当前操作系统架构类型。请自行填写platform参数"
    conf_failed_msg="配置文件错误"
    latest_version_msg="最新版本："
    current_version_msg="当前版本："
    was_install_msg="已安装"
    not_install_msg="未安装"
    file_does_not_exist='下载的文件不存在'
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
    migrate_config_success_msg="配置文件迁移成功"
    download_start_msg="开始下载"
    download_waiting_msg="下载失败，等待5秒后进行下一次尝试..."
    download_success_msg="下载成功"
    download_failed_msg="下载失败"
    download_path_msg="下载地址："
    get_version_failed_msg="获取版本失败"
    install_equal_versions_warn_msg="新安装版本与当前版本相同"
    install_ui_parameter_failed_msg="参数错误，只能为 dashboard 或 yacd，默认为当前安装版本"
    clash_running_warn_msg="Clash服务已运行"
    clash_not_running_warn_msg="Clash服务未启动"
    clash_start_msg="正在启动Clash服务"
    clash_start_success_msg="Clash服务启动成功"
    clash_start_failed_msg="Clash服务启动失败"
    clash_reload_success_msg="Clash重载配置成功"
    clash_reload_failed_msg="Clash重载配置失败"
    clash_stop_success_msg="Clash服务停止成功"
    clash_yaml_failed_msg="配置文件错误"
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
    status_gateway_msg="本机网关状态："
    status_clash_address_msg="Clash访问地址："
    status_clash_secret_msg="Clash访问令牌："
    status_clash_ui_address_msg="ClashUI访问地址："
    list_sub_url_msg="订阅地址："
    list_sub_update_interval_msg="更新间隔："
    proxy_port_update_msg="检测到Clash http代理端口已更改并已开启代理,请重新设置代理"
    proxy_enable_reminder_msg="检测到代理开启，请注意关闭"
    proxy_enable_faile_msg="检测到代理已开启，关闭代理后再重新卸载"
    proxy_source_command_msg="不要使用source执行除proxy其他命令"
    proxy_not_source_command_msg="请使用source执行proxy命令"
    proxy_on_success_msg="代理已开启"
    proxy_off_success_msg="代理已关闭"
    gateway_enable_success_msg="网关启用成功"
    gateway_disable_success_msg="网关禁用成功"
    gateway_set_failed_msg="网关设置失败"
    confg_key_error_msg="变量不存在"
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
    proxy           true或false      可为空     启用或禁用本机代理，默认为true，此命令需要使用source运行
    gateway         true或false      可为空     启用或禁用网关，默认为true"
    main_msg="无效命令，相关命令输入help进行查看"
}

# 函数：判断指定节是否存在
# 参数：
#   $1: file - 文件名
#   $2: section - 指定节
section_exists() {
    file=$1
    section=$2
    grep -q "^\[$section\]$" "$file"
    return $?
}

# 函数：添加或修改INI配置文件
# 参数：
#   $1: section - 指定节
#   $2: key - 变量名
#   $3: value - 值
#   $4: file - 文件名
update_ini() {
    section=$1
    key=$2
    value=$3
    file=$4
    temp_file=$(mktemp)
    awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section = 0; key_written = 0 }
    /^\s*\[.*\]/ {
        if (in_section && !key_written) {
            print key "=" value
            key_written = 1
        }
        in_section = ($0 == "[" section "]")
    }
    in_section && $1 ~ key"=" {
        $0 = key "=" value
        key_written = 1
    }
    { print }
    END {
        if (!key_written && in_section) {
            print key "=" value
        } else if (!key_written) {
            print "[" section "]"
            print key "=" value
        }
    }' "$file" > "$temp_file"

    mv "$temp_file" "$file"
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
    temp_file=$(mktemp)

    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^\s*\[.*\]/ { 
        in_section = ($0 == "[" section "]")
    }
    !(in_section && $1 ~ key"=") {
        print
    }' "$file" > "$temp_file"

    mv "$temp_file" "$file"
}

# 函数：获取INI配置文件
# 参数：
#   $1: file - 文件名
#   $2: section - 指定节
#   $3: key - 变量名
find_ini() {
    section=$1
    key=$2
    file=$3
    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^\s*\[.*\]/ { 
        in_section = ($0 == "[" section "]") 
    }
    in_section && $1 ~ key"=" {
        gsub(/^[ \t]+|[ \t]+$/, "", $0) # 去掉前后空格
        split($0, kv, "=")
        if (kv[1] == key) {
            print kv[2]
            exit
        }
    }' "$file"
}

# 函数：获取clashtool配置
# 参数：$1: key - 变量名
find_clashtool_config() {
    key=$1
    find_ini 'clashtool' "${key}" "${clashtool_config_path}"
}

# 函数：添加或更改clashtool配置文件
# 参数：
#   $1: key - 变量名
#   $2: val - 值
update_clashtool_config() {
    key=$1
    val=$2
    update_ini "clashtool" "${key}" "${val}" "${clashtool_config_path}"
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
update_subscribe_config() {
    sec_name=$1
    key=$2
    val=$3
    if [ -z "$sec_name" ]; then
        sec="subscribe"
    else
        sec="subscribe_$sec_name"
    fi
    update_ini "$sec" "$key" "$val" "$clashtool_config_path"
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
    } >> "$clashtool_config_path"
    # 更新names名称
    names=$(find_subscribe_config '' 'names')${name}','
    update_subscribe_config '' 'names' "${names}"
}

# 函数：删除订阅
# 参数：$1: name - 订阅名称
delete_subscribe_config() {
    name=$1
    # 更新names
    names=$(find_subscribe_config '' 'names' | sed "s/${name},//g")
    update_subscribe_config '' 'names' "$names"
    # 删除订阅节点
    delete_ini "subscribe_$name" '' "${clashtool_config_path}"
}

# 获取订阅配置
# 函数：添加订阅配置
# 参数：
#   $1: name - 订阅名称
#   $2: key - 变量名
find_subscribe_config() {
    name=$1
    key=$2
    if [ -z "${name}" ]; then
        sec="subscribe"
    else
        sec="subscribe_${name}"
    fi
    find_ini "${sec}" "${key}" "${clashtool_config_path}"
}

# 函数：获取用户Clash配置
# 参数：
#   $1: key - 订阅名称
#   $2: file - 订阅文件
find_clash_config(){
    key="$1"
    sed -n "/^${key}:/,/^[[:alnum:]]/{s/^${key}:[[:space:]]\{0,1\}//p;t end;/^[[:alnum:]]/!p;:end}" "$user_config_path"
}

# 函数：添加或修改用户Clash配置
# 参数：
#   $1: key - 订阅名称
#   $2: val - 订阅值
update_clash_config() {
    key="$1"
    value="$2"
    temp_file="$(mktemp)"
    for temp_key in $clash_config_keys; do
        if [ "$temp_key" = "$key" ] && [ -n "$value" ]; then
            # 如果新值不为空，则更新临时文件中的值
            echo "${temp_key}: ${value}" >> "$temp_file"
        elif grep -Eq "^${temp_key}:" "$user_config_path"; then
            # 如果原文件存在则把相关信息复制到临时文件
            sed -n "/^${temp_key}:/,/^[[:alnum:]]/{/^${temp_key}:/p; /^[[:alnum:]]/!p}" $user_config_path >> "$temp_file"
        fi
    done
    check_conf "$temp_file"
    mv "$temp_file" "$user_config_path"
}

# 函数：删除用户Clash配置
# 参数：
#   $1: key - 订阅名称
delete_clash_config() {
    key="$1"
    # 使用 sed 删除键的范围，不包括终点行
    sed -i "/^${key}:/,/^[[:alnum:]]/{/^${key}:/d;/^[[:alnum:]]/!d}" "$user_config_path"
}

# 函数：合并用户和订阅的Clash配置
merge_clash_config() {
    sub_config_path="$1"
    gateway_status=$(find_clashtool_config "gateway")
    temp_file="$(mktemp)"
    for temp_key in $clash_config_keys; do
        if grep -Eq "^${temp_key}:" "$user_config_path"; then
            sed -n "/^${temp_key}:/,/^[[:alnum:]]/{/^${temp_key}:/p; /^[[:alnum:]]/!p}" $user_config_path >> "$temp_file"
        elif [ "$gateway_status" = "true" ] && grep -Eq "^${temp_key}:" "$gateway_config_path"; then
            sed -n "/^${temp_key}:/,/^[[:alnum:]]/{/^${temp_key}:/p; /^[[:alnum:]]/!p}" $gateway_config_path >> "$temp_file"
        elif grep -Eq "^${temp_key}:" "$sub_config_path"; then
            sed -n "/^${temp_key}:/,/^[[:alnum:]]/{/^${temp_key}:/p; /^[[:alnum:]]/!p}" $sub_config_path >> "$temp_file"
        fi
    done
    check_conf "$temp_file"
    mv "$temp_file" "$config_path" 
}

# 通用消息函数
# 参数：
#   $1: color_code - 状态颜色码
#   $2: status - 状态文本（OK/FAILED/WARN/REMIND/NORMAL）
#   $3: msg - 消息
#   $4: is_exit - 是否退出脚本 (true/false)，默认 false
message() {
    color_code="$1"
    status="$2"
    msg="$3"
    is_exit="${4:-false}"
    # 使用 printf 格式化输出：状态码 消息，设置符号和对齐
    printf "\033[1;${color_code}m[%s]\033[0m %-60s\n" "$status" "$msg"
    $is_exit && exit 0
}

# 失败消息
failed() { message "31" "✖ FAILED" "$1" "${2:-true}"; }

# 警告消息
warn() { message "33" "⚠ WARN" "$1" "${2:-true}"; }

# 提醒消息
remind() { message "36" "ℹ REMIND" "$1" "${2:-false}"; }

# 成功消息
success() { message "32" "✔ OK" "$1" "${2:-false}"; }

# 正常消息（无状态符号和颜色）
normal() { message "0" "INFO" "$1" "${2:-false}"; }

# 函数：输出UI链接相关信息
clash_ui_link_info(){
    ips=$(ip -o -4 addr show | awk '!/127.0.0.1/ {print $4}' | cut -d'/' -f1)
    port=$(find_clash_config "external-controller" | awk -F ':' '{print $2}')
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
    normal "$sub_url_check_msg"
    if $sub_proxy;then
        curl -sSf --max-time 30 "${github_proxy}${url}" > /dev/null
    else
        curl -sSf --max-time 30 "$url" > /dev/null
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

# 函数：获取下载文件名称
get_download_filename() {
    url="$1"
    # 尝试从URL中提取文件名
    filename=$(basename "$url")
    # 如果无法从URL中提取文件名，则获取文件头信息
    if [ -z "$filename" ]; then
        headers=$(curl -sI "$url")
        filename=$(echo "$headers" | grep -i 'Content-Disposition' | sed -e 's/.*filename=//')
        filename="${filename%\"}"
        filename="${filename#\"}"
    fi
    echo "$filename"
}

# 函数：设置定时任务
# 参数：
#   $1: interval - 运行时间，为空则删除定时任务
#   $2: command - 需要执行的命令
crontab_tool() {
    interval=$1
    command=$2
    # 读取当前的 crontab
    current_crontab=$(crontab -l 2>/dev/null)

    if [ -z "$interval" ]; then
        # 删除定时任务
        if echo "$current_crontab" | grep -qF "$command"; then
            echo "$current_crontab" | grep -vF "$command" | crontab -
        fi
    else
        # 添加或修改定时任务
        if echo "$current_crontab" | grep -qF "$command"; then
            # 定时任务已存在，修改
            current_crontab=$(echo "$current_crontab" | sed -e "\|$command|d")
        fi
        # 添加或更新定时任务
        (
            echo "$current_crontab"
            echo "$interval $command"
        ) | crontab -
    fi
}

# 函数：安装依赖程序
# 参数：$1:name 程序名称
install_procedure(){
    name="$1"
    # 检查并安装
    if ! command -v "$name" >/dev/null 2>&1; then
        echo "${install_start_msg} $name"
        if command -v apt >/dev/null 2>&1; then
            apt install "$name" -y
        elif command -v yum >/dev/null 2>&1; then
            yum install "$name" -y
        elif command -v dnf >/dev/null 2>&1; then
            dnf install "$name" -y
        elif command -v zypper >/dev/null 2>&1; then
            zypper install "$name" -y    
        elif command -v apk >/dev/null 2>&1; then
            apk add "$name"
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

# 函数：解压常用压缩文件到指定目录
decompression() {
    archive_file="$1"
    destination="$2"

    # 检测输出目录，不存在则创建ss
    if [ ! -d "$destination" ]; then
        mkdir -p "$destination"
    fi

    # 使用 case 语句来匹配文件后缀
    case "$archive_file" in
        *.tar.gz)
            tar -xzf "$archive_file" -C "$destination"
            ;;
        *.tar)
            tar -xf "$archive_file" -C "$destination"
            ;;
        *.gz)
            gunzip -ck "$archive_file" > "$destination/$(basename "$archive_file" .gz)"
            ;;
        *.zip)
            unzip -q "$archive_file" -d "$destination"
            ;;
        *.rar)
            unrar x "$archive_file" "$destination"
            ;;
        *.7z)
            7z x "$archive_file" -o"$destination"
            ;;
        *.bz2)
            bunzip2 -ck "$archive_file" > "$destination/$(basename "$archive_file" .bz2)"
            ;;
        *)
            failed "Unsupported archive format: $archive_file"
            ;;
    esac
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
            platform="arm64"
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
        distribution="ubuntu"
    elif [ -f /etc/debian_version ];then
        distribution="debian"
    elif [ -f /etc/arch-release ]; then
        distribution="arch"
    elif [ -f /etc/centos-release ]; then
        distribution="centos"
    elif [ -f /etc/redhat-release ];then
        distribution="redhat"
    elif [ -f /etc/alpine-release ];then
        distribution="alpine"
    else
        failed $unsupported_linux_distribution_failed_msg
    fi
    echo "$distribution"
}

# 函数：检查并安装依赖
require() {
    normal "$require_check_msg"
    # 检查并安装tar
    install_procedure tar
    # 检查并安装curl
    install_procedure curl
    # 检查安装unzip，竟然有linux没预安装
    install_procedure unzip
    # 检查安装unzip，竟然有linux没预安装
    install_procedure gunzip
}
# 函数：初始化配置
init_config() {
    normal "$init_config_start_msg"
    
    # 检查并创建 clash 目录
    if [ ! -d $clash_dir ]; then
        mkdir -p "${clash_dir}"
    fi
    
    # 检查并创建配置目录
    if [ ! -d $config_dir ]; then
        mkdir -p "${config_dir}"
    fi
    
    # 检查并创建 logs 目录
    if [ ! -d $logs_dir ]; then
        mkdir -p "${logs_dir}"
    fi
    
    # 检查并创建 subscribe 配置目录
    if [ ! -d $subscribe_dir ]; then
        mkdir -p "${subscribe_dir}"
    fi
    
    # 检查并创建 subscribe_backup_dir 目录
    if [ ! -d $subscribe_backup_dir ]; then
        mkdir -p "${subscribe_backup_dir}"
    fi
    
    # 检查并创建 clashtool 配置文件
    if [ ! -f $clashtool_config_path ]; then
        cat <<EOF > "${clashtool_config_path}"
[clashtool]
ui=dashboard
version=
gateway=false
auto_start=false
auto_update_sub=true
http_port=7890
socks_port=7891
[subscribe]
names=
use=default
EOF
    fi
    
    # 检查并创建默认用户自定义的 clash 配置文件
    if [ ! -f $user_config_path ]; then
        # 未自定义网页密码则产生随机密码
        if [ -z "$secret" ]; then
            secret=$(tr -dc a-zA-Z0-9#@ 2>/dev/null < /dev/urandom | head -c 12)
        fi
        cat <<EOF > "${user_config_path}"
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: error
external-controller: 0.0.0.0:9090
secret: ${secret}
EOF
    fi
    # 检查并创建默认tun模式的clash 配置文件
    if [ ! -f $gateway_config_path ]; then
        cat <<EOF > "${gateway_config_path}"
tun:
  enable: true
  stack: system
  dns-hijack:
    - any:53
  auto-route: true
  # auto-redir: true
  auto-detect-interface: true
dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 114.114.114.114
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
EOF
    fi
    # 检查并下载 Country.mmdb 文件
    if [ ! -f "${config_dir}/Country.mmdb" ]; then
        echo "Country.mmdb文件不存在"
        api_url="https://api.github.com/repos/Dreamacro/maxmind-geoip/releases/latest"
        country_version=$(curl -k -s "$api_url" | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':v' '{print $2}')
        country_version=${country_version:-"20241012"}
        download "${config_dir}/Country.mmdb" "https://github.com/Dreamacro/maxmind-geoip/releases/download/${country_version}/Country.mmdb" "Country.mmdb" true
    fi
    success "$init_config_success_msg"
}

# 函数：根新配置
update_config(){
    # 备份用户配置文件
    cp -r $config_dir "${config_dir}.bak"
    # 重命名用户文件
    mv $config_path "$user_config_path"
    # 重新初始化文件，补全缺少的网关配置
    init_config
    # 更改clashtool脚本部分配置文件
    sed -i "s/^httpPort=/http_port=/" $clashtool_config_path
    sed -i "s/^socksPort=/socks_port=/" $clashtool_config_path 
    sed -i "s/^autoStart=/auto_start=/" $clashtool_config_path 
    sed -i "s/^autoUpdateSub=/auto_update_sub=/" $clashtool_config_path 
    sed -i '/^\s*$/d' $clashtool_config_path
    update_clashtool_config 'gateway' "false"
    # 重新创建服务文件解决使用系统服务启动时无法使用脚本结束
    del_service_file
    create_service_file
    success "$migrate_config_success_msg"
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
    normal "${download_start_msg}${tag}"
    # 关闭本shell进程代理
    if is_proxy;then
        for key in $proxy_keys 'no'; do
            unset "${key}_proxy"
        done
    fi
    # 设置github代理
    if [ "$enable" = "true" ];then
        url="${github_proxy}${url}"
    fi
    # 重试计数
    retry_count=0
    # 使用curl下载文件
    while [ $retry_count -lt $max_retries ]; do
        curl ${url} -o "$file_path"
        # 检查curl命令的退出状态为0并且下载的文件存在
        if [ $? -eq 0 ] && [ -f "$file_path" ] && [ $(stat -c%s "$1") -gt 1024 ]; then
            success "${tag}${download_success_msg}"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                normal "$download_waiting_msg"
                sleep 5
            else
                normal "${download_path_msg}${url}"
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
    current=$(find_clashtool_config 'version')
    if [ -n "$current" ];then
        normal "${current_version_msg}${current}"
    fi
    # 没有指定版本则更新最新版本
    if [ -z "$version" ]; then
        # 获取clash最新版本号
        api_url="https://api.github.com/repos/${clash_repo}/releases/latest"
        version=$(curl -k -s $api_url | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':v' '{print $2}')
        if [ -z "$version" ]; then
            failed "$get_version_failed_msg"
        fi
    fi
    # 要安装的版本
    normal "${latest_version_msg}${version}"
    # 判断版本是否相等
    if [ "${current}" = "${version}" ]; then
        warn "$install_equal_versions_warn_msg"
    fi
    temp_clash_releases_file=$(echo "$clash_releases_file" | sed "s/:platform:/${platform}/g" | sed "s/:version:/${version}/g")
    clash_url="https://github.com/${clash_repo}/releases/download/${temp_clash_releases_file}"
    download_name=$(get_download_filename "$clash_url")
    temp_clash_path="${clash_dir}/${download_name}"
    # 下载clash
    download "${temp_clash_path}" "$clash_url" "$download_name"
    normal "${install_start_msg} Clash"
    # 解压clash
    temp_clash_dir="${clash_dir}/temp_clash"
    decompression "$temp_clash_path" "$temp_clash_dir"
    # 查找clash文件
    find_result=$(find "$temp_clash_dir" -type f \( -name "*clash*" -o -name "*mihomo*" \) -print)
    if [ -z "$find_result" ]; then
        # 删除下载和解压缩的文件
        rm -rf "$temp_clash_path"
        rm -rf "$temp_clash_dir"
        failed "${file_does_not_exist} clash"
    fi
    # 重命名clash
    mv "$find_result" "$clash_path"
    # 删除下载的压缩文件
    rm -rf "$temp_clash_path"
    # 删除解压的文件
    rm -rf "$temp_clash_dir"
    # 赋予运行权限
    chmod +x "$clash_path"
    # 向clash配置文件写入当前版本
    update_clashtool_config 'version' "$version"
}

clear(){
    # 如果已安装则报错
    if [ -f "$clash_path" ];then
        failed "Clash $was_install_msg"
    fi
    # 如果存在残余则清零
    if [ -d "$clash_dir" ];then
        rm -rf "$clash_dir"
    fi
}

# 函数：安装clash内核
# 参数: $1：version - clash版本 （可为空），默认为最新版本
install() {
    version=$1
    # 如果已安装则报错
    if [ -f "$clash_path" ];then
        failed "Clash $was_install_msg"
    fi
    # 检测安装依赖软件
    require
    # 创建服务脚本
    create_service_file
    # 初始化目录配置
    init_config
    # 复制当前脚本到安装目录
    cp "$(readlink -f "$0")" "$script_path"
    # 下载安装clash
    download_clash "${version}"
    success "Clash $install_success_msg"
}

# 函数：卸载clash
# 参数: $1：all -（可为空），默认不删除配置信息
uninstall() {
    all=$1
    # 开始删除clash
    normal "$uninstall_start_msg Clash"
    # 关闭clash
    if $state; then
        stop
    fi
    # 关闭自动启动
    if [ "$(find_clashtool_config 'auto_start')" = 'true' ];then
        auto_start false
    fi
    # 关闭自动更新订阅
    if [ "$(find_clashtool_config 'auto_update_sub')" = 'true' ];then
        auto_update_sub false
    fi
    # 删除服务脚本
    del_service_file

    # 删除Clash所有相关文件
    if [ "$all" = "all" ];then
        rm -rf "${clash_dir}"
    else
        rm "$clash_path"
        # 向clash配置文件写入版本为空
        update_clashtool_config 'version' ""
    fi
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
        ui_name=$(find_clashtool_config 'ui')
    fi
    # 下载UI安装包
    if [ "${ui_name}" = "dashboard" ]; then
        update_clashtool_config 'ui' "dashboard"
        ui_name="clash-dashboard-gh-pages"
        url="$dashboard_url"
    elif [ "${ui_name}" = "yacd" ]; then
        # 在clashtool配置文件中写入ui
        update_clashtool_config 'ui' "yacd"
        ui_name="yacd-gh-pages"
        url="$yacd_url"
    else
        failed "$install_ui_parameter_failed_msg"
    fi
    download_name="$(get_download_filename "$url")"
    temp_clash_ui_path="${clash_dir}/${download_name}"
    download "$temp_clash_ui_path" "$url" "$download_name"    
    normal "${install_start_msg} ClashUI"
    # 解压
    temp_clash_ui_dir=${clash_dir}/temp_clash_ui
    decompression "$temp_clash_ui_path" "$temp_clash_ui_dir"
    find_result=$(find "$temp_clash_ui_dir" -type f -name "index.html" -print -quit)
    if [ -z "$find_result" ]; then
        # 删除已下载和解压的文件
        rm -rf "$temp_clash_ui_path"
        rm -rf "$temp_clash_ui_dir"
        failed ""
    fi
    # 重命名
    mv $(dirname "$find_result") "$clash_ui_dir"
    # 删除已下载和解压的文件
    rm -rf "$temp_clash_ui_path"
    rm -rf "$temp_clash_ui_dir"
    # 设置ui配置
    update_clash_config 'external-ui' "$clash_ui_dir"
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
    normal "$uninstall_start_msg ClashUI" 
    rm -rf "${clash_ui_dir}"
    update_clashtool_config 'ui' 'dashboard'
    # 设置ui配置
    delete_clash_config 'external-ui'
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
    normal "$uninstall_start_msg ClashUI" 
    rm -rf "${clash_ui_dir}"
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
    normal "${current_version_msg}$current"
    url='https://raw.githubusercontent.com/onlypeng/clash-for-linux/main/clashtool.sh'
    version=$(curl -k -s ${github_proxy}${url} | grep '^# version:' | head -1 | sed 's/# version://')
    if [ -z $version ];then
        failed $get_version_failed_msg
    fi
    normal "${latest_version_msg}$version" 
    if [ $version = $current ];then
        warn "$install_equal_versions_warn_msg"
    fi
    download "${current_path}.temp" "$url" "Script"
        cp "${current_path}.temp" $current_path
        chmod 755 $current_path
    chmod 755 $current_path
    if [ -d $clash_dir ];then
        cp "${current_path}.temp" $script_path
        chmod 755 $script_path
        # 升级配置相关文件
        sh $script_path update_config
    fi
    rm "${current_path}.temp"
    success $update_script_success_msg
}   

# 函数：加载订阅配置文件
# 参数: $1：sub_name - 订阅名称 （可为空），默认为当前使用订阅
loading_config(){
    sub_name=$1
    # 未指定订阅，获取当前订阅
    if [ -z "$sub_name" ]; then
        sub_name=$(find_subscribe_config '' 'use')
    fi

    if [ "$sub_name" = 'default' ]; then
        # 使用默认配置
        cp $user_config_path $config_path
    else
        if existence_subscrib_config "${sub_name}";then
             # 文件不存在则更新订阅
            if [ ! -f "${subscribe_dir}/${sub_name}.yaml" ];then
                update_sub "$sub_name"
            fi
            sub_config_path="${subscribe_dir}/${sub_name}.yaml"
            # 合并用户配置文件和订阅配置文件生成Clash配置文件
            merge_clash_config "$sub_config_path"
        else
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
        normal "$clash_start_msg"
        # 生成配置文件
        loading_config "$sub_name"
        # 判断是否开启透明网关
        gateway_status=$(find_clashtool_config "gateway")
        if [ "$gateway_status" = 'true' ];then
            # 开启电脑网卡转发功能
            sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
            if [ -f '/proc/sys/net/ipv6/ip_forward' ]; then
               sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
            fi
        fi
        # 启动clash
        nohup "${clash_path}" -d "${config_dir}" > "${logs_dir}/clash.log" 2>&1 &
        # 等待启动成功
        sleep 3
        # 判断是否启动失败
        pid=$(pgrep -f "$clash_path")
        if [ -z "$pid" ];then
            failed "$clash_start_failed_msg"
        fi
        # 修改运行状态
        state=true
        if [ -n "$sub_name" ];then
            # 更改配置中默认使用的配置文件
            update_subscribe_config '' 'use' "$sub_name"
        fi
        # 显示提示信息
        port=$(find_clash_config "external-controller" | awk -F ':' '{print $2}')
        secret=$(find_clash_config "secret")
        success "$clash_start_success_msg"
        clash_ui_link_info

        if grep -q 'mixed-port:' "$config_path"; then
            mixed_port=$(find_clash_config 'mixed-port')
            http_port="$mixed_port"
            mixed_port="$mixed_port"
        else
            http_port=$(find_clash_config 'port')
            socks_port=$(find_clash_config 'socks-port')
        fi
        _http_port=$(find_clashtool_config 'http_port')
        _socks_port=$(find_clashtool_config 'socks_port')
        # 判断用户是否修改监http听端口
        if ([ "$http_port" != "$_http_port" ] || [ "$socks_port" != "$_socks_port" ]) && is_proxy;then
            remind "$proxy_port_update_msg"
        fi
    fi
}

# 函数：停止clash
stop() {
    # 判断程序是否运行
    if [ -n "${pid}" ]; then
        # 根据clash PID 结束Clash
        for temp_pid in $pid; do
            if kill -0 "${temp_pid}" 2>/dev/null; then
                kill "${temp_pid}"
                # 等待进程结束
                wait "${temp_pid}"
            fi
        done
        # 清理pid变量
        pid=""
        # 判断是否是由systemctl启动的
        # 提醒关闭系统代理
        if is_proxy; then
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
    # 生成配置
    loading_config "$sub_name"
    # 重载配置
    port=$(find_clash_config "external-controller" "${config_path}" | awk -F ':' '{print $2}')
    secret=$(find_clash_config "secret" "${config_path}")
    if [ -z "$secret" ]; then
        result=$(curl -s -X PUT "${proxy_host}:${port}/configs" -H "Content-Type: application/json" -d "{\"path\": \"${config_path}\"}")
    else
        result=$(curl -s -X PUT "${proxy_host}:${port}/configs" -H "Content-Type: application/json" -H "Authorization: Bearer ${secret}" -d "{\"path\": \"${config_path}\"}")
    fi
    # 解析返回数据判断使用重载成功
    if [ -n "$result" ];then
        normal "$result" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p'
        failed "$clash_yaml_failed_msg"
        return 1
    fi
    # 如果加载成功修改启用配置文件名
    if [ $? -eq 0 ]; then
        update_subscribe_config '' 'use' "${sub_name}"
        success "$clash_reload_success_msg"
    else
        failed "$clash_reload_failed_msg"
        
    fi
}

# 函数：获取Clash信息
status() {
    ui_name=$(find_clashtool_config 'ui')
    version=$(find_clashtool_config 'version')
    autostart=$(find_clashtool_config 'auto_start')
    sub_name=$(find_subscribe_config '' 'use')
    gateway_status=$(find_clashtool_config 'gateway')
    secret=$(find_clash_config 'secret' "$config_path")
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
    echo "${status_gateway_msg}${gateway_status}"
    clash_ui_link_info
    echo "${status_clash_path_msg}${clash_path}"
}

# 函数：显示当所有订阅
list() {
    names=$(find_subscribe_config '' 'names')
    echo "$names" | tr ',' '\n' | while IFS= read -r name; do
        if [ -n "$name" ]; then
            url=$(find_subscribe_config "$name" "url")
            interval=$(find_subscribe_config "$name" "interval")
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
    req=$($clash_path -t -f "$file")
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
    # 检查是否不为空
    if [ -n "$interval" ]; then
        # 检查是否不全为数字
        case "$interval" in
            *[!0-9]*)
            failed "$add_sub_parameter_failed_msg:${interval}"
            ;;
        esac
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
            update_subscribe_config "$name" 'url' "$url"
            update_subscribe_config "$name" 'interval' "$interval"
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
        cp "$url" "${subscribe_dir}/${name}.yaml"
        # 如果配置文件不存在此信息则添加
        if ! existence_subscrib_config "${name}"; then
            add_subscribe_config "$name" "---" "0"
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
        update_subscribe_config "$sub_name" "interval" "0"
        auto_update_sub '' "${sub_name}"

        # 删除订阅配置信息
        delete_subscribe_config "${sub_name}"
        # 删除下载订阅文件
        if [ -f "${subscribe_dir}/${sub_name}.yaml" ]; then
            rm -rf "${subscribe_dir}/${sub_name}.yaml"
        fi
        # 判断当前订阅是否正在使用
        use=$(find_subscribe_config '' 'use')
        if [ "$use" = "${sub_name}" ]; then
            # 设置订阅配置为default
            update_subscribe_config '' 'use' 'default'
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
        names=$(find_subscribe_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                download_sub "${name}"
            fi
        done
    else
        # 当前使用配置文件
        use=$(find_subscribe_config '' 'use')
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
    url=${2:-$(find_subscribe_config "${name}" "url")}
    if [ -z "$url" ];then
        warn "$update_local_sub_failed_msg"
    else
        # 获取下载地址
        temp_sub_path="${subscribe_dir}/${name}.new.yaml"
        # 下载订阅文件
        download "${temp_sub_path}" "${url}" "${name}" $sub_proxy
        # 检查订阅文件是否有效
        check_conf "$temp_sub_path"
        # 如果已存在则备份原先订阅
        if [ -f "${subscribe_dir}/${name}.yaml" ];then
            mv "${subscribe_dir}/${name}.yaml" "${subscribe_backup_dir}/${name}$(date +'%Y%m%d%H%M').yaml"
        fi
        # 重命名订阅文件
        mv "${temp_sub_path}" "${subscribe_dir}/${name}.yaml"
    fi
}

# 函数：设置自动更新订阅
# 参数：$1：enable - 设置自动更新总开关，默认根据配置文件重新设置
#      $2：sub_name - 订阅名称（可选），默认根据配置文件重新设置全部
auto_update_sub() {
    enable=$1
    sub_name=$2
    if [ "$enable" = 'true' ] || [ "$enable" = 'false' ];then
        update_clashtool_config "auto_update_sub" "$enable"
        success $auto_update_sub_success_msg
    elif [ "$enable" = '' ];then
        enable=$(find_subscribe_config 'auto_update_sub')
    else
        failed $verify_failed_msg
    fi
    # 判断是否存在订阅配置
    if [ -n "$sub_name" ] && ! existence_subscrib_config "$sub_name"; then
        failed "$not_sub_exists_msg"
    fi
    if [ -z "$sub_name" ]; then
        # 为空则根据配置和enable重新设置全部定时任务
        names=$(find_subscribe_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                interval=$(find_subscribe_config "$name" 'interval')
                if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
                    crontab_tool '' "$script_path update_sub ${name} >> ${logs_dir}/crontab.log 2>&1"
                else
                    crontab_tool "0 */$interval * * *" "$script_path update_sub ${name} >> ${logs_dir}/crontab.log 2>&1"
                fi
            fi
        done
    else
        interval=$(find_subscribe_config "$sub_name" 'interval')
        # 设置指定定时任务
        if [ "$enable" = "false" ] || [ "$interval" = '0' ]; then
            crontab_tool '' "$script_path update_sub ${sub_name} >> ${logs_dir}/crontab.log 2>&1"
        else
            crontab_tool "0 */$interval * * *" "$script_path update_sub ${sub_name} >> ${logs_dir}/crontab.log 2>&1"
        fi
    fi
}
gateway(){
    enable=${1:-true}
    verify $enable
    if $enable; then
        success "$gateway_enable_success_msg"
    else
        success "$gateway_disable_success_msg"
    fi
    gateway_status=$(find_clashtool_config 'gateway')
    if [ "$gateway_status" != "$enable" ];then
        update_clashtool_config "gateway" "$enable"
        if $state; then
            restart
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
                } > "$service_file"
                chmod +x "$service_file"
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
                    echo "Type=simple"
                    echo "KillMode=process"
                    echo "ExecStart=$script_path start"
                    # echo "Restart=always"
                    echo "User=root"
                    echo ""
                    echo "[Install]"
                    echo "WantedBy=multi-user.target"
                } > "$service_file"
                chmod +x "$service_file"
                systemctl daemon-reload
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
        rm -rf "$service_file"
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
                rcupdate add "$service_name" default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                systemctl enable "$service_name" >/dev/null 2>&1
            ;;
        *)
            failed "$unsupported_linux_distribution_failed_msg"
        esac
        success "$auto_start_enabled_success_msg"
    else
        case "$linux_distribution" in
            "alpine")
                rcupdate del $service_name default
                ;;
            "centos" | "redhat" | "ubuntu" | "debian" | "kylin" | "deepin")
                systemctl disable $service_name >/dev/null 2>&1
                ;;
            *)
                failed "$unsupported_linux_distribution_failed_msg"
        esac
        success "$auto_start_turned_off_success_msg"
    fi
    update_clashtool_config 'auto_start' "$enable"
}

# 函数：开启系统代理
proxy_on() {
    if $state;then
        mixed_port=$(find_clash_config 'mixed-port' "$config_path")
        if [ -n "$mixed_port" ]; then
            http_port="$mixed_port"
            socks_port="$mixed_port"
        else
            http_port=$(find_clash_config 'port' "$config_path")
            socks_port=$(find_clash_config 'socks-port' "$config_path")
        fi
        # 设置环境变量
        # 检查 "$bashrc" 是否存在
        if [ ! -f "$bashrc" ]; then
            printf "" >> "$bashrc"
        fi
        # 循环添加或修改代理
        for proto in $proxy_keys; do
            proxy_key="${proto}_proxy"
            if [ $proto = 'socks' ];then
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
        done

        # 添加或修改排除代理地址
        if grep -q "no_proxy=" "$bashrc"; then
            sed -i "s|no_proxy=.*|no_proxy=${proxy_no}|" "$bashrc"
        else
            echo "export no_proxy=$proxy_no" >> "$bashrc"      
        fi

        # 生效设置
        source $bashrc

        # 配置包管理器        
        # [ -f "/etc/apt/apt.conf" ] && echo "Acquire::http::Proxy ${proxy_host}:${http_port}" >> "/etc/apt/apt.conf"
        # [ -f "/etc/yum.conf" ] && echo "proxy=${proxy_host}:${http_port}" >> "/etc/yum.conf"
        # [ -f "/etc/dnf/dnf.conf" ] && echo "proxy=${proxy_host}:${http_port}" >> "/etc/dnf/dnf.conf"


        # 设置 GNOME 桌面代理
        if command -v gsettings >/dev/null 2>&1; then
            for proto in $proxy_keys; do
                if [ "$proto" = 'socks' ];then
                    proxy_port="$socks_port"
                else
                    proxy_port="$http_port"
                fi
                gsettings set org.gnome.system.proxy.${proto} host $proxy_host
                gsettings set org.gnome.system.proxy.${proto} port $proxy_port
            done
            gsettings set org.gnome.system.proxy ignore-hosts "[$(echo $proxy_no | sed "s/[^,]\+/'&'/g")]"
            gsettings set org.gnome.system.proxy mode 'manual'
        fi

        # 设置 KDE 桌面代理
        if command -v kwriteconfig5 >/dev/null 2>&1; then
            echo "已进入kwriteconfig5"
            kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 1
            for proto in $proxy_keys; do
                if [ $proto = 'socks' ];then
                    proxy_port="$socks_port"
                else
                    proxy_port="$http_port"
                fi
                kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ${proto}Proxy "${proxy_host}:${proxy_port}"
            done
            kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "${proxy_no}"
        fi

        # 配置文件写入相关端口信息
        sh $script_path 'clashtool' "http_port::$http_port"
        sh $script_path 'clashtool' "socks_port::$socks_port"
        success "$proxy_on_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 函数：关闭系统代理
proxy_off(){
    # 删除环境变量的代理设置
    sed -i '/_proxy=/d' "$bashrc"
    # sed -i '/no_proxy=/d' "$bashrc"
    # 生效设置
    source $bashrc

    # 移除包管理器的代理配置
    # [ -f /etc/apt/apt.conf ] && sed -i "/Acquire::http::Proxy/d" /etc/apt/apt.conf
    # [ -f /etc/yum.conf ] && sed -i '/proxy=/d' /etc/yum.conf
    # [ -f /etc/dnf/dnf.conf ] && sed -i '/proxy=/d' /etc/dnf/dnf.conf

    # 禁用 GNOME 桌面代理
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.system.proxy mode 'none'
        for proto in $proxy_keys; do
            gsettings reset org.gnome.system.proxy.${proto} host
            gsettings reset org.gnome.system.proxy.${proto} port
        done
        gsettings reset org.gnome.system.proxy ignore-hosts
    fi

    # 禁用 KDE 桌面代理
    if command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0
        for proto in "$proxy_keys"; do
            kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ${proto}Proxy ''
        done
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key NoProxyFor ''
    fi

	success "$proxy_off_success_msg"
}

# 函数：判断是否设置代理
is_proxy(){
    # 检查环境变量代理设置
    for key in $proxy_keys; do
        # 检查HTTPS代理设置
        if [ -n "$(eval "echo \$${key}_proxy")" ]; then
            return 0
        fi
    done
     # 检查 GNOME 桌面代理设置
    if command -v gsettings >/dev/null 2>&1; then
        proxy_mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null)
        if [ "$proxy_mode" = "'manual'" ]; then
            return 0
        fi
    fi

    # 检查 KDE 桌面代理设置
    if command -v kwriteconfig5 >/dev/null 2>&1; then
        proxy_mode=$(kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 2>/dev/null)
        if [ "$proxy_mode" -eq 1 ]; then
            return 0
        fi
    fi
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

# 函数：自提升root权限
check_and_elevate() {
    if [ "$(id -u)" -ne 0 ]; then
        # 重新以sudo方式执行当前脚本
        if echo "$-" | grep -q x; then
            exec sudo sh -x "$0" "$@"
        else
            exec sudo sh "$0" "$@"
        fi
    fi
}


# 函数:修改用户配置
userconfig(){
    input=$1
    key=$(echo "${input}" | awk -F '::' '{print $1}')
    val=$(echo "${input}" | awk -F '::' '{print $2}')
    if [ -z $val ];then
        echo "$temp_val"
        exit 0
    fi
    temp_val=$(find_clash_config "$key")
    if [ -z "$temp_val" ];then
        failed $confg_key_error_msg
    fi
    update_clash_config "$key" "$val"
}

# 函数:获取或修改clashtool配置
clashtool() {
    input=$1
    key=$(echo "${input}" | awk -F '::' '{print $1}')
    val=$(echo "${input}" | awk -F '::' '{print $2}')
    if [ -z $val ];then
        echo "$temp_val"
        exit 0
    fi
    temp_val=$(find_clashtool_config "$key")
    if [ -z "$temp_val" ];then
        failed $confg_key_error_msg
    fi
    update_clashtool_config "$key" "$val"
}

# 定义菜单函数
menu() {
    clash() {
        while true; do
            echo "$menu_core"
            echo "$menu_core_option1"
            echo "$menu_core_option2"
            echo "$menu_core_option3"
            echo "$menu_core_option4"
            echo "$menu_return"
            echo "$menu_end"
            read -p "$prompt_choice_msg" choice
            case $choice in
                1)
                    read -p "$prompt_version_msg" input
                    $0 install "$input"
                    ;;
                2)
                    read -p "$prompt_version_msg" input
                    $0 update "$input"
                    ;;
                3) $0 uninstall;;
                4) $0 uninstall all;;
                'r') break;;
                *) echo "$menu_invalid_choice";;
            esac
        done
    }

    ui() {
        while true; do
            echo "$menu_ui"
            echo "$menu_ui_option1"
            echo "$menu_ui_option2"
            echo "$menu_ui_option3"
            echo "$menu_ui_option4"
            echo "$menu_return"
            echo "$menu_end"
            read -p "$prompt_choice_msg" choice
            case $choice in
                1|2) 
                    ui="yacd"
                    [ $choice=2 ] && ui="dashboard"
                    if [ -d "$clash_ui_dir" ];then
                        $0 update_ui $ui
                    else
                        $0 install_ui $ui
                    fi
                    ;;
                3) $0 update_ui;;
                4) $0 uninstall_ui;;
                'r') break;;
                *) echo "$menu_invalid_choice";;
            esac
        done
    }

    subscription() {
        while true; do
            echo "$menu_subscription"
            echo "$menu_subscription_option1"
            echo "$menu_subscription_option2"
            echo "$menu_subscription_option3"
            echo "$menu_subscription_option4"
            echo "$menu_subscription_option5"
            echo "$menu_subscription_option6"
            echo "$menu_subscription_option7"
            echo "$menu_return"
            echo "$menu_end"
            read -p "$prompt_choice_msg" choice
            case $choice in
                1|2) 
                    [ $choice = 2 ] && list
                    read -p "$prompt_subscription_name_msg" input
                    var="${input}"
                    read -p "$prompt_subscription_url_msg" input
                    var="${var}::${input}"
                    read -p "$prompt_subscription_update_msg" input
                    [ -n "$input" ] && var="${var}::${input}"
                    $0 add "$var"
                    ;;
                3) 
                    list
                    read -p "$prompt_subscription_name_msg" input
                    $0 del $input
                    ;;
                4) list;;
                5)
                    list
                    read -p "$prompt_subscription_name_msg" input
                    $0 update_sub "$input"
                    ;;
                6) $0 auto_update_sub true;;
                7) $0 auto_update_sub false;;
                'r') break;;
                *) echo "$menu_invalid_choice";;
            esac
        done
    }

    running() {
        while true; do
            echo "$menu_running"
            echo "$menu_running_option1"
            echo "$menu_running_option2"
            echo "$menu_running_option3"
            echo "$menu_running_option4"
            echo "$menu_return"
            echo "$menu_end"
            read -p "$prompt_choice_msg" choice
            case $choice in
                1) $0 start;;
                2) 
                    list
                    read -p "$prompt_subscription_name_msg" input
                    $0 reload "$input"
                    ;;
                3) $0 stop;;
                4) $0 restart;;
                'r') break;;
                *) echo "$menu_invalid_choice";;
            esac
        done
    }

    while true; do
        echo "$menu_start"
        echo "$menu_main_option1"
        echo "$menu_main_option2"
        echo "$menu_main_option3"
        echo "$menu_main_option4"
        echo "$menu_main_option5"
        echo "$menu_main_option6"
        echo "$menu_main_option7"
        echo "$menu_main_option8"
        echo "$menu_main_option9"
        echo "$menu_main_help"
        echo "$menu_exit"
        echo "$menu_end"
        read -p "$prompt_choice_msg" choice
        case $choice in
            1) clash;;
            2) ui;;
            3) running;;
            4) subscription;;
            5) 
                while true; do
                    echo "$menu_autostart"
                    echo "$menu_autostart_option1"
                    echo "$menu_autostart_option2"
                    echo "$menu_return"
                    echo "$menu_end"
                    read -p "$prompt_choice_msg" input
                    case $input in
                        1) $0 auto_start true;;
                        2) $0 auto_start false;;
                        'r') break;;
                        *) echo "$menu_invalid_choice";;
                    esac
                done
                ;;
            6) status;;
            7) $0 update_script;;
            8) echo "$proxy_not_source_command_msg";;
            9)  
                while true; do
                    echo "$menu_gateway"
                    echo "$menu_gateway_option1"
                    echo "$menu_gateway_option2"
                    echo "$menu_return"
                    echo "$menu_end"
                    read -p "$prompt_choice_msg" input
                    case $input in
                        1) $0 gateway true;;
                        2) $0 gateway false;;
                        'r') break;;
                        *) echo "$menu_invalid_choice";;
                    esac
                done
                ;;
            h) echo "$help_msg";;
            'q') break;;
            *) echo "$menu_invalid_choice";;
        esac
    done
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
        "install")
            check_and_elevate "$@"
            $fun "$var"
            ;;
        "uninstall"|"update"|"install_ui"|"uninstall_ui"|"update_ui"|"start"|"stop"|"restart"|"reload"|"add"|"list"|"del"|"update_sub"|"auto_update_sub"|"auto_start"|"update_script"|"gateway"|"clashtool"|"userconfig"|"update_config")
            if [ ! -f "$clash_path" ];then
                failed $not_install_msg
            fi
            check_and_elevate "$@"
            $fun "$var"
            ;;
        "status")
            if [ ! -f "$clash_path" ];then
                failed $not_install_msg
            fi
            $fun
            ;;
        "clear")
            check_and_elevate "$@"
            clear
            ;;
        "proxy")
            failed "$proxy_not_source_command_msg" false
            ;;
        "help")
            echo "$help_msg"
            ;;
        "")
            menu
            ;;
        *)
            normal "$main_msg"
            ;;
        esac 
    fi
}

# 执行主函数
main "$1" "$2"