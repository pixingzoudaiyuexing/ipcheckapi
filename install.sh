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
ACTION="install"

usage() {
  cat <<'USAGE'
Usage:
  install.sh --cn
  install.sh --global
  install.sh --uninstall

Options:
  --cn         Install as China probe; GitHub downloads use git.hubproxy.top first.
  --global     Install as global probe; GitHub downloads use GitHub directly.
  --uninstall  Remove ipcheckapi service, binary, and configuration.
USAGE
}

log() { printf '[ipcheckapi] %s\n' "$*"; }
fail() { printf '[ipcheckapi] ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "please run as root"
}

fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 10 --retry 2 --retry-delay 1 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=15 -O "$dest" "$url"
  else
    fail "curl or wget is required"
  fi
}

fetch_with_fallback() {
  local official="$1" dest="$2"
  if [ "$MODE" = "cn" ]; then
    local proxy="${IPCHECKAPI_GITHUB_PROXY:-$DEFAULT_CN_PROXY}"
    local proxied="${proxy}${official}"
    log "download via China proxy"
    if fetch "$proxied" "$dest"; then
      return 0
    fi
    log "proxy failed, retry GitHub directly"
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
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
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
  log "uninstalled"
}

install_ipcheckapi() {
  require_root
  command -v systemctl >/dev/null 2>&1 || fail "systemd is required"
  command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

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
    grep "  ${asset}$" SHA256SUMS > SHA256SUMS.one || fail "checksum entry missing for ${asset}"
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

  log "installed successfully"
  log "mode: ${MODE}"
  log "listen: ${listen_addr}"
  log "api key: ${key}"
  log "health: curl http://SERVER_IP:${listen_addr##*:}/health"
  log "check:  curl -H 'X-API-Key: ${key}' 'http://SERVER_IP:${listen_addr##*:}/check?ip=1.1.1.1&port=443'"
}

for arg in "$@"; do
  case "$arg" in
    --cn) MODE="cn" ;;
    --global) MODE="global" ;;
    --uninstall) ACTION="uninstall" ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $arg" ;;
  esac
done

if [ "$ACTION" = "uninstall" ]; then
  uninstall_ipcheckapi
  exit 0
fi

[ -n "$MODE" ] || { usage; exit 1; }
install_ipcheckapi
