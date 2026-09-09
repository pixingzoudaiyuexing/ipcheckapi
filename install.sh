#!/usr/bin/env bash
set -euo pipefail

REPO="pixingzoudaiyuexing/ipcheckapi"
BIN_PATH="/usr/local/bin/ipcheckapi"
CONFIG_DIR="/etc/ipcheckapi"
CONFIG_FILE="${CONFIG_DIR}/config.env"
SERVICE_FILE="/etc/systemd/system/ipcheckapi.service"
DEFAULT_PORT="18080"
DEFAULT_TIMEOUT="5s"
DEFAULT_CN_PROXY="https://git.hubproxy.top/"

MODE=""
ACTION=""

usage() {
  cat <<'USAGE'
用法：
  install.sh                 打开一键管理菜单
  install.sh --cn            安装/升级为国内探针
  install.sh --global        安装/升级为国外探针
  install.sh --status        查看运行状态
  install.sh --info          查看 API 信息
  install.sh --restart       重启服务
  install.sh --uninstall     卸载

说明：
  国内模式优先通过 git.hubproxy.top 下载 GitHub Release，失败后回退 GitHub 官方。
  国外模式直接从 GitHub 官方下载。
USAGE
}

log() { printf '[ipcheckapi] %s\n' "$*"; }
fail() { printf '[ipcheckapi] 错误: %s\n' "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "请使用 root 用户运行"
}

fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 10 --retry 2 --retry-delay 1 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=15 -O "$dest" "$url"
  else
    fail "系统需要 curl 或 wget"
  fi
}

fetch_with_fallback() {
  local official="$1" dest="$2"
  if [ "$MODE" = "cn" ]; then
    local proxy="${IPCHECKAPI_GITHUB_PROXY:-$DEFAULT_CN_PROXY}"
    local proxied="${proxy}${official}"
    log "正在通过国内 GitHub 镜像下载"
    if fetch "$proxied" "$dest"; then
      return 0
    fi
    log "镜像下载失败，尝试 GitHub 官方地址"
  fi
  fetch "$official" "$dest"
}

read_existing_value() {
  local key="$1"
  [ -f "$CONFIG_FILE" ] || return 0
  sed -n "s/^${key}=//p" "$CONFIG_FILE" | tail -n 1
}

generate_key() {
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) fail "暂不支持此架构: $(uname -m)" ;;
  esac
}

is_installed() {
  [ -x "$BIN_PATH" ] && [ -f "$SERVICE_FILE" ]
}

show_status() {
  require_root
  if ! is_installed; then
    printf '\n未安装 ipcheckapi。\n'
    return 0
  fi

  local active enabled mode listen timeout
  active="$(systemctl is-active ipcheckapi 2>/dev/null || true)"
  enabled="$(systemctl is-enabled ipcheckapi 2>/dev/null || true)"
  mode="$(read_existing_value PROBE_NAME)"
  listen="$(read_existing_value LISTEN_ADDR)"
  timeout="$(read_existing_value CHECK_TIMEOUT)"

  printf '\n========== ipcheckapi 状态 ==========\n'
  printf '服务状态 : %s\n' "${active:-unknown}"
  printf '开机自启 : %s\n' "${enabled:-unknown}"
  printf '探针模式 : %s\n' "${mode:-unknown}"
  printf '监听地址 : %s\n' "${listen:-unknown}"
  printf '检测超时 : %s\n' "${timeout:-unknown}"
  printf '=====================================\n'
}

show_api_info() {
  require_root
  if [ ! -f "$CONFIG_FILE" ]; then
    printf '\n未安装 ipcheckapi 或配置文件不存在。\n'
    return 0
  fi

  local key mode listen port
  key="$(read_existing_value API_KEY)"
  mode="$(read_existing_value PROBE_NAME)"
  listen="$(read_existing_value LISTEN_ADDR)"
  port="${listen##*:}"

  printf '\n========== API 信息 ==========\n'
  printf '探针模式 : %s\n' "${mode:-unknown}"
  printf '监听地址 : %s\n' "${listen:-unknown}"
  printf 'API Key  : %s\n' "${key:-unknown}"
  printf '\n健康检查：\n'
  printf 'curl http://服务器IP:%s/health\n' "$port"
  printf '\nTCP 检测示例：\n'
  printf "curl -H 'X-API-Key: %s' 'http://服务器IP:%s/check?ip=1.1.1.1&port=443'\n" "$key" "$port"
  printf '==============================\n'
}

restart_ipcheckapi() {
  require_root
  is_installed || fail "ipcheckapi 尚未安装"
  systemctl restart ipcheckapi
  log "服务已重启"
  show_status
}

uninstall_ipcheckapi() {
  require_root
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now ipcheckapi >/dev/null 2>&1 || true
  fi
  rm -f "$SERVICE_FILE" "$BIN_PATH"
  rm -rf "$CONFIG_DIR"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
  fi
  log "卸载完成"
}

