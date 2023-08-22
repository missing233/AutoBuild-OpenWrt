#!/bin/sh
#   Copyright (C) 2023  沉默の金

trap 'rm -rf "$TMPDIR"' EXIT
TMPDIR=$(mktemp -d) || exit 1
cmd=$1
arg=$2


main() {
    check
    case "${cmd}" in
        update)
            check_curl
            case "${arg}" in
                packages)
                    update_package
                    ;;
                firmware)
                    update_firmware
                    ;;
                tool)
                    update_tool
                    ;;
                *)
                 echo "不支持的参数 $arg"            
            esac
            ;;
        info)
            show_info
            ;;
        help)
            usage
            ;;
        --help)
            usage
            ;;
        *)
        echo "不支持的命令 $cmd"
        usage
    esac
}

check() {
    if [ "$(grep -c "^ID_LIKE=\"lede openwrt\"$" /etc/os-release)" -eq '0' ];then
        echo "不支持非openwrt类系统"
        exit 1
    fi
}

show_info() {
    echo "固件系统："$(sed -n  "/^NAME=\"/p" /etc/os-release | sed -e "s/NAME=\"//g" -e "s/\"//g" )
    echo "固件版本："$(sed -n  "/^DISTRIB_RELEASE=\'/p" /etc/openwrt_release|sed -e "s/DISTRIB_RELEASE='//g" -e "s/'//g" )
    echo "固件架构："$(sed -n  "/^DISTRIB_ARCH=\'/p" /etc/openwrt_release|sed -e "s/DISTRIB_ARCH='//g" -e "s/'//g" )
    if  [ -e "/etc/openwrt-k_info" ]; then
        echo "固件编译者："$(sed -n  "/^COMPILER=\"/p" /etc/openwrt-k_info | sed -e "s/COMPILER=\"//g" -e "s/\"//g" )
        echo "固件编译仓库地址："$(sed -n  "/REPOSITORY_URL=\"/p" /etc/openwrt-k_info | sed -e "s/REPOSITORY_URL=\"//g" -e "s/\"//g" )
        echo "固件编译时间：UTC+8 "$(sed -n  "/^COMPILE_START_TIME=\"/p" /etc/openwrt-k_info | sed -e "s/COMPILE_START_TIME=\"//g" -e "s/\"/时/g" -e "s/-/日/" -e "s/\./月/g" -e "s/月/年/" )
        echo "固件发布名称："$(sed -n  "/^RELEASE_NAME=\"/p" /etc/openwrt-k_info | sed -e "s/RELEASE_NAME=\"//g" -e "s/\"//g" )
        echo "固件标签名称："$(sed -n  "/RELEASE_TAG_NAME=\"/p" /etc/openwrt-k_info | sed -e "s/RELEASE_TAG_NAME=\"//g" -e "s/\"//g" )
    elif [ "$(grep -c "Compiled by" /etc/openwrt_release)" -ne '0' ];then
        echo "固件编译者："$(sed -n  "/Compiled by /p" /etc/openwrt_release|sed -e "s/.*Compiled by //g" -e "s/'//g" )
    fi
}

check_curl(){
	which curl && return || 未找到curl
    echo "错误:未检测到依赖的包curl"
    exit 1
}

check_github(){
    echo "检测与github的连通性"
    echo "github.com"
    curl -o /dev/null --connect-timeout 5 -s -w %{time_namelookup}---%{time_connect}---%{time_starttransfer}---%{time_total}---%{speed_download}"\n" github.com || github_check_failed
    echo "api.github.com"
    curl -o /dev/null --connect-timeout 5 -s -w %{time_namelookup}---%{time_connect}---%{time_starttransfer}---%{time_total}---%{speed_download}"\n" api.github.com || github_check_failed
    echo "objects.githubusercontent.com"
    curl -o /dev/null --connect-timeout 5 -s -w %{time_namelookup}---%{time_connect}---%{time_starttransfer}---%{time_total}---%{speed_download}"\n" objects.githubusercontent.com || github_check_failed
}

github_check_failed(){
    echo github测试失败
    exit 1
}

download_failed() {
    echo "下载失败,请检查你的网络环境是否良好"
    exit 1
}

