#!/usr/bin/env bash
# 模块 04：TLS/ACME、DNS 以及端口管理

checkIP() {
    echoContent skyBlue "\n ---> 检查域名ip中"
    local localIP=$1

    if [[ -z ${localIP} ]] || ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q '\.' && ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q ':'; then
        echoContent red "\n ---> 未检测到当前域名的ip"
        echoContent skyBlue " ---> 请依次进行下列检查"
        echoContent yellow " --->  1.检查域名是否书写正确"
        echoContent yellow " --->  2.检查域名dns解析是否正确"
        echoContent yellow " --->  3.如解析正确，请等待dns生效，预计三分钟内生效"
        echoContent yellow " --->  4.如报Nginx启动问题，请手动启动nginx查看错误，如自己无法处理请提issues"
        echo
        echoContent skyBlue " ---> 如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            echoContent yellow " ---> 检测返回值异常，建议手动卸载nginx后重新执行脚本"
            echoContent red " ---> 异常结果：${localIP}"
        fi
        exit 0
    else
        if echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q "." || echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q ":"; then
            echoContent red "\n ---> 检测到多个ip，请确认是否关闭cloudflare的云朵"
            echoContent yellow " ---> 关闭云朵后等待三分钟后重试"
            echoContent yellow " ---> 检测到的ip如下:[${localIP}]"
            exit 0
        fi
        echoContent green " ---> 检查当前域名IP正确"
    fi
}
# 自定义email
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> 添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}
# DNS API申请证书
switchDNSAPI() {
    # 检测是否有 Native ACME，提供使用现有证书的选项
    if checkNativeACME; then
        echoContent skyBlue "\n=============================================================="
        echoContent yellow "检测到系统已安装 Native ACME 客户端"
        echoContent skyBlue "==============================================================\n"
        echoContent yellow "请选择证书获取方式:"
        echoContent yellow "1. 使用现有 Native ACME 证书 (推荐)"
        echoContent yellow "2. 使用 acme.sh 申请新证书 (DNS API)"
        echoContent yellow "3. 使用 acme.sh 申请新证书 (standalone)\n"
        read -r -p "请选择 [1-3, 默认: 1]:" certMethodChoice
        
        case ${certMethodChoice} in
        1 | "")
            # 使用 Native ACME 现有证书
            echoContent green "\n ---> 选择使用 Native ACME 证书"
            provideExistingCert
            return
            ;;
        2)
            # 使用 acme.sh DNS API 申请
            echoContent green "\n ---> 选择使用 acme.sh DNS API 申请证书"
            dnsAPIStatus="y"
            ;;
        3)
            # 使用 acme.sh standalone 申请
            echoContent green "\n ---> 选择使用 acme.sh standalone 申请证书"
            dnsAPIStatus="n"
            return
            ;;
        *)
            echoContent red "\n ---> 选择无效，默认使用 Native ACME 证书"
            provideExistingCert
            return
            ;;
        esac
    else
        # 没有 Native ACME，询问是否使用 DNS API
        read -r -p "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    fi
    
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[默认]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectDNSAPIType
        case ${selectDNSAPIType} in
        1)
            dnsAPIType="cloudflare"
            ;;
        2)
            dnsAPIType="aliyun"
            ;;
        *)
            dnsAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${dnsAPIType}"
    fi
}