install_ipcheckapi() {
  require_root
  command -v systemctl >/dev/null 2>&1 || fail "系统需要 systemd"
  command -v sha256sum >/dev/null 2>&1 || fail "系统需要 sha256sum"

  local arch asset base tmpdir key listen_addr timeout
  arch="$(detect_arch)"
  asset="ipcheckapi-linux-${arch}"
  base="https://github.com/${REPO}/releases/latest/download"
  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" EXIT

  fetch_with_fallback "${base}/${asset}" "${tmpdir}/${asset}"
  fetch_with_fallback "${base}/SHA256SUMS" "${tmpdir}/SHA256SUMS"

  (
    cd "$tmpdir"
    grep "  ${asset}$" SHA256SUMS > SHA256SUMS.one || fail "SHA256SUMS 中没有找到 ${asset}"
    sha256sum -c SHA256SUMS.one
  )

  install -m 0755 "${tmpdir}/${asset}" "$BIN_PATH"
  mkdir -p "$CONFIG_DIR"

  key="$(read_existing_value API_KEY)"
  [ -n "$key" ] || key="$(generate_key)"
  listen_addr="$(read_existing_value LISTEN_ADDR)"
  [ -n "$listen_addr" ] || listen_addr="0.0.0.0:${DEFAULT_PORT}"
  timeout="$(read_existing_value CHECK_TIMEOUT)"
  [ -n "$timeout" ] || timeout="$DEFAULT_TIMEOUT"

  cat > "$CONFIG_FILE" <<EOF_CONFIG
API_KEY=${key}
PROBE_NAME=${MODE}
LISTEN_ADDR=${listen_addr}
CHECK_TIMEOUT=${timeout}
EOF_CONFIG
  chmod 600 "$CONFIG_FILE"

  cat > "$SERVICE_FILE" <<'EOF_SERVICE'
[Unit]
Description=ipcheckapi lightweight TCP probe
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ipcheckapi
EnvironmentFile=/etc/ipcheckapi/config.env
Restart=on-failure
RestartSec=2s
DynamicUser=yes
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  systemctl daemon-reload
  systemctl enable --now ipcheckapi

  rm -rf "$tmpdir"
  trap - EXIT

  printf '\n'
  log "安装/升级完成"
  show_api_info
}

pause_menu() {
  printf '\n按回车键返回菜单...'
  read -r _ || true
}

menu_loop() {
  require_root

  while true; do
    local active="未安装"
    if is_installed; then
      active="$(systemctl is-active ipcheckapi 2>/dev/null || true)"
    fi

    printf '\n'
    printf '========================================\n'
    printf '          ipcheckapi 一键管理菜单        \n'
    printf '========================================\n'
    printf ' 当前状态：%s\n' "$active"
    printf '----------------------------------------\n'
    printf ' 1. 安装 / 升级 国内探针\n'
    printf ' 2. 安装 / 升级 国外探针\n'
    printf ' 3. 查看运行状态\n'
    printf ' 4. 查看 API 信息\n'
    printf ' 5. 重启服务\n'
    printf ' 6. 卸载 ipcheckapi\n'
    printf ' 0. 退出\n'
    printf '========================================\n'
    printf '请选择 [0-6]: '

    local choice
    read -r choice || exit 0
    case "$choice" in
      1)
        MODE="cn"
        install_ipcheckapi
        pause_menu
        ;;
      2)
        MODE="global"
        install_ipcheckapi
        pause_menu
        ;;
      3)
        show_status
        pause_menu
        ;;
      4)
        show_api_info
        pause_menu
        ;;
      5)
        if is_installed; then
          restart_ipcheckapi
        else
          printf '\nipcheckapi 尚未安装。\n'
        fi
        pause_menu
        ;;
      6)
        if ! is_installed && [ ! -d "$CONFIG_DIR" ]; then
          printf '\nipcheckapi 尚未安装。\n'
        else
          printf '确认卸载并删除 API Key 与配置？[y/N]: '
          local confirm
          read -r confirm || true
          case "$confirm" in
            y|Y|yes|YES|Yes) uninstall_ipcheckapi ;;
            *) printf '已取消卸载。\n' ;;
          esac
        fi
        pause_menu
        ;;
      0)
        printf '已退出。\n'
        exit 0
        ;;
      *)
        printf '\n无效选项，请输入 0-6。\n'
        pause_menu
        ;;
    esac
  done
}

if [ "$#" -eq 0 ]; then
  menu_loop
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --cn) MODE="cn"; ACTION="install" ;;
    --global) MODE="global"; ACTION="install" ;;
    --status) ACTION="status" ;;
    --info) ACTION="info" ;;
    --restart) ACTION="restart" ;;
    --uninstall) ACTION="uninstall" ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知参数: $arg" ;;
  esac
done

case "$ACTION" in
  install)
    [ -n "$MODE" ] || fail "安装时需要 --cn 或 --global"
    install_ipcheckapi
    ;;
  status) show_status ;;
  info) show_api_info ;;
  restart) restart_ipcheckapi ;;
  uninstall) uninstall_ipcheckapi ;;
  *) usage; exit 1 ;;
esac
