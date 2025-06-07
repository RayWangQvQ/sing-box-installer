# sing-box-installer

https://github.com/RayWangQvQ/sing-box-installer

基于`sing-box`和`docker`容器化搭建`vmess`、`naiveproxy`和`hysteria2`的保姆级教程。

<!-- more -->

<!-- TOC depthFrom:2 -->

- [1. 简介](#1-简介)
    - [1.1. 关于sing-box](#11-关于sing-box)
    - [1.2. 关于naiveproxy](#12-关于naiveproxy)
    - [1.3. 关于hysteria](#13-关于hysteria)
    - [1.4. 关于sing-box的配置](#14-关于sing-box的配置)
- [2. 部署服务端](#2-部署服务端)
    - [2.1. 思路](#21-思路)
    - [2.2. 一键脚本部署](#22-一键脚本部署)
    - [2.3. 手动部署](#23-手动部署)
- [3. 其他协议](#3-其他协议)
- [4. 客户端](#4-客户端)
    - [4.1. vmess](#41-vmess)
    - [4.2. hysteria2](#42-hysteria2)
    - [4.3. reality](#43-reality)
- [5. 感谢](#5-感谢)

<!-- /TOC -->

省流，可以直接执行：

基于docker，需要root：
```
# get permission
sudo -i

# create a dir
mkdir -p ./sing-box && cd ./sing-box

# install
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install.sh)
```

serv00版：
```
# create a dir
mkdir -p ./sing-box && cd ./sing-box
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install-serv00.sh)
```

## 1. 简介

### 1.1. 关于sing-box

开源地址：[https://github.com/SagerNet/sing-box](https://github.com/SagerNet/sing-box)

`sing-box`是一个开源的**通用代理部署平台**，支持大部分协议，有了它，我可以使用同一套配置规则，部署多个不同的协议。

### 1.2. 关于naiveproxy

开源地址：
- 服务端：[https://github.com/klzgrad/forwardproxy](https://github.com/klzgrad/forwardproxy)
- 客户端：[https://github.com/klzgrad/naiveproxy](https://github.com/klzgrad/naiveproxy)

据说是当前最安全的协议**之一**

### 1.3. 关于hysteria

开源地址：[https://github.com/apernet/hysteria](https://github.com/apernet/hysteria)

`hysteria`的优势是快，基于`quic`协议，走udp，跟它名字一样（歇斯底里），并发去请求扔包，所以快。

已知问题是qos，来自服务商的限制，当请求流量过大时，会被限速、断流。以前看有图比是嫌清晰度不够，用了`hysteria`可能要反过来主动去自己调低清晰度了。

关于安全性，目前墙对UDP的管控技术还没有TCP那么成熟，所以相对来说算比较安全。

### 1.4. 关于sing-box的配置

文档：[https://sing-box.sagernet.org/zh/configuration/](https://sing-box.sagernet.org/zh/configuration/)

部署`sing-box`的关键，就是编写它的配置文件。

`sing-box`抽象出一套配置规则，有DNS，有路由（router），有入站（inbound）和出站（outbound）。

如果之前使用过`v2ray`，对这些概念很熟悉，那么你可以很轻松切换到`sing-box`；

## 2. 部署服务端

### 2.1. 思路

我个人推荐使用`docker`容器化部署，容器化有很多好处，这里就不多说了。

下面会基于`sing-box`的官方`docker`镜像，使用`docker-compose`进行容器构建。

官方镜像地址：[https://github.com/orgs/SagerNet/packages?repo_name=sing-box](https://github.com/orgs/SagerNet/packages?repo_name=sing-box)

如果你的机器没有装过docker，请先安装docker，安装指令：

```
curl -sSL https://get.docker.com/ | sh
systemctl start docker
systemctl enable docker
```

然后基于docker容器run sing-box的官方镜像，我们只需要配置好配置文件config.json即可。

下面有两种模式：一键脚本部署和手动部署，任选其一即可。

### 2.2. 一键脚本部署

```
# get permission
sudo -i

# create a dir
mkdir -p ./sing-box && cd ./sing-box

# install
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install.sh)
```

运行后会让输入参数：

- 域名：需要自己DNS解析好到自己的服务器ip
- 邮箱：用来申请证书的（会自动申请并更新）
- proxy uuid: 自己设置，可以随便搜个网站生成
- proxy用户名：自己设置
- proxy密码：自己设置

### 2.3. 手动部署

[教程](DIY.md)

## 3. 其他协议

支持所有sing-box支持的协议，自行修改config.json即可。

## 4. 客户端

以下以clash配置为例。

### 4.1. vmess

```json
{
    "name": "your-vmess-name",
    "type": "vmess",
    "port": <port>,
    "udp": true,
    "alterId": 0,
    "cipher": "auto",
    "network": "ws",
    "skip-cert-verify": true,
    "ws-opts": {
        "path": "/download",
        "headers": {
            "Host": "download.windowsupdate.com"
        }
    },
    "server": "<ip>",
    "uuid": "<uuid>"
}
```

### 4.2. hysteria2

```json
{
    "name": "your-hy-name",
    "type": "hysteria2",
    "alpn": [
        "h3"
    ],
    "up": "50 Mbps",
    "down": "50 Mbps",
    "password": "<pwd>",
    "port": <port>,
    "server": "<ip>",
    "sni": "<domain>"
}
```

### 4.3. reality

```json
{
    "type": "vless",
    "name": "your-reality-name",
    "server": "<ip>",
    "port": <port>,
    "uuid": "<uuid>",
    "tls": true,
    "skip-cert-verify": false,
    "reality-opts": {
        "public-key": "<pub-key>",
        "short-id": "<short-id>"
    },
    "network": "tcp",
    "servername": "swdist.apple.com"
}
```

## 5. 感谢

Thanks to [ZMTO](https://console.zmto.com/?affid=1565) for sponsoring the VPS for scripts testing work.

![ZMTO](https://console.zmto.com/templates/2019/dist/images/logo_white.svg)

Thanks to [DartNode](https://dartnode.com/) for sponsoring the VPS for scripts testing work.

[![Powered by DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")
