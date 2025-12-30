#!/bin/bash

# ============================================
# INSTALADOR COMPLETO - SISTEMA VOD SYNC
# ============================================
# Versão: 2.0.0
# Data: $(date)
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis do sistema
VERSION="2.0.0"
INSTALL_DIR="/opt/vodsync"
LOG_FILE="/var/log/vodsync-install.log"
BACKUP_DIR="/backup/vodsync"
DOMAIN=""
EMAIL=""
MYSQL_ROOT_PASS=$(openssl rand -base64 32)
MYSQL_VOD_PASS=$(openssl rand -base64 32)
REDIS_PASS=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)
ADMIN_PASS=$(openssl rand -base64 12)

# Configuração de repositórios
REPO_URL="https://github.com/seu-usuario/vod-sync-system.git"
REPO_BRANCH="main"

# Funções de utilidade
print_header() {
    clear
    echo -e "${PURPLE}"
    echo -e "╔══════════════════════════════════════════════════════════════╗"
    echo -e "║                                                              ║"
    echo -e "║     ██╗   ██╗ ██████╗ ██████╗     ███████╗██╗   ██╗███╗   ██╗║"
    echo -e "║     ██║   ██║██╔═══██╗██╔══██╗    ██╔════╝╚██╗ ██╔╝████╗  ██║║"
    echo -e "║     ██║   ██║██║   ██║██║  ██║    ███████╗ ╚████╔╝ ██╔██╗ ██║║"
    echo -e "║     ╚██╗ ██╔╝██║   ██║██║  ██║    ╚════██║  ╚██╔╝  ██║╚██╗██║║"
    echo -e "║      ╚████╔╝ ╚██████╔╝██████╔╝    ███████║   ██║   ██║ ╚████║║"
    echo -e "║       ╚═══╝   ╚═════╝ ╚═════╝     ╚══════╝   ╚═╝   ╚═╝  ╚═══╝║"
    echo -e "║                                                              ║"
    echo -e "║                   SISTEMA DE SINCRONIZAÇÃO VOD               ║"
    echo -e "║                    INSTALADOR COMPLETO v$VERSION              ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "Este script precisa ser executado como root"
        exit 1
    fi
}

check_requirements() {
    log_message "INFO" "Verificando requisitos do sistema..."
    
    # Verificar sistema operacional
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_message "ERROR" "Não foi possível detectar o sistema operacional"
        exit 1
    fi
    
    log_message "INFO" "Sistema: $OS $VER"
    
    # Verificar arquitetura
    ARCH=$(uname -m)
    log_message "INFO" "Arquitetura: $ARCH"
    
    # Verificar memória
    MEMORY=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$MEMORY" -lt 1024 ]; then
        log_message "WARN" "Memória RAM baixa (${MEMORY}MB). Recomendado mínimo 1GB"
    fi
    
    # Verificar espaço em disco
    DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
    if [ "$DISK_SPACE" -lt 5242880 ]; then
        log_message "WARN" "Espaço em disco baixo ($((DISK_SPACE/1024))MB). Recomendado mínimo 5GB"
    fi
    
    return 0
}

install_dependencies() {
    log_message "INFO" "Instalando dependências do sistema..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        apt-get update -y >> "$LOG_FILE" 2>&1
        apt-get upgrade -y >> "$LOG_FILE" 2>&1
        
        # Dependências essenciais
        apt-get install -y software-properties-common curl wget git unzip >> "$LOG_FILE" 2>&1
        apt-get install -y build-essential libssl-dev libffi-dev >> "$LOG_FILE" 2>&1
        apt-get install -y python3.10 python3.10-venv python3.10-dev python3-pip >> "$LOG_FILE" 2>&1
        apt-get install -y php8.1 php8.1-fpm php8.1-mysql php8.1-curl >> "$LOG_FILE" 2>&1
        apt-get install -y php8.1-mbstring php8.1-xml php8.1-zip php8.1-gd >> "$LOG_FILE" 2>&1
        apt-get install -y nginx mariadb-server redis-server >> "$LOG_FILE" 2>&1
        apt-get install -y supervisor certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
        apt-get install -y fail2ban ufw >> "$LOG_FILE" 2>&1
        
        # Atualizar alternativas do Python
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
        update-alternatives --set python3 /usr/bin/python3.10
        
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Rocky"* ]] || [[ "$OS" == *"AlmaLinux"* ]]; then
        dnf update -y >> "$LOG_FILE" 2>&1
        dnf install -y epel-release >> "$LOG_FILE" 2>&1
        dnf install -y curl wget git unzip >> "$LOG_FILE" 2>&1
        dnf install -y gcc make openssl-devel libffi-devel >> "$LOG_FILE" 2>&1
        dnf install -y python3.10 python3.10-devel python3-pip >> "$LOG_FILE" 2>&1
        dnf install -y php81 php81-php-fpm php81-php-mysqlnd php81-php-curl >> "$LOG_FILE" 2>&1
        dnf install -y php81-php-mbstring php81-php-xml php81-php-zip php81-php-gd >> "$LOG_FILE" 2>&1
        dnf install -y nginx mariadb-server mariadb-client redis >> "$LOG_FILE" 2>&1
        dnf install -y supervisor certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
        dnf install -y fail2ban firewalld >> "$LOG_FILE" 2>&1
        
    else
        log_message "ERROR" "Sistema operacional não suportado: $OS"
        exit 1
    fi
    
    log_message "INFO" "Dependências instaladas com sucesso"
}

