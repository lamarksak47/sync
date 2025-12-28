#!/bin/bash

# ============================================
# INSTALADOR XUI ONE VODs SYNC - Ubuntu 20.04
# ============================================
# Script completo de instalação e configuração
# Autor: XUI ONE VODs Sync Team
# Versão: 2.0.0
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Constantes
SCRIPT_VERSION="2.0.0"
INSTALL_DIR="/opt/xui-one-vods-sync"
CONFIG_DIR="/etc/xui-one-vods-sync"
LOG_DIR="/var/log/xui-one-vods-sync"
SERVICE_USER="xui-vods"
DATABASE_NAME="xui_one_vods"
DATABASE_USER="xui_one_vods_user"
API_PORT="8001"
WEB_PORT="8080"
DOMAIN_NAME=""
EMAIL=""
ENABLE_SSL=false

# Variáveis de controle
IS_ROOT=false
IS_UBUNTU=false
IS_20_04=false
MYSQL_ROOT_PASS=""
DB_PASSWORD=""
API_KEY=""
INSTALL_TYPE="full" # full, api-only, web-only

# Funções de utilidade
print_header() {
    clear
    echo -e "${PURPLE}"
    echo "============================================="
    echo "   XUI ONE VODs Sync - Instalador v$SCRIPT_VERSION"
    echo "============================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

pause() {
    echo ""
    read -p "Pressione Enter para continuar..."
}

generate_random_password() {
    local length=${1:-24}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c $length
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        IS_ROOT=true
        print_success "Executando como root"
    else
        print_error "Este script precisa ser executado como root"
        echo "Use: sudo $0"
        exit 1
    fi
}

check_os() {
    print_status "Verificando sistema operacional..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            IS_UBUNTU=true
            print_success "Sistema: Ubuntu"
            
            if [[ "$VERSION_ID" == "20.04" ]]; then
                IS_20_04=true
                print_success "Versão: 20.04 LTS"
            else
                print_warning "Versão: $VERSION_ID (Este script foi testado para 20.04)"
                read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                    exit 1
                fi
            fi
        else
            print_error "Sistema não suportado: $ID"
            print_info "Este instalador é específico para Ubuntu 20.04"
            exit 1
        fi
    else
        print_error "Não foi possível identificar o sistema operacional"
        exit 1
    fi
}

check_dependencies() {
    print_status "Verificando dependências básicas..."
    
    local missing_deps=()
    
    # Verifica comandos essenciais
    for cmd in curl wget git systemctl; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Dependências faltando: ${missing_deps[*]}"
        print_status "Instalando dependências básicas..."
        apt-get update
        apt-get install -y curl wget git systemd
    else
        print_success "Dependências básicas verificadas"
    fi
}

get_install_type() {
    print_header
    echo "Selecione o tipo de instalação:"
    echo "1) Instalação Completa (API + Painel Web + MySQL + Nginx)"
    echo "2) Apenas API Backend"
    echo "3) Apenas Painel Web"
    echo "4) Instalação Personalizada"
    echo ""
    
    read -p "Digite sua escolha [1-4]: " choice
    
    case $choice in
        1) INSTALL_TYPE="full" ;;
        2) INSTALL_TYPE="api-only" ;;
        3) INSTALL_TYPE="web-only" ;;
        4) INSTALL_TYPE="custom" ;;
        *) INSTALL_TYPE="full" ;;
    esac
    
    if [[ "$INSTALL_TYPE" == "custom" ]]; then
        echo ""
        echo "Selecione componentes para instalar:"
        read -p "Instalar API Backend? (s/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Ss]$ ]] && INSTALL_API=true || INSTALL_API=false
        
        read -p "Instalar Painel Web? (s/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Ss]$ ]] && INSTALL_WEB=true || INSTALL_WEB=false
        
        read -p "Instalar MySQL? (s/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Ss]$ ]] && INSTALL_MYSQL=true || INSTALL_MYSQL=false
        
        read -p "Instalar Nginx? (s/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Ss]$ ]] && INSTALL_NGINX=true || INSTALL_NGINX=false
        
        read -p "Configurar SSL? (s/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Ss]$ ]] && ENABLE_SSL=true || ENABLE_SSL=false
    fi
}