update_package() {
    if ! type sed;then
        echo "错误:未检测到依赖的包sed" 
        exit 1
    fi
    if ! type diff;then
        echo "错误:未检测到依赖的包diffutils" 
        exit 1
    fi
    if ! type unzip;then
        echo "错误:未检测到依赖的包unzip" 
        exit 1
    fi    
    check_github
    mkdir -p $TMPDIR/update/package
    cd $TMPDIR/update/package
    [[ -d $TMPDIR ]] && rm -rf $TMPDIR/update/package/* || exit 1
    opkg list-installed > installed.list
    if  [ ! -e "/etc/openwrt-k_info" ]; then
        echo "错误：未找到openwrt-k_info"
        exit 1
    elif [ "$(grep -c "^REPOSITORY_URL=" /etc/openwrt-k_info)" -eq '0' ]; then
        echo "错误：未知的固件编译仓库地址"
        exit 1
    elif [ "$(grep -c "^RELEASE_TAG_NAME=" /etc/openwrt-k_info)" -eq '0' ]; then
        echo "错误：未知的固件标签名称"
        exit 1
    fi
    REPOSITORY_URL=$(sed -n  "/REPOSITORY_URL=\"/p" /etc/openwrt-k_info | sed -e "s/REPOSITORY_URL=\"//g" -e "s/\"//g")
    REPOSITORY=$(echo $REPOSITORY_URL|sed -e "s/https:\/\/github.com\///")
    RELEASE_TAG_NAME=$(sed -n  "/RELEASE_TAG_NAME=\"/p" /etc/openwrt-k_info | sed -e "s/RELEASE_TAG_NAME=\"//g" -e "s/\"//g")
    RELEASE_TAG_MAINNAME=$(echo $RELEASE_TAG_NAME | sed "s/v[0-9]\{1,2\}.[0-9]\{2,2\}.[0-9]\{1,2\}-[0-9]\{2,2\}(/(/")
    latest_ver="$(curl -s https://api.github.com/repos/$REPOSITORY/releases 2>/dev/null | grep -E 'tag_name' | grep "$RELEASE_TAG_MAINNAME" | sed -e 's/    "tag_name": "//' -e 's/",//' | sed -n '1p')"
    FILE_NAME=$(curl -s "https://api.github.com/repos/$REPOSITORY/releases/tags/$latest_ver"| grep -E 'name'| grep -E '\.manifest'| sed -e 's/      "name": "//' -e 's/",//' | sed -n '1p')
    curl -L --retry 3 --connect-timeout 20 $REPOSITORY_URL/releases/download/${latest_ver}/$FILE_NAME -o package.list || download_failed
    if ! diff installed.list package.list -y -W 80 -B -b | grep  '|' |sed -e "s/^/update:/g" -e 's/|/>/g' -e "/kmod-/d" > update.list; then
        echo "没有可更新的包"
        exit 0
    else
        if [ -z "$(cat update.list)" ]; then
            echo "没有可更新的包"
            exit 0  
        else
            echo "将更新以下包："
            cat update.list
            diff installed.list package.list -y -W 80 -B -b | grep  '|' | sed -e "s/ -.*//g" -e "s/ //g" -e "s/$/_/g" > update_package.list
        fi
    fi
    echo "这将下载releases中的package.zip请确保你有足够的空间与良好的网络"
    read -n1 -p "是否继续 [Y/N]?" answer
    case "$answer" in
    Y | y)
        echo "继续"
        ;;
    N | n)
        echo "你选择了退出"
        exit 0
        ;;

    *)
        echo "错误:未指定的选择"
        exit 1
        ;;
    esac
    read -n1 -p "下载到内存 [Y/N]?" answer
    case "$answer" in
    Y | y)
        echo "下载到内存"
        mkdir $TMPDIR/update/package/download
        DOWNLOAD_PATH=$TMPDIR/update/package/download/newpackage.zip
        ;;
    N | n)
        echo "下载到磁盘"
        mkdir -p /usr/share/cmzj/download
        DOWNLOAD_PATH=/usr/share/cmzj/download/newpackage.zip
        ;;

    *)
        echo "错误:未指定的选择"
        exit 1
        ;;
    esac
    [[ -d /usr/share/cmzj/download/ ]] && rm -rf /usr/share/cmzj/download/*
    curl -L --retry 3 --connect-timeout 20 $REPOSITORY_URL/releases/download/${latest_ver}/package.zip -o $DOWNLOAD_PATH || download_failed
    unzip -l $DOWNLOAD_PATH |grep "-"|grep ":"|grep " "|sed "s/.*[0-9][0-9]-[0-9]\{1,2\}-[0-9]\{1,5\} [0-9]\{1,2\}:[0-9]\{1,2\}   //g"|sed "s/ //g" > newpackage.list
    unzip $DOWNLOAD_PATH $(grep "$(cat update_package.list)" newpackage.list | sed ':label;N;s/\n/ /;b label') -d $TMPDIR/update/package
    rm -rf /usr/share/cmzj/download $TMPDIR/update/package/download
    if opkg install $TMPDIR/update/package/package/* ; then
        echo "安装成功"        
    else
        echo "安装失败"
    fi
}

update_firmware() {
    echo "不支持的参数 $arg"
}

update_tool() {
    echo "这可能会导致工具与固件不兼容"
    read -n1 -p "是否继续 [Y/N]?" answer
    case "$answer" in
    Y | y)
        echo "继续"
        ;;
    N | n)
        echo "你选择了退出"
        exit 0
        ;;

    *)
        echo "错误:未指定的选择"
        exit 1
        ;;
    esac
    curl -L --retry 3 --connect-timeout 20 https://raw.githubusercontent.com/chenmozhijin/OpenWrt-K/main/files/usr/share/cmzj/openwrt-k_tool.sh -o $TMPDIR/openwrt-k_tool.sh || download_failed
    mv $TMPDIR/openwrt-k_tool.sh /usr/share/cmzj/openwrt-k_tool.sh && exit 0
}

usage() {
    echo "OpenWrt-K工具"
    echo "固件项目地址：https://github.com/chenmozhijin/OpenWrt-K"
    echo ""
    echo "Usage: OpenWrt-K <command> [<arguments>]"
    echo ""
    echo "Commands:"
    echo "update <packages|rules|tool>              更新包/规则/本工具"
    #echo "update <packages|rules|firmwar|tool>     更新包/规则/固件/本工具"
    echo "info                                      打印固件信息"
}
main
