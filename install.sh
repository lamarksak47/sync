#!/bin/bash

# ============================================
# INSTALADOR COMPLETO - VOD SYNC SYSTEM
# ============================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório base
BASE_DIR=$(pwd)
BACKEND_DIR="$BASE_DIR/backend"
FRONTEND_DIR="$BASE_DIR/frontend"
INSTALL_DIR="$BASE_DIR/install"
LOG_FILE="/var/log/vod-sync-install.log"

# Funções de utilitário
print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          VOD SYNC SYSTEM - INSTALAÇÃO COMPLETA          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Verificar se é root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Este script requer privilégios de root."
        echo "Por favor, execute com: sudo ./install.sh"
        exit 1
    fi
}

# Verificar dependências do sistema
check_dependencies() {
    log "Verificando dependências do sistema..."
    
    local deps_ok=true
    
    # Lista de dependências
    declare -A dependencies=(
        ["python3"]="Python 3.10+"
        ["pip3"]="Pip para Python"
        ["php"]="PHP 8.0+"
        ["mysql"]="MySQL/MariaDB"
        ["git"]="Git"
        ["curl"]="cURL"
        ["wget"]="Wget"
    )
    
    for cmd in "${!dependencies[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            warning "${dependencies[$cmd]} não encontrado"
            deps_ok=false
        else
            success "${dependencies[$cmd]} encontrado"
        fi
    done
    
    if [ "$deps_ok" = false ]; then
        echo ""
        read -p "Deseja instalar as dependências faltantes automaticamente? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            install_dependencies
        else
            error "Por favor, instale as dependências manualmente antes de continuar."
        fi
    fi
}

# Instalar dependências
install_dependencies() {
    log "Instalando dependências do sistema..."
    
    # Detectar distribuição
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y python3 python3-pip python3-venv \
                          php php-fpm php-mysql php-curl php-json php-mbstring \
                          mysql-server mysql-client \
                          git curl wget nginx \
                          build-essential libssl-dev libffi-dev \
                          python3-dev default-libmysqlclient-dev
        
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        yum install -y python3 python3-pip python3-virtualenv \
                      php php-fpm php-mysql php-curl php-json php-mbstring \
                      mariadb-server mariadb-client \
                      git curl wget nginx \
                      gcc make openssl-devel mysql-devel
        
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        pacman -Syu --noconfirm python python-pip php php-fpm mariadb \
                               nginx git curl wget base-devel
    else
        error "Distribuição não suportada. Instale manualmente as dependências."
    fi
    
    success "Dependências instaladas com sucesso"
}

# Configurar banco de dados
setup_database() {
    print_step "Configurando banco de dados..."
    
    # Parâmetros do banco de dados
    DB_NAME="vod_system"
    DB_USER="vodsync_user"
    DB_PASS=$(openssl rand -base64 12)
    
    log "Criando banco de dados: $DB_NAME"
    
    # Criar banco de dados
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE" || {
        error "Falha ao criar banco de dados"
    }
    
    # Criar usuário
    log "Criando usuário: $DB_USER"
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$LOG_FILE" || {
        error "Falha ao criar usuário do banco"
    }
    
    # Conceder privilégios
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>> "$LOG_FILE" || {
        error "Falha ao conceder privilégios"
    }
    
    mysql -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"
    
    # Importar estrutura do banco
    log "Importando estrutura do banco de dados..."
    
    # Criar arquivo SQL temporário com estrutura básica
    cat > /tmp/vod_system_structure.sql << 'EOF'
-- ============================================
-- BANCO DE DADOS - VOD SYNC SYSTEM
-- ============================================

CREATE DATABASE IF NOT EXISTS vod_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vod_system;

-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('admin', 'reseller', 'user') DEFAULT 'user',
    parent_id INT NULL,
    license_key VARCHAR(100) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    max_connections INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    FOREIGN KEY (parent_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_type (user_type),
    INDEX idx_parent (parent_id)
) ENGINE=InnoDB;

