#!/bin/sh

# 网页初始链接密码，不填写则随机生成
secret=''
# clash架构，默认自动获取，获取失败请自行填写
platform=''
# 使用中文提示输出语言
chinese=true
# 订阅使用github代理下载
sub_proxy=false
# github下载代理地址，clash核心和ui的下载使用该代理
github_proxy="https://gh.ylpproxy.eu.org/"
# 设置代理的环境变量,
proxy_keys="http_proxy https_proxy ftp_proxy all_proxy"
# get_scripts_path脚本存放目录
get_scripts_dir="/tmp/clash/"
# get_scripts_path脚本路径
get_scripts_path="$get_scripts_dir/clashtool_script_path.sh"

# 判断是否使用了source 命令运行脚本
if [ "${0#-}" = "$0" ];then
    # 使用readlink获取当前脚本路径
    script_path="$(readlink -f "$0")"
    # 如果不存在get_scripts_dir目录则创建
    if [ ! -d $get_scripts_dir ];then
        mkdir -p $get_scripts_dir
    fi
    # 如果不存在get_scripts_path脚本或脚本保存的路径与当前路径不一致则更新地址
    if [ ! -f "$get_scripts_path" ] || [ "$(cat $get_scripts_path)" != "$script_path" ];then
        echo "$script_path"> $get_scripts_path
    fi
else
    # 使用source命令时使用get_scripts_path脚本获取脚本地址
    if [ ! -f "$get_scripts_path" ] ;then
        failed "$status_not_running_msg"
    fi
    script_path=$(cat $get_scripts_path)
fi

# clash 安装目录
clash_dir="$(dirname "$script_path")/clash"
# clash UI目录
clash_ui_dir="${clash_dir}/clash_gh_pages"
# clash 日志目录
logs_dir="${clash_dir}/logs"
# clash 配置目录
config_dir="${clash_dir}/config"
# 订阅文件目录
subscribe_dir="${config_dir}/subscribe"

# 用户环境变量存放地址
bashrc="/root/.bashrc"
# clash文件
clash_path="${clash_dir}/clash"
# clash配置文件
config_path="${config_dir}/config.yaml"

# 用户自定义配置
user_config_path="${config_dir}/user.yaml"
# clashtool 配置文件
clashtool_config_path="${config_dir}/clashtool.ini"

# 保存当前clash程序运行状态
pid=$(pgrep -f "^$clash_path -d ${config_dir}\$")
if [ -z "$pid" ]; then
    state=false
else
    state=true
fi
# 英文提示文字开始——ChatGPT翻译，给不支持中文的linux系统使用
verify_failed_msg="Parameter can only be true, false, or '' (default is true)"
require_curl_failed_msg="Unrecognized package manager, please install the curl software manually"
require_unzip_failed_msg="Unrecognized package manager, please install the unzip software manually"
init_config_start_msg="Initializing configuration file"
init_config_success_msg="Configuration file initialized successfully"
download_file_path_null_msg="Download path cannot be empty"
download_url_null_msg="Download URL address cannot be empty"
download_start_msg="Starting download"
download_success_msg="Download successful"
download_failed_msg="Download failed"
get_version_failed_msg="Failed to retrieve version, please specify a version manually"
current_version_msg="Installed version:"
install_version_msg="Newly installed version:"
equal_versions_warn_msg="Newly installed version is the same as the current version"
recognition_system_failed_msg="Unable to determine the current operating system architecture type. Please specify the 'platform' parameter manually."
install_ui_start_msg="Starting WebUI installation"
install_ui_parameter_failed_msg="Parameter error, can only be dashboard or yacd, defaults to the current installed version"
delete_ui_success_msg="Successfully deleted installed WebUI"
install_ui_success_msg="WebUI installed successfully"
clash_installed_msg="Clash is already installed"
install_clash_start_msg="Starting Clash installation"
delete_clash_success_msg="Successfully deleted installed Clash"
install_clash_success_msg="Clash installed successfully"
uninstall_clash_success_msg="Clash uninstalled successfully"
not_install_clash_msg="Clash is not installed"
clash_running_warn_msg="Clash service is already running"
clash_not_running_warn_msg="Clash service is not running"
clash_start_msg="Starting Clash service"
clash_start_success_msg="Clash service started successfully"
clash_start_failed_msg="Failed to start Clash service"
clash_ui_access_address_msg="ClashWebUI access address:"
clash_ui_access_secret_msg="ClashWebUI access token:"
clash_yaml_failed_msg="Configuration file error"
clash_reload_success_msg="Successfully reloaded Clash configuration"
clash_stop_success_msg="Clash service stopped successfully"
add_sub_success_msg="Successfully added subscription information"
add_sub_parameter_failed_msg="Format error: Format should be \"Subscription Name::Subscription URL::Update Interval (in hours)\""
delete_sub_success_msg="Successfully deleted subscription information"
update_sub_success_msg="Successfully updated subscription information"
update_default_sub_failed_msg="Currently using default configuration, unable to update"
not_sub_exists_msg="Subscription does not exist"
unsupported_linux_distribution_failed_msg="Unsupported Linux distribution"
auto_start_enabled_success_msg="Auto-start enabled"
auto_start_turned_off_success_msg="Auto-start turned off"
status_running_msg="Status: Running"
status_not_running_msg="Status: Not running"
status_ui_msg="ClashUI:"
status_clash_version_msg="Clash version:"
status_sub_msg="Current subscription file:"
status_auto_start_msg="Auto-start on boot:"
status_secret_msg="webUI link password:"
status_proxy_msg="Local proxy status:"
status_clash_path_msg="Clash installation path:"
list_sub_url_msg="Subscription URL:"
list_sub_update_interval_msg="Update Interval:"
proxy_port_update_msg="Detected that the Clash HTTP proxy port has been changed and the proxy is now active. Please reconfigure the proxy."
proxy_manually_running_msg="Please run this command manually, otherwise you may not be able to access the internet."
proxy_proxy_command_msg="Command: source $script_path proxy"
proxy_source_command_msg="Do not use 'source' to execute commands other than 'proxy'."
proxy_not_source_command_msg="Please use 'source' to execute the 'proxy' command."
proxy_on_success_msg="Proxy is now enabled."
proxy_off_success_msg="Proxy has been disabled."
help_msg="
    Command                Parameter                           Note
    install        version             Optional     Install Clash, default is the latest version
    uninstall      all                 Optional     Uninstall Clash, use 'all' to delete related configurations
    update         version             Optional     Update Clash, default is the latest version
    install_ui     dashboard or yacd   Optional     Install web interface, default is dashboard
    start          subscription        Optional     Start Clash, use current subscription configuration by default
    stop           None                             Stop Clash
    restart        subscription        Optional     Restart Clash, use current subscription configuration by default
    reload         subscription        Optional     Reload Clash, use current subscription configuration by default
    add            subscription                     Add subscription: Format \"Subscription Name::Subscription URL::Update Interval (in hours)\"
    del            subscription                     Delete subscription
    update_sub     subscription or all              Update subscription file, update current subscription by default, use 'all' to update all subscriptions
    list           None                             List all subscription information
    auto_start     true or false       Optional     Enable or disable auto-start on boot, default is true
    status         None                             Display Clash-related information
    proxy          true or false       Optional     Enable or disable local proxy, default is true,This command needs to be run using source"
