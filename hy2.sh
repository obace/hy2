# 1. 创建并写入脚本
cat > hy2_manage.sh << 'EOF'
#!/bin/bash

# ==========================================
# Hysteria 2 一键管理脚本 (自签名 bing.com 版)
# ==========================================

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 路径定义
HY2_BIN="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CERT_FILE="${CONFIG_DIR}/server.crt"
KEY_FILE="${CONFIG_DIR}/server.key"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"

# 检查是否为 root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n" && exit 1

# 安装依赖
install_dependencies() {
    echo -e "${GREEN}正在安装依赖...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt update && apt install -y curl wget openssl ca-certificates
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl wget openssl ca-certificates
    fi
}

# 生成随机端口
get_random_port() {
    echo $(shuf -i 10000-65000 -n 1)
}

# 生成随机密码
get_random_pass() {
    echo $(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
}

# 生成自签名证书 (CN=bing.com)
generate_cert() {
    echo -e "${GREEN}正在生成自签名证书 (域名: bing.com)...${PLAIN}"
    mkdir -p $CONFIG_DIR
    openssl req -x509 -nodes -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -days 3650 -subj "/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/CN=bing.com"
    chmod 644 $CERT_FILE
    chmod 600 $KEY_FILE
}

# 写入配置文件
write_config() {
    local port=$1
    local password=$2
    
    cat > $CONFIG_FILE <<EOF
listen: :$port

tls:
  cert: $CERT_FILE
  key: $KEY_FILE

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF
}

# 安装 Hysteria 2
install_hy2() {
    install_dependencies
    
    echo -e "${GREEN}正在下载 Hysteria 2 核心...${PLAIN}"
    # 使用官方脚本安装/更新
    bash <(curl -fsSL https://get.hy2.sh/)
    
    # 停止服务以进行配置
    systemctl stop hysteria-server 2>/dev/null

    # 生成配置
    local port=$(get_random_port)
    local password=$(get_random_pass)
    
    generate_cert
    write_config "$port" "$password"
    
    # 重启服务
    systemctl enable hysteria-server
    systemctl restart hysteria-server
    
    echo -e "${GREEN}Hysteria 2 安装并启动成功！${PLAIN}"
    show_config
}

# 获取公网 IP
get_ip() {
    local ip=$(curl -s4 ifconfig.me)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4 icanhazip.com)
    fi
    echo $ip
}

# 显示配置信息
show_config() {
    if [[ ! -f $CONFIG_FILE ]]; then
        echo -e "${RED}配置文件不存在，请先安装！${PLAIN}"
        return
    fi

    local port=$(grep "listen:" $CONFIG_FILE | awk -F: '{print $3}')
    local password=$(grep "password:" $CONFIG_FILE | awk '{print $2}')
    local ip=$(get_ip)
    
    echo -e "\n========================================"
    echo -e "       Hysteria 2 配置信息"
    echo -e "========================================"
    echo -e "IP 地址: ${GREEN}${ip}${PLAIN}"
    echo -e "端口   : ${GREEN}${port}${PLAIN}"
    echo -e "密码   : ${GREEN}${password}${PLAIN}"
    echo -e "SNI    : ${GREEN}bing.com${PLAIN}"
    echo -e "========================================"
    
    # 生成分享链接
    # 注意：因为是自签名证书，必须加上 insecure=1
    local hy2_link="hy2://${password}@${ip}:${port}/?insecure=1&sni=bing.com#Hysteria2-Bing"
    
    echo -e "分享链接 (复制导入客户端):"
    echo -e "${YELLOW}${hy2_link}${PLAIN}"
    echo -e "========================================"
    echo -e "${RED}注意：由于使用自签名证书，客户端必须开启【允许不安全连接/跳过证书验证】选项。${PLAIN}"
    echo -e ""
}

# 修改端口
change_port() {
    read -p "请输入新端口 (留空则随机): " new_port
    [[ -z "$new_port" ]] && new_port=$(get_random_port)
    
    sed -i "s/listen: :.*/listen: :$new_port/" $CONFIG_FILE
    systemctl restart hysteria-server
    echo -e "${GREEN}端口已修改为: $new_port${PLAIN}"
    show_config
}

# 修改密码
change_password() {
    read -p "请输入新密码 (留空则随机): " new_pass
    [[ -z "$new_pass" ]] && new_pass=$(get_random_pass)
    
    sed -i "s/password: .*/password: $new_pass/" $CONFIG_FILE
    systemctl restart hysteria-server
    echo -e "${GREEN}密码已修改为: $new_pass${PLAIN}"
    show_config
}

# 卸载
uninstall_hy2() {
    echo -e "${YELLOW}正在卸载 Hysteria 2...${PLAIN}"
    systemctl stop hysteria-server
    systemctl disable hysteria-server
    rm -f $SERVICE_FILE
    rm -rf $CONFIG_DIR
    rm -f $HY2_BIN
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成！${PLAIN}"
}

# 菜单
menu() {
    clear
    echo -e "#############################################"
    echo -e "#    Hysteria 2 一键管理脚本 (Bing自签版)   #"
    echo -e "#############################################"
    echo -e " 1. 安装 Hysteria 2"
    echo -e " 2. 查看当前配置 / 分享链接"
    echo -e " 3. 修改端口"
    echo -e " 4. 修改密码"
    echo -e " 5. 重启服务"
    echo -e " 6. 卸载 Hysteria 2"
    echo -e " 0. 退出"
    echo -e "#############################################"
    
    read -p "请选择 [0-6]: " choice
    case $choice in
        1) install_hy2 ;;
        2) show_config ;;
        3) change_port ;;
        4) change_password ;;
        5) systemctl restart hysteria-server && echo -e "${GREEN}服务已重启${PLAIN}" ;;
        6) uninstall_hy2 ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${PLAIN}" ;;
    esac
}