-- Tabela de licenças
CREATE TABLE IF NOT EXISTS licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_key VARCHAR(100) UNIQUE NOT NULL,
    user_id INT NULL,
    type ENUM('trial', 'monthly', 'yearly', 'lifetime') DEFAULT 'monthly',
    status ENUM('active', 'expired', 'suspended', 'pending') DEFAULT 'pending',
    max_users INT DEFAULT 1,
    max_xui_connections INT DEFAULT 1,
    valid_from DATE,
    valid_until DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_status (status),
    INDEX idx_valid_until (valid_until)
) ENGINE=InnoDB;

-- Tabela de conexões XUI
CREATE TABLE IF NOT EXISTS xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    alias VARCHAR(100),
    host VARCHAR(255) NOT NULL,
    port INT DEFAULT 3306,
    database_name VARCHAR(100) DEFAULT 'xui',
    username VARCHAR(100) NOT NULL,
    password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_test TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_active (user_id, is_active)
) ENGINE=InnoDB;

-- Tabela de listas M3U
CREATE TABLE IF NOT EXISTS m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    name VARCHAR(255),
    m3u_content LONGTEXT NOT NULL,
    total_channels INT DEFAULT 0,
    total_vod INT DEFAULT 0,
    total_series INT DEFAULT 0,
    parsed_data JSON,
    is_active BOOLEAN DEFAULT TRUE,
    last_parsed TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user (user_id)
) ENGINE=InnoDB;

-- Tabela de categorias
CREATE TABLE IF NOT EXISTS categories (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    xui_connection_id INT NOT NULL,
    name VARCHAR(255) NOT NULL,
    category_type ENUM('movie', 'series') NOT NULL,
    tmdb_genre_id INT NULL,
    external_id VARCHAR(100),
    is_selected BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_user_category (user_id, xui_connection_id, name, category_type),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (xui_connection_id) REFERENCES xui_connections(id) ON DELETE CASCADE,
    INDEX idx_type_selected (category_type, is_selected)
) ENGINE=InnoDB;

-- Tabela de agendamentos
CREATE TABLE IF NOT EXISTS schedules (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    name VARCHAR(100),
    schedule_type ENUM('sync', 'backup', 'cleanup') DEFAULT 'sync',
    cron_expression VARCHAR(50) DEFAULT '0 2 * * *',
    is_active BOOLEAN DEFAULT TRUE,
    last_run TIMESTAMP NULL,
    next_run TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_next_run (next_run, is_active)
) ENGINE=InnoDB;

-- Tabela de logs de sincronização
CREATE TABLE IF NOT EXISTS sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    xui_connection_id INT NOT NULL,
    m3u_list_id INT NOT NULL,
    log_type ENUM('info', 'warning', 'error', 'success') DEFAULT 'info',
    operation ENUM('insert', 'update', 'skip', 'delete') DEFAULT 'insert',
    content_type ENUM('movie', 'series', 'category') DEFAULT 'movie',
    item_title VARCHAR(500),
    tmdb_id INT NULL,
    message TEXT,
    details JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (xui_connection_id) REFERENCES xui_connections(id) ON DELETE CASCADE,
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE CASCADE,
    INDEX idx_user_created (user_id, created_at),
    INDEX idx_operation_type (operation, content_type)
) ENGINE=InnoDB;

-- Tabela de configurações do sistema
CREATE TABLE IF NOT EXISTS system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type ENUM('string', 'int', 'bool', 'json') DEFAULT 'string',
    category VARCHAR(50) DEFAULT 'general',
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category)
) ENGINE=InnoDB;

-- Tabela de cache TMDb
CREATE TABLE IF NOT EXISTS tmdb_cache (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tmdb_id INT NOT NULL,
    content_type ENUM('movie', 'tv') NOT NULL,
    language VARCHAR(10) DEFAULT 'pt-BR',
    data JSON NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    UNIQUE KEY unique_tmdb_content (tmdb_id, content_type, language),
    INDEX idx_expires (expires_at)
) ENGINE=InnoDB;