get_configuration() {
    print_header
    print_status "Configuração do Sistema"
    echo ""
    
    # Configurações gerais
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]]; then
        read -p "Porta para API Backend [$API_PORT]: " input_port
        API_PORT=${input_port:-$API_PORT}
        
        read -p "Chave API (deixe em branco para gerar automaticamente): " input_key
        if [[ -z "$input_key" ]]; then
            API_KEY=$(generate_random_password 32)
            print_info "Chave API gerada: $API_KEY"
        else
            API_KEY="$input_key"
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]]; then
        read -p "Porta para Painel Web [$WEB_PORT]: " input_web_port
        WEB_PORT=${input_web_port:-$WEB_PORT}
    fi
    
    # Configurações de banco de dados
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]]; then
        echo ""
        print_status "Configuração do Banco de Dados MySQL"
        
        # Verifica se MySQL já está instalado
        if systemctl is-active --quiet mysql; then
            print_warning "MySQL já está instalado e rodando"
            read -p "Usar instalação existente? (S/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                INSTALL_MYSQL=true
            else
                INSTALL_MYSQL=false
                read -p "Senha root do MySQL: " -s MYSQL_ROOT_PASS
                echo
            fi
        else
            print_status "MySQL será instalado"
            read -p "Definir senha para root do MySQL (deixe em branco para gerar): " -s input_db_root
            echo
            MYSQL_ROOT_PASS=${input_db_root:-$(generate_random_password 16)}
        fi
        
        read -p "Senha para usuário do banco de dados (deixe em branco para gerar): " -s input_db_pass
        echo
        DB_PASSWORD=${input_db_pass:-$(generate_random_password 16)}
    fi
    
    # Configurações de domínio e SSL
    if [[ "$ENABLE_SSL" == true || "$INSTALL_NGINX" == true ]]; then
        echo ""
        print_status "Configuração de Domínio e SSL"
        
        read -p "Domínio (ex: vods.seusite.com): " DOMAIN_NAME
        read -p "E-mail para certificados SSL: " EMAIL
        
        if [[ -z "$DOMAIN_NAME" ]]; then
            print_warning "Domínio não informado, SSL não será configurado"
            ENABLE_SSL=false
        elif [[ -z "$EMAIL" ]]; then
            print_warning "E-mail não informado, SSL não será configurado"
            ENABLE_SSL=false
        else
            ENABLE_SSL=true
        fi
    fi
    
    # Resumo da configuração
    echo ""
    print_status "Resumo da Configuração:"
    echo "----------------------------------------"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && echo "API Backend: Sim (Porta: $API_PORT)"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && echo "Painel Web: Sim (Porta: $WEB_PORT)"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && echo "MySQL: Sim"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_NGINX" == true ]] && echo "Nginx: Sim"
    [[ "$ENABLE_SSL" == true ]] && echo "SSL: Sim (Domínio: $DOMAIN_NAME)"
    echo "----------------------------------------"
    
    read -p "Continuar com a instalação? (S/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Instalação cancelada pelo usuário"
        exit 0
    fi
}

update_system() {
    print_status "Atualizando sistema..."
    
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
    
    print_success "Sistema atualizado"
}

install_mysql() {
    if [[ "$INSTALL_MYSQL" == false ]] && [[ "$INSTALL_TYPE" != "full" ]]; then
        return 0
    fi
    
    print_status "Instalando MySQL Server..."
    
    # Instala MySQL Server
    apt-get install -y mysql-server
    
    # Configura o MySQL
    print_status "Configurando MySQL..."
    
    # Inicia o serviço
    systemctl start mysql
    systemctl enable mysql
    
    # Configura segurança
    if [[ -n "$MYSQL_ROOT_PASS" ]]; then
        print_status "Configurando senha root do MySQL..."
        
        # Cria arquivo temporário para configuração
        cat > /tmp/mysql_secure_installation.sql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        
        mysql -u root < /tmp/mysql_secure_installation.sql
        rm /tmp/mysql_secure_installation.sql
        
        # Cria arquivo de opções do MySQL
        cat > /root/.my.cnf << EOF
[client]
user=root
password=$MYSQL_ROOT_PASS
EOF
        
        chmod 600 /root/.my.cnf
    fi
    
    # Cria banco de dados e usuário
    print_status "Criando banco de dados..."
    
    cat > /tmp/create_database.sql << EOF
CREATE DATABASE IF NOT EXISTS $DATABASE_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DATABASE_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DATABASE_NAME.* TO '$DATABASE_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [[ -n "$MYSQL_ROOT_PASS" ]]; then
        mysql -u root -p"$MYSQL_ROOT_PASS" < /tmp/create_database.sql
    else
        mysql -u root < /tmp/create_database.sql
    fi
    
    rm /tmp/create_database.sql
    
    print_success "MySQL instalado e configurado"
}

install_python_dependencies() {
    if [[ "$INSTALL_TYPE" == "web-only" ]]; then
        return 0
    fi
    
    print_status "Instalando Python e dependências..."
    
    # Instala Python 3.8 e ferramentas
    apt-get install -y python3.8 python3.8-dev python3-pip python3.8-venv \
        python3-setuptools python3-wheel build-essential
    
    # Instala dependências do sistema para MySQL
    apt-get install -y libmysqlclient-dev libssl-dev libffi-dev
    
    # Cria ambiente virtual
    print_status "Criando ambiente virtual Python..."
    
    if [[ ! -d "$INSTALL_DIR/venv" ]]; then
        python3.8 -m venv "$INSTALL_DIR/venv"
    fi
    
    # Ativa o ambiente virtual e instala pacotes Python
    source "$INSTALL_DIR/venv/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Instala dependências Python
    print_status "Instalando pacotes Python..."
    
    cat > "$INSTALL_DIR/requirements.txt" << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
mysql-connector-python==8.2.0
pydantic==2.5.0
python-multipart==0.0.6
aiohttp==3.9.1
requests==2.31.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
cryptography==41.0.7
aiosqlite==0.19.0
httpx==0.25.1
pytz==2023.3
colorlog==6.7.0
python-dateutil==2.8.2
pyyaml==6.0.1
celery==5.3.4
redis==5.0.1
flower==2.0.1
EOF
    
    pip install -r "$INSTALL_DIR/requirements.txt"
    
    # Desativa ambiente virtual
    deactivate
    
    print_success "Python e dependências instalados"
}

install_nginx() {
    if [[ "$INSTALL_NGINX" == false ]] && [[ "$INSTALL_TYPE" != "full" ]]; then
        return 0
    fi
    
    print_status "Instalando Nginx..."
    
    apt-get install -y nginx
    
    # Cria estrutura de diretórios
    mkdir -p /var/www/html
    mkdir -p /etc/nginx/ssl
    
    # Configuração básica do Nginx
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    print_success "Nginx instalado"
}