# 提供现有证书（简化版）
provideExistingCert() {
    echoContent skyBlue "\n请选择证书来源:"
    echoContent yellow "1. 使用现有证书（从列表选择）- 支持 certbot 和 acme.sh"
    echoContent yellow "2. 手动指定证书路径"
    echoContent yellow "3. 使用通配符证书路径"
    echoContent yellow "4. 使用 certbot 申请新证书\n"
    read -r -p "请选择 [1-4, 默认: 1]:" certSourceType
    
    case ${certSourceType:-1} in
    1)
        # 使用现有证书 - 支持 certbot 和 acme.sh
        local certbotCerts=()
        local acmeshCerts=()

        # 检查 certbot 证书
        if [[ -d "/etc/letsencrypt/live" ]]; then
            while IFS= read -r cert; do
                certbotCerts+=("${cert}")
            done < <(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        fi

        # 检查 acme.sh 证书
        if [[ -d "$HOME/.acme.sh" ]]; then
            while IFS= read -r certDir; do
                # 获取域名（移除_ecc后缀）
                certName=$(basename "${certDir}")
                certName=${certName%_ecc}
                # 检查证书文件是否存在
                if [[ -f "$HOME/.acme.sh/${certName}_ecc/${certName}.cer" ]] && [[ -f "$HOME/.acme.sh/${certName}_ecc/${certName}.key" ]]; then
                    acmeshCerts+=("${certName}")
                fi
            done < <(find "$HOME/.acme.sh" -maxdepth 1 -type d -name "*_ecc" 2>/dev/null)
        fi

        # 合并并去重
        local allCerts=($(printf '%s\n' "${certbotCerts[@]}" "${acmeshCerts[@]}" | sort -u))

        if [[ ${#allCerts[@]} -eq 0 ]]; then
            echoContent red "\n ---> 未找到任何证书"
            nativeACMEEnabled=false
        else
            echoContent green "\n可用证书域名 (certbot 和 acme.sh):"
            for i in "${!allCerts[@]}"; do
                local cert="${allCerts[$i]}"
                local source="certbot"
                # 判断证书来源
                if [[ " ${acmeshCerts[*]} " =~ " ${cert} " ]]; then
                    source="acme.sh"
                fi
                echo "$((i + 1)). ${cert} (${source})"
            done

            read -r -p "请输入证书序号 或 域名:" selectedDomain

            # 处理数字输入
            if [[ "${selectedDomain}" =~ ^[0-9]+$ ]] && [[ ${selectedDomain} -le ${#allCerts[@]} ]]; then
                selectedDomain="${allCerts[$((selectedDomain - 1))]}"
            fi

            # 尝试从 certbot 获取
            if [[ -d "/etc/letsencrypt/live/${selectedDomain}" ]]; then
                nativeCertPath="/etc/letsencrypt/live/${selectedDomain}/fullchain.pem"
                nativeKeyPath="/etc/letsencrypt/live/${selectedDomain}/privkey.pem"

                if [[ -f "${nativeCertPath}" && -f "${nativeKeyPath}" ]]; then
                    domain=${selectedDomain}
                    nativeACMEEnabled=true
                    echoContent green "\n ---> 证书来源: certbot"
                    echoContent green " ---> 证书路径: ${nativeCertPath}"
                    echoContent green " ---> 密钥路径: ${nativeKeyPath}"
                else
                    echoContent red "\n ---> 证书文件不存在"
                    nativeACMEEnabled=false
                fi
            # 尝试从 acme.sh 获取
            elif [[ -f "$HOME/.acme.sh/${selectedDomain}_ecc/${selectedDomain}.cer" ]] && [[ -f "$HOME/.acme.sh/${selectedDomain}_ecc/${selectedDomain}.key" ]]; then
                nativeCertPath="$HOME/.acme.sh/${selectedDomain}_ecc/${selectedDomain}.cer"
                nativeKeyPath="$HOME/.acme.sh/${selectedDomain}_ecc/${selectedDomain}.key"
                domain=${selectedDomain}
                nativeACMEEnabled=true
                echoContent green "\n ---> 证书来源: acme.sh"
                echoContent green " ---> 证书路径: ${nativeCertPath}"
                echoContent green " ---> 密钥路径: ${nativeKeyPath}"
            else
                echoContent red "\n ---> 域名不存在或证书文件不存在"
                nativeACMEEnabled=false
            fi
        fi
        ;;
    2)
        # 手动指定证书路径
        echoContent yellow "\n请输入证书完整路径 (fullchain.pem):"
        read -r -p "证书路径:" inputCertPath
        echoContent yellow "请输入私钥完整路径 (privkey.pem):"
        read -r -p "私钥路径:" inputKeyPath
        
        if [[ -f "${inputCertPath}" && -f "${inputKeyPath}" ]]; then
            nativeCertPath="${inputCertPath}"
            nativeKeyPath="${inputKeyPath}"
            nativeACMEEnabled=true
            
            # 尝试从证书中提取域名
            domain=$(openssl x509 -in "${nativeCertPath}" -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,]+' | head -1)
            if [[ -z "${domain}" ]]; then
                echoContent yellow "\n无法从证书提取域名，请手动输入:"
                read -r -p "域名:" domain
            fi
            
            echoContent green "\n ---> 使用证书: ${nativeCertPath}"
            echoContent green " ---> 使用密钥: ${nativeKeyPath}"
            echoContent green " ---> 域名: ${domain}"
        else
            echoContent red "\n ---> 证书或密钥文件不存在"
            nativeACMEEnabled=false
        fi
        ;;
    3)
        # 使用通配符证书
        echoContent yellow "\n请输入通配符证书的主域名 (例: example.com):"
        read -r -p "主域名:" wildcardDomain
        
        # 默认 Let's Encrypt 通配符证书路径
        local wildcardCertPath="/etc/letsencrypt/live/${wildcardDomain}/fullchain.pem"
        local wildcardKeyPath="/etc/letsencrypt/live/${wildcardDomain}/privkey.pem"
        
        # 如果默认路径不存在，询问自定义路径
        if [[ ! -f "${wildcardCertPath}" ]]; then
            echoContent yellow "\n默认路径不存在，是否指定自定义路径？[y/n]:"
            read -r -p "" customWildcardPath
            
            if [[ "${customWildcardPath}" == "y" ]]; then
                echoContent yellow "请输入通配符证书路径:"
                read -r -p "证书路径:" wildcardCertPath
                echoContent yellow "请输入通配符私钥路径:"
                read -r -p "私钥路径:" wildcardKeyPath
            fi
        fi
        
        if [[ -f "${wildcardCertPath}" && -f "${wildcardKeyPath}" ]]; then
            nativeCertPath="${wildcardCertPath}"
            nativeKeyPath="${wildcardKeyPath}"
            nativeACMEEnabled=true
            
            echoContent yellow "\n使用通配符证书，请输入实际使用的子域名 (例: sub.example.com):"
            read -r -p "域名:" domain
            
            echoContent green "\n ---> 通配符证书: ${nativeCertPath}"
            echoContent green " ---> 通配符密钥: ${nativeKeyPath}"
            echoContent green " ---> 应用域名: ${domain}"
        else
            echoContent red "\n ---> 通配符证书不存在"
            nativeACMEEnabled=false
        fi
        ;;
    4)
        # 使用 certbot 申请新证书
        if ! command -v certbot &> /dev/null; then
            echoContent red "\n ---> certbot 未安装"
            echoContent yellow " ---> 正在安装 certbot..."
            
            if [[ "${release}" == "ubuntu" ]] || [[ "${release}" == "debian" ]]; then
                ${installType} certbot >/dev/null 2>&1
            elif [[ "${release}" == "centos" ]]; then
                ${installType} certbot >/dev/null 2>&1
            fi
            
            if ! command -v certbot &> /dev/null; then
                echoContent red " ---> certbot 安装失败，将使用 acme.sh"
                nativeACMEEnabled=false
                return
            fi
            echoContent green " ---> certbot 安装成功"
        fi
        
        echoContent yellow "\n请输入域名 (例: example.com):"
        read -r -p "域名:" certbotDomain
        
        if [[ -z "${certbotDomain}" ]]; then
            echoContent red "\n ---> 域名不能为空"
            nativeACMEEnabled=false
            return
        fi
        
        domain=${certbotDomain}
        
        echoContent skyBlue "\n请选择证书类型:"
        echoContent yellow "1. 普通证书 (单域名)"
        echoContent yellow "2. 通配符证书 (需要 DNS 验证)\n"
        read -r -p "请选择 [1-2, 默认: 1]:" certbotCertType
        
        # 选择 CA 服务器 - 使用原有的 switchSSLType 逻辑
        switchSSLType
        
        local certbotServer=""
        local certbotEabKid=""
        local certbotEabHmac=""
        
        case ${sslType} in
        letsencrypt)
            certbotServer=""  # Let's Encrypt 是默认的
            ;;
        zerossl)
            certbotServer="--server https://acme.zerossl.com/v2/DV90"
            ;;
        buypass)
            certbotServer="--server https://api.buypass.com/acme/directory"
            ;;
        google)
            certbotServer="--server https://dv.acme-v02.api.pki.goog/directory"
            
            # 读取保存的 Google EAB 凭证
            if [[ -f /opt/xray-agent/tls/google_eab_kid ]]; then
                certbotEabKid=$(cat /opt/xray-agent/tls/google_eab_kid)
                certbotEabHmac=$(cat /opt/xray-agent/tls/google_eab_hmac)
                echoContent green "\n ---> 使用已保存的 Google EAB 凭证"
            fi
            
            if [[ -z "${certbotEabKid}" || -z "${certbotEabHmac}" ]]; then
                echoContent red "\n ---> 未找到 Google EAB 凭证，请先配置"
                nativeACMEEnabled=false
                return
            fi
            ;;
        *)
            certbotServer=""
            ;;
        esac
        
        echoContent yellow "\n正在使用 certbot 申请证书，请稍候..."
        
        local certbotCmd="certbot certonly --non-interactive --agree-tos --email admin@${certbotDomain} ${certbotServer}"
        
        # 添加 EAB 参数（如果是 Google GTS）
        if [[ -n "${certbotEabKid}" && -n "${certbotEabHmac}" ]]; then
            certbotCmd="${certbotCmd} --eab-kid ${certbotEabKid} --eab-hmac-key ${certbotEabHmac}"
        fi
        
        if [[ "${certbotCertType:-1}" == "2" ]]; then
            # 通配符证书 - 需要 DNS 验证
            echoContent yellow "\n通配符证书需要 DNS 验证"
            echoContent yellow "支持的 DNS 插件:"
            echoContent yellow "1. Cloudflare"
            echoContent yellow "2. 手动 DNS (需要手动添加 TXT 记录)\n"
            read -r -p "请选择 [1-2, 默认: 2]:" dnsPlugin
            
            if [[ "${dnsPlugin}" == "1" ]]; then
                # 检查 Cloudflare 插件
                if ! dpkg -l 2>/dev/null | grep -q python3-certbot-dns-cloudflare; then
                    echoContent yellow " ---> 安装 Cloudflare DNS 插件..."
                    ${installType} python3-certbot-dns-cloudflare >/dev/null 2>&1
                fi
                
                echoContent yellow "\n请输入 Cloudflare API Token:"
                read -r -p "API Token:" cfToken
                
                # 创建 Cloudflare 配置文件
                mkdir -p /root/.secrets
                echo "dns_cloudflare_api_token = ${cfToken}" > /root/.secrets/cloudflare.ini
                chmod 600 /root/.secrets/cloudflare.ini
                
                certbotCmd="${certbotCmd} --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d *.${certbotDomain} -d ${certbotDomain}"
            else
                # 手动 DNS
                certbotCmd="${certbotCmd} --manual --preferred-challenges dns -d *.${certbotDomain} -d ${certbotDomain}"
            fi
        else
            # 普通证书 - standalone
            certbotCmd="${certbotCmd} --standalone -d ${certbotDomain}"
        fi
        
        echoContent skyBlue "\n执行命令: ${certbotCmd}\n"
        
        if eval "${certbotCmd}"; then
            nativeCertPath="/etc/letsencrypt/live/${certbotDomain}/fullchain.pem"
            nativeKeyPath="/etc/letsencrypt/live/${certbotDomain}/privkey.pem"
            
            if [[ -f "${nativeCertPath}" && -f "${nativeKeyPath}" ]]; then
                nativeACMEEnabled=true
                echoContent green "\n ---> 证书申请成功"
                echoContent green " ---> 证书路径: ${nativeCertPath}"
                echoContent green " ---> 密钥路径: ${nativeKeyPath}"
            else
                echoContent red "\n ---> 证书文件未找到"
                nativeACMEEnabled=false
            fi
        else
            echoContent red "\n ---> 证书申请失败"
            nativeACMEEnabled=false
        fi
        ;;
    *)
        echoContent red "\n ---> 选择无效"
        nativeACMEEnabled=false
        ;;
    esac
    
    # 如果成功配置 native 证书，创建软链接
    if [[ "${nativeACMEEnabled}" == "true" && -n "${nativeCertPath}" && -n "${nativeKeyPath}" ]]; then
        mkdir -p /opt/xray-agent/tls
        ln -sf "${nativeCertPath}" "/opt/xray-agent/tls/${domain}.crt"
        ln -sf "${nativeKeyPath}" "/opt/xray-agent/tls/${domain}.key"
        echoContent green "\n ---> 已创建证书软链接到 /opt/xray-agent/tls/"
    fi
}
# 初始化dns配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        read -r -p "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "请输入Ali Key:" aliKey
        read -r -p "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}
# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent skyBlue "请选择 SSL 证书提供商"
        echoContent red "=============================================================="
        echoContent yellow "1. Let's Encrypt [推荐，默认]"
        echoContent green "   - 免费、稳定、广泛使用"
        echoContent green "   - 支持所有申请方式\n"
        echoContent yellow "2. ZeroSSL"
        echoContent green "   - 免费、支持ECC"
        echoContent green "   - 需要注册账号\n"
        echoContent yellow "3. Buypass"
        echoContent green "   - 免费、挪威CA机构"
        echoContent red "   - 不支持DNS API申请\n"
        echoContent yellow "4. Google Trust Services (GTS)"
        echoContent green "   - Google提供的免费证书"
        echoContent green "   - 支持所有申请方式"
        echoContent green "   - 与Chrome浏览器兼容性好"
        echoContent red "   ⚠️  需要 EAB 凭证 (External Account Binding)"
        echoContent skyBlue "   📌 获取地址: https://cloud.google.com/certificate-manager/docs/public-ca\n"
        echoContent red "=============================================================="
        read -r -p "请选择 [1-4，回车默认使用 Let's Encrypt]:" selectSSLType
        case ${selectSSLType} in
        1)
            sslType="letsencrypt"
            echoContent green "\n ---> 已选择: Let's Encrypt"
            ;;
        2)
            sslType="zerossl"
            echoContent green "\n ---> 已选择: ZeroSSL"
            ;;
        3)
            sslType="buypass"
            echoContent green "\n ---> 已选择: Buypass"
            ;;
        4)
            sslType="google"
            echoContent green "\n ---> 已选择: Google Trust Services (GTS)"
            echoContent red "\n=============================================================="
            echoContent skyBlue "⚠️  Google GTS 需要 External Account Binding (EAB) 凭证"
            echoContent red "=============================================================="
            echoContent yellow "获取步骤:"
            echoContent white "1. 访问 Google Cloud Console"
            echoContent white "2. 启用 Public Certificate Authority API"
            echoContent white "3. 创建 External Account Key"
            echoContent white "4. 获取 KID 和 HMAC Key\n"
            echoContent skyBlue "📖 详细文档: https://cloud.google.com/certificate-manager/docs/public-ca"
            echoContent skyBlue "🔗 快速链接: https://console.cloud.google.com/security/publicca\n"
            echoContent red "=============================================================="
            read -r -p "请输入 EAB Key ID (KID): " googleEabKid
            read -r -p "请输入 EAB HMAC Key: " googleEabHmac
            
            if [[ -z "${googleEabKid}" || -z "${googleEabHmac}" ]]; then
                echoContent red "\n ---> EAB 凭证不能为空，退出安装"
                echoContent yellow " ---> 建议使用 Let's Encrypt (无需额外注册)"
                exit 0
            fi
            
            # 保存 EAB 凭证
            echo "${googleEabKid}" > /opt/xray-agent/tls/google_eab_kid
            echo "${googleEabHmac}" > /opt/xray-agent/tls/google_eab_hmac
            echoContent green "\n ---> EAB 凭证已保存"
            ;;
        *)
            sslType="letsencrypt"
            echoContent green "\n ---> 已选择: Let's Encrypt (默认)"
            ;;
        esac
        if [[ -n "${dnsAPIType}" && "${sslType}" == "buypass" ]]; then
            echoContent red " ---> Buypass 不支持 DNS API 申请证书"
            exit 0
        fi
        echo "${sslType}" >/opt/xray-agent/tls/ssl_type
    fi
}