configure_mysql() {
    log_message "INFO" "Configurando MySQL/MariaDB..."
    
    # Iniciar serviço
    systemctl start mariadb >> "$LOG_FILE" 2>&1
    systemctl enable mariadb >> "$LOG_FILE" 2>&1
    
    # Configurar segurança
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';" >> "$LOG_FILE" 2>&1
    
    cat > /tmp/mysql_secure.sql << EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    mysql -u root -p"$MYSQL_ROOT_PASS" < /tmp/mysql_secure.sql >> "$LOG_FILE" 2>&1
    rm -f /tmp/mysql_secure.sql
    
    # Criar banco e usuário do sistema
    mysql -u root -p"$MYSQL_ROOT_PASS" << EOF
CREATE DATABASE IF NOT EXISTS vod_sync_system 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'vodsync_user'@'localhost' 
IDENTIFIED BY '$MYSQL_VOD_PASS';

GRANT ALL PRIVILEGES ON vod_sync_system.* 
TO 'vodsync_user'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE ON vod_sync_system.* 
TO 'vodsync_user'@'localhost';

FLUSH PRIVILEGES;
EOF
    
    log_message "INFO" "MySQL configurado com sucesso"
}

configure_redis() {
    log_message "INFO" "Configurando Redis..."
    
    # Configurar senha do Redis
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASS/" /etc/redis/redis.conf
    sed -i "s/bind 127.0.0.1 ::1/bind 127.0.0.1/" /etc/redis/redis.conf
    sed -i "s/protected-mode yes/protected-mode no/" /etc/redis/redis.conf
    
    # Habilitar persistência
    echo "appendonly yes" >> /etc/redis/redis.conf
    echo "appendfsync everysec" >> /etc/redis/redis.conf
    
    systemctl restart redis >> "$LOG_FILE" 2>&1
    systemctl enable redis >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "Redis configurado com sucesso"
}

configure_php() {
    log_message "INFO" "Configurando PHP-FPM..."
    
    PHP_CONF="/etc/php/8.1/fpm/php.ini"
    if [ ! -f "$PHP_CONF" ]; then
        PHP_CONF="/etc/opt/remi/php81/php.ini"
    fi
    
    if [ -f "$PHP_CONF" ]; then
        # Otimizar configurações PHP
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' "$PHP_CONF"
        sed -i 's/post_max_size = 8M/post_max_size = 100M/' "$PHP_CONF"
        sed -i 's/max_execution_time = 30/max_execution_time = 300/' "$PHP_CONF"
        sed -i 's/memory_limit = 128M/memory_limit = 256M/' "$PHP_CONF"
        
        # Habilitar extensões necessárias
        sed -i 's/;extension=curl/extension=curl/' "$PHP_CONF"
        sed -i 's/;extension=gd/extension=gd/' "$PHP_CONF"
        sed -i 's/;extension=mysqli/extension=mysqli/' "$PHP_CONF"
        sed -i 's/;extension=openssl/extension=openssl/' "$PHP_CONF"
        
        # Configurar timezone
        sed -i 's/;date.timezone =/date.timezone = America\/Sao_Paulo/' "$PHP_CONF"
    fi
    
    # Configurar pool PHP-FPM
    cat > /etc/php/8.1/fpm/pool.d/vodsync.conf << EOF
[vodsync]
user = www-data
group = www-data
listen = /run/php/php8.1-fpm-vodsync.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500
slowlog = /var/log/php8.1-fpm-slow.log
request_slowlog_timeout = 5s
php_admin_value[error_log] = /var/log/php8.1-fpm-vodsync-error.log
php_admin_flag[log_errors] = on
php_value[session.save_handler] = redis
php_value[session.save_path] = "tcp://127.0.0.1:6379?auth=$REDIS_PASS"
EOF
    
    systemctl restart php8.1-fpm >> "$LOG_FILE" 2>&1
    systemctl enable php8.1-fpm >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "PHP-FPM configurado com sucesso"
}

download_system() {
    log_message "INFO" "Baixando sistema VOD Sync..."
    
    # Criar diretório de instalação
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Clonar repositório
    if [ -d "$INSTALL_DIR/.git" ]; then
        log_message "INFO" "Atualizando repositório existente..."
        git pull origin "$REPO_BRANCH" >> "$LOG_FILE" 2>&1
    else
        log_message "INFO" "Clonando repositório..."
        git clone -b "$REPO_BRANCH" "$REPO_URL" . >> "$LOG_FILE" 2>&1
    fi
    
    # Definir permissões
    chown -R www-data:www-data "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod -R 777 "$INSTALL_DIR/backend/app/logs" 2>/dev/null || true
    chmod -R 777 "$INSTALL_DIR/frontend/app/cache" 2>/dev/null || true
    
    log_message "INFO" "Sistema baixado com sucesso"
}