main_msg="Invalid command. Enter help to view related commands"
# 英文提示文字结束

# 中文提示函数
chinese_language(){
    # 中文提示文字开始
    verify_failed_msg="参数只能是true、false 或 ''， ''默认为true"
    require_curl_failed_msg="无法识别包管理器，请自行安装curl软件"
    require_unzip_failed_msg="无法识别包管理器，请自行安装unzip软件"
    init_config_start_msg="初始化配置文件"
    init_config_success_msg="配置文件初始化成功"
    download_file_path_null_msg="下载路径不能为空"
    download_url_null_msg="下载url地址不能为空"
    download_start_msg="开始下载"
    download_success_msg="下载成功"
    download_failed_msg="下载失败"
    get_version_failed_msg="获取版本失败，请自行指定版本"
    current_version_msg="已安装版本："
    install_version_msg="新安装版本："
    equal_versions_warn_msg="新安装版本与当前版本相同"
    recognition_system_failed_msg="无法确定当前操作系统架构类型。请自行填写platform参数"
    install_ui_start_msg="开始安装WebUI"
    install_ui_parameter_failed_msg="参数错误，只能为 dashboard 或 yacd，默认为当前安装版本"
    delete_ui_success_msg="删除已安装WebUI"
    install_ui_success_msg="WebUI安装成功"
    clash_installed_msg="已安装Clash"
    install_clash_start_msg="开始安装Clash"
    delete_clash_success_msg="删除已安装Clash"
    install_clash_success_msg="Clash安装成功"
    uninstall_clash_success_msg="Clash卸载成功"
    not_install_clash_msg="Clash未安装"
    clash_running_warn_msg="Clash服务已运行"
    clash_not_running_warn_msg="Clash服务未启动"
    clash_start_msg="正在启动Clash服务"
    clash_start_success_msg="Clash服务启动成功"
    clash_start_failed_msg="Clash服务启动失败"
    clash_ui_access_address_msg="ClashWebUI访问地址："
    clash_ui_access_secret_msg="ClashWebUI访问令牌："
    clash_yaml_failed_msg="配置文件错误"
    clash_reload_success_msg="Clash重载配置成功"
    clash_stop_success_msg="Clash服务停止成功"
    add_sub_success_msg="添加订阅信息成功"
    add_sub_parameter_failed_msg="格式错误：格式《订阅名称::订阅地址::订阅更新时间（小时）》"
    delete_sub_success_msg="删除订阅信息成功"
    update_sub_success_msg="更新订阅信息成功"
    update_default_sub_failed_msg="当前使用默认配置，无法更新"
    not_sub_exists_msg="不存在此订阅"
    unsupported_linux_distribution_failed_msg="不支持的Linux发行版"
    auto_start_enabled_success_msg="自动启动已开启"
    auto_start_turned_off_success_msg="自动启动已关闭"
    status_running_msg="状态：运行中"
    status_not_running_msg="状态：未运行"
    status_ui_msg="ClashUI："
    status_clash_version_msg="Clash版本："
    status_sub_msg="当前订阅文件："
    status_auto_start_msg="开机自动启动："
    status_secret_msg="webUI链接密码："
    status_clash_path_msg="Clash安装路径："
    status_proxy_msg="本机代理状态："
    list_sub_url_msg="订阅地址："
    list_sub_update_interval_msg="更新间隔："
    proxy_port_update_msg="检测到Clash http代理端口已更改并已开启代理,请重新设置代理"
    proxy_manually_running_msg="请手动运行此命令，否则可能无法访问互联网"
    proxy_proxy_command_msg="命令：source $script_path proxy"
    proxy_source_command_msg="不要使用source执行除proxy其他命令"
    proxy_not_source_command_msg="请使用source执行proxy命令"
    proxy_on_success_msg="代理已开启"
    proxy_off_success_msg="代理已关闭"
    help_msg="
      命令                  参数                           备注
    install        版本             可为空       安装Clash，默认为最新版本
    uninstall      all              可为空       卸载Clash，参数为all时同时删除相关配置
    update         版本             可为空       更新Clash，默认为最新版本
    install_ui     dashboard或yacd  可为空       安装web界面，默认安装dashboard
    start          订阅名称         可为空       启动Clash，默认，使用当前订阅配置
    stop           空                            停止Clash运行
    restart        订阅名称         可为空       重启Clash，默认使用当前订阅配置
    reload         订阅名称         可为空       重载Clash，默认使用当前订阅配置
    add            订阅信息                      添加订阅信息：格式《订阅名称::订阅地址::订阅更新时间（小时）》
    del            订阅名称                      删除订阅
    update_sub     订阅名称或all     可为空       更新订阅文件，默认更新当前使用订阅，参数为all时更新所有订阅
    list           空                            查询所有订阅信息
    auto_start     true或false      可为空       启用或禁用开机自启动功能，默认为true
    status         空                            查看Clash相关信息
    proxy          true或false      可为空       启用或禁用本机代理，默认为true，此命令需要使用source运行"
    main_msg="无效命令，相关命令输入help进行查看"
    # 中文提示文字结束
}

