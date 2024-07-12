#!/usr/bin/env bash
set -e
set -u
set -o pipefail

# ------------share--------------
invocation='echo "" && say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'
exec 3>&1
if [ -t 1 ] && command -v tput >/dev/null; then
    ncolors=$(tput colors || echo 0)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold || echo)"
        normal="$(tput sgr0 || echo)"
        black="$(tput setaf 0 || echo)"
        red="$(tput setaf 1 || echo)"
        green="$(tput setaf 2 || echo)"
        yellow="$(tput setaf 3 || echo)"
        blue="$(tput setaf 4 || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6 || echo)"
        white="$(tput setaf 7 || echo)"
    fi
fi

say_warning() {
    printf "%b\n" "${yellow:-}ray_naive_install: Warning: $1${normal:-}" >&3
}

say_err() {
    printf "%b\n" "${red:-}ray_naive_install: Error: $1${normal:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}ray_naive_install:${normal:-} $1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

machine_has() {
    eval $invocation

    command -v "$1" >/dev/null 2>&1
    return $?
}

# args:
# remote_path - $1
get_http_header_curl() {
    eval $invocation

    local remote_path="$1"

    curl_options="-I -sSL --retry 5 --retry-delay 2 --connect-timeout 15 "
    curl $curl_options "$remote_path" 2>&1 || return 1
    return 0
}

# args:
# remote_path - $1
get_http_header_wget() {
    eval $invocation

    local remote_path="$1"
    local wget_options="-q -S --spider --tries 5 "
    # Store options that aren't supported on all wget implementations separately.
    local wget_options_extra="--waitretry 2 --connect-timeout 15 "
    local wget_result=''

    wget $wget_options $wget_options_extra "$remote_path" 2>&1
    wget_result=$?

    if [[ $wget_result == 2 ]]; then
        # Parsing of the command has failed. Exclude potentially unrecognized options and retry.
        wget $wget_options "$remote_path" 2>&1
        return $?
    fi

    return $wget_result
}

# Updates global variables $http_code and $download_error_msg
downloadcurl() {
    eval $invocation

    unset http_code
    unset download_error_msg
    local remote_path="$1"
    local out_path="${2:-}"
    local remote_path_with_credential="${remote_path}"
    local curl_options="--retry 20 --retry-delay 2 --connect-timeout 15 -sSL -f --create-dirs "
    local failed=false
    if [ -z "$out_path" ]; then
        curl $curl_options "$remote_path_with_credential" 2>&1 || failed=true
    else
        curl $curl_options -o "$out_path" "$remote_path_with_credential" 2>&1 || failed=true
    fi
    if [ "$failed" = true ]; then
        local response=$(get_http_header_curl $remote_path)
        http_code=$(echo "$response" | awk '/^HTTP/{print $2}' | tail -1)
        download_error_msg="Unable to download $remote_path."
        if [[ $http_code != 2* ]]; then
            download_error_msg+=" Returned HTTP status code: $http_code."
        fi
        say_verbose "$download_error_msg"
        return 1
    fi
    return 0
}

# Updates global variables $http_code and $download_error_msg
downloadwget() {
    eval $invocation

    unset http_code
    unset download_error_msg
    local remote_path="$1"
    local out_path="${2:-}"
    local remote_path_with_credential="${remote_path}"
    local wget_options="--tries 20 "
    # Store options that aren't supported on all wget implementations separately.
    local wget_options_extra="--waitretry 2 --connect-timeout 15 "
    local wget_result=''

    if [ -z "$out_path" ]; then
        wget -q $wget_options $wget_options_extra -O - "$remote_path_with_credential" 2>&1
        wget_result=$?
    else
        wget $wget_options $wget_options_extra -O "$out_path" "$remote_path_with_credential" 2>&1
        wget_result=$?
    fi

    if [[ $wget_result == 2 ]]; then
        # Parsing of the command has failed. Exclude potentially unrecognized options and retry.
        if [ -z "$out_path" ]; then
            wget -q $wget_options -O - "$remote_path_with_credential" 2>&1
            wget_result=$?
        else
            wget $wget_options -O "$out_path" "$remote_path_with_credential" 2>&1
            wget_result=$?
        fi
    fi

    if [[ $wget_result != 0 ]]; then
        local disable_feed_credential=false
        local response=$(get_http_header_wget $remote_path $disable_feed_credential)
        http_code=$(echo "$response" | awk '/^  HTTP/{print $2}' | tail -1)
        download_error_msg="Unable to download $remote_path."
        if [[ $http_code != 2* ]]; then
            download_error_msg+=" Returned HTTP status code: $http_code."
        fi
        say_verbose "$download_error_msg"
        return 1
    fi

    return 0
}

# args:
# remote_path - $1
# [out_path] - $2 - stdout if not provided
download() {
    eval $invocation

    local remote_path="$1"
    local out_path="${2:-}"

    if [[ "$remote_path" != "http"* ]]; then
        cp "$remote_path" "$out_path"
        return $?
    fi

    local failed=false
    local attempts=0
    while [ $attempts -lt 3 ]; do
        attempts=$((attempts + 1))
        failed=false
        if machine_has "curl"; then
            downloadcurl "$remote_path" "$out_path" || failed=true
        elif machine_has "wget"; then
            downloadwget "$remote_path" "$out_path" || failed=true
        else
            say_err "Missing dependency: neither curl nor wget was found."
            exit 1
        fi

        if [ "$failed" = false ] || [ $attempts -ge 3 ] || { [ ! -z $http_code ] && [ $http_code = "404" ]; }; then
            break
        fi

        say "Download attempt #$attempts has failed: $http_code $download_error_msg"
        say "Attempt #$((attempts + 1)) will start in $((attempts * 10)) seconds."
        sleep $((attempts * 10))
    done

    if [ "$failed" = true ]; then
        say_verbose "Download failed: $remote_path"
        return 1
    fi
    return 0
}
# ---------------------------------

echo '  ____               ____  _              '
echo ' |  _ \ __ _ _   _  / ___|(_)_ __   __ _  '
echo ' | |_) / _` | | | | \___ \| |  _ \ / _  | '
echo ' |  _ < (_| | |_| |  ___) | | | | | (_| | '
echo ' |_| \_\__,_|\__, | |____/|_|_| |_|\__, | '
echo '             |___/                 |___/  '

# ------------vars-----------、
gitRowUrl="https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main"

proxy_uuid=""
proxy_name=""
proxy_pwd=""

domain=""
cert_choice=""
cert_path=""
cert_private_key_path=""
email=""

port_vmess=""
port_naive=""
port_hy2=""

verbose=false
# --------------------------

# read params from init cmd
while [ $# -ne 0 ]; do
    name="$1"
    case "$name" in
    -u | --proxy-uuid | -[Pp]roxy[Uu]uid)
        shift
        proxy_uuid="$1"
        ;;
    -n | --proxy-name | -[Pp]roxy[Nn]ame)
        shift
        proxy_name="$1"
        ;;
    -p | --proxy-pwd | -[Pp]roxy[Pp]wd)
        shift
        proxy_pwd="$1"
        ;;
    -d | --domain | -[Dd]omain)
        shift
        domain="$1"
        ;;
    -m | --mail | -[Mm]ail)
        shift
        email="$1"
        ;;
    -c | --cert-path | -[Cc]ert[Pp]ath)
        shift
        cert_path="$1"
        ;;
    -k | --cert-private-key-path | -[Cc]ert[Pp]rivate[Kk]ey[Pp]ath)
        shift
        cert_private_key_path="$1"
        ;;
    --verbose | -[Vv]erbose)
        verbose=true
        ;;
    -? | --? | -h | --help | -[Hh]elp)
        script_name="$(basename "$0")"
        echo "Ray Naiveproxy in Docker"
        echo "Usage: $script_name [-t|--host <HOST>] [-m|--mail <MAIL>]"
        echo "       $script_name -h|-?|--help"
        echo ""
        echo "$script_name is a simple command line interface to install naiveproxy in docker."
        echo ""
        echo "Options:"
        echo "  -t,--host <HOST>         Your host, Defaults to \`$host\`."
        echo "      -Host"
        echo "          Possible values:"
        echo "          - xui.test.com"
        echo "  -m,--mail <MAIL>         Your mail, Defaults to \`$mail\`."
        echo "      -Mail"
        echo "          Possible values:"
        echo "          - mail@qq.com"
        echo "  -u,--user <USER>         Your proxy user name, Defaults to \`$user\`."
        echo "      -User"
        echo "          Possible values:"
        echo "          - user"
        echo "  -p,--pwd <PWD>         Your proxy password, Defaults to \`$pwd\`."
        echo "      -Pwd"
        echo "          Possible values:"
        echo "          - 1qaz@wsx"
        echo "  -f,--fake-host <FAKEHOST>         Your fake host, Defaults to \`$fakeHost\`."
        echo "      -FakeHost"
        echo "          Possible values:"
        echo "          - https://demo.cloudreve.org"
        echo "  -?,--?,-h,--help,-Help             Shows this help message"
        echo ""
        exit 0
        ;;
    *)
        say_err "Unknown argument \`$name\`"
        exit 1
        ;;
    esac
    shift