install_nodejs() {
    if [[ "$INSTALL_TYPE" == "api-only" ]]; then
        return 0
    fi
    
    print_status "Instalando Node.js..."
    
    # Instala Node.js 18.x
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Verifica instalação
    node --version
    npm --version
    
    print_success "Node.js instalado"
}

create_service_user() {
    print_status "Criando usuário de serviço..."
    
    if id "$SERVICE_USER" &>/dev/null; then
        print_warning "Usuário $SERVICE_USER já existe"
    else
        useradd -r -s /bin/false -d "$INSTALL_DIR" -m "$SERVICE_USER"
        print_success "Usuário $SERVICE_USER criado"
    fi
    
    # Configura permissões
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"
}

setup_directories() {
    print_status "Criando diretórios do sistema..."
    
    # Diretórios principais
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/scripts"
    
    # Diretórios para a API
    mkdir -p "$INSTALL_DIR/api"
    mkdir -p "$INSTALL_DIR/api/logs"
    mkdir -p "$INSTALL_DIR/api/static"
    mkdir -p "$INSTALL_DIR/api/templates"
    
    # Diretórios para o painel web
    mkdir -p "$INSTALL_DIR/web"
    mkdir -p "$INSTALL_DIR/web/public"
    mkdir -p "$INSTALL_DIR/web/uploads"
    
    # Define permissões
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    print_success "Diretórios criados"
}

setup_api_backend() {
    if [[ "$INSTALL_TYPE" == "web-only" ]]; then
        return 0
    fi
    
    print_status "Configurando API Backend..."
    
    # Cria arquivo de configuração
    cat > "$CONFIG_DIR/api.env" << EOF
# Configurações da API XUI ONE VODs Sync
API_ENV=production
API_HOST=0.0.0.0
API_PORT=$API_PORT
API_WORKERS=4
API_RELOAD=false
API_LOG_LEVEL=info

# Banco de Dados
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DATABASE_NAME
DB_USER=$DATABASE_USER
DB_PASSWORD=$DB_PASSWORD

# Segurança
API_KEY=$API_KEY
JWT_SECRET_KEY=$(generate_random_password 32)
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# URLs
XUI_ONE_URL=http://localhost:8000
XUI_ONE_USERNAME=admin
XUI_ONE_PASSWORD=admin

# Sincronização
SYNC_INTERVAL=3600
MAX_SYNC_WORKERS=3
DEFAULT_LANGUAGE=pt-BR

# Logs
LOG_DIR=$LOG_DIR/api
LOG_FILE=api.log
LOG_ROTATION_SIZE=10MB
LOG_RETENTION_DAYS=30

# Redis (para Celery)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# Configurações de CORS
CORS_ORIGINS=["http://localhost:8080","http://127.0.0.1:8080"]
EOF
    
    # Cria arquivo principal da API
    cat > "$INSTALL_DIR/api/main.py" << 'EOF'
#!/usr/bin/env python3
"""
API Principal - XUI ONE VODs Sync
Ponto de entrada da aplicação
"""
import os
import sys
import logging
from pathlib import Path

# Adiciona diretório pai ao path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.config import settings
from app.main import app

if __name__ == "__main__":
    import uvicorn
    
    logging.basicConfig(
        level=getattr(logging, settings.LOG_LEVEL.upper()),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        workers=settings.API_WORKERS,
        reload=settings.API_RELOAD,
        log_level=settings.LOG_LEVEL.lower()
    )
EOF
    
    # Cria estrutura completa da API
    mkdir -p "$INSTALL_DIR/api/app"
    mkdir -p "$INSTALL_DIR/api/app/core"
    mkdir -p "$INSTALL_DIR/api/app/api"
    mkdir -p "$INSTALL_DIR/api/app/api/v1"
    mkdir -p "$INSTALL_DIR/api/app/api/v1/endpoints"
    mkdir -p "$INSTALL_DIR/api/app/models"
    mkdir -p "$INSTALL_DIR/api/app/schemas"
    mkdir -p "$INSTALL_DIR/api/app/services"
    mkdir -p "$INSTALL_DIR/api/app/utils"
    mkdir -p "$INSTALL_DIR/api/app/db"
    
    # Cria arquivo __init__.py para cada diretório
    for dir in "$INSTALL_DIR/api/app" "$INSTALL_DIR/api/app/core" \
               "$INSTALL_DIR/api/app/api" "$INSTALL_DIR/api/app/api/v1" \
               "$INSTALL_DIR/api/app/api/v1/endpoints" "$INSTALL_DIR/api/app/models" \
               "$INSTALL_DIR/api/app/schemas" "$INSTALL_DIR/api/app/services" \
               "$INSTALL_DIR/api/app/utils" "$INSTALL_DIR/api/app/db"; do
        touch "$dir/__init__.py"
    done
    
    # Cria arquivo de configurações
    cat > "$INSTALL_DIR/api/app/core/config.py" << 'EOF'
"""
Configurações da aplicação
"""
import os
from typing import List, Optional
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

load_dotenv()

class Settings(BaseSettings):
    # API
    API_ENV: str = os.getenv("API_ENV", "development")
    API_HOST: str = os.getenv("API_HOST", "0.0.0.0")
    API_PORT: int = int(os.getenv("API_PORT", 8001))
    API_WORKERS: int = int(os.getenv("API_WORKERS", 4))
    API_RELOAD: bool = os.getenv("API_RELOAD", "false").lower() == "true"
    API_KEY: str = os.getenv("API_KEY", "")
    
    # Banco de Dados
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", 3306))
    DB_USER: str = os.getenv("DB_USER", "xui_one_vods_user")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_NAME: str = os.getenv("DB_NAME", "xui_one_vods")
    
    # Segurança
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "")
    JWT_ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 30))
    
    # URLs
    XUI_ONE_URL: str = os.getenv("XUI_ONE_URL", "http://localhost:8000")
    XUI_ONE_USERNAME: str = os.getenv("XUI_ONE_USERNAME", "admin")
    XUI_ONE_PASSWORD: str = os.getenv("XUI_ONE_PASSWORD", "admin")
    
    # Sincronização
    SYNC_INTERVAL: int = int(os.getenv("SYNC_INTERVAL", 3600))
    MAX_SYNC_WORKERS: int = int(os.getenv("MAX_SYNC_WORKERS", 3))
    DEFAULT_LANGUAGE: str = os.getenv("DEFAULT_LANGUAGE", "pt-BR")
    
    # Logs
    LOG_DIR: str = os.getenv("LOG_DIR", "/var/log/xui-one-vods-sync/api")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "info")
    LOG_FILE: str = os.getenv("LOG_FILE", "api.log")
    
    # CORS
    CORS_ORIGINS: List[str] = os.getenv("CORS_ORIGINS", "http://localhost:8080").split(",")
    
    # Redis
    REDIS_HOST: str = os.getenv("REDIS_HOST", "localhost")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", 6379))
    REDIS_DB: int = int(os.getenv("REDIS_DB", 0))
    
    # Caminhos
    DATA_DIR: str = "/opt/xui-one-vods-sync/data"
    BACKUP_DIR: str = "/opt/xui-one-vods-sync/backups"
    
    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()
