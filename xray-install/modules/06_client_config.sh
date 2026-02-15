#!/usr/bin/env bash
# 模块 06：客户端/入站配置生成

initXrayClients() {
    local type=",$1,"
    local newUUID=$2
    local newEmail=$3
    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${newEmail}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .id//.uuid)
        email=$(echo "${user}" | jq -r .email//.name | awk -F "[-]" '{print $1}')
        currentUser=
        if echo "${type}" | grep -q "0"; then
            currentUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${email}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS WS
        if echo "${type}" | grep -q ",1,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS XHTTP
        if echo "${type}" | grep -q ",12,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_XHTTP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # trojan grpc
        if echo "${type}" | grep -q ",2,"; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-Trojan_gRPC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess WS
        if echo "${type}" | grep -q ",3,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VMess_WS\",\"alterId\": 0}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # trojan tcp
        if echo "${type}" | grep -q ",4,"; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-trojan_tcp\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless grpc
        if echo "${type}" | grep -q ",5,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_grpc\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality vision
        if echo "${type}" | grep -q ",7,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_vision\",\"flow\":\"xtls-rprx-vision\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality grpc
        if echo "${type}" | grep -q ",8,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_grpc\",\"flow\":\"\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}
# 初始化tuic配置
#initTuicConfig() {
#    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Tuic配置"
#
#    initTuicPort
#    initTuicProtocol
#    cat <<EOF >/opt/xray-agent/tuic/conf/config.json
#{
#    "server": "[::]:${tuicPort}",
#    "users": $(initXrayClients 9),
#    "certificate": "/opt/xray-agent/tls/${currentHost}.crt",
#    "private_key": "/opt/xray-agent/tls/${currentHost}.key",
#    "congestion_control":"${tuicAlgorithm}",
#    "alpn": ["h3"],
#    "log_level": "warn"
#}
#EOF
#}

# 添加Xray-core 出站
addXrayOutbound() {
    local tag=$1
    local domainStrategy=

    if echo "${tag}" | grep -q "IPv4"; then
        domainStrategy="ForceIPv4"
    elif echo "${tag}" | grep -q "IPv6"; then
        domainStrategy="ForceIPv6"
    fi

    if [[ -n "${domainStrategy}" ]]; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"${domainStrategy}"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # direct
    if echo "${tag}" | grep -q "direct"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings": {
                "domainStrategy":"UseIP"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # blackhole
    if echo "${tag}" | grep -q "blackhole"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"blackhole",
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # socks5 outbound
    if echo "${tag}" | grep -q "socks5"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "socks",
      "tag": "${tag}",
      "settings": {
        "servers": [
          {
            "address": "${socks5RoutingOutboundIP}",
            "port": ${socks5RoutingOutboundPort},
            "users": [
              {
                "user": "${socks5RoutingOutboundUserName}",
                "pass": "${socks5RoutingOutboundPassword}"
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv4"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv6"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "vmess-out"; then
        cat <<EOF >"/opt/xray-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "tag": "${tag}",
      "protocol": "vmess",
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {},
        "wsSettings": {
          "path": "${setVMessWSTLSPath}"
        }
      },
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "settings": {
        "vnext": [
          {
            "address": "${setVMessWSTLSAddress}",
            "port": "${setVMessWSTLSPort}",
            "users": [
              {
                "id": "${setVMessWSTLSUUID}",
                "security": "auto",
                "alterId": 0
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
}

# 删除 Xray-core出站
removeXrayOutbound() {
    local tag=$1
    if [[ -f "/opt/xray-agent/xray/conf/${tag}.json" ]]; then
        rm "/opt/xray-agent/xray/conf/${tag}.json" >/dev/null 2>&1
    fi
}
# 初始化Xray Trojan XTLS 配置文件
#initXrayFrontingConfig() {
#    echoContent red " ---> Trojan暂不支持 xtls-rprx-vision"
#    if [[ -z "${configPath}" ]]; then
#        echoContent red " ---> 未安装，请使用脚本安装"
#        menu
#        exit 0
#    fi
#    if [[ "${coreInstallType}" != "1" ]]; then
#        echoContent red " ---> 未安装可用类型"
#    fi
#    local xtlsType=
#    if echo ${currentInstallProtocolType} | grep -q trojan; then
#        xtlsType=VLESS
#    else
#        xtlsType=Trojan
#    fi
#
#    echoContent skyBlue "\n功能 1/${totalProgress} : 前置切换为${xtlsType}"
#    echoContent red "\n=============================================================="
#    echoContent yellow "# 注意事项\n"
#    echoContent yellow "会将前置替换为${xtlsType}"
#    echoContent yellow "如果前置是Trojan，查看账号时则会出现两个Trojan协议的节点，有一个不可用xtls"
#    echoContent yellow "再次执行可切换至上一次的前置\n"
#
#    echoContent yellow "1.切换至${xtlsType}"
#    echoContent red "=============================================================="
#    read -r -p "请选择:" selectType
#    if [[ "${selectType}" == "1" ]]; then
#
#        if [[ "${xtlsType}" == "Trojan" ]]; then
#
#            local VLESSConfig
#            VLESSConfig=$(cat ${configPath}${frontingType}.json)
#            VLESSConfig=${VLESSConfig//"id"/"password"}
#            VLESSConfig=${VLESSConfig//VLESSTCP/TrojanTCPXTLS}
#            VLESSConfig=${VLESSConfig//VLESS/Trojan}
#            VLESSConfig=${VLESSConfig//"vless"/"trojan"}
#            VLESSConfig=${VLESSConfig//"id"/"password"}
#
#            echo "${VLESSConfig}" | jq . >${configPath}02_trojan_TCP_inbounds.json
#            rm ${configPath}${frontingType}.json
#        elif [[ "${xtlsType}" == "VLESS" ]]; then
#
#            local VLESSConfig
#            VLESSConfig=$(cat ${configPath}02_trojan_TCP_inbounds.json)
#            VLESSConfig=${VLESSConfig//"password"/"id"}
#            VLESSConfig=${VLESSConfig//TrojanTCPXTLS/VLESSTCP}
#            VLESSConfig=${VLESSConfig//Trojan/VLESS}
#            VLESSConfig=${VLESSConfig//"trojan"/"vless"}
#            VLESSConfig=${VLESSConfig//"password"/"id"}
#
#            echo "${VLESSConfig}" | jq . >${configPath}02_VLESS_TCP_inbounds.json
#            rm ${configPath}02_trojan_TCP_inbounds.json
#        fi
#        reloadCore
#    fi
#
#    exit 0
#}

# 初始化Xray 配置文件
