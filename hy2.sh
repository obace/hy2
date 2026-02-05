#!/usr/bin/env bash
set -euo pipefail

# 安装 hy2 管理脚本到 /usr/local/bin/hy2-manager
# 并创建快捷命令 /usr/local/bin/hy2

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 执行：sudo bash $0"
  exit 1
fi

cat > /usr/local/bin/hy2-manager <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="bing.com"
CERT_DIR="/etc/hysteria"
CONFIG_FILE="${CERT_DIR}/config.yaml"
CERT_FILE="${CERT_DIR}/server.crt"
KEY_FILE="${CERT_DIR}/server.key"
STATE_FILE="${CERT_DIR}/server-meta.env"
SERVICE_NAME="hysteria-server"

detect_service_name() {
  if systemctl list-unit-files | grep -q "^hysteria-server.service"; then
    SERVICE_NAME="hysteria-server"
  elif systemctl list-unit-files | grep -q "^hysteria.service"; then
    SERVICE_NAME="hysteria"
  else
    SERVICE_NAME="hysteria-server"
  fi
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 运行：sudo $0 $*"
    exit 1
  fi
}

get_public_ip() {
  local ip
  ip=$(curl -4 -fsSL --max-time 8 https://api.ipify.org || true)
  [[ -z "${ip}" ]] && ip=$(curl -4 -fsSL --max-time 8 https://ifconfig.me || true)
  [[ -z "${ip}" ]] && ip=$(hostname -I | awk '{print $1}' || true)
  echo "${ip:-YOUR_SERVER_IP}"
}

gen_port() { shuf -i 10000-65535 -n 1; }
gen_pass() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20; }

install_deps() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl openssl ca-certificates coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl openssl ca-certificates coreutils
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl openssl ca-certificates coreutils
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl openssl ca-certificates coreutils
  else
    echo "未识别包管理器，请手动安装 curl openssl 后重试。"
    exit 1
  fi
}

open_firewall_udp() {
  local port="$1"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${port}/udp" >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${port}/udp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || true
  fi
}

close_firewall_udp() {
  local port="$1"
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "${port}/udp" >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -D INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || true
  fi
}

save_meta() {
  local port="$1" pass="$2"
  mkdir -p "${CERT_DIR}"
  cat > "${STATE_FILE}" <<EOM
PORT=${port}
PASSWORD=${pass}
DOMAIN=${DOMAIN}
EOM
  chmod 600 "${STATE_FILE}"
}

load_meta() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  else
    PORT=""
    PASSWORD=""
  fi
}

write_config() {
  local port="$1" pass="$2"
  mkdir -p "${CERT_DIR}"
  cat > "${CONFIG_FILE}" <<EOM
listen: :${port}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

auth:
  type: password
  password: ${pass}

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOM
  chmod 600 "${CONFIG_FILE}"
}

cert_fingerprint() {
  if [[ -f "${CERT_FILE}" ]]; then
    openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 | cut -d= -f2
  else
    echo "N/A"
  fi
}

print_info() {
  detect_service_name
  load_meta
  local ip fp
  ip="$(get_public_ip)"
  fp="$(cert_fingerprint)"

  echo "============= Hysteria2 信息 ============="
  echo "服务名: ${SERVICE_NAME}"
  echo "服务器IP: ${ip}"
  echo "端口(UDP): ${PORT:-未知}"
  echo "密码: ${PASSWORD:-未知}"
  echo "SNI/域名: ${DOMAIN}"
  echo "证书SHA256指纹: ${fp}"
  echo
  if [[ -n "${PORT:-}" && -n "${PASSWORD:-}" ]]; then
    echo "客户端 URI："
    echo "hysteria2://${PASSWORD}@${ip}:${PORT}/?sni=${DOMAIN}&insecure=1"
  fi
  echo "=========================================="
}

do_install() {
  require_root
  detect_service_name
  local port pass
  port="$(gen_port)"
  pass="$(gen_pass)"

  echo "==> 安装依赖..."
  install_deps

  echo "==> 安装 Hysteria2..."
  bash <(curl -fsSL https://get.hy2.sh/)

  detect_service_name

  echo "==> 生成自签证书（CN=${DOMAIN}）..."
  mkdir -p "${CERT_DIR}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -days 36500 \
    -subj "/CN=${DOMAIN}" >/dev/null 2>&1
  chmod 600 "${KEY_FILE}"
  chmod 644 "${CERT_FILE}"

  echo "==> 写入配置..."
  write_config "${port}" "${pass}"
  save_meta "${port}" "${pass}"

  echo "==> 启动服务..."
  systemctl daemon-reload || true
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE_NAME}"

  echo "==> 放行 UDP 端口 ${port}..."
  open_firewall_udp "${port}"

  echo "安装完成。"
  print_info
}

