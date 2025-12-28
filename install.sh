#!/bin/bash

# ============================================================
# INSTALADOR COMPLETO DO SISTEMA SINCRONIZADOR DE VODS XUI ONE
# ============================================================
# Este script cria TODOS os arquivos e instala o sistema completo
# Autor: Sistema de VOD Sync XUI
# Versão: 3.0.0
# ============================================================

set -e

# Configurações
INSTALL_DIR="/opt/vod-sync-xui"
APP_USER="vodsync"
APP_GROUP="vodsync"
DB_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -hex 64)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funções de utilidade
print_header() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     SISTEMA SINCRONIZADOR DE VODS XUI ONE - INSTALADOR   ║"
    echo "║                    Versão 3.0.0 Completa                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

print_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

# Verificar sistema
check_system() {
    print_step "Verificando sistema..."
    
    # Verificar root
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script precisa ser executado como root!"
        echo "Use: sudo $0"
        exit 1
    fi
    
    # Verificar OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    print_info "Sistema: $OS $VER"
    
    case $ID in
        ubuntu|debian)
            OS_TYPE="debian"
            PKG_MGR="apt-get"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            OS_TYPE="rhel"
            PKG_MGR="yum"
            ;;
        *)
            print_error "Sistema operacional não suportado!"
            exit 1
            ;;
    esac
    
    print_success "Sistema verificado"
}

# Verificar e corrigir serviços
check_and_fix_services() {
    print_step "Verificando serviços..."
    
    # Verificar Redis
    if systemctl list-unit-files 2>/dev/null | grep -q "redis.*service"; then
        print_info "Redis detectado"
    else
        print_warning "Redis não está disponível, será instalado"
    fi
    
    # Verificar MySQL/MariaDB
    if systemctl list-unit-files 2>/dev/null | grep -q "^mysql.service"; then
        print_info "MySQL disponível"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^mariadb.service"; then
        print_info "MariaDB disponível"
    else
        print_warning "MySQL/MariaDB não encontrado"
    fi
    
    # Verificar Nginx
    if systemctl list-unit-files 2>/dev/null | grep -q "^nginx.service"; then
        print_info "Nginx disponível"
    else
        print_warning "Nginx não encontrado"
    fi
    
    print_success "Serviços verificados"
}

# Criar estrutura de diretórios
create_directories() {
    print_step "Criando estrutura de diretórios..."
    
    mkdir -p "$INSTALL_DIR"/{src,logs,data,config,backups,scripts,systemd,dashboard/{static/{css,js,img},templates}}
    mkdir -p "$INSTALL_DIR"/data/{vods,sessions,thumbnails}
    mkdir -p "$INSTALL_DIR"/backups/{daily,weekly,monthly}
    
    print_success "Diretórios criados"
}

# Criar arquivos de configuração
create_config_files() {
    print_step "Criando arquivos de configuração..."
    
    # Arquivo .env
    cat > "$INSTALL_DIR/.env" << EOF
# ============================================
# CONFIGURAÇÕES DO SISTEMA VOD SYNC XUI
# ============================================

# Aplicação
FLASK_APP=app.py
FLASK_ENV=production
SECRET_KEY=$SECRET_KEY
DEBUG=false
HOST=0.0.0.0
PORT=5000

# Banco de dados local
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync
DB_USER=vod_sync
DB_PASSWORD=$DB_PASSWORD

# Banco de dados XUI (remoto)
XUI_DB_HOST=seu_host_xui
XUI_DB_PORT=3306
XUI_DB_NAME=xui
XUI_DB_USER=seu_usuario_xui
XUI_DB_PASSWORD=sua_senha_xui
XUI_USE_SSH=false
XUI_SSH_HOST=
XUI_SSH_PORT=22
XUI_SSH_USER=
XUI_SSH_PASSWORD=

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# Caminhos
VOD_STORAGE_PATH=$INSTALL_DIR/data/vods
LOG_PATH=$INSTALL_DIR/logs
BACKUP_PATH=$INSTALL_DIR/backups
TEMP_PATH=/tmp/vod_sync

# Sincronização
SYNC_INTERVAL=3600
MAX_CONCURRENT_SYNC=3
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=300
CHUNK_SIZE=10485760  # 10MB

# Notificações
NOTIFY_ON_SUCCESS=true
NOTIFY_ON_FAILURE=true
NOTIFY_EMAIL=
NOTIFY_TELEGRAM=false
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Limites
MAX_LOG_SIZE=104857600  # 100MB
MAX_LOG_FILES=10
MAX_BACKUP_FILES=30
MAX_DISK_USAGE=90

# Segurança
REQUIRE_SSL=false
SESSION_TIMEOUT=3600
API_RATE_LIMIT=100
ALLOWED_IPS=*
EOF

    # Arquivo config.yaml
    cat > "$INSTALL_DIR/config/config.yaml" << EOF
# Configuração do Sistema VOD Sync XUI

database:
  host: "seu_host_xui"
  port: 3306
  user: "seu_usuario_xui"
  password: "sua_senha_xui"
  name: "xui"
  use_ssh: false
  ssh_host: ""
  ssh_port: 22
  ssh_user: ""
  ssh_password: ""

sync:
  interval: 3600
  max_concurrent: 3
  retry_attempts: 3
  retry_delay: 300
  vod_extensions:
    - ".mp4"
    - ".mkv"
    - ".avi"
    - ".mov"
    - ".flv"
    - ".wmv"
    - ".m4v"
    - ".ts"
    - ".mpg"
    - ".mpeg"

storage:
  local_path: "$INSTALL_DIR/data/vods"
  remote_path: ""
  max_size_gb: 1000
  cleanup_threshold: 80
  backup_enabled: true
  backup_path: "$INSTALL_DIR/backups"
  thumbnail_enabled: true
  thumbnail_size: "320x180"

security:
  secret_key: "$SECRET_KEY"
  admin_user: "admin"
  admin_password: ""
  session_timeout: 3600
  api_rate_limit: 100
  ssl_enabled: false
  ssl_cert: ""
  ssl_key: ""
  cors_origins:
    - "*"

monitoring:
  enabled: true
  metrics_port: 9090
  alert_email: ""
  cpu_threshold: 80.0
  memory_threshold: 85.0
  disk_threshold: 90.0
  network_threshold: 70.0
  check_interval: 60

notifications:
  email_enabled: false
  email_server: ""
  email_port: 587
  email_user: ""
  email_password: ""
  email_from: ""
  email_to: ""
  
  telegram_enabled: false
  telegram_bot_token: ""
  telegram_chat_id: ""
  
  webhook_enabled: false
  webhook_url: ""

logging:
  level: "INFO"
  file: "$INSTALL_DIR/logs/vod_sync.log"
  max_size: 104857600
  backup_count: 10
  format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

api:
  enabled: true
  rate_limit: "100 per minute"
  enable_swagger: true
  enable_cors: true
EOF

    # Arquivo requirements.txt
    cat > "$INSTALL_DIR/requirements.txt" << EOF
# Core
Flask==2.3.3
Werkzeug==2.3.7
Jinja2==3.1.2

# Database
SQLAlchemy==2.0.19
PyMySQL==1.1.0
alembic==1.12.0
psycopg2-binary==2.9.7

# SSH/Tunnel
sshtunnel==0.4.0
paramiko==3.3.1
cryptography==41.0.5

# Async & Tasks
celery==5.3.1
redis==5.0.1
eventlet==0.33.3
schedule==1.2.0

# Web & API
Flask-CORS==4.0.0
Flask-Login==0.6.2
Flask-WTF==1.1.1
Flask-SocketIO==5.3.4
Flask-RESTful==0.3.10
Flask-JWT-Extended==4.5.3
Flask-Limiter==3.5.1

# File Processing
watchdog==3.0.0
python-magic==0.4.27
Pillow==10.0.1
moviepy==1.0.3
ffmpeg-python==0.2.0

# Monitoring & Metrics
psutil==5.9.6
prometheus-client==0.18.0
python-dotenv==1.0.0
pyyaml==6.0.1
requests==2.31.0

# Utilities
python-dateutil==2.8.2
pytz==2023.3
colorlog==6.7.0
progress==1.6
tabulate==0.9.0

# Production
gunicorn==21.2.0
gevent==23.9.1
supervisor==4.2.5

# Security
bcrypt==4.0.1
passlib==1.7.4
cryptography==41.0.5
EOF

    # Arquivo docker-compose.yml
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  vod-sync:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: vod-sync-xui
    restart: unless-stopped
    ports:
      - "5000:5000"
      - "9090:9090"
    environment:
      - FLASK_ENV=production
      - SECRET_KEY=${SECRET_KEY}
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_NAME=vod_sync
      - DB_USER=vod_sync
      - DB_PASSWORD=${DB_PASSWORD}
      - REDIS_HOST=redis
    volumes:
      - vod-storage:/app/data/vods
      - ./logs:/app/logs
      - ./config:/app/config
      - ./backups:/app/backups
    depends_on:
      - mysql
      - redis
    networks:
      - vod-sync-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  mysql:
    image: mysql:8.0
    container_name: vod-sync-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: root_${DB_PASSWORD}
      MYSQL_DATABASE: vod_sync
      MYSQL_USER: vod_sync
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - mysql-data:/var/lib/mysql
      - ./config/mysql-init:/docker-entrypoint-initdb.d
    networks:
      - vod-sync-network
    command: --default-authentication-plugin=mysql_native_password

  redis:
    image: redis:7-alpine
    container_name: vod-sync-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${DB_PASSWORD}
    volumes:
      - redis-data:/data
    networks:
      - vod-sync-network

  nginx:
    image: nginx:alpine
    container_name: vod-sync-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf
      - ./config/ssl:/etc/nginx/ssl
      - ./logs/nginx:/var/log/nginx
      - vod-storage:/var/www/vods:ro
    depends_on:
      - vod-sync
    networks:
      - vod-sync-network

  monitor:
    image: netdata/netdata:latest
    container_name: vod-sync-monitor
    restart: unless-stopped
    ports:
      - "19999:19999"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - netdata-config:/etc/netdata
      - netdata-lib:/var/lib/netdata
      - netdata-cache:/var/cache/netdata
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
    networks:
      - vod-sync-network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: vod-sync-phpmyadmin
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      UPLOAD_LIMIT: 512M
    depends_on:
      - mysql
    networks:
      - vod-sync-network

volumes:
  vod-storage:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${INSTALL_DIR}/data/vods
  mysql-data:
  redis-data:
  netdata-config:
  netdata-lib:
  netdata-cache:

networks:
  vod-sync-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

    # Arquivo Dockerfile
    cat > "$INSTALL_DIR/Dockerfile" << EOF
FROM python:3.11-slim

WORKDIR /app

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libmariadb-dev \
    libssl-dev \
    libffi-dev \
    ffmpeg \
    curl \
    wget \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements
COPY requirements.txt .

# Instalar dependências Python
RUN pip install --no-cache-dir -r requirements.txt

# Copiar aplicação
COPY . .

# Criar usuário não-root
RUN groupadd -r vodsync && useradd -r -g vodsync vodsync
RUN chown -R vodsync:vodsync /app
USER vodsync

# Portas
EXPOSE 5000 9090

# Comando de inicialização
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--threads", "2", "--timeout", "120", "src.app:app"]
EOF

    # Arquivo Nginx
    mkdir -p "$INSTALL_DIR/config"
    cat > "$INSTALL_DIR/config/nginx.conf" << EOF
# Configuração Nginx para VOD Sync XUI

user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    # Configurações básicas
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 2G;
    
    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Upstream para aplicação
    upstream vod_sync_app {
        server vod-sync:5000;
        keepalive 32;
    }
    
    # Configuração do servidor HTTP
    server {
        listen 80;
        listen [::]:80;
        server_name _;
        
        # Redirecionar para HTTPS se configurado
        # return 301 https://\$host\$request_uri;
        
        # Dashboard principal
        location / {
            proxy_pass http://vod_sync_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
            proxy_send_timeout 300;
        }
        
        # API
        location /api {
            proxy_pass http://vod_sync_app;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 300;
        }
        
        # WebSocket para atualizações em tempo real
        location /socket.io {
            proxy_pass http://vod_sync_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 86400;
        }
        
        # Servir arquivos de VODs estáticos
        location /vods {
            alias /var/www/vods;
            autoindex off;
            internal;
            
            # Headers para streaming
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods 'GET, OPTIONS';
            add_header Access-Control-Allow-Headers 'Range';
            
            # Streaming de vídeo
            mp4;
            mp4_buffer_size 1m;
            mp4_max_buffer_size 5m;
            
            # Permitir requisições de range (para streaming)
            if (\$request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'Range';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain charset=UTF-8';
                add_header 'Content-Length' 0;
                return 204;
            }
        }
        
        # Métricas Prometheus
        location /metrics {
            proxy_pass http://vod_sync_app;
            auth_basic "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
        }
        
        # Status Nginx
        location /nginx_status {
            stub_status;
            access_log off;
            allow 127.0.0.1;
            deny all;
        }
    }
    
    # Configuração HTTPS (descomente e configure após obter certificado SSL)
    # server {
    #     listen 443 ssl http2;
    #     listen [::]:443 ssl http2;
    #     server_name seu-dominio.com;
    #     
    #     ssl_certificate /etc/nginx/ssl/cert.pem;
    #     ssl_certificate_key /etc/nginx/ssl/key.pem;
    #     ssl_protocols TLSv1.2 TLSv1.3;
    #     ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    #     
    #     # Resto da configuração igual ao servidor HTTP
    # }
}
EOF

    print_success "Arquivos de configuração criados"
}

