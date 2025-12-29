#!/bin/bash
# install_vod_sync.sh - Instalador completo do Sistema VOD Sync XUI One

# ============================================
# CONFIGURAÇÕES
# ============================================
APP_NAME="vod-sync-xui"
INSTALL_DIR="/opt/$APP_NAME"
BACKEND_DIR="$INSTALL_DIR/backend"
FRONTEND_DIR="$INSTALL_DIR/frontend"
DB_NAME="vod_sync_system"
DB_USER="vod_sync_user"
DB_PASS=$(openssl rand -base64 32)
PYTHON_VENV="$INSTALL_DIR/venv"
LOG_FILE="/var/log/$APP_NAME-install.log"
DOMAIN="" # Definir via parâmetro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# FUNÇÕES UTILITÁRIAS
# ============================================

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}!${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Não foi possível detectar o sistema operacional"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            success "Sistema operacional detectado: $OS $VERSION"
            ;;
        *)
            error "Sistema operacional não suportado: $OS"
            exit 1
            ;;
    esac
}

# ============================================
# FUNÇÕES DE INSTALAÇÃO
# ============================================

install_dependencies() {
    log "Instalando dependências do sistema..."
    
    apt-get update >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        error "Falha ao atualizar pacotes"
        exit 1
    fi
    
    # Dependências básicas
    DEPS="software-properties-common apt-transport-https ca-certificates curl wget gnupg lsb-release"
    
    # Dependências Python
    PYTHON_DEPS="python3.10 python3.10-venv python3.10-dev python3-pip build-essential"
    
    # Dependências MySQL
    MYSQL_DEPS="mysql-server mysql-client libmysqlclient-dev"
    
    # Dependências PHP
    PHP_DEPS="php8.1 php8.1-cli php8.1-common php8.1-mysql php8.1-zip php8.1-gd php8.1-mbstring php8.1-curl php8.1-xml php8.1-bcmath"
    
    # Dependências Web Server
    WEB_DEPS="nginx supervisor certbot python3-certbot-nginx"
    
    ALL_DEPS="$DEPS $PYTHON_DEPS $MYSQL_DEPS $PHP_DEPS $WEB_DEPS"
    
    apt-get install -y $ALL_DEPS >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        error "Falha ao instalar dependências"
        exit 1
    fi
    
    success "Dependências instaladas com sucesso"
}

setup_mysql() {
    log "Configurando MySQL/MariaDB..."
    
    # Iniciar serviço MySQL
    systemctl start mysql >> "$LOG_FILE" 2>&1
    systemctl enable mysql >> "$LOG_FILE" 2>&1
    
    # Criar banco de dados e usuário
    SQL_COMMANDS=$(cat <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mysql.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
)
    
    mysql -e "$SQL_COMMANDS" >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        error "Falha ao configurar banco de dados"
        exit 1
    fi
    
    success "Banco de dados configurado: $DB_NAME"
}

setup_directory() {
    log "Criando estrutura de diretórios..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$FRONTEND_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/ssl"
    mkdir -p "/var/log/$APP_NAME"
    
    chmod 755 "$INSTALL_DIR"
    chown -R www-data:www-data "$INSTALL_DIR"
    
    success "Estrutura de diretórios criada"
}

setup_python_backend() {
    log "Configurando backend Python..."
    
    # Criar ambiente virtual
    python3.10 -m venv "$PYTHON_VENV" >> "$LOG_FILE" 2>&1
    source "$PYTHON_VENV/bin/activate"
    
    # Criar requirements.txt
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
# Core
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6

# Database
sqlalchemy==2.0.23
alembic==1.12.1
pymysql==1.1.0
aiomysql==0.2.0

# Authentication
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0

# Scheduling
apscheduler==3.10.4
schedule==1.2.0

# HTTP Client
httpx==0.25.1
aiohttp==3.9.1
requests==2.31.0

# Data Processing
pydantic==2.5.0
pydantic-settings==2.1.0
python-dateutil==2.8.2

# Utilities
pycryptodome==3.19.0
redis==5.0.1
celery==5.3.4

# M3U Parser
m3u8==6.0.0

# Logging
loguru==0.7.2

# Email
emails==0.6
jinja2==3.1.2

# Production
gunicorn==21.2.0
EOF
    
    # Instalar dependências Python
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install -r "$BACKEND_DIR/requirements.txt" >> "$LOG_FILE" 2>&1
    
    success "Backend Python configurado"
}