setup_backend() {
    log_message "INFO" "Configurando backend Python..."
    
    cd "$INSTALL_DIR/backend"
    
    # Criar ambiente virtual
    python3.10 -m venv venv
    
    # Ativar ambiente e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    
    # Criar arquivo .env
    cat > .env << EOF
# ============================================
# CONFIGURAÇÃO DO SISTEMA VOD SYNC
# ============================================

# Banco de dados
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync_system
DB_USER=vodsync_user
DB_PASS=$MYSQL_VOD_PASS

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASS=$REDIS_PASS
REDIS_DB=0

# API Keys
TMDB_API_KEY=SUA_CHAVE_TMDB_AQUI
TMDB_LANGUAGE=pt-BR

# Segurança
JWT_SECRET=$JWT_SECRET
JWT_ALGORITHM=HS256
JWT_EXPIRE_HOURS=24

# Servidor
API_HOST=127.0.0.1
API_PORT=8000
DEBUG=false
LOG_LEVEL=INFO

# XUI One
XUI_DEFAULT_HOST=localhost
XUI_DEFAULT_PORT=3306
XUI_DEFAULT_USER=root
XUI_DEFAULT_PASS=

# Sincronização
SYNC_MAX_WORKERS=4
SYNC_BATCH_SIZE=50
SYNC_RETRY_ATTEMPTS=3
SYNC_TIMEOUT=30

# Cache
CACHE_TTL_MOVIES=86400
CACHE_TTL_SERIES=86400
CACHE_TTL_TMDB=604800

# Limites
MAX_M3U_SIZE=10485760
MAX_SYNC_ITEMS=10000
MAX_LOG_DAYS=30

# Email (opcional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=noreply@vodsync.com
EOF
    
    # Executar migrações do banco
    python -c "
from app.database.mysql import engine, Base
from app.models import *
Base.metadata.create_all(bind=engine)
print('Banco de dados inicializado')
" >> "$LOG_FILE" 2>&1
    
    # Criar usuário admin inicial
    python -c "
from app.database.mysql import SessionLocal
from app.models.user import User
from app.utils.security import get_password_hash

db = SessionLocal()
try:
    admin = User(
        username='admin',
        email='admin@vodsync.com',
        password_hash=get_password_hash('$ADMIN_PASS'),
        user_type='admin',
        is_active=True
    )
    db.add(admin)
    db.commit()
    print('Usuário admin criado')
except Exception as e:
    print(f'Erro: {e}')
finally:
    db.close()
" >> "$LOG_FILE" 2>&1
    
    deactivate
    
    log_message "INFO" "Backend configurado com sucesso"
}

setup_frontend() {
    log_message "INFO" "Configurando frontend PHP..."
    
    cd "$INSTALL_DIR/frontend"
    
    # Criar arquivo de configuração
    cat > config/database.php << EOF
<?php
// Configuração automática gerada pelo instalador
\$db_config = [
    'host' => 'localhost',
    'port' => '3306',
    'database' => 'vod_sync_system',
    'username' => 'vodsync_user',
    'password' => '$MYSQL_VOD_PASS',
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => '',
    'options' => [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci"
    ]
];

// Configuração da API
define('API_BASE_URL', 'http://localhost:8000');
define('API_TIMEOUT', 30);
define('API_DEBUG', false);

// Configuração do sistema
define('APP_NAME', 'VOD Sync System');
define('APP_VERSION', '$VERSION');
define('APP_ENV', 'production');
define('APP_DEBUG', false);
define('APP_URL', 'https://\$domain');

// Configuração de sessão
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', 'tcp://127.0.0.1:6379?auth=$REDIS_PASS');
ini_set('session.gc_maxlifetime', 86400);
session_cache_limiter('nocache');

// Timezone
date_default_timezone_set('America/Sao_Paulo');

// Configurações de upload
ini_set('upload_max_filesize', '100M');
ini_set('post_max_size', '100M');
ini_set('max_execution_time', '300');
ini_set('memory_limit', '256M');
EOF
    
    # Criar arquivo .htaccess se necessário
    cat > public/.htaccess << EOF
RewriteEngine On
RewriteBase /

# Proteger arquivos sensíveis
<FilesMatch "^\.">
    Order allow,deny
    Deny from all
</FilesMatch>

<FilesMatch "(\.(log|ini|env|sql|yml)|composer\.json|composer\.lock)$">
    Order allow,deny
    Deny from all
</FilesMatch>

# Redirecionar para index.php
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php?/$1 [L,QSA]

# Proteção contra ataques
<IfModule mod_headers.c>
    Header set X-Content-Type-Options "nosniff"
    Header set X-Frame-Options "SAMEORIGIN"
    Header set X-XSS-Protection "1; mode=block"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>

# Cache de arquivos estáticos
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpg "access plus 1 year"
    ExpiresByType image/jpeg "access plus 1 year"
    ExpiresByType image/gif "access plus 1 year"
    ExpiresByType image/png "access plus 1 year"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType font/woff2 "access plus 1 year"
</IfModule>

# Gzip compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
</IfModule>
EOF
    
    # Configurar permissões
    chown -R www-data:www-data "$INSTALL_DIR/frontend"
    chmod -R 755 "$INSTALL_DIR/frontend"
    chmod 777 "$INSTALL_DIR/frontend/app/cache" 2>/dev/null || true
    chmod 777 "$INSTALL_DIR/frontend/app/logs" 2>/dev/null || true
    
    log_message "INFO" "Frontend configurado com sucesso"
}

configure_nginx() {
    log_message "INFO" "Configurando Nginx..."
    
    # Remover configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Criar configuração do sistema
    cat > /etc/nginx/sites-available/vodsync << EOF
# Configuração do Sistema VOD Sync
# Gerado automaticamente pelo instalador

# Configurações globais
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

# Servidor principal
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    # Redirecionar para HTTPS
    return 301 https://\$server_name\$request_uri;
}

