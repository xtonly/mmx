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

# 检查并安装 Docker 和 Docker Compose
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在为您安装官方 Docker 环境...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
    fi
    
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

# 1. 全新安装 (带端口冲突检测重试)
install_app() {
    if [ -f "${APP_DIR}/docker-compose.yml" ]; then
        echo -e "${RED}检测到已安装配置，请使用更新或卸载功能。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi

    install_docker
    COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${YELLOW}正在创建安装目录: ${APP_DIR}...${NC}"
    mkdir -p "${APP_DIR}"
    cd "${APP_DIR}"

    JWT_SECRET=$(date +%s | sha256sum | base64 | head -c 32)

    # 进入端口设置与启动循环
    while true; do
        echo -e "${GREEN}===================================${NC}"
        read -p "请输入你想使用的面板端口 [默认 12889]: " PORT
        PORT=${PORT:-12889}

        echo -e "${YELLOW}正在生成配置 docker-compose.yml...${NC}"
        cat <<EOF > docker-compose.yml
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

        echo -e "${YELLOW}正在拉取镜像并启动容器...${NC}"
        $COMPOSE_CMD pull
        $COMPOSE_CMD up -d

        if [ $? -eq 0 ]; then
            IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
            echo -e "${GREEN}===================================================${NC}"
            echo -e "${GREEN}🎉 恭喜！妙妙屋X 一键安装成功！${NC}"
            echo -e "${GREEN}👉 面板访问地址: http://${IP}:${PORT}${NC}"
            echo -e "${YELLOW}⚠️ 注意：请确保防火墙已放行端口: ${PORT}${NC}"
            echo -e "${GREEN}===================================================${NC}"
            break # 成功启动，跳出循环
        else
            echo -e "${RED}❌ 启动失败！端口 ${PORT} 可能被占用，或存在网络问题。${NC}"
            read -p "是否更换一个新端口重新尝试？(y/n) [默认 y]: " RETRY
            RETRY=${RETRY:-y}
            if [[ "$RETRY" == "y" || "$RETRY" == "Y" ]]; then
                echo -e "${YELLOW}正在清理失败的容器状态，准备重试...${NC}"
                $COMPOSE_CMD down 2>/dev/null
                # 继续下一次循环，重新要求输入端口
            else
                echo -e "${RED}已取消安装。正在清理残留文件...${NC}"
                $COMPOSE_CMD down 2>/dev/null
                rm -rf "${APP_DIR}"
                break # 放弃安装，跳出循环
            fi
        fi
    done
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 2. 更新应用
update_app() {
    if [ ! -f "${APP_DIR}/docker-compose.yml" ]; then
        echo -e "${RED}未找到配置文件，请先执行安装！${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi
    
    COMPOSE_CMD=$(get_compose_cmd)
    cd "${APP_DIR}"
    echo -e "${YELLOW}正在拉取最新镜像...${NC}"
    $COMPOSE_CMD pull
    echo -e "${YELLOW}正在重建并重启容器...${NC}"
    $COMPOSE_CMD up -d
    echo -e "${GREEN}更新完成！${NC}"
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 3. 卸载应用
uninstall_app() {
    if [ ! -d "${APP_DIR}" ]; then
        echo -e "${RED}错误：未找到安装目录，您可能尚未安装。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
        return
    fi
    
    COMPOSE_CMD=$(get_compose_cmd)
    cd "${APP_DIR}"
    echo -e "${YELLOW}正在停止并删除容器...${NC}"
    $COMPOSE_CMD down
    
    read -p "是否需要彻底删除所有数据（配置、数据库等）？(y/n) [默认 n]: " DEL_DATA
    if [[ "$DEL_DATA" == "y" || "$DEL_DATA" == "Y" ]]; then
        cd /opt
        rm -rf "${APP_DIR}"
        echo -e "${GREEN}完全卸载成功，所有数据已被清除！${NC}"
    else
        rm -f docker-compose.yml
        echo -e "${GREEN}容器已卸载。您的数据保留在目录: ${APP_DIR}${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 4. 查看日志
view_logs() {
    COMPOSE_CMD=$(get_compose_cmd)
    if [ -d "${APP_DIR}" ]; then
        cd "${APP_DIR}"
        echo -e "${YELLOW}正在查看日志（按 Ctrl+C 退出返回终端）...${NC}"
        $COMPOSE_CMD logs -f --tail 100
    else
        echo -e "${RED}错误：安装目录不存在。${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
    fi
}

# 5. 查看状态
check_status() {
    if [ ! -d "${APP_DIR}" ]; then
        echo -e "${RED}尚未安装 妙妙屋X。${NC}"
    else
        echo -e "${BLUE}=== 容器运行状态 ===${NC}"
        docker ps -a --filter "name=miaomiaowux" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo -e "\n${BLUE}=== 系统资源占用 ===${NC}"
        docker stats --no-stream miaomiaowux 2>/dev/null || echo "容器未运行"
    fi
    echo ""
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 脚本主菜单
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}===================================${NC}"
        echo -e "${GREEN}     妙妙屋X 容器管理工具 v1.2       ${NC}"
        echo -e "${GREEN}===================================${NC}"
        echo -e " ${BLUE}1.${NC} 安装 妙妙屋X"
        echo -e " ${BLUE}2.${NC} 更新 妙妙屋X"
        echo -e " ${BLUE}3.${NC} 查看 当前状态"
        echo -e " ${BLUE}4.${NC} 查看 运行日志"
        echo -e " ${BLUE}5.${NC} 卸载 妙妙屋X"
        echo -e " ${BLUE}0.${NC} 退出脚本"
        echo -e "${GREEN}===================================${NC}"
        read -p "请输入数字选择 [0-5]: " CHOICE

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