setup_php_frontend() {
    log "Configurando frontend PHP..."
    
    # Instalar Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
    
    # Criar composer.json
    cat > "$FRONTEND_DIR/composer.json" << 'EOF'
{
    "name": "vod-sync-xui/frontend",
    "description": "Frontend PHP para VOD Sync XUI One",
    "type": "project",
    "require": {
        "php": ">=8.1.0",
        "ext-json": "*",
        "ext-curl": "*",
        "ext-mbstring": "*"
    },
    "autoload": {
        "psr-4": {
            "App\\": "app/"
        }
    },
    "config": {
        "platform-check": false
    }
}
EOF
    
    cd "$FRONTEND_DIR"
    composer install --no-dev --optimize-autoloader >> "$LOG_FILE" 2>&1
    
    success "Frontend PHP configurado"
}

create_backend_structure() {
    log "Criando estrutura do backend..."
    
    # Estrutura de diretórios backend
    mkdir -p "$BACKEND_DIR/app"
    mkdir -p "$BACKEND_DIR/app/api/v1/endpoints"
    mkdir -p "$BACKEND_DIR/app/services"
    mkdir -p "$BACKEND_DIR/app/models"
    mkdir -p "$BACKEND_DIR/app/schemas"
    mkdir -p "$BACKEND_DIR/app/database"
    mkdir -p "$BACKEND_DIR/app/utils"
    mkdir -p "$BACKEND_DIR/app/workers"
    mkdir -p "$BACKEND_DIR/alembic/versions"
    mkdir -p "$BACKEND_DIR/scripts"
    
    # Criar arquivo .env
    cat > "$BACKEND_DIR/.env" << EOF
# Application
APP_NAME="VOD Sync XUI One"
APP_ENV=production
APP_DEBUG=false
APP_URL=http://${DOMAIN:-localhost}
APP_TIMEZONE=America/Sao_Paulo

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

# Redis (opcional)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# TMDb API
TMDB_API_KEY=your_tmdb_api_key_here
TMDB_LANGUAGE=pt-BR
TMDB_REGION=BR

# XUI Defaults
XUI_DEFAULT_PORT=3306
XUI_DEFAULT_TIMEOUT=30

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_PERIOD=60

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/${APP_NAME}/app.log
LOG_MAX_SIZE=10485760  # 10MB
LOG_BACKUP_COUNT=5

# Email (opcional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=noreply@${DOMAIN:-localhost}

# License
LICENSE_VALIDATION_URL=https://license.yourdomain.com/validate
LICENSE_GRACE_DAYS=7
EOF
    
    chmod 600 "$BACKEND_DIR/.env"
    chown www-data:www-data "$BACKEND_DIR/.env"
    
    success "Estrutura do backend criada"
}

create_frontend_structure() {
    log "Criando estrutura do frontend..."
    
    # Configuração do banco de dados PHP
    cat > "$FRONTEND_DIR/app/Config/database.php" << EOF
<?php
return [
    'host' => 'localhost',
    'port' => 3306,
    'database' => '$DB_NAME',
    'username' => '$DB_USER',
    'password' => '$DB_PASS',
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => '',
    'options' => [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]
];
EOF
    
    # Configuração da aplicação PHP
    cat > "$FRONTEND_DIR/app/Config/config.php" << EOF
<?php
return [
    'app' => [
        'name' => 'VOD Sync XUI One',
        'version' => '1.0.0',
        'debug' => false,
        'timezone' => 'America/Sao_Paulo',
        'url' => 'http://${DOMAIN:-localhost}'
    ],
    'api' => [
        'base_url' => 'http://localhost:8000/api/v1',
        'timeout' => 30,
        'retry_attempts' => 3
    ],
    'session' => [
        'name' => 'vod_sync_session',
        'lifetime' => 7200,
        'secure' => false,
        'httponly' => true
    ],
    'upload' => [
        'max_size' => 10485760, // 10MB
        'allowed_types' => ['m3u', 'm3u8', 'txt'],
        'upload_path' => '$FRONTEND_DIR/public/uploads/'
    ]
];
EOF
    
    # Criar .htaccess
    cat > "$FRONTEND_DIR/public/.htaccess" << 'EOF'
RewriteEngine On
RewriteBase /

# Redirect to index.php if file doesn't exist
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php?url=$1 [QSA,L]

# Security headers
Header set X-Content-Type-Options "nosniff"
Header set X-Frame-Options "SAMEORIGIN"
Header set X-XSS-Protection "1; mode=block"

# Compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
</IfModule>
EOF
    
    success "Estrutura do frontend criada"
}