EOF
    
    # Cria arquivo principal da aplicação
    cat > "$INSTALL_DIR/api/app/main.py" << 'EOF'
"""
Aplicação FastAPI principal
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager

from app.core.config import settings
from app.api.v1.api import api_router
from app.core.logging import setup_logging
from app.db.session import engine, Base

import logging
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan events for the application
    """
    # Startup
    logger.info("Starting XUI ONE VODs Sync API")
    logger.info(f"Environment: {settings.API_ENV}")
    logger.info(f"Database: {settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}")
    
    # Create database tables
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created/verified")
    except Exception as e:
        logger.error(f"Error creating database tables: {e}")
    
    yield
    
    # Shutdown
    logger.info("Shutting down XUI ONE VODs Sync API")

# Create FastAPI app
app = FastAPI(
    title="XUI ONE VODs Sync API",
    description="API for synchronizing VODs with XUI ONE panel",
    version="2.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan
)

# Setup CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API router
app.include_router(api_router, prefix="/api/v1")

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def root():
    return {
        "message": "XUI ONE VODs Sync API",
        "version": "2.0.0",
        "docs": "/api/docs",
        "health": "/api/v1/health"
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "xui-one-vods-api"}
EOF
    
    # Cria systemd service para a API
    cat > /etc/systemd/system/xui-vods-api.service << EOF
[Unit]
Description=XUI ONE VODs Sync API
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/api
EnvironmentFile=$CONFIG_DIR/api.env
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app.main:app --host \${API_HOST} --port \${API_PORT}
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/api.log
StandardError=append:$LOG_DIR/api-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $INSTALL_DIR/data

[Install]
WantedBy=multi-user.target
EOF
    
    # Cria script de inicialização da API
    cat > "$INSTALL_DIR/scripts/start_api.sh" << 'EOF'
#!/bin/bash
# Script para iniciar a API

source /opt/xui-one-vods-sync/venv/bin/activate
cd /opt/xui-one-vods-sync/api

# Carrega variáveis de ambiente
if [ -f /etc/xui-one-vods-sync/api.env ]; then
    export $(cat /etc/xui-one-vods-sync/api.env | grep -v '^#' | xargs)
fi

# Executa a API
exec python -m uvicorn app.main:app --host $API_HOST --port $API_PORT --workers $API_WORKERS
EOF
    
    chmod +x "$INSTALL_DIR/scripts/start_api.sh"
    
    print_success "API Backend configurada"
}

setup_web_panel() {
    if [[ "$INSTALL_TYPE" == "api-only" ]]; then
        return 0
    fi
    
    print_status "Configurando Painel Web..."
    
    # Cria arquivo de configuração do painel web
    cat > "$CONFIG_DIR/web.env" << EOF
# Configurações do Painel Web
WEB_PORT=$WEB_PORT
API_URL=http://localhost:$API_PORT
API_KEY=$API_KEY
SESSION_SECRET=$(generate_random_password 32)

# Configurações de UI
SITE_NAME=XUI ONE VODs Sync
SITE_DESCRIPTION=Sistema de Sincronização de VODs
DEFAULT_THEME=dark

# Configurações de Email
SMTP_HOST=localhost
SMTP_PORT=25
SMTP_USER=
SMTP_PASSWORD=
EMAIL_FROM=noreply@localhost

# Configurações de Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30
EOF
    
    # Cria estrutura do painel web
    cat > "$INSTALL_DIR/web/package.json" << 'EOF'
{
  "name": "xui-one-vods-panel",
  "version": "2.0.0",
  "description": "Painel de administração para XUI ONE VODs Sync",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "build": "webpack --mode production",
    "install-deps": "npm install"
  },
  "dependencies": {
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "connect-redis": "^7.0.0",
    "redis": "^4.6.7",
    "axios": "^1.6.0",
    "bcryptjs": "^2.4.3",
    "dotenv": "^16.3.1",
    "ejs": "^3.1.9",
    "helmet": "^7.0.0",
    "morgan": "^1.10.0",
    "cors": "^2.8.5",
    "compression": "^1.7.4",
    "express-rate-limit": "^6.10.0",
    "express-validator": "^7.0.1",
    "multer": "^1.4.5-lts.1",
    "jsonwebtoken": "^9.0.2",
    "winston": "^3.10.0",
    "socket.io": "^4.7.2",
    "socket.io-client": "^4.7.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "webpack": "^5.88.2",
    "webpack-cli": "^5.1.4",
    "css-loader": "^6.8.1",
    "style-loader": "^3.3.3",
    "file-loader": "^6.2.0"
  },
  "engines": {
    "node": ">=18.0.0"
  },
  "author": "XUI ONE Team",
  "license": "MIT"
}
EOF
    
    # Cria servidor web básico
    cat > "$INSTALL_DIR/web/server.js" << 'EOF'
