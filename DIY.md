# DIY

<!-- TOC depthFrom:2 -->

- [1. 文件目录](#1-文件目录)
- [2. docker compose](#2-docker-compose)
- [3. entry.sh](#3-entrysh)
- [4. config.json](#4-configjson)
- [5. 运行](#5-运行)

<!-- /TOC -->

## 1. 文件目录

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

## 2. docker compose

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

## 3. entry.sh

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

## 4. config.json

最关键的配置文件，参考内容如下：

```
{
    "log": {
      "level": "trace",
      "output": "/data/sing-box.log",
      "timestamp": true
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

## 5. 运行

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