setup_nginx() {
    log "Configurando Nginx..."
    
    # Configuração do site
    cat > /etc/nginx/sites-available/$APP_NAME << EOF
server {
    listen 80;
    server_name ${DOMAIN:-_};
    root $FRONTEND_DIR/public;
    index index.php index.html;
    
    # Frontend PHP
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP-FPM
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # WebSocket para logs em tempo real
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    # Static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Security
    location ~ /\. {
        deny all;
    }
    
    location ~ /(config|logs|backups)/ {
        deny all;
    }
    
    # Logging
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
}
EOF
    
    # Remover configuração padrão e habilitar novo site
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        error "Configuração Nginx inválida"
        exit 1
    fi
    
    systemctl restart nginx >> "$LOG_FILE" 2>&1
    systemctl enable nginx >> "$LOG_FILE" 2>&1
    
    success "Nginx configurado"
}

setup_supervisor() {
    log "Configurando Supervisor..."
    
    # Configuração do serviço FastAPI
    cat > /etc/supervisor/conf.d/$APP_NAME-api.conf << EOF
[program:$APP_NAME-api]
command=$PYTHON_VENV/bin/gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 127.0.0.1:8000
directory=$BACKEND_DIR
user=www-data
autostart=true
autorestart=true
stderr_logfile=/var/log/$APP_NAME/api-error.log
stdout_logfile=/var/log/$APP_NAME/api-access.log
environment=PYTHONPATH="$BACKEND_DIR",PATH="$PYTHON_VENV/bin"
EOF
    
    # Configuração do worker de sincronização
    cat > /etc/supervisor/conf.d/$APP_NAME-worker.conf << EOF
[program:$APP_NAME-worker]
command=$PYTHON_VENV/bin/python -m app.workers.sync_worker
directory=$BACKEND_DIR
user=www-data
autostart=true
autorestart=true
stderr_logfile=/var/log/$APP_NAME/worker-error.log
stdout_logfile=/var/log/$APP_NAME/worker-access.log
environment=PYTHONPATH="$BACKEND_DIR",PATH="$PYTHON_VENV/bin"
EOF
    
    # Configuração do scheduler
    cat > /etc/supervisor/conf.d/$APP_NAME-scheduler.conf << EOF
[program:$APP_NAME-scheduler]
command=$PYTHON_VENV/bin/python -m app.workers.scheduler_worker
directory=$BACKEND_DIR
user=www-data
autostart=true
autorestart=true
stderr_logfile=/var/log/$APP_NAME/scheduler-error.log
stdout_logfile=/var/log/$APP_NAME/scheduler-access.log
environment=PYTHONPATH="$BACKEND_DIR",PATH="$PYTHON_VENV/bin"
EOF
    
    systemctl restart supervisor >> "$LOG_FILE" 2>&1
    supervisorctl update >> "$LOG_FILE" 2>&1
    
    success "Supervisor configurado"
}

setup_systemd() {
    log "Configurando serviços systemd..."
    
    # Serviço de backup automático
    cat > /etc/systemd/system/$APP_NAME-backup.service << EOF
[Unit]
Description=VOD Sync XUI One - Backup Service
After=mysql.service

[Service]
Type=oneshot
User=www-data
Group=www-data
ExecStart=$INSTALL_DIR/scripts/backup.sh
Environment=PATH=$PYTHON_VENV/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
    
    # Timer para backup diário
    cat > /etc/systemd/system/$APP_NAME-backup.timer << EOF
[Unit]
Description=Daily backup for VOD Sync XUI One

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable $APP_NAME-backup.timer >> "$LOG_FILE" 2>&1
    systemctl start $APP_NAME-backup.timer >> "$LOG_FILE" 2>&1
    
    success "Serviços systemd configurados"
}