-- Inserir configurações padrão
INSERT IGNORE INTO system_settings (setting_key, setting_value, setting_type, category) VALUES
('system_name', 'VOD Sync System', 'string', 'general'),
('tmdb_api_key', '', 'string', 'tmdb'),
('tmdb_language', 'pt-BR', 'string', 'tmdb'),
('sync_auto_start', 'true', 'bool', 'sync'),
('default_sync_time', '02:00', 'string', 'sync'),
('max_retries', '3', 'int', 'sync'),
('log_retention_days', '30', 'int', 'logs'),
('license_key', 'TRIAL-7DAYS', 'string', 'license');

-- Inserir usuário administrador padrão (senha: admin123)
INSERT IGNORE INTO users (username, email, password_hash, user_type, is_active) 
VALUES ('admin', 'admin@vodsync.local', '$2b$12$LQv3c1yqBWVHxpd5g8T3e.BHZzl6CLj7/5L8OYyN8pMZ7cJkzq6W2', 'admin', TRUE);

-- Inserir licença trial
INSERT IGNORE INTO licenses (license_key, user_id, type, status, max_users, valid_from, valid_until) 
VALUES ('TRIAL-7DAYS', 1, 'trial', 'active', 1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY));
EOF
    
    mysql -u root $DB_NAME < /tmp/vod_system_structure.sql 2>> "$LOG_FILE" || {
        error "Falha ao importar estrutura do banco de dados"
    }
    
    # Salvar credenciais
    cat > /root/vod-sync-db-credentials.txt << EOF
============================================
CREDENCIAIS DO BANCO DE DADOS - VOD SYNC
============================================
Banco de Dados: $DB_NAME
Usuário: $DB_USER
Senha: $DB_PASS
Host: localhost
Porta: 3306

Guarde estas informações em um local seguro!
============================================
EOF
    
    # Atualizar arquivos de configuração
    if [ -f "$BACKEND_DIR/.env" ]; then
        sed -i "s/DB_NAME=.*/DB_NAME=$DB_NAME/" "$BACKEND_DIR/.env"
        sed -i "s/DB_USER=.*/DB_USER=$DB_USER/" "$BACKEND_DIR/.env"
        sed -i "s/DB_PASS=.*/DB_PASS=$DB_PASS/" "$BACKEND_DIR/.env"
    fi
    
    success "Banco de dados configurado com sucesso"
    log "Credenciais salvas em: /root/vod-sync-db-credentials.txt"
}

# Configurar backend Python
setup_backend() {
    print_step "Configurando backend Python..."
    
    if [ ! -d "$BACKEND_DIR" ]; then
        error "Diretório backend não encontrado: $BACKEND_DIR"
    fi
    
    cd "$BACKEND_DIR"
    
    # Criar ambiente virtual
    log "Criando ambiente virtual Python..."
    python3 -m venv venv 2>> "$LOG_FILE" || {
        error "Falha ao criar ambiente virtual"
    }
    
    # Ativar e instalar dependências
    log "Instalando dependências Python..."
    source venv/bin/activate
    pip install --upgrade pip 2>> "$LOG_FILE"
    
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt 2>> "$LOG_FILE" || {
            error "Falha ao instalar dependências Python"
        }
    else
        # Instalar dependências básicas se requirements.txt não existir
        pip install fastapi uvicorn sqlalchemy pymysql python-dotenv \
                   requests apscheduler python-jose[cryptography] \
                   passlib[bcrypt] beautifulsoup4 2>> "$LOG_FILE" || {
            error "Falha ao instalar dependências Python"
        }
    fi
    
    # Configurar chave secreta
    if [ -f ".env" ]; then
        SECRET_KEY=$(openssl rand -hex 32)
        sed -i "s/SECRET_KEY=.*/SECRET_KEY=$SECRET_KEY/" .env
        
        # Solicitar chave TMDb
        echo ""
        echo "🔑 CONFIGURAÇÃO TMDb API"
        echo "Para usar o sistema, você precisa de uma chave de API do TMDb."
        echo "Obtenha em: https://www.themoviedb.org/settings/api"
        echo ""
        read -p "Digite sua chave da API TMDb (ou Enter para pular): " TMDB_API_KEY
        
        if [ -n "$TMDB_API_KEY" ]; then
            sed -i "s/TMDB_API_KEY=.*/TMDB_API_KEY=$TMDB_API_KEY/" .env
            success "Chave TMDb configurada"
        else
            warning "Chave TMDb não configurada. O sistema funcionará sem enriquecimento de metadados."
        fi
    fi
    
    # Criar diretórios necessários
    mkdir -p logs cache
    
    # Criar serviço systemd
    log "Criando serviço systemd para backend..."
    
    cat > /etc/systemd/system/vod-sync-backend.service << EOF
[Unit]
Description=VOD Sync System Backend API
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin"
ExecStart=$BACKEND_DIR/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
StandardOutput=append:$BACKEND_DIR/logs/backend.log
StandardError=append:$BACKEND_DIR/logs/backend-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable vod-sync-backend 2>> "$LOG_FILE"
    systemctl start vod-sync-backend 2>> "$LOG_FILE"
    
    # Verificar se serviço está rodando
    sleep 3
    if systemctl is-active --quiet vod-sync-backend; then
        success "Backend configurado e rodando na porta 8000"
    else
        warning "Backend instalado mas não está rodando. Verifique os logs."
        systemctl status vod-sync-backend --no-pager
    fi
}