const express = require('express');
const path = require('path');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const compression = require('compression');
require('dotenv').config();

const app = express();
const PORT = process.env.WEB_PORT || 8080;

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Configurações
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Servir arquivos estáticos
app.use(express.static(path.join(__dirname, 'public')));

// Rotas básicas
app.get('/', (req, res) => {
  res.render('index', {
    title: 'XUI ONE VODs Sync',
    apiUrl: process.env.API_URL || 'http://localhost:8001'
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'xui-one-vods-web',
    version: '2.0.0'
  });
});

// Inicia servidor
app.listen(PORT, () => {
  console.log(`XUI ONE VODs Web Panel running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`API URL: ${process.env.API_URL || 'Not configured'}`);
});
EOF
    
    # Cria arquivo HTML/EJS básico
    mkdir -p "$INSTALL_DIR/web/views"
    cat > "$INSTALL_DIR/web/views/index.ejs" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><%= title %> - Painel de Controle</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary-color: #3498db;
            --dark-bg: #1a1a2e;
        }
        body {
            background-color: #f8f9fa;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .login-container {
            max-width: 400px;
            margin: 100px auto;
            padding: 30px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .brand-title {
            color: var(--primary-color);
            font-weight: bold;
            margin-bottom: 30px;
        }
        .btn-primary {
            background-color: var(--primary-color);
            border-color: var(--primary-color);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="login-container">
            <h2 class="text-center brand-title">
                <i class="fas fa-film"></i> XUI ONE VODs
            </h2>
            <p class="text-center text-muted mb-4">Sincronizador de Catálogo</p>
            
            <div class="text-center mb-4">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">Carregando...</span>
                </div>
                <p class="mt-2">Inicializando sistema...</p>
            </div>
            
            <div id="loginForm" style="display: none;">
                <form id="loginFormElement">
                    <div class="mb-3">
                        <label for="username" class="form-label">Usuário</label>
                        <input type="text" class="form-control" id="username" required>
                    </div>
                    <div class="mb-3">
                        <label for="password" class="form-label">Senha</label>
                        <input type="password" class="form-control" id="password" required>
                    </div>
                    <div class="d-grid">
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-sign-in-alt me-2"></i> Entrar
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <script>
        // Verifica status da API
        async function checkAPIStatus() {
            try {
                const response = await fetch('<%= apiUrl %>/health');
                if (response.ok) {
                    document.querySelector('.spinner-border').style.display = 'none';
                    document.getElementById('loginForm').style.display = 'block';
                    document.querySelector('.text-center p').textContent = 'Sistema pronto para uso';
                }
            } catch (error) {
                setTimeout(checkAPIStatus, 3000);
            }
        }
        
        // Inicia verificação
        checkAPIStatus();
        
        // Formulário de login
        document.getElementById('loginFormElement')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            // Implementar login
            alert('Sistema em desenvolvimento. Use as credenciais padrão.');
        });
    </script>
</body>
</html>
EOF
    
    # Cria systemd service para o painel web
    cat > /etc/systemd/system/xui-vods-web.service << EOF
[Unit]
Description=XUI ONE VODs Sync Web Panel
After=network.target xui-vods-api.service
Requires=xui-vods-api.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/web
EnvironmentFile=$CONFIG_DIR/web.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/web.log
StandardError=append:$LOG_DIR/web-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $INSTALL_DIR/web/uploads

[Install]
WantedBy=multi-user.target
EOF
    
    # Instala dependências Node.js
    print_status "Instalando dependências Node.js..."
    cd "$INSTALL_DIR/web"
    npm install --production
    
    print_success "Painel Web configurado"
}

setup_nginx_config() {
    if [[ "$INSTALL_NGINX" == false ]] && [[ "$INSTALL_TYPE" != "full" ]]; then
        return 0
    fi
    
    print_status "Configurando Nginx..."
    
    # Remove configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    if [[ "$ENABLE_SSL" == true ]] && [[ -n "$DOMAIN_NAME" ]]; then
        # Configuração com SSL
        cat > /etc/nginx/sites-available/xui-vods-sync << EOF
# XUI ONE VODs Sync - Nginx Configuration with SSL
upstream api_backend {
    server 127.0.0.1:$API_PORT;
    keepalive 32;
}

upstream web_frontend {
    server 127.0.0.1:$WEB_PORT;
    keepalive 32;
}

# HTTP Redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;
    
    # ACME Challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN_NAME/chain.pem;
    
    # SSL Protocols
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # SSL Session
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    # Root location
    root /var/www/html;
    index index.html;
    
    # API Proxy
    location /api/ {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # CORS
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
    
    # Web Panel Proxy
    location / {
        proxy_pass http://web_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Compression
        gzip on;
        gzip_vary on;
        gzip_min_length 1024;
        gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    }
    
    # Static Files
    location /static/ {
        alias $INSTALL_DIR/api/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Logs
    access_log /var/log/nginx/xui-vods-access.log;
    error_log /var/log/nginx/xui-vods-error.log;
}
EOF
    else
        # Configuração sem SSL (HTTP apenas)
        cat > /etc/nginx/sites-available/xui-vods-sync << EOF
# XUI ONE VODs Sync - Nginx Configuration (HTTP)
upstream api_backend {
    server 127.0.0.1:$API_PORT;
    keepalive 32;
}

upstream web_frontend {
    server 127.0.0.1:$WEB_PORT;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    
    # Root location
    root /var/www/html;
    index index.html;
    
    # API Proxy
    location /api/ {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # CORS
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
    
    # Web Panel Proxy
    location / {
        proxy_pass http://web_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Static Files
    location /static/ {
        alias $INSTALL_DIR/api/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Logs
    access_log /var/log/nginx/xui-vods-access.log;
    error_log /var/log/nginx/xui-vods-error.log;
}
EOF
    fi
    
    # Habilita o site
    ln -sf /etc/nginx/sites-available/xui-vods-sync /etc/nginx/sites-enabled/
    
    # Testa configuração do Nginx
    nginx -t
    
    print_success "Nginx configurado"
}

setup_ssl_certificate() {
    if [[ "$ENABLE_SSL" != true ]] || [[ -z "$DOMAIN_NAME" ]] || [[ -z "$EMAIL" ]]; then
        return 0
    fi
    
    print_status "Configurando certificado SSL com Let's Encrypt..."
    
    # Instala Certbot
    apt-get install -y certbot python3-certbot-nginx
    
    # Obtém certificado
    certbot certonly --nginx --non-interactive --agree-tos \
        --email "$EMAIL" \
        -d "$DOMAIN_NAME" \
        --redirect \
        --hsts \
        --uir \
        --staple-ocsp
    
    # Configura renovação automática
    echo "0 12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew
    
    print_success "Certificado SSL configurado"
}

setup_firewall() {
    print_status "Configurando firewall (UFW)..."
    
    # Instala UFW se não estiver instalado
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw
    fi
    
    # Configura regras básicas
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Portas necessárias
    ufw allow ssh
    ufw allow http
    ufw allow https
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]]; then
        ufw allow "$API_PORT/tcp"
    fi
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]]; then
        ufw allow "$WEB_PORT/tcp"
    fi
    
    # Habilita UFW
    ufw --force enable
    
    # Verifica status
    ufw status verbose
    
    print_success "Firewall configurado"
}

setup_redis() {
    print_status "Configurando Redis..."
    
    # Instala Redis
    apt-get install -y redis-server
    
    # Configura Redis
    sed -i 's/supervised no/supervised systemd/' /etc/redis/redis.conf
    sed -i 's/# maxmemory <bytes>/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    # Reinicia Redis
    systemctl restart redis-server
    systemctl enable redis-server
    
    print_success "Redis configurado"
}

setup_backup_system() {
    print_status "Configurando sistema de backup..."
    
    # Cria script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << EOF
#!/bin/bash
# Script de backup para XUI ONE VODs Sync

BACKUP_DIR="$INSTALL_DIR/backups"
LOG_FILE="$LOG_DIR/backup.log"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="xui-vods-backup_\$DATE.tar.gz"
RETENTION_DAYS=30

# Cria backup
echo "\$(date): Iniciando backup" >> "\$LOG_FILE"

# Backup do banco de dados
mysqldump -u$DATABASE_USER -p$DB_PASSWORD $DATABASE_NAME > /tmp/db_backup.sql

# Cria arquivo compactado
tar -czf "\$BACKUP_DIR/\$BACKUP_FILE" \
    -C /tmp db_backup.sql \
    -C "$CONFIG_DIR" . \
    -C "$INSTALL_DIR/data" .

# Limpa backup temporário
rm -f /tmp/db_backup.sql

# Remove backups antigos
find "\$BACKUP_DIR" -name "xui-vods-backup_*.tar.gz" -mtime +\$RETENTION_DAYS -delete

echo "\$(date): Backup concluído: \$BACKUP_FILE" >> "\$LOG_FILE"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    # Configura cron job para backup diário
    echo "0 2 * * * $SERVICE_USER $INSTALL_DIR/scripts/backup.sh" > /etc/cron.d/xui-vods-backup
    
    print_success "Sistema de backup configurado"
}

setup_monitoring() {
    print_status "Configurando monitoramento..."
    
    # Instala ferramentas de monitoramento
    apt-get install -y htop net-tools
    
    # Cria script de status
    cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
# Script para verificar status do sistema

echo "=== XUI ONE VODs Sync Status ==="
echo "Data/Hora: $(date)"
echo ""

# Verifica serviços
echo "1. Serviços do Sistema:"
systemctl is-active --quiet xui-vods-api && echo "  API: ✅ Ativo" || echo "  API: ❌ Inativo"
systemctl is-active --quiet xui-vods-web && echo "  Web: ✅ Ativo" || echo "  Web: ❌ Inativo"
systemctl is-active --quiet mysql && echo "  MySQL: ✅ Ativo" || echo "  MySQL: ❌ Inativo"
systemctl is-active --quiet nginx && echo "  Nginx: ✅ Ativo" || echo "  Nginx: ❌ Inativo"
systemctl is-active --quiet redis-server && echo "  Redis: ✅ Ativo" || echo "  Redis: ❌ Inativo"
echo ""

# Verifica portas
echo "2. Portas em Uso:"
netstat -tlnp | grep -E ":$API_PORT|:$WEB_PORT|:80|:443|:3306|:6379"
echo ""

# Verifica espaço em disco
echo "3. Espaço em Disco:"
df -h / /opt /var
echo ""

# Verifica logs recentes
echo "4. Logs Recentes (últimas 10 linhas):"
tail -10 /var/log/xui-one-vods-sync/api.log 2>/dev/null || echo "  Log da API não encontrado"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/status.sh"
    
    # Cria script de diagnóstico
    cat > "$INSTALL_DIR/scripts/diagnose.sh" << 'EOF'
#!/bin/bash
# Script de diagnóstico do sistema

LOG_DIR="/var/log/xui-one-vods-sync"
DIAG_FILE="$LOG_DIR/diagnose_$(date +%Y%m%d_%H%M%S).log"

{
    echo "=== Diagnóstico XUI ONE VODs Sync ==="
    echo "Data/Hora: $(date)"
    echo ""
    
    echo "1. Informações do Sistema:"
    uname -a
    echo ""
    
    echo "2. Uso de Memória:"
    free -h
    echo ""
    
    echo "3. Uso de CPU:"
    top -bn1 | head -20
    echo ""
    
    echo "4. Serviços:"
    systemctl list-units --type=service | grep -E "xui|mysql|nginx|redis"
    echo ""
    
    echo "5. Logs de Erro (últimas 50 linhas):"
    journalctl -u xui-vods-api -u xui-vods-web --since "1 hour ago" -n 50
    echo ""
    
    echo "6. Conexões de Rede:"
    ss -tulpn | grep -E ":$API_PORT|:$WEB_PORT"
    echo ""
    
    echo "7. Permissões de Diretórios:"
    ls -la /opt/xui-one-vods-sync/
    echo ""
    
    echo "8. Configurações:"
    echo "API_PORT: $API_PORT"
    echo "WEB_PORT: $WEB_PORT"
    echo "DB_HOST: localhost"
    echo ""
    
} > "$DIAG_FILE"

echo "Diagnóstico salvo em: $DIAG_FILE"
cat "$DIAG_FILE"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/diagnose.sh"
    
    print_success "Monitoramento configurado"
}

start_services() {
    print_status "Iniciando serviços..."
    
    # Recarrega systemd
    systemctl daemon-reload
    
    # Habilita e inicia serviços
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]]; then
        systemctl enable xui-vods-api
        systemctl start xui-vods-api
        sleep 3
        
        # Verifica status
        if systemctl is-active --quiet xui-vods-api; then
            print_success "API Backend iniciada"
        else
            print_error "Falha ao iniciar API Backend"
            journalctl -u xui-vods-api -n 20 --no-pager
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]]; then
        systemctl enable xui-vods-web
        systemctl start xui-vods-web
        sleep 2
        
        if systemctl is-active --quiet xui-vods-web; then
            print_success "Painel Web iniciado"
        else
            print_error "Falha ao iniciar Painel Web"
            journalctl -u xui-vods-web -n 20 --no-pager
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_NGINX" == true ]]; then
        systemctl enable nginx
        systemctl restart nginx
        
        if systemctl is-active --quiet nginx; then
            print_success "Nginx iniciado"
        else
            print_error "Falha ao iniciar Nginx"
            nginx -t
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]]; then
        systemctl enable mysql
        systemctl restart mysql
        print_success "MySQL iniciado"
    fi
}

show_installation_summary() {
    print_header
    echo -e "${GREEN}✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
    echo ""
    echo "=============================================="
    echo "         RESUMO DA INSTALAÇÃO"
    echo "=============================================="
    echo ""
    
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && \
    echo "🌐 API Backend:"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && \
    echo "   URL: http://$(hostname -I | awk '{print $1}'):$API_PORT"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && \
    echo "   Documentação: http://$(hostname -I | awk '{print $1}'):$API_PORT/api/docs"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && \
    echo "   Chave API: $API_KEY"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && echo ""
    
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && \
    echo "🖥️  Painel Web:"
    if [[ "$ENABLE_SSL" == true ]] && [[ -n "$DOMAIN_NAME" ]]; then
        [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && \
        echo "   URL: https://$DOMAIN_NAME"
    else
        [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && \
        echo "   URL: http://$(hostname -I | awk '{print $1}'):$WEB_PORT"
    fi
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && echo ""
    
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && \
    echo "🗄️  Banco de Dados:"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && \
    echo "   Nome: $DATABASE_NAME"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && \
    echo "   Usuário: $DATABASE_USER"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && \
    echo "   Senha: $DB_PASSWORD"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_MYSQL" == true ]] && echo ""
    
    echo "📁 Diretórios:"
    echo "   Instalação: $INSTALL_DIR"
    echo "   Configuração: $CONFIG_DIR"
    echo "   Logs: $LOG_DIR"
    echo "   Backups: $INSTALL_DIR/backups"
    echo ""
    
    echo "⚙️  Comandos Úteis:"
    echo "   Verificar status: $INSTALL_DIR/scripts/status.sh"
    echo "   Diagnóstico: $INSTALL_DIR/scripts/diagnose.sh"
    echo "   Backup manual: $INSTALL_DIR/scripts/backup.sh"
    echo ""
    echo "   Iniciar/Parar API: systemctl start|stop|restart xui-vods-api"
    echo "   Iniciar/Parar Web: systemctl start|stop|restart xui-vods-web"
    echo ""
    
    echo "📋 Logs do Sistema:"
    echo "   API: journalctl -u xui-vods-api -f"
    echo "   Web: journalctl -u xui-vods-web -f"
    echo "   Nginx: tail -f /var/log/nginx/xui-vods-*.log"
    echo ""
    
    echo "🔧 Arquivos de Configuração:"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]] && \
    echo "   API: $CONFIG_DIR/api.env"
    [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]] && \
    echo "   Web: $CONFIG_DIR/web.env"
    echo ""
    
    echo "=============================================="
    echo "👤 Credenciais Padrão:"
    echo "   Painel Web: admin / admin123"
    echo "   API: Use a chave API acima"
    echo ""
    echo "⚠️  ALTERE AS CREDENCIAIS PADRÃO IMEDIATAMENTE!"
    echo "=============================================="
    echo ""
    
    # Salva resumo em arquivo
    cat > "$INSTALL_DIR/INSTALL_SUMMARY.txt" << EOF
XUI ONE VODs Sync - Resumo da Instalação
========================================
Data da Instalação: $(date)
Versão do Instalador: $SCRIPT_VERSION

CONFIGURAÇÕES:
---------------
API Backend:
  URL: http://$(hostname -I | awk '{print $1}'):$API_PORT
  Docs: http://$(hostname -I | awk '{print $1}'):$API_PORT/api/docs
  API Key: $API_KEY

Painel Web:
  URL: $(if [[ "$ENABLE_SSL" == true ]] && [[ -n "$DOMAIN_NAME" ]]; then echo "https://$DOMAIN_NAME"; else echo "http://$(hostname -I | awk '{print $1}'):$WEB_PORT"; fi)

Banco de Dados:
  Nome: $DATABASE_NAME
  Usuário: $DATABASE_USER
  Senha: $DB_PASSWORD

DIRETÓRIOS:
-----------
Instalação: $INSTALL_DIR
Configuração: $CONFIG_DIR
Logs: $LOG_DIR
Backups: $INSTALL_DIR/backups

COMANDOS ÚTEIS:
---------------
Status: $INSTALL_DIR/scripts/status.sh
Diagnóstico: $INSTALL_DIR/scripts/diagnose.sh
Backup: $INSTALL_DIR/scripts/backup.sh

SERVIÇOS:
---------
API: systemctl start|stop|restart xui-vods-api
Web: systemctl start|stop|restart xui-vods-web

LOGS:
-----
API: journalctl -u xui-vods-api -f
Web: journalctl -u xui-vods-web -f
Nginx: tail -f /var/log/nginx/xui-vods-*.log

CREDENCIAIS PADRÃO:
-------------------
Painel Web: admin / admin123
API: Use a chave API acima

⚠️ IMPORTANTE: Altere as credenciais padrão imediatamente!

EOF
    
    echo "📄 Resumo salvo em: $INSTALL_DIR/INSTALL_SUMMARY.txt"
    echo ""
    
    # Testa serviços
    echo "🧪 Testando serviços..."
    sleep 2
    
    # Testa API
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_API" == true ]]; then
        if curl -s http://localhost:$API_PORT/health > /dev/null 2>&1; then
            echo "✅ API está respondendo"
        else
            echo "⚠️  API não está respondendo, verifique os logs"
        fi
    fi
    
    # Testa Web
    if [[ "$INSTALL_TYPE" == "full" || "$INSTALL_WEB" == true ]]; then
        if curl -s http://localhost:$WEB_PORT/health > /dev/null 2>&1; then
            echo "✅ Painel Web está respondendo"
        else
            echo "⚠️  Painel Web não está respondendo, verifique os logs"
        fi
    fi
    
    echo ""
    echo "🎉 Instalação finalizada!"
    echo ""
    
    # Mostra avisos importantes
    print_warning "IMPORTANTE:"
    echo "1. Altere as senhas padrão imediatamente"
    echo "2. Configure o backup regular"
    echo "3. Mantenha o sistema atualizado"
    echo "4. Configure monitoramento"
    echo ""
}

cleanup() {
    print_status "Limpando arquivos temporários..."
    
    # Remove arquivos temporários
    rm -f /tmp/mysql_secure_installation.sql
    rm -f /tmp/create_database.sql
    
    # Limpa cache apt
    apt-get autoremove -y
    apt-get clean
    
    print_success "Limpeza concluída"
}

main() {
    print_header
    
    # Verifica root
    check_root
    
    # Verifica sistema operacional
    check_os
    
    # Verifica dependências
    check_dependencies
    
    # Obtém tipo de instalação
    get_install_type
    
    # Obtém configurações
    get_configuration
    
    # Atualiza sistema
    update_system
    
    # Instala MySQL
    install_mysql
    
    # Instala Python
    install_python_dependencies
    
    # Instala Nginx
    install_nginx
    
    # Instala Node.js
    install_nodejs
    
    # Cria usuário de serviço
    create_service_user
    
    # Cria diretórios
    setup_directories
    
    # Configura API
    setup_api_backend
    
    # Configura Painel Web
    setup_web_panel
    
    # Configura Redis
    setup_redis
    
    # Configura Nginx
    setup_nginx_config
    
    # Configura SSL
    setup_ssl_certificate
    
    # Configura firewall
    setup_firewall
    
    # Configura backup
    setup_backup_system
    
    # Configura monitoramento
    setup_monitoring
    
    # Inicia serviços
    start_services
    
    # Limpeza
    cleanup
    
    # Mostra resumo
    show_installation_summary
    
    # Log da instalação
    print_status "Log da instalação salvo em: $LOG_DIR/install.log"
}

# Executa a instalação
main 2>&1 | tee "$LOG_DIR/install.log"

exit 0