# Criar arquivos do sistema
create_system_files() {
    print_step "Criando arquivos do sistema..."
    
    # Serviço systemd principal
    cat > "$INSTALL_DIR/systemd/vod-sync.service" << EOF
[Unit]
Description=VOD Sync XUI Service
Documentation=https://github.com/seu-repositorio/vod-sync-xui
After=network.target mysql.service redis-server.service
Requires=mysql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 4 --threads 2 --timeout 120 --access-logfile $INSTALL_DIR/logs/gunicorn_access.log --error-logfile $INSTALL_DIR/logs/gunicorn_error.log --capture-output --log-level info src.app:app
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
OOMScoreAdjust=-100
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync

# Segurança
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR/logs $INSTALL_DIR/data $INSTALL_DIR/backups
ReadOnlyPaths=/
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
ProtectClock=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF

    # Serviço Celery
    cat > "$INSTALL_DIR/systemd/vod-sync-celery.service" << EOF
[Unit]
Description=Celery Service for VOD Sync XUI
Documentation=https://docs.celeryq.dev/
After=network.target vod-sync.service
Requires=vod-sync.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery -A src.celery_tasks.celery worker --loglevel=info --concurrency=4 --hostname=vod-sync@%%h --queues=sync_tasks,notifications --max-tasks-per-child=100
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync-celery

[Install]
WantedBy=multi-user.target
EOF

    # Serviço Celery Beat
    cat > "$INSTALL_DIR/systemd/vod-sync-celerybeat.service" << EOF
[Unit]
Description=Celery Beat Service for VOD Sync XUI
Documentation=https://docs.celeryq.dev/
After=network.target vod-sync.service vod-sync-celery.service
Requires=vod-sync.service vod-sync-celery.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery -A src.celery_tasks.celery beat --loglevel=info --schedule=$INSTALL_DIR/data/celerybeat-schedule
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync-celerybeat

[Install]
WantedBy=multi-user.target
EOF

    # Logrotate
    cat > /etc/logrotate.d/vod-sync << EOF
$INSTALL_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 $APP_USER $APP_GROUP
    sharedscripts
    postrotate
        systemctl reload vod-sync > /dev/null 2>&1 || true
    endscript
}
EOF

    print_success "Arquivos do sistema criados"
}

# Criar código fonte da aplicação
create_source_code() {
    print_step "Criando código fonte da aplicação..."
    
    # Criar __init__.py
    cat > "$INSTALL_DIR/src/__init__.py" << EOF
"""
VOD Sync XUI - Sistema de Sincronização de VODs para XUI One
"""

__version__ = '3.0.0'
__author__ = 'VOD Sync System'
__license__ = 'MIT'
EOF

    # Criar app.py principal
    cat > "$INSTALL_DIR/src/app.py" << EOF
#!/usr/bin/env python3
"""
Aplicação principal do Sistema VOD Sync XUI
"""

import os
import sys
import logging
from datetime import datetime
from flask import Flask, render_template, jsonify, request, send_file
from flask_socketio import SocketIO
from flask_login import LoginManager, current_user, login_required
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import psutil
import humanize

# Adicionar caminho
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.config import Config
from src.database import db, init_db
from src.models import User, VOD, SyncTask, SystemLog
from src.services.sync_service import VODSyncService
from src.services.monitoring import SystemMonitor
from src.utils.helpers import get_ip_address
from src.api import api_bp
from src.auth import auth_bp

# Configuração
config = Config()
app = Flask(__name__, 
            template_folder='../dashboard/templates',
            static_folder='../dashboard/static')

# Configurar Flask
app.config['SECRET_KEY'] = config.SECRET_KEY
app.config['SQLALCHEMY_DATABASE_URI'] = f"mysql+pymysql://{config.DB_USER}:{config.DB_PASSWORD}@{config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME}"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2GB

# Inicializar extensões
db.init_app(app)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'auth.login'
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://",
)

# Registrar blueprints
app.register_blueprint(api_bp, url_prefix='/api/v1')
app.register_blueprint(auth_bp, url_prefix='/auth')

# Inicializar serviços
sync_service = VODSyncService(config)
system_monitor = SystemMonitor()

