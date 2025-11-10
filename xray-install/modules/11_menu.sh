#!/usr/bin/env bash
# 模块 11：交互菜单与入口逻辑

# 主菜单
menu() {
    cd "$HOME" || exit
    echoContent red "\n=============================================================="
    echoContent green "当前版本：v1.0.0"
    echoContent green "描述：Xray 一键安装管理脚本\c"
    showInstallStatus
    checkWgetShowProgress
    echoContent skyBlue "快捷命令：xraya"
    echoContent red "\n=============================================================="
    if [[ -n "${coreInstallType}" ]]; then
        echoContent yellow "1.重新安装"
    else
        echoContent yellow "1.安装"
    fi

    echoContent yellow "2.任意组合安装"
    echoContent yellow "3.REALITY管理"

    echoContent skyBlue "-------------------------工具管理-----------------------------"
    echoContent yellow "4.用户管理"
    echoContent yellow "5.伪装站管理"
    echoContent yellow "6.证书管理"
    echoContent yellow "7.分流工具"
    echoContent yellow "8.添加新端口"
    echoContent yellow "9.ALPN切换"
    echoContent skyBlue "-------------------------版本管理-----------------------------"
    echoContent yellow "10.core管理"
    echoContent yellow "11.更新脚本"
    echoContent skyBlue "-------------------------脚本管理-----------------------------"
    echoContent yellow "12.卸载脚本"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "请选择:" selectInstallType
    case ${selectInstallType} in
    1)
        selectCoreInstall
        ;;
    2)
        selectCoreInstall
        ;;
        #    3)
        #        initXrayFrontingConfig 1
        #        ;;
    3)
        manageReality 1
        ;;
    4)
        manageAccount 1
        ;;
    5)
        updateNginxBlog 1
        ;;
    6)
        renewalTLS 1
        ;;
    7)
        routingToolsMenu 1
        ;;
    8)
        addCorePort 1
        ;;
    9)
        switchAlpn 1
        ;;
    10)
        coreVersionManageMenu 1
        ;;
    11)
        updateV2RayAgent 1
        ;;
    12)
        unInstall 1
        ;;
    esac
}
