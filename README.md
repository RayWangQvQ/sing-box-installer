# sing-box-installer

[English](./README.MD) | [中文](./README_zh.MD)

https://github.com/RayWangQvQ/sing-box-installer

A step-by-step "nanny-level" tutorial for deploying `reality`, `naiveproxy` and `hysteria2` with sing-box by containerized docker or binary packages.

<!-- more -->

<!-- TOC depthFrom:2 -->

- [1. Introduction](#1-introduction)
    - [1.1. About sing-box](#11-about-sing-box)
    - [1.2. About naiveproxy](#12-about-naiveproxy)
    - [1.3. About hysteria](#13-about-hysteria)
    - [1.4. About sing-box configuration](#14-about-sing-box-configuration)
- [2. Server Deployment](#2-server-deployment)
    - [2.1. Approach](#21-approach)
    - [2.2. One-click script deployment](#22-one-click-script-deployment)
    - [2.3. Manual deployment](#23-manual-deployment)
- [3. Other Protocols](#3-other-protocols)
- [4. Client](#4-client)
    - [4.1. vmess](#41-vmess)
    - [4.2. hysteria2](#42-hysteria2)
    - [4.3. reality](#43-reality)
- [5. Acknowledgments](#5-acknowledgments)

<!-- /TOC -->

You can directly execute the following codes if you want to skip reading details:

Docker-based, requires root:

```
# get permission
sudo -i

# create a dir
mkdir -p ./sing-box && cd ./sing-box

# install
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install.sh)
```

serv00 version:

```
# create a dir
mkdir -p ./sing-box && cd ./sing-box
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install-serv00.sh)
```

## 1. Introduction

### 1.1. About sing-box

Open source repository: [https://github.com/SagerNet/sing-box](https://github.com/SagerNet/sing-box)

`sing-box` is an open-source **universal proxy deployment platform** that supports most protocols. With it, I can use the same set of configuration rules to deploy multiple different protocols.

### 1.2. About naiveproxy

Open source repositories:
- Server-side: [https://github.com/klzgrad/forwardproxy](https://github.com/klzgrad/forwardproxy)
- Client-side: [https://github.com/klzgrad/naiveproxy](https://github.com/klzgrad/naiveproxy)

It is said to be **one of** the most secure protocols currently available.

### 1.3. About hysteria

Open source repository: [https://github.com/apernet/hysteria](https://github.com/apernet/hysteria)

The advantage of `hysteria` is speed. Based on the `quic` protocol, it uses UDP and, like its name suggests (hysteria), makes concurrent requests and drops packets, which makes it fast.

A known issue is QoS - limitations from service providers. When request traffic is too high, it will be throttled or disconnected. Previously, people complained about insufficient video quality clarity, but with `hysteria`, you might have to proactively lower the video quality yourself.

Regarding security, the current firewall control technology for UDP is not as mature as for TCP, so it's relatively safer.

### 1.4. About sing-box configuration

Documentation: [https://sing-box.sagernet.org/zh/configuration/](https://sing-box.sagernet.org/zh/configuration/)

The key to deploying `sing-box` is writing its configuration file.

`sing-box` abstracts a set of configuration rules, including DNS, routing (router), inbound and outbound connections.

If you've used `v2ray` before and are familiar with these concepts, you can easily switch to `sing-box`.

## 2. Server Deployment

### 2.1. Approach

I personally recommend using `docker` containerized deployment. Containerization has many benefits, which I won't elaborate on here.

The following will be based on the official `docker` image of `sing-box`, using `docker-compose` for container construction.

Official image repository: [https://github.com/orgs/SagerNet/packages?repo_name=sing-box](https://github.com/orgs/SagerNet/packages?repo_name=sing-box)

If your machine doesn't have docker installed, please install docker first with the following commands:

```
curl -sSL https://get.docker.com/ | sh
systemctl start docker
systemctl enable docker
```

Then run the official sing-box image based on docker containers. We only need to configure the config.json configuration file.

Below are two modes: one-click script deployment and manual deployment. Choose either one.

### 2.2. One-click script deployment

```
# get permission
sudo -i

# create a dir
mkdir -p ./sing-box && cd ./sing-box

# install
bash <(curl -sSL https://raw.githubusercontent.com/RayWangQvQ/sing-box-installer/main/install.sh)
```

After running, you'll be prompted to input parameters:

- Domain: You need to configure DNS resolution to point to your server IP
- Email: Used for certificate application (will automatically apply and renew)
- Proxy UUID: Set by yourself, you can search for any website to generate one
- Proxy username: Set by yourself
- Proxy password: Set by yourself

### 2.3. Manual deployment

[Tutorial](DIY.md)

## 3. Other Protocols

Supports all protocols that sing-box supports. Simply modify config.json yourself.

## 4. Client

The following examples use clash configuration.

### 4.1. vmess

```json
{
    "name": "your-vmess-name",
    "type": "vmess",
    "port": ,
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
    "server": "",
    "uuid": ""
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
    "password": "",
    "port": ,
    "server": "",
    "sni": ""
}
```

### 4.3. reality

```json
{
    "type": "vless",
    "name": "your-reality-name",
    "server": "",
    "port": ,
    "uuid": "",
    "tls": true,
    "skip-cert-verify": false,
    "reality-opts": {
        "public-key": "",
        "short-id": ""
    },
    "network": "tcp",
    "servername": "swdist.apple.com"
}
```

## 5. Acknowledgments

Thanks to [ZMTO](https://console.zmto.com/?affid=1565) for sponsoring the VPS for scripts testing work.

![ZMTO](https://console.zmto.com/templates/2019/dist/images/logo_white.svg)

Thanks to [DartNode](https://dartnode.com/) for sponsoring the VPS for scripts testing work.

[![Powered by DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")