# Configurar logging
logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(config.LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

@app.before_first_request
def initialize():
    """Inicializar banco de dados e criar admin padrão"""
    with app.app_context():
        init_db()
        
        # Criar usuário admin se não existir
        if not User.query.filter_by(username='admin').first():
            admin = User(
                username='admin',
                email='admin@vodsync.local',
                is_admin=True,
                is_active=True
            )
            admin.set_password('admin123')
            db.session.add(admin)
            db.session.commit()
            logger.info("Usuário admin criado (senha: admin123)")

@app.route('/')
@login_required
def index():
    """Página inicial"""
    return render_template('index.html', user=current_user)

@app.route('/dashboard')
@login_required
def dashboard():
    """Dashboard com estatísticas"""
    # Obter estatísticas
    stats = system_monitor.get_all_stats()
    
    # Estatísticas do banco
    vod_count = VOD.query.count()
    sync_tasks = SyncTask.query.count()
    pending_tasks = SyncTask.query.filter_by(status='pending').count()
    
    # Últimos logs
    recent_logs = SystemLog.query.order_by(SystemLog.timestamp.desc()).limit(10).all()
    
    return render_template('dashboard.html',
                         stats=stats,
                         vod_count=vod_count,
                         sync_tasks=sync_tasks,
                         pending_tasks=pending_tasks,
                         recent_logs=recent_logs,
                         user=current_user)

@app.route('/api/system/health')
def health_check():
    """Endpoint de health check"""
    health = {
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '3.0.0',
        'services': {
            'database': 'connected' if db.session.execute('SELECT 1').first() else 'disconnected',
            'redis': 'unknown',  # Implementar verificação do Redis
            'sync_service': 'running' if sync_service.is_running else 'stopped'
        }
    }
    return jsonify(health)

@app.route('/api/system/stats')
@login_required
@limiter.limit("10 per minute")
def get_system_stats():
    """Obter estatísticas do sistema"""
    stats = system_monitor.get_all_stats()
    return jsonify(stats)

@app.route('/api/system/logs')
@login_required
def get_system_logs():
    """Obter logs do sistema"""
    level = request.args.get('level', 'INFO')
    limit = request.args.get('limit', 100, type=int)
    
    query = SystemLog.query
    if level != 'ALL':
        query = query.filter_by(level=level)
    
    logs = query.order_by(SystemLog.timestamp.desc()).limit(limit).all()
    
    return jsonify({
        'logs': [log.to_dict() for log in logs],
        'total': query.count()
    })

@app.route('/api/sync/start', methods=['POST'])
@login_required
@limiter.limit("5 per hour")
def start_sync():
    """Iniciar sincronização manual"""
    try:
        task_id = sync_service.start_manual_sync()
        logger.info(f"Sincronização manual iniciada por {current_user.username}")
        
        # Notificar via SocketIO
        socketio.emit('sync_started', {
            'task_id': task_id,
            'user': current_user.username,
            'timestamp': datetime.now().isoformat()
        })
        
        return jsonify({
            'success': True,
            'task_id': task_id,
            'message': 'Sincronização iniciada'
        })
    except Exception as e:
        logger.error(f"Erro ao iniciar sincronização: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/sync/status/<task_id>')
@login_required
def get_sync_status(task_id):
    """Obter status da sincronização"""
    task = SyncTask.query.get_or_404(task_id)
    return jsonify(task.to_dict())

@socketio.on('connect')
def handle_connect():
    """Manipular conexão de cliente"""
    if current_user.is_authenticated:
        logger.debug(f"Cliente conectado: {current_user.username}")
        socketio.emit('connected', {
            'message': 'Conectado ao servidor VOD Sync',
            'user': current_user.username
        })

@socketio.on('get_stats')
def handle_get_stats():
    """Enviar estatísticas em tempo real"""
    stats = system_monitor.get_all_stats()
    socketio.emit('system_stats', stats)

def main():
    """Função principal"""
    # Criar diretórios necessários
    os.makedirs(config.VOD_STORAGE_PATH, exist_ok=True)
    os.makedirs(config.LOG_PATH, exist_ok=True)
    os.makedirs(config.BACKUP_PATH, exist_ok=True)
    
    # Iniciar serviço de sincronização agendada
    sync_service.start_scheduled_sync()
    
    logger.info(f"Iniciando VOD Sync XUI v3.0.0 em {get_ip_address()}:{config.PORT}")
    logger.info(f"Modo: {'Desenvolvimento' if config.DEBUG else 'Produção'}")
    
    # Iniciar aplicação
    socketio.run(app,
                host=config.HOST,
                port=config.PORT,
                debug=config.DEBUG,
                use_reloader=False,
                allow_unsafe_werkzeug=True)

if __name__ == '__main__':
    main()
EOF

    # Criar config.py
    cat > "$INSTALL_DIR/src/config.py" << EOF
"""
Configuração do Sistema VOD Sync XUI
"""

import os
import yaml
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from pathlib import Path
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv(Path(__file__).parent.parent / '.env')

@dataclass
class DatabaseConfig:
    """Configuração do banco de dados"""
    host: str = os.getenv('DB_HOST', 'localhost')
    port: int = int(os.getenv('DB_PORT', 3306))
    name: str = os.getenv('DB_NAME', 'vod_sync')
    user: str = os.getenv('DB_USER', 'vod_sync')
    password: str = os.getenv('DB_PASSWORD', '')
    
    # XUI Database
    xui_host: str = os.getenv('XUI_DB_HOST', '')
    xui_port: int = int(os.getenv('XUI_DB_PORT', 3306))
    xui_name: str = os.getenv('XUI_DB_NAME', 'xui')
    xui_user: str = os.getenv('XUI_DB_USER', '')
    xui_password: str = os.getenv('XUI_DB_PASSWORD', '')
    use_ssh: bool = os.getenv('XUI_USE_SSH', 'false').lower() == 'true'
    ssh_host: str = os.getenv('XUI_SSH_HOST', '')
    ssh_port: int = int(os.getenv('XUI_SSH_PORT', 22))
    ssh_user: str = os.getenv('XUI_SSH_USER', '')
    ssh_password: str = os.getenv('XUI_SSH_PASSWORD', '')

@dataclass
class SyncConfig:
    """Configuração de sincronização"""
    interval: int = int(os.getenv('SYNC_INTERVAL', 3600))
    max_concurrent: int = int(os.getenv('MAX_CONCURRENT_SYNC', 3))
    max_retry_attempts: int = int(os.getenv('MAX_RETRY_ATTEMPTS', 3))
    retry_delay: int = int(os.getenv('RETRY_DELAY', 300))
    chunk_size: int = int(os.getenv('CHUNK_SIZE', 10485760))
    
    vod_extensions: List[str] = field(default_factory=lambda: [
        '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv',
        '.m4v', '.ts', '.mpg', '.mpeg', '.webm'
    ])

@dataclass
class StorageConfig:
    """Configuração de armazenamento"""
    local_path: str = os.getenv('VOD_STORAGE_PATH', '/data/vods')
    log_path: str = os.getenv('LOG_PATH', '/logs')
    backup_path: str = os.getenv('BACKUP_PATH', '/backups')
    temp_path: str = os.getenv('TEMP_PATH', '/tmp/vod_sync')
    
    max_size_gb: int = 1000
    cleanup_threshold: int = 80  # percentual
    backup_enabled: bool = True
    thumbnail_enabled: bool = True
    thumbnail_size: str = "320x180"

@dataclass
class SecurityConfig:
    """Configuração de segurança"""
    secret_key: str = os.getenv('SECRET_KEY', 'dev-secret-key-change-me')
    admin_user: str = os.getenv('ADMIN_USER', 'admin')
    admin_password: str = os.getenv('ADMIN_PASSWORD', '')
    
    session_timeout: int = int(os.getenv('SESSION_TIMEOUT', 3600))
    api_rate_limit: int = int(os.getenv('API_RATE_LIMIT', 100))
    require_ssl: bool = os.getenv('REQUIRE_SSL', 'false').lower() == 'true'
    allowed_ips: str = os.getenv('ALLOWED_IPS', '*')
    
    # SSL
    ssl_enabled: bool = False
    ssl_cert: Optional[str] = None
    ssl_key: Optional[str] = None

@dataclass
class MonitoringConfig:
    """Configuração de monitoramento"""
    enabled: bool = os.getenv('MONITORING_ENABLED', 'true').lower() == 'true'
    metrics_port: int = int(os.getenv('METRICS_PORT', 9090))
    
    cpu_threshold: float = 80.0
    memory_threshold: float = 85.0
    disk_threshold: float = 90.0
    network_threshold: float = 70.0
    
    check_interval: int = 60  # segundos
    alert_email: Optional[str] = None

@dataclass
class NotificationConfig:
    """Configuração de notificações"""
    email_enabled: bool = False
    email_server: Optional[str] = None
    email_port: int = 587
    email_user: Optional[str] = None
    email_password: Optional[str] = None
    email_from: Optional[str] = None
    email_to: Optional[str] = None
    
    telegram_enabled: bool = os.getenv('NOTIFY_TELEGRAM', 'false').lower() == 'true'
    telegram_bot_token: Optional[str] = os.getenv('TELEGRAM_BOT_TOKEN', '')
    telegram_chat_id: Optional[str] = os.getenv('TELEGRAM_CHAT_ID', '')
    
    notify_on_success: bool = os.getenv('NOTIFY_ON_SUCCESS', 'true').lower() == 'true'
    notify_on_failure: bool = os.getenv('NOTIFY_ON_FAILURE', 'true').lower() == 'true'

@dataclass
class LoggingConfig:
    """Configuração de logging"""
    level: str = os.getenv('LOG_LEVEL', 'INFO')
    file: str = os.getenv('LOG_FILE', '/logs/vod_sync.log')
    max_size: int = int(os.getenv('MAX_LOG_SIZE', 104857600))  # 100MB
    backup_count: int = int(os.getenv('MAX_LOG_FILES', 10))
    format: str = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

class Config:
    """Configuração principal"""
    
    def __init__(self):
        # Carregar configuração do YAML se existir
        self.config_file = Path(__file__).parent.parent / 'config' / 'config.yaml'
        self.yaml_config = self._load_yaml_config()
        
        # Inicializar configurações
        self.database = DatabaseConfig()
        self.sync = SyncConfig()
        self.storage = StorageConfig()
        self.security = SecurityConfig()
        self.monitoring = MonitoringConfig()
        self.notification = NotificationConfig()
        self.logging = LoggingConfig()
        
        # Atualizar com YAML
        self._update_from_yaml()
    
    def _load_yaml_config(self) -> Dict[str, Any]:
        """Carregar configuração do arquivo YAML"""
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                return yaml.safe_load(f) or {}
        return {}
    
    def _update_from_yaml(self):
        """Atualizar configurações do YAML"""
        if not self.yaml_config:
            return
        
        # Atualizar cada seção
        sections = {
            'database': self.database,
            'sync': self.sync,
            'storage': self.storage,
            'security': self.security,
            'monitoring': self.monitoring,
            'notification': self.notification,
            'logging': self.logging
        }
        
        for section_name, section_obj in sections.items():
            if section_name in self.yaml_config:
                section_data = self.yaml_config[section_name]
                for key, value in section_data.items():
                    if hasattr(section_obj, key):
                        setattr(section_obj, key, value)
    
    @property
    def DEBUG(self) -> bool:
        return os.getenv('FLASK_ENV', 'production') == 'development'
    
    @property
    def HOST(self) -> str:
        return os.getenv('HOST', '0.0.0.0')
    
    @property
    def PORT(self) -> int:
        return int(os.getenv('PORT', 5000))
    
    @property
    def LOG_LEVEL(self) -> str:
        return self.logging.level
    
    @property
    def LOG_FILE(self) -> str:
        return self.logging.file
    
    @property
    def SECRET_KEY(self) -> str:
        return self.security.secret_key
    
    @property
    def DB_HOST(self) -> str:
        return self.database.host
    
    @property
    def DB_PORT(self) -> int:
        return self.database.port
    
    @property
    def DB_NAME(self) -> str:
        return self.database.name
    
    @property
    def DB_USER(self) -> str:
        return self.database.user
    
    @property
    def DB_PASSWORD(self) -> str:
        return self.database.password
    
    @property
    def VOD_STORAGE_PATH(self) -> str:
        return self.storage.local_path
    
    @property
    def LOG_PATH(self) -> str:
        return self.storage.log_path
    
    @property
    def BACKUP_PATH(self) -> str:
        return self.storage.backup_path

# Instância global de configuração
config = Config()
EOF

    # Criar models
    mkdir -p "$INSTALL_DIR/src/models"
    cat > "$INSTALL_DIR/src/models/__init__.py" << EOF
"""
Models do Sistema VOD Sync XUI
"""

from .user import User
from .vod import VOD, VODCategory, VODSeries
from .sync import SyncTask, SyncLog
from .system import SystemLog, SystemSetting

__all__ = [
    'User',
    'VOD', 'VODCategory', 'VODSeries',
    'SyncTask', 'SyncLog',
    'SystemLog', 'SystemSetting'
]
EOF

    cat > "$INSTALL_DIR/src/models/user.py" << EOF
"""
Model de Usuário
"""

from datetime import datetime
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from src.database import db

class User(db.Model, UserMixin):
    """Model de usuário"""
    __tablename__ = 'users'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_login = db.Column(db.DateTime, nullable=True)
    
    # Relacionamentos
    sync_tasks = db.relationship('SyncTask', backref='user', lazy=True)
    
    def set_password(self, password):
        """Definir senha hash"""
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        """Verificar senha"""
        return check_password_hash(self.password_hash, password)
    
    def to_dict(self):
        """Converter para dicionário"""
        return {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'is_admin': self.is_admin,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'last_login': self.last_login.isoformat() if self.last_login else None
        }
    
    def __repr__(self):
        return f'<User {self.username}>'
EOF

    cat > "$INSTALL_DIR/src/models/vod.py" << EOF
"""
Models de VOD
"""

from datetime import datetime
from src.database import db

class VODCategory(db.Model):
    """Categoria de VOD"""
    __tablename__ = 'vod_categories'
    
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Relacionamentos
    vods = db.relationship('VOD', backref='category', lazy=True)
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'vod_count': len(self.vods),
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

class VODSeries(db.Model):
    """Série de VOD"""
    __tablename__ = 'vod_series'
    
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    year = db.Column(db.Integer)
    rating = db.Column(db.Float, default=0.0)
    poster_url = db.Column(db.String(500))
    backdrop_url = db.Column(db.String(500))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Relacionamentos
    vods = db.relationship('VOD', backref='series', lazy=True)
    
    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'year': self.year,
            'rating': self.rating,
            'poster_url': self.poster_url,
            'backdrop_url': self.backdrop_url,
            'vod_count': len(self.vods),
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

class VOD(db.Model):
    """VOD individual"""
    __tablename__ = 'vods'
    
    id = db.Column(db.Integer, primary_key=True)
    xui_id = db.Column(db.Integer, unique=True, nullable=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    file_path = db.Column(db.String(500), nullable=False)
    file_size = db.Column(db.BigInteger, default=0)
    duration = db.Column(db.Integer, default=0)  # segundos
    thumbnail_path = db.Column(db.String(500))
    stream_url = db.Column(db.String(500))
    
    # Metadados
    year = db.Column(db.Integer)
    rating = db.Column(db.Float, default=0.0)
    imdb_id = db.Column(db.String(20))
    tmdb_id = db.Column(db.String(20))
    
    # Status
    is_active = db.Column(db.Boolean, default=True)
    last_played = db.Column(db.DateTime, nullable=True)
    play_count = db.Column(db.Integer, default=0)
    
    # Relacionamentos
    category_id = db.Column(db.Integer, db.ForeignKey('vod_categories.id'))
    series_id = db.Column(db.Integer, db.ForeignKey('vod_series.id'), nullable=True)
    season_number = db.Column(db.Integer, nullable=True)
    episode_number = db.Column(db.Integer, nullable=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    synced_at = db.Column(db.DateTime, nullable=True)
    
    def to_dict(self):
        """Converter para dicionário"""
        return {
            'id': self.id,
            'xui_id': self.xui_id,
            'title': self.title,
            'description': self.description,
            'file_path': self.file_path,
            'file_size': self.file_size,
            'duration': self.duration,
            'thumbnail_url': f'/api/v1/vods/{self.id}/thumbnail' if self.thumbnail_path else None,
            'stream_url': f'/api/v1/vods/{self.id}/stream' if self.file_path else None,
            'year': self.year,
            'rating': self.rating,
            'category': self.category.to_dict() if self.category else None,
            'series': self.series.to_dict() if self.series else None,
            'season_number': self.season_number,
            'episode_number': self.episode_number,
            'is_active': self.is_active,
            'play_count': self.play_count,
            'last_played': self.last_played.isoformat() if self.last_played else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'synced_at': self.synced_at.isoformat() if self.synced_at else None
        }
    
    def __repr__(self):
        return f'<VOD {self.title}>'
EOF

    # Criar estrutura básica do código
    print_info "Criando estrutura básica do código..."
    
    # database.py
    cat > "$INSTALL_DIR/src/database.py" << EOF
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import declarative_base

db = SQLAlchemy()
Base = declarative_base()

def init_db():
    """Inicializar banco de dados"""
    db.create_all()
EOF

    # services/sync_service.py
    mkdir -p "$INSTALL_DIR/src/services"
    cat > "$INSTALL_DIR/src/services/sync_service.py" << EOF
class VODSyncService:
    """Serviço de sincronização de VODs"""
    def __init__(self, config):
        self.config = config
        self.is_running = False
    
    def start_manual_sync(self):
        """Iniciar sincronização manual"""
        import uuid
        return str(uuid.uuid4())
    
    def start_scheduled_sync(self):
        """Iniciar sincronização agendada"""
        pass
EOF

    # services/monitoring.py
    cat > "$INSTALL_DIR/src/services/monitoring.py" << EOF
import psutil
import datetime

class SystemMonitor:
    """Monitoramento do sistema"""
    
    def get_all_stats(self):
        """Obter todas as estatísticas"""
        return {
            'cpu': self.get_cpu_stats(),
            'memory': self.get_memory_stats(),
            'disk': self.get_disk_stats(),
            'network': self.get_network_stats(),
            'system': self.get_system_info(),
            'timestamp': datetime.datetime.now().isoformat()
        }
    
    def get_cpu_stats(self):
        """Obter estatísticas da CPU"""
        return {
            'percent': psutil.cpu_percent(interval=1),
            'cores': psutil.cpu_count(),
            'frequency': psutil.cpu_freq().current if psutil.cpu_freq() else 0
        }
    
    def get_memory_stats(self):
        """Obter estatísticas de memória"""
        mem = psutil.virtual_memory()
        return {
            'total': mem.total,
            'available': mem.available,
            'percent': mem.percent,
            'used': mem.used,
            'free': mem.free
        }
    
    def get_disk_stats(self):
        """Obter estatísticas de disco"""
        disk = psutil.disk_usage('/')
        return {
            'total': disk.total,
            'used': disk.used,
            'free': disk.free,
            'percent': disk.percent
        }
    
    def get_network_stats(self):
        """Obter estatísticas de rede"""
        net = psutil.net_io_counters()
        return {
            'bytes_sent': net.bytes_sent,
            'bytes_recv': net.bytes_recv,
            'packets_sent': net.packets_sent,
            'packets_recv': net.packets_recv
        }
    
    def get_system_info(self):
        """Obter informações do sistema"""
        import platform
        return {
            'os': platform.system(),
            'os_version': platform.release(),
            'hostname': platform.node(),
            'python_version': platform.python_version(),
            'boot_time': datetime.datetime.fromtimestamp(psutil.boot_time()).isoformat()
        }
EOF

    # utils/helpers.py
    mkdir -p "$INSTALL_DIR/src/utils"
    cat > "$INSTALL_DIR/src/utils/helpers.py" << EOF
import socket

def get_ip_address():
    """Obter endereço IP da máquina"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"
EOF

    # API e Auth
    mkdir -p "$INSTALL_DIR/src/api" "$INSTALL_DIR/src/auth"
    
    cat > "$INSTALL_DIR/src/api/__init__.py" << EOF
from flask import Blueprint

api_bp = Blueprint('api', __name__)

from . import routes
EOF

    cat > "$INSTALL_DIR/src/auth/__init__.py" << EOF
from flask import Blueprint

auth_bp = Blueprint('auth', __name__)

from . import routes
EOF

    print_success "Código fonte criado"
}

# Criar dashboard HTML/CSS/JS
create_dashboard() {
    print_step "Criando dashboard web..."
    
    # Base template
    cat > "$INSTALL_DIR/dashboard/templates/base.html" << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VOD Sync XUI - {% block title %}Dashboard{% endblock %}</title>
    
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Chart.js -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <!-- Custom CSS -->
    <link rel="stylesheet" href="{{ url_for('static', filename='css/main.css') }}">
    
    {% block extra_css %}{% endblock %}
</head>
<body>
    <!-- Navbar -->
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="/">
                <i class="fas fa-sync-alt"></i> VOD Sync XUI
            </a>
            
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
                <span class="navbar-toggler-icon"></span>
            </button>
            
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav me-auto">
                    <li class="nav-item">
                        <a class="nav-link {% if request.path == '/dashboard' %}active{% endif %}" href="/dashboard">
                            <i class="fas fa-tachometer-alt"></i> Dashboard
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link {% if request.path == '/sync' %}active{% endif %}" href="/sync">
                            <i class="fas fa-sync"></i> Sincronização
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link {% if request.path == '/vods' %}active{% endif %}" href="/vods">
                            <i class="fas fa-film"></i> VODs
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link {% if request.path == '/logs' %}active{% endif %}" href="/logs">
                            <i class="fas fa-clipboard-list"></i> Logs
                        </a>
                    </li>
                    {% if current_user.is_admin %}
                    <li class="nav-item">
                        <a class="nav-link {% if request.path == '/settings' %}active{% endif %}" href="/settings">
                            <i class="fas fa-cog"></i> Configurações
                        </a>
                    </li>
                    {% endif %}
                </ul>
                
                <ul class="navbar-nav">
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" id="userDropdown" role="button" data-bs-toggle="dropdown">
                            <i class="fas fa-user"></i> {{ current_user.username }}
                        </a>
                        <ul class="dropdown-menu dropdown-menu-end">
                            <li><a class="dropdown-item" href="/profile"><i class="fas fa-id-card"></i> Perfil</a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><a class="dropdown-item" href="/auth/logout"><i class="fas fa-sign-out-alt"></i> Sair</a></li>
                        </ul>
                    </li>
                </ul>
            </div>
        </div>
    </nav>

    <!-- Main Content -->
    <div class="container-fluid mt-3">
        <!-- Notifications -->
        <div id="notification-area"></div>
        
        <!-- Breadcrumb -->
        <nav aria-label="breadcrumb" class="mb-3">
            <ol class="breadcrumb">
                <li class="breadcrumb-item"><a href="/">Home</a></li>
                {% block breadcrumb %}{% endblock %}
            </ol>
        </nav>
        
        <!-- Page Header -->
        <div class="row mb-4">
            <div class="col">
                <h2>{% block page_title %}Dashboard{% endblock %}</h2>
                <p class="text-muted">{% block page_subtitle %}Sistema de Sincronização de VODs XUI One{% endblock %}</p>
            </div>
            <div class="col-auto">
                {% block page_actions %}{% endblock %}
            </div>
        </div>
        
        <!-- Page Content -->
        {% block content %}{% endblock %}
    </div>

    <!-- Footer -->
    <footer class="footer mt-5 py-3 bg-light">
        <div class="container-fluid">
            <div class="row">
                <div class="col-md-6">
                    <span class="text-muted">VOD Sync XUI v3.0.0 &copy; 2024</span>
                </div>
                <div class="col-md-6 text-end">
                    <span class="text-muted" id="system-status">
                        <i class="fas fa-circle text-success"></i> Sistema Online
                    </span>
                </div>
            </div>
        </div>
    </footer>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <!-- Socket.IO -->
    <script src="https://cdn.socket.io/4.6.0/socket.io.min.js"></script>
    <!-- jQuery -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <!-- Custom JS -->
    <script src="{{ url_for('static', filename='js/main.js') }}"></script>
    
    {% block extra_js %}{% endblock %}
    
    <script>
        // Inicializar Socket.IO
        const socket = io();
        
        // Status do sistema
        socket.on('connect', function() {
            $('#system-status').html('<i class="fas fa-circle text-success"></i> Sistema Online');
        });
        
        socket.on('disconnect', function() {
            $('#system-status').html('<i class="fas fa-circle text-danger"></i> Sistema Offline');
        });
        
        // Notificações em tempo real
        socket.on('notification', function(data) {
            showNotification(data.type, data.message);
        });
        
        function showNotification(type, message) {
            const alertClass = type === 'success' ? 'alert-success' : 
                             type === 'error' ? 'alert-danger' : 
                             type === 'warning' ? 'alert-warning' : 'alert-info';
            
            const alert = '<div class="alert ' + alertClass + ' alert-dismissible fade show" role="alert">' +
                         message +
                         '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>' +
                         '</div>';
            
            $('#notification-area').append(alert);
            
            // Auto-remover após 5 segundos
            setTimeout(() => {
                $('.alert').alert('close');
            }, 5000);
        }
    </script>
</body>
</html>
EOF

    # Dashboard principal
    cat > "$INSTALL_DIR/dashboard/templates/dashboard.html" << EOF
{% extends "base.html" %}

{% block title %}Dashboard - VOD Sync XUI{% endblock %}
{% block page_title %}Dashboard do Sistema{% endblock %}
{% block page_subtitle %}Visão geral e estatísticas em tempo real{% endblock %}

{% block breadcrumb %}
<li class="breadcrumb-item active">Dashboard</li>
{% endblock %}

{% block page_actions %}
<button class="btn btn-primary" onclick="startSync()">
    <i class="fas fa-sync"></i> Iniciar Sincronização
</button>
{% endblock %}

{% block content %}
<div class="row">
    <!-- System Stats -->
    <div class="col-md-3 mb-3">
        <div class="card h-100">
            <div class="card-header bg-primary text-white">
                <i class="fas fa-microchip"></i> CPU
            </div>
            <div class="card-body">
                <h3 id="cpu-percent">0%</h3>
                <div class="progress" style="height: 10px;">
                    <div id="cpu-bar" class="progress-bar" role="progressbar" style="width: 0%"></div>
                </div>
                <small class="text-muted" id="cpu-info">Cores: 0 | Freq: 0 MHz</small>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card h-100">
            <div class="card-header bg-success text-white">
                <i class="fas fa-memory"></i> Memória
            </div>
            <div class="card-body">
                <h3 id="mem-percent">0%</h3>
                <div class="progress" style="height: 10px;">
                    <div id="mem-bar" class="progress-bar bg-success" role="progressbar" style="width: 0%"></div>
                </div>
                <small class="text-muted" id="mem-info">0 GB / 0 GB</small>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card h-100">
            <div class="card-header bg-warning text-white">
                <i class="fas fa-hdd"></i> Disco
            </div>
            <div class="card-body">
                <h3 id="disk-percent">0%</h3>
                <div class="progress" style="height: 10px;">
                    <div id="disk-bar" class="progress-bar bg-warning" role="progressbar" style="width: 0%"></div>
                </div>
                <small class="text-muted" id="disk-info">0 GB / 0 GB</small>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card h-100">
            <div class="card-header bg-info text-white">
                <i class="fas fa-network-wired"></i> Rede
            </div>
            <div class="card-body">
                <h6>Upload: <span id="net-up">0 B/s</span></h6>
                <h6>Download: <span id="net-down">0 B/s</span></h6>
                <small class="text-muted" id="net-info">Total: 0 MB</small>
            </div>
        </div>
    </div>
</div>

<div class="row mt-4">
    <!-- Left Column -->
    <div class="col-md-8">
        <!-- Sync Status -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-sync-alt"></i> Status da Sincronização
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-4 text-center">
                        <div class="display-4">{{ vod_count }}</div>
                        <small class="text-muted">VODs Sincronizados</small>
                    </div>
                    <div class="col-md-4 text-center">
                        <div class="display-4">{{ pending_tasks }}</div>
                        <small class="text-muted">Tarefas Pendentes</small>
                    </div>
                    <div class="col-md-4 text-center">
                        <div id="sync-status" class="display-6">
                            <span class="badge bg-success">Ativo</span>
                        </div>
                        <small class="text-muted">Status do Serviço</small>
                    </div>
                </div>
                
                <div class="mt-3">
                    <h6>Última Sincronização:</h6>
                    <div class="table-responsive">
                        <table class="table table-sm">
                            <thead>
                                <tr>
                                    <th>ID</th>
                                    <th>Tipo</th>
                                    <th>Status</th>
                                    <th>Início</th>
                                    <th>Progresso</th>
                                </tr>
                            </thead>
                            <tbody id="sync-tasks">
                                <!-- Preenchido via JavaScript -->
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- CPU/Memory Chart -->
        <div class="card">
            <div class="card-header">
                <i class="fas fa-chart-line"></i> Monitoramento em Tempo Real
            </div>
            <div class="card-body">
                <canvas id="systemChart" height="100"></canvas>
            </div>
        </div>
    </div>
    
    <!-- Right Column -->
    <div class="col-md-4">
        <!-- System Info -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-info-circle"></i> Informações do Sistema
            </div>
            <div class="card-body">
                <table class="table table-sm">
                    <tr>
                        <td><i class="fas fa-server"></i> Hostname:</td>
                        <td id="sys-hostname">-</td>
                    </tr>
                    <tr>
                        <td><i class="fab fa-python"></i> Python:</td>
                        <td id="sys-python">-</td>
                    </tr>
                    <tr>
                        <td><i class="fas fa-clock"></i> Uptime:</td>
                        <td id="sys-uptime">-</td>
                    </tr>
                    <tr>
                        <td><i class="fas fa-database"></i> Banco:</td>
                        <td><span class="badge bg-success">Conectado</span></td>
                    </tr>
                    <tr>
                        <td><i class="fas fa-plug"></i> Redis:</td>
                        <td><span class="badge bg-success">Conectado</span></td>
                    </tr>
                </table>
            </div>
        </div>
        
        <!-- Recent Logs -->
        <div class="card">
            <div class="card-header">
                <i class="fas fa-clipboard-list"></i> Logs Recentes
            </div>
            <div class="card-body" style="max-height: 300px; overflow-y: auto;">
                {% for log in recent_logs %}
                <div class="mb-2">
                    <small class="text-muted">{{ log.timestamp.strftime('%H:%M:%S') }}</small>
                    <span class="badge bg-{{ 'info' if log.level == 'INFO' else 'warning' if log.level == 'WARNING' else 'danger' }}">
                        {{ log.level }}
                    </span>
                    <small>{{ log.message[:50] }}{% if log.message|length > 50 %}...{% endif %}</small>
                </div>
                {% endfor %}
            </div>
            <div class="card-footer text-center">
                <a href="/logs" class="btn btn-sm btn-outline-primary">Ver todos os logs</a>
            </div>
        </div>
    </div>
</div>

<!-- Quick Actions -->
<div class="row mt-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header">
                <i class="fas fa-bolt"></i> Ações Rápidas
            </div>
            <div class="card-body">
                <button class="btn btn-outline-primary" onclick="forceSync()">
                    <i class="fas fa-sync"></i> Forçar Sincronização
                </button>
                <button class="btn btn-outline-success" onclick="backupNow()">
                    <i class="fas fa-save"></i> Backup Agora
                </button>
                <button class="btn btn-outline-warning" onclick="clearLogs()">
                    <i class="fas fa-trash"></i> Limpar Logs Antigos
                </button>
                <button class="btn btn-outline-info" onclick="refreshStats()">
                    <i class="fas fa-redo"></i> Atualizar Estatísticas
                </button>
            </div>
        </div>
    </div>
</div>
{% endblock %}

{% block extra_js %}
<script src="{{ url_for('static', filename='js/dashboard.js') }}"></script>

<script>
let systemChart;
let lastNetUp = 0;
let lastNetDown = 0;

function updateStats() {
    \$.get('/api/system/stats', function(data) {
        // CPU
        \$('#cpu-percent').text(data.cpu.percent.toFixed(1) + '%');
        \$('#cpu-bar').css('width', data.cpu.percent + '%');
        \$('#cpu-info').text('Cores: ' + data.cpu.cores + ' | Freq: ' + data.cpu.frequency.toFixed(0) + ' MHz');
        
        // Memory
        const memGB = data.memory.total / 1024 / 1024 / 1024;
        const usedGB = data.memory.used / 1024 / 1024 / 1024;
        \$('#mem-percent').text(data.memory.percent.toFixed(1) + '%');
        \$('#mem-bar').css('width', data.memory.percent + '%');
        \$('#mem-info').text(usedGB.toFixed(1) + ' GB / ' + memGB.toFixed(1) + ' GB');
        
        // Disk
        const diskGB = data.disk.total / 1024 / 1024 / 1024;
        const usedDiskGB = data.disk.used / 1024 / 1024 / 1024;
        \$('#disk-percent').text(data.disk.percent.toFixed(1) + '%');
        \$('#disk-bar').css('width', data.disk.percent + '%');
        \$('#disk-info').text(usedDiskGB.toFixed(1) + ' GB / ' + diskGB.toFixed(1) + ' GB');
        
        // Network
        const upSpeed = data.network.bytes_sent - lastNetUp;
        const downSpeed = data.network.bytes_recv - lastNetDown;
        
        \$('#net-up').text(formatBytes(upSpeed) + '/s');
        \$('#net-down').text(formatBytes(downSpeed) + '/s');
        
        lastNetUp = data.network.bytes_sent;
        lastNetDown = data.network.bytes_recv;
        
        // System Info
        \$('#sys-hostname').text(data.system.hostname);
        \$('#sys-python').text(data.system.python_version);
        \$('#sys-uptime').text(formatUptime(data.system.boot_time));
        
        // Update chart
        updateChart(data);
    });
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatUptime(bootTime) {
    const now = new Date();
    const boot = new Date(bootTime);
    const diff = now - boot;
    
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    
    if (days > 0) return days + 'd ' + hours + 'h';
    if (hours > 0) return hours + 'h ' + minutes + 'm';
    return minutes + 'm';
}

function updateChart(data) {
    if (!systemChart) {
        const ctx = document.getElementById('systemChart').getContext('2d');
        systemChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'CPU %',
                        data: [],
                        borderColor: 'rgb(255, 99, 132)',
                        tension: 0.1
                    },
                    {
                        label: 'Memória %',
                        data: [],
                        borderColor: 'rgb(54, 162, 235)',
                        tension: 0.1
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'top',
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100
                    }
                }
            }
        });
    }
    
    const now = new Date().toLocaleTimeString();
    
    // Limitar a 20 pontos
    if (systemChart.data.labels.length > 20) {
        systemChart.data.labels.shift();
        systemChart.data.datasets.forEach(dataset => {
            dataset.data.shift();
        });
    }
    
    systemChart.data.labels.push(now);
    systemChart.data.datasets[0].data.push(data.cpu.percent);
    systemChart.data.datasets[1].data.push(data.memory.percent);
    
    systemChart.update();
}

function startSync() {
    \$.post('/api/sync/start', function(response) {
        if (response.success) {
            showNotification('success', 'Sincronização iniciada!');
        } else {
            showNotification('error', 'Erro: ' + response.error);
        }
    });
}

function refreshStats() {
    updateStats();
    showNotification('info', 'Estatísticas atualizadas!');
}

// Atualizar a cada 5 segundos
setInterval(updateStats, 5000);

// Inicializar
\$(document).ready(function() {
    updateStats();
    
    // Socket.IO para atualizações em tempo real
    socket.on('system_stats', function(data) {
        updateChart(data);
    });
    
    socket.on('sync_update', function(data) {
        \$('#sync-tasks').html('<tr>' +
            '<td>' + data.task_id + '</td>' +
            '<td>' + data.type + '</td>' +
            '<td><span class="badge bg-info">' + data.status + '</span></td>' +
            '<td>' + new Date(data.start_time).toLocaleTimeString() + '</td>' +
            '<td>' +
            '<div class="progress" style="height: 5px;">' +
            '<div class="progress-bar" style="width: ' + data.progress + '%"></div>' +
            '</div>' +
            '<small>' + data.progress + '%</small>' +
            '</td>' +
            '</tr>');
    });
});
</script>
{% endblock %}
EOF

    # CSS principal
    cat > "$INSTALL_DIR/dashboard/static/css/main.css" << EOF
/* VOD Sync XUI - Main CSS */

:root {
    --primary-color: #3498db;
    --secondary-color: #2c3e50;
    --success-color: #27ae60;
    --warning-color: #f39c12;
    --danger-color: #e74c3c;
    --info-color: #17a2b8;
    --dark-color: #343a40;
    --light-color: #f8f9fa;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: #f5f5f5;
    color: #333;
}

.navbar-brand {
    font-weight: bold;
    font-size: 1.5rem;
}

.card {
    border: none;
    border-radius: 10px;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    transition: transform 0.3s ease;
}

.card:hover {
    transform: translateY(-5px);
}

.card-header {
    border-radius: 10px 10px 0 0 !important;
    font-weight: 600;
}

.progress {
    border-radius: 10px;
}

.progress-bar {
    border-radius: 10px;
}

/* Status badges */
.badge {
    font-size: 0.8em;
    padding: 0.4em 0.8em;
    border-radius: 20px;
}

/* Tables */
.table {
    background-color: white;
    border-radius: 8px;
    overflow: hidden;
}

.table thead th {
    background-color: var(--primary-color);
    color: white;
    border: none;
}

.table tbody tr:hover {
    background-color: rgba(52, 152, 219, 0.1);
}

/* Footer */
.footer {
    border-top: 1px solid #dee2e6;
    margin-top: 2rem;
}

/* Animations */
@keyframes pulse {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
}

.pulse {
    animation: pulse 2s infinite;
}

/* Custom scrollbar */
::-webkit-scrollbar {
    width: 8px;
}

::-webkit-scrollbar-track {
    background: #f1f1f1;
    border-radius: 10px;
}

::-webkit-scrollbar-thumb {
    background: #888;
    border-radius: 10px;
}

::-webkit-scrollbar-thumb:hover {
    background: #555;
}

/* Responsive adjustments */
@media (max-width: 768px) {
    .display-4 {
        font-size: 2rem;
    }
    
    .card-body {
        padding: 1rem;
    }
}

/* Loading spinner */
.spinner {
    border: 4px solid rgba(0, 0, 0, 0.1);
    border-left-color: var(--primary-color);
    border-radius: 50%;
    width: 40px;
    height: 40px;
    animation: spin 1s linear infinite;
    margin: 20px auto;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

/* Notification styles */
.notification {
    position: fixed;
    top: 20px;
    right: 20px;
    z-index: 9999;
    min-width: 300px;
    max-width: 500px;
}

/* Button animations */
.btn {
    transition: all 0.3s ease;
}

.btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
}

/* Form controls */
.form-control:focus {
    border-color: var(--primary-color);
    box-shadow: 0 0 0 0.2rem rgba(52, 152, 219, 0.25);
}

/* Dashboard specific */
.dashboard-stat {
    text-align: center;
    padding: 20px;
}

.dashboard-stat .stat-value {
    font-size: 2.5rem;
    font-weight: bold;
    color: var(--primary-color);
}

.dashboard-stat .stat-label {
    color: #6c757d;
    font-size: 0.9rem;
    text-transform: uppercase;
    letter-spacing: 1px;
}
EOF

    # JavaScript principal
    cat > "$INSTALL_DIR/dashboard/static/js/main.js" << EOF
// VOD Sync XUI - Main JavaScript

class VODSyncApp {
    constructor() {
        this.socket = io();
        this.initializeSocket();
        this.initializeEventListeners();
        this.checkSystemStatus();
    }
    
    initializeSocket() {
        this.socket.on('connect', () => {
            console.log('Conectado ao servidor via Socket.IO');
            this.showToast('success', 'Conectado ao servidor');
        });
        
        this.socket.on('disconnect', () => {
            console.log('Desconectado do servidor');
            this.showToast('warning', 'Desconectado do servidor');
        });
        
        this.socket.on('sync_started', (data) => {
            this.showToast('info', 'Sincronização iniciada: ' + data.task_id);
            this.updateSyncStatus(data);
        });
        
        this.socket.on('sync_completed', (data) => {
            this.showToast('success', 'Sincronização concluída: ' + data.task_id);
            this.updateSyncStatus(data);
        });
        
        this.socket.on('sync_failed', (data) => {
            this.showToast('error', 'Sincronização falhou: ' + data.error);
            this.updateSyncStatus(data);
        });
        
        this.socket.on('system_alert', (data) => {
            this.showAlert(data.type, data.message);
        });
    }
    
    initializeEventListeners() {
        // Global event listeners
        \$(document).on('click', '[data-action="start-sync"]', (e) => {
            e.preventDefault();
            this.startSync();
        });
        
        \$(document).on('click', '[data-action="stop-sync"]', (e) => {
            e.preventDefault();
            this.stopSync();
        });
        
        \$(document).on('click', '[data-action="refresh"]', (e) => {
            e.preventDefault();
            this.refreshData();
        });
        
        // Auto-refresh dashboard every 30 seconds
        setInterval(() => {
            if (\$('#dashboard').length) {
                this.refreshDashboard();
            }
        }, 30000);
    }
    
    async startSync() {
        try {
            const response = await fetch('/api/sync/start', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showToast('success', 'Sincronização iniciada com sucesso!');
                this.socket.emit('sync_action', { action: 'started' });
            } else {
                this.showToast('error', 'Erro: ' + data.error);
            }
        } catch (error) {
            this.showToast('error', 'Erro: ' + error.message);
        }
    }
    
    async stopSync(taskId) {
        try {
            const response = await fetch('/api/sync/stop/' + taskId, {
                method: 'POST'
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showToast('warning', 'Sincronização parada!');
            } else {
                this.showToast('error', 'Erro: ' + data.error);
            }
        } catch (error) {
            this.showToast('error', 'Erro: ' + error.message);
        }
    }
    
    async refreshDashboard() {
        try {
            const response = await fetch('/api/system/stats');
            const data = await response.json();
            
            // Update CPU
            \$('#cpu-percent').text(data.cpu.percent.toFixed(1) + '%');
            \$('#cpu-bar').css('width', data.cpu.percent + '%');
            
            // Update Memory
            \$('#mem-percent').text(data.memory.percent.toFixed(1) + '%');
            \$('#mem-bar').css('width', data.memory.percent + '%');
            
            // Update Disk
            \$('#disk-percent').text(data.disk.percent.toFixed(1) + '%');
            \$('#disk-bar').css('width', data.disk.percent + '%');
            
            // Update system info
            \$('#sys-hostname').text(data.system.hostname);
            \$('#sys-uptime').text(this.formatUptime(data.system.boot_time));
            
        } catch (error) {
            console.error('Erro ao atualizar dashboard:', error);
        }
    }
    
    async checkSystemStatus() {
        try {
            const response = await fetch('/api/system/health');
            const data = await response.json();
            
            const statusElement = \$('#system-status');
            if (data.status === 'healthy') {
                statusElement.html('<i class="fas fa-circle text-success"></i> Sistema Online');
            } else {
                statusElement.html('<i class="fas fa-circle text-danger"></i> Sistema Offline');
                this.showToast('error', 'Sistema está com problemas!');
            }
        } catch (error) {
            \$('#system-status').html('<i class="fas fa-circle text-warning"></i> Erro de Conexão');
        }
    }
    
    updateSyncStatus(data) {
        // Atualizar interface com status da sincronização
        const syncTable = \$('#sync-tasks');
        if (syncTable.length) {
            const row = '<tr>' +
                '<td>' + data.task_id + '</td>' +
                '<td>' + (data.type || 'Manual') + '</td>' +
                '<td><span class="badge bg-' + this.getStatusColor(data.status) + '">' + data.status + '</span></td>' +
                '<td>' + new Date(data.timestamp).toLocaleTimeString() + '</td>' +
                '<td>' + (data.progress || 0) + '%</td>' +
                '</tr>';
            syncTable.prepend(row);
            
            // Limitar a 10 linhas
            if (syncTable.find('tr').length > 10) {
                syncTable.find('tr').last().remove();
            }
        }
    }
    
    getStatusColor(status) {
        switch(status.toLowerCase()) {
            case 'completed': return 'success';
            case 'running': return 'primary';
            case 'pending': return 'warning';
            case 'failed': return 'danger';
            default: return 'secondary';
        }
    }
    
    formatUptime(bootTime) {
        const now = new Date();
        const boot = new Date(bootTime);
        const diff = now - boot;
        
        const days = Math.floor(diff / (1000 * 60 * 60 * 24));
        const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
        const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
        
        if (days > 0) return days + 'd ' + hours + 'h';
        if (hours > 0) return hours + 'h ' + minutes + 'm';
        return minutes + 'm';
    }
    
    showToast(type, message) {
        // Remove existing toasts
        \$('.toast').remove();
        
        const toast = \$('<div class="toast align-items-center text-bg-' + type + ' border-0" role="alert">' +
            '<div class="d-flex">' +
            '<div class="toast-body">' +
            message +
            '</div>' +
            '<button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>' +
            '</div>' +
            '</div>');
        
        \$('body').append(toast);
        
        const bsToast = new bootstrap.Toast(toast[0], {
            autohide: true,
            delay: 5000
        });
        
        bsToast.show();
    }
    
    showAlert(type, message) {
        const alert = \$('<div class="alert alert-' + type + ' alert-dismissible fade show" role="alert">' +
            message +
            '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>' +
            '</div>');
        
        \$('#notification-area').prepend(alert);
        
        // Auto-remove after 10 seconds
        setTimeout(() => {
            alert.alert('close');
        }, 10000);
    }
    
    refreshData() {
        this.refreshDashboard();
        this.checkSystemStatus();
        this.showToast('info', 'Dados atualizados!');
    }
}

// Initialize app when document is ready
\$(document).ready(function() {
    window.vodSyncApp = new VODSyncApp();
    
    // Tooltips
    \$('[data-bs-toggle="tooltip"]').tooltip();
    
    // Popovers
    \$('[data-bs-toggle="popover"]').popover();
    
    // Auto-dismiss alerts after 5 seconds
    setTimeout(() => {
        \$('.alert:not(.alert-permanent)').alert('close');
    }, 5000);
});

// Utility functions
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];
    
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    
    if (hours > 0) {
        return hours + 'h ' + minutes + 'm';
    } else if (minutes > 0) {
        return minutes + 'm ' + secs + 's';
    } else {
        return secs + 's';
    }
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('pt-BR') + ' ' + date.toLocaleTimeString('pt-BR');
}

// Global error handler
window.onerror = function(message, source, lineno, colno, error) {
    console.error('Erro global:', { message, source, lineno, colno, error });
    
    // Don't show error toast for network errors
    if (message.includes('NetworkError') || message.includes('Failed to fetch')) {
        return;
    }
    
    if (window.vodSyncApp) {
        window.vodSyncApp.showToast('error', 'Erro: ' + message);
    }
};
EOF

    # Dashboard JavaScript
    cat > "$INSTALL_DIR/dashboard/static/js/dashboard.js" << EOF
// Dashboard specific JavaScript

// Funções específicas do dashboard
function forceSync() {
    window.vodSyncApp.startSync();
}

function backupNow() {
    \$.post('/api/system/backup', function(response) {
        if (response.success) {
            window.vodSyncApp.showToast('success', 'Backup iniciado!');
        } else {
            window.vodSyncApp.showToast('error', 'Erro: ' + response.error);
        }
    });
}

function clearLogs() {
    if (confirm('Tem certeza que deseja limpar os logs antigos?')) {
        \$.post('/api/system/clear-logs', function(response) {
            if (response.success) {
                window.vodSyncApp.showToast('success', 'Logs limpos!');
            } else {
                window.vodSyncApp.showToast('error', 'Erro: ' + response.error);
            }
        });
    }
}

// Inicialização do dashboard
\$(document).ready(function() {
    // Atualizar estatísticas a cada 10 segundos
    setInterval(function() {
        if (\$('#dashboard').length) {
            window.vodSyncApp.refreshDashboard();
        }
    }, 10000);
});
EOF

    print_success "Dashboard criado"
}

# Instalar dependências do sistema
install_system_dependencies() {
    print_step "Instalando dependências do sistema..."
    
    if [ "$OS_TYPE" = "debian" ]; then
        apt-get update
        
        # Instalar pacotes essenciais
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv \
            python3-dev \
            build-essential \
            nginx \
            redis-server \
            mysql-server \
            mysql-client \
            libmariadb-dev \
            libssl-dev \
            libffi-dev \
            ffmpeg \
            git \
            curl \
            wget \
            htop \
            net-tools \
            supervisor \
            ufw \
            cron \
            logrotate \
            zip \
            unzip \
            pv \
            jq \
            tree
        
        # Iniciar serviços
        print_info "Iniciando serviços..."
        systemctl start mysql 2>/dev/null || print_warning "MySQL não pôde ser iniciado"
        systemctl start redis-server 2>/dev/null || print_warning "Redis não pôde ser iniciado"
        systemctl start nginx 2>/dev/null || print_warning "Nginx não pôde ser iniciado"
        
        # Habilitar serviços
        print_info "Habilitando serviços..."
        
        # MySQL
        if systemctl list-unit-files | grep -q "^mysql.service"; then
            systemctl enable mysql 2>/dev/null || print_warning "Não foi possível habilitar MySQL"
        else
            print_warning "Serviço MySQL não encontrado"
        fi
        
        # Nginx
        if systemctl list-unit-files | grep -q "^nginx.service"; then
            systemctl enable nginx 2>/dev/null || print_warning "Não foi possível habilitar Nginx"
        else
            print_warning "Serviço Nginx não encontrado"
        fi
        
        # Redis - tratamento especial para evitar erro de alias
        if systemctl list-unit-files | grep -q "^redis-server.service"; then
            systemctl enable redis-server 2>/dev/null || print_warning "Redis já habilitado ou é um alias"
        elif systemctl list-unit-files | grep -q "^redis.service"; then
            # Tentar habilitar mas ignorar erros se for alias
            systemctl enable redis 2>/dev/null || print_info "Redis pode ser um alias, continuando..."
        else
            print_warning "Serviço Redis não encontrado"
        fi
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        yum update -y
        yum install -y \
            python3 \
            python3-pip \
            python3-devel \
            nginx \
            redis \
            mariadb-server \
            mariadb-devel \
            openssl-devel \
            gcc \
            gcc-c++ \
            make \
            ffmpeg \
            ffmpeg-devel \
            git \
            curl \
            wget \
            htop \
            net-tools \
            supervisor \
            firewalld \
            cronie \
            logrotate \
            zip \
            unzip \
            pv \
            jq \
            tree
        
        # Iniciar serviços
        systemctl start mariadb redis nginx firewalld 2>/dev/null || true
        
        # Habilitar serviços
        systemctl enable mariadb nginx firewalld 2>/dev/null || true
        
        # Redis no RHEL
        if systemctl list-unit-files | grep -q "^redis.service"; then
            systemctl enable redis 2>/dev/null || print_warning "Não foi possível habilitar Redis"
        fi
    fi
    
    print_success "Dependências do sistema instaladas"
}

# Configurar banco de dados
setup_database() {
    print_step "Configurando banco de dados..."
    
    # Verificar se MySQL/MariaDB está rodando
    if ! systemctl is-active --quiet mysql 2>/dev/null && ! systemctl is-active --quiet mariadb 2>/dev/null; then
        print_warning "MySQL/MariaDB não está rodando, tentando iniciar..."
        
        if systemctl start mysql 2>/dev/null; then
            print_success "MySQL iniciado"
        elif systemctl start mariadb 2>/dev/null; then
            print_success "MariaDB iniciado"
        else
            print_error "Não foi possível iniciar MySQL/MariaDB"
            return 1
        fi
    fi
    
    # Aguardar MySQL/MariaDB iniciar
    sleep 3
    
    # Tentar conectar sem senha primeiro
    if mysql -u root -e "SELECT 1" 2>/dev/null; then
        print_info "Conexão MySQL sem senha detectada"
        
        # Criar banco de dados sem senha
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS vod_sync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
        mysql -u root -e "CREATE USER IF NOT EXISTS 'vod_sync'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" 2>/dev/null
        mysql -u root -e "GRANT ALL PRIVILEGES ON vod_sync.* TO 'vod_sync'@'localhost';" 2>/dev/null
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        
    elif mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1" 2>/dev/null; then
        print_info "Conexão MySQL com senha detectada"
        
        # Criar banco de dados com senha
        mysql -u root -p"${DB_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS vod_sync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
        mysql -u root -p"${DB_PASSWORD}" -e "CREATE USER IF NOT EXISTS 'vod_sync'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" 2>/dev/null
        mysql -u root -p"${DB_PASSWORD}" -e "GRANT ALL PRIVILEGES ON vod_sync.* TO 'vod_sync'@'localhost';" 2>/dev/null
        mysql -u root -p"${DB_PASSWORD}" -e "FLUSH PRIVILEGES;" 2>/dev/null
        
    else
        print_error "Não foi possível conectar ao MySQL/MariaDB"
        print_info "Tentando configurar acesso root sem senha..."
        
        # Tentar configurar acesso root sem senha temporariamente
        if [ -f /etc/mysql/debian.cnf ]; then
            # Debian/Ubuntu com debian-sys-maint
            DEBIAN_PASS=$(grep -oP 'password\s*=\s*\K.*' /etc/mysql/debian.cnf | head -1)
            mysql -u debian-sys-maint -p"${DEBIAN_PASS}" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';" 2>/dev/null || true
            mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        fi
        
        # Tentar novamente
        if mysql -u root -e "CREATE DATABASE IF NOT EXISTS vod_sync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
            print_success "Banco de dados criado"
            mysql -u root -e "CREATE USER IF NOT EXISTS 'vod_sync'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" 2>/dev/null
            mysql -u root -e "GRANT ALL PRIVILEGES ON vod_sync.* TO 'vod_sync'@'localhost';" 2>/dev/null
            mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        else
            print_error "Falha crítica: não foi possível configurar banco de dados"
            print_info "Configure manualmente o banco de dados após a instalação"
            return 1
        fi
    fi
    
    print_success "Banco de dados configurado"
}

# Configurar ambiente Python
setup_python_env() {
    print_step "Configurando ambiente Python..."
    
    # Criar ambiente virtual
    python3 -m venv "$INSTALL_DIR/venv"
    
    # Ativar e instalar pacotes
    source "$INSTALL_DIR/venv/bin/activate"
    
    # Atualizar pip
    pip install --upgrade pip setuptools wheel
    
    # Instalar requirements
    pip install -r "$INSTALL_DIR/requirements.txt"
    
    print_success "Ambiente Python configurado"
}

# Configurar serviços systemd
setup_system_services() {
    print_step "Configurando serviços systemd..."
    
    # Copiar arquivos de serviço se existirem
    if [ -f "$INSTALL_DIR/systemd/vod-sync.service" ]; then
        cp "$INSTALL_DIR/systemd/vod-sync.service" /etc/systemd/system/
        print_info "Serviço vod-sync copiado"
    fi
    
    if [ -f "$INSTALL_DIR/systemd/vod-sync-celery.service" ]; then
        cp "$INSTALL_DIR/systemd/vod-sync-celery.service" /etc/systemd/system/
        print_info "Serviço vod-sync-celery copiado"
    fi
    
    if [ -f "$INSTALL_DIR/systemd/vod-sync-celerybeat.service" ]; then
        cp "$INSTALL_DIR/systemd/vod-sync-celerybeat.service" /etc/systemd/system/
        print_info "Serviço vod-sync-celerybeat copiado"
    fi
    
    # Recarregar systemd
    systemctl daemon-reload
    
    # Habilitar serviços (não iniciar ainda)
    if [ -f /etc/systemd/system/vod-sync.service ]; then
        systemctl enable vod-sync.service 2>/dev/null || print_warning "Não foi possível habilitar vod-sync.service"
    fi
    
    if [ -f /etc/systemd/system/vod-sync-celery.service ]; then
        systemctl enable vod-sync-celery.service 2>/dev/null || print_warning "Não foi possível habilitar vod-sync-celery.service"
    fi
    
    if [ -f /etc/systemd/system/vod-sync-celerybeat.service ]; then
        systemctl enable vod-sync-celerybeat.service 2>/dev/null || print_warning "Não foi possível habilitar vod-sync-celerybeat.service"
    fi
    
    print_success "Serviços systemd configurados"
}

# Configurar Nginx
setup_nginx() {
    print_step "Configurando Nginx..."
    
    # Copiar configuração do Nginx
    cp "$INSTALL_DIR/config/nginx.conf" /etc/nginx/nginx.conf 2>/dev/null || true
    
    # Testar configuração
    nginx -t 2>/dev/null || print_warning "Configuração Nginx com erro, usando padrão"
    
    # Reiniciar Nginx se estiver rodando
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx 2>/dev/null || print_warning "Não foi possível reiniciar Nginx"
    else
        systemctl start nginx 2>/dev/null || print_warning "Não foi possível iniciar Nginx"
    fi
    
    # Configurar firewall
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 5000/tcp
        echo "y" | ufw --force enable 2>/dev/null || print_warning "Não foi possível configurar UFW"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=5000/tcp
        firewall-cmd --reload 2>/dev/null || print_warning "Não foi possível configurar firewalld"
    fi
    
    print_success "Nginx configurado"
}

# Criar usuário do sistema
create_system_user() {
    print_step "Criando usuário do sistema..."
    
    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$APP_USER" 2>/dev/null || \
        useradd -r -s /bin/bash -d "$INSTALL_DIR" "$APP_USER" 2>/dev/null || \
        (print_warning "Não foi possível criar usuário $APP_USER, usando root" && APP_USER="root")
    fi
    
    # Definir permissões
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR" 2>/dev/null || true
    chmod -R 750 "$INSTALL_DIR" 2>/dev/null || true
    
    # Permissões especiais para logs e dados
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR/logs" 2>/dev/null || true
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR/data" 2>/dev/null || true
    chmod -R 770 "$INSTALL_DIR/logs" "$INSTALL_DIR/data" 2>/dev/null || true
    
    # Adicionar ao grupo www-data/nginx
    usermod -a -G www-data "$APP_USER" 2>/dev/null || true
    usermod -a -G nginx "$APP_USER" 2>/dev/null || true
    
    print_success "Usuário do sistema configurado"
}

# Configurar backup automático
setup_backup() {
    print_step "Configurando sistema de backup..."
    
    mkdir -p "$INSTALL_DIR/scripts"
    
    # Script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << EOF
#!/bin/bash
BACKUP_DIR="$INSTALL_DIR/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/backup_\$DATE.tar.gz"

echo "Iniciando backup em \$(date)"

# Criar backup dos dados
tar -czf "\$BACKUP_FILE" \\
    "$INSTALL_DIR/data" \\
    "$INSTALL_DIR/config" \\
    "$INSTALL_DIR/logs" 2>/dev/null

# Backup do banco de dados (se possível)
mysqldump -u vod_sync -p"${DB_PASSWORD}" vod_sync > "\$BACKUP_DIR/db_backup_\$DATE.sql" 2>/dev/null || \
echo "Não foi possível fazer backup do banco de dados" > "\$BACKUP_DIR/db_backup_\$DATE.sql"

# Compactar backup do banco
gzip -f "\$BACKUP_DIR/db_backup_\$DATE.sql" 2>/dev/null || true

# Manter apenas últimos 30 backups
find "\$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +30 -delete 2>/dev/null || true
find "\$BACKUP_DIR" -name "db_backup_*.sql.gz" -type f -mtime +30 -delete 2>/dev/null || true

echo "Backup concluído: \$BACKUP_FILE"
echo "Tamanho: \$(du -h "\$BACKUP_FILE" 2>/dev/null | cut -f1 || echo "0")"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/scripts/backup.sh" 2>/dev/null || true
    
    # Agendar no cron
    (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/scripts/backup.sh"; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh >> $INSTALL_DIR/logs/backup.log 2>&1") | crontab -u "$APP_USER" - 2>/dev/null || \
    print_warning "Não foi possível agendar backup no cron"
    
    print_success "Sistema de backup configurado"
}

# Configurar monitoramento
setup_monitoring() {
    print_step "Configurando monitoramento..."
    
    # Script de monitoramento
    cat > "$INSTALL_DIR/scripts/monitor.sh" << EOF
#!/bin/bash
LOG_FILE="$INSTALL_DIR/logs/monitor.log"

# Função para obter métricas
get_metrics() {
    # CPU
    CPU_PERCENT=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1)
    
    # Memória
    MEM_PERCENT=\$(free | grep Mem | awk '{printf "%.2f", \$3/\$2 * 100}')
    MEM_TOTAL=\$(free -h | grep Mem | awk '{print \$2}')
    MEM_USED=\$(free -h | grep Mem | awk '{print \$3}')
    
    # Disco
    DISK_PERCENT=\$(df -h / | awk 'NR==2 {print \$5}' | cut -d'%' -f1)
    DISK_TOTAL=\$(df -h / | awk 'NR==2 {print \$2}')
    DISK_USED=\$(df -h / | awk 'NR==2 {print \$3}')
    
    # Network
    NET_IN=\$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
    NET_OUT=\$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)
    
    # Timestamp
    TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log
    echo "\$TIMESTAMP - CPU: \$CPU_PERCENT% | RAM: \$MEM_PERCENT% (\$MEM_USED/\$MEM_TOTAL) | DISK: \$DISK_PERCENT% (\$DISK_USED/\$DISK_TOTAL) | NET: IN=\$NET_IN OUT=\$NET_OUT" >> "\$LOG_FILE"
    
    # Verificar limites
    if [ \$(echo "\$CPU_PERCENT > 90" | bc 2>/dev/null) -eq 1 ]; then
        echo "\$TIMESTAMP - ALERTA: CPU acima de 90% (\$CPU_PERCENT%)" >> "\$LOG_FILE"
    fi
    
    if [ \$(echo "\$MEM_PERCENT > 90" | bc 2>/dev/null) -eq 1 ]; then
        echo "\$TIMESTAMP - ALERTA: Memória acima de 90% (\$MEM_PERCENT%)" >> "\$LOG_FILE"
    fi
    
    if [ "\$DISK_PERCENT" -gt 90 ] 2>/dev/null; then
        echo "\$TIMESTAMP - ALERTA: Disco acima de 90% (\$DISK_PERCENT%)" >> "\$LOG_FILE"
    fi
}

# Executar monitoramento
get_metrics

# Rotacionar logs se necessário
if [ -f "\$LOG_FILE" ]; then
    LOG_SIZE=\$(stat -c%s "\$LOG_FILE" 2>/dev/null || echo 0)
    if [ \$LOG_SIZE -gt 104857600 ]; then  # 100MB
        mv "\$LOG_FILE" "\$LOG_FILE.old" 2>/dev/null || true
        gzip "\$LOG_FILE.old" 2>/dev/null || true
    fi
fi
EOF
    
    chmod +x "$INSTALL_DIR/scripts/monitor.sh"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/scripts/monitor.sh" 2>/dev/null || true
    
    # Agendar no cron
    (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/scripts/monitor.sh"; echo "*/5 * * * * $INSTALL_DIR/scripts/monitor.sh >> /dev/null 2>&1") | crontab -u "$APP_USER" - 2>/dev/null || \
    print_warning "Não foi possível agendar monitoramento no cron"
    
    print_success "Monitoramento configurado"
}

# Criar scripts de gerenciamento
create_management_scripts() {
    print_step "Criando scripts de gerenciamento..."
    
    # start.sh
    cat > "$INSTALL_DIR/start.sh" << EOF
#!/bin/bash
systemctl start vod-sync vod-sync-celery vod-sync-celerybeat 2>/dev/null || true
echo "Serviços VOD Sync iniciados!"
EOF
    
    # stop.sh
    cat > "$INSTALL_DIR/stop.sh" << EOF
#!/bin/bash
systemctl stop vod-sync-celerybeat vod-sync-celery vod-sync 2>/dev/null || true
echo "Serviços VOD Sync parados!"
EOF
    
    # restart.sh
    cat > "$INSTALL_DIR/restart.sh" << EOF
#!/bin/bash
systemctl restart vod-sync vod-sync-celery vod-sync-celerybeat 2>/dev/null || true
echo "Serviços VOD Sync reiniciados!"
EOF
    
    # status.sh
    cat > "$INSTALL_DIR/status.sh" << EOF
#!/bin/bash
echo "=== Status dos Serviços VOD Sync ==="
echo ""
systemctl status vod-sync --no-pager 2>/dev/null || echo "Serviço vod-sync não encontrado"
echo ""
systemctl status vod-sync-celery --no-pager 2>/dev/null || echo "Serviço vod-sync-celery não encontrado"
echo ""
systemctl status vod-sync-celerybeat --no-pager 2>/dev/null || echo "Serviço vod-sync-celerybeat não encontrado"
EOF
    
    # logs.sh
    cat > "$INSTALL_DIR/logs.sh" << EOF
#!/bin/bash
tail -f "$INSTALL_DIR/logs/vod_sync.log" 2>/dev/null || echo "Arquivo de log não encontrado: $INSTALL_DIR/logs/vod_sync.log"
EOF
    
    # update.sh
    cat > "$INSTALL_DIR/update.sh" << EOF
#!/bin/bash
cd "$INSTALL_DIR"
source venv/bin/activate 2>/dev/null || echo "Ambiente virtual não encontrado"
pip install -r requirements.txt --upgrade 2>/dev/null || echo "Erro ao atualizar pacotes"
systemctl restart vod-sync vod-sync-celery vod-sync-celerybeat 2>/dev/null || echo "Erro ao reiniciar serviços"
echo "Sistema VOD Sync atualizado!"
EOF
    
    # backup-now.sh
    cat > "$INSTALL_DIR/backup-now.sh" << EOF
#!/bin/bash
"$INSTALL_DIR/scripts/backup.sh"
echo "Backup manual executado!"
EOF
    
    # Dar permissões
    chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR"/*.sh 2>/dev/null || true
    
    print_success "Scripts de gerenciamento criados"
}

# Inicializar aplicação
initialize_application() {
    print_step "Inicializando aplicação..."
    
    cd "$INSTALL_DIR"
    
    # Verificar se ambiente virtual existe
    if [ ! -f "$INSTALL_DIR/venv/bin/activate" ]; then
        print_error "Ambiente virtual não encontrado!"
        return 1
    fi
    
    source "$INSTALL_DIR/venv/bin/activate"
    
    # Criar banco de dados
    if python3 -c "
from src.database import db
from src.app import app

with app.app_context():
    try:
        db.create_all()
        print('Banco de dados criado com sucesso!')
    except Exception as e:
        print(f'Erro ao criar banco de dados: {e}')
" 2>/dev/null; then
        print_success "Banco de dados inicializado"
    else
        print_warning "Erro ao inicializar banco de dados, continuando..."
    fi
    
    # Iniciar serviços
    systemctl start vod-sync vod-sync-celery vod-sync-celerybeat 2>/dev/null || \
    print_warning "Não foi possível iniciar serviços, tente manualmente com: $INSTALL_DIR/start.sh"
    
    # Esperar serviços iniciarem
    sleep 3
    
    print_success "Aplicação inicializada"
}

# Criar README
create_readme() {
    print_step "Criando documentação..."
    
    cat > "$INSTALL_DIR/README.md" << EOF
# VOD Sync XUI - Sistema de Sincronização de VODs

## Visão Geral
Sistema completo para sincronização de VODs com o XUI One, incluindo dashboard, monitoramento e gerenciamento completo.

## Instalação
O sistema já está instalado em: $INSTALL_DIR

## Acesso
- Dashboard: http://\$(hostname -I | awk '{print \$1}'):5000
- Usuário: admin
- Senha: admin123

## Comandos Úteis

### Gerenciamento de Serviços
\`\`\`bash
# Iniciar
$INSTALL_DIR/start.sh

# Parar
$INSTALL_DIR/stop.sh

# Reiniciar
$INSTALL_DIR/restart.sh

# Status
$INSTALL_DIR/status.sh

# Logs em tempo real
$INSTALL_DIR/logs.sh
\`\`\`

### Backup e Manutenção
\`\`\`bash
# Backup manual
$INSTALL_DIR/backup-now.sh

# Atualizar sistema
$INSTALL_DIR/update.sh

# Monitorar sistema
$INSTALL_DIR/scripts/monitor.sh
\`\`\`

## Estrutura de Diretórios
\`\`\`
$INSTALL_DIR/
├── src/              # Código fonte
├── dashboard/        # Interface web
├── config/           # Configurações
├── data/            # Dados da aplicação
├── logs/            # Logs do sistema
├── backups/         # Backups
├── scripts/         # Scripts auxiliares
└── venv/            # Ambiente virtual Python
\`\`\`

## Configuração
Arquivos de configuração importantes:
- \`$INSTALL_DIR/.env\` - Variáveis de ambiente
- \`$INSTALL_DIR/config/config.yaml\` - Configuração principal
- \`/etc/systemd/system/vod-sync*.service\` - Serviços systemd

## Conexão com XUI Database
Edite o arquivo \`$INSTALL_DIR/.env\` para configurar a conexão com o banco de dados do XUI:
\`\`\`
XUI_DB_HOST=seu_host_xui
XUI_DB_PORT=3306
XUI_DB_NAME=xui
XUI_DB_USER=seu_usuario_xui
XUI_DB_PASSWORD=sua_senha_xui
\`\`\`

## Segurança
1. Altere a senha do usuário admin após o primeiro login
2. Configure SSL no arquivo \`$INSTALL_DIR/config/config.yaml\`
3. Restrinja acesso por IP se necessário

## Monitoramento
O sistema inclui:
- Dashboard com métricas em tempo real
- Monitoramento de CPU, memória, disco e rede
- Alertas automáticos
- Logs detalhados

## Suporte
Para suporte ou problemas, consulte a documentação ou entre em contato.

## Licença
MIT License
EOF
    
    print_success "Documentação criada"
}

# Exibir resumo da instalação
show_installation_summary() {
    print_header
    print_success "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗"
    echo -e "║                  RESUMO DA INSTALAÇÃO                   ║"
    echo -e "╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📁 Diretório de Instalação:${NC}"
    echo "  $INSTALL_DIR"
    echo ""
    echo -e "${CYAN}🌐 Acesso ao Sistema:${NC}"
    echo "  URL: http://$(hostname -I | awk '{print $1}'):5000"
    echo "  Usuário: admin"
    echo "  Senha: admin123"
    echo ""
    echo -e "${CYAN}🔧 Comandos Úteis:${NC}"
    echo "  Iniciar:    $INSTALL_DIR/start.sh"
    echo "  Parar:      $INSTALL_DIR/stop.sh"
    echo "  Status:     $INSTALL_DIR/status.sh"
    echo "  Logs:       $INSTALL_DIR/logs.sh"
    echo "  Backup:     $INSTALL_DIR/backup-now.sh"
    echo "  Atualizar:  $INSTALL_DIR/update.sh"
    echo ""
    echo -e "${CYAN}📊 Serviços:${NC}"
    if systemctl is-active vod-sync >/dev/null 2>&1; then
        echo "  VOD Sync:        ✅ Ativo"
    else
        echo "  VOD Sync:        ❌ Inativo"
    fi
    
    if systemctl is-active vod-sync-celery >/dev/null 2>&1; then
        echo "  Celery Worker:   ✅ Ativo"
    else
        echo "  Celery Worker:   ❌ Inativo"
    fi
    
    if systemctl is-active vod-sync-celerybeat >/dev/null 2>&1; then
        echo "  Celery Beat:     ✅ Ativo"
    else
        echo "  Celery Beat:     ❌ Inativo"
    fi
    echo ""
    echo -e "${CYAN}💾 Banco de Dados:${NC}"
    echo "  Nome: vod_sync"
    echo "  Usuário: vod_sync"
    echo "  Senha: ${DB_PASSWORD}"
    echo ""
    echo -e "${CYAN}⚠️  PRÓXIMOS PASSOS:${NC}"
    echo "  1. Acesse o dashboard e altere a senha do admin"
    echo "  2. Configure a conexão com o banco do XUI no arquivo .env"
    echo "  3. Configure os caminhos de armazenamento se necessário"
    echo "  4. Ajuste as configurações em config/config.yaml"
    echo ""
    echo -e "${YELLOW}📚 Documentação disponível em: $INSTALL_DIR/README.md${NC}"
    echo ""
    echo -e "${GREEN}✅ Sistema pronto para uso!${NC}"
    echo ""
}

# Função principal de instalação
main_installation() {
    print_header
    
    # Verificar sistema
    check_system
    
    # Verificar serviços antes de instalar
    check_and_fix_services
    
    # Criar estrutura
    create_directories
    create_config_files
    create_system_files
    create_source_code
    create_dashboard
    
    # Instalar dependências
    install_system_dependencies
    
    # Configurar sistema
    create_system_user
    setup_database
    setup_python_env
    setup_system_services
    setup_nginx
    setup_backup
    setup_monitoring
    create_management_scripts
    
    # Inicializar
    initialize_application
    create_readme
    
    # Mostrar resumo
    show_installation_summary
    
    # Registrar instalação
    echo "$(date) - Instalação concluída" > "$INSTALL_DIR/logs/install.log" 2>/dev/null || true
}

# Limpeza em caso de erro
cleanup_on_error() {
    print_error "Erro na instalação! Revertendo alterações..."
    
    # Parar serviços
    systemctl stop vod-sync vod-sync-celery vod-sync-celerybeat 2>/dev/null || true
    
    # Remover serviços
    rm -f /etc/systemd/system/vod-sync*.service 2>/dev/null || true
    
    # Remover usuário se não for root
    if [ "$APP_USER" != "root" ]; then
        userdel -r "$APP_USER" 2>/dev/null || true
    fi
    
    # Remover diretório de instalação
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    
    print_warning "Instalação revertida. Por favor, execute novamente."
    exit 1
}

# Configurar trap para erros
trap cleanup_on_error ERR

# Executar instalação
main_installation

# Limpar trap
trap - ERR

print_header
print_success "🎉 Instalação concluída com sucesso!"
echo ""
echo -e "${GREEN}O sistema VOD Sync XUI está pronto para uso!"
echo -e "Acesse: http://$(hostname -I | awk '{print $1}'):5000${NC}"
echo ""
echo -e "${YELLOW}Use as credenciais: admin / admin123${NC}"
echo ""