# Configurar frontend PHP
setup_frontend() {
    print_step "Configurando frontend PHP..."
    
    if [ ! -d "$FRONTEND_DIR" ]; then
        error "Diretório frontend não encontrado: $FRONTEND_DIR"
    fi
    
    # Configurar PHP-FPM
    log "Configurando PHP-FPM..."
    
    # Verificar se PHP-FPM está instalado
    if ! systemctl is-active --quiet php*-fpm 2>/dev/null; then
        # Tentar encontrar e iniciar o serviço PHP-FPM
        for service in php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php-fpm; do
            if systemctl list-unit-files | grep -q $service; then
                systemctl enable $service 2>> "$LOG_FILE"
                systemctl start $service 2>> "$LOG_FILE"
                break
            fi
        done
    fi
    
    # Criar usuário e grupo se não existirem
    if ! id -u www-data >/dev/null 2>&1; then
        useradd -r -s /bin/false www-data 2>> "$LOG_FILE"
    fi
    
    # Configurar permissões
    log "Configurando permissões..."
    chown -R www-data:www-data "$FRONTEND_DIR"
    chmod -R 755 "$FRONTEND_DIR/public"
    
    # Criar diretório de sessões PHP
    mkdir -p /var/lib/php/sessions
    chown -R www-data:www-data /var/lib/php/sessions
    
    # Configurar Nginx
    log "Configurando Nginx..."
    
    # Obter domínio/IP
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    DOMAIN=${SERVER_IP:-localhost}
    
    # Criar configuração Nginx
    cat > /etc/nginx/sites-available/vod-sync << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    root $FRONTEND_DIR/public;
    index index.php index.html index.htm;
    
    # Frontend PHP
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # Backend API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        
        # Tentar diferentes sockets do PHP-FPM
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_pass 127.0.0.1:9000;
        
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Bloquear acesso a arquivos sensíveis
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    location ~ /(config|app|logs|temp)/ {
        deny all;
    }
    
    # Cache para arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }
    
    # Logs
    access_log /var/log/nginx/vod-sync-access.log;
    error_log /var/log/nginx/vod-sync-error.log;
}
EOF
    
    # Remover configuração padrão se existir
    rm -f /etc/nginx/sites-enabled/default
    
    # Ativar site
    ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
    
    # Testar e recarregar Nginx
    nginx -t 2>> "$LOG_FILE" || {
        error "Configuração Nginx inválida"
    }
    
    systemctl restart nginx 2>> "$LOG_FILE" || {
        error "Falha ao reiniciar Nginx"
    }
    
    success "Frontend configurado em http://$DOMAIN"
}