# Servidor HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    
    # SSL
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Root directory
    root $INSTALL_DIR/frontend/public;
    index index.php index.html;
    
    # Logs
    access_log /var/log/nginx/vodsync-access.log;
    error_log /var/log/nginx/vodsync-error.log;
    
    # Frontend PHP
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.1-fpm-vodsync.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        proxy_buffering off;
        proxy_cache off;
        proxy_redirect off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # WebSocket para logs em tempo real
    location /ws {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    
    # Proteger arquivos sensíveis
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /(config|app|logs|vendor)/ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~* \.(log|ini|env|sql|yml|json|lock)\$ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Cache de arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
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
}
EOF
    
    # Habilitar site
    ln -sf /etc/nginx/sites-available/vodsync /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        systemctl restart nginx >> "$LOG_FILE" 2>&1
        systemctl enable nginx >> "$LOG_FILE" 2>&1
        log_message "INFO" "Nginx configurado com sucesso"
    else
        log_message "ERROR" "Erro na configuração do Nginx"
        exit 1
    fi
}

configure_supervisor() {
    log_message "INFO" "Configurando Supervisor..."
    
    # Configuração do backend
    cat > /etc/supervisor/conf.d/vodsync-backend.conf << EOF
[program:vodsync-backend]
command=$INSTALL_DIR/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 4
directory=$INSTALL_DIR/backend
user=www-data
autostart=true
autorestart=true
startsecs=10
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/vodsync-backend.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/var/log/supervisor/vodsync-backend-error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=PYTHONPATH="$INSTALL_DIR/backend",PATH="$INSTALL_DIR/backend/venv/bin:%(ENV_PATH)s"
EOF
    
    # Configuração do scheduler
    cat > /etc/supervisor/conf.d/vodsync-scheduler.conf << EOF
[program:vodsync-scheduler]
command=$INSTALL_DIR/backend/venv/bin/python -m app.services.scheduler
directory=$INSTALL_DIR/backend
user=www-data
autostart=true
autorestart=true
startsecs=10
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/vodsync-scheduler.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/var/log/supervisor/vodsync-scheduler-error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=PYTHONPATH="$INSTALL_DIR/backend",PATH="$INSTALL_DIR/backend/venv/bin:%(ENV_PATH)s"
EOF
    
    # Configuração do worker
    cat > /etc/supervisor/conf.d/vodsync-worker.conf << EOF
[program:vodsync-worker]
command=$INSTALL_DIR/backend/venv/bin/celery -A app.tasks.celery_app worker --loglevel=info --concurrency=4
directory=$INSTALL_DIR/backend
user=www-data
autostart=true
autorestart=true
startsecs=10
startretries=3
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/supervisor/vodsync-worker.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/var/log/supervisor/vodsync-worker-error.log
stderr_logfile_maxbytes=50MB
stderr_logfiles_backups=10
environment=C_FORCE_ROOT="true",PYTHONPATH="$INSTALL_DIR/backend",PATH="$INSTALL_DIR/backend/venv/bin:%(ENV_PATH)s"
EOF
    
    # Recarregar supervisor
    systemctl restart supervisor >> "$LOG_FILE" 2>&1
    systemctl enable supervisor >> "$LOG_FILE" 2>&1
    
    # Iniciar serviços
    supervisorctl update >> "$LOG_FILE" 2>&1
    supervisorctl start all >> "$LOG_FILE" 2>&1
    
    log_message "INFO" "Supervisor configurado com sucesso"
}

configure_firewall() {
    log_message "INFO" "Configurando firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw --force reset >> "$LOG_FILE" 2>&1
        ufw default deny incoming >> "$LOG_FILE" 2>&1
        ufw default allow outgoing >> "$LOG_FILE" 2>&1
        ufw allow ssh >> "$LOG_FILE" 2>&1
        ufw allow 80/tcp >> "$LOG_FILE" 2>&1
        ufw allow 443/tcp >> "$LOG_FILE" 2>&1
        ufw --force enable >> "$LOG_FILE" 2>&1
    elif command -v firewall-cmd &> /dev/null; then
        systemctl start firewalld >> "$LOG_FILE" 2>&1
        systemctl enable firewalld >> "$LOG_FILE" 2>&1
        firewall-cmd --permanent --add-service=ssh >> "$LOG_FILE" 2>&1
        firewall-cmd --permanent --add-service=http >> "$LOG_FILE" 2>&1
        firewall-cmd --permanent --add-service=https >> "$LOG_FILE" 2>&1
        firewall-cmd --reload >> "$LOG_FILE" 2>&1
    fi
    
    log_message "INFO" "Firewall configurado com sucesso"
}

configure_ssl() {
    if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
        log_message "INFO" "Configurando SSL com Let's Encrypt..."
        
        # Instalar certificado SSL
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1
        
        # Configurar renovação automática
        echo "0 0,12 * * * root /usr/bin/certbot renew --quiet" > /etc/cron.d/certbot
        
        log_message "INFO" "SSL configurado com sucesso"
    else
        log_message "WARN" "SSL não configurado (domínio ou email não fornecido)"
    fi
}

