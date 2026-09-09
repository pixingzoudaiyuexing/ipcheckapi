# ipcheckapi

一个极简的 TCP 可达性探针，用于从不同服务器检测目标 IP:Port 是否可连接。

第一版只保留必要功能：

- 单个 Go 二进制，无运行时依赖
- `/health` 健康检查
- `/check` TCP 探测
- API Key 鉴权
- 返回 Open / Closed / Timeout / Error 和连接耗时
- 国内 / 国外两种安装模式
- 一键交互式管理菜单
- 国内安装默认优先使用 `https://git.hubproxy.top/` 下载 GitHub Release
- 支持 Linux amd64 / arm64
- systemd 自启动

## 一键管理菜单

### 国内服务器

```bash
bash <(curl -fsSL https://git.hubproxy.top/https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh)
```

### 国外服务器

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pixingzoudaiyuexing/ipcheckapi/main/install.sh)
```

执行后会显示：

```text
========================================
          ipcheckapi 一键管理菜单
========================================
 当前状态：未安装
----------------------------------------
 1. 安装 / 升级 国内探针
 2. 安装 / 升级 国外探针
 3. 查看运行状态
 4. 查看 API 信息
 5. 重启服务
 6. 卸载 ipcheckapi
 0. 退出
========================================
请选择 [0-6]:
```

国内探针模式会优先通过 `git.hubproxy.top` 下载 GitHub Release，镜像失败后再尝试 GitHub 官方地址。

国外探针模式直接从 GitHub 官方下载。

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
{"probe":"cn","status":"ok","version":"v0.1.2"}
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

## 菜单功能

### 安装 / 升级

菜单选择 `1` 或 `2` 即可。重复安装会自动更新二进制，并保留已有 API Key、监听地址和超时时间。

### 查看状态

菜单选择 `3`，会显示：

- 服务是否运行
- 是否开机自启
- 国内 / 国外探针模式
- 监听地址
- 检测超时

### 查看 API 信息

菜单选择 `4`，会直接显示：

- API Key
- 监听地址
- `/health` 调用示例
- `/check` 调用示例

### 重启

菜单选择 `5`。

### 卸载

菜单选择 `6`，确认后会停止服务并删除：

```text
/usr/local/bin/ipcheckapi
/etc/ipcheckapi/
/etc/systemd/system/ipcheckapi.service
```

卸载会同时删除 API Key 和配置文件。

## 配置

`/etc/ipcheckapi/config.env`：

```ini
API_KEY=自动生成的随机密钥
PROBE_NAME=cn
LISTEN_ADDR=0.0.0.0:18080
CHECK_TIMEOUT=5s
```

`CHECK_TIMEOUT` 最大允许 30 秒。

修改配置后可通过菜单重启服务，或者执行：

```bash
systemctl restart ipcheckapi
```

查看实时日志：

```bash
journalctl -u ipcheckapi -f
```

## 无交互参数模式

菜单是默认使用方式。为了方便后续自动化调用，也保留参数模式：

```bash
# 国内安装/升级
bash install.sh --cn

# 国外安装/升级
bash install.sh --global

# 查看状态
bash install.sh --status

# 查看 API 信息
bash install.sh --info

# 重启
bash install.sh --restart

# 卸载
bash install.sh --uninstall
```

## 本地构建

服务器无需安装 Go。构建由 GitHub Actions 完成并发布到 GitHub Releases。

手动构建示例：

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ipcheckapi-linux-amd64 .
```
