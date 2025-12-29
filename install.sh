#!/bin/bash
# install_vod_sync_nginx_only.sh - Instalador CORRIGIDO (somente Nginx)

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
DOMAIN="${1:-}" # Definir via parâmetro

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
    exit 1
}

warning() {
    echo -e "${YELLOW}!${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root"
    fi
}

stop_apache() {
    log "Verificando e parando Apache..."
    
    # Verificar se Apache está instalado
    if systemctl is-active --quiet apache2 2>/dev/null; then
        log "Apache está rodando, parando..."
        systemctl stop apache2
        systemctl disable apache2
        success "Apache parado e desabilitado"
    fi
    
    # Verificar se há processos Apache usando porta 80
    if netstat -tlnp | grep :80 | grep apache; then
        warning "Processos Apache ainda usando porta 80"
        pkill -9 apache2 2>/dev/null || true
    fi
}

check_port_80() {
    log "Verificando porta 80..."
    
    # Verificar se há algum serviço usando porta 80
    if netstat -tlnp | grep :80 > /dev/null; then
        warning "Porta 80 está em uso por:"
        netstat -tlnp | grep :80
        
        # Matar processos usando porta 80 (exceto nginx)
        for pid in $(lsof -ti:80); do
            process=$(ps -p $pid -o comm=)
            if [[ "$process" != "nginx" ]]; then
                log "Encerrando processo $process (PID: $pid) usando porta 80"
                kill -9 $pid 2>/dev/null || true
            fi
        done
        
        sleep 2
        
        # Verificar novamente
        if netstat -tlnp | grep :80 > /dev/null; then
            error "Não foi possível liberar porta 80"
        fi
    else
        success "Porta 80 está livre"
    fi
}

install_dependencies() {
    log "Instalando dependências do sistema..."
    
    # Parar Apache primeiro
    stop_apache
    
    # Atualizar sistema
    apt-get update >> "$LOG_FILE" 2>&1 || error "Falha ao atualizar pacotes"
    
    # Instalar ferramentas essenciais
    log "Instalando ferramentas essenciais..."
    ESSENTIAL="curl wget git build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release"
    apt-get install -y $ESSENTIAL >> "$LOG_FILE" 2>&1 || error "Falha ao instalar ferramentas essenciais"
    
    # Adicionar repositório para PHP 8.1 (Ubuntu 20.04/22.04)
    if [[ "$VERSION" == "20.04" || "$VERSION" == "22.04" ]]; then
        log "Adicionando repositório PHP 8.1..."
        add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
        apt-get update >> "$LOG_FILE" 2>&1
    fi
    
    # Instalar Python 3
    log "Instalando Python 3..."
    apt-get install -y python3 python3-pip python3-venv python3-dev >> "$LOG_FILE" 2>&1 || error "Falha ao instalar Python"
    
    # Instalar MySQL
    log "Instalando MySQL..."
    apt-get install -y mysql-server mysql-client libmysqlclient-dev >> "$LOG_FILE" 2>&1 || error "Falha ao instalar MySQL"
    
    # Instalar PHP (NÃO instalar apache2!)
    log "Instalando PHP (somente CLI e FPM)..."
    apt-get install -y php8.1-cli php8.1-fpm php8.1-mysql php8.1-curl php8.1-gd php8.1-mbstring php8.1-xml php8.1-zip php8.1-bcmath >> "$LOG_FILE" 2>&1 || {
        warning "Falha ao instalar PHP 8.1, tentando PHP padrão..."
        apt-get install -y php-cli php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-bcmath >> "$LOG_FILE" 2>&1 || error "Falha ao instalar PHP"
    }
    
    # Instalar Nginx (NÃO instalar apache2!)
    log "Instalando Nginx..."
    apt-get install -y nginx >> "$LOG_FILE" 2>&1 || error "Falha ao instalar Nginx"
    
    # Instalar Supervisor
    log "Instalando Supervisor..."
    apt-get install -y supervisor >> "$LOG_FILE" 2>&1 || error "Falha ao instalar Supervisor"
    
    # Outras dependências
    log "Instalando outras dependências..."
    apt-get install -y redis-server fail2ban ufw >> "$LOG_FILE" 2>&1 || warning "Algumas dependências opcionais falharam"
    
    success "Dependências instaladas com sucesso"
}

