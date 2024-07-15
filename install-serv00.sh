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

print_prefix="ray_sbox_install"

warning() {
    printf "%b\n" "${yellow:-}$1${normal:-}" >&3
}
say_warning() {
    printf "%b\n" "${yellow:-}$print_prefix: Warning: $1${normal:-}" >&3
}

err() {
    printf "%b\n" "${red:-}$1${normal:-}" >&2
}
say_err() {
    printf "%b\n" "${red:-}$print_prefix: Error: $1${normal:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}$print_prefix:${normal:-} $1" >&3
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

    if [[ $wget_result = 2 ]]; then
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

    if [[ $wget_result = 2 ]]; then
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

# ------------vars-----------
WORK_DIR="$PWD" # ~/sing-box

gitRowUrl="https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main"

sbox_pkg_url="https://pkg.freebsd.org/FreeBSD:14:amd64/latest/All/sing-box-1.9.3.pkg" # https://pkgs.org/download/sing-box
sbox_pkg_fileName="sing-box-1.9.3.pkg"
sbox_bin_url="https://raw.githubusercontent.com/k0baya/sb-for-serv00/main/sing-box"
status_sbox=0 # 0.未下载；1.已安装未运行；2.运行
SING_BOX_PID=""
log_file="$WORK_DIR/data/sing-box.log"

proxy_uuid=""
proxy_uuid_file="$WORK_DIR/data/uuid.txt"
proxy_name="ray"
proxy_pwd="ray1qaz@WSX"

domain=""
domain_file="$WORK_DIR/data/domain.txt"
cert_choice=""
cert_path=""
cert_private_key_path=""
email=""

port_vmess=""
port_naive=""
port_hy2=""
port_reality=""

reality_server_name="addons.mozilla.org"
reality_short_id=""
reality_short_id_file="$WORK_DIR/data/short_id.txt"
reality_private_key=""
reality_private_key_file="$WORK_DIR/certs/$reality_server_name/private_key.txt"
reality_cert=""
reality_cert_file="$WORK_DIR/certs/$reality_server_name/certificate.txt"

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
        echo "节点需要一个域名，请提供一个域名或IP："
        read -p "请输入域名或IP(如demo.test.tk):" domain
    else
        say "域名: $domain"
    fi
    proxy_name=$domain

    # 端口
    if [ -z "$port_vmess" ]; then
        read -p "vmess端口(如8080，需防火墙放行该端口tcp流量):" port_vmess
    else
        say "vmess端口: $port_vmess"
    fi
    if [ -z "$port_reality" ]; then
        read -p "reality端口(如8088，需防火墙放行该端口tcp流量):" port_reality
    else
        say "reality端口: $port_reality"
    fi
}

check_status() {
    eval $invocation
    ps -axj | grep sing-box
    SING_BOX_PID=$(ps -axj | awk '$0 ~ "sing-box run" && $0 !~ "awk" {print $2}')

    say_verbose "sing-box PID: $SING_BOX_PID"

    if [ -n "$SING_BOX_PID" ];then
        err "\nsing-box正在运行"
        status_sbox="2"
    else
        touch ~/.bashrc && . ~/.bashrc
        if machine_has "sing-box";then
            err "\n已安装sing-box，但未运行"
            status_sbox="1"
        else
            err "\n当前未安装sing-box";
            status_sbox="0"
        fi
    fi
}

install_sbox_binary() {
    eval $invocation

    say "installing"

    download $sbox_pkg_url $WORK_DIR/$sbox_pkg_fileName
    tar -xvf $sbox_pkg_fileName

    touch ~/.bashrc
    echo "export PATH=\"\$PATH:$PWD/usr/local/bin\"" > ~/.bashrc
    chmod +x ~/.bashrc && . ~/.bashrc

    say "check sing-box"
    export PATH="$PATH:$PWD/usr/local/bin"
    sing-box version
}

install_sbox_bin(){
    eval $invocation
    say "installing"

    download $sbox_bin_url $WORK_DIR/sing-box
    chmod +x $WORK_DIR/sing-box

    touch ~/.bashrc
    echo "export PATH=\"\$PATH:$WORK_DIR\"" > ~/.bashrc
    chmod +x ~/.bashrc && . ~/.bashrc

    say "check sing-box"
    sing-box version
}