setup_firewall() {
    log "Configurando firewall..."
    
    # Instalar UFW se não estiver instalado
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw >> "$LOG_FILE" 2>&1
    fi
    
    ufw --force enable >> "$LOG_FILE" 2>&1
    ufw allow 22/tcp comment 'SSH' >> "$LOG_FILE" 2>&1
    ufw allow 80/tcp comment 'HTTP' >> "$LOG_FILE" 2>&1
    ufw allow 443/tcp comment 'HTTPS' >> "$LOG_FILE" 2>&1
    ufw allow 8000/tcp comment 'API Internal' >> "$LOG_FILE" 2>&1
    ufw reload >> "$LOG_FILE" 2>&1
    
    success "Firewall configurado"
}

setup_ssl() {
    if [[ -n "$DOMAIN" && "$DOMAIN" != "localhost" ]]; then
        log "Configurando SSL com Let's Encrypt..."
        
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN >> "$LOG_FILE" 2>&1
        
        if [[ $? -eq 0 ]]; then
            # Atualizar .env com HTTPS
            sed -i "s|APP_URL=http://|APP_URL=https://|g" "$BACKEND_DIR/.env"
            success "SSL configurado para $DOMAIN"
        else
            warning "Falha ao obter certificado SSL. Configure manualmente."
        fi
    else
        warning "Domínio não configurado. SSL não será configurado."
    fi
}

create_admin_user() {
    log "Criando usuário administrador..."
    
    # Gerar senha aleatória para admin
    ADMIN_PASS=$(openssl rand -base64 12)
    ADMIN_HASH=$(echo -n "$ADMIN_PASS" | openssl dgst -sha256 | cut -d' ' -f2)
    
    # Inserir usuário admin no banco
    SQL_ADMIN=$(cat <<EOF
USE $DB_NAME;

-- Inserir usuário administrador
INSERT INTO users (uuid, username, email, password_hash, full_name, role, is_active) 
VALUES (
    UUID(),
    'admin',
    'admin@${DOMAIN:-localhost}',
    '$ADMIN_HASH',
    'Administrador',
    'admin',
    TRUE
) ON DUPLICATE KEY UPDATE email='admin@${DOMAIN:-localhost}';

-- Inserir licença trial
INSERT INTO licenses (license_key, type, user_id, max_users, valid_from, valid_until, is_active, features)
VALUES (
    'TRIAL-'$(date +%Y%m%d)'-'$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]'),
    'trial',
    (SELECT id FROM users WHERE username='admin'),
    1,
    CURDATE(),
    DATE_ADD(CURDATE(), INTERVAL 30 DAY),
    TRUE,
    '{"auto_sync": true, "tmdb": true, "multiple_xui": false, "api_access": true}'
);
EOF
)
    
    mysql -e "$SQL_ADMIN" >> "$LOG_FILE" 2>&1
    
    # Salvar credenciais em arquivo seguro
    cat > "$INSTALL_DIR/credentials.txt" << EOF
============================================
VOD SYNC XUI ONE - CREDENCIAIS DE ACESSO
============================================
URL de acesso: http://${DOMAIN:-seu-ip}
Usuário: admin
Senha: $ADMIN_PASS

============================================
CONFIGURAÇÕES DO BANCO DE DADOS
============================================
Banco de dados: $DB_NAME
Usuário: $DB_USER
Senha: $DB_PASS

============================================
CONFIGURAÇÕES IMPORTANTES
============================================
1. Configure sua chave API TMDb em:
   $BACKEND_DIR/.env
   TMDB_API_KEY=sua_chave_aqui

2. Para produção, altere todas as senhas!

3. Certifique-se de configurar o cron para backup:
   0 2 * * * $INSTALL_DIR/scripts/backup.sh

============================================
ARQUIVOS DE LOG
============================================
Backend: /var/log/$APP_NAME/
Nginx: /var/log/nginx/${APP_NAME}_*.log
Supervisor: /var/log/supervisor/