configure_php_fpm() {
    log "Configurando PHP-FPM..."
    
    # Configurar PHP-FPM para usar socket
    PHP_FPM_CONF="/etc/php/8.1/fpm/pool.d/www.conf"
    if [[ -f "$PHP_FPM_CONF" ]]; then
        # Backup da configuração original
        cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup"
        
        # Configurar para usar socket Unix
        sed -i 's/listen = .*/listen = \/var\/run\/php\/php8.1-fpm.sock/' "$PHP_FPM_CONF"
        sed -i 's/;listen.owner = www-data/listen.owner = www-data/' "$PHP_FPM_CONF"
        sed -i 's/;listen.group = www-data/listen.group = www-data/' "$PHP_FPM_CONF"
        sed -i 's/;listen.mode = 0660/listen.mode = 0660/' "$PHP_FPM_CONF"
        
        # Aumentar limites para processamento
        sed -i 's/pm.max_children = .*/pm.max_children = 50/' "$PHP_FPM_CONF"
        sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' "$PHP_FPM_CONF"
        sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$PHP_FPM_CONF"
        sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$PHP_FPM_CONF"
        
        success "PHP-FPM configurado"
    else
        # Tentar encontrar arquivo de configuração
        PHP_FPM_CONF=$(find /etc/php -name "www.conf" | head -1)
        if [[ -f "$PHP_FPM_CONF" ]]; then
            sed -i 's/listen = .*/listen = \/var\/run\/php\/php-fpm.sock/' "$PHP_FPM_CONF"
            success "PHP-FPM configurado (configuração alternativa)"
        else
            warning "Arquivo de configuração PHP-FPM não encontrado"
        fi
    fi
    
    # Reiniciar PHP-FPM
    systemctl restart php8.1-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null
}

configure_nginx() {
    log "Configurando Nginx..."
    
    # Parar Nginx se estiver rodando
    systemctl stop nginx 2>/dev/null || true
    
    # Verificar e liberar porta 80
    check_port_80
    
    # Remover configurações padrão do Nginx
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Configuração do site
    NGINX_SITE="/etc/nginx/sites-available/$APP_NAME"
    
    cat > "$NGINX_SITE" << EOF
# VOD Sync XUI One - Nginx Configuration
server {
    listen 80;
    listen [::]:80;
    
    server_name ${DOMAIN:-_} localhost 127.0.0.1;
    root $FRONTEND_DIR/public;
    index index.php index.html index.htm;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logging
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
    
    # Frontend PHP
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP-FPM configuration
    location ~ \\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        
        # Usar socket Unix do PHP-FPM
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Security
        fastcgi_hide_header X-Powered-By;
        fastcgi_param HTTP_PROXY "";
        
        # Timeouts
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
    
    # Backend API - FastAPI
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
        proxy_cache off;
    }
    
    # WebSocket for real-time logs
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    
    # Static files
    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files \$uri =404;
    }
    
    # Deny access to sensitive files
    location ~ /(\\.|config|logs|backups|storage) {
        deny all;
        return 404;
    }
    
    location ~ /\\.ht {
        deny all;
        return 404;
    }
    
    # Security: deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}

# Se tiver domínio, configurar redirect HTTP para HTTPS
EOF
    
    # Habilitar site
    ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/
    
    # Testar configuração
    log "Testando configuração Nginx..."
    if nginx -t >> "$LOG_FILE" 2>&1; then
        success "Configuração Nginx testada com sucesso"
    else
        error "Configuração Nginx inválida"
    fi
    
    # Iniciar Nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Verificar status
    if systemctl is-active --quiet nginx; then
        success "Nginx iniciado com sucesso"
    else
        error "Nginx falhou ao iniciar"
    fi
}

main() {
    clear
    
    echo "========================================================"
    echo "  VOD SYNC XUI ONE - INSTALADOR (NGINX ONLY) v1.0.0    "
    echo "========================================================"
    echo ""
    
    # Verificar root
    check_root
    
    # Verificar parâmetros
    if [[ -n "$1" ]]; then
        DOMAIN="$1"
        log "Domínio configurado: $DOMAIN"
    fi
    
    # Detectar sistema
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Não foi possível detectar o sistema"
    fi
    
    echo "📋 Sistema: $OS $VERSION"
    echo "📁 Diretório: $INSTALL_DIR"
    echo "🌐 Domínio: ${DOMAIN:-localhost}"
    echo ""
    
    read -p "Deseja continuar? (s/N): " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[SsYy]$ ]] && error "Instalação cancelada"
    
    # Iniciar instalação
    log "Iniciando instalação..."
    
    # Passos principais
    install_dependencies
    configure_php_fpm
    configure_nginx
    
    success "Instalação concluída!"
    echo ""
    echo "✅ Nginx configurado e rodando"
    echo "✅ Apache parado e desabilitado"
    echo "✅ Porta 80 liberada para Nginx"
    echo ""
    echo "Acesse: http://${DOMAIN:-seu-ip}"
}

# Executar
main "$@"