# 判断指定节是否存在
section_exists() {
    file=$1
    section=$2

    # 使用 grep 搜索指定节
    grep -q "^\[$section\]$" "$file"
    return $?
}

# 添加或修改INI配置文件
write_ini() {
    file=$1
    section=$2
    key=$3
    value=$4

    # 判断指定节是否存在
    if section_exists "$file" "$section"; then
        # 使用 awk 编辑配置文件
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
        ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
    else
        # 如果节不存在，则添加新节和键值对
        {
            echo "[$section]"
            echo "$key=$value"
        } >>"$file"
    fi
}

# 删除INI配置项或指定节
delete_ini() {
    file=$1
    section=$2
    key=$3

    # 判断指定节是否存在
    if section_exists "$file" "$section"; then
        if [ -z "$key" ]; then
            # 删除整个节
            sed -i "/\[$section\]/,/^$/d" "$file"
        else
            # 删除指定节下的指定键的配置项
            sed -i "/\[$section\]/,+1 { /^\[$section\]/! { /$key=/d } }" "$file"
        fi
    fi
}

# 获取INI配置文件
read_ini() {
    file=$1
    section=$2
    key=$3

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

# 获取clashtool配置
get_clashtool_config() {
    key=$1
    read_ini "${clashtool_config_path}" 'clashtool' "${key}"
}

# 添加修改clashtool配置
set_clashtool_config() {
    key=$1
    val=$2
    write_ini "${clashtool_config_path}" "clashtool" "${key}" "${val}"
}

# 判断订阅是否存在
existence_subscrib_config() {
    sec=$1
    section_exists "${clashtool_config_path}" "subscribe_${sec}"
    return $?
}

# 添加订阅配置
add_subscribe_config() {
    name=$1
    url=$2
    interval=$3
    {
        echo "[subscribe_$name]"
        echo "url=$url"
        echo "interval=$interval"
    } >>"$clashtool_config_path"
    # 更新names名称
    names=$(get_subscribe_config '' 'names')${name}','
    set_subscribe_config '' 'names' "${names}"
}

# 添加修改订阅配置
set_subscribe_config() {
    sec=$1
    key=$2
    val=$3
    if [ -z "${sec}" ]; then
        sec="subscribe"
    else
        sec="subscribe_${sec}"
    fi
    write_ini "${clashtool_config_path}" "${sec}" "${key}" "${val}"
}

# 删除订阅
del_subscribe_config() {
    sub=$1
    # 更新names
    names=$(get_subscribe_config '' 'names' | sed "s/${sub},//g")
    set_subscribe_config '' 'names' "$names"
    # 删除订阅节点
    delete_ini "${clashtool_config_path}" "subscribe_${sub}" ''
}

# 获取订阅配置
get_subscribe_config() {
    sec=$1
    key=$2
    if [ -z "${sec}" ]; then
        sec="subscribe"
    else
        sec="subscribe_${sec}"
    fi
    read_ini "${clashtool_config_path}" "${sec}" "${key}"
}

# 获取yaml配置,只能简单的读取单行key: value
get_yaml_value() {
    key="$1"
    file="$2"
    sed -n "/^$key:/s/^$key:[[:space:]]*//p" "$file"
}

# 失败
failed() {
    printf "\\033[88G[\\033[1;31mFAILED\\033[0;39m]\r"
    echo "$1"
    is_true=${2:-true}
    if $is_true;then
        exit 1
    fi
}

# 警告
warn() {
    printf "\\033[88G[\\033[1;33m WARN \\033[0;39m]\r"
    echo "$1"
    is_true=${2:-true}
    if $is_true;then
        exit 0
    fi
}

# 提醒
remind(){
    printf "\\033[88G[\\033[1;36mREMIND\\033[0;39m]\r"
    echo "$1"
    is_true=${2:-false}
    if $is_true;then
        exit 0
    fi
}

# 成功
success() {
    printf "\\033[88G[\\033[1;32m  OK  \\033[0;39m]\r"
    echo "$1"
    is_true=${2:-false}
    if $is_true;then
        exit 0
    fi
}
# 验证true false ''默认为true
verify() {
    if [ "$1" != 'true' ] && [ "$1" != 'false' ]; then
        failed "$verify_failed_msg"
    fi
}

# 检查并安装依赖
require() {

    # 检查并安装curl
    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt >/dev/null 2>&1; then
            apt install curl -y
        elif command -v yum >/dev/null 2>&1; then
            yum install curl -y
        elif command -v apk >/dev/null 2>&1; then
            apk add curl -y
        else
            failed "$require_curl_failed_msg"
        fi
    fi
    # 检查安装unzip，竟然有linux没预安装
    if ! command -v unzip >/dev/null 2>&1; then
        if command -v apt >/dev/null 2>&1; then
            apt install unzip -y
        elif command -v yum >/dev/null 2>&1; then
            yum install unzip -y
        elif command -v apk >/dev/null 2>&1; then
            apk add unzip -y
        else
            failed "$require_unzip_failed_msg"
        fi
    fi
}

# 初始化配置
init_config() {
    echo "$init_config_start_msg"
    # 创建clash目录
    if [ ! -d "${clash_dir}" ]; then
        mkdir -p "${clash_dir}"
    fi
    # 创建配置目录
    if [ ! -d "${config_dir}" ]; then
        mkdir -p "${config_dir}"
    fi
    # 创建logs目录
    if [ ! -d "${logs_dir}" ]; then
        mkdir -p "${logs_dir}"
    fi
    # 创建subscribe配置目录
    if [ ! -d "${subscribe_dir}" ]; then
        mkdir "${subscribe_dir}"
    fi
    # 创建clashtool和订阅配置文件
    if [ ! -f "${clashtool_config_path}" ]; then
        {
            echo "[clashtool]"
            echo "ui=dashboard"
            echo "version="
            echo "proxy=false"
            echo "autoStart=false"
            echo "autoUpdateSub=true"
            echo "proxyPort=7890"
            echo ""
            echo "[subscribe]"
            echo "names="
            echo "use=default"
        } >>"${clashtool_config_path}"
    fi
    # 创建默认clash配置文件
    if [ ! -f "${user_config_path}" ]; then
        # 未自定义网页密码则产生随机密码
        if [ -z "$secret" ];then
            secret=$(tr -dc a-zA-Z0-9#@ 2>/dev/null < /dev/urandom | head -c 12)
        fi
        {
            echo "port: 7890"
            echo "socks-port: 7891"
            echo "allow-lan: true"
            echo "mode: Rule"
            echo "log-level: error"
            echo "external-controller: 0.0.0.0:9090"
            echo "external-ui: ${clash_ui_dir}"
            echo "secret: ${secret}"
        } >> "${user_config_path}"
    fi
    success "$init_config_success_msg"
}

# 下载通用脚本
download(){
    # 下载后保存的文件名
    file_path=$1
    # 要下载的文件的URL
    url=$2
    # 输出标签
    tag=$3
    # 是否使用github代理
    enable=${4:-true}
    if [ -z "$file_path" ];then
        failed "$download_file_path_null_msg"
    fi

    if [ -z "$url" ];then
        failed "$download_url_null_msg"
    fi

    echo "${download_start_msg}${tag}"
    # 关闭本shell代理
    proxy=$(get_clashtool_config "proxy")
    if [ "$proxy" = "true" ];then
        unset no_proxy
        for key in $proxy_keys; do
            unset "$key"
        done
    fi
    # 使用curl下载文件
    if [ "$enable" = "true" ];then
        curl "${github_proxy}${url}" -o "$file_path"
    else
        curl "${url}" -o "$file_path"
    fi
    _status=$?
    # 检查curl命令的退出状态
    if [ $_status -ne 0 ]; then
        failed "${tag}${download_failed_msg}"
    fi
    # 检查文件是否下载成功（文件存在）
    if [ ! -f "$file_path" ]; then
        failed "${tag}${download_failed_msg}"
    fi
    success "${tag}${download_success_msg}"
}

# 状态为运行则重载配置
autoreload() {
    if $state; then
        reload "$1"
    fi
}

# 状态为运行则停止
autostop() {
    if $state; then
        stop
    fi
}

# 状态为运行则启动
autostart() {
    if $state; then
        start "$1"
    fi
}

# 安装clash内核
install_clash() {
    # 没有指定版本则更新最新版本
    if [ -z "${version}" ]; then
        # 获取clash最新版本号
        version=$(curl -k -s https://api.github.com/repos/Dreamacro/clash/releases/latest | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':' '{print $2}')
        if [ -z "${version}" ]; then
            failed "$get_version_failed_msg"
        fi
    fi
    # 获取配置中当前安装的版本
    current=$(get_clashtool_config 'version')
    # 不是第一次安装则不显示当前版本
    if [ -n "${current}" ]; then
        echo "${current_version_msg}${current}"
    fi
    # 要安装的版本
    echo "${install_version_msg}${version}"
    # 判断版本是否相等
    if [ "${current}" = "${version}" ]; then
        warn "$equal_versions_warn_msg"
    fi
    # 使用 uname -m 命令获取当前操作系统的架构
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
            ;;
        esac
    fi
    # 下载clash
    clash_temp_path="${clash_dir}/temp_clash"
    download "${clash_temp_path}.gz" "https://github.com/Dreamacro/clash/releases/download/${version}/clash-linux-${platform}-${version}.gz" "Clash"
    # 停止clash
    autostop
    if [ -f "$clash_path" ];then
        # 卸载已安装Clash
        success "$delete_clash_success_msg"
    fi
    echo "$install_clash_start_msg"
    # 解压clash
    gunzip -f "${clash_temp_path}.gz"
    # 重命名clash
    mv "${clash_temp_path}" "${clash_path}"
    # 赋予运行权限
    chmod 755 "${clash_path}"
    # 向clash配置文件写入当前版本
    set_clashtool_config 'version' "${version}"
    # 启动clash
    success "$install_clash_success_msg"
}

# 安装UIee
install_ui() {
    ui=$1
    # 没有指定UI则使用配置中指定UI
    if [ -z "${ui}" ]; then
        ui=$(get_clashtool_config 'ui')
    fi
    # 下载UI安装包
    if [ "${ui}" = "dashboard" ]; then
        set_clashtool_config 'ui' "dashboard"
        ui_name="clash-dashboard-gh-pages"
        url="https://github.com/Dreamacro/clash-dashboard/archive/refs/heads/gh-pages.zip"
    elif [ "${ui}" = "yacd" ]; then
        # 在clashtool配置文件中写入ui
        set_clashtool_config 'ui' "yacd"
        ui_name="yacd-gh-pages"
        url="https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip"
    else
        failed "$install_ui_parameter_failed_msg"
    fi
    download "${clash_dir}/gh-pages.zip" "$url" "${ui}"
    # 删除当前已安装UI
    if [ -d "${clash_ui_dir}" ]; then
        echo "$delete_ui_success_msg"
        rm -rf "${clash_ui_dir}"
    fi
    echo "${install_ui_start_msg}"
    # 解压
    unzip -q -d "${clash_dir}" "${clash_dir}/gh-pages.zip"
    # 重命名
    mv "${clash_dir}/${ui_name}" "${clash_ui_dir}"
    # 删除已下载文件
    rm "${clash_dir}/gh-pages.zip"
    success "$install_ui_success_msg"
}

# 安装clash
install() {
    # 判断是否已经安装clash
    if [ -f "${clash_path}" ]; then
        warn "$clash_installed_msg"
    else
        # 安装依赖软件
        require
        # 初始化目录配置
        init_config
        # 安装 clash
        install_clash "$1"
        # 安装 ui
        install_ui
    fi
}

# 卸载clash
uninstall() {
    # 删除clash
    if [ -d "${clash_dir}" ]; then
        # 关闭calash
        autostop
        
        if [ "$(get_clashtool_config 'autoStart')" = 'true' ];then
            # 关闭自动启动
            auto_start false
        fi
        if [ "$1" = "all" ]; then
            # 关闭自动更新配置
            auto_update_sub false
            # 删除Clash所有相关文件
            rm -rf "${clash_dir}"
        else
            # 删除clash程序文件
            rm -rf "${clash_path}"
            # 修Clash改版本为空
            set_clashtool_config 'version' ''
        fi
    fi
    success "$uninstall_clash_success_msg"
}

# 更新clash
update() {
    autostop ""
    install_clash "$$1"
    autostart ""
}

# 处理Clash配置文件
processing_config(){
    use=$1
    if [ -z "$use" ]; then
        use=$(get_subscribe_config '' 'use')
    elif ! existence_subscrib_config "${use}"; then
        # 不存在该订阅配置
        failed "$not_sub_exists_msg"
    fi

    # 文件不存在则更新订阅
    if [ ! -f "${subscribe_dir}/${use}.yaml" ];then
        update_sub "$use"
    fi

    if [ "$use" = 'default' ]; then
        # 使用默认配置
        cp "${user_config_path}" "${config_path}"
    else
        # 把自定义文件覆写到下载的配置文件中生成临时配置文件
        awk '
            NR==FNR { a[$1]=$2; next }
            ($1 in a) { $2=a[$1]; delete a[$1] }
            { print }
            END { for (k in a) print k, a[k] }
        ' "${user_config_path}" "${subscribe_dir}/${use}.yaml" > "${config_path}"
    fi

    proxy_port=$(get_yaml_value 'port' "$user_config_path")
    
    # 判断用户是否修改监http听端口
    if [ "$(get_clashtool_config 'proxyPort')" != "$proxy_port" ];then
        set_clashtool_config 'proxyPort' "$proxy_port"
        if [ "$(get_clashtool_config 'porxy')" = 'true' ];then
            remind "$proxy_port_update_msg"
            remind "$proxy_manually_running_msg"       
            remind "$proxy_proxy_command_msg true"
        fi
    fi
}

# 启动clash
start() {
    use=$1
    # 判断是否正在运行
    if [ -n "$pid" ]; then
        warn "$clash_running_warn_msg"
    else
        processing_config "$use"
        echo "$clash_start_msg"
        # 启动clash
        nohup "${clash_path}" -d "${config_dir}" > "${logs_dir}/clash.log" 2>&1 &
        # 等待2秒时间输出日志
        sleep 2
        # 根据输出日志判断是否启动失败
        result=$(awk -v search="level=fatal" -F 'msg=' '/level=fatal/ && $0 ~ search {gsub(/"/, "", $2); print $2; found=1} END{if (found != 1) exit 1}' "${logs_dir}/clash.log")
        if [ -n "$result" ];then
            echo "$result"
            failed "$clash_yaml_failed_msg"
        fi

        pid=$(pgrep -f "$clash_path")
        # 进一步判断是否启动失败
        if [ -z "$pid" ];then
            failed "$clash_start_failed_msg"
        fi
        # 更改配置中默认使用的配置文件
        set_subscribe_config '' 'use' "${use}"
        # 修改登录状态
        state=true
        # 显示提示信息
        port=$(get_yaml_value "external-controller" "${config_path}" | awk -F ':' '{print $2}')
        secret=$(get_yaml_value "secret" "${config_path}")
        success "$clash_start_success_msg"
        echo "${clash_ui_access_address_msg}http://<ip>:$port/ui"
        echo "${clash_ui_access_secret_msg}${secret}"
    fi
}

# 停止clash
stop() {
    # 判断程序是否运行
    if [ -n "${pid}" ] ; then
        # 根据clash PID 结束Clash
        kill -9 "${pid}"
        pid=""
        # 提醒关闭系统代理
        if [ "$(get_clashtool_config "proxy")" = "true" ];then
            remind "$proxy_manually_running_msg"
            remind "$proxy_proxy_command_msg false"
        fi
        success "$clash_stop_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 重启clash
restart() {
    stop
    start ""
}

# 重载clash配置文件
reload() {
    use=$1
    if ! $state; then
        warn "$clash_not_running_warn_msg"
    fi
    processing_config "$use"
    port=$(get_yaml_value "external-controller" "${config_path}" | awk -F ':' '{print $2}')
    secret=$(get_yaml_value "secret" "${config_path}")
    # 重载配置
    if [ -z "${secret}" ]; then
        result=$(curl -s -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -d "{\"path\": \"${config_path}\"}")
    else
        result=$(curl -s -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -H "Authorization: Bearer ${secret}" -d "{\"path\": \"${config_path}\"}")
    fi
    if [ -n "$result" ];then
        echo "$result" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p'
        failed "$clash_yaml_failed_msg"
    fi
    # 修改启用配置文件名
    set_subscribe_config '' 'use' "${use}"
    success "$clash_reload_success_msg"
}

# 获取Clash信息
status() {
    _ui=$(get_clashtool_config 'ui')
    _version=$(get_clashtool_config 'version')
    _sub=$(get_subscribe_config '' 'use')
    _proxy=$(get_clashtool_config 'proxy')
    _secret=$(get_yaml_value 'secret' "$config_path")
    _autostart=$(get_clashtool_config 'autoStart')
    if $state; then
        echo "$status_running_msg"
    else
        echo "$status_not_running_msg"
    fi
    echo "${status_ui_msg}${_ui}"
    echo "${status_clash_version_msg}${_version}"
    echo "${status_sub_msg}${_sub}"
    echo "${status_auto_start_msg}${_autostart}"
    echo "${status_secret_msg}${_secret}"
    echo "${status_proxy_msg}${_proxy}"
    echo "${status_clash_path_msg}${clash_path}"
}

# 显示当所有订阅
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

# 添加订阅
add() {
    input=$1
    name=$(echo "${input}" | awk -F '::' '{print $1}')
    url=$(echo "${input}" | awk -F '::' '{print $2}')
    interval=$(echo "${input}" | awk -F '::' '{print $3}')
    # 验证参数
    if [ -z "$name" ] || [ -z "$url" ] || [ -z "$interval" ]; then
        failed "$add_sub_parameter_failed_msg"
    fi
    if existence_subscrib_config "${name}"; then
        # 更新配置
        set_subscribe_config "${name}" 'url' "${url}"
        set_subscribe_config "${name}" 'interval' "${interval}"
        success "$update_sub_success_msg"
    else
        # 创建配置
        add_subscribe_config "$name" "$url" "$interval"
        success "$add_sub_success_msg"
    fi
    # 更新配置定时任务
    auto_update_sub true "${name}"
    # 下载配置
    download_sub "${name}"
}

# 删除订阅
del() {
    name=$1
    if existence_subscrib_config "${name}"; then
        # 关闭自动更新定时任务
        auto_update_sub false "${name}"
        # 删除订阅配置信息
        del_subscribe_config "${name}"
        # 删除下载订阅文件
        if [ -f "${subscribe_dir}/${name}.yaml" ]; then
            rm "${subscribe_dir}/${name}.yaml"
        fi
        # 判断当前订阅是否正在使用
        use=$(get_subscribe_config '' 'use')
        if [ "$use" = "${name}" ]; then
            # 设置订阅配置为default
            set_subscribe_config '' 'use' 'default'
            # 重载配置
            autoreload
        fi
        success "$delete_sub_success_msg"
    else
        failed "$not_sub_exists_msg"
    fi
}

# 更新订阅
update_sub() {
    sub_name=$1
    # 当前使用配置文件
    use=$(get_subscribe_config '' 'use')
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
    autoreload "$use"
}

# 下载订阅配置
download_sub() {
    name=$1
    url=$(get_subscribe_config "${name}" "url")
    temp_sub_path="${subscribe_dir}/${name}.new.yaml"
    download "${temp_sub_path}" "${url}" "${name}" $sub_proxy
    mv "$temp_sub_path" "${subscribe_dir}/${name}.yaml"
}

# 函数名称：crontab_tool
# 参数：
#   $1: interval - 运行间隔，表示每隔几小时运行一次脚本,为0则删除定时任务
#   $2: command - 需要执行的命令或脚本路径
crontab_tool() {
    interval=$1
    command=$2
    if [ "$interval" = "0" ]; then
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
                echo "0 */$interval * * * $command"
            ) | crontab -
        else
            # 定时任务不存在，执行添加操作
            (
                crontab -l
                echo "0 */$interval * * * $command"
            ) | crontab -
        fi
    fi
}

# 根据配置生成定时任务文件
auto_update_sub() {
    enable=${1:-true}
    verify "$enable"
    sub_name=$2
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
                if ! [ "$enable" = "true" ]; then
                    interval=0
                fi
                crontab_tool "$interval" "$script_path update_sub ${name} >> ${logs_dir}/crontab.log 2>&1"
            fi
        done
    else
        # 设置指定定时任务
        if ! [ "$enable" = "true" ]; then
            interval=0
        fi
        interval=$(get_subscribe_config "$sub_name" 'interval')
        crontab_tool "$interval" "$script_path update_sub ${sub_name} >> ${logs_dir}/crontab.log 2>&1"
    fi
}

# 函数：设置开机运行脚本 （由于各linux系统环境差异原因可能会无效）
# 参数: 是否启用开机运行 （可选），默认为 true（true/false）
auto_start() {
    # 开机运行的脚本
    script="$script_path start"
    # 是否开机运行
    enable=${1:-true}
    verify "$enable"
    service_name=$(basename "$script_path")
    service_name=${service_name%.sh}
    # 判断 Linux 发行版
    if [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
        # Ubuntu 或 Debian
        # 启用或禁用开机运行
        if [ "$enable" = "true" ]; then
            # 检查脚本是否已存在
            if [ ! -f "/etc/init.d/$service_name" ]; then
                # 创建服务脚本文件
                {
                    echo "#!/bin/bash"
                    echo "### BEGIN INIT INFO"
                    echo "# Provides:          $service_name"
                    echo "# Required-Start:    \$remote_fs \$syslog"
                    echo "# Required-Stop:     \$remote_fs \$syslog"
                    echo "# Default-Start:     2 3 4 5"
                    echo "# Default-Stop:      0 1 6"
                    echo "# Short-Description: $service_name Script"
                    echo "# Description:       $service_name Script"
                    echo "### END INIT INFO"
                    echo ""
                    echo "$script"
                } >>"/etc/init.d/$service_name"
                chmod +x "/etc/init.d/$service_name"
                update-rc.d "$service_name" defaults >/dev/null 2>&1
            fi
        else
            # 禁用开机运行
            if [ -f "/etc/init.d/$service_name" ]; then
                update-rc.d -f "$service_name" remove >/dev/null 2>&1
                rm "/etc/init.d/$service_name"
            fi
        fi
    elif [ -f /etc/arch-release ]; then
        # Arch Linux  
        # 启用或禁用开机运行
        if [ "$enable" = "true" ]; then
            # 检查脚本是否已存在
            if [ ! -f "/etc/systemd/system/$service_name.service" ]; then
                # 添加 systemd 服务
                {
                    echo "[Unit]"
                    echo "Description=My Startup Script"
                    echo ""
                    echo "[Service]"
                    echo "ExecStart=$script"
                    echo "Type=simple"
                    echo ""
                    echo "[Install]"
                    echo "WantedBy=default.target"
                } >>"/etc/systemd/system/$service_name.service"
                systemctl enable "$service_name.service" >/dev/null 2>&1
            fi
        else
            # 禁用开机运行
            if [ -f "/etc/systemd/system/$service_name.service" ]; then
                systemctl disable "$service_name.service" >/dev/null 2>&1
                rm "/etc/systemd/system/$service_name.service"
                systemctl daemon-reload >/dev/null 2>&1
            fi
        fi
    elif [ -f /etc/alpine-release ]; then
        # Alpine Linux
        rc_local_file="/etc/local.d/$service_name.start"
    
        # 启用或禁用开机运行
        if [ "$enable" = "true" ]; then
            # 检查脚本是否已存在
            if [ ! -f "$rc_local_file" ]; then
                # 创建开机启动脚本
                echo "$script" >>"$rc_local_file"
                chmod +x "$rc_local_file"
            fi
        else
            # 禁用开机运行
            if [ -f "$rc_local_file" ]; then
                sed -i "\|^$script|d" "$rc_local_file"
            fi
        fi
    
        # 检查服务是否已添加
        if ! rc-status | grep -qw "local"; then
            # 添加服务到开机启动
            rc-update add local default >/dev/null 2>&1
        fi
    elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
        # CentOS
        rc_local_file="/etc/rc.d/$service_name.local"
    
        # 启用或禁用开机运行
        if [ "$enable" = "true" ]; then
            # 检查脚本是否已存在
            if ! grep -qF "$script" "$rc_local_file"; then
                # 将脚本添加到 rc.local
                echo "$script" | tee -a "$rc_local_file" >/dev/null
            fi
        else
            # 禁用开机运行
            if [ -f "$rc_local_file" ]; then
                sed -i "\|^$script|d" "$rc_local_file"
            fi
        fi
    else
        failed "$unsupported_linux_distribution_failed_msg"
    fi
    
    set_clashtool_config 'autoStart' "${enable}"
    
    if [ "$enable" = "true" ]; then
        success "$auto_start_enabled_success_msg"
    else
        success "$auto_start_turned_off_success_msg"
    fi
}

# 开启系统代理
proxy_on() {
    if $state;then
        proxy_host="http://127.0.0.1:$(get_yaml_value 'port' "$user_config_path")"
        # 检查 "$bashrc" 是否存在，并添加或修改代理设置
        if [ -f "$bashrc" ]; then
            for key in $proxy_keys; do
                if grep -q "$key=" "$bashrc"; then
                    # 如果已存在，则进行修改
                    sed -i "s|${key}=.*|${key}=${proxy_host}|" "$bashrc"
                else
                    # 如果不存在，则添加设置
                    echo "export $key=$proxy_host" >> "$bashrc"
                fi
                export "$key"="$proxy_host" 
            done
            if ! grep -q "no_proxy=" "$bashrc"; then
                # 如果不存在，则添加设置
                echo "export no_proxy=localhost,127.0.0.1" >> "$bashrc"
                export no_proxy="localhost,127.0.0.1"          
            fi
        else
            for key in $proxy_keys; do
                echo "export $key=$proxy_host" >> "$bashrc"
                export "$key"="$proxy_host" 
            done
            echo "export no_proxy=localhost,127.0.0.1"
            export no_proxy="localhost,127.0.0.1" 
        fi
        # 更改配置文件中的代理状态
        set_clashtool_config 'proxy' "$enable"
        success "$proxy_on_success_msg"
    else
        warn "$clash_not_running_warn_msg" false
    fi
}

# 关闭系统代理
proxy_off(){
    for key in $proxy_keys; do
        sed -i "/$key=/d" "$bashrc"
        unset "$key"
    done
    sed -i "/no_proxy=/d" "$bashrc"
    unset no_proxy
    # 更改配置文件中的代理状态
    set_clashtool_config 'proxy' "$enable"
	success "$proxy_off_success_msg"
}

proxy(){
    enable=${1:-true}
    verify "$enable"
    if [ "$enable" = "true" ];then
        if [ -f "${clash_path}" ]; then
            if $state ;then
                proxy_on
            else
                failed "$clash_not_running_warn_msg"
            fi
        else
            failed "$not_install_clash_msg"
        fi
    else
        proxy_off
    fi
}
# 主函数
main() {
    fun=$1
    var=$2
    # 更新chinese参数设置是否汉化提示信息
    if $chinese;then
        chinese_language
    fi
    # 判断使用的命令类型
    if [ "${0#-}" = "$0" ];then
        case "${fun}" in
        "install")
            install "$var"
            ;;
        "uninstall"|"update"|"install_ui"|"start"|"stop"|"restart"|"reload"|"add"|"del"|"update_sub"|"list"|"auto_start"|"status")
            if [ -f "$clash_path" ]; then
                case "${fun}" in
                "uninstall")
                    uninstall "$var"
                    ;;
                "update")
                    update "$var"
                    ;;
                "install_ui")
                    install_ui "$var"
                    ;;
                "start")
                    start "$var"
                    ;;
                "stop")
                    stop
                    ;;
                "restart")
                    restart "$var"
                    ;;
                "reload")
                    reload "$var"
                    ;;
                "add")
                    add "$var"
                    ;;
                "del")
                    del "$var"
                    ;;
                "update_sub")
                    update_sub "$var"
                    ;;
                "list")
                    list
                    ;;
                "auto_start")
                    auto_start "$var"
                    ;;
                "status")
                    status
                    ;;
                esac
            else
                failed "$not_install_clash_msg"
            fi
            ;;
        "proxy")
            failed "$proxy_not_source_command_msg" false
            remind "${proxy_proxy_command_msg} $enable"
            ;;
        "help")
            echo "$help_msg"
            ;;
        *)
            echo "$main_msg"
            ;;
        esac 
    else
        if [ "$fun" = "proxy" ];then
            proxy "$var"
        else
            failed "$proxy_source_command_msg" false
        fi
    fi
}

# 执行主函数
main "$1" "$2"