Guarde este arquivo em local seguro!
EOF
    
    chmod 600 "$INSTALL_DIR/credentials.txt"
    
    success "Usuário administrador criado"
    warning "Credenciais salvas em: $INSTALL_DIR/credentials.txt"
    echo -e "${YELLOW}Senha do admin: ${ADMIN_PASS}${NC}"
}

create_backup_script() {
    log "Criando script de backup..."
    
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
# backup.sh - Script de backup do VOD Sync XUI One

BACKUP_DIR="/opt/vod-sync-xui/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"
LOG_FILE="/var/log/vod-sync-xui/backup.log"
RETENTION_DAYS=7

# Configurações do banco
DB_NAME="vod_sync_system"
DB_USER="vod_sync_user"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Criar diretório de backup se não existir
mkdir -p "$BACKUP_DIR"

log "Iniciando backup..."

# Backup do banco de dados
DB_FILE="/tmp/db_backup_$DATE.sql"
mysqldump --single-transaction --routines --triggers "$DB_NAME" > "$DB_FILE" 2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
    log "Backup do banco de dados concluído: $(du -h "$DB_FILE" | cut -f1)"
else
    log "ERRO: Falha no backup do banco de dados"
    exit 1
fi

# Compactar tudo
tar czf "$BACKUP_FILE" \
    -C /opt/vod-sync-xui \
    backend \
    frontend \
    "$DB_FILE" \
    2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
    log "Backup compactado: $(du -h "$BACKUP_FILE" | cut -f1)"
else
    log "ERRO: Falha ao compactar backup"
    exit 1
fi

# Limpar arquivo temporário
rm -f "$DB_FILE"

# Limpar backups antigos
find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>> "$LOG_FILE"
log "Backups antigos removidos (retenção: $RETENTION_DAYS dias)"

# Verificar integridade do backup
if tar tzf "$BACKUP_FILE" > /dev/null 2>&1; then
    log "Backup concluído com sucesso: $BACKUP_FILE"
else
    log "ERRO: Backup corrompido"
    exit 1
fi

log "========================================="
EOF
    
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    success "Script de backup criado"
}

create_update_script() {
    log "Criando script de atualização..."
    
    cat > "$INSTALL_DIR/scripts/update.sh" << 'EOF'
#!/bin/bash
# update.sh - Script de atualização do VOD Sync XUI One

APP_NAME="vod-sync-xui"
INSTALL_DIR="/opt/$APP_NAME"
BACKEND_DIR="$INSTALL_DIR/backend"
FRONTEND_DIR="$INSTALL_DIR/frontend"
PYTHON_VENV="$INSTALL_DIR/venv"
LOG_FILE="/var/log/$APP_NAME/update.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root"
        exit 1
    fi
}

backup_before_update() {
    log "Criando backup antes da atualização..."
    $INSTALL_DIR/scripts/backup.sh
}

update_backend() {
    log "Atualizando backend..."
    
    cd "$BACKEND_DIR"
    
    # Atualizar código do backend
    git pull origin main 2>> "$LOG_FILE"
    
    if [[ $? -ne 0 ]]; then
        error "Falha ao atualizar código do backend"
        return 1
    fi
    
    # Atualizar dependências Python
    source "$PYTHON_VENV/bin/activate"
    pip install -r requirements.txt --upgrade 2>> "$LOG_FILE"
    
    # Executar migrações do banco
    alembic upgrade head 2>> "$LOG_FILE"
    
    success "Backend atualizado"
}

update_frontend() {
    log "Atualizando frontend..."
    
    cd "$FRONTEND_DIR"
    
    # Atualizar código do frontend
    git pull origin main 2>> "$LOG_FILE"
    
    if [[ $? -ne 0 ]]; then
        error "Falha ao atualizar código do frontend"
        return 1
    fi
    
    # Atualizar dependências Composer
    composer install --no-dev --optimize-autoloader 2>> "$LOG_FILE"
    
    # Limpar cache
    rm -rf "$FRONTEND_DIR/public/cache/*"
    
    success "Frontend atualizado"
}