do_status() {
  require_root
  detect_service_name
  systemctl status "${SERVICE_NAME}" --no-pager -l
}

do_restart() {
  require_root
  detect_service_name
  systemctl restart "${SERVICE_NAME}"
  echo "已重启 ${SERVICE_NAME}"
  systemctl is-active "${SERVICE_NAME}" >/dev/null && echo "服务状态：active"
}

do_change_port() {
  require_root
  detect_service_name
  load_meta
  [[ -f "${CONFIG_FILE}" ]] || { echo "未安装，请先执行 install"; exit 1; }

  local old_port new_port pass
  old_port="${PORT:-}"
  pass="${PASSWORD:-$(gen_pass)}"
  new_port="$(gen_port)"

  write_config "${new_port}" "${pass}"
  save_meta "${new_port}" "${pass}"

  systemctl restart "${SERVICE_NAME}"
  open_firewall_udp "${new_port}"
  [[ -n "${old_port}" ]] && close_firewall_udp "${old_port}"

  echo "端口已更换：${old_port:-未知} -> ${new_port}"
  print_info
}

do_change_pass() {
  require_root
  detect_service_name
  load_meta
  [[ -f "${CONFIG_FILE}" ]] || { echo "未安装，请先执行 install"; exit 1; }

  local port new_pass
  port="${PORT:-$(gen_port)}"
  new_pass="$(gen_pass)"

  write_config "${port}" "${new_pass}"
  save_meta "${port}" "${new_pass}"
  systemctl restart "${SERVICE_NAME}"

  echo "密码已更新。"
  print_info
}

do_uninstall() {
  require_root
  detect_service_name
  load_meta

  systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true

  if command -v hysteria >/dev/null 2>&1; then
    hysteria uninstall server >/dev/null 2>&1 || true
  fi

  if [[ -n "${PORT:-}" ]]; then
    close_firewall_udp "${PORT}"
  fi

  rm -rf "${CERT_DIR}"
  echo "Hysteria2 已卸载并清理配置。"
}

menu() {
  while true; do
    echo
    echo "========== hy2 管理菜单 =========="
    echo "1) 安装 Hysteria2"
    echo "2) 查看连接信息"
    echo "3) 查看服务状态"
    echo "4) 重启服务"
    echo "5) 换随机五位端口"
    echo "6) 换随机密码"
    echo "7) 卸载"
    echo "0) 退出"
    echo "=================================="
    read -rp "请选择 [0-7]: " choice

    case "${choice}" in
      1) do_install ;;
      2) print_info ;;
      3) do_status ;;
      4) do_restart ;;
      5) do_change_port ;;
      6) do_change_pass ;;
      7) do_uninstall ;;
      0) exit 0 ;;
      *) echo "无效选项，请重试。" ;;
    esac
  done
}

usage() {
  cat <<EOM
用法:
  hy2-manager install
  hy2-manager info
  hy2-manager status
  hy2-manager restart
  hy2-manager change-port
  hy2-manager change-pass
  hy2-manager uninstall
  hy2-manager menu
EOM
}

main() {
  local cmd="${1:-menu}"
  case "${cmd}" in
    install)      do_install ;;
    info)         print_info ;;
    status)       do_status ;;
    restart)      do_restart ;;
    change-port)  do_change_port ;;
    change-pass)  do_change_pass ;;
    uninstall)    do_uninstall ;;
    menu)         menu ;;
    *)            usage; exit 1 ;;
  esac
}

main "$@"
EOF

chmod +x /usr/local/bin/hy2-manager

# 快捷命令 hy2（直接进入菜单）
cat > /usr/local/bin/hy2 <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/hy2-manager menu
EOF
chmod +x /usr/local/bin/hy2

echo "安装完成！现在可直接输入：hy2"
echo "也可用命令模式：hy2-manager install|info|restart|change-port|change-pass|status|uninstall"