configure_backup() {
    log_message "INFO" "Configurando sistema de backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Script de backup
    cat > /usr/local/bin/vodsync-backup << EOF
#!/bin/bash
# Script de backup do Sistema VOD Sync

BACKUP_DIR="$BACKUP_DIR"
INSTALL_DIR="$INSTALL_DIR"
MYSQL_USER="vodsync_user"
MYSQL_PASS="$MYSQL_VOD_PASS"
MYSQL_DB="vod_sync_system"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vodsync_backup_\$DATE"

echo "[Backup] Iniciando backup: \$DATE"

# Criar diretório temporário
TEMP_DIR="/tmp/\$BACKUP_NAME"
mkdir -p "\$TEMP_DIR"

# Backup do banco de dados
echo "[Backup] Exportando banco de dados..."
mysqldump -u\$MYSQL_USER -p\$MYSQL_PASS \$MYSQL_DB > "\$TEMP_DIR/database.sql"

# Backup dos arquivos
echo "[Backup] Copiando arquivos do sistema..."
cp -r "\$INSTALL_DIR/backend" "\$TEMP_DIR/"
cp -r "\$INSTALL_DIR/frontend" "\$TEMP_DIR/"
cp -r "\$INSTALL_DIR/database" "\$TEMP_DIR/"

# Remover arquivos desnecessários
find "\$TEMP_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find "\$TEMP_DIR" -name "*.pyc" -delete
find "\$TEMP_DIR" -name ".git" -type d -exec rm -rf {} + 2>/dev/null

# Compactar backup
echo "[Backup] Compactando arquivos..."
cd /tmp
tar -czf "\$BACKUP_DIR/\$BACKUP_NAME.tar.gz" "\$BACKUP_NAME"

# Limpar arquivos temporários
rm -rf "\$TEMP_DIR"

# Manter apenas últimos 7 backups
echo "[Backup] Limpando backups antigos..."
ls -t "\$BACKUP_DIR/"*.tar.gz | tail -n +8 | xargs -r rm

echo "[Backup] Backup concluído: \$BACKUP_DIR/\$BACKUP_NAME.tar.gz"

# Log
echo "\$(date) - Backup realizado com sucesso" >> /var/log/vodsync-backup.log
EOF
    
    chmod +x /usr/local/bin/vodsync-backup
    
    # Agendar backup diário
    echo "0 2 * * * root /usr/local/bin/vodsync-backup >> /var/log/vodsync-cron.log 2>&1" > /etc/cron.d/vodsync-backup
    
    # Script de restore
    cat > /usr/local/bin/vodsync-restore << EOF
#!/bin/bash
# Script de restore do Sistema VOD Sync

if [ -z "\$1" ]; then
    echo "Uso: vodsync-restore <arquivo_backup.tar.gz>"
    exit 1
fi

BACKUP_FILE="\$1"
INSTALL_DIR="$INSTALL_DIR"
MYSQL_USER="vodsync_user"
MYSQL_PASS="$MYSQL_VOD_PASS"
MYSQL_DB="vod_sync_system"

if [ ! -f "\$BACKUP_FILE" ]; then
    echo "Erro: Arquivo não encontrado: \$BACKUP_FILE"
    exit 1
fi

echo "[Restore] Iniciando restore a partir de: \$BACKUP_FILE"

# Criar diretório temporário
TEMP_DIR="/tmp/restore_\$(date +%s)"
mkdir -p "\$TEMP_DIR"

# Extrair backup
echo "[Restore] Extraindo arquivos..."
tar -xzf "\$BACKUP_FILE" -C "\$TEMP_DIR" --strip-components=1

# Restaurar banco de dados
echo "[Restore] Restaurando banco de dados..."
mysql -u\$MYSQL_USER -p\$MYSQL_PASS \$MYSQL_DB < "\$TEMP_DIR/database.sql"

# Restaurar arquivos
echo "[Restore] Restaurando arquivos do sistema..."
cp -r "\$TEMP_DIR/backend/"* "\$INSTALL_DIR/backend/"
cp -r "\$TEMP_DIR/frontend/"* "\$INSTALL_DIR/frontend/"
cp -r "\$TEMP_DIR/database/"* "\$INSTALL_DIR/database/"

# Ajustar permissões
chown -R www-data:www-data "\$INSTALL_DIR"
chmod -R 755 "\$INSTALL_DIR"

# Limpar
rm -rf "\$TEMP_DIR"

# Reiniciar serviços
echo "[Restore] Reiniciando serviços..."
supervisorctl restart all
systemctl restart nginx

echo "[Restore] Restore concluído com sucesso!"

# Log
echo "\$(date) - Restore realizado a partir de: \$BACKUP_FILE" >> /var/log/vodsync-restore.log
EOF
    
    chmod +x /usr/local/bin/vodsync-restore
    
    log_message "INFO" "Sistema de backup configurado com sucesso"
}