restart_services() {
    log "Reiniciando serviços..."
    
    supervisorctl restart $APP_NAME-api 2>> "$LOG_FILE"
    supervisorctl restart $APP_NAME-worker 2>> "$LOG_FILE"
    supervisorctl restart $APP_NAME-scheduler 2>> "$LOG_FILE"
    
    systemctl restart nginx 2>> "$LOG_FILE"
    
    success "Serviços reiniciados"
}

main() {
    check_root
    
    log "Iniciando atualização do $APP_NAME"
    
    # Criar backup
    backup_before_update
    
    # Manter arquivo .env
    cp "$BACKEND_DIR/.env" /tmp/vod_sync_env.bak
    
    # Atualizar componentes
    update_backend
    update_frontend
    
    # Restaurar .env
    cp /tmp/vod_sync_env.bak "$BACKEND_DIR/.env"
    
    # Reiniciar serviços
    restart_services
    
    log "Atualização concluída com sucesso!"
    
    # Mostrar status
    supervisorctl status | grep $APP_NAME
}

main "$@"
EOF
    
    chmod +x "$INSTALL_DIR/scripts/update.sh"
    
    success "Script de atualização criado"
}

setup_cron() {
    log "Configurando tarefas cron..."
    
    # Backup automático via cron (fallback)
    CRON_BACKUP="0 2 * * * $INSTALL_DIR/scripts/backup.sh >> /var/log/$APP_NAME/cron-backup.log 2>&1"
    
    # Limpeza de logs antigos
    CRON_CLEAN="0 1 * * 0 find /var/log/$APP_NAME -name \"*.log\" -mtime +30 -delete"
    
    # Monitoramento de saúde
    CRON_HEALTH="*/5 * * * * $INSTALL_DIR/scripts/health-check.sh >> /var/log/$APP_NAME/cron-health.log 2>&1"
    
    echo -e "$CRON_BACKUP\n$CRON_CLEAN\n$CRON_HEALTH" | crontab -u www-data -
    
    success "Tarefas cron configuradas"
}

create_health_check() {
    log "Criando script de health check..."
    
    cat > "$INSTALL_DIR/scripts/health-check.sh" << 'EOF'
#!/bin/bash
# health-check.sh - Monitoramento de saúde do sistema

APP_NAME="vod-sync-xui"
INSTALL_DIR="/opt/$APP_NAME"
LOG_FILE="/var/log/$APP_NAME/health.log"

check_service() {
    SERVICE=$1
    if systemctl is-active --quiet "$SERVICE"; then
        echo "[OK] $SERVICE está ativo"
    else
        echo "[ERRO] $SERVICE está inativo"
        systemctl restart "$SERVICE"
    fi
}

check_supervisor() {
    PROCESS=$1
    STATUS=$(supervisorctl status "$PROCESS" 2>/dev/null | awk '{print $2}')
    if [[ "$STATUS" == "RUNNING" ]]; then
        echo "[OK] $PROCESS está rodando"
    else
        echo "[ERRO] $PROCESS com status: $STATUS"
        supervisorctl restart "$PROCESS"
    fi
}

check_disk() {
    USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ $USAGE -gt 90 ]]; then
        echo "[ALERTA] Uso de disco: $USAGE%"
    else
        echo "[OK] Uso de disco: $USAGE%"
    fi
}

check_memory() {
    FREE_MEM=$(free -m | awk 'NR==2 {print $4}')
    if [[ $FREE_MEM -lt 100 ]]; then
        echo "[ALERTA] Memória livre: ${FREE_MEM}MB"
    else
        echo "[OK] Memória livre: ${FREE_MEM}MB"
    fi
}

check_api() {
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/v1/health)
    if [[ "$RESPONSE" == "200" ]]; then
        echo "[OK] API respondendo"
    else
        echo "[ERRO] API não respondendo: HTTP $RESPONSE"
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

main() {
    echo "=== Health Check $APP_NAME ==="
    
    # Serviços systemd
    check_service nginx
    check_service mysql
    check_service supervisor
    
    # Processos supervisor
    check_supervisor "$APP_NAME-api"
    check_supervisor "$APP_NAME-worker"
    check_supervisor "$APP_NAME-scheduler"
    
    # Recursos do sistema
    check_disk
    check_memory
    
    # API
    check_api
    
    echo "=== Health Check Concluído ==="
}