# 下载data
download_data_files() {
    eval $invocation

    mkdir -p ./data

    # config.json
    rm -rf $WORK_DIR/data/config.json
    download $gitRowUrl/sing-box/data/config_serv00.json $WORK_DIR/data/config.json

    # entry.sh
    rm -rf $WORK_DIR/data/entry.sh
    download $gitRowUrl/sing-box/data/entry.sh $WORK_DIR/data/entry.sh
}

# 配置
replace_configs() {
    eval $invocation

    # log
    sed 's|<log_file>|'"$log_file"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # domain
    sed 's|<domain>|'"$domain"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json
    touch $domain_file
    echo $domain > $domain_file

    # port
    sed 's|<port_vmess>|'"$port_vmess"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json
    sed 's|<port_reality>|'"$port_reality"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # certs
    sed 's|<cert_path>|'"$cert_path"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json
    sed 's|<cert_private_key_path>|'"$cert_private_key_path"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # mail
    sed 's|<email>|'"$email"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_uuid
    if [ ! -e "$proxy_uuid_file" ];then
        proxy_uuid=$(sing-box generate uuid)
        touch $proxy_uuid_file
        echo $proxy_uuid > $proxy_uuid_file
    fi
    proxy_uuid=$(cat $proxy_uuid_file)
    sed 's|<proxy_uuid>|'"$proxy_uuid"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_name
    sed 's|<proxy_name>|'"$proxy_name"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # proxy_pwd
    sed 's|<proxy_pwd>|'"$proxy_pwd"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # reality_server_name
    sed 's|<reality_server_name>|'"$reality_server_name"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # reality_private_key
    # 生成 Reality 公私钥，第一次安装的时候使用新生成的；添加协议的时，使用相应数组里的第一个非空值，如全空则像第一次安装那样使用新生成的
    mkdir -p $WORK_DIR/certs/$reality_server_name
    if [ ! -e "$reality_private_key_file" ];then
        say "reality密钥不存在，开始生成"
        keypair=$(sing-box generate reality-keypair)
        # 将私钥和证书分开
        reality_private_key=$(echo "$keypair" | grep -o "PrivateKey: .*" | awk -F': ' '{print $2}')
        reality_cert=$(echo "$keypair" | grep -o "PublicKey: .*" | awk -F': ' '{print $2}')
        echo $reality_private_key > $reality_private_key_file
        echo $reality_cert > $reality_cert_file
    fi
    reality_private_key=$(cat $reality_private_key_file)
    reality_cert=$(cat $reality_cert_file)
    echo "Private key: $reality_private_key"
    echo "Certificate: $reality_cert"
    sed 's|<reality_private_key>|'"$reality_private_key"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    # reality_short_id
    if [ ! -e "$reality_short_id_file" ];then
        say "reality short id不存在，开始生成"
        reality_short_id=$(sing-box generate rand 8 --hex)
        echo $reality_short_id > $reality_short_id_file
    fi
    reality_short_id=$(cat $reality_short_id_file)
    echo "reality short id: $reality_short_id"
    sed 's|<reality_short_id>|'"$reality_short_id"'|g' ./data/config.json >./data/config.json.new
    mv ./data/config.json.new ./data/config.json

    say "配置文件已生成"
}

# 运行
run_sbox() {
    eval $invocation

    chmod +x $WORK_DIR/data/entry.sh && $WORK_DIR/data/entry.sh $PWD/data true
}

