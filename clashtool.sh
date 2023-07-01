#!/bin/sh

# 网页初始链接密码
secret='12123'
# clash平台，为空则自动获取，获取失败请自行填写
platform=''

# 当前脚本路径
script_path=$(readlink -f "$0")
# 当前脚本目录
tool_catalog=$(dirname "$script_path")
# clash 安装目录
clash_catalog="${tool_catalog}/clash"
# clash 配置目录
config_catalog="${clash_catalog}/config"
# clash UI目录
clash_gh_pages_catalog="${clash_catalog}/clash_gh_pages"
# clash 日志目录
logs_catalog="${clash_catalog}/logs"
# clash文件
clash_path="${clash_catalog}/clash"

# clash配置文件
config_path="${config_catalog}/config.yaml"
# 订阅配置目录
subscribe_config_catalog="${config_catalog}/subscribe"
# clashtool 配置文件
clashtool_config_path="${config_catalog}/clashtool.ini"

# 保存程序运行状态
pid=$(pgrep -f "$clash_path")
if [ -z "$pid" ]; then
    state=false
else
    state=true
fi

# 验证true false ''默认为true
verify() {
    if [ "$1" != 'true' ] && [ "$1" != 'false' ]; then
        echo "The parameter can only be true, false, or '', and '' defaults to true"
        exit 1
    fi
}

# 检查并安装依赖
require() {
    # 检查包管理器
    if command -v apt >/dev/null 2>&1; then
        package_manager="apt"
    elif command -v yum >/dev/null 2>&1; then
        package_manager="yum"
    elif command -v apk >/dev/null 2>&1; then
        package_manager="apk"
    else
        echo "Unable to determine the package manager. Please install curl, wget, yq yourself"
        exit 1
    fi

    # 检查并安装curl
    if ! command -v curl >/dev/null 2>&1; then
        echo "Install curl..."
        if [ "$package_manager" = "apt" ]; then
            apt install -y curl
        elif [ "$package_manager" = "yum" ]; then
            yum install -y curl
        elif [ "$package_manager" = "apk" ]; then
            apk add --update curl
        fi
    fi

    # 检查并安装wget
    if ! command -v wget >/dev/null 2>&1; then
        echo "Install wget..."
        if [ "$package_manager" = "apt" ]; then
            apt install -y wget
        elif [ "$package_manager" = "yum" ]; then
            yum install -y wget
        elif [ "$package_manager" = "apk" ]; then
            apk add --update wget
        fi
    fi

    # 检查并安装yq
    if ! command -v yq >/dev/null 2>&1; then
        echo "Install yq..."
        if [ "$package_manager" = "apt" ]; then
            apt install -y yq
        elif [ "$package_manager" = "yum" ]; then
            yum install -y yq
        elif [ "$package_manager" = "apk" ]; then
            apk add --update yq
        fi
    fi
}

