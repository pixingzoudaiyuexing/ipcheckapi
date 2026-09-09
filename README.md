# ipcheckapi

一个极简的 TCP 可达性探针，用于从不同服务器检测目标 IP:Port 是否可连接。

第一版只保留必要功能：

- 单个 Go 二进制，无运行时依赖
- `/health` 健康检查
- `/check` TCP 探测
- API Key 鉴权
- 返回 Open / Closed / Timeout / Error 和连接耗时
- 国内 / 国外两种一键安装模式
- 国内安装默认优先使用 `https://git.hubproxy.top/` 下载 GitHub Release
- 支持 Linux amd64 / arm64
- systemd 自启动

## 一键安装

### 国内服务器

```bash
bash <(curl -fsSL https://git.hubproxy.top/https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh) --cn
```

### 国外服务器

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh) --global
```

安装脚本会自动：

1. 判断 amd64 / arm64
2. 下载最新 GitHub Release 二进制
3. 校验 SHA256
4. 自动生成 API Key
5. 写入 systemd 服务
6. 启动并设置开机自启

默认监听：`0.0.0.0:18080`

配置文件：`/etc/ipcheckapi/config.env`

二进制：`/usr/local/bin/ipcheckapi`

## API

### 健康检查

```bash
curl http://服务器IP:18080/health
```

示例：

```json
{"probe":"cn","status":"ok","version":"v0.1.0"}
```

### TCP 检测

```bash
curl \
  -H "X-API-Key: 你的API_KEY" \
  "http://服务器IP:18080/check?ip=1.1.1.1&port=443"
```

成功连接示例：

```json
{
  "success": true,
  "probe": "cn",
  "target": "1.1.1.1",
  "port": 443,
  "tcp": {
    "reachable": true,
    "status": "open",
    "latency_ms": 23
  }
}
```

`tcp.status` 可能为：

- `open`：TCP 连接成功
- `closed`：目标明确拒绝连接
- `timeout`：连接超时
- `error`：其他连接错误

只接受 IP 地址，不接受域名，避免把探针变成任意 DNS / 代理工具。

## 配置

`/etc/ipcheckapi/config.env`：

```ini
API_KEY=自动生成的随机密钥
PROBE_NAME=cn
LISTEN_ADDR=0.0.0.0:18080
CHECK_TIMEOUT=5s
```

`CHECK_TIMEOUT` 最大允许 30 秒。

修改配置后：

```bash
systemctl restart ipcheckapi
```

查看状态：

```bash
systemctl status ipcheckapi
```

查看日志：

```bash
journalctl -u ipcheckapi -f
```

## 升级

重新执行对应的一键安装命令即可。已有 API Key、监听地址和超时时间会保留。

## 卸载

国外：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh) --uninstall
```

国内：

```bash
bash <(curl -fsSL https://git.hubproxy.top/https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh) --uninstall
```

## 本地构建

服务器无需安装 Go。构建由 GitHub Actions 完成并发布到 GitHub Releases。

手动构建示例：

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ipcheckapi-linux-amd64 .
```