# 获取订阅，根据当前配置
get_sub(){
    eval $invocation

    echo ""
    echo "==============================================="
    echo "Congratulations! 恭喜！"
    echo "创建并运行sing-box服务成功。"
    echo ""
    echo "请使用客户端尝试连接你的节点进行测试"

    local JSON=$(cat $WORK_DIR/data/config.json)
    echo ""
    echo ""
    echo ""
    echo "==============================================="
    err "【vmess节点】如下："
    port_vmess=$(jq -r '.inbounds[0].listen_port' <<< "$JSON")
    proxy_uuid=$(jq -r '.inbounds[0].users[0].uuid' <<< "$JSON")
    domain=$(cat $domain_file)
    sub_vmess="vmess://$(echo "{\"add\":\"$domain\",\"aid\":\"0\",\"host\":\"download.windowsupdate.com\",\"id\":\"$proxy_uuid\",\"net\":\"ws\",\"path\":\"/download\",\"port\":\"$port_vmess\",\"ps\":\"serv00-vmess\",\"scy\":\"auto\",\"sni\":\"\",\"tls\":\"\",\"type\":\"\",\"v\":\"2\"}" | base64 -w0 )"
    echo "订阅：$sub_vmess"
    echo "服务器：$domain"
    echo "端口：$port_vmess"
    echo "UUID：$proxy_uuid"
    echo "Alter Id：0"
    echo "传输：ws"
    echo "Path：/download"
    echo "Host：download.windowsupdate.com"
    echo ""
    echo ""
    echo ""
    echo "==============================================="
    err "【reality节点】如下："
    port_reality=$(jq -r '.inbounds[1].listen_port' <<< "$JSON")
    proxy_uuid=$(jq -r '.inbounds[1].users[0].uuid' <<< "$JSON")
    domain=$(cat $domain_file)
    reality_server_name=$(jq -r '.inbounds[1].tls.server_name' <<< "$JSON")
    reality_cert=$(cat $reality_cert_file)
    reality_short_id=$(cat $reality_short_id_file)
    sub_reality="vless://$proxy_uuid@$domain:$port_reality?security=reality&sni=$reality_server_name&pbk=$reality_cert&sid=$reality_short_id&type=tcp&flow=xtls-rprx-vision#serv00-reality"
    echo "订阅：$sub_reality"
    echo "服务器：$domain"
    echo "端口：$port_reality"
    echo "UUID：$proxy_uuid"
    echo "Flow：xtls-rprx-vision"
    echo "传输：tcp"
    echo "传输安全：tls"
    echo "TLS SNI：$reality_server_name"
    echo "Reality公钥：$reality_cert"
    echo "Reality Sid：$reality_short_id"
    echo "Enjoy it~"
    echo "==============================================="
}

uninstall(){
    eval $invocation

    rm -rf $WORK_DIR/*
    say_warning "完成"
}

stop_sbox(){
    eval $invocation

    kill -9 $SING_BOX_PID
    say "已关闭"
}

menu_setting() {
  eval $invocation
  
  check_status

  if [[ -n "$SING_BOX_PID" ]]; then
    OPTION[1]="1 .  查看sing-box运行状态"
    OPTION[2]="2 .  查看订阅"
    OPTION[3]="3 .  查看sing-box日志"
    OPTION[4]="4 .  关闭sing-box"
    OPTION[5]="5 .  卸载"

    ACTION[1]() { check_status; exit 0; }
    ACTION[2]() { get_sub; exit 0; }
    ACTION[3]() { tail -f $log_file; exit 0; }
    ACTION[4]() { stop_sbox; exit 0; }
    ACTION[5]() { uninstall; exit; }
  else
    OPTION[1]="1.  安装sing-box"
    OPTION[2]="2.  启动sing-box"
    OPTION[3]="3.  卸载"

    ACTION[1]() { init; exit; }
    ACTION[2]() { run_sbox; check_status; exit; }
    ACTION[3]() { uninstall; exit; }
  fi

  [ "${#OPTION[@]}" -ge '10' ] && OPTION[0]="0 .  Exit" || OPTION[0]="0.  Exit"
  ACTION[0]() { exit; }
}

menu() {
  eval $invocation

  say "==============================================="
  for ((b=1;b<=${#OPTION[*]};b++)); 
  do [ "$b" = "${#OPTION[*]}" ] && warning " ${OPTION[0]} " || warning " ${OPTION[b]} "; 
  done
  read -rp "Choose: " CHOOSE

  # 输入必须是数字且少于等于最大可选项
  if grep -qE "^[0-9]{1,2}$" <<< "$CHOOSE" && [ "$CHOOSE" -lt "${#OPTION[*]}" ]; then
    ACTION[$CHOOSE]
  else
    warning " Please enter the correct number [0-$((${#OPTION[*]}-1))] " && sleep 1 && menu
  fi
}

init(){
    #install_sbox_binary
    install_sbox_bin

    read_var_from_user

    download_data_files
    replace_configs

    run_sbox

    check_status
    get_sub
}

main() {
    menu_setting
    menu
}

main
