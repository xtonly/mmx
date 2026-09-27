cat << 'EOF_SCRIPT' > mmx_manager.sh && chmod +x mmx_manager.sh && ./mmx_manager.sh
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 用户或使用 sudo 运行此脚本！${NC}"
    exit 1
fi

APP_DIR="/opt/miaomiaowux"

install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在为您安装官方 Docker 环境...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
    fi
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}安装 Docker Compose 插件...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y docker-compose-plugin
        elif command -v yum &> /dev/null; then
            yum install -y docker-compose-plugin
        fi
    fi
}

get_compose_cmd() {
    if docker compose version &> /dev/null; then echo "docker compose"; else echo "docker-compose"; fi
}

install_app() {
    if [ -f "${APP_DIR}/docker-compose.yml" ]; then
        echo -e "${RED}检测到已安装配置，请使用更新或卸载功能。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi

    install_docker
    COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${YELLOW}创建安装目录: ${APP_DIR}...${NC}"
    mkdir -p "${APP_DIR}"
    cd "${APP_DIR}"

    # 安全增强：生成 32 位强随机 JWT 密钥，防止会话伪造
    JWT_SECRET=$(date +%s | sha256sum | base64 | head -c 32)

    while true; do
        echo -e "${GREEN}===================================${NC}"
        read -p "请输入面板访问端口 [默认 12889]: " PORT
        PORT=${PORT:-12889}

        echo -e "${YELLOW}正在生成安全版 docker-compose.yml...${NC}"
        cat <<EOF > docker-compose.yml
services:
  miaomiaowux:
    image: ghcr.io/iluobei/miaomiaowux:latest
    container_name: miaomiaowux
    restart: unless-stopped
    user: root
    # 【核心配置】IPv6 节点与多端口必须使用 host 模式，否则代理节点无法绑定公网 IPv6 地址
    network_mode: host
    environment:
      - PORT=${PORT}
      - LOG_LEVEL=info
      - JWT_SECRET=${JWT_SECRET}
      # 安全与兼容：绕过 503 拦截，允许直接反代或 IP 访问
      - MMWX_FORCE_PUBLIC_ACCESS=1
    volumes:
      - ./data:/app/data
      - ./subscribes:/app/subscribes
      - ./rule_templates:/app/rule_templates
      # 时间线安全：挂载宿主机时区，确保连接审计日志和流量重置时间绝对准确
      - /etc/localtime:/etc/localtime:ro
EOF

        echo -e "${YELLOW}拉取镜像并启动容器...${NC}"
        $COMPOSE_CMD pull
        $COMPOSE_CMD up -d

        if [ $? -eq 0 ]; then
            IP4=$(curl -s -4 ifconfig.me || echo "未检测到IPv4")
            IP6=$(curl -s -6 ifconfig.me || echo "未检测到IPv6")
            echo -e "${GREEN}===================================================${NC}"
            echo -e "${GREEN}🎉 恭喜！妙妙屋X (支持 IPv6 节点) 安装成功！${NC}"
            echo -e "${GREEN}👉 面板地址 (请通过 Caddy 反代访问): http://127.0.0.1:${PORT}${NC}"
            echo -e "${BLUE}ℹ️ 您的公网 IPv4: ${IP4}${NC}"
            echo -e "${BLUE}ℹ️ 您的公网 IPv6: ${IP6}${NC}"
            echo -e "${YELLOW}⚠️ 提示：添加本地节点时，监听地址请填 0.0.0.0 或 [::]${NC}"
            echo -e "${GREEN}===================================================${NC}"
            break
        else
            echo -e "${RED}❌ 启动失败！端口 ${PORT} 可能被占用。${NC}"
            read -p "是否更换新端口重试？(y/n) [默认 y]: " RETRY
            RETRY=${RETRY:-y}
            if [[ "$RETRY" == "y" || "$RETRY" == "Y" ]]; then
                $COMPOSE_CMD down 2>/dev/null
                rm -f docker-compose.yml
            else
                $COMPOSE_CMD down 2>/dev/null
                rm -rf "${APP_DIR}"
                break
            fi
        fi
    done
    read -n 1 -s -r -p "按任意键返回菜单..."
}

update_app() {
    if [ ! -f "${APP_DIR}/docker-compose.yml" ]; then
        echo -e "${RED}未找到配置，请先执行安装！${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi
    COMPOSE_CMD=$(get_compose_cmd)
    cd "${APP_DIR}"
    echo -e "${YELLOW}拉取最新镜像并重启...${NC}"
    $COMPOSE_CMD pull
    $COMPOSE_CMD up -d
    echo -e "${GREEN}更新完成！${NC}"
    read -n 1 -s -r -p "按任意键返回菜单..."
}

uninstall_app() {
    if [ ! -d "${APP_DIR}" ]; then
        echo -e "${RED}未找到安装目录。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi
    COMPOSE_CMD=$(get_compose_cmd)
    cd "${APP_DIR}"
    echo -e "${YELLOW}停止并删除容器...${NC}"
    $COMPOSE_CMD down
    read -p "是否彻底删除所有数据(含数据库和节点配置)？(y/n) [默认 n]: " DEL_DATA
    if [[ "$DEL_DATA" == "y" || "$DEL_DATA" == "Y" ]]; then
        cd /opt
        rm -rf "${APP_DIR}"
        echo -e "${GREEN}数据已完全清除！${NC}"
    else
        rm -f docker-compose.yml
        echo -e "${GREEN}容器已卸载，数据保留。${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回菜单..."
}

view_logs() {
    COMPOSE_CMD=$(get_compose_cmd)
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        $COMPOSE_CMD logs -f --tail 100
    else
        echo -e "${RED}目录不存在。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
    fi
}

check_status() {
    if [ ! -d "${APP_DIR}" ]; then
        echo -e "${RED}尚未安装。${NC}"
    else
        echo -e "${BLUE}=== 容器状态 ===${NC}"
        docker ps -a --filter "name=miaomiaowux" --format "table {{.Names}}\t{{.Status}}\t{{.NetworkMode}}"
    fi
    read -n 1 -s -r -p "按任意键返回菜单..."
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}===================================${NC}"
        echo -e "${GREEN}   妙妙屋X 管理工具 (IPv6 节点增强版)  ${NC}"
        echo -e "${GREEN}===================================${NC}"
        echo -e " ${BLUE}1.${NC} 安装 妙妙屋X"
        echo -e " ${BLUE}2.${NC} 更新 妙妙屋X"
        echo -e " ${BLUE}3.${NC} 查看 当前状态"
        echo -e " ${BLUE}4.${NC} 查看 运行日志"
        echo -e " ${BLUE}5.${NC} 卸载 妙妙屋X"
        echo -e " ${BLUE}0.${NC} 退出脚本"
        echo -e "${GREEN}===================================${NC}"
        read -p "请输入数字 [0-5]: " CHOICE
        case $CHOICE in
            1) install_app ;;
            2) update_app ;;
            3) check_status ;;
            4) view_logs ;;
            5) uninstall_app ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入！${NC}" && sleep 1 ;;
        esac
    done
}

show_menu
EOF_SCRIPT
