#!/bin/bash

# Shadowsocks (libev & rust) + simple-obfs 一键安装脚本
# 适用于 Debian / Ubuntu
# 使用方法: bash install.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${GREEN}[信息]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_step() { echo -e "${BLUE}[步骤]${NC} $1"; }

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    print_error "此脚本必须以 root 身份运行"
    exit 1
fi

# 配置参数
LIB_PORT=${LIB_PORT:-65041}
RUST_PORT=${RUST_PORT:-65042}
PASSWORD="opj33QlG2TRNOB18xt288A=="

print_info "=== Shadowsocks 安装脚本 ==="
echo "配置信息："
echo "  - shadowsocks-libev 端口: $LIB_PORT"
echo "  - shadowsocks-rust 端口: $RUST_PORT"
echo "  - 密码: $PASSWORD"
echo "  - libev 加密: aes-256-gcm"
echo "  - rust 加密: aes-128-gcm"
echo "  - 混淆插件: obfs-server (http)"
echo

# 步骤 1: 更新系统
print_step "步骤 1/7: 更新系统并安装基础工具"
apt update && apt upgrade -y
apt install -y sudo curl wget openssl unzip xz-utils
print_success "系统更新完成"
echo

# 步骤 2: 安装 shadowsocks-libev
print_step "步骤 2/7: 安装 shadowsocks-libev"
apt install -y shadowsocks-libev

if command -v ss-server >/dev/null 2>&1; then
    print_success "shadowsocks-libev 安装完成"
    ss-server -h | head -n 1
else
    print_error "shadowsocks-libev 安装失败"
    exit 1
fi
echo

# 步骤 3: 安装 shadowsocks-rust
print_step "步骤 3/7: 安装 shadowsocks-rust（获取最新版本）"

# 获取最新版本号
print_info "正在获取 shadowsocks-rust 最新版本..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    print_warn "无法获取最新版本，使用默认版本 1.23.5"
    LATEST_VERSION="1.23.5"
else
    print_info "最新版本: v$LATEST_VERSION"
fi

RUST_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${LATEST_VERSION}/shadowsocks-v${LATEST_VERSION}.x86_64-unknown-linux-gnu.tar.xz"

print_info "下载 shadowsocks-rust..."
wget -q --show-progress "$RUST_URL" -O /tmp/shadowsocks-rust.tar.xz

print_info "解压并安装..."
cd /tmp
tar -xf shadowsocks-rust.tar.xz
mv ss* /usr/bin/
chmod +x /usr/bin/ss*
rm -f /tmp/shadowsocks-rust.tar.xz

if command -v ssserver >/dev/null 2>&1; then
    print_success "shadowsocks-rust 安装完成"
    ssserver --version
else
    print_error "shadowsocks-rust 安装失败"
    exit 1
fi
echo

# 步骤 4: 安装 simple-obfs
print_step "步骤 4/7: 安装 simple-obfs"

OBFS_URL="https://github.com/hide3110/ss-lib-rust/raw/main/simple-obfs-debian10-amd64.tar.gz"

print_info "下载 simple-obfs..."
if wget -q --show-progress "$OBFS_URL" -O /tmp/simple-obfs.tar.gz; then
    cd /tmp
    tar -xzf simple-obfs.tar.gz
    mv obfs-server obfs-local /usr/bin/
    chmod +x /usr/bin/obfs-*
    rm -f /tmp/simple-obfs.tar.gz
    
    if command -v obfs-server >/dev/null 2>&1; then
        print_success "simple-obfs 安装完成"
        obfs-server --help 2>&1 | head -n 1 || echo "obfs-server installed"
    else
        print_warn "simple-obfs 安装失败，将跳过混淆配置"
        USE_OBFS=false
    fi
else
    print_warn "simple-obfs 下载失败，将跳过混淆配置"
    USE_OBFS=false
fi
echo

# 步骤 5: 创建 shadowsocks-rust systemd 服务
print_step "步骤 5/7: 创建 shadowsocks-rust 服务文件"

cat > /usr/lib/systemd/system/shadowsocks-rust.service <<'EOF'
[Unit]
Description=Shadowsocks-rust Service
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network.target

[Service]
Type=simple
LimitNOFILE=32768
ExecStart=/usr/bin/ssservice server --log-without-time -c /etc/shadowsocks-rust/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

print_success "shadowsocks-rust 服务文件创建完成"
echo

# 步骤 6: 创建配置文件
print_step "步骤 6/7: 创建配置文件"

mkdir -p /etc/shadowsocks-libev
mkdir -p /etc/shadowsocks-rust

# shadowsocks-libev 配置
print_info "创建 shadowsocks-libev 配置..."
if [ "$USE_OBFS" != false ]; then
    cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $LIB_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "aes-256-gcm",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "mode": "tcp_and_udp",
    "plugin": "obfs-server",
    "plugin_opts": "obfs=http"
}
EOF
else
    cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $LIB_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "aes-256-gcm",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "mode": "tcp_and_udp"
}
EOF
fi

# shadowsocks-rust 配置
print_info "创建 shadowsocks-rust 配置..."
if [ "$USE_OBFS" != false ]; then
    cat > /etc/shadowsocks-rust/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $RUST_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "aes-128-gcm",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "mode": "tcp_and_udp",
    "plugin": "obfs-server",
    "plugin_opts": "obfs=http"
}
EOF
else
    cat > /etc/shadowsocks-rust/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $RUST_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "aes-128-gcm",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "mode": "tcp_and_udp"
}
EOF
fi

print_success "配置文件创建完成"
echo

# 步骤 7: 启动服务
print_step "步骤 7/7: 启动并启用服务"

systemctl daemon-reload

print_info "启动 shadowsocks-libev..."
systemctl enable shadowsocks-libev --now
sleep 2

if systemctl is-active --quiet shadowsocks-libev; then
    print_success "shadowsocks-libev 服务已启动"
else
    print_error "shadowsocks-libev 服务启动失败"
    systemctl status shadowsocks-libev --no-pager
fi

print_info "启动 shadowsocks-rust..."
systemctl enable shadowsocks-rust --now
sleep 2

if systemctl is-active --quiet shadowsocks-rust; then
    print_success "shadowsocks-rust 服务已启动"
else
    print_error "shadowsocks-rust 服务启动失败"
    systemctl status shadowsocks-rust --no-pager
fi

echo

# 安装总结
print_success "=========================================="
print_success "安装完成！"
print_success "=========================================="
echo
print_info "服务器信息："
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "获取失败")
echo "  服务器地址: $SERVER_IP"
echo "  shadowsocks-libev 端口: $LIB_PORT"
echo "  shadowsocks-rust 端口: $RUST_PORT"
echo "  密码: $PASSWORD"
echo "  libev 加密方法: aes-256-gcm"
echo "  rust 加密方法: aes-128-gcm"
if [ "$USE_OBFS" != false ]; then
    echo "  混淆插件: obfs-server"
    echo "  混淆类型: http"
else
    echo "  混淆插件: 未安装"
fi
echo
print_info "配置文件位置："
echo "  - /etc/shadowsocks-libev/config.json"
echo "  - /etc/shadowsocks-rust/config.json"
echo
print_info "服务管理命令："
echo "  - systemctl status shadowsocks-libev"
echo "  - systemctl status shadowsocks-rust"
echo "  - systemctl restart shadowsocks-libev"
echo "  - systemctl restart shadowsocks-rust"
echo
print_info "日志查看命令："
echo "  - journalctl -u shadowsocks-libev -f"
echo "  - journalctl -u shadowsocks-rust -f"
echo
print_success "=========================================="