configure_monitoring() {
    log_message "INFO" "Configurando monitoramento..."
    
    # Script de monitoramento
    cat > /usr/local/bin/vodsync-monitor << EOF
#!/bin/bash
# Script de monitoramento do Sistema VOD Sync

LOG_FILE="/var/log/vodsync-monitor.log"
API_URL="http://localhost:8000"
ALERT_EMAIL="$EMAIL"

# Função para log
log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

# Função para enviar alerta
send_alert() {
    local subject="[VOD Sync Alert] \$1"
    local message="\$2"
    
    if [ -n "\$ALERT_EMAIL" ]; then
        echo "\$message" | mail -s "\$subject" "\$ALERT_EMAIL"
    fi
}

# Verificar serviços
check_service() {
    local service=\$1
    if ! systemctl is-active --quiet "\$service"; then
        log "Serviço \$service está inativo"
        send_alert "Serviço \$service inativo" "O serviço \$service está inativo. Reiniciando..."
        systemctl restart "\$service"
    fi
}

# Verificar processos Supervisor
check_supervisor() {
    if ! supervisorctl status | grep -q "RUNNING"; then
        log "Processos Supervisor não estão rodando"
        send_alert "Supervisor com problemas" "Alguns processos não estão rodando. Verificando..."
        supervisorctl restart all
    fi
}

# Verificar API
check_api() {
    if ! curl -s -f "\$API_URL/" > /dev/null; then
        log "API não está respondendo"
        send_alert "API offline" "A API do sistema não está respondendo"
        supervisorctl restart vodsync-backend
    fi
}

# Verificar recursos do sistema
check_resources() {
    local cpu=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1)
    local memory=\$(free | grep Mem | awk '{print \$3/\$2 * 100.0}')
    local disk=\$(df / | awk 'END{print \$5}' | sed 's/%//')
    
    if (( \$(echo "\$cpu > 80" | bc -l) )); then
        log "Uso de CPU alto: \$cpu%"
    fi
    
    if (( \$(echo "\$memory > 85" | bc -l) )); then
        log "Uso de memória alto: \$memory%"
    fi
    
    if [ "\$disk" -gt 90 ]; then
        log "Uso de disco alto: \$disk%"
        send_alert "Disco quase cheio" "Uso de disco em \$disk%. Limpe necessária."
    fi
}

# Executar verificações
log "Iniciando monitoramento"
check_service nginx
check_service mariadb
check_service redis
check_service php8.1-fpm
check_service supervisor
check_supervisor
check_api
check_resources
log "Monitoramento concluído"
EOF
    
    chmod +x /usr/local/bin/vodsync-monitor
    
    # Agendar monitoramento a cada 5 minutos
    echo "*/5 * * * * root /usr/local/bin/vodsync-monitor >> /var/log/vodsync-monitor-cron.log 2>&1" > /etc/cron.d/vodsync-monitor
    
    # Configurar logrotate
    cat > /etc/logrotate.d/vodsync << EOF
/var/log/vodsync-*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        systemctl reload supervisor > /dev/null 2>&1 || true
    endscript
}

$INSTALL_DIR/backend/app/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
}

$INSTALL_DIR/frontend/app/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
}
EOF
    
    log_message "INFO" "Monitoramento configurado com sucesso"
}

create_admin_tools() {
    log_message "INFO" "Criando ferramentas administrativas..."
    
    # Script de administração
    cat > /usr/local/bin/vodsync-admin << EOF
#!/bin/bash
# Ferramenta administrativa do Sistema VOD Sync

INSTALL_DIR="$INSTALL_DIR"
BACKEND_DIR="\$INSTALL_DIR/backend"
FRONTEND_DIR="\$INSTALL_DIR/frontend"

case "\$1" in
    start)
        echo "Iniciando todos os serviços..."
        supervisorctl start all
        systemctl start nginx mariadb redis php8.1-fpm
        ;;
    stop)
        echo "Parando todos os serviços..."
        supervisorctl stop all
        systemctl stop nginx php8.1-fpm
        ;;
    restart)
        echo "Reiniciando todos os serviços..."
        supervisorctl restart all
        systemctl restart nginx mariadb redis php8.1-fpm
        ;;
    status)
        echo "=== Status dos Serviços ==="
        systemctl status nginx mariadb redis php8.1-fpm supervisor | grep -E "(Active|Loaded)"
        echo ""
        echo "=== Status dos Processos ==="
        supervisorctl status
        ;;
    logs)
        case "\$2" in
            backend)
                tail -f /var/log/supervisor/vodsync-backend*.log
                ;;
            scheduler)
                tail -f /var/log/supervisor/vodsync-scheduler*.log
                ;;
            worker)
                tail -f /var/log/supervisor/vodsync-worker*.log
                ;;
            nginx)
                tail -f /var/log/nginx/vodsync-*.log
                ;;
            all)
                tail -f /var/log/supervisor/vodsync-*.log /var/log/nginx/vodsync-*.log
                ;;
            *)
                echo "Uso: vodsync-admin logs <backend|scheduler|worker|nginx|all>"
                ;;
        esac
        ;;
    update)
        echo "Atualizando sistema..."
        cd "\$INSTALL_DIR"
        git pull origin main
        
        cd "\$BACKEND_DIR"
        source venv/bin/activate
        pip install -r requirements.txt
        deactivate
        
        supervisorctl restart all
        echo "Sistema atualizado com sucesso!"
        ;;
    backup)
        /usr/local/bin/vodsync-backup
        ;;
    restore)
        if [ -z "\$2" ]; then
            echo "Uso: vodsync-admin restore <arquivo_backup>"
            exit 1
        fi
        /usr/local/bin/vodsync-restore "\$2"
        ;;
    shell)
        cd "\$BACKEND_DIR"
        source venv/bin/activate
        python
        ;;
    user-add)
        if [ -z "\$2" ] || [ -z "\$3" ]; then
            echo "Uso: vodsync-admin user-add <username> <user_type>"
            echo "Tipos: admin, reseller, user"
            exit 1
        fi
        cd "\$BACKEND_DIR"
        source venv/bin/activate
        python -c "
