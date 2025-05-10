#!/bin/bash

# 客服聊天系统一键安装脚本
# 版本: 2.0.0 (优化版)
# 此脚本自动安装所有必需的依赖项并配置系统

set -e

# 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 显示彩色消息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清理函数 - 在脚本结束或中断时执行
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "安装过程中断，退出代码: $exit_code"
        log_info "可以通过查看日志文件了解更多信息: $LOG_FILE"
    fi
}

# 设置退出钩子
trap cleanup EXIT INT TERM

# 创建日志目录和日志文件
LOGS_DIR="/var/log/customer-service-chat"
mkdir -p "$LOGS_DIR"
LOG_FILE="$LOGS_DIR/install-$(date +%Y%m%d-%H%M%S).log"
touch "$LOG_FILE"

# 同时输出到控制台和日志文件
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用root权限运行此脚本 (sudo ./one-click-install.sh)"
    exit 1
fi

# 检查系统类型和版本
check_system() {
    log_info "检查系统兼容性..."
    
    # 检查Linux发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        
        log_info "检测到的系统: $PRETTY_NAME"
        
        # 检查支持的发行版
        case $DISTRO in
            ubuntu|debian)
                # 检查版本兼容性
                if [[ "$DISTRO" == "ubuntu" && $(echo "$VERSION" | cut -d. -f1) -lt 18 ]]; then
                    log_warning "检测到Ubuntu $VERSION，建议使用Ubuntu 18.04或更新版本"
                fi
                if [[ "$DISTRO" == "debian" && $(echo "$VERSION" | cut -d. -f1) -lt 10 ]]; then
                    log_warning "检测到Debian $VERSION，建议使用Debian 10或更新版本"
                fi
                ;;
            *)
                log_warning "未经测试的Linux发行版: $DISTRO $VERSION，安装可能会失败"
                read -p "是否继续安装? (y/n) " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "安装已取消"
                    exit 0
                fi
                ;;
        esac
    else
        log_warning "无法确定Linux发行版，安装可能会失败"
    fi
    
    # 检查系统内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 1024 ]; then
        log_warning "系统内存低于1GB (${total_mem}MB)，可能会影响性能"
    else
        log_info "系统内存: ${total_mem}MB"
    fi
    
    # 检查磁盘空间
    local free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 1024 ]; then
        log_warning "根分区可用空间低于1GB (${free_space}MB)，建议至少有2GB可用空间"
    else
        log_info "根分区可用空间: ${free_space}MB"
    fi
}

# 检查并安装依赖，如果不存在则安装
install_dependency() {
    local pkgs=("$@")
    local missing_pkgs=()
    
    # 检查哪些包需要安装
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l | grep -q "ii  $pkg "; then
            missing_pkgs+=("$pkg")
        fi
    done
    
    # 如果有缺失的包，一次性安装
    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        log_info "正在安装缺失的依赖: ${missing_pkgs[*]}..."
        apt-get update -qq
        apt-get install -y "${missing_pkgs[@]}" || {
            log_error "安装依赖失败"
            return 1
        }
    else
        log_info "所有依赖已安装"
    fi
    
    return 0
}

# 安装系统依赖
install_dependencies() {
    log_info "正在安装系统依赖..."
    
    # 定义所有需要的依赖
    local dependencies=(
        curl wget git build-essential nginx 
        certbot python3-certbot-nginx
        postgresql postgresql-contrib 
        redis-server ssl-cert
    )
    
    # 一次性安装所有依赖
    install_dependency "${dependencies[@]}" || {
        log_error "安装系统依赖失败"
        return 1
    }
    
    log_success "系统依赖安装完成"
    return 0
}

# 生成强密码
generate_password() {
    local length=${1:-16}
    local chars="A-Za-z0-9!#%&()*+,-./:;<=>?@[]^_"
    
    # 使用/dev/urandom和tr命令生成随机密码
    local password=$(tr -dc "$chars" </dev/urandom | head -c "$length")
    
    # 确保密码至少包含一个数字和一个特殊字符
    while ! [[ "$password" =~ [0-9] && "$password" =~ [^a-zA-Z0-9] ]]; do
        password=$(tr -dc "$chars" </dev/urandom | head -c "$length")
    done
    
    echo "$password"
}