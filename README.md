# sing-box-installer

https://github.com/RayWangQvQ/sing-box-installer

基于`sing-box`和`docker`容器化搭建`naiveproxy`和`hysteria`的保姆级教程。

<!-- more -->

<!-- TOC depthFrom:2 -->

- [1. 大概介绍下](#1-大概介绍下)
    - [1.1. 关于sing-box](#11-关于sing-box)
    - [1.2. 关于naiveproxy](#12-关于naiveproxy)
    - [1.3. 关于hysteria](#13-关于hysteria)
    - [1.4. 关于sing-box的配置](#14-关于sing-box的配置)
- [2. 部署服务端](#2-部署服务端)
    - [2.1. 思路](#21-思路)
    - [2.2. 文件目录](#22-文件目录)
    - [2.3. docker compose](#23-docker-compose)
    - [2.4. entry.sh](#24-entrysh)
    - [2.5. config.json](#25-configjson)
    - [2.6. 运行](#26-运行)
- [3. 客户端](#3-客户端)
    - [3.1. 安卓-SagerNet](#31-安卓-sagernet)
        - [3.1.1. hysteria](#311-hysteria)
        - [3.1.2. naive](#312-naive)
    - [3.2. IOS-小火箭](#32-ios-小火箭)
    - [3.3. Win-V2RayN](#33-win-v2rayn)
        - [3.3.1. hysteria](#331-hysteria)
        - [3.3.2. naive](#332-naive)
- [4. FAQ](#4-faq)
    - [4.1. 一键安装脚本在哪](#41-一键安装脚本在哪)

<!-- /TOC -->

## 1. 大概介绍下

### 1.1. 关于sing-box

开源地址：[https://github.com/SagerNet/sing-box](https://github.com/SagerNet/sing-box)

`sing-box`是一个开源的**通用代理部署平台**，目的是在当今繁杂的各种代理协议之上，抽象出一个通用接口（interface），来统一各种协议的定义和配置。

做过软件开发的朋友应该都很熟悉一句话：没有什么问题是不能通过加一层来解决的，如果有，就再加一层。

简单理解，`sing-box`就起到这一层的作用，有了它，我可以使用同一套配置规则，部署多个不同的协议。

### 1.2. 关于naiveproxy

开源地址：
- 服务端：[https://github.com/klzgrad/forwardproxy](https://github.com/klzgrad/forwardproxy)
- 客户端：[https://github.com/klzgrad/naiveproxy](https://github.com/klzgrad/naiveproxy)

`naiveproxy`据说是当前最安全的协议**之一**，了解到它还是去年（2022年）10月份那次大规模封禁，据说除了`naiveproxy`幸免，其他协议均有死伤（包括`trojan`，`Xray`，`V2Ray TLS+Websocket`，`VLESS`和`gRPC`），详细可查看issue：[https://github.com/net4people/bbs/issues/129](https://github.com/net4people/bbs/issues/129)


![naiveproxy-bbs-survivor.png](https://blog.zai7lou.ml/static/img/8ff0b7ca66d71028ef059439aa8bafc4.naiveproxy-bbs-survivor.png)

为了解决墙的**主动探测**，它在服务端它使用自己优化过`Caddy`（`forwardproxy`），利用反代，将没有认证的流量转到一个正常的站点（伪装站点）。也就是，你用你的proxy客户端去访问，认证（用户名+密码）能通过，它就给你做代理；你不用客户端用正常浏览器（或用户名密码错误），只要认证不通过，它就给你反代到正常站点，瞒天过海。

关于TLS指纹问题的讨论，可以看下这个issus：[https://github.com/v2ray/v2ray-core/issues/2098](https://github.com/v2ray/v2ray-core/issues/2098)

在issue里顺便也了解到，`naiveproxy`的作者原来也是`trojan`最初的几个作者之一，后来`trojan`有些设计上的争议，包括一些优化的想法，由于主程没时间，无法得到实施，于是`naiveproxy`的作者就自己开了个项目来实现这些想法，这个项目就是现在的`naiveproxy`。

### 1.3. 关于hysteria

开源地址：[https://github.com/apernet/hysteria](https://github.com/apernet/hysteria)

`hysteria`的优势是快，**真的快**。同一台机器，我的测试结果是，比我之前的`xray`快了2到3倍（网上有人测出快了10倍）。

它是基于`quic`协议，走udp，跟它名字一样（歇斯底里），并发去请求扔包，所以快。

已知问题是qos，来自服务商的限制，当请求流量过大时，会被限速、断流。以前看有图比是嫌清晰度不够，用了`hysteria`可能要反过来主动去自己调低清晰度了。

关于安全性，目前墙对UDP的管控技术还没有TCP那么成熟，所以相对来说算比较安全。

### 1.4. 关于sing-box的配置

文档：[https://sing-box.sagernet.org/zh/configuration/](https://sing-box.sagernet.org/zh/configuration/)

部署`sing-box`的关键，就是编写它的配置文件。

`sing-box`抽象出一套配置规则，这套配置规则主要参考了`v2ray`，有DNS，有路由（router），有入站（inbound）和出站（outbound）。

如果之前使用过`v2ray`，对这些概念很熟悉，那么你可以很轻松切换到`sing-box`；
如果你是个新手，完全不了解这些概念，那么我建议你先去读读v2ray的文档（[https://www.v2ray.com](https://www.v2ray.com)）。

因为当前sing-box的文档还处于待完善阶段，只有对各配置字段的解释，并不会告诉你它是什么以及为什么要这么配。

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

### 2.2. 文件目录

需要在服务器构建如下目录结构：

```
sing-box
├── data
    ├── config.json
    ├── entry.sh
└── tls
└── docker-compose.yml
```

其中，`data/config.json`是`sing-box`的配置文件，所有节点配置信息都在里面。

`data/entry.sh`是容器启动脚本。

tls文件夹用于存储tls证书，`sing-box`可以自动颁发证书，你也可以使用自己现有的证书。如果自动颁发，就空文件夹就行，运行后该目录下会生成证书文件；如果要使用现有证书，可以将证书拷贝到当前文件夹下。

### 2.3. docker compose

`docker-compose.yml`参考内容如下：

```
version: '3'

services:
  sing-box:
    image: ghcr.io/sagernet/sing-box
    container_name: sing-box
    restart: unless-stopped
    network_mode: "host"
    # ports:
      # - 80:80
      # - 443:443
      # - 8090:8090
      # - 10080-10099:10080-10099/udp
    volumes:
      - ./data:/data
      - ./tls:/tls
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    entrypoint: ["/bin/bash", "/data/entry.sh"]
```

其中，网络模式使用了`network_mode: "host"`，直接使用了宿主机的网络环境，需要关闭宿主机的防火墙，命令如下：

```
# CentOS：
systemctl disable firewalld

# Debian/Ubuntu：
sudo ufw disable
```

如果`host模式`有问题，也可以切换到指定ports模式（注释掉`network_mode`，然后删掉下方prots的注释）

### 2.4. entry.sh

参考内容如下：

```
#!/bin/bash
set -e

configFilePath="/data/config.json"
logFilePath="/data/sing-box.json"

echo "entry"
sing-box version

# https://sing-box.sagernet.org/configuration/
echo -e "\nconfig:"
sing-box check -c $configFilePath || cat $configFilePath
sing-box format -c /data/config.json -w
cat $configFilePath

echo -e "\nstarting"
sing-box run -c $configFilePath
tail -f $logFilePath
```

会输出`sing-box`版本，检查并格式化配置文件，启动`sing-box`，并追踪日志。

### 2.5. config.json

最关键的配置文件，参考内容如下：

```
{
    "log": {
      "level": "trace",
      "output": "/data/sing-box.log",
      "timestamp": true
    },
    "dns": {
      "servers": [
        {
          "tag": "google-tls",
          "address": "local",
          "address_strategy": "prefer_ipv4",
          "strategy": "ipv4_only",
          "detour": "direct"
        },
        {
          "tag": "google-udp",
          "address": "8.8.8.8",
          "address_strategy": "prefer_ipv4",
          "strategy": "prefer_ipv4",
          "detour": "direct"
        }
      ],
      "strategy": "prefer_ipv4"
    },
    "inbounds": [
      {
        "type": "hysteria",
        "tag": "hysteria-in",
        "listen": "0.0.0.0",
        "listen_port": 10080,
        "domain_strategy": "ipv4_only",
        "up_mbps": 50,
        "down_mbps": 50,
        "obfs": "nicetofuckyou",
        "users": [
          {
            "name": "<proxy_name>",
            "auth_str": "<proxy_pwd>"
          }
        ],
        "tls": {
          "enabled": true,
          "server_name": "<domain>",
          "acme": {
            "domain": "<domain>",
            "data_directory": "/tls",
            "default_server_name": "<domain>",
            "email": "<email>"
          }
        }
      },
      {
        "type": "naive",
        "tag": "naive-in",
        "listen": "0.0.0.0",
        "listen_port": 8090,
        "domain_strategy": "ipv4_only",
        "users": [
          {
            "username": "<proxy_name>",
            "password": "<proxy_pwd>"
          }
        ],
        "network": "tcp",
        "tls": {
          "enabled": true,
          "server_name": "<domain>",
          "acme": {
            "domain": "<domain>",
            "data_directory": "/tls",
            "default_server_name": "<domain>",
            "email": "<email>"
          }
        }
      }
    ],
    "outbounds": [
      {
        "type": "direct",
        "tag": "direct"
      },
      {
        "type": "block",
        "tag": "block"
      },
      {
        "type": "dns",
        "tag": "dns-out"
      }
    ],
    "route": {
      "geoip": {
        "path": "/data/geoip.db",
        "download_url": "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db",
        "download_detour": "direct"
      },
      "geosite": {
        "path": "/data/geosite.db",
        "download_url": "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db",
        "download_detour": "direct"
      },
      "rules": [
        {
          "protocol": "dns",
          "outbound": "dns-out"
        },
        {
          "geosite": [
            "cn",
            "category-ads-all"
          ],
          "geoip": "cn",
          "outbound": "block"
        }
      ],
      "final": "direct",
      "auto_detect_interface": true
    }
  }
  
```

其中，有几处需要替换的地方：

- `<proxy_name>`替换为代理的用户名，自己取，如`Ray`
- `<proxy_pwd>`替换为代理的密码，自己取，如`1234@qwer`
- `<domain>`替换为域名
- `<email>`替换为邮箱
- `obfs`是`hysteria`混淆字符串，可以自定义

如上就配置了两个节点，一个**基于udp的10080端口**的`hysteria`节点，一个**基于tcp的8090端口**的`naive`节点。

**如果你的云上有安全策略，请确保这两个端口都开放了。**

证书的话，如果tls目录下没有现有证书，会自动颁发。

其他配置可以查阅官方文档了解。

### 2.6. 运行

在`docker-compose.yml`同级目录下，执行：

```
docker compose up -d
```

等待容器启动。

如果一切正常，就是启动成功，可以去使用自己的客户端连接了。（就是这么简单）

*其他参考指令：*

```
# 查看当前运行中的容器
docker ps

# 查看容器启动日志
docker logs sing-box

# 追踪容器运行日志（使用Ctrl C退出追踪）
docker logs -f sing-box

# 进入容器
docker exec -it sing-box bash
```

## 3. 客户端

### 3.1. 安卓-SagerNet

#### 3.1.1. hysteria

![sing-box-client-sagernet-hysteria.jpg](https://blog.zai7lou.ml/static/img/87514a662f253ae2a12d2e2b98441ae5.sing-box-client-sagernet-hysteria.jpg)

其中：

- `混淆密码`是配置中的`obfs`
- `认证荷载`是配置中的`auth_str`

#### 3.1.2. naive

![sing-box-client-sagernet-naive.jpg](https://blog.zai7lou.ml/static/img/a65503bf1d71255a3ff3d0eebff9435f.sing-box-client-sagernet-naive.jpg)

其中，`密码`是配置中的`password`

### 3.2. IOS-小火箭
todo

### 3.3. Win-V2RayN

#### 3.3.1. hysteria


![hysteria-v2rayn-add.png](https://blog.zai7lou.ml/static/img/ef39f4212a82a7c5dd5637be568fc63d.hysteria-v2rayn-add.png)

配置文件内容如下：

```
{
  "server": "sample.zai7lou.ml:10080",
  "obfs": "Ray",
  "auth_str": "1234@qwer",
  "up_mbps": 10,
  "down_mbps": 50,
  "socks5": {
    "listen": "127.0.0.1:10808"
  },
  "http": {
    "listen": "127.0.0.1:10809"
  }
}
```

#### 3.3.2. naive


![naive-v2rayn-add.png](https://blog.zai7lou.ml/static/img/6f5d33a2e5a7129118687948251ac82e.naive-v2rayn-add.png)

配置文件内容如下：

```
{
  "listen": "socks://127.0.0.1:10808",
  "proxy": "https://Ray:1234@qwer@sample.zai7lou.ml:8090"
}

```

## 4. FAQ

### 4.1. 一键安装脚本在哪

没有写。

`sing-box`的主要工作都在配置`config.json`上，但是用`shell`编辑更新`json`有点鸡肋。

而且当前`sing-box`处于很活跃的开发阶段，我猜测，过不了多久，就会有类似`x-ui`的web管理系统出来。用这种form表单来配置，才是最优方案。

所以，综合考虑下来，当前还是直接编辑json文件来的简单。