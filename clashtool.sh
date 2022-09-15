#!/bin/sh

set -e
command=$1
command2=$2
clash_catalog="/usr/local/clash"
config_catalog="/root/.config/clash"
clash_path="${clash_catalog}/clash"
version_path="${config_catalog}/version"
config_path="${clash_catalog}/config.yaml"
user_config_path="${config_catalog}/default_config.yaml"

autoecreate
if [[ "help" == ${command} ]]; then                                         
    help
elif [[ "install" == ${command} ]]; then
    install
elif [[ "install-ui" == ${command} ]]; then
    stop
	if [[ -e $command2 ]]; then
	    $command2="dashboard"
	fi
    install-ui
elif [[ "uninstall" == ${command} ]]; then
    stop
    uninstall
elif [[ "uninstall-ui" == ${command} ]]; then
    stop
    uninstall-ui 
elif [[ "update" == ${command} ]]; then
    update
elif [[ "update-ui" == ${command} ]]; then
    update-ui
elif [[ "start" == ${command} ]]; then
    start
elif [[ "stop" == ${command} ]]; then
    stop
elif [[ "restart" == ${command} ]]; then
    restart
elif [[ "subscribe" == ${command} ]]; then
    restart
elif [[ "reload" == ${command} ]]; then
    reload
else
	help
fi

autoconfig(){
    if [[ -f "${cd_path}/${1}" ]]; then
		cp ${cd_path}/${1} $config_path
	fi
	IFS_old=$IFS
    IFS=$'\n'
	count=0
	for line in `cat ${user_config_path}`
    do
        count=$((${count} + 1))
        sed -i '/^'${line%: *}'/d' ${config_path}
        sed -i ${count}'i\'${line} ${config_path}
    done
	IFS=$IFS_old
}

autoecreate(){
    if [[ -d "${clash_catalog}" ]]; then
		mkdir -p ${clash_catalog}
	fi
	
    if [[ -d "${config_catalog}/config.d" ]]; then
		mkdir - p ${config_catalog}/config.d
	fi
	
	if [[ -f "${version_path}" ]]; then
        echo "v0.0.0" > ${version_path}
	fi
	
	if [[ -f "${config_catalog}/pid" ]]; then
        echo "" > ${config_catalog}/pid
	fi
	
	if [[ -f "${config_catalog}/subscribe" ]]; then
        echo "# status：0 or 1，0:stop  1:start" > ${config_catalog}/subscribe
        echo "status name url" > ${config_catalog}/subscribe
	fi
	
    if [[ -f "${user_config_path}" ]]; then
        echo "port: 7890" >> $user_config_path
        echo "socks-port: 7891" >> $user_config_path
        echo "allow-lan: true" >> $user_config_path
        echo "mode: Rule" >> $user_config_path
        echo "log-level: error" >> $user_config_path
        echo "external-controller: 0.0.0.0:9090" >> $user_config_path
		echo "secret" >> $user_config_path
	fi
}

hepl(){
	echo "command               command2"
	echo "install       (dashboard or yacd) default ''  no install ui"
	echo "install-ui    (dashboard or yacd) default dashboard"          
	echo "uninstall     (ui or config or all) default '' uninstall clash"     
	echo "uninstall-ui  (not command2)"
	echo "update        (ui or all) default '' uninstall clash command2"
	echo "update-ui     (dashboard or yacd) default"  
	echo "start         (config name) default default_config"
	echo ""
	echo ""
	echo ""
}