done

read_var_from_user() {
    eval $invocation

    # host
    if [ -z "$domain" ]; then
        echo "节点需要一个域名，请提供一个域名，且确保该域名已DNS到服务器ip："
        read -p "请输入域名(如demo.test.tk):" domain
    else
        say "域名: $domain"
    fi

    # proxy uuid
    if [ -z "$proxy_uuid" ]; then
        read -p "请输入节点uuid(如c2cd9b44-e92f-80a6-b5ae-43c8cd37f476):" proxy_uuid
    else
        say "节点uuid: $proxy_uuid"
    fi

    # proxy用户名
    if [ -z "$proxy_name" ]; then
        read -p "请输入节点用户名(如ray):" proxy_name
    else
        say "节点用户名: $proxy_name"
    fi

    # proxy密码
    if [ -z "$proxy_pwd" ]; then
        read -p "请输入节点密码(如1qaz@wsx):" proxy_pwd
    else
        say "节点密码: $proxy_pwd"
    fi

    # 端口
    if [ -z "$port_vmess" ]; then
        read -p "vmess端口(如8080，需防火墙放行该端口tcp流量):" port_vmess
    else
        say "vmess端口: $port_vmess"
    fi
}

download_sing-box_binary() {
    eval $invocation

    say "installing"

    download https://pkg.freebsd.org/FreeBSD:14:amd64/latest/All/sing-box-1.9.3.pkg ./sing-box-1.9.3.pkg
    tar -xvf sing-box-1.9.3.pkg

    touch ~/.bashrc
    echo "export PATH=\"\$PATH:$PWD/usr/local/bin\"" >~/.bashrc
    chmod +x ~/.bashrc && ~/.bashrc

    say "check sing-box"
    export PATH="$PATH:$PWD/usr/local/bin"
    sing-box version
}