main 2>&1 | while IFS= read -r line; do log "$line"; done
EOF
    
    chmod +x "$INSTALL_DIR/scripts/health-check.sh"
    
    success "Script de health check criado"
}

finalize_installation() {
    log "Finalizando instalação..."
    
    # Ajustar permissões finais
    chown -R www-data:www-data "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod -R 775 "$INSTALL_DIR/logs"
    chmod -R 775 "$INSTALL_DIR/backups"
    
    # Criar link simbólico para logs
    ln -sf "/var/log/$APP_NAME" "$INSTALL_DIR/logs/system"
    
    # Reiniciar todos os serviços
    systemctl restart nginx
    systemctl restart supervisor
    supervisorctl restart all
    
    # Aguardar serviços iniciarem
    sleep 5
    
    # Verificar status
    log "Verificando status dos serviços..."
    supervisorctl status | grep "$APP_NAME"
    
    # Testar API
    API_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/v1/health 2>/dev/null || echo "000")
    
    if [[ "$API_TEST" == "200" ]]; then
        success "API está respondendo corretamente"
    else
        warning "API não está respondendo (HTTP $API_TEST)"
    fi
    
    success "Instalação concluída com sucesso!"
    
    # Mostrar informações finais
    echo ""
    echo "========================================================"
    echo "         VOD SYNC XUI ONE - INSTALAÇÃO CONCLUÍDA       "
    echo "========================================================"
    echo ""
    echo "📁 Diretório de instalação: $INSTALL_DIR"
    echo "🌐 URL de acesso: http://${DOMAIN:-seu-ip}"
    echo "🔑 Credenciais: $INSTALL_DIR/credentials.txt"
    echo ""
    echo "📊 Serviços instalados:"
    echo "   - Nginx (Web Server)"
    echo "   - MySQL (Banco de dados)"
    echo "   - Python Backend (FastAPI)"
    echo "   - PHP Frontend"
    echo "   - Supervisor (Gerenciador de processos)"
    echo "   - Backup automático diário"
    echo ""
    echo "🔧 Próximos passos:"
    echo "   1. Configure sua chave API TMDb em:"
    echo "      $BACKEND_DIR/.env"
    echo "   2. Acesse o painel com as credenciais acima"
    echo "   3. Configure sua conexão XUI One"
    echo "   4. Adicione sua lista M3U"
    echo ""
    echo "📞 Suporte e documentação:"
    echo "   Logs: /var/log/$APP_NAME/"
    echo "   Scripts: $INSTALL_DIR/scripts/"
    echo "   Backup: $INSTALL_DIR/backups/"
    echo ""
    echo "========================================================"
}

# ============================================
# FUNÇÃO PRINCIPAL
# ============================================

main() {
    clear
    echo "==========================================="
    echo "  INSTALADOR VOD SYNC XUI ONE v1.0.0"
    echo "==========================================="
    echo ""
    
    # Obter domínio se fornecido
    if [[ -n "$1" ]]; then
        DOMAIN="$1"
        log "Domínio configurado: $DOMAIN"
    fi
    
    # Verificar requisitos
    check_root
    check_os
    
    # Exibir informações
    echo ""
    echo "📋 Informações da instalação:"
    echo "   Sistema: $OS $VERSION"
    echo "   Diretório: $INSTALL_DIR"
    echo "   Banco de dados: $DB_NAME"
    echo "   Domínio: ${DOMAIN:-localhost}"
    echo ""
    
    read -p "Deseja continuar com a instalação? (s/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        error "Instalação cancelada pelo usuário"
        exit 0
    fi
    
    # Iniciar instalação
    log "Iniciando instalação do $APP_NAME"
    
    # Executar passos de instalação
    install_dependencies
    setup_mysql
    setup_directory
    setup_python_backend
    setup_php_frontend
    create_backend_structure
    create_frontend_structure
    setup_nginx
    setup_supervisor
    setup_systemd
    setup_firewall
    setup_ssl
    create_backup_script
    create_update_script
    create_health_check
    setup_cron
    create_admin_user
    finalize_installation
    
    # Registrar instalação
    echo "$(date) - Instalação concluída - $DOMAIN" >> "$INSTALL_DIR/INSTALL.log"
}

# Executar função principal
main "$@"