# 选择acme安装证书方式
selectAcmeInstallSSL() {
    #    local sslIPv6=
    #    local currentIPType=
    if [[ "${ipType}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi
    #    currentIPType=$(curl -s "-${ipType}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    #    if [[ -z "${currentIPType}" ]]; then
    #                currentIPType=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)
    #        if [[ -n "${currentIPType}" ]]; then
    #            sslIPv6="--listen-v6"
    #        fi
    #    fi

    acmeInstallSSL

    readAcmeTLS
}

# 安装SSL证书
acmeInstallSSL() {
    # Google GTS 需要先注册 EAB 账号
    if [[ "${sslType}" == "google" ]]; then
        local googleEabKid=""
        local googleEabHmac=""
        
        # 读取保存的 EAB 凭证
        if [[ -f /opt/xray-agent/tls/google_eab_kid ]]; then
            googleEabKid=$(cat /opt/xray-agent/tls/google_eab_kid)
            googleEabHmac=$(cat /opt/xray-agent/tls/google_eab_hmac)
        fi
        
        if [[ -n "${googleEabKid}" && -n "${googleEabHmac}" ]]; then
            echoContent skyBlue " ---> 检测到 Google EAB 凭证，正在注册账号..."
            
            # 注册 Google GTS 账号
            if ! "$HOME/.acme.sh/acme.sh" --register-account \
                --server google \
                --eab-kid "${googleEabKid}" \
                --eab-hmac-key "${googleEabHmac}" 2>&1 | tee -a /opt/xray-agent/tls/acme.log; then
                
                echoContent red "\n ---> Google GTS 账号注册失败"
                echoContent yellow " ---> 请检查 EAB 凭证是否正确"
                echoContent yellow " ---> 或选择其他证书提供商 (Let's Encrypt)"
                exit 0
            fi
            
            echoContent green " ---> Google GTS 账号注册成功"
        fi
    fi
    
    local dnsAPIDomain="${tlsDomain}"
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API 生成证书中"
        sudo CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /opt/xray-agent/tls/acme.log >/dev/null
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API 生成证书中"
        sudo Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /opt/xray-agent/tls/acme.log >/dev/null
    else
        echoContent green " ---> 生成证书中"
        
        # Standalone 模式需要停止 Nginx 以释放 80 端口
        if [[ -n "${customNginxConfigPath}" ]]; then
            # Docker Nginx - 停止容器
            local dockerNginxContainer=$(docker ps --filter "name=nginx" --format "{{.Names}}" 2>/dev/null | head -n 1)
            if [[ -n "${dockerNginxContainer}" ]]; then
                echoContent yellow " ---> 停止 Docker Nginx 容器以释放 80 端口"
                docker stop "${dockerNginxContainer}" >/dev/null 2>&1
            fi
        else
            # 系统 Nginx
            handleNginx stop
        fi
        
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /opt/xray-agent/tls/acme.log >/dev/null
        
        # 证书申请完成后重启 Nginx
        if [[ -n "${customNginxConfigPath}" ]]; then
            # Docker Nginx - 重启容器
            local dockerNginxContainer=$(docker ps -a --filter "name=nginx" --format "{{.Names}}" 2>/dev/null | head -n 1)
            if [[ -n "${dockerNginxContainer}" ]]; then
                echoContent green " ---> 重启 Docker Nginx 容器"
                docker start "${dockerNginxContainer}" >/dev/null 2>&1
            fi
        fi
    fi
}
# 自定义端口
customPortFunction() {
    local historyCustomPortStatus=
    if [[ -n "${customPort}" || -n "${currentPort}" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口？[y/n]:" historyCustomPortStatus
            if [[ "${historyCustomPortStatus}" == "y" ]]; then
                port=${currentPort}
                echoContent yellow "\n ---> 端口: ${port}"
            fi
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${currentPort}
        fi
    fi
    if [[ -z "${currentPort}" ]] || [[ "${historyCustomPortStatus}" == "n" ]]; then
        echo

        if [[ -n "${btDomain}" ]]; then
            echoContent yellow "请输入端口[不可与BT Panel/1Panel端口相同，回车随机]"
            read -r -p "端口:" port
            if [[ -z "${port}" ]]; then
                port=$((RANDOM % 20001 + 10000))
            fi
        else
            echo
            echoContent yellow "请输入端口[默认: 443]，可自定义端口[回车使用默认]"
            read -r -p "端口:" port
            if [[ -z "${port}" ]]; then
                port=443
            fi
            if [[ "${port}" == "${xrayVLESSRealityPort}" ]]; then
                handleXray stop
            fi
        fi

        if [[ -n "${port}" ]]; then
            if ((port >= 1 && port <= 65535)); then
                allowPort "${port}"
                echoContent yellow "\n ---> 端口: ${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}"
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}"
                fi
            else
                echoContent red " ---> 端口输入错误"
                exit 0
            fi
        else
            echoContent red " ---> 端口不可为空"
            exit 0
        fi
    fi
}

# 检测端口是否占用
checkPort() {
    if [[ -n "$1" ]] && lsof -i "tcp:$1" | grep -q LISTEN; then
        echoContent red "\n=============================================================="
        echoContent yellow "端口 $1 已被占用"
        echoContent skyBlue "\n占用进程信息："
        lsof -i "tcp:$1" | grep LISTEN
        
        # 检查是否是 Nginx 占用
        if lsof -i "tcp:$1" | grep -q nginx; then
            echoContent yellow "\n检测到端口被 Nginx 占用，这可能是现有业务"
            echoContent red "警告：强制使用此端口可能影响现有服务！"
        fi
        echoContent red "==============================================================\n"
        
        read -r -p "是否继续（可能导致冲突）？[y/n]:" continueWithConflict
        if [[ "${continueWithConflict}" != "y" ]]; then
            echoContent yellow "请更换端口或关闭占用进程后重试"
            exit 0
        fi
    fi
}

# 安装TLS
installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    
    # 检查是否使用 Native ACME 证书
    if [[ "${nativeACMEEnabled}" == "true" ]]; then
        echoContent green " ---> 使用 Native ACME 证书"
        echoContent green " ---> 证书路径: ${nativeCertPath}"
        echoContent green " ---> 密钥路径: ${nativeKeyPath}"
        
        # 验证证书文件存在
        if [[ -f "/opt/xray-agent/tls/${domain}.crt" && -f "/opt/xray-agent/tls/${domain}.key" ]]; then
            echoContent green " ---> Native ACME 证书已就绪"
            return 0
        else
            echoContent red " ---> Native ACME 证书软链接创建失败"
            exit 0
        fi
    fi
    
    readAcmeTLS
    local tlsDomain=${domain}

    # 安装tls
    if [[ -f "/opt/xray-agent/tls/${tlsDomain}.crt" && -f "/opt/xray-agent/tls/${tlsDomain}.key" && -n $(cat "/opt/xray-agent/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> 检测到证书"
        renewalTLS

        if [[ -z $(find /opt/xray-agent/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /opt/xray-agent/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/opt/xray-agent/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchain-file "/opt/xray-agent/tls/${tlsDomain}.crt" --key-file "/opt/xray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchain-file "/opt/xray-agent/tls/${tlsDomain}.crt" --key-file "/opt/xray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
                    read -r -p "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        rm -rf /opt/xray-agent/tls/*
                        installTLS "$1"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采用API申请证书"
            echoContent green " ---> 安装TLS证书，需要依赖80端口"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/opt/xray-agent/tls/${tlsDomain}.crt" --keypath "/opt/xray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/opt/xray-agent/tls/${tlsDomain}.crt" --keypath "/opt/xray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "/opt/xray-agent/tls/${tlsDomain}.crt" || ! -f "/opt/xray-agent/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/opt/xray-agent/tls/${tlsDomain}.key") || -z $(cat "/opt/xray-agent/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /opt/xray-agent/tls/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLS安装失败，请检查acme日志"
                exit 0
            fi

            echo

            if tail -n 10 /opt/xray-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email"
                installTLSCount=1
                installTLS "$1"
            else
                installTLSCount=1
                installTLS "$1"
            fi
        fi

        echoContent green " ---> TLS生成成功"
    else
        echoContent yellow " ---> 未安装acme.sh"
        exit 0
    fi
}

# 初始化随机字符串