# Configurar agendador
setup_scheduler() {
    print_step "Configurando agendador..."
    
    # Criar script do agendador se não existir
    if [ ! -f "$BACKEND_DIR/app/services/scheduler.py" ]; then
        mkdir -p "$BACKEND_DIR/app/services"
        
        cat > "$BACKEND_DIR/app/services/scheduler.py" << 'EOF'
#!/usr/bin/env python3
"""
Serviço de agendamento do VOD Sync System
"""

import asyncio
import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime
import sys
import os

# Adicionar diretório raiz ao path
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from app.core.config import settings
from app.services.sync_service import SyncService
from app.utils.logger import setup_logger

logger = setup_logger("scheduler")

class SchedulerService:
    def __init__(self):
        self.scheduler = AsyncIOScheduler()
        self.sync_service = SyncService()
        
    async def daily_sync(self):
        """Executa sincronização diária"""
        logger.info("Iniciando sincronização diária agendada")
        try:
            await self.sync_service.sync_all_users()
            logger.info("Sincronização diária concluída")
        except Exception as e:
            logger.error(f"Erro na sincronização diária: {str(e)}")
    
    async def cleanup_logs(self):
        """Limpa logs antigos"""
        logger.info("Limpando logs antigos")
        # Implementar limpeza de logs
        pass
    
    def start(self):
        """Inicia o agendador"""
        
        # Agendar sincronização diária às 2:00 AM
        self.scheduler.add_job(
            self.daily_sync,
            CronTrigger(hour=2, minute=0),
            id='daily_sync',
            name='Sincronização diária',
            replace_existing=True
        )
        
        # Agendar limpeza de logs aos domingos às 3:00 AM
        self.scheduler.add_job(
            self.cleanup_logs,
            CronTrigger(day_of_week='sun', hour=3, minute=0),
            id='log_cleanup',
            name='Limpeza de logs',
            replace_existing=True
        )
        
        self.scheduler.start()
        logger.info("Agendador iniciado")
        
        try:
            # Manter o serviço rodando
            asyncio.get_event_loop().run_forever()
        except (KeyboardInterrupt, SystemExit):
            self.scheduler.shutdown()
            logger.info("Agendador finalizado")

if __name__ == "__main__":
    service = SchedulerService()
    service.start()
EOF
        
        chmod +x "$BACKEND_DIR/app/services/scheduler.py"
    fi
    
    # Criar serviço systemd para o agendador
    cat > /etc/systemd/system/vod-sync-scheduler.service << EOF
[Unit]
Description=VOD Sync System Scheduler
After=network.target vod-sync-backend.service
Requires=vod-sync-backend.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin"
ExecStart=$BACKEND_DIR/venv/bin/python -m app.services.scheduler
Restart=always
RestartSec=10
StandardOutput=append:$BACKEND_DIR/logs/scheduler.log
StandardError=append:$BACKEND_DIR/logs/scheduler-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable vod-sync-scheduler 2>> "$LOG_FILE"
    systemctl start vod-sync-scheduler 2>> "$LOG_FILE"
    
    if systemctl is-active --quiet vod-sync-scheduler; then
        success "Agendador configurado e rodando"
    else
        warning "Agendador instalado mas não está rodando"
    fi
}

