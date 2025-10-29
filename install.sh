#!/bin/sh
# xray 一键安装脚本 (POSIX 兼容版)
# 适用于 Debian/Ubuntu 和 Alpine 系统

set -e

# 默认配置变量
: "${AL_PORTS:=63031-63034}"
: "${RE_PORT:=63035}"
: "${AL_DOMAIN:=us01.yyds.nyc.mn}"
: "${RE_SNI:=www.cityofrc.us}"
: "${XRAY_VER:=25.7.26}"

BASE_DIR=/opt/xray
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
ACME_DIR="$DATA_DIR/acme"
ACME_PROVIDER_DIR="acme-v02.api.letsencrypt.org-directory"
CERT_DIR_CONTAINER="/opt/certs/certificates/$ACME_PROVIDER_DIR/$AL_DOMAIN"
CERT_FILE="$CERT_DIR_CONTAINER/$AL_DOMAIN.crt"
KEY_FILE="$CERT_DIR_CONTAINER/$AL_DOMAIN.key"

RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[1;33m')"
NC="$(printf '\033[0m')"

COMPOSE_CMD=""

log_info() {
    printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$1"
}

log_warn() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1"
}

log_error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        log_error "无法检测系统类型"
        exit 1
    fi
    log_info "检测到系统: $OS"
}

check_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker 已安装: $(docker --version)"
        return 0
    else
        log_warn "Docker 未安装"
        return 1
    fi
}

check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose 已安装: $(docker compose version)"
        COMPOSE_CMD="docker compose"
        return 0
    elif command -v docker-compose >/dev/null 2>&1; then
        log_info "Docker Compose 已安装: $(docker-compose --version)"
        COMPOSE_CMD="docker-compose"
        return 0
    else
        log_warn "Docker Compose 未安装"
        return 1
    fi
}

install_docker_debian() {
    log_info "开始安装 Docker (Debian/Ubuntu)..."
    curl -fsSL https://get.docker.com | sh -s docker
    systemctl enable docker
    systemctl start docker
    log_info "Docker 安装完成"
}

install_docker_alpine() {
    log_info "开始安装 Docker (Alpine)..."
    apk add docker docker-cli-compose
    rc-update add docker boot
    service docker start
    log_info "Docker 安装完成"
}

install_docker() {
    case $OS in
        ubuntu|debian)
            install_docker_debian
            ;;
        alpine)
            install_docker_alpine
            ;;
        *)
            log_error "不支持的系统类型: $OS"
            exit 1
            ;;
    esac
}

parse_ports() {
    case "$AL_PORTS" in
        *-*)
            PORT_START=${AL_PORTS%-*}
            PORT_END=${AL_PORTS#*-}
            ;;
        *)
            log_error "端口范围格式错误，应为: 开始端口-结束端口 (如: 63031-63034)"
            exit 1
            ;;
    esac

    case $PORT_START in
        ''|*[!0-9]*)
            log_error "开始端口必须为数字"
            exit 1
            ;;
    esac

    case $PORT_END in
        ''|*[!0-9]*)
            log_error "结束端口必须为数字"
            exit 1
            ;;
    esac

    if [ "$PORT_START" -gt "$PORT_END" ]; then
        log_error "端口范围错误: 开始端口大于结束端口"
        exit 1
    fi

    if [ $((PORT_END - PORT_START)) -lt 3 ]; then
        log_error "端口范围不足 4 个端口"
        exit 1
    fi

    PORT_SS=$PORT_START
    PORT_TROJAN=$((PORT_START + 1))
    PORT_VMESS=$((PORT_START + 2))
    PORT_VLESS_TLS=$((PORT_START + 3))

    case $RE_PORT in
        ''|*[!0-9]*)
            log_error "Reality 端口必须为数字"
            exit 1
            ;;
    esac
}

create_directories() {
    log_info "创建目录结构..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$ACME_DIR"
    log_info "目录创建完成: $BASE_DIR"
}

create_docker_compose() {
    log_info "创建 docker-compose.yml..."
    cat > "$BASE_DIR/docker-compose.yml" << EOF
services:
  xray:
    image: teddysun/xray:$XRAY_VER
    container_name: xray
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/etc/xray:ro
      - $ACME_DIR:/opt/certs:ro
EOF
    log_info "docker-compose.yml 创建完成"
}

create_config() {
    log_info "创建 config.json..."
    log_info "使用端口配置: SS=$PORT_SS, Trojan=$PORT_TROJAN, VMess=$PORT_VMESS, VLESS(TLS)=$PORT_VLESS, Reality=$RE_PORT"
    log_info "使用域名: $AL_DOMAIN, Reality SNI: $RE_SNI"

    cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT_SS,
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "L3vCBgE7nSUlHQcV0D9qYA==",
        "network": "tcp,udp"
      }
    },
    {
      "port": $PORT_TROJAN,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "hBh1uKxMhYr6yTc40MDIcg=="
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      }
    },
    {
      "port": $PORT_VMESS,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "25ec3523-5bbc-4cbf-b946-879941af55ab"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      }
    },
    {
      "port": $PORT_VLESS,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "43a1f08a-d9ff-4aea-ac8a-cc622caf62a5"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "h2",
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      }
    },
    {
      "port": $RE_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "43a1f08a-d9ff-4aea-ac8a-cc622caf62a5",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$RE_SNI:443",
          "serverNames": [
            "$RE_SNI"
          ],
          "privateKey": "IJ7MvrtAgMGCJdLk4JHtaRci5uAIa2SD5aNO0hsNJ2U",
          "shortIds": [
            "4eae9cfd38fb5a8d"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    log_info "config.json 创建完成"
    log_warn "请确保证书已存在于 $ACME_DIR/certificates/$ACME_PROVIDER_DIR/$AL_DOMAIN/ 下，否则 TLS/Reality 无法正常工作"
}

start_container() {
    log_info "启动 xray 容器..."
    cd "$BASE_DIR" || exit 1
    $COMPOSE_CMD up -d
    log_info "xray 容器已启动"
}

show_status() {
    printf '\n'
    log_info "========================================"
    log_info "xray 安装完成！"
    log_info "========================================"
    printf '\n'
    log_info "配置信息:"
    log_info "  - Xray 版本: $XRAY_VER"
    log_info "  - Shadowsocks 端口: $PORT_SS"
    log_info "  - Trojan 端口: $PORT_TROJAN"
    log_info "  - VMess 端口: $PORT_VMESS"
    log_info "  - VLESS (TLS) 端口: $PORT_VLESS"
    log_info "  - VLESS (Reality) 端口: $RE_PORT"
    log_info "  - TLS/ACME 域名: $AL_DOMAIN"
    log_info "  - Reality SNI: $RE_SNI"
    printf '\n'
    log_info "常用命令:"
    log_info "  - 查看日志: docker logs -f xray"
    log_info "  - 停止容器: cd $BASE_DIR && $COMPOSE_CMD down"
    log_info "  - 重启容器: cd $BASE_DIR && $COMPOSE_CMD restart"
    log_info "  - 查看状态: docker ps | grep xray"
    printf '\n'
}

main() {
    printf '\n'
    log_info "========================================"
    log_info "xray 一键安装脚本"
    log_info "========================================"
    printf '\n'

    detect_os

    if ! check_docker; then
        log_info "准备安装 Docker..."
        install_docker
    fi

    if ! check_docker_compose; then
        log_error "Docker Compose 未安装，但应该随 Docker 一起安装"
        exit 1
    fi

    parse_ports
    create_directories
    create_docker_compose
    create_config
    start_container
    show_status
}

main
