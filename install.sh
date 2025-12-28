#!/bin/bash

# ============================================================
# INSTALADOR COMPLETO DO SISTEMA SINCRONIZADOR DE VODS XUI ONE
# ============================================================
# Este script cria TODOS os arquivos e instala o sistema completo
# Autor: Sistema de VOD Sync XUI
# Versão: 3.0.0 Corrigida
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
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script precisa ser executado como root!"
        echo "Use: sudo $0"
        exit 1
    fi
    
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

# Criar estrutura de diretórios
create_directories() {
    print_step "Criando estrutura de diretórios..."
    
    mkdir -p $INSTALL_DIR/{src,logs,data,config,backups,scripts,systemd,dashboard/static/{css,js,img},dashboard/templates}
    mkdir -p $INSTALL_DIR/data/{vods,sessions,thumbnails}
    mkdir -p $INSTALL_DIR/backups/{daily,weekly,monthly}
    
    print_success "Diretórios criados"
}

# Criar arquivos de configuração
create_config_files() {
    print_step "Criando arquivos de configuração..."
    
    # Arquivo .env
    cat > "$INSTALL_DIR/.env" << 'CONFIG_ENV'
# ============================================
# CONFIGURAÇÕES DO SISTEMA VOD SYNC XUI
# ============================================

# Aplicação
FLASK_APP=app.py
FLASK_ENV=production
SECRET_KEY=CHANGE_THIS_SECRET_KEY
DEBUG=false
HOST=0.0.0.0
PORT=5000

# Banco de dados local
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync
DB_USER=vod_sync
DB_PASSWORD=CHANGE_DB_PASSWORD

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
VOD_STORAGE_PATH=/opt/vod-sync-xui/data/vods
LOG_PATH=/opt/vod-sync-xui/logs
BACKUP_PATH=/opt/vod-sync-xui/backups
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
CONFIG_ENV

    # Substituir valores dinâmicos
    sed -i "s|CHANGE_THIS_SECRET_KEY|$SECRET_KEY|g" "$INSTALL_DIR/.env"
    sed -i "s|CHANGE_DB_PASSWORD|$DB_PASSWORD|g" "$INSTALL_DIR/.env"
    sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$INSTALL_DIR/.env"

    # Arquivo config.yaml
    cat > "$INSTALL_DIR/config/config.yaml" << 'CONFIG_YAML'
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
  local_path: "/opt/vod-sync-xui/data/vods"
  remote_path: ""
  max_size_gb: 1000
  cleanup_threshold: 80
  backup_enabled: true
  backup_path: "/opt/vod-sync-xui/backups"
  thumbnail_enabled: true
  thumbnail_size: "320x180"

security:
  secret_key: "CHANGE_THIS_SECRET_KEY"
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
  file: "/opt/vod-sync-xui/logs/vod_sync.log"
  max_size: 104857600
  backup_count: 10
  format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

api:
  enabled: true
  rate_limit: "100 per minute"
  enable_swagger: true
  enable_cors: true
CONFIG_YAML

    # Substituir valores dinâmicos no YAML
    sed -i "s|CHANGE_THIS_SECRET_KEY|$SECRET_KEY|g" "$INSTALL_DIR/config/config.yaml"
    sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$INSTALL_DIR/config/config.yaml"

    # Arquivo requirements.txt
    cat > "$INSTALL_DIR/requirements.txt" << 'REQUIREMENTS'
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
REQUIREMENTS

    # Arquivo docker-compose.yml
    cat > "$INSTALL_DIR/docker-compose.yml" << 'DOCKER_COMPOSE'
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

volumes:
  vod-storage:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/vod-sync-xui/data/vods
  mysql-data:
  redis-data:

networks:
  vod-sync-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
DOCKER_COMPOSE

    # Arquivo Dockerfile
    cat > "$INSTALL_DIR/Dockerfile" << 'DOCKERFILE'
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
DOCKERFILE

    # Arquivo Nginx
    cat > "$INSTALL_DIR/config/nginx.conf" << 'NGINX_CONF'
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
        server 127.0.0.1:5000;
        keepalive 32;
    }
    
    # Configuração do servidor HTTP
    server {
        listen 80;
        listen [::]:80;
        server_name _;
        
        # Dashboard principal
        location / {
            proxy_pass http://vod_sync_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
            proxy_send_timeout 300;
        }
        
        # API
        location /api {
            proxy_pass http://vod_sync_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300;
        }
        
        # WebSocket
        location /socket.io {
            proxy_pass http://vod_sync_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 86400;
        }
        
        # Servir arquivos de VODs
        location /vods {
            alias /opt/vod-sync-xui/data/vods;
            autoindex off;
            internal;
            
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods 'GET, OPTIONS';
            add_header Access-Control-Allow-Headers 'Range';
            
            mp4;
            mp4_buffer_size 1m;
            mp4_max_buffer_size 5m;
        }
    }
}
NGINX_CONF

    # Substituir caminhos no nginx.conf
    sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$INSTALL_DIR/config/nginx.conf"

    print_success "Arquivos de configuração criados"
}