from app.database.mysql import SessionLocal
from app.models.user import User
from app.utils.security import get_password_hash
import sys

db = SessionLocal()
try:
    password = 'Vodsync@123'
    user = User(
        username='\$2',
        email='\$2@vodsync.com',
        password_hash=get_password_hash(password),
        user_type='\$3',
        is_active=True
    )
    db.add(user)
    db.commit()
    print(f'Usuário \$2 criado com senha: {password}')
except Exception as e:
    print(f'Erro: {e}')
    db.rollback()
finally:
    db.close()
"
        deactivate
        ;;
    *)
        echo "Uso: vodsync-admin <comando>"
        echo ""
        echo "Comandos disponíveis:"
        echo "  start       - Iniciar todos os serviços"
        echo "  stop        - Parar todos os serviços"
        echo "  restart     - Reiniciar todos os serviços"
        echo "  status      - Verificar status dos serviços"
        echo "  logs <type> - Ver logs (backend, scheduler, worker, nginx, all)"
        echo "  update      - Atualizar sistema"
        echo "  backup      - Criar backup"
        echo "  restore     - Restaurar backup"
        echo "  shell       - Abrir shell Python"
        echo "  user-add    - Adicionar usuário"
        echo ""
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/vodsync-admin
    
    # Criar alias útil
    cat > /etc/profile.d/vodsync.sh << EOF
alias vodsync='vodsync-admin'
alias vodsync-logs='vodsync-admin logs all'
alias vodsync-status='vodsync-admin status'
EOF
    
    log_message "INFO" "Ferramentas administrativas criadas com sucesso"
}

show_summary() {
    print_header
    
    echo -e "${GREEN}"
    echo -e "╔══════════════════════════════════════════════════════════════╗"
    echo -e "║                     INSTALAÇÃO CONCLUÍDA!                    ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    echo -e "${CYAN}📋 RESUMO DA INSTALAÇÃO${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}📍 Diretório de Instalação:${NC}"
    echo -e "  $INSTALL_DIR"
    echo ""
    
    echo -e "${YELLOW}🌐 URLs de Acesso:${NC}"
    if [ -n "$DOMAIN" ]; then
        echo -e "  Painel:     ${GREEN}https://$DOMAIN${NC}"
        echo -e "  API:        ${GREEN}https://$DOMAIN/api${NC}"
    else
        echo -e "  Painel:     ${GREEN}http://$(hostname -I | awk '{print $1}')${NC}"
        echo -e "  API:        ${GREEN}http://$(hostname -I | awk '{print $1}'):8000${NC}"
    fi
    echo ""
    
    echo -e "${YELLOW}🔑 Credenciais de Acesso:${NC}"
    echo -e "  Usuário:    ${GREEN}admin${NC}"
    echo -e "  Senha:      ${GREEN}$ADMIN_PASS${NC}"
    echo ""
    
    echo -e "${YELLOW}🗄️  Banco de Dados:${NC}"
    echo -e "  Host:       localhost"
    echo -e "  Banco:      vod_sync_system"
    echo -e "  Usuário:    vodsync_user"
    echo -e "  Senha:      ${RED}(armazenada no arquivo .env)${NC}"
    echo ""
    
    echo -e "${YELLOW}⚙️  Serviços Instalados:${NC}"
    echo -e "  ✅ Nginx (Web Server)"
    echo -e "  ✅ PHP 8.1 (Frontend)"
    echo -e "  ✅ Python 3.10 (Backend)"
    echo -e "  ✅ MariaDB (Database)"
    echo -e "  ✅ Redis (Cache/Queue)"
    echo -e "  ✅ Supervisor (Process Manager)"
    echo ""
    
    echo -e "${YELLOW}🔧 Ferramentas Administrativas:${NC}"
    echo -e "  Comando:    ${GREEN}vodsync-admin${NC}"
    echo -e "  Exemplo:    vodsync-admin status"
    echo -e "              vodsync-admin logs backend"
    echo -e "              vodsync-admin update"
    echo ""
    
    echo -e "${YELLOW}💾 Sistema de Backup:${NC}"
    echo -e "  Diretório:  $BACKUP_DIR"
    echo -e "  Backup:     ${GREEN}vodsync-backup${NC}"
    echo -e "  Restore:    ${GREEN}vodsync-restore <arquivo>${NC}"
    echo ""
    
    echo -e "${YELLOW}📊 Monitoramento:${NC}"
    echo -e "  Logs:       /var/log/vodsync-*.log"
    echo -e "  Monitor:    ${GREEN}vodsync-monitor${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  PRÓXIMOS PASSOS:${NC}"
    echo -e "  1. Acesse o painel com as credenciais acima"
    echo -e "  2. Configure sua chave do TMDb no arquivo .env"
    echo -e "  3. Configure a conexão com o XUI One"
    echo -e "  4. Adicione sua lista M3U"
    echo -e "  5. Configure a sincronização automática"
    echo ""
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Salvar credenciais em arquivo
    cat > "$INSTALL_DIR/INSTALLATION_SUMMARY.txt" << EOF
==================================================
      RESUMO DA INSTALAÇÃO - VOD SYNC SYSTEM
==================================================

DATA DA INSTALAÇÃO: $(date)
VERSÃO DO SISTEMA: $VERSION

🔧 CONFIGURAÇÃO DO SISTEMA
Diretório: $INSTALL_DIR
Logs: /var/log/vodsync-*.log

🌐 ACESSO
Painel: https://$DOMAIN
API: https://$DOMAIN/api

🔑 CREDENCIAIS INICIAIS
Usuário: admin
Senha: $ADMIN_PASS

⚠️ IMPORTANTE: Altere esta senha no primeiro acesso!

🗄️ BANCO DE DADOS
Host: localhost
Banco: vod_sync_system
Usuário: vodsync_user
Senha: $MYSQL_VOD_PASS

🔐 SENHAS DE SISTEMA
MySQL Root: $MYSQL_ROOT_PASS
Redis: $REDIS_PASS
JWT Secret: $JWT_SECRET

⚙️ COMANDOS ADMINISTRATIVOS
Status: vodsync-admin status
Logs: vodsync-admin logs <tipo>
Backup: vodsync-backup
Restore: vodsync-restore
Monitor: vodsync-monitor

📁 ESTRUTURA DE DIRETÓRIOS
$INSTALL_DIR/
├── backend/      # API Python
├── frontend/     # Painel PHP
├── database/     # Scripts SQL
└── scripts/      # Utilitários

⚠️ RECOMENDAÇÕES DE SEGURANÇA
1. Altere todas as senhas após instalação
2. Configure firewall adequadamente
3. Mantenha o sistema atualizado
4. Configure backups regulares
5. Monitore os logs periodicamente

📞 SUPORTE
Documentação: https://docs.vodsync.com
Suporte: support@vodsync.com

==================================================
        INSTALAÇÃO CONCLUÍDA COM SUCESSO!
==================================================
EOF
    
    echo -e "${GREEN}📄 Um arquivo com este resumo foi salvo em:${NC}"
    echo -e "${YELLOW}  $INSTALL_DIR/INSTALLATION_SUMMARY.txt${NC}"
    echo ""
    
    echo -e "${RED}⚠️  ATENÇÃO:${NC}"
    echo -e "  Salve este arquivo em local seguro!"
    echo -e "  Ele contém todas as senhas de acesso ao sistema."
    echo ""
}

