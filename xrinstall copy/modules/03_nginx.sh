#!/usr/bin/env bash
# 模块 03：Docker/Nginx 环境与工具安装

checkDockerNginx() {
    if ! command -v docker &> /dev/null; then
        return
    fi
    
    local dockerNginx=$(docker ps --filter "name=nginx" --format "{{.Names}}" 2>/dev/null)
    if [[ -n "${dockerNginx}" ]]; then
        echoContent yellow "\n检测到 Docker Nginx 容器:"
        echo "${dockerNginx}" | while read -r container; do
            local status=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null)
            local confPath=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/etc/nginx"}}{{.Source}}{{end}}{{end}}' "${container}" 2>/dev/null)
            echoContent skyBlue "  容器名: ${container}"
            echoContent green "    状态: ${status}"
            if [[ -n "${confPath}" ]]; then
                echoContent green "    配置路径: ${confPath}"
            fi
        done
        echoContent skyBlue ""
        return 0
    fi
    return 1
}

# Nginx 环境检测
checkNginxEnvironment() {
    local hasNginx=false
    
    # 检测系统 Nginx
    if command -v nginx &> /dev/null; then
        hasNginx=true
        echoContent skyBlue "\n========== Nginx 环境检测 ==========\n"
        
        # Nginx 版本
        local nginxVer=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
        echoContent green "Nginx 版本: ${nginxVer}"
        
        # 配置文件数量
        local confCount=$(find /etc/nginx/conf.d /etc/nginx/sites-enabled -name "*.conf" 2>/dev/null | wc -l)
        echoContent yellow "现有配置文件: ${confCount} 个"
        
        # 监听的端口
        local ports=$(netstat -tlnp 2>/dev/null | grep nginx | awk '{print $4}' | awk -F':' '{print $NF}' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [[ -n "${ports}" ]]; then
            echoContent yellow "监听端口: ${ports}"
        fi
        
        # 配置的域名
        local domains=$(grep -rh "server_name" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null | grep -v "server_name _" | awk '{for(i=2;i<=NF;i++)print $i}' | sed 's/;//g' | sort -u | head -5)
        if [[ -n "${domains}" ]]; then
            echoContent yellow "已配置域名:"
            echo "${domains}" | while read -r d; do
                echoContent skyBlue "  - ${d}"
            done
        fi
        
        echoContent skyBlue "\n====================================\n"
    fi
    
    # 检测 Docker Nginx
    checkDockerNginx
    
    # 如果都没有检测到 Nginx
    if [[ "${hasNginx}" == "false" ]] && ! command -v docker &> /dev/null; then
        return
    fi
}

initVar "$1"
checkSystem
checkCPUVendor

readInstallType
readInstallProtocolType
readConfigHostPathUUID
readCustomPort
readSingBoxConfig
checkNginxEnvironment
# -------------------------------------------------------------

# 初始化安装目录
mkdirTools() {
    mkdir -p /opt/xray-agent/tls
    mkdir -p /opt/xray-agent/subscribe_local/default
    mkdir -p /opt/xray-agent/subscribe_local/clashMeta

    mkdir -p /opt/xray-agent/subscribe_remote/default
    mkdir -p /opt/xray-agent/subscribe_remote/clashMeta

    mkdir -p /opt/xray-agent/subscribe/default
    mkdir -p /opt/xray-agent/subscribe/clashMetaProfiles
    mkdir -p /opt/xray-agent/subscribe/clashMeta

    mkdir -p /opt/xray-agent/subscribe/sing-box
    mkdir -p /opt/xray-agent/subscribe/sing-box_profiles
    mkdir -p /opt/xray-agent/subscribe_local/sing-box

    mkdir -p /opt/xray-agent/xray/conf
    mkdir -p /opt/xray-agent/xray/reality_scan
    mkdir -p /opt/xray-agent/xray/tmp
    mkdir -p /etc/systemd/system/
    mkdir -p /tmp/xray-agent-tls/

    mkdir -p /opt/xray-agent/warp

    mkdir -p /opt/xray-agent/sing-box/conf/config

    mkdir -p /usr/share/nginx/html/
}

# 安装工具包
installTools() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
    # 修复ubuntu个别系统问题
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi

    if [[ -n $(pgrep -f "apt") ]]; then
        pgrep -f apt | xargs kill -9
    fi

    echoContent green " ---> 检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"

    ${upgrade} >/opt/xray-agent/install.log 2>&1
    if grep <"/opt/xray-agent/install.log" -q "changed"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi

    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        ${installType} epel-release >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w sudo; then
        echoContent green " ---> 安装sudo"
        ${installType} sudo >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w wget; then
        echoContent green " ---> 安装wget"
        ${installType} wget >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w netfilter-persistent; then
        # 检查是否已安装 UFW
        if dpkg -l 2>/dev/null | grep -q "^[[:space:]]*ii[[:space:]]\+ufw" || command -v ufw &> /dev/null; then
            echoContent yellow " ---> 检测到 UFW 防火墙，跳过安装 iptables-persistent"
        elif [[ "${release}" != "centos" ]]; then
            echoContent green " ---> 安装iptables"
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
            ${installType} iptables-persistent >/dev/null 2>&1
        fi
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w curl; then
        echoContent green " ---> 安装curl"
        ${installType} curl >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w unzip; then
        echoContent green " ---> 安装unzip"
        ${installType} unzip >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w socat; then
        echoContent green " ---> 安装socat"
        ${installType} socat >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w tar; then
        echoContent green " ---> 安装tar"
        ${installType} tar >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w cron; then
        echoContent green " ---> 安装crontabs"
        if [[ "${release}" == "ubuntu" ]] || [[ "${release}" == "debian" ]]; then
            ${installType} cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    if ! find /usr/bin /usr/sbin | grep -q -w jq; then
        echoContent green " ---> 安装jq"
        ${installType} jq >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w binutils; then
        echoContent green " ---> 安装binutils"
        ${installType} binutils >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w openssl; then
        echoContent green " ---> 安装openssl"
        ${installType} openssl >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w ping6; then
        echoContent green " ---> 安装ping6"
        ${installType} inetutils-ping >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w qrencode; then
        echoContent green " ---> 安装qrencode"
        ${installType} qrencode >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w lsb-release; then
        echoContent green " ---> 安装lsb-release"
        ${installType} lsb-release >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w lsof; then
        echoContent green " ---> 安装lsof"
        ${installType} lsof >/dev/null 2>&1
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w dig; then
        echoContent green " ---> 安装dig"
        if echo "${installType}" | grep -qw "apt"; then
            ${installType} dnsutils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "yum"; then
            ${installType} bind-utils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "apk"; then
            ${installType} bind-tools >/dev/null 2>&1
        fi
    fi

    # 检测nginx版本，并提供是否卸载的选项
    if echo "${selectCustomInstallType}" | grep -qwE ",7,|,8,|,7,8,"; then
        echoContent green " ---> 检测到无需依赖Nginx的服务，跳过安装"
    else
        # 检查是否有 Docker Nginx 配置记录
        local hasDockerNginxConfig=false
        if [[ -f "/opt/xray-agent/nginx_config_path" ]]; then
            hasDockerNginxConfig=true
            savedNginxPath=$(cat /opt/xray-agent/nginx_config_path)
            echoContent green " ---> 检测到之前配置的 Docker Nginx 路径: ${savedNginxPath}"
        fi

        # 检查 Docker Nginx (运行中)
        if checkDockerNginx; then
            echoContent green " ---> 检测到 Docker Nginx 运行中，跳过安装系统 Nginx"
            echoContent yellow " ---> 将使用 Docker Nginx 配置"

            # 询问是否设置 Docker Nginx 配置路径
            read -r -p "是否设置 Docker Nginx 配置路径？[y/n] (默认: n):" setDockerNginxPath
            if [[ "${setDockerNginxPath}" == "y" ]]; then
                echoContent yellow "请输入 Docker Nginx 配置目录路径 (例: /path/to/nginx/conf.d/):"
                read -r -p "配置路径:" dockerNginxPath
                if [[ -n "${dockerNginxPath}" ]]; then
                    # 确保路径以 / 结尾
                    if [[ "${dockerNginxPath}" != */ ]]; then
                        dockerNginxPath="${dockerNginxPath}/"
                    fi
                    nginxConfigPath="${dockerNginxPath}"
                    customNginxConfigPath="true"

                    # 保存配置路径到文件
                    mkdir -p /opt/xray-agent
                    echo "${nginxConfigPath}" > /opt/xray-agent/nginx_config_path

                    echoContent green " ---> 已设置 Docker Nginx 配置路径: ${nginxConfigPath}"
                fi

                # 询问静态文件路径
                echoContent yellow "\n请输入 Docker Nginx 静态文件目录路径 (容器内路径，例: /usr/share/nginx/html/ 或 /var/www/):"
                read -r -p "静态文件路径:" dockerNginxStaticPath
                if [[ -n "${dockerNginxStaticPath}" ]]; then
                    # 确保路径以 / 结尾
                    if [[ "${dockerNginxStaticPath}" != */ ]]; then
                        dockerNginxStaticPath="${dockerNginxStaticPath}/"
                    fi
                    nginxStaticPath="${dockerNginxStaticPath}"

                    # 保存静态文件路径到文件
                    echo "${nginxStaticPath}" > /opt/xray-agent/nginx_static_path

                    echoContent green " ---> 已设置 Docker Nginx 静态文件路径: ${nginxStaticPath}"
                else
                    echoContent yellow " ---> 使用默认静态文件路径: ${nginxStaticPath}"
                fi
            fi
        elif [[ "${hasDockerNginxConfig}" == "true" ]]; then
            # 有 Docker Nginx 配置但容器未运行（可能暂时停止）
            echoContent yellow " ---> 检测到之前使用 Docker Nginx，但容器当前未运行"
            echoContent skyBlue " ---> 提示：Docker Nginx 可能在申请证书时暂时停止"
            read -r -p "是否继续使用 Docker Nginx 配置？[y/n] (默认: y):" continueDockerNginx
            if [[ -z "${continueDockerNginx}" ]] || [[ "${continueDockerNginx}" == "y" ]]; then
                echoContent green " ---> 继续使用 Docker Nginx 配置"
                nginxConfigPath="${savedNginxPath}"
                if [[ -f "/opt/xray-agent/nginx_static_path" ]]; then
                    nginxStaticPath=$(cat /opt/xray-agent/nginx_static_path)
                    echoContent green " ---> 使用静态文件路径: ${nginxStaticPath}"
                fi
            else
                echoContent yellow " ---> 用户选择不使用 Docker Nginx"
                # 询问是否安装系统 Nginx
                read -r -p "是否安装系统级 Nginx？[y/n]:" installSystemNginx
                if [[ "${installSystemNginx}" == "y" ]]; then
                    echoContent green " ---> 安装nginx"
                    installNginxTools
                    # 清除 Docker Nginx 配置记录
                    rm -f /opt/xray-agent/nginx_config_path
                    rm -f /opt/xray-agent/nginx_static_path
                else
                    echoContent red " ---> 未安装 Nginx，部分功能可能无法使用"
                    echoContent yellow " ---> 请手动安装 Nginx 或启动 Docker Nginx 容器后重新运行脚本"
                fi
            fi
        elif ! find /usr/bin /usr/sbin | grep -q -w nginx; then
            # 没有系统 Nginx，也没有 Docker Nginx 配置
            echoContent yellow " ---> 未检测到 Nginx (系统或 Docker)"
            echoContent skyBlue " ---> 提示：如果您使用 Docker Nginx，请确保容器名包含 'nginx' 并处于运行状态"
            echo ""
            echoContent yellow "请选择 Nginx 部署方式："
            echoContent white "1. 安装系统级 Nginx (推荐新手)"
            echoContent white "2. 使用 Docker Nginx (需要手动启动容器)"
            echoContent white "3. 跳过 Nginx 安装 (稍后手动配置)"
            read -r -p "请选择 [1-3] (默认: 1):" nginxChoice

            case "${nginxChoice}" in
                2)
                    echoContent green " ---> 选择使用 Docker Nginx"
                    echoContent yellow "请输入 Docker Nginx 配置目录路径 (例: /opt/nginx/conf.d/):"
                    read -r -p "配置路径:" dockerNginxPath
                    if [[ -n "${dockerNginxPath}" ]]; then
                        if [[ "${dockerNginxPath}" != */ ]]; then
                            dockerNginxPath="${dockerNginxPath}/"
                        fi
                        nginxConfigPath="${dockerNginxPath}"
                        mkdir -p /opt/xray-agent
                        echo "${nginxConfigPath}" > /opt/xray-agent/nginx_config_path
                        echoContent green " ---> 已设置 Docker Nginx 配置路径: ${nginxConfigPath}"

                        echoContent yellow "请输入 Docker Nginx 静态文件目录路径 (例: /opt/nginx/html/):"
                        read -r -p "静态文件路径:" dockerNginxStaticPath
                        if [[ -n "${dockerNginxStaticPath}" ]]; then
                            if [[ "${dockerNginxStaticPath}" != */ ]]; then
                                dockerNginxStaticPath="${dockerNginxStaticPath}/"
                            fi
                            nginxStaticPath="${dockerNginxStaticPath}"
                            echo "${nginxStaticPath}" > /opt/xray-agent/nginx_static_path
                            echoContent green " ---> 已设置 Docker Nginx 静态文件路径: ${nginxStaticPath}"
                        fi
                    else
                        echoContent red " ---> 未设置配置路径，退出安装"
                        exit 0
                    fi
                    ;;
                3)
                    echoContent yellow " ---> 跳过 Nginx 安装"
                    echoContent red " ---> 警告：部分功能可能无法使用，请稍后手动配置 Nginx"
                    ;;
                *)
                    echoContent green " ---> 安装系统级 Nginx"
                    installNginxTools
                    ;;
            esac
        else
            # 检测现有 Nginx 业务
            local existingConfCount=$(find /etc/nginx/conf.d /etc/nginx/sites-enabled -name "*.conf" 2>/dev/null | wc -l)
            
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            
            if [[ ${nginxVersion} -lt 14 ]]; then
                echoContent red "\n=============================================================="
                echoContent yellow "检测到 Nginx 版本 < 1.14，不支持 gRPC"
                if [[ ${existingConfCount} -gt 0 ]]; then
                    echoContent yellow "检测到 ${existingConfCount} 个现有配置文件，可能有业务运行中"
                    echoContent red "警告：卸载 Nginx 会影响现有业务！"
                fi
                echoContent red "==============================================================\n"
                read -r -p "是否卸载 Nginx 后重新安装？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    # 备份现有配置
                    if [[ ${existingConfCount} -gt 0 ]]; then
                        local backupPath="/opt/xray-agent/nginx_backup_$(date +%Y%m%d_%H%M%S)"
                        mkdir -p "${backupPath}"
                        cp -r /etc/nginx/conf.d "${backupPath}/" 2>/dev/null
                        cp -r /etc/nginx/sites-enabled "${backupPath}/" 2>/dev/null
                        echoContent green " ---> 已备份配置到: ${backupPath}"
                    fi
                    ${removeType} nginx >/dev/null 2>&1
                    echoContent yellow " ---> nginx卸载完成"
                    echoContent green " ---> 安装nginx"
                    installNginxTools >/dev/null 2>&1
                else
                    exit 0
                fi
            else
                # Nginx 版本符合要求
                if [[ ${existingConfCount} -gt 0 ]]; then
                    echoContent yellow "\n检测到 Nginx 已安装且有 ${existingConfCount} 个配置文件"
                    echoContent skyBlue "脚本将在共存模式下运行，不会影响现有业务"
                    echoContent green "提示：建议使用不同的域名避免冲突\n"
                fi
            fi
        fi
    fi

    if ! find /usr/bin /usr/sbin | grep -q -w semanage; then
        echoContent green " ---> 安装semanage"
        ${installType} bash-completion >/dev/null 2>&1

        if [[ "${centosVersion}" == "7" ]]; then
            policyCoreUtils="policycoreutils-python.x86_64"
        elif [[ "${centosVersion}" == "8" ]]; then
            policyCoreUtils="policycoreutils-python-utils-2.9-9.el8.noarch"
        fi

        if [[ -n "${policyCoreUtils}" ]]; then
            ${installType} ${policyCoreUtils} >/dev/null 2>&1
        fi
        if [[ -n $(which semanage) ]]; then
            semanage port -a -t http_port_t -p tcp 31300

        fi
    fi
    if [[ "${selectCustomInstallType}" == "7" ]]; then
        echoContent green " ---> 检测到无需依赖证书的服务，跳过安装"
    else
        # 检查是否使用 native ACME
        local useNativeACME=$(useNativeACMECert)
        
        if [[ "${nativeACMEEnabled}" != "true" ]]; then
            # 未使用 native ACME，安装 acme.sh
            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent green " ---> 安装acme.sh"
                curl -s https://get.acme.sh | sh >/opt/xray-agent/tls/acme.log 2>&1

                if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                    echoContent red "  acme安装失败--->"
                    tail -n 100 /opt/xray-agent/tls/acme.log
                    echoContent yellow "错误排查:"
                    echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
                    echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
                    echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
                    echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                    exit 0
                fi
            else
                echoContent green " ---> acme.sh 已安装"
            fi
        else
            echoContent green " ---> 使用 Native ACME 证书，跳过安装 acme.sh"
        fi
    fi

}
# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}
# 安装Nginx
installNginxTools() {

    if [[ "${release}" == "debian" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        # 使用 stable 版本而非 mainline
        echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        # 使用 stable 版本而非 mainline
        echo "deb http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        # CentOS 使用 stable 版本,不启用 mainline
        # sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    elif [[ "${release}" == "alpine" ]]; then
        rm "${nginxConfigPath}default.conf"
    fi
    ${installType} nginx >/dev/null 2>&1
    bootStartup nginx
}

# 安装warp
installWarp() {
    if [[ "${cpuVendor}" == "arm" ]]; then
        echoContent red " ---> 官方WARP客户端不支持ARM架构"
        exit 0
    fi

    ${installType} gnupg2 -y >/dev/null 2>&1
    if [[ "${release}" == "debian" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb http://pkg.cloudflareclient.com/ focal main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        sudo rpm -ivh "http://pkg.cloudflareclient.com/cloudflare-release-el${centosVersion}.rpm" >/dev/null 2>&1
    fi

    echoContent green " ---> 安装WARP"
    ${installType} cloudflare-warp >/dev/null 2>&1
    if [[ -z $(which warp-cli) ]]; then
        echoContent red " ---> 安装WARP失败"
        exit 0
    fi
    systemctl enable warp-svc
    warp-cli --accept-tos register
    warp-cli --accept-tos set-mode proxy
    warp-cli --accept-tos set-proxy-port 31303
    warp-cli --accept-tos connect
    warp-cli --accept-tos enable-always-on

    local warpStatus=
    warpStatus=$(curl -s --socks5 127.0.0.1:31303 https://www.cloudflare.com/cdn-cgi/trace | grep "warp" | cut -d "=" -f 2)

    if [[ "${warpStatus}" == "on" ]]; then
        echoContent green " ---> WARP启动成功"
    fi
}

# 通过dns检查域名的IP
checkDNSIP() {
    local domain=$1
    local dnsIP=
    ipType=4
    dnsIP=$(dig @1.1.1.1 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    if [[ -z "${dnsIP}" ]]; then
        dnsIP=$(dig @8.8.8.8 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    fi
    if echo "${dnsIP}" | grep -q "timed out" || [[ -z "${dnsIP}" ]]; then
        echo
        echoContent red " ---> 无法通过DNS获取域名 IPv4 地址"
        echoContent green " ---> 尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if echo "${dnsIP}" | grep -q "network unreachable" || [[ -z "${dnsIP}" ]]; then
            echoContent red " ---> 无法通过DNS获取域名IPv6地址，退出安装"
            exit 0
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        echoContent red " ---> 域名解析IP与当前服务器IP不一致\n"
        echoContent yellow " ---> 请检查域名解析是否生效以及正确"
        echoContent green " ---> 当前VPS IP：${publicIP}"
        echoContent green " ---> DNS解析 IP：${dnsIP}"
        exit 0
    else
        echoContent green " ---> 域名IP校验通过"
    fi
}
# 检查端口实际开放状态
checkPortOpen() {
    handleSingBox stop >/dev/null 2>&1
    handleXray stop >/dev/null 2>&1

    local port=$1
    local domain=$2
    local checkPortOpenResult=
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化nginx配置
        touch ${nginxConfigPath}checkPortOpen.conf
        local listenIPv6PortConfig=

        if [[ -n $(curl -s -6 -m 4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2) ]]; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        cat <<EOF >${nginxConfigPath}checkPortOpen.conf
server {
    listen ${port};
    ${listenIPv6PortConfig}
    server_name ${domain};
    location /checkPort {
        return 200 'fjkvymb6len';
    }
    location /ip {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header REMOTE-HOST \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        default_type text/plain;
        return 200 \$proxy_add_x_forwarded_for;
    }
}
EOF
        
        # Docker Nginx 调试信息
        if [[ -n "${customNginxConfigPath}" ]]; then
            echoContent yellow " ---> Docker Nginx 模式"
            echoContent skyBlue " ---> 配置文件: ${nginxConfigPath}checkPortOpen.conf"
            if [[ -f "${nginxConfigPath}checkPortOpen.conf" ]]; then
                echoContent green " ---> 配置文件创建成功"
            else
                echoContent red " ---> 配置文件创建失败"
            fi
        fi
        
        handleNginx start
        # 检查域名+端口的开放
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        
        # 如果是 Docker Nginx，删除配置后需要重载
        if [[ -n "${customNginxConfigPath}" ]]; then
            local dockerNginxContainer=$(docker ps --filter "name=nginx" --format "{{.Names}}" 2>/dev/null | head -n 1)
            if [[ -n "${dockerNginxContainer}" ]]; then
                docker exec "${dockerNginxContainer}" nginx -s reload >/dev/null 2>&1
            fi
        fi
        
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            echoContent green " ---> 检测到${port}端口已开放"
        else
            echoContent green " ---> 未检测到${port}端口开放，退出安装"
            if echo "${checkPortOpenResult}" | grep -q "cloudflare"; then
                echoContent yellow " ---> 请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    echoContent red " ---> 请检查是否有网页防火墙，比如Oracle等云服务商"
                    echoContent red " ---> 检查是否自己安装过nginx并且有配置冲突，可以尝试DD纯净系统后重新尝试"
                else
                    echoContent red " ---> 错误日志：${checkPortOpenResult}，请将此错误日志通过issues提交反馈"
                fi
            fi
            exit 0
        fi
        checkIP "${localIP}"
    fi
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
    handleNginx stop
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"

    # 优先读取已保存的 Docker Nginx 配置
    if [[ -f /opt/xray-agent/nginx_config_path ]]; then
        nginxConfigPath=$(cat /opt/xray-agent/nginx_config_path)
        customNginxConfigPath="true"
        echoContent green " ---> 使用已保存的 Docker Nginx 配置路径: ${nginxConfigPath}"

        # 读取已保存的静态文件路径
        if [[ -f "/opt/xray-agent/nginx_static_path" ]]; then
            nginxStaticPath=$(cat /opt/xray-agent/nginx_static_path)
            echoContent green " ---> 使用已保存的静态文件路径: ${nginxStaticPath}"
        fi
        return
    fi

    # 询问是否自定义 Nginx 配置路径
    if [[ -z "${customNginxConfigPath}" ]]; then
        echoContent skyBlue "\n=============================================================="
        echoContent yellow "检测到的 Nginx 配置路径: ${nginxConfigPath}"
        echoContent skyBlue "==============================================================\n"
        read -r -p "是否使用自定义 Nginx 配置路径？[y/n] (默认: n):" useCustomPath
        if [[ "${useCustomPath}" == "y" ]]; then
            echoContent yellow "请输入 Nginx 配置目录路径 (例: /opt/nginx/conf.d/):"
            read -r -p "路径:" inputNginxPath
            if [[ -n "${inputNginxPath}" ]]; then
                # 确保路径以 / 结尾
                if [[ "${inputNginxPath}" != */ ]]; then
                    inputNginxPath="${inputNginxPath}/"
                fi
                
                # 检查路径是否存在
                if [[ -d "${inputNginxPath}" ]]; then
                    nginxConfigPath="${inputNginxPath}"
                    customNginxConfigPath="true"
                    
                    # 保存配置路径到文件
                    mkdir -p /opt/xray-agent
                    echo "${nginxConfigPath}" > /opt/xray-agent/nginx_config_path
                    
                    echoContent green "\n ---> 已设置 Nginx 配置路径: ${nginxConfigPath}"
                else
                    echoContent yellow "\n路径不存在，是否创建？[y/n]:"
                    read -r -p "" createPath
                    if [[ "${createPath}" == "y" ]]; then
                        mkdir -p "${inputNginxPath}"
                        nginxConfigPath="${inputNginxPath}"
                        customNginxConfigPath="true"
                        
                        # 保存配置路径到文件
                        mkdir -p /opt/xray-agent
                        echo "${nginxConfigPath}" > /opt/xray-agent/nginx_config_path
                        
                        echoContent green "\n ---> 已创建并设置 Nginx 配置路径: ${nginxConfigPath}"
                    else
                        echoContent yellow "\n ---> 使用默认路径: ${nginxConfigPath}"
                    fi
                fi
            fi
        else
            echoContent green "\n ---> 使用默认路径: ${nginxConfigPath}"
        fi
        
        # 如果是自定义路径（Docker Nginx），询问静态文件路径
        if [[ -n "${customNginxConfigPath}" ]]; then
            echoContent skyBlue "\n=============================================================="
            echoContent yellow "检测到的 Nginx 静态文件路径: ${nginxStaticPath}"
            echoContent skyBlue "==============================================================\n"
            read -r -p "是否使用自定义 Nginx 静态文件路径？[y/n] (默认: n):" useCustomStaticPath
            if [[ "${useCustomStaticPath}" == "y" ]]; then
                echoContent yellow "请输入 Nginx 静态文件目录路径 (容器内路径，例: /var/www/):"
                read -r -p "静态文件路径:" inputNginxStaticPath
                if [[ -n "${inputNginxStaticPath}" ]]; then
                    # 确保路径以 / 结尾
                    if [[ "${inputNginxStaticPath}" != */ ]]; then
                        inputNginxStaticPath="${inputNginxStaticPath}/"
                    fi
                    nginxStaticPath="${inputNginxStaticPath}"
                    
                    # 保存静态文件路径到文件
                    mkdir -p /opt/xray-agent
                    echo "${nginxStaticPath}" > /opt/xray-agent/nginx_static_path
                    
                    echoContent green "\n ---> 已设置 Nginx 静态文件路径: ${nginxStaticPath}"
                else
                    echoContent yellow "\n ---> 使用默认静态文件路径: ${nginxStaticPath}"
                fi
            else
                echoContent green "\n ---> 使用默认静态文件路径: ${nginxStaticPath}"
            fi
        fi
    fi
    
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        else
            echo
            echoContent yellow "请输入要配置的域名 例: example.com --->"
            read -r -p "域名:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "请输入要配置的域名 例: example.com --->"
        read -r -p "域名:" domain
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  域名不可为空--->"
        initTLSNginxConfig 3
    else
        # 检查域名是否已在 Nginx 中配置
        if grep -r "server_name.*${domain}" /etc/nginx/conf.d/ /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "xray-agent.conf" | grep -q "${domain}"; then
            echoContent red "\n=============================================================="
            echoContent yellow "警告：检测到域名 ${domain} 已在 Nginx 中配置"
            echoContent yellow "这可能会导致配置冲突！"
            echoContent red "==============================================================\n"
            read -r -p "是否继续使用此域名（可能影响现有业务）？[y/n]:" domainConflictStatus
            if [[ "${domainConflictStatus}" != "y" ]]; then
                echoContent yellow "请使用不同的域名"
                initTLSNginxConfig 3
                return
            fi
        fi
        
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
        if [[ "${selectCoreType}" == "1" ]]; then
            customPortFunction
        fi
        # 修改配置
        handleNginx stop
    fi
}

# 删除nginx默认的配置
removeNginxDefaultConf() {
    if [[ -f ${nginxConfigPath}default.conf ]]; then
        if [[ "$(grep -c "server_name" <${nginxConfigPath}default.conf)" == "1" ]] && [[ "$(grep -c "server_name  localhost;" <${nginxConfigPath}default.conf)" == "1" ]]; then
            echoContent green " ---> 删除Nginx默认配置"
            rm -rf ${nginxConfigPath}default.conf >/dev/null 2>&1
        fi
    fi
}
# 修改nginx重定向配置
updateRedirectNginxConf() {
    # 备份现有配置
    if [[ -f "${nginxConfigPath}xray-agent.conf" ]]; then
        local backupFile="${nginxConfigPath}xray-agent.conf.bak_$(date +%Y%m%d_%H%M%S)"
        cp "${nginxConfigPath}xray-agent.conf" "${backupFile}"
        echoContent skyBlue " ---> 已备份原配置: ${backupFile}"
    fi
    
    local redirectDomain=
    redirectDomain=${domain}:${port}

    local nginxH2Conf=
    nginxH2Conf="listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;"
    nginxVersion=$(nginx -v 2>&1)

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen 127.0.0.1:31302 so_keepalive=on proxy_protocol;http2 on;"
    fi

    cat <<EOF >${nginxConfigPath}xray-agent.conf
    server {
    		listen 127.0.0.1:31300;
    		server_name _;
    		return 403;
    }
EOF

    if echo "${selectCustomInstallType}" | grep -qE ",2,|,5," || [[ -z "${selectCustomInstallType}" ]]; then

        cat <<EOF >>${nginxConfigPath}xray-agent.conf
server {
	${nginxH2Conf}
	server_name ${domain};
	root ${nginxStaticPath};

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

    location /${currentPath}grpc {
    	if (\$content_type !~ "application/grpc") {
    		return 404;
    	}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location /${currentPath}trojangrpc {
		if (\$content_type !~ "application/grpc") {
            		return 404;
		}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31304;
	}
	location / {
    }
}
EOF
    elif echo "${selectCustomInstallType}" | grep -q ",5," || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}xray-agent.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	location /${currentPath}grpc {
		client_max_body_size 0;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
}
EOF

    elif echo "${selectCustomInstallType}" | grep -q ",2," || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}xray-agent.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    server_name ${domain};
	root ${nginxStaticPath};

	location /${currentPath}trojangrpc {
		client_max_body_size 0;
		# keepalive_time 1071906480m;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
}
EOF
    else

        cat <<EOF >>${nginxConfigPath}xray-agent.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	location / {
	}
}
EOF
    fi

    cat <<EOF >>${nginxConfigPath}xray-agent.conf
server {
	listen 127.0.0.1:31300 proxy_protocol;
	server_name ${domain};

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	root ${nginxStaticPath};
	location / {
	}
}
EOF
    handleNginx stop
}
# singbox Nginx config
singBoxNginxConfig() {
    local type=$1
    local port=$2

    local nginxH2Conf=
    nginxH2Conf="listen ${port} http2 so_keepalive=on ssl;"
    nginxVersion=$(nginx -v 2>&1)

    local singBoxNginxSSL=
    singBoxNginxSSL="ssl_certificate /opt/xray-agent/tls/${domain}.crt;ssl_certificate_key /opt/xray-agent/tls/${domain}.key;"

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen ${port} so_keepalive=on ssl;http2 on;"
    fi

    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        cat <<EOF >>${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf
server {
	${nginxH2Conf}

	server_name ${domain};
	root ${nginxStaticPath};
    ${singBoxNginxSSL}

    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;

    location /${currentPath} {
    	if (\$http_upgrade != "websocket") {
            return 444;
        }

        proxy_pass                          http://127.0.0.1:31306;
        proxy_http_version                  1.1;
        proxy_set_header Upgrade            \$http_upgrade;
        proxy_set_header Connection         "upgrade";
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header Host               \$host;
        proxy_redirect                      off;
	}
}
EOF
    fi
}

# 检查ip