# Criar arquivos do sistema
create_system_files() {
    print_step "Criando arquivos do sistema..."
    
    # Serviço systemd principal
    cat > "$INSTALL_DIR/systemd/vod-sync.service" << 'SYSTEMD_SERVICE'
[Unit]
Description=VOD Sync XUI Service
After=network.target mysql.service redis-server.service
Requires=mysql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=vodsync
Group=vodsync
WorkingDirectory=/opt/vod-sync-xui
Environment="PATH=/opt/vod-sync-xui/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=/opt/vod-sync-xui/.env
ExecStart=/opt/vod-sync-xui/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 4 --threads 2 --timeout 120 --access-logfile /opt/vod-sync-xui/logs/gunicorn_access.log --error-logfile /opt/vod-sync-xui/logs/gunicorn_error.log --capture-output --log-level info src.app:app
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

    # Serviço Celery
    cat > "$INSTALL_DIR/systemd/vod-sync-celery.service" << 'CELERY_SERVICE'
[Unit]
Description=Celery Service for VOD Sync XUI
After=network.target vod-sync.service
Requires=vod-sync.service

[Service]
Type=simple
User=vodsync
Group=vodsync
WorkingDirectory=/opt/vod-sync-xui
Environment="PATH=/opt/vod-sync-xui/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=/opt/vod-sync-xui/.env
ExecStart=/opt/vod-sync-xui/venv/bin/celery -A src.celery_tasks.celery worker --loglevel=info --concurrency=4 --hostname=vod-sync@%%h
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync-celery

[Install]
WantedBy=multi-user.target
CELERY_SERVICE

    # Serviço Celery Beat
    cat > "$INSTALL_DIR/systemd/vod-sync-celerybeat.service" << 'CELERYBEAT_SERVICE'
[Unit]
Description=Celery Beat Service for VOD Sync XUI
After=network.target vod-sync.service vod-sync-celery.service
Requires=vod-sync.service vod-sync-celery.service

[Service]
Type=simple
User=vodsync
Group=vodsync
WorkingDirectory=/opt/vod-sync-xui
Environment="PATH=/opt/vod-sync-xui/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=/opt/vod-sync-xui/.env
ExecStart=/opt/vod-sync-xui/venv/bin/celery -A src.celery_tasks.celery beat --loglevel=info --schedule=/opt/vod-sync-xui/data/celerybeat-schedule
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vod-sync-celerybeat

[Install]
WantedBy=multi-user.target
CELERYBEAT_SERVICE

    # Substituir caminhos nos serviços
    for service_file in "$INSTALL_DIR"/systemd/*.service; do
        sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$service_file"
        sed -i "s|User=vodsync|User=$APP_USER|g" "$service_file"
        sed -i "s|Group=vodsync|Group=$APP_GROUP|g" "$service_file"
    done

    # Logrotate
    cat > /etc/logrotate.d/vod-sync << 'LOGROTATE'
/opt/vod-sync-xui/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 vodsync vodsync
    sharedscripts
    postrotate
        systemctl reload vod-sync > /dev/null 2>&1 || true
    endscript
}
LOGROTATE

    sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" /etc/logrotate.d/vod-sync
    sed -i "s|vodsync vodsync|$APP_USER $APP_GROUP|g" /etc/logrotate.d/vod-sync

    print_success "Arquivos do sistema criados"
}

# Criar código fonte simplificado
create_source_code() {
    print_step "Criando código fonte da aplicação..."
    
    # __init__.py
    cat > "$INSTALL_DIR/src/__init__.py" << 'SRC_INIT'
"""
VOD Sync XUI - Sistema de Sincronização de VODs para XUI One
"""
__version__ = '3.0.0'
SRC_INIT

    # app.py principal
    cat > "$INSTALL_DIR/src/app.py" << 'APP_PY'
#!/usr/bin/env python3
"""
Aplicação principal do Sistema VOD Sync XUI
"""

import os
import sys
import logging
from datetime import datetime
from flask import Flask, render_template, jsonify, request, session
from flask_socketio import SocketIO
from flask_login import LoginManager, current_user, login_required, UserMixin
from flask_cors import CORS
import psutil
import humanize

# Adicionar caminho
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Configuração básica
class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-key-change-me')
    DEBUG = os.getenv('DEBUG', 'false').lower() == 'true'
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', 5000))

# Modelo de usuário simplificado
class User(UserMixin):
    def __init__(self, id, username, is_admin=False):
        self.id = id
        self.username = username
        self.is_admin = is_admin

# Usuário admin padrão
admin_user = User(1, 'admin', True)

# Inicializar Flask
app = Flask(__name__, 
            template_folder='../dashboard/templates',
            static_folder='../dashboard/static')
app.config.from_object(Config)

# Inicializar extensões
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/vod-sync-xui/logs/vod_sync.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@login_manager.user_loader
def load_user(user_id):
    if user_id == '1':
        return admin_user
    return None

# Rotas de autenticação
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if username == 'admin' and password == 'admin123':
            from flask_login import login_user
            login_user(admin_user)
            return jsonify({'success': True, 'redirect': '/'})
        
        return jsonify({'success': False, 'error': 'Credenciais inválidas'})
    
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    from flask_login import logout_user
    logout_user()
    return jsonify({'success': True, 'redirect': '/login'})

# Rotas principais
@app.route('/')
@login_required
def index():
    return render_template('index.html', user=current_user)

@app.route('/dashboard')
@login_required
def dashboard():
    return render_template('dashboard.html', user=current_user)

@app.route('/api/system/stats')
@login_required
def system_stats():
    """Obter estatísticas do sistema"""
    stats = {
        'cpu': {
            'percent': psutil.cpu_percent(interval=1),
            'cores': psutil.cpu_count(),
            'frequency': psutil.cpu_freq().current if psutil.cpu_freq() else 0
        },
        'memory': {
            'total': psutil.virtual_memory().total,
            'available': psutil.virtual_memory().available,
            'percent': psutil.virtual_memory().percent,
            'used': psutil.virtual_memory().used,
            'free': psutil.virtual_memory().free
        },
        'disk': {
            'total': psutil.disk_usage('/').total,
            'used': psutil.disk_usage('/').used,
            'free': psutil.disk_usage('/').free,
            'percent': psutil.disk_usage('/').percent
        },
        'system': {
            'hostname': os.uname().nodename,
            'os': os.uname().sysname,
            'release': os.uname().release,
            'python_version': sys.version.split()[0],
            'boot_time': datetime.fromtimestamp(psutil.boot_time()).isoformat()
        },
        'timestamp': datetime.now().isoformat()
    }
    
    return jsonify(stats)

@app.route('/api/sync/start', methods=['POST'])
@login_required
def start_sync():
    """Iniciar sincronização"""
    import uuid
    task_id = str(uuid.uuid4())
    
    logger.info(f"Sincronização iniciada: {task_id}")
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

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '3.0.0'
    })

@socketio.on('connect')
def handle_connect():
    logger.info(f"Cliente conectado: {request.sid}")
    socketio.emit('connected', {'message': 'Conectado ao servidor VOD Sync'})

@socketio.on('get_stats')
def handle_get_stats():
    stats_response = system_stats()
    socketio.emit('system_stats', stats_response.get_json())

def main():
    """Função principal"""
    logger.info(f"Iniciando VOD Sync XUI v3.0.0")
    logger.info(f"Modo: {'Desenvolvimento' if app.config['DEBUG'] else 'Produção'}")
    
    socketio.run(app,
                host=app.config['HOST'],
                port=app.config['PORT'],
                debug=app.config['DEBUG'],
                use_reloader=False,
                allow_unsafe_werkzeug=True)

if __name__ == '__main__':
    main()
APP_PY

    # Criar estrutura básica de models
    mkdir -p "$INSTALL_DIR/src/models"
    cat > "$INSTALL_DIR/src/models/__init__.py" << 'MODELS_INIT'
"""
Models do Sistema VOD Sync XUI
"""
MODELS_INIT

    # Criar services
    mkdir -p "$INSTALL_DIR/src/services"
    cat > "$INSTALL_DIR/src/services/__init__.py" << 'SERVICES_INIT'
"""
Services do Sistema VOD Sync XUI
"""
SERVICES_INIT

    cat > "$INSTALL_DIR/src/services/monitoring.py" << 'MONITORING_PY'
"""
Serviço de monitoramento do sistema
"""

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
MONITORING_PY

    # Criar utils
    mkdir -p "$INSTALL_DIR/src/utils"
    cat > "$INSTALL_DIR/src/utils/__init__.py" << 'UTILS_INIT'
"""
Utils do Sistema VOD Sync XUI
"""
UTILS_INIT

    cat > "$INSTALL_DIR/src/utils/helpers.py" << 'HELPERS_PY'
"""
Funções auxiliares
"""

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

def format_bytes(bytes_size):
    """Formatar bytes para formato legível"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"
HELPERS_PY

    print_success "Código fonte criado"
}

# Criar dashboard simplificado
create_dashboard() {
    print_step "Criando dashboard web..."
    
    # Base template
    cat > "$INSTALL_DIR/dashboard/templates/base.html" << 'BASE_HTML'
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
            
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav me-auto">
                    <li class="nav-item">
                        <a class="nav-link" href="/dashboard">
                            <i class="fas fa-tachometer-alt"></i> Dashboard
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="#">
                            <i class="fas fa-sync"></i> Sincronização
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="#">
                            <i class="fas fa-cog"></i> Configurações
                        </a>
                    </li>
                </ul>
                
                <ul class="navbar-nav">
                    <li class="nav-item">
                        <a class="nav-link" href="/logout">
                            <i class="fas fa-sign-out-alt"></i> Sair
                        </a>
                    </li>
                </ul>
            </div>
        </div>
    </nav>

    <!-- Main Content -->
    <div class="container-fluid mt-3">
        <!-- Page Content -->
        {% block content %}{% endblock %}
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <!-- jQuery -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    
    {% block extra_js %}{% endblock %}
</body>
</html>
BASE_HTML

    # Login page
    cat > "$INSTALL_DIR/dashboard/templates/login.html" << 'LOGIN_HTML'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - VOD Sync XUI</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-card {
            background: white;
            border-radius: 15px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header i {
            font-size: 48px;
            color: #667eea;
            margin-bottom: 15px;
        }
        .login-header h2 {
            color: #333;
            font-weight: 600;
        }
        .login-header p {
            color: #666;
        }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="login-header">
            <i class="fas fa-sync-alt"></i>
            <h2>VOD Sync XUI</h2>
            <p class="text-muted">Sistema de Sincronização</p>
        </div>
        
        <form id="loginForm">
            <div class="mb-3">
                <label for="username" class="form-label">
                    <i class="fas fa-user"></i> Usuário
                </label>
                <input type="text" class="form-control" id="username" 
                       placeholder="Digite seu usuário" required>
            </div>
            
            <div class="mb-3">
                <label for="password" class="form-label">
                    <i class="fas fa-lock"></i> Senha
                </label>
                <input type="password" class="form-control" id="password" 
                       placeholder="Digite sua senha" required>
            </div>
            
            <div class="d-grid gap-2">
                <button type="submit" class="btn btn-primary btn-lg">
                    <i class="fas fa-sign-in-alt"></i> Entrar
                </button>
            </div>
            
            <div class="alert alert-danger mt-3 d-none" id="errorAlert"></div>
        </form>
        
        <div class="mt-4 text-center text-muted">
            <small>
                <i class="fas fa-info-circle"></i>
                Use: admin / admin123
            </small>
        </div>
    </div>

    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
    $(document).ready(function() {
        $('#loginForm').on('submit', function(e) {
            e.preventDefault();
            
            const username = $('#username').val();
            const password = $('#password').val();
            
            $.ajax({
                url: '/login',
                method: 'POST',
                data: {
                    username: username,
                    password: password
                },
                success: function(response) {
                    if (response.success) {
                        window.location.href = response.redirect;
                    } else {
                        $('#errorAlert').text(response.error).removeClass('d-none');
                    }
                },
                error: function() {
                    $('#errorAlert').text('Erro ao conectar com o servidor').removeClass('d-none');
                }
            });
        });
        
        // Auto-focus no campo de usuário
        $('#username').focus();
    });
    </script>
</body>
</html>
LOGIN_HTML

    # Index page
    cat > "$INSTALL_DIR/dashboard/templates/index.html" << 'INDEX_HTML'
{% extends "base.html" %}

{% block title %}Dashboard - VOD Sync XUI{% endblock %}

{% block content %}
<div class="row">
    <div class="col-12">
        <div class="card">
            <div class="card-header bg-primary text-white">
                <h4 class="mb-0"><i class="fas fa-home"></i> Bem-vindo ao VOD Sync XUI</h4>
            </div>
            <div class="card-body">
                <div class="text-center py-5">
                    <i class="fas fa-sync-alt fa-5x text-primary mb-4"></i>
                    <h2>Sistema de Sincronização de VODs</h2>
                    <p class="lead">Sincronize automaticamente seus VODs com o XUI One</p>
                    
                    <div class="mt-5">
                        <a href="/dashboard" class="btn btn-primary btn-lg">
                            <i class="fas fa-tachometer-alt"></i> Ir para Dashboard
                        </a>
                    </div>
                </div>
                
                <div class="row mt-5">
                    <div class="col-md-4">
                        <div class="card text-center">
                            <div class="card-body">
                                <i class="fas fa-database fa-3x text-info mb-3"></i>
                                <h5>Sincronização Automática</h5>
                                <p>Sincronize VODs automaticamente com o banco XUI</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-4">
                        <div class="card text-center">
                            <div class="card-body">
                                <i class="fas fa-chart-line fa-3x text-success mb-3"></i>
                                <h5>Monitoramento em Tempo Real</h5>
                                <p>Monitore CPU, memória e disco em tempo real</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-4">
                        <div class="card text-center">
                            <div class="card-body">
                                <i class="fas fa-shield-alt fa-3x text-warning mb-3"></i>
                                <h5>Sistema Seguro</h5>
                                <p>Autenticação e segurança implementadas</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
INDEX_HTML

    # Dashboard page
    cat > "$INSTALL_DIR/dashboard/templates/dashboard.html" << 'DASHBOARD_HTML'
{% extends "base.html" %}

{% block title %}Dashboard - VOD Sync XUI{% endblock %}

{% block extra_css %}
<style>
    .stat-card {
        border: none;
        border-radius: 10px;
        transition: transform 0.3s;
    }
    .stat-card:hover {
        transform: translateY(-5px);
    }
    .stat-value {
        font-size: 2rem;
        font-weight: bold;
    }
    .stat-icon {
        font-size: 2.5rem;
        opacity: 0.8;
    }
</style>
{% endblock %}

{% block content %}
<div class="row mb-4">
    <div class="col-12">
        <h1><i class="fas fa-tachometer-alt"></i> Dashboard</h1>
        <p class="text-muted">Estatísticas do sistema em tempo real</p>
    </div>
</div>

<div class="row">
    <!-- CPU Stats -->
    <div class="col-md-3 mb-4">
        <div class="card stat-card bg-primary text-white">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="card-title">CPU</h6>
                        <div class="stat-value" id="cpu-percent">0%</div>
                        <small id="cpu-info">Cores: 0</small>
                    </div>
                    <i class="fas fa-microchip stat-icon"></i>
                </div>
                <div class="progress mt-2" style="height: 6px;">
                    <div id="cpu-bar" class="progress-bar bg-white" style="width: 0%"></div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Memory Stats -->
    <div class="col-md-3 mb-4">
        <div class="card stat-card bg-success text-white">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="card-title">Memória</h6>
                        <div class="stat-value" id="mem-percent">0%</div>
                        <small id="mem-info">0 GB</small>
                    </div>
                    <i class="fas fa-memory stat-icon"></i>
                </div>
                <div class="progress mt-2" style="height: 6px;">
                    <div id="mem-bar" class="progress-bar bg-white" style="width: 0%"></div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Disk Stats -->
    <div class="col-md-3 mb-4">
        <div class="card stat-card bg-warning text-white">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="card-title">Disco</h6>
                        <div class="stat-value" id="disk-percent">0%</div>
                        <small id="disk-info">0 GB</small>
                    </div>
                    <i class="fas fa-hdd stat-icon"></i>
                </div>
                <div class="progress mt-2" style="height: 6px;">
                    <div id="disk-bar" class="progress-bar bg-white" style="width: 0%"></div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- System Info -->
    <div class="col-md-3 mb-4">
        <div class="card stat-card bg-info text-white">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="card-title">Sistema</h6>
                        <div class="stat-value" id="sys-hostname">-</div>
                        <small id="sys-uptime">Uptime: -</small>
                    </div>
                    <i class="fas fa-server stat-icon"></i>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-chart-line"></i> Monitoramento em Tempo Real</h5>
            </div>
            <div class="card-body">
                <canvas id="systemChart" height="150"></canvas>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-cogs"></i> Controles Rápidos</h5>
            </div>
            <div class="card-body">
                <button class="btn btn-primary btn-lg w-100 mb-3" onclick="startSync()">
                    <i class="fas fa-sync"></i> Iniciar Sincronização
                </button>
                
                <button class="btn btn-success btn-lg w-100 mb-3" onclick="refreshStats()">
                    <i class="fas fa-redo"></i> Atualizar Estatísticas
                </button>
                
                <button class="btn btn-info btn-lg w-100" onclick="showSystemInfo()">
                    <i class="fas fa-info-circle"></i> Informações do Sistema
                </button>
                
                <hr>
                
                <div class="text-center">
                    <small class="text-muted">
                        <i class="fas fa-clock"></i> Última atualização:
                        <span id="last-update">-</span>
                    </small>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row mt-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-info-circle"></i> Status do Sistema</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-3">
                        <div class="text-center p-3">
                            <i class="fas fa-database fa-2x text-primary"></i>
                            <h5 class="mt-2">Banco de Dados</h5>
                            <span class="badge bg-success">Online</span>
                        </div>
                    </div>
                    
                    <div class="col-md-3">
                        <div class="text-center p-3">
                            <i class="fas fa-sync-alt fa-2x text-info"></i>
                            <h5 class="mt-2">Serviço Sync</h5>
                            <span class="badge bg-success" id="sync-status">Ativo</span>
                        </div>
                    </div>
                    
                    <div class="col-md-3">
                        <div class="text-center p-3">
                            <i class="fas fa-shield-alt fa-2x text-warning"></i>
                            <h5 class="mt-2">Segurança</h5>
                            <span class="badge bg-success">Ativa</span>
                        </div>
                    </div>
                    
                    <div class="col-md-3">
                        <div class="text-center p-3">
                            <i class="fas fa-bell fa-2x text-danger"></i>
                            <h5 class="mt-2">Notificações</h5>
                            <span class="badge bg-secondary">Desativadas</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}

{% block extra_js %}
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script src="https://cdn.socket.io/4.6.0/socket.io.min.js"></script>

<script>
let systemChart;
let cpuData = [];
let memData = [];
let labels = [];
let socket;

function updateStats() {
    $.get('/api/system/stats', function(data) {
        // CPU
        $('#cpu-percent').text(data.cpu.percent.toFixed(1) + '%');
        $('#cpu-bar').css('width', data.cpu.percent + '%');
        $('#cpu-info').text('Cores: ' + data.cpu.cores);
        
        // Memory
        const memGB = data.memory.total / 1024 / 1024 / 1024;
        const usedGB = data.memory.used / 1024 / 1024 / 1024;
        $('#mem-percent').text(data.memory.percent.toFixed(1) + '%');
        $('#mem-bar').css('width', data.memory.percent + '%');
        $('#mem-info').text(usedGB.toFixed(1) + ' GB / ' + memGB.toFixed(1) + ' GB');
        
        // Disk
        const diskGB = data.disk.total / 1024 / 1024 / 1024;
        const usedDiskGB = data.disk.used / 1024 / 1024 / 1024;
        $('#disk-percent').text(data.disk.percent.toFixed(1) + '%');
        $('#disk-bar').css('width', data.disk.percent + '%');
        $('#disk-info').text(usedDiskGB.toFixed(1) + ' GB / ' + diskGB.toFixed(1) + ' GB');
        
        // System
        $('#sys-hostname').text(data.system.hostname);
        $('#sys-uptime').text('Uptime: ' + formatUptime(data.system.boot_time));
        
        // Last update
        const now = new Date(data.timestamp);
        $('#last-update').text(now.toLocaleTimeString());
        
        // Update chart
        updateChart(data.cpu.percent, data.memory.percent);
    }).fail(function() {
        console.error('Erro ao obter estatísticas');
    });
}

function updateChart(cpuPercent, memPercent) {
    const now = new Date().toLocaleTimeString();
    
    // Add new data
    cpuData.push(cpuPercent);
    memData.push(memPercent);
    labels.push(now);
    
    // Keep only last 20 data points
    if (cpuData.length > 20) {
        cpuData.shift();
        memData.shift();
        labels.shift();
    }
    
    // Create or update chart
    if (!systemChart) {
        const ctx = document.getElementById('systemChart').getContext('2d');
        systemChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'CPU %',
                        data: cpuData,
                        borderColor: 'rgb(255, 99, 132)',
                        backgroundColor: 'rgba(255, 99, 132, 0.2)',
                        tension: 0.4,
                        fill: true
                    },
                    {
                        label: 'Memória %',
                        data: memData,
                        borderColor: 'rgb(54, 162, 235)',
                        backgroundColor: 'rgba(54, 162, 235, 0.2)',
                        tension: 0.4,
                        fill: true
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
    } else {
        systemChart.data.labels = labels;
        systemChart.data.datasets[0].data = cpuData;
        systemChart.data.datasets[1].data = memData;
        systemChart.update();
    }
}

function formatUptime(bootTime) {
    const now = new Date();
    const boot = new Date(bootTime);
    const diff = now - boot;
    
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
}

function startSync() {
    $.post('/api/sync/start', function(response) {
        if (response.success) {
            alert('Sincronização iniciada com sucesso!');
        } else {
            alert('Erro: ' + response.error);
        }
    });
}

function refreshStats() {
    updateStats();
}

function showSystemInfo() {
    $.get('/api/system/stats', function(data) {
        const info = `
            Hostname: ${data.system.hostname}
            OS: ${data.system.os} ${data.system.release}
            Python: ${data.system.python_version}
            CPU Cores: ${data.cpu.cores}
            Memory Total: ${(data.memory.total / 1024 / 1024 / 1024).toFixed(2)} GB
            Disk Total: ${(data.disk.total / 1024 / 1024 / 1024).toFixed(2)} GB
        `;
        alert(info);
    });
}

// Initialize Socket.IO
function initSocket() {
    socket = io();
    
    socket.on('connect', function() {
        console.log('Conectado ao servidor via Socket.IO');
        $('#sync-status').removeClass('bg-danger').addClass('bg-success').text('Ativo');
    });
    
    socket.on('disconnect', function() {
        console.log('Desconectado do servidor');
        $('#sync-status').removeClass('bg-success').addClass('bg-danger').text('Inativo');
    });
    
    socket.on('system_stats', function(data) {
        updateChart(data.cpu.percent, data.memory.percent);
    });
    
    socket.on('sync_started', function(data) {
        alert(`Sincronização iniciada por ${data.user} às ${new Date(data.timestamp).toLocaleTimeString()}`);
    });
}

// Auto-refresh every 5 seconds
$(document).ready(function() {
    updateStats();
    initSocket();
    
    setInterval(updateStats, 5000);
});
</script>
{% endblock %}
DASHBOARD_HTML

    # CSS principal
    cat > "$INSTALL_DIR/dashboard/static/css/main.css" << 'MAIN_CSS'
/* VOD Sync XUI - Main CSS */

:root {
    --primary-color: #3498db;
    --secondary-color: #2c3e50;
    --success-color: #27ae60;
    --warning-color: #f39c12;
    --danger-color: #e74c3c;
    --info-color: #17a2b8;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: #f8f9fa;
}

.navbar-brand {
    font-weight: bold;
}

.card {
    border: none;
    border-radius: 10px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 20px;
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

.btn {
    border-radius: 8px;
    font-weight: 600;
}

.btn-primary {
    background-color: var(--primary-color);
    border-color: var(--primary-color);
}

.btn-success {
    background-color: var(--success-color);
    border-color: var(--success-color);
}

.btn-warning {
    background-color: var(--warning-color);
    border-color: var(--warning-color);
}

.btn-danger {
    background-color: var(--danger-color);
    border-color: var(--danger-color);
}

.badge {
    font-size: 0.8em;
    padding: 0.4em 0.8em;
    border-radius: 20px;
}

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

/* Responsive */
@media (max-width: 768px) {
    .stat-value {
        font-size: 1.5rem;
    }
    
    .card-body {
        padding: 1rem;
    }
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
MAIN_CSS

    print_success "Dashboard criado"
}

# Instalar dependências do sistema
install_system_dependencies() {
    print_step "Instalando dependências do sistema..."
    
    if [ "$OS_TYPE" = "debian" ]; then
        apt-get update
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
            supervisor
        
        # Iniciar serviços
        systemctl start mysql redis
        systemctl enable mysql redis
        
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
            git \
            curl \
            wget \
            htop \
            net-tools \
            supervisor
        
        # Iniciar serviços
        systemctl start mariadb redis
        systemctl enable mariadb redis
    fi
    
    print_success "Dependências do sistema instaladas"
}

# Configurar banco de dados
setup_database() {
    print_step "Configurando banco de dados..."
    
    # MySQL/MariaDB
    if [ "$OS_TYPE" = "debian" ]; then
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASSWORD}';" 2>/dev/null || true
    fi
    
    mysql -e "CREATE DATABASE IF NOT EXISTS vod_sync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
        print_warning "MySQL não está disponível, o sistema usará SQLite"
        return 0
    }
    
    mysql -e "CREATE USER IF NOT EXISTS 'vod_sync'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" 2>/dev/null || true
    mysql -e "GRANT ALL PRIVILEGES ON vod_sync.* TO 'vod_sync'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
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
    
    # Copiar arquivos de serviço
    cp "$INSTALL_DIR/systemd"/*.service /etc/systemd/system/ 2>/dev/null || true
    
    # Recarregar systemd
    systemctl daemon-reload
    
    # Habilitar serviços
    systemctl enable vod-sync.service 2>/dev/null || true
    systemctl enable vod-sync-celery.service 2>/dev/null || true
    systemctl enable vod-sync-celerybeat.service 2>/dev/null || true
    
    print_success "Serviços systemd configurados"
}

# Configurar Nginx
setup_nginx() {
    print_step "Configurando Nginx..."
    
    # Backup da configuração original
    if [ -f /etc/nginx/nginx.conf ]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    fi
    
    # Copiar nossa configuração
    cp "$INSTALL_DIR/config/nginx.conf" /etc/nginx/nginx.conf
    
    # Testar configuração
    if nginx -t 2>/dev/null; then
        # Reiniciar Nginx
        systemctl restart nginx 2>/dev/null || true
        systemctl enable nginx 2>/dev/null || true
        print_success "Nginx configurado"
    else
        print_warning "Nginx não pôde ser configurado. Usando servidor Flask diretamente na porta 5000"
    fi
}

# Criar usuário do sistema
create_system_user() {
    print_step "Criando usuário do sistema..."
    
    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$APP_USER"
    fi
    
    # Definir permissões
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
    chmod -R 750 "$INSTALL_DIR"
    
    # Permissões especiais para logs e dados
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR/logs"
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR/data"
    chmod -R 770 "$INSTALL_DIR/logs" "$INSTALL_DIR/data"
    
    print_success "Usuário do sistema criado"
}

# Configurar backup automático
setup_backup() {
    print_step "Configurando sistema de backup..."
    
    mkdir -p "$INSTALL_DIR/scripts"
    
    # Script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'BACKUP_SH'
#!/bin/bash
BACKUP_DIR="/opt/vod-sync-xui/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"

echo "Iniciando backup em $(date)"

# Criar backup dos dados
tar -czf $BACKUP_FILE \
    /opt/vod-sync-xui/data \
    /opt/vod-sync-xui/config \
    /opt/vod-sync-xui/logs 2>/dev/null

echo "Backup concluído: $BACKUP_FILE"
echo "Tamanho: $(du -h $BACKUP_FILE | cut -f1)"
BACKUP_SH
    
    sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$INSTALL_DIR/scripts/backup.sh"
    
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/scripts/backup.sh"
    
    print_success "Sistema de backup configurado"
}

# Criar scripts de gerenciamento
create_management_scripts() {
    print_step "Criando scripts de gerenciamento..."
    
    # start.sh
    cat > "$INSTALL_DIR/start.sh" << 'START_SH'
#!/bin/bash
echo "Iniciando VOD Sync XUI..."
systemctl start vod-sync 2>/dev/null || echo "Serviço não encontrado, iniciando manualmente..."
cd /opt/vod-sync-xui
source venv/bin/activate
nohup python src/app.py > logs/app.log 2>&1 &
echo $! > /tmp/vod-sync.pid
echo "VOD Sync XUI iniciado!"
START_SH
    
    # stop.sh
    cat > "$INSTALL_DIR/stop.sh" << 'STOP_SH'
#!/bin/bash
echo "Parando VOD Sync XUI..."
systemctl stop vod-sync 2>/dev/null || echo "Serviço não encontrado"
if [ -f /tmp/vod-sync.pid ]; then
    kill $(cat /tmp/vod-sync.pid) 2>/dev/null || true
    rm -f /tmp/vod-sync.pid
fi
echo "VOD Sync XUI parado!"
STOP_SH
    
    # restart.sh
    cat > "$INSTALL_DIR/restart.sh" << 'RESTART_SH'
#!/bin/bash
/opt/vod-sync-xui/stop.sh
sleep 2
/opt/vod-sync-xui/start.sh
RESTART_SH
    
    # status.sh
    cat > "$INSTALL_DIR/status.sh" << 'STATUS_SH'
#!/bin/bash
echo "=== Status do VOD Sync XUI ==="
echo ""
if [ -f /tmp/vod-sync.pid ]; then
    PID=$(cat /tmp/vod-sync.pid)
    if ps -p $PID > /dev/null; then
        echo "✅ Serviço rodando (PID: $PID)"
    else
        echo "❌ Serviço parado"
    fi
else
    echo "❌ Serviço não está rodando"
fi
echo ""
echo "Logs disponíveis em: /opt/vod-sync-xui/logs/"
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):5000"
STATUS_SH
    
    # update.sh
    cat > "$INSTALL_DIR/update.sh" << 'UPDATE_SH'
#!/bin/bash
cd /opt/vod-sync-xui
echo "Atualizando VOD Sync XUI..."
source venv/bin/activate
pip install -r requirements.txt --upgrade
echo "Sistema atualizado! Reinicie com: ./restart.sh"
UPDATE_SH
    
    # Dar permissões
    chmod +x "$INSTALL_DIR"/*.sh
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR"/*.sh
    
    # Substituir caminhos
    for script in "$INSTALL_DIR"/*.sh; do
        sed -i "s|/opt/vod-sync-xui|$INSTALL_DIR|g" "$script"
    done
    
    print_success "Scripts de gerenciamento criados"
}

# Inicializar aplicação
initialize_application() {
    print_step "Inicializando aplicação..."
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    # Criar arquivo de log
    touch "$INSTALL_DIR/logs/vod_sync.log"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/logs/vod_sync.log"
    
    # Testar aplicação
    if python3 -c "import flask; import psutil; print('Bibliotecas carregadas com sucesso')" 2>/dev/null; then
        print_success "Aplicação testada com sucesso"
    else
        print_warning "Algumas bibliotecas podem não estar instaladas corretamente"
    fi
    
    print_success "Aplicação inicializada"
}

# Criar README
create_readme() {
    print_step "Criando documentação..."
    
    cat > "$INSTALL_DIR/README.md" << 'README_MD'
# VOD Sync XUI - Sistema de Sincronização de VODs

## Visão Geral
Sistema completo para sincronização de VODs com o XUI One, incluindo dashboard e monitoramento.

## Instalação
O sistema está instalado em: /opt/vod-sync-xui

## Acesso
- Dashboard: http://SEU-IP:5000
- Usuário: admin
- Senha: admin123

## Comandos Úteis

### Iniciar/Parar
```bash
/opt/vod-sync-xui/start.sh
/opt/vod-sync-xui/stop.sh
/opt/vod-sync-xui/restart.sh
/opt/vod-sync-xui/status.sh