# Função principal
main() {
    print_header
    
    # Solicitar informações do usuário
    echo -e "${CYAN}📝 CONFIGURAÇÃO INICIAL${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "📧 Email do administrador (para SSL): " EMAIL
    read -p "🌐 Domínio (deixe em branco para IP): " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        DOMAIN=$(hostname -I | awk '{print $1}')
    fi
    
    echo ""
    echo -e "${YELLOW}📋 RESUMO DA CONFIGURAÇÃO:${NC}"
    echo -e "  Email: $EMAIL"
    echo -e "  Domínio: $DOMAIN"
    echo -e "  Diretório: $INSTALL_DIR"
    echo ""
    
    read -p "✅ Confirmar instalação? (s/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${RED}Instalação cancelada.${NC}"
        exit 0
    fi
    
    # Iniciar log
    echo "========================================" > "$LOG_FILE"
    echo "INSTALAÇÃO VOD SYNC - $(date)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    # Executar etapas de instalação
    log_message "INFO" "Iniciando instalação do VOD Sync System..."
    
    check_root
    check_requirements
    
    # Progress bar simulation
    echo -e "${CYAN}🔄 INSTALANDO SISTEMA...${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    
    steps=(
        "Instalando dependências do sistema"
        "Configurando MySQL/MariaDB"
        "Configurando Redis"
        "Configurando PHP-FPM"
        "Baixando sistema VOD Sync"
        "Configurando backend Python"
        "Configurando frontend PHP"
        "Configurando Nginx"
        "Configurando Supervisor"
        "Configurando firewall"
        "Configurando SSL"
        "Configurando sistema de backup"
        "Configurando monitoramento"
        "Criando ferramentas administrativas"
    )
    
    for i in "${!steps[@]}"; do
        step=$((i + 1))
        total_steps=${#steps[@]}
        percentage=$((step * 100 / total_steps))
        
        # Atualizar barra de progresso
        echo -ne "\r["
        for ((j=0; j<50; j++)); do
            if [ $j -lt $((percentage / 2)) ]; then
                echo -ne "▓"
            else
                echo -ne "░"
            fi
        done
        echo -ne "] $percentage% - ${steps[$i]}"
        
        case $step in
            1) install_dependencies ;;
            2) configure_mysql ;;
            3) configure_redis ;;
            4) configure_php ;;
            5) download_system ;;
            6) setup_backend ;;
            7) setup_frontend ;;
            8) configure_nginx ;;
            9) configure_supervisor ;;
            10) configure_firewall ;;
            11) configure_ssl ;;
            12) configure_backup ;;
            13) configure_monitoring ;;
            14) create_admin_tools ;;
        esac
        
        sleep 1
    done
    
    echo -e "\n\n${GREEN}✅ Instalação concluída!${NC}"
    
    # Mostrar resumo
    show_summary
    
    # Iniciar serviços
    systemctl restart supervisor nginx mariadb redis php8.1-fpm
    
    log_message "INFO" "Instalação concluída com sucesso!"
}

# Executar instalação
main "$@"