# 下载data
download_data_files() {
    eval $invocation

    mkdir -p ./data

    # config.json
    rm -rf ./data/config.json
    download $gitRowUrl/sing-box/data/config_serv00.json ./data/config.json

    # entry.sh
    rm -rf ./data/entry.sh
    download $gitRowUrl/sing-box/data/entry.sh ./data/entry.sh
}

# 配置
replace_configs() {
    eval $invocation

    # replace domain
    sed 's|<domain>|'"$domain"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # certs
    sed 's|<cert_path>|'"$cert_path"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json
    sed 's|<cert_private_key_path>|'"$cert_private_key_path"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # replace mail
    sed 's|<email>|'"$email"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_uuid
    sed 's|<proxy_uuid>|'"$proxy_uuid"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_name
    sed 's|<proxy_name>|'"$proxy_name"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_pwd
    sed 's|<proxy_pwd>|'"$proxy_pwd"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    say "config.json:"
    cat ./data/config.json
}

# 运行容器
run() {
    eval $invocation

    chmod +x ./data/entry.sh && ./data/entry.sh $PWD/data
}

# 检查容器运行状态
check_result() {
    eval $invocation

    say "search running processes:"
    ps -axj | grep sing-box

    echo ""
    echo "==============================================="
    echo "Congratulations! 恭喜！"
    echo "创建并运行sing-box容器成功。"
    echo ""
    echo "请使用客户端尝试连接你的节点进行测试"
    echo ""
    echo "vmess节点如下："
    echo "服务器：$domain"
    echo "端口：$port_vmess"
    echo "UUID：$proxy_uuid"
    echo "Alter Id：0"
    echo "传输：ws"
    echo "Path：/download"
    echo "Host：download.windowsupdate.com"
    echo ""
    echo "Enjoy it~"
    echo "==============================================="
}

main() {
    download_sing-box_binary

    read_var_from_user

    download_data_files
    replace_configs

    run

    check_result
}

main