# Criar usuário administrador
create_admin_user() {
    print_step "Criando usuário administrador..."
    
    echo ""
    echo "👤 CRIAÇÃO DE USUÁRIO ADMINISTRADOR"
    echo "====================================="
    
    read -p "Usuário administrador [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    read -p "E-mail do administrador [admin@vodsync.local]: " ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-admin@vodsync.local}
    
    read -sp "Senha do administrador: " ADMIN_PASS
    echo
    read -sp "Confirmar senha: " ADMIN_PASS2
    echo
    
    if [ "$ADMIN_PASS" != "$ADMIN_PASS2" ]; then
        error "As senhas não coincidem"
    fi
    
    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS="admin123"
        warning "Usando senha padrão: admin123 - ALTERE IMEDIATAMENTE!"
    fi
    
    # Hash da senha usando Python
    HASHED_PASS=$(python3 -c "
import bcrypt
import sys
password = sys.argv[1].encode('utf-8')
salt = bcrypt.gensalt(rounds=12)
hashed = bcrypt.hashpw(password, salt)
print(hashed.decode('utf-8'))
" "$ADMIN_PASS")
    
    # Atualizar banco de dados
    mysql vod_system << EOF 2>> "$LOG_FILE"
UPDATE users SET 
    username='$ADMIN_USER',
    email='$ADMIN_EMAIL',
    password_hash='$HASHED_PASS',
    updated_at=NOW()
WHERE id=1;
EOF
    
    if [ $? -eq 0 ]; then
        success "Usuário administrador criado: $ADMIN_USER"
        
        # Salvar credenciais
        cat > /root/vod-sync-admin-credentials.txt << EOF
============================================
CREDENCIAIS ADMINISTRATIVAS - VOD SYNC
============================================
URL: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
Usuário: $ADMIN_USER
Senha: $ADMIN_PASS
E-mail: $ADMIN_EMAIL

⚠️ GUARDE ESTAS INFORMAÇÕES EM LOCAL SEGURO!
⚠️ ALTERE A SENHA NO PRIMEIRO ACESSO!
============================================
EOF
        
        log "Credenciais salvas em: /root/vod-sync-admin-credentials.txt"
    else
        error "Falha ao criar usuário administrador"
    fi
}

# Configurar firewall
setup_firewall() {
    print_step "Configurando firewall..."
    
    # Verificar se UFW está disponível
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp 2>> "$LOG_FILE"
        ufw allow 443/tcp 2>> "$LOG_FILE"
        ufw allow 8000/tcp 2>> "$LOG_FILE"
        success "Firewall configurado (portas 80, 443, 8000)"
    fi
}

# Instalação completa
complete_installation() {
    print_header
    
    echo "Este instalador irá configurar o VOD Sync System com:"
    echo ""
    echo "1. ✅ Dependências do sistema (Python, PHP, MySQL, Nginx)"
    echo "2. ✅ Banco de dados MySQL com estrutura completa"
    echo "3. ✅ Backend Python (FastAPI na porta 8000)"
    echo "4. ✅ Frontend PHP (Nginx na porta 80)"
    echo "5. ✅ Agendador automático"
    echo "6. ✅ Usuário administrador"
    echo "7. ✅ Firewall (se UFW disponível)"
    echo ""
    echo "📝 Log da instalação: $LOG_FILE"
    echo ""
    
    read -p "Deseja continuar? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Instalação cancelada."
        exit 0
    fi
    
    # Iniciar log
    echo "============================================" >> "$LOG_FILE"
    echo "INÍCIO DA INSTALAÇÃO: $(date)" >> "$LOG_FILE"
    echo "============================================" >> "$LOG_FILE"
    
    # Executar passos
    check_root
    check_dependencies
    setup_database
    setup_backend
    setup_frontend
    setup_scheduler
    create_admin_user
    setup_firewall
    
    # Finalização
    print_header
    echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo ""
    echo "══════════════════════════════════════════════════════════"
    
    # Obter URL de acesso
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    
    echo "🌐 URL DE ACESSO: http://$SERVER_IP"
    echo "   (ou http://$(hostname -f 2>/dev/null || echo 'localhost'))"
    echo ""
    
    # Mostrar credenciais do admin
    if [ -f "/root/vod-sync-admin-credentials.txt" ]; then
        echo "👤 CREDENCIAIS ADMINISTRATIVAS:"
        echo "   Usuário: $(grep 'Usuário:' /root/vod-sync-admin-credentials.txt | cut -d: -f2)"
        echo "   Senha: [definida durante a instalação]"
        echo ""
        echo "   ⚠️ Credenciais completas salvas em:"
        echo "   /root/vod-sync-admin-credentials.txt"
        echo ""
    fi
    
    echo "🔧 SERVIÇOS INSTALADOS:"
    echo "   vod-sync-backend    (Status: $(systemctl is-active vod-sync-backend))"
    echo "   vod-sync-scheduler  (Status: $(systemctl is-active vod-sync-scheduler))"
    echo "   nginx               (Status: $(systemctl is-active nginx))"
    echo ""
    
    echo "📁 DIRETÓRIOS PRINCIPAIS:"
    echo "   Backend: $BACKEND_DIR"
    echo "   Frontend: $FRONTEND_DIR"
    echo "   Logs: $BACKEND_DIR/logs/"
    echo ""
    
    echo "⚡ COMANDOS ÚTEIS:"
    echo "   sudo systemctl status vod-sync-backend"
    echo "   sudo tail -f $BACKEND_DIR/logs/backend.log"
    echo "   sudo tail -f /var/log/nginx/vod-sync-error.log"
    echo ""
    
    echo "🔧 CONFIGURAÇÃO PÓS-INSTALAÇÃO:"
    echo "   1. Acesse http://$SERVER_IP"
    echo "   2. Faça login com as credenciais acima"
    echo "   3. Configure a conexão com XUI One"
    echo "   4. Adicione sua lista M3U"
    echo "   5. Escaneie e sincronize conteúdos"
    echo ""
    
    echo "📚 DOCUMENTAÇÃO:"
    echo "   Consulte $BASE_DIR/README.md para detalhes"
    echo ""
    
    echo "══════════════════════════════════════════════════════════"
    echo ""
    echo "⏱️ Tempo estimado para configuração inicial: 10-15 minutos"
    echo ""
    echo "❗ IMPORTANTE: Configure sua chave TMDb API para"
    echo "   enriquecimento automático de metadados!"
    echo ""
    
    # Criar arquivo de instalação concluída
    cat > "$BASE_DIR/.installed" << EOF
# VOD Sync System - Instalação Concluída
install_date=$(date '+%Y-%m-%d %H:%M:%S')
version=1.0.0
backend_port=8000
frontend_url=http://$SERVER_IP
admin_user=$(grep 'Usuário:' /root/vod-sync-admin-credentials.txt 2>/dev/null | cut -d: -f2 | xargs)
EOF
    
    success "Arquivo de instalação criado: $BASE_DIR/.installed"
    
    # Log final
    echo "============================================" >> "$LOG_FILE"
    echo "INSTALAÇÃO CONCLUÍDA: $(date)" >> "$LOG_FILE"
    echo "URL: http://$SERVER_IP" >> "$LOG_FILE"
    echo "============================================" >> "$LOG_FILE"
}

# Menu principal
show_menu() {
    while true; do
        print_header
        echo "MENU PRINCIPAL - VOD SYNC SYSTEM"
        echo ""
        echo "Selecione uma opção:"
        echo ""
        echo "1) 📦 Instalação Completa"
        echo "2) 🐍 Apenas Backend Python"
        echo "3) 🌐 Apenas Frontend PHP"
        echo "4) 🗄️ Apenas Banco de Dados"
        echo "5) 🔧 Verificar Sistema"
        echo "6) 🗑️ Desinstalar Tudo"
        echo "7) 📊 Status dos Serviços"
        echo "8) 🚪 Sair"
        echo ""
        read -p "Opção: " choice
        
        case $choice in
            1)
                complete_installation
                ;;
            2)
                check_root
                setup_backend
                ;;
            3)
                check_root
                setup_frontend
                ;;
            4)
                check_root
                setup_database
                ;;
            5)
                check_system
                ;;
            6)
                uninstall_system
                ;;
            7)
                show_status
                ;;
            8)
                echo "Até logo!"
                exit 0
                ;;
            *)
                echo "Opção inválida"
                sleep 2
                ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..." -n 1
    done
}