install(){
    if [[ -f $clash_path ]]; then
        echo "Clash installed"
	else
        echo "start install clash"
        latest=$(curl -k -s https://api.github.com/repos/Dreamacro/clash/releases/latest | grep '^tag_name' | awk -F ': ' '{print $2}' | sed 's/[\",]//g')
        wget -O ${clash_path}-linux-amd64-${latest}.gz "https://github.com/Dreamacro/clash/releases/download/${latest}/clash-linux-amd64-${latest}.gz"
        gunzip ${clash_path}-linux-amd64-${latest}.gz
        mv ${clash_path}-linux-amd64-$latest ${clash_path}
        chmod 755 ${clash_path}
	    echo ${latest} > version_path
        echo "install clash ok"
	    install-ui
	fi
}

install-ui(){
	clash-gh-pages="${clash_catalog}/clash-gh-pages"
	if [[ -d ${clash-gh-pages} ]]; then
        echo "Clash ui installed"
	else
        echo "start install ui"
	    if [[ $command2 == "dashboard" ]]; then
            ui="clash-dashboard-gh-pages" 
	    	wget -O ${clash_catalog}/gh-pages https://codeload.github.com/Dreamacro/clash-dashboard/zip/refs/heads/gh-pages
        elif [[ $command2 == "yacd" ]]; then
	        ui="yacd-gh-pages" 
            wget -O ${clash_catalog}/gh-pages https://codeload.github.com/haishanh/yacd/zip/refs/heads/gh-pages		
	    else
            echo "Command error, ui is dashboard or yacd"
	    	exit 0
	    fi 
        unzip ${clash_catalog}/gh-pages
        mv ${clash_catalog}/${ui} ${clash-gh-pages}
	    [[ -e $(cat ${user_config_path} | grep '^external-ui: ') ]] && sed -i "1i\${clash-gh-pages}" ${user_config_path} || sed -i "/^external-ui: /c external-ui: ${clash-gh-pages}'" ${user_config_path}
	    echo "install ${command2} ui ok" 
	fi
}

uninstall(){
    echo "start uninstall clash"
	rm $clash_path
	if [[ $command2 == "ui" ]]; then
		uninstall-ui
    fi
    if [[ $command2 == "config" ]]; then
	    rm -rf $config_catalog
    fi
    if [[ $command2 == "all" ]]; then
	    rm -rf $clash_catalog
	    rm -rf $config_catalog
    fi
	echo "uninstall clash ok"
}

uninstall-ui(){
    echo "start uninstall ui"
	rm -rf "${clash_catalog}/clash-gh-pages"
	sed -i "/^external-ui: /d" ${user_config_path}
	echo "uninstall ui ok"
}

update(){
	current=$(cat version_path)
	latest=$(curl -k -s https://api.github.com/repos/Dreamacro/clash/releases/latest | grep '^tag_name' | awk -F ': ' '{print $2}' | sed 's/[\",]//g')
	echo "Current version: ${current}"
	echo "Latest  version: ${latest}"
    if [[ $latest != $current ]]; then
		echo "Updating..."
        wget -O ${clash_path}-linux-amd64-${latest}.gz "https://github.com/Dreamacro/clash/releases/download/${latest}/clash-linux-amd64-${latest}.gz"
        gunzip ${clash_path}-linux-amd64-${latest}.gz
        mv ${clash_path} ${config_catalog}/backup/clash`date '+%Y%m%d%H%M%S'`
        mv ${clash_path}-linux-amd64-$latest ${clash_path}
        chmod 755 ${clash_path}
		echo ${latest} > version_path
        echo "update ok"
		start
    else
    	echo "No update required"
    fi
}

update-ui(){
	echo "update ui start"
	uninstall-ui
	install-ui
	echo "update ui ok"
}

start (){
    nohup ${clash_path} > ${config_catalog}/clash.log 2>&1 &
    echo "$!" > ${config_catalog}/pid
    echo "start ok  "`cat ${config_catalog}/pid`
}

stop (){
    kill `cat ${config_catalog}/pid`
    echo "stop ok  "`cat ${config_catalog}/pid`
}

restart (){
    stop
    start
    echo "restart ok"
}

subscribe(){
    echo "dowload:" `cat ${config_catalog}/subscribe` 
    wget -O ${config_path}.new `cat ${config_catalog}/subscribe`
    count=1
    if [[ ! -d "${config_catalog}/backup" ]]; then
        echo "create backup directory"
        mkdir ${config_catalog}/backup
    fi
    mv ${config_path} ${config_catalog}/backup/config`date '+%Y%m%d%H%M%S'`
    mv ${config_path}.new ${config_path}
}

reload (){
    
    port=$(cat ${user_config_path} | grep '^external-controller: ' | awk -F ':' '{print $3}' | sed "s/[\'\"]//g")
    port=$([[ -z ${port} ]] && echo "9090" || echo "$port")
    secret=$(cat ${user_config_path} | grep '^secret: ' | awk -F ': ' '{print $2}' | sed "s/[\'\"]//g")
    config=${config_catalog}/$([[ -z ${command2} ]] && echo "config.yaml" || echo $command2)
    if [[ -z $secret ]]; then
        curl -X PUT http://127.0.0.1:${port}/configs -H "Content-Type: application/json" -d "{\"path\": \"${config}\"}"
    else
        curl -X PUT http://127.0.0.1:${port}/configs -H "Content-Type: application/json" -H "Authorization: Bearer ${secret}" -d "{\"path\": \"${config}\"}"
    fi
    echo "reload ok"
}