init() {

    # 创建clash目录
    if [ ! -d "${clash_catalog}" ]; then
        mkdir -p ${clash_catalog}
    fi
    # 创建配置目录
    if [ ! -d "${config_catalog}" ]; then
        mkdir -p ${config_catalog}
    fi
    # 创建UI目录
    if [ ! -d "${clash_gh_pages_catalog}" ]; then
        mkdir -p ${clash_gh_pages_catalog}
    fi
    # 创建logs目录
    if [ ! -d "${logs_catalog}" ]; then
        mkdir -p ${logs_catalog}
    fi
    # 创建subscribe配置目录
    if [ ! -d "${subscribe_config_catalog}" ]; then
        mkdir ${subscribe_config_catalog}
    fi
    # 创建clashtool和订阅配置文件
    if [ ! -f "${clashtool_config_path}" ]; then
        {
            echo "[clashtool]"
            echo "ui=dashboard"
            echo "version=v0.0.0"
            echo "autostart=false"
            echo "autoupdatesub=true"
            echo ""
            echo "[subscribe]"
            echo "names="
            echo "use=default"
        } >>"${clashtool_config_path}"
    fi
    # 创建默认clash配置文件
    if [ ! -f "${config_path}" ]; then
        {
            echo "port: 7890"
            echo "socks-port: 7891"
            echo "allow-lan: true"
            echo "mode: Rule"
            echo "log-level: error"
            echo "external-controller: 0.0.0.0:9090"
            echo "external-ui: ${clash_gh_pages_catalog}"
            echo "secret: ${secret}"
        } >>"$config_path"
    fi

    echo "Initialization successful"
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
        echo "Section not found: $section"
        # 如果节不存在，则添加新节和键值对
        echo "[$section]" >>"$file"
        echo "$key=$value" >>"$file"
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
    else
        echo "Section not found: $section"
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
            $0 ~ /^\[.*\]$/ { in_section=($0 == "["section"]") }  # 进入指定节
            in_section && $1 == key {  # 在指定节中找到指定键
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
    else
        echo "Section not found: $section"
    fi
}

# 获取clashtool配置
get_clashtool_config() {
    key=$1
    read_ini ${clashtool_config_path} 'clashtool' "${key}"
}

# 添加修改clashtool配置
set_clashtool_config() {
    key=$1
    val=$2
    write_ini ${clashtool_config_path} "clashtool" "${key}" "${val}"
}

# 判断订阅是否存在
existence_subscrib_config() {
    sec=$1
    section_exists ${clashtool_config_path} "subscribe_${sec}"
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
    names=$(get_subscribe_config '' 'names' | sed "s/${sub}//g")
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

# 状态为运行则启动
autostart() {
    if $state; then
        start "$1"
    fi
}

# 状态为运行则停止
autostop() {
    if $state; then
        stop
    fi
}

autorestart() {
    if $state; then
        restart "$1"
    fi
}

# 状态为运行则重载配置
autoreload() {
    if $state; then
        reload "$1"
    fi
}

install_clash() {
    # 没有指定版本则更新最新版本
    if [ -z "${version}" ]; then
        # 获取clash最新版本号
        version=$(curl -k -s https://api.github.com/repos/Dreamacro/clash/releases/latest | sed 's/[\" ,]//g' | grep '^tag_name' | awk -F ':' '{print $2}')
        if [ -z "${version}" ]; then
            echo "Failed to obtain version"
            exit 1
        fi
    fi
    # 获取配置中当前安装的版本
    current=$(get_clashtool_config 'version')
    # 不是第一次安装则不显示当前版本
    if [ -n "${current}" ]; then
        echo "Current version: ${current}"
    fi
    # 要安装的版本
    echo "installed version: ${version}"
    # 判断版本是否相等
    if [ "${current}" = "${version}" ]; then
        echo "No update required"
        exit 0
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
            echo "Unable to determine the architecture type of the current operating system. Please fill in the configuration yourself"
            exit 1
            ;;
        esac
    fi
    # 下载clash
    wget -O "${clash_catalog}/${platform}-${version}.gz" "https://gh.ylpproxy.eu.org/https://github.com/Dreamacro/clash/releases/download/${version}/clash-linux-${platform}-${version}.gz"
    # 下载成功则安装clash
    if [ -f "${clash_catalog}/${platform}-${version}.gz" ]; then
        # 解压clash
        gunzip -f "${clash_catalog}/${platform}-${version}.gz"
        # 重命名clash
        mv "${clash_catalog}/${platform}-${version}" "${clash_path}"
        # 赋予运行权限
        chmod 755 ${clash_path}
        # 向clash配置文件写入当前版本
        set_clashtool_config 'version' "${version}"
    else
        echo "Download failed"
        exit 1
    fi
}

# 安装UI
install_ui() {
    ui=$1
    # 没有指定UI则使用配置中指定UI
    if [ -z "${ui}" ]; then
        ui=$(get_clashtool_config 'ui')
    fi
    # 下载UI安装包
    if [ "${ui}" = "dashboard" ]; then
        set_clashtool_config 'ui' "dashboard"
        ui="clash-dashboard-gh-pages"
        wget -O ${clash_catalog}/gh-pages.zip https://gh.ylpproxy.eu.org/https://github.com/Dreamacro/clash-dashboard/archive/refs/heads/gh-pages.zip
    elif [ "${ui}" = "yacd" ]; then
        # 在clashtool配置文件中写入ui
        set_clashtool_config 'ui' "yacd"
        ui="yacd-gh-pages"
        wget -O ${clash_catalog}/gh-pages.zip https://gh.ylpproxy.eu.org/https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip
    else
        echo "Command error, UI is dashboard or yacd"
        exit 1
    fi
    if [ -f "${clash_catalog}/gh-pages.zip" ]; then
        # 删除当前已安装UI
        rm -rf ${clash_gh_pages_catalog}
        # 解压
        unzip -d ${clash_catalog} ${clash_catalog}/gh-pages.zip
        # 重命名
        mv ${clash_catalog}/${ui} ${clash_gh_pages_catalog}
        # 删除已下载文件
        rm ${clash_catalog}/gh-pages.zip
    else
        echo 'Failed to download UI'
        exit 1
    fi
}

# 安装clash
install() {
    version=$1
    # 判断是否已经安装clash
    if [ -f "${clash_path}" ]; then
        echo "Clash installed"
    else
        echo "Start installing clash"
        # 安装依赖软件
        require
        # 初始化目录配置
        init
        # 安装 clash
        install_clash "$version"
        # 安装 ui
        install_ui
        echo 'Successfully installed Clash'
    fi
}

# 卸载clash
uninstall() {
    # 删除clash
    if [ -d "${clash_catalog}" ]; then
        # 停止clash运行
        autostop false
        # 关闭自动启动
        auto_start false
        if [ "$1" = "all" ]; then
            # 关闭自动更新配置
            auto_update_sub false
            # 删除Clash所有相关文件
            rm -rf ${clash_catalog}
        else
            # 删除clash程序文件
            rm -rf ${clash_path}
        fi
    fi
    echo "Uninstall succeeded"
}

# 更新clash
update() {
    version=$1
    if [ ! -f "${clash_path}" ]; then
        echo "Clash not installed"
    else
        install_clash "$version"
        # 重启
        autorestart ''
        echo "Successfully updated Clash"
    fi
}

# 启动clash
start() {
    # 判断是否正在运行
    if $state; then
        echo "Program already running"
    else
        echo "Start loding..."
        if [ -f "${clash_path}" ]; then
            # 启动clash
            nohup ${clash_path} -f ${config_path} >${logs_catalog}/clash.log 2>&1 &
            pid="$!"
            state=true
            # 等待Clash启动成功
            sleep 6
            # 载入配置
            reload "$1"
            echo "Start succeeded"
        else
            echo "Clash Program path not installed or specified"
        fi
    fi
}

# 停止clash
stop() {
    # 判断程序是否运行
    if ${state}; then
        # 根据clash PID 结束Clash
        kill -9 "${pid}"
        echo "Stop succeeded"
    else
        echo "not running"
    fi
}

# 重启clash
restart() {
    stop
    start
}

# 重载clash配置文件
reload() {
    use=$1
    if ! $state; then
        echo "Clash not running"
        exit 1
    fi

    if [ -z ${use} ]; then
        use=$(get_subscribe_config '' 'use')
    elif ! existence_subscrib_config "${use}"; then
        # 不存在该订阅配置
        echo "The subscription could not be found"
        exit 1
    fi

    if [ "$use" = 'default' ]; then
        # 使用默认配置
        echo "Use default configuration"
        cp ${config_path} ${config_catalog}/temp_config.yaml
    else
        # 把自定义文件覆写到下载的配置文件中生成临时配置文件
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${config_path}" "${subscribe_config_catalog}/${use}.yaml" >"${config_catalog}/temp_config.yaml"
    fi
    port=$(yq eval ".external-controller" "${config_path}" | awk -F ':' '{print $2}')
    secret=$(yq eval ".secret" "${config_path}")
    # 重载配置
    if [ -z "${secret}" ]; then
        curl -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -d "{\"path\": \"${config_catalog}/temp_config.yaml\"}"
    else
        curl -X PUT "http://127.0.0.1:${port}/configs" -H "Content-Type: application/json" -H "Authorization: Bearer ${secret}" -d "{\"path\": \"${config_catalog}/temp_config.yaml\"}"
    fi

    # 修改启用配置文件名
    set_subscribe_config '' 'use' "${use}"
    echo "reload succeeded"
}

# 获取Clash信息
status() {
    u=$(get_clashtool_config 'ui')
    v=$(get_clashtool_config 'version')
    s=$(get_subscribe_config '' 'use')
    as=$(get_clashtool_config 'autostart')
    if $state; then
        echo "status: started"
    else
        echo "status: stopped"
    fi
    echo "ui：$u"
    echo "version：$v"
    echo "subscribe: $s"
    echo "autoStart: $as"
    echo "installCatalog: $clash_catalog"
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
            echo "url: $url"
            echo "interval: $interval"
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
        echo "Invalid input string: $input"
        exit 1
    fi
    if existence_subscrib_config "${name}"; then
        # 更新配置
        set_subscribe_config "${name}" 'url' "${url}"
        set_subscribe_config "${name}" 'interval' "${interval}"
        echo "Update subscribe succeeded"
    else
        # 创建配置
        add_subscribe_config $name $url $interval
        echo "Add subscribe succeeded"
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
        if [ -f "${subscribe_config_catalog}/${name}.yaml" ]; then
            rm "${subscribe_config_catalog}/${name}.yaml"
        fi
        # 判断当前订阅是否正在使用
        use=$(get_subscribe_config '' 'use')
        if [ "$use" = "${name}" ]; then
            # 设置订阅配置为default
            set_subscribe_config '' 'use' 'default'
            # 重载配置
            autoreload
        fi
        echo "Delete subscription succeeded"
    else
        echo "The subscription was not found"
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
            download_sub "${sub_name}"
        else
            # 更新指定订阅配置
            if existence_subscrib_config "${sub_name}"; then
                download_sub "${sub_name}"
                echo "update subscribe ok"
            else
                echo "No such subscription"
            fi
        fi
    fi
    # 重载配置文件
    autoreload "$use"
}

# 下载订阅配置
download_sub() {
    name=$1
    url=$(get_subscribe_config "${name}" "url")
    echo "start dowload: ${name}.conf"
    wget -O "${subscribe_config_catalog}/${name}.new.yaml" "${url}"
    if [ -f "${subscribe_config_catalog}/${name}.new.yaml" ]; then
        mv "${subscribe_config_catalog}/${name}.new.yaml" "${subscribe_config_catalog}/${name}.yaml"
    else
        echo "Failed to download ${name}.ymal"
        exit 1
    fi
    echo "download ok"
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
            echo "Deleted scheduled task: $command"
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
            echo "Updated scheduled task: Run $command every $interval hours"
        else
            # 定时任务不存在，执行添加操作
            (
                crontab -l
                echo "0 */$interval * * * $command"
            ) | crontab -
            echo "Added scheduled task: Run $command every $interval hours"
        fi
    fi
}

# 根据配置生成定时任务文件
auto_update_sub() {
    enable=${1:-true}
    verify "$enable"
    sub_name=$2
    # 判断是否存在订阅配置
    if [ -n "$sub_name" ] && existence_subscrib_config "$sub_name"; then
        echo "There is no subscription configuration for $sub_name "
    fi
    if [ -z "$sub_name" ]; then
        # 为空则根据配置和enable重新设置全部定时任务
        names=$(get_subscribe_config '' 'names')
        echo "$names" | tr ',' '\n' | while IFS= read -r name; do
            if [ -n "$name" ]; then
                interval=$(get_subscribe_config "$name" 'interval')
                if ! $enable; then
                    interval=0
                fi
                crontab_tool "$interval" "$script_path update_sub ${name} >> ${logs_catalog}/crontab.log 2>&1"
            fi
        done
    else
        # 设置指定定时任务
        if ! $enable; then
            interval=0
        fi
        crontab_tool "$interval" "$script_path update_sub ${sub_name} >> ${logs_catalog}/crontab.log 2>&1"
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
    # 判断 Linux 发行版
    if [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
        # Ubuntu 或 Debian
        service_name="myscript"

        # 启用或禁用开机运行
        if $enable; then
            # 创建服务脚本文件
            {
                echo "#!/bin/bash"
                echo "### BEGIN INIT INFO"
                echo "# Provides:          $service_name"
                echo "# Required-Start:    \$remote_fs \$syslog"
                echo "# Required-Stop:     \$remote_fs \$syslog"
                echo "# Default-Start:     2 3 4 5"
                echo "# Default-Stop:      0 1 6"
                echo "# Short-Description: My Startup Script"
                echo "# Description:       My Startup Script"
                echo "### END INIT INFO"
                echo ""
                echo "$script"
            } >>"/etc/init.d/$service_name"
            chmod +x "/etc/init.d/$service_name"
            update-rc.d "$service_name" defaults
        else
            # 禁用开机运行
            update-rc.d -f "$service_name" remove
            rm "/etc/init.d/$service_name"
        fi

        echo "Successfully set startup and running scripts"
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        service_name="myscript"

        # 启用或禁用开机运行
        if $enable; then
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
            systemctl enable "$service_name.service"
        else
            # 禁用开机运行
            systemctl disable "$service_name.service"
            rm "/etc/systemd/system/$service_name.service"
            systemctl daemon-reload
        fi
    elif [ -f /etc/alpine-release ]; then
        # Alpine Linux
        rc_local_file="/etc/local.d/startup.start"

        # 启用或禁用开机运行
        if $enable; then
            # 创建开机启动脚本
            echo "$script" >>"$rc_local_file"
            chmod +x "$rc_local_file"
        else
            # 禁用开机运行
            sed -i "\|^$script|d" "$rc_local_file"
        fi

        # 检查 服务是否已添加
        if ! rc-status | grep -qw "local"; then
            # 添加 服务到开机启动
            rc-update add local default
        fi
    elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
        # CentOS
        rc_local_file="/etc/rc.d/rc.local"

        # 启用或禁用开机运行
        if $enable; then
            # 判断脚本是否已添加到 rc.local
            if ! grep -qF "$script" "$rc_local_file"; then
                # 将脚本添加到 rc.local
                echo "$script" | tee -a "$rc_local_file" >/dev/null
            fi
        else
            # 禁用开机运行
            sed -i "\|^$script|d" "$rc_local_file"
        fi
    else
        echo "Unsupported Linux distribution"
        exit 1
    fi
    set_clashtool_config 'autostart' "${enable}"
    if ${enable}; then
        echo 'Successfully enabled automatic start'
    else
        echo 'Successfully turned off automatic start'
    fi
}

# 说明

hepl() {
echo " Command                Parameters                            Remarks"
echo "install        version            Optional       Install Clash, default is the latest version"
echo "uninstall      all                Optional       Uninstall Clash, with 'all' parameter deletes related configurations"
echo "update         version            Optional       Update Clash, default is the latest version"
echo "install_ui     dashboard or yacd  Optional       Install web interface, default is dashboard"
echo "start          Subscription Name                 Start Clash, by default uses the current subscription configuration"
echo "stop            -                                Stop Clash from running"
echo "restart        Subscription Name  Optional       Restart Clash, by default uses the current subscription configuration"
echo "reload         Subscription Name  Optional       Reload Clash, by default uses the current subscription configuration"
echo "add            Subscription                      Info Add subscription info: Format '<Subscription Name::Subscription URL::Subscription Update Interval (hours)>'"
echo "del            Subscription Name                 Delete subscription"
echo "update_sub     Subscription Name  Optional       Update subscription files, by default updates all subscription files"
echo "list           -                                 Query all subscription information"
echo "auto_start     true or false      Optional       Enable or disable auto-start on boot, default is true"
echo "status         -                                 View Clash status information"
}

main() {
    fun=$1
    var=$2
    case "${fun}" in
    "install")
        install "${var}"
        ;;
    "uninstall")
        uninstall "${var}"
        ;;
    "update")
        update "${var}"
        ;;
    "install_ui")
        install_ui "${var}"
        ;;
    "start")
        start "${var}"
        ;;
    "stop")
        stop
        ;;
    "restart")
        restart "${var}"
        ;;
    "reload")
        reload "${var}"
        ;;
    "add")
        add "${var}"
        ;;
    "del")
        del "${var}"
        ;;
    "update_sub")
        update_sub "${var}"
        ;;
    "list")
        list
        ;;
    "auto_start")
        auto_start "${var}"
        ;;
    "auto_update_sub")
        auto_update_sub "${var}"
        ;;
    "status")
        status
        ;;
    *)
        hepl
        ;;
    esac
}

main "$1" "$2"