# Verificar status do sistema
check_system() {
    print_header
    echo "🔍 VERIFICAÇÃO DO SISTEMA"
    echo ""
    
    echo "📦 DEPENDÊNCIAS:"
    for cmd in python3 php mysql nginx pip3; do
        if command -v $cmd &> /dev/null; then
            echo "  ✅ $cmd: $(which $cmd)"
        else
            echo "  ❌ $cmd: NÃO INSTALADO"
        fi
    done
    
    echo ""
    echo "🔧 SERVIÇOS:"
    for service in vod-sync-backend vod-sync-scheduler nginx mysql; do
        if systemctl is-enabled $service 2>/dev/null | grep -q enabled; then
            status="$(systemctl is-active $service 2>/dev/null || echo 'inactive')"
            echo "  $service: $status"
        else
            echo "  $service: NÃO CONFIGURADO"
        fi
    done
    
    echo ""
    echo "🌐 CONEXÕES:"
    echo "  Porta 80 (HTTP): $(netstat -tuln | grep ':80 ' | wc -l) ouvindo"
    echo "  Porta 8000 (API): $(netstat -tuln | grep ':8000 ' | wc -l) ouvindo"
    
    echo ""
    echo "📁 DIRETÓRIOS:"
    for dir in "$BACKEND_DIR" "$FRONTEND_DIR"; do
        if [ -d "$dir" ]; then
            echo "  ✅ $dir"
        else
            echo "  ❌ $dir: NÃO ENCONTRADO"
        fi
    done
}

