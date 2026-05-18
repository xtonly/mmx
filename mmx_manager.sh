cat << 'EOF_SCRIPT' > mmx_manager.sh && chmod +x mmx_manager.sh && ./mmx_manager.sh
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 用户或使用 sudo 运行此脚本！${NC}"
    exit 1
fi

APP_DIR="/opt/miaomiaowux"

# 检查并安装 Docker 和 Docker Compose
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在为您安装官方 Docker 环境...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
    fi
    
    # 检查新版 docker compose 插件或老版 docker-compose
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker Compose 插件，正在尝试安装...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y docker-compose-plugin
        elif command -v yum &> /dev/null; then
            yum install -y docker-compose-plugin
        fi
    fi
}

# 获取正确的 compose 执行命令
get_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# 安装妙妙屋X
install_app() {
    install_docker
    COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${GREEN}===================================${NC}"
    read -p "请输入你想使用的面板端口 [默认 12889]: " PORT
    PORT=${PORT:-12889}
    
    # 随机生成一个 JWT 密钥增强安全性
    JWT_SECRET=$(date +%s | sha256sum | base64 | head -c 32)

    echo -e "${YELLOW}正在创建安装目录: ${APP_DIR}...${NC}"
    mkdir -p "${APP_DIR}"
    cd "${APP_DIR}"

    echo -e "${YELLOW}正在生成配置 docker-compose.yml...${NC}"
    cat <<EOF > docker-compose.yml
version: '3.8'

services:
  miaomiaowux:
    image: ghcr.io/iluobei/miaomiaowux:latest
    container_name: miaomiaowux
    restart: unless-stopped
    user: root
    environment:
      - PORT=${PORT}
      - LOG_LEVEL=info
      - JWT_SECRET=${JWT_SECRET}
    ports:
      - "${PORT}:${PORT}"
    volumes:
      - ./data:/app/data
      - ./subscribes:/app/subscribes
      - ./rule_templates:/app/rule_templates
EOF

    echo -e "${YELLOW}正在拉取最新镜像并启动容器...${NC}"
    $COMPOSE_CMD pull
    $COMPOSE_CMD up -d

    if [ $? -eq 0 ]; then
        IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
        echo -e "${GREEN}===================================================${NC}"
        echo -e "${GREEN}🎉 恭喜！妙妙屋X 一键 Docker 安装成功！${NC}"
        echo -e "${GREEN}👉 面板访问地址: http://${IP}:${PORT}${NC}"
        echo -e "${GREEN}📂 数据安装目录: ${APP_DIR}${NC}"
        echo -e "${YELLOW}⚠️ 注意：请确保您服务器的安全组/防火墙已放行端口: ${PORT}${NC}"
        echo -e "${GREEN}===================================================${NC}"
    else
        echo -e "${RED}❌ 启动失败，请检查端口 ${PORT} 是否被占用，或检查网络是否能连接到 ghcr.io 镜像源！${NC}"
    fi
}

# 卸载功能
uninstall_app() {
    COMPOSE_CMD=$(get_compose_cmd)
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        echo -e "${YELLOW}正在停止并删除妙妙屋X容器...${NC}"
        $COMPOSE_CMD down
        echo -e "${RED}为了防止误删，脚本默认不会自动清除数据文件夹。${NC}"
        read -p "是否需要删除所有数据（包括订阅、配置、数据库）？(y/n) [默认 n]: " DEL_DATA
        if [[ "$DEL_DATA" == "y" || "$DEL_DATA" == "Y" ]]; then
            rm -rf "${APP_DIR}"
            echo -e "${GREEN}完全卸载成功，所有数据已被清除！${NC}"
        else
            rm -f docker-compose.yml
            echo -e "${GREEN}容器已卸载。您的数据仍保留在目录: ${APP_DIR}${NC}"
        fi
    else
        echo -e "${RED}错误：未找到安装目录 ${APP_DIR}，您可能尚未安装。${NC}"
    fi
}

# 重启功能
restart_app() {
    COMPOSE_CMD=$(get_compose_cmd)
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        $COMPOSE_CMD restart
        echo -e "${GREEN}妙妙屋X 已完成重启！${NC}"
    else
        echo -e "${RED}错误：安装目录不存在。${NC}"
    fi
}

# 查看日志
view_logs() {
    COMPOSE_CMD=$(get_compose_cmd)
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        echo -e "${YELLOW}正在实时查看日志（按 Ctrl+C 退出日志查看）...${NC}"
        $COMPOSE_CMD logs -f --tail 100
    else
        echo -e "${RED}错误：安装目录不存在。${NC}"
    fi
}

# 脚本主菜单
show_menu() {
    clear
    echo -e "${GREEN}===================================${NC}"
    echo -e "${GREEN}     妙妙屋X 一键 Docker 管理脚本     ${NC}"
    echo -e "${GREEN}===================================${NC}"
    echo -e " 1. 安装 / 更新 妙妙屋X"
    echo -e " 2. 重启 妙妙屋X"
    echo -e " 3. 查看 运行日志"
    echo -e " 4. 卸载 妙妙屋X"
    echo -e " 0. 退出脚本"
    echo -e "${GREEN}===================================${NC}"
    read -p "请输入数字选择 [0-4]: " CHOICE

    case $CHOICE in
        1) install_app ;;
        2) restart_app ;;
        3) view_logs ;;
        4) uninstall_app ;;
        *) exit 0 ;;
    esac
}

show_menu
EOF_SCRIPT