# Mostrar status dos serviços
show_status() {
    print_header
    echo "📊 STATUS DOS SERVIÇOS"
    echo ""
    
    echo "vod-sync-backend:"
    systemctl status vod-sync-backend --no-pager | head -20
    echo ""
    
    echo "vod-sync-scheduler:"
    systemctl status vod-sync-scheduler --no-pager | head -20
    echo ""
    
    echo "nginx:"
    systemctl status nginx --no-pager | head -20
    echo ""
    
    echo "MySQL:"
    systemctl status mysql --no-pager 2>/dev/null | head -20 || 
    systemctl status mariadb --no-pager 2>/dev/null | head -20
}

# Desinstalar sistema
uninstall_system() {
    print_header
    echo "⚠️  DESINSTALAÇÃO COMPLETA"
    echo ""
    echo "Esta ação irá:"
    echo "1. Parar e remover todos os serviços"
    echo "2. Remover banco de dados (opcional)"
    echo "3. Manter arquivos do sistema (opcional)"
    echo ""
    
    read -p "Tem certeza que deseja continuar? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        return
    fi
    
    # Parar serviços
    log "Parando serviços..."
    systemctl stop vod-sync-backend vod-sync-scheduler 2>/dev/null
    systemctl disable vod-sync-backend vod-sync-scheduler 2>/dev/null
    
    # Remover serviços systemd
    rm -f /etc/systemd/system/vod-sync-*.service
    systemctl daemon-reload
    
    # Remover configuração Nginx
    rm -f /etc/nginx/sites-available/vod-sync
    rm -f /etc/nginx/sites-enabled/vod-sync
    systemctl reload nginx 2>/dev/null
    
    # Perguntar sobre banco de dados
    read -p "Remover banco de dados também? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log "Removendo banco de dados..."
        mysql -e "DROP DATABASE IF EXISTS vod_system;"
        mysql -e "DROP USER IF EXISTS 'vodsync_user'@'localhost';"
        success "Banco de dados removido"
    fi
    
    # Perguntar sobre arquivos
    read -p "Manter arquivos do sistema em $BASE_DIR? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        log "Removendo arquivos do sistema..."
        rm -rf "$BACKEND_DIR" "$FRONTEND_DIR" "$INSTALL_DIR"
        success "Arquivos removidos"
    fi
    
    # Remover arquivos de credenciais
    rm -f /root/vod-sync-*.txt
    rm -f "$BASE_DIR/.installed"
    
    success "Sistema desinstalado com sucesso"
}

# Script principal
main() {
    # Verificar argumentos
    if [ "$1" = "--auto" ]; then
        complete_installation
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Uso: $0 [OPÇÃO]"
        echo ""
        echo "Opções:"
        echo "  --auto      Instalação automática não interativa"
        echo "  --help      Mostra esta ajuda"
        echo "  --status    Mostra status dos serviços"
        echo ""
        echo "Sem opções: Menu interativo"
        exit 0
    elif [ "$1" = "--status" ]; then
        show_status
        exit 0
    else
        show_menu
    fi
}

# Executar
main "$@"
