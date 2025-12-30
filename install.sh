#!/bin/bash

# ============================================
# INSTALADOR DO SISTEMA VOD SYNC
# Versão: 2.0
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
PROJECT_NAME="vod_sync_system"
BACKEND_DIR="backend"
FRONTEND_DIR="frontend"
INSTALL_DIR="/opt/${PROJECT_NAME}"
LOG_FILE="/tmp/vod_system_install.log"

# Funções de utilidade
print_header() {
    echo -e "${BLUE}"
    echo "========================================="
    echo "  INSTALADOR SISTEMA VOD SYNC"
    echo "========================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_requirements() {
    print_step "Verificando requisitos do sistema..."
    
    # Verificar se é root
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script precisa ser executado como root!"
        exit 1
    fi
    
    # Verificar sistema operacional
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Não foi possível detectar o sistema operacional"
        exit 1
    fi
    
    print_success "Sistema detectado: $OS $VER"
}

install_dependencies() {
    print_step "Instalando dependências do sistema..."
    
    # Ubuntu/Debian
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        apt-get update >> $LOG_FILE 2>&1
        apt-get install -y \
            python3.10 \
            python3.10-venv \
            python3-pip \
            python3-dev \
            mysql-server \
            mariadb-client \
            php \
            php-mysql \
            php-curl \
            php-json \
            php-mbstring \
            apache2 \
            libapache2-mod-php \
            git \
            curl \
            wget \
            nano \
            htop \
            unzip \
            cron \
            screen >> $LOG_FILE 2>&1
            
    # CentOS/RHEL/Fedora
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]] || [[ "$OS" == *"Fedora"* ]]; then
        yum update -y >> $LOG_FILE 2>&1
        yum install -y \
            python3.10 \
            python3-pip \
            mariadb-server \
            mariadb-client \
            php \
            php-mysqlnd \
            php-curl \
            php-json \
            php-mbstring \
            httpd \
            git \
            curl \
            wget \
            nano \
            htop \
            unzip \
            cronie \
            screen >> $LOG_FILE 2>&1
    else
        print_warning "Sistema não suportado oficialmente. Continuando com instalação básica..."
    fi
    
    print_success "Dependências instaladas"
}

create_directories() {
    print_step "Criando estrutura de diretórios..."
    
    # Diretório principal
    mkdir -p $INSTALL_DIR
    mkdir -p $INSTALL_DIR/logs
    mkdir -p $INSTALL_DIR/backups
    mkdir -p $INSTALL_DIR/config
    
    # Estrutura do backend
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/controllers
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/services
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/database
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/models
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/routes
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/utils
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/middleware
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/app/schemas
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/tests
    mkdir -p $INSTALL_DIR/$BACKEND_DIR/migrations
    
    # Estrutura do frontend
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/public/assets
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/public/css
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/public/js
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/public/images
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/app/controllers
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/app/models
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/app/views
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/app/helpers
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/config
    mkdir -p $INSTALL_DIR/$FRONTEND_DIR/vendor
    
    print_success "Estrutura de diretórios criada"
}

setup_database() {
    print_step "Configurando banco de dados..."
    
    # Iniciar MySQL/MariaDB
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        systemctl start mysql >> $LOG_FILE 2>&1
        systemctl enable mysql >> $LOG_FILE 2>&1
    else
        systemctl start mariadb >> $LOG_FILE 2>&1
        systemctl enable mariadb >> $LOG_FILE 2>&1
    fi
    
    # Configurar root password (altere conforme necessário)
    ROOT_PASS="VodSync@2024"
    
    # Comandos SQL para configuração segura
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';" >> $LOG_FILE 2>&1
    mysql -e "DELETE FROM mysql.user WHERE User='';" >> $LOG_FILE 2>&1
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" >> $LOG_FILE 2>&1
    mysql -e "DROP DATABASE IF EXISTS test;" >> $LOG_FILE 2>&1
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> $LOG_FILE 2>&1
    mysql -e "FLUSH PRIVILEGES;" >> $LOG_FILE 2>&1
    
    # Criar banco de dados do sistema
    DB_NAME="vod_sync_db"
    DB_USER="vod_sync_user"
    DB_PASS="SyncVod@2024"
    
    mysql -u root -p${ROOT_PASS} <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mysql.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Salvar credenciais em arquivo seguro
    cat > $INSTALL_DIR/config/db_credentials.cnf <<EOF
[client]
user=${DB_USER}
password=${DB_PASS}
host=localhost
database=${DB_NAME}
EOF
    
    chmod 600 $INSTALL_DIR/config/db_credentials.cnf
    
    print_success "Banco de dados configurado"
}

create_database_schema() {
    print_step "Criando schema do banco de dados..."
    
    # Arquivo SQL com todas as tabelas
    SQL_FILE="$INSTALL_DIR/config/database_schema.sql"
    
    cat > $SQL_FILE <<'EOF'
-- ============================================
-- SCHEMA DO SISTEMA VOD SYNC
-- ============================================

-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    user_level ENUM('admin', 'reseller', 'user') DEFAULT 'user',
    parent_id INT NULL,
    license_key VARCHAR(100) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    max_clients INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    FOREIGN KEY (parent_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de licenças
CREATE TABLE IF NOT EXISTS licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_key VARCHAR(100) UNIQUE NOT NULL,
    user_id INT NULL,
    product_name VARCHAR(50) DEFAULT 'VOD Sync System',
    license_type ENUM('trial', 'monthly', 'yearly', 'lifetime') DEFAULT 'trial',
    status ENUM('active', 'expired', 'suspended', 'cancelled') DEFAULT 'active',
    max_connections INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMP NULL,
    expires_at TIMESTAMP NULL,
    last_check TIMESTAMP NULL,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de configurações do XUI
CREATE TABLE IF NOT EXISTS xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    connection_name VARCHAR(50) DEFAULT 'Primary XUI',
    host VARCHAR(100) NOT NULL,
    port INT DEFAULT 3306,
    db_name VARCHAR(50) DEFAULT 'xui',
    db_user VARCHAR(50) NOT NULL,
    db_password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_test TIMESTAMP NULL,
    test_status ENUM('success', 'failed', 'pending') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de listas M3U
CREATE TABLE IF NOT EXISTS m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    list_name VARCHAR(100) NOT NULL,
    m3u_content LONGTEXT NOT NULL,
    total_channels INT DEFAULT 0,
    total_movies INT DEFAULT 0,
    total_series INT DEFAULT 0,
    parsed_categories JSON,
    is_active BOOLEAN DEFAULT TRUE,
    last_parsed TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de agendamentos
CREATE TABLE IF NOT EXISTS schedules (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    schedule_type ENUM('daily', 'weekly', 'custom') DEFAULT 'daily',
    schedule_time TIME DEFAULT '02:00:00',
    is_active BOOLEAN DEFAULT TRUE,
    last_run TIMESTAMP NULL,
    next_run TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de logs de sincronização
CREATE TABLE IF NOT EXISTS sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    log_type ENUM('info', 'warning', 'error', 'success') DEFAULT 'info',
    operation ENUM('scan', 'sync_movies', 'sync_series', 'full_sync', 'test') NOT NULL,
    items_total INT DEFAULT 0,
    items_processed INT DEFAULT 0,
    items_added INT DEFAULT 0,
    items_updated INT DEFAULT 0,
    items_failed INT DEFAULT 0,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    duration_seconds INT DEFAULT 0,
    details JSON,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de configurações do sistema
CREATE TABLE IF NOT EXISTS system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(50) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_group VARCHAR(30) DEFAULT 'general',
    is_encrypted BOOLEAN DEFAULT FALSE,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de categorias de conteúdo
CREATE TABLE IF NOT EXISTS content_categories (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    content_type ENUM('movie', 'series') NOT NULL,
    is_selected BOOLEAN DEFAULT TRUE,
    tmdb_genre_id INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_user_category (user_id, category_name, content_type),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de cache TMDb
CREATE TABLE IF NOT EXISTS tmdb_cache (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tmdb_id INT NOT NULL,
    content_type ENUM('movie', 'tv') NOT NULL,
    language VARCHAR(10) DEFAULT 'pt-BR',
    data JSON NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    UNIQUE KEY unique_tmdb_content (tmdb_id, content_type, language)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de atividades do usuário
CREATE TABLE IF NOT EXISTS user_activity (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    activity_type VARCHAR(50) NOT NULL,
    description TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Índices para performance
CREATE INDEX idx_users_parent_id ON users(parent_id);
CREATE INDEX idx_users_user_level ON users(user_level);
CREATE INDEX idx_licenses_status ON licenses(status);
CREATE INDEX idx_licenses_expires ON licenses(expires_at);
CREATE INDEX idx_xui_connections_user ON xui_connections(user_id);
CREATE INDEX idx_m3u_lists_user ON m3u_lists(user_id);
CREATE INDEX idx_sync_logs_user_time ON sync_logs(user_id, start_time);
CREATE INDEX idx_sync_logs_operation ON sync_logs(operation);
CREATE INDEX idx_tmdb_cache_expires ON tmdb_cache(expires_at);
CREATE INDEX idx_user_activity_user_time ON user_activity(user_id, created_at);

-- Inserir configurações padrão
INSERT INTO system_settings (setting_key, setting_value, setting_group, description) VALUES
('tmdb_api_key', '', 'api', 'Chave da API do TMDb'),
('tmdb_language', 'pt-BR', 'api', 'Idioma padrão para conteúdo'),
('system_name', 'VOD Sync System', 'general', 'Nome do sistema'),
('system_version', '2.0.0', 'general', 'Versão do sistema'),
('default_user_max_clients', '10', 'users', 'Máximo de clientes por usuário padrão'),
('default_reseller_max_clients', '50', 'users', 'Máximo de clientes por revendedor'),
('sync_retry_attempts', '3', 'sync', 'Tentativas de retry na sincronização'),
('sync_timeout_seconds', '300', 'sync', 'Timeout da sincronização em segundos'),
('log_retention_days', '30', 'logs', 'Dias para retenção de logs'),
('license_check_interval', '24', 'license', 'Intervalo de verificação de licença em horas');

-- Criar usuário admin padrão (senha: Admin@123)
INSERT INTO users (username, email, password_hash, full_name, user_level, is_active, max_clients) VALUES
('admin', 'admin@vodsync.com', '$2b$12$V9q7r7b6U3W2p6p9Z8YQZ.B6p8vN9sP2rT8p6vQ9rS7tU2vW3xYzA', 'Administrador do Sistema', 'admin', TRUE, 999999);

-- Criar licença padrão para admin
INSERT INTO licenses (license_key, user_id, license_type, status, max_connections, activated_at, expires_at) VALUES
('VODSYS-ADMIN-001', 1, 'lifetime', 'active', 999999, NOW(), DATE_ADD(NOW(), INTERVAL 100 YEAR));

-- Inserir configuração XUI padrão
INSERT INTO xui_connections (user_id, connection_name, host, port, db_name, db_user, db_password) VALUES
(1, 'Servidor Principal', 'localhost', 3306, 'xui', 'root', '');

-- Inserir agendamento padrão
INSERT INTO schedules (user_id, schedule_type, schedule_time, is_active) VALUES
(1, 'daily', '02:00:00', TRUE);
EOF
    
    # Executar schema
    mysql -u root -p${ROOT_PASS} $DB_NAME < $SQL_FILE >> $LOG_FILE 2>&1
    
    print_success "Schema do banco de dados criado"
}

setup_backend() {
    print_step "Configurando backend Python..."
    
    # Criar ambiente virtual Python
    cd $INSTALL_DIR/$BACKEND_DIR
    python3.10 -m venv venv >> $LOG_FILE 2>&1
    
    # Arquivo requirements.txt
    cat > requirements.txt <<'EOF'
# FastAPI e dependências principais
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0

# Banco de dados
sqlalchemy==2.0.23
pymysql==1.1.0
alembic==1.13.1
mysqlclient==2.2.4

# Autenticação e segurança
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
cryptography==41.0.7
pyjwt==2.8.0

# Agendamento
apscheduler==3.10.4
schedule==1.2.0

# Parsing e requisições
requests==2.31.0
beautifulsoup4==4.12.2
lxml==4.9.3
m3u8==4.1.0

# Cache e performance
redis==5.0.1
pymemcache==4.0.0

# Utilitários
python-dotenv==1.0.0
python-dateutil==2.8.2
pytz==2023.3
tzlocal==5.2

# Logging
loguru==0.7.2
structlog==23.2.0

# Validação
email-validator==2.1.0
phonenumbers==8.13.27

# Testes
pytest==7.4.3
pytest-asyncio==0.21.1
httpx==0.25.2

# Monitoramento
psutil==5.9.7
prometheus-client==0.19.0

# CLI
click==8.1.7
rich==13.7.0

# Outros
pyyaml==6.0.1
jsonpickle==3.0.2
EOF
    
    # Ativar venv e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip >> $LOG_FILE 2>&1
    pip install -r requirements.txt >> $LOG_FILE 2>&1
    
    # Criar arquivos principais do backend
    create_backend_files
    
    print_success "Backend Python configurado"
}

create_backend_files() {
    print_step "Criando arquivos do backend..."
    
    # Arquivo main.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/main.py <<'EOF'
"""
VOD Sync System - Backend Main Application
FastAPI application with all routes and configurations
"""

import os
import logging
from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager

from app.database.mysql import engine, Base, SessionLocal
from app.routes import (
    auth_routes,
    user_routes,
    license_routes,
    xui_routes,
    m3u_routes,
    sync_routes,
    settings_routes,
    dashboard_routes
)
from app.middleware.auth_middleware import AuthMiddleware
from app.middleware.license_middleware import LicenseMiddleware
from app.services.scheduler import init_scheduler, shutdown_scheduler
from app.utils.logger import setup_logging
from app.config import settings

# Setup logging
logger = setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan events for startup and shutdown"""
    # Startup
    logger.info("Starting VOD Sync System...")
    
    # Create database tables
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created/verified")
    except Exception as e:
        logger.error(f"Database initialization error: {e}")
    
    # Initialize scheduler
    scheduler = init_scheduler()
    app.state.scheduler = scheduler
    
    yield
    
    # Shutdown
    logger.info("Shutting down VOD Sync System...")
    shutdown_scheduler(scheduler)

# Create FastAPI app
app = FastAPI(
    title="VOD Sync System API",
    description="API for syncing VOD content from M3U lists to XUI One",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/api/docs" if settings.DEBUG else None,
    redoc_url="/api/redoc" if settings.DEBUG else None
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Trusted hosts middleware
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.ALLOWED_HOSTS
)

# Custom middlewares
app.add_middleware(AuthMiddleware)
app.add_middleware(LicenseMiddleware)

# Include routers
app.include_router(auth_routes.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(user_routes.router, prefix="/api/users", tags=["Users"])
app.include_router(license_routes.router, prefix="/api/licenses", tags=["Licenses"])
app.include_router(xui_routes.router, prefix="/api/xui", tags=["XUI"])
app.include_router(m3u_routes.router, prefix="/api/m3u", tags=["M3U"])
app.include_router(sync_routes.router, prefix="/api/sync", tags=["Sync"])
app.include_router(settings_routes.router, prefix="/api/settings", tags=["Settings"])
app.include_router(dashboard_routes.router, prefix="/api/dashboard", tags=["Dashboard"])

# Error handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "status": "error"}
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "status": "error"}
    )

# Health check endpoint
@app.get("/api/health", tags=["Health"])
async def health_check():
    return {
        "status": "healthy",
        "service": "vod_sync_system",
        "version": "2.0.0"
    }

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "VOD Sync System API",
        "version": "2.0.0",
        "docs": "/api/docs",
        "health": "/api/health"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info"
    )
EOF

    # Arquivo .env
    cat > $INSTALL_DIR/$BACKEND_DIR/.env <<EOF
# ============================================
# VOD Sync System - Environment Variables
# ============================================

# Application
APP_NAME=VOD Sync System
APP_VERSION=2.0.0
DEBUG=True
HOST=0.0.0.0
PORT=8000

# Security
SECRET_KEY=your-super-secret-key-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440
ENCRYPTION_KEY=your-encryption-key-32-chars

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync_db
DB_USER=vod_sync_user
DB_PASS=SyncVod@2024
DB_CHARSET=utf8mb4

# XUI Database (Default)
XUI_DB_HOST=localhost
XUI_DB_PORT=3306
XUI_DB_NAME=xui
XUI_DB_USER=root
XUI_DB_PASS=

# TMDb API
TMDB_API_KEY=your_tmdb_api_key_here
TMDB_LANGUAGE=pt-BR
TMDB_TIMEOUT=30
TMDB_CACHE_HOURS=24

# Redis (Optional)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASS=
REDIS_DB=0

# CORS
ALLOWED_ORIGINS=["http://localhost", "http://localhost:8080", "http://your-domain.com"]
ALLOWED_HOSTS=["localhost", "your-domain.com", "127.0.0.1"]

# File Uploads
MAX_UPLOAD_SIZE=10485760  # 10MB
ALLOWED_EXTENSIONS=.m3u,.txt,.json

# Scheduler
SCHEDULER_TIMEZONE=America/Sao_Paulo
SYNC_HOUR=2
SYNC_MINUTE=0

# Logging
LOG_LEVEL=INFO
LOG_FILE=/opt/vod_sync_system/logs/backend.log
LOG_RETENTION_DAYS=30

# License
LICENSE_VALIDATION_URL=https://license.vodsync.com/api/validate
LICENSE_CHECK_INTERVAL=24
EOF

    # Arquivo config.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/config.py <<'EOF'
"""
Configuration settings for the VOD Sync System
"""

import os
from typing import List, Optional
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

load_dotenv()

class Settings(BaseSettings):
    # Application
    APP_NAME: str = os.getenv("APP_NAME", "VOD Sync System")
    APP_VERSION: str = os.getenv("APP_VERSION", "2.0.0")
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", 8000))
    
    # Security
    SECRET_KEY: str = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")
    ALGORITHM: str = os.getenv("ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 1440))
    ENCRYPTION_KEY: str = os.getenv("ENCRYPTION_KEY", "your-encryption-key-32-chars")
    
    # Database
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", 3306))
    DB_NAME: str = os.getenv("DB_NAME", "vod_sync_db")
    DB_USER: str = os.getenv("DB_USER", "vod_sync_user")
    DB_PASS: str = os.getenv("DB_PASS", "SyncVod@2024")
    DB_CHARSET: str = os.getenv("DB_CHARSET", "utf8mb4")
    
    # XUI Database
    XUI_DB_HOST: str = os.getenv("XUI_DB_HOST", "localhost")
    XUI_DB_PORT: int = int(os.getenv("XUI_DB_PORT", 3306))
    XUI_DB_NAME: str = os.getenv("XUI_DB_NAME", "xui")
    XUI_DB_USER: str = os.getenv("XUI_DB_USER", "root")
    XUI_DB_PASS: str = os.getenv("XUI_DB_PASS", "")
    
    # TMDb API
    TMDB_API_KEY: str = os.getenv("TMDB_API_KEY", "")
    TMDB_LANGUAGE: str = os.getenv("TMDB_LANGUAGE", "pt-BR")
    TMDB_TIMEOUT: int = int(os.getenv("TMDB_TIMEOUT", 30))
    TMDB_CACHE_HOURS: int = int(os.getenv("TMDB_CACHE_HOURS", 24))
    
    # Redis
    REDIS_HOST: Optional[str] = os.getenv("REDIS_HOST")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", 6379))
    REDIS_PASS: Optional[str] = os.getenv("REDIS_PASS")
    REDIS_DB: int = int(os.getenv("REDIS_DB", 0))
    
    # CORS
    ALLOWED_ORIGINS: List[str] = eval(os.getenv("ALLOWED_ORIGINS", '["http://localhost:3000"]'))
    ALLOWED_HOSTS: List[str] = eval(os.getenv("ALLOWED_HOSTS", '["localhost", "127.0.0.1"]'))
    
    # File Uploads
    MAX_UPLOAD_SIZE: int = int(os.getenv("MAX_UPLOAD_SIZE", 10485760))
    ALLOWED_EXTENSIONS: List[str] = os.getenv("ALLOWED_EXTENSIONS", ".m3u,.txt,.json").split(",")
    
    # Scheduler
    SCHEDULER_TIMEZONE: str = os.getenv("SCHEDULER_TIMEZONE", "America/Sao_Paulo")
    SYNC_HOUR: int = int(os.getenv("SYNC_HOUR", 2))
    SYNC_MINUTE: int = int(os.getenv("SYNC_MINUTE", 0))
    
    # Logging
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_FILE: str = os.getenv("LOG_FILE", "/opt/vod_sync_system/logs/backend.log")
    LOG_RETENTION_DAYS: int = int(os.getenv("LOG_RETENTION_DAYS", 30))
    
    # License
    LICENSE_VALIDATION_URL: str = os.getenv("LICENSE_VALIDATION_URL", "https://license.vodsync.com/api/validate")
    LICENSE_CHECK_INTERVAL: int = int(os.getenv("LICENSE_CHECK_INTERVAL", 24))
    
    # File paths
    BASE_DIR: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    LOGS_DIR: str = os.path.join(os.path.dirname(BASE_DIR), "logs")
    CONFIG_DIR: str = os.path.join(os.path.dirname(BASE_DIR), "config")
    
    @property
    def DATABASE_URL(self) -> str:
        return f"mysql+pymysql://{self.DB_USER}:{self.DB_PASS}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}?charset={self.DB_CHARSET}"
    
    @property
    def XUI_DATABASE_URL(self) -> str:
        return f"mysql+pymysql://{self.XUI_DB_USER}:{self.XUI_DB_PASS}@{self.XUI_DB_HOST}:{self.XUI_DB_PORT}/{self.XUI_DB_NAME}?charset={self.DB_CHARSET}"
    
    @property
    def USE_REDIS(self) -> bool:
        return bool(self.REDIS_HOST)

settings = Settings()
EOF

    # Criar outros arquivos essenciais
    create_essential_backend_files
    
    print_success "Arquivos do backend criados"
}

create_essential_backend_files() {
    # services/m3u_parser.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/services/m3u_parser.py <<'EOF'
"""
M3U Parser Service
Handles parsing of M3U playlists and extracting VOD content
"""

import re
import logging
from typing import Dict, List, Tuple, Optional
from urllib.parse import urlparse, parse_qs
import m3u8

logger = logging.getLogger(__name__)

class M3UParser:
    """Parser for M3U playlists"""
    
    def __init__(self):
        self.extinf_pattern = re.compile(r'#EXTINF:(-?\d+)\s*(?:.*?)?,(.+)')
        self.attribute_pattern = re.compile(r'([a-zA-Z-]+)=\"([^\"]*)\"')
        
    def parse_m3u_content(self, m3u_content: str) -> Dict:
        """
        Parse M3U content and extract channels, movies, and series
        
        Returns:
            Dict with parsed content
        """
        lines = m3u_content.strip().split('\n')
        content = {
            'channels': [],
            'movies': [],
            'series': [],
            'categories': set(),
            'total_items': 0
        }
        
        current_item = {}
        in_item = False
        
        for line in lines:
            line = line.strip()
            
            if line.startswith('#EXTM3U'):
                continue
                
            elif line.startswith('#EXTINF:'):
                # Parse EXTINF line
                match = self.extinf_pattern.match(line)
                if match:
                    duration, title = match.groups()
                    current_item = {
                        'duration': int(duration) if duration else 0,
                        'title': title.strip(),
                        'attributes': {},
                        'type': 'channel'  # default
                    }
                    
                    # Parse attributes
                    attrs = self.attribute_pattern.findall(line)
                    for key, value in attrs:
                        current_item['attributes'][key.lower()] = value
                        
                        # Determine content type
                        if 'tvg-name' in current_item['attributes']:
                            tvg_name = current_item['attributes']['tvg-name'].lower()
                            if 'movie' in tvg_name or current_item['duration'] > 3600:
                                current_item['type'] = 'movie'
                            elif 'serie' in tvg_name or 'series' in tvg_name:
                                current_item['type'] = 'series'
                        
                        # Extract category
                        if 'group-title' in current_item['attributes']:
                            category = current_item['attributes']['group-title']
                            content['categories'].add(category)
                            current_item['category'] = category
                    
                    in_item = True
                    
            elif line and not line.startswith('#') and in_item:
                # This is the URL for the current item
                current_item['url'] = line
                
                # Categorize content
                if current_item['type'] == 'movie':
                    content['movies'].append(current_item.copy())
                elif current_item['type'] == 'series':
                    content['series'].append(current_item.copy())
                else:
                    content['channels'].append(current_item.copy())
                
                content['total_items'] += 1
                in_item = False
        
        # Convert categories to list
        content['categories'] = list(content['categories'])
        
        logger.info(f"Parsed M3U: {content['total_items']} total items")
        logger.info(f"Found: {len(content['movies'])} movies, {len(content['series'])} series")
        logger.info(f"Categories: {len(content['categories'])} categories")
        
        return content
    
    def extract_movie_info(self, item: Dict) -> Dict:
        """Extract movie information from M3U item"""
        title = item['title']
        attributes = item.get('attributes', {})
        
        # Try to extract year from title
        year_match = re.search(r'\((\d{4})\)', title)
        year = int(year_match.group(1)) if year_match else None
        
        # Clean title
        clean_title = re.sub(r'\([^)]*\)', '', title).strip()
        
        movie_info = {
            'original_title': title,
            'clean_title': clean_title,
            'year': year,
            'category': attributes.get('group-title', 'Unknown'),
            'duration': item.get('duration', 0),
            'url': item.get('url', ''),
            'attributes': attributes
        }
        
        return movie_info
    
    def extract_series_info(self, item: Dict) -> Dict:
        """Extract series information from M3U item"""
        title = item['title']
        attributes = item.get('attributes', {})
        
        # Try to extract season and episode
        season_episode = None
        season_match = re.search(r'[Ss](\d{1,2})', title)
        episode_match = re.search(r'[Ee](\d{1,3})', title)
        
        if season_match and episode_match:
            season_episode = {
                'season': int(season_match.group(1)),
                'episode': int(episode_match.group(1))
            }
        
        # Clean title (remove season/episode info)
        clean_title = re.sub(r'[Ss]\d{1,2}[Ee]\d{1,3}', '', title)
        clean_title = re.sub(r'\(\d{4}\)', '', clean_title).strip()
        
        series_info = {
            'original_title': title,
            'clean_title': clean_title,
            'season_episode': season_episode,
            'category': attributes.get('group-title', 'Unknown'),
            'url': item.get('url', ''),
            'attributes': attributes
        }
        
        return series_info
    
    def categorize_content(self, content: Dict) -> Dict:
        """Categorize content by type and category"""
        categorized = {
            'movies_by_category': {},
            'series_by_category': {}
        }
        
        # Categorize movies
        for movie in content['movies']:
            category = movie.get('category', 'Unknown')
            if category not in categorized['movies_by_category']:
                categorized['movies_by_category'][category] = []
            categorized['movies_by_category'][category].append(movie)
        
        # Categorize series
        for series in content['series']:
            category = series.get('category', 'Unknown')
            if category not in categorized['series_by_category']:
                categorized['series_by_category'][category] = []
            categorized['series_by_category'][category].append(series)
        
        return categorized
EOF

    # services/tmdb_service.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/services/tmdb_service.py <<'EOF'
"""
TMDb Service for fetching movie and series metadata
"""

import requests
import logging
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import hashlib
import json

from app.database.mysql import SessionLocal
from app.models.tmdb_cache import TMDB_Cache

logger = logging.getLogger(__name__)

class TMDBService:
    """Service for interacting with TMDb API"""
    
    def __init__(self, api_key: str, language: str = 'pt-BR'):
        self.api_key = api_key
        self.language = language
        self.base_url = "https://api.themoviedb.org/3"
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json;charset=utf-8'
        })
    
    def search_movie(self, query: str, year: Optional[int] = None) -> Optional[Dict]:
        """Search for a movie on TMDb"""
        cache_key = f"movie_search:{hashlib.md5(f'{query}:{year}'.encode()).hexdigest()}"
        cached = self._get_from_cache(cache_key)
        if cached:
            return cached
        
        params = {
            'query': query,
            'language': self.language,
            'page': 1
        }
        if year:
            params['year'] = year
        
        try:
            response = self.session.get(
                f"{self.base_url}/search/movie",
                params=params,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            if data['results']:
                movie_id = data['results'][0]['id']
                movie_details = self.get_movie_details(movie_id)
                
                # Cache for 24 hours
                self._save_to_cache(cache_key, movie_details, hours=24)
                return movie_details
                
        except Exception as e:
            logger.error(f"Error searching movie '{query}': {e}")
        
        return None
    
    def search_tv_series(self, query: str, year: Optional[int] = None) -> Optional[Dict]:
        """Search for a TV series on TMDb"""
        cache_key = f"tv_search:{hashlib.md5(f'{query}:{year}'.encode()).hexdigest()}"
        cached = self._get_from_cache(cache_key)
        if cached:
            return cached
        
        params = {
            'query': query,
            'language': self.language,
            'page': 1
        }
        if year:
            params['first_air_date_year'] = year
        
        try:
            response = self.session.get(
                f"{self.base_url}/search/tv",
                params=params,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            if data['results']:
                tv_id = data['results'][0]['id']
                tv_details = self.get_tv_details(tv_id)
                
                # Cache for 24 hours
                self._save_to_cache(cache_key, tv_details, hours=24)
                return tv_details
                
        except Exception as e:
            logger.error(f"Error searching TV series '{query}': {e}")
        
        return None
    
    def get_movie_details(self, movie_id: int) -> Dict:
        """Get detailed movie information"""
        cache_key = f"movie:{movie_id}:{self.language}"
        cached = self._get_from_cache(cache_key)
        if cached:
            return cached
        
        try:
            # Get movie details
            response = self.session.get(
                f"{self.base_url}/movie/{movie_id}",
                params={
                    'language': self.language,
                    'append_to_response': 'credits,videos,images'
                },
                timeout=10
            )
            response.raise_for_status()
            movie_data = response.json()
            
            # Format movie data
            formatted_movie = {
                'tmdb_id': movie_id,
                'title': movie_data.get('title', ''),
                'original_title': movie_data.get('original_title', ''),
                'overview': movie_data.get('overview', ''),
                'release_date': movie_data.get('release_date', ''),
                'year': movie_data.get('release_date', '')[:4] if movie_data.get('release_date') else None,
                'runtime': movie_data.get('runtime', 0),
                'genres': [genre['name'] for genre in movie_data.get('genres', [])],
                'vote_average': movie_data.get('vote_average', 0),
                'vote_count': movie_data.get('vote_count', 0),
                'poster_path': f"https://image.tmdb.org/t/p/w500{movie_data.get('poster_path', '')}" if movie_data.get('poster_path') else None,
                'backdrop_path': f"https://image.tmdb.org/t/p/original{movie_data.get('backdrop_path', '')}" if movie_data.get('backdrop_path') else None,
                'imdb_id': movie_data.get('imdb_id'),
                'cast': [],
                'directors': [],
                'trailers': []
            }
            
            # Extract cast (first 10)
            credits = movie_data.get('credits', {})
            if credits:
                formatted_movie['cast'] = [
                    {
                        'name': actor.get('name'),
                        'character': actor.get('character'),
                        'profile_path': f"https://image.tmdb.org/t/p/w185{actor.get('profile_path')}" if actor.get('profile_path') else None
                    }
                    for actor in credits.get('cast', [])[:10]
                ]
                
                # Extract directors
                formatted_movie['directors'] = [
                    crew.get('name')
                    for crew in credits.get('crew', [])
                    if crew.get('job') == 'Director'
                ]
            
            # Extract trailers
            videos = movie_data.get('videos', {}).get('results', [])
            formatted_movie['trailers'] = [
                {
                    'key': video.get('key'),
                    'name': video.get('name'),
                    'site': video.get('site'),
                    'type': video.get('type')
                }
                for video in videos
                if video.get('site') == 'YouTube' and video.get('type') in ['Trailer', 'Teaser']
            ]
            
            # Cache for 30 days
            self._save_to_cache(cache_key, formatted_movie, hours=720)
            return formatted_movie
            
        except Exception as e:
            logger.error(f"Error getting movie details {movie_id}: {e}")
            return {}
    
    def get_tv_details(self, tv_id: int) -> Dict:
        """Get detailed TV series information"""
        cache_key = f"tv:{tv_id}:{self.language}"
        cached = self._get_from_cache(cache_key)
        if cached:
            return cached
        
        try:
            # Get TV details
            response = self.session.get(
                f"{self.base_url}/tv/{tv_id}",
                params={
                    'language': self.language,
                    'append_to_response': 'credits,videos,images,content_ratings'
                },
                timeout=10
            )
            response.raise_for_status()
            tv_data = response.json()
            
            # Format TV data
            formatted_tv = {
                'tmdb_id': tv_id,
                'name': tv_data.get('name', ''),
                'original_name': tv_data.get('original_name', ''),
                'overview': tv_data.get('overview', ''),
                'first_air_date': tv_data.get('first_air_date', ''),
                'last_air_date': tv_data.get('last_air_date', ''),
                'year': tv_data.get('first_air_date', '')[:4] if tv_data.get('first_air_date') else None,
                'number_of_seasons': tv_data.get('number_of_seasons', 0),
                'number_of_episodes': tv_data.get('number_of_episodes', 0),
                'episode_run_time': tv_data.get('episode_run_time', [0])[0] if tv_data.get('episode_run_time') else 0,
                'genres': [genre['name'] for genre in tv_data.get('genres', [])],
                'vote_average': tv_data.get('vote_average', 0),
                'vote_count': tv_data.get('vote_count', 0),
                'poster_path': f"https://image.tmdb.org/t/p/w500{tv_data.get('poster_path', '')}" if tv_data.get('poster_path') else None,
                'backdrop_path': f"https://image.tmdb.org/t/p/original{tv_data.get('backdrop_path', '')}" if tv_data.get('backdrop_path') else None,
                'status': tv_data.get('status', ''),
                'cast': [],
                'creators': [],
                'trailers': [],
                'seasons': []
            }
            
            # Extract cast (first 10)
            credits = tv_data.get('credits', {})
            if credits:
                formatted_tv['cast'] = [
                    {
                        'name': actor.get('name'),
                        'character': actor.get('character'),
                        'profile_path': f"https://image.tmdb.org/t/p/w185{actor.get('profile_path')}" if actor.get('profile_path') else None
                    }
                    for actor in credits.get('cast', [])[:10]
                ]
                
                # Extract creators
                formatted_tv['creators'] = [
                    creator.get('name')
                    for creator in tv_data.get('created_by', [])
                ]
            
            # Extract trailers
            videos = tv_data.get('videos', {}).get('results', [])
            formatted_tv['trailers'] = [
                {
                    'key': video.get('key'),
                    'name': video.get('name'),
                    'site': video.get('site'),
                    'type': video.get('type')
                }
                for video in videos
                if video.get('site') == 'YouTube' and video.get('type') in ['Trailer', 'Teaser']
            ]
            
            # Extract seasons
            seasons = tv_data.get('seasons', [])
            formatted_tv['seasons'] = [
                {
                    'season_number': season.get('season_number'),
                    'name': season.get('name'),
                    'overview': season.get('overview'),
                    'episode_count': season.get('episode_count'),
                    'poster_path': f"https://image.tmdb.org/t/p/w500{season.get('poster_path')}" if season.get('poster_path') else None,
                    'air_date': season.get('air_date')
                }
                for season in seasons
            ]
            
            # Cache for 30 days
            self._save_to_cache(cache_key, formatted_tv, hours=720)
            return formatted_tv
            
        except Exception as e:
            logger.error(f"Error getting TV details {tv_id}: {e}")
            return {}
    
    def get_movie_by_imdb(self, imdb_id: str) -> Optional[Dict]:
        """Get movie details by IMDb ID"""
        try:
            response = self.session.get(
                f"{self.base_url}/find/{imdb_id}",
                params={
                    'external_source': 'imdb_id',
                    'language': self.language
                },
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            if data.get('movie_results'):
                movie_id = data['movie_results'][0]['id']
                return self.get_movie_details(movie_id)
                
        except Exception as e:
            logger.error(f"Error getting movie by IMDb {imdb_id}: {e}")
        
        return None
    
    def _get_from_cache(self, cache_key: str) -> Optional[Dict]:
        """Get data from cache"""
        try:
            db = SessionLocal()
            cache_entry = db.query(TMDB_Cache).filter(
                TMDB_Cache.cache_key == cache_key,
                TMDB_Cache.expires_at > datetime.utcnow()
            ).first()
            
            if cache_entry:
                return json.loads(cache_entry.data)
        except Exception as e:
            logger.error(f"Error reading from cache: {e}")
        finally:
            db.close()
        
        return None
    
    def _save_to_cache(self, cache_key: str, data: Dict, hours: int = 24):
        """Save data to cache"""
        try:
            db = SessionLocal()
            expires_at = datetime.utcnow() + timedelta(hours=hours)
            
            cache_entry = TMDB_Cache(
                cache_key=cache_key,
                data=json.dumps(data, ensure_ascii=False),
                expires_at=expires_at
            )
            
            db.add(cache_entry)
            db.commit()
        except Exception as e:
            logger.error(f"Error saving to cache: {e}")
            db.rollback()
        finally:
            db.close()
    
    def cleanup_cache(self, days_old: int = 30):
        """Cleanup old cache entries"""
        try:
            db = SessionLocal()
            cutoff_date = datetime.utcnow() - timedelta(days=days_old)
            
            db.query(TMDB_Cache).filter(
                TMDB_Cache.expires_at < cutoff_date
            ).delete()
            
            db.commit()
            logger.info(f"Cleaned up old cache entries")
        except Exception as e:
            logger.error(f"Error cleaning cache: {e}")
            db.rollback()
        finally:
            db.close()
EOF

    # services/sync_movies.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/services/sync_movies.py <<'EOF'
"""
Movie synchronization service
Handles syncing movies to XUI One database
"""

import logging
from typing import Dict, List, Tuple
from datetime import datetime

from app.services.m3u_parser import M3UParser
from app.services.tmdb_service import TMDBService
from app.database.xui import XUIDatabase
from app.models.sync_logs import SyncLog

logger = logging.getLogger(__name__)

class MovieSyncService:
    """Service for syncing movies to XUI database"""
    
    def __init__(self, tmdb_service: TMDBService, xui_db: XUIDatabase):
        self.tmdb_service = tmdb_service
        self.xui_db = xui_db
        self.parser = M3UParser()
    
    def sync_movies(self, m3u_content: str, user_id: int, categories: List[str] = None) -> Dict:
        """
        Synchronize movies from M3U to XUI database
        
        Args:
            m3u_content: M3U playlist content
            user_id: ID of the user performing sync
            categories: List of categories to sync (None for all)
        
        Returns:
            Dict with sync results
        """
        logger.info(f"Starting movie sync for user {user_id}")
        
        # Parse M3U content
        parsed_content = self.parser.parse_m3u_content(m3u_content)
        
        # Filter movies by selected categories
        movies_to_sync = []
        if categories:
            for movie in parsed_content['movies']:
                movie_category = movie.get('category', 'Unknown')
                if movie_category in categories:
                    movies_to_sync.append(movie)
        else:
            movies_to_sync = parsed_content['movies']
        
        logger.info(f"Found {len(movies_to_sync)} movies to sync")
        
        results = {
            'total': len(movies_to_sync),
            'added': 0,
            'updated': 0,
            'failed': 0,
            'details': []
        }
        
        # Sync each movie
        for idx, movie_item in enumerate(movies_to_sync, 1):
            try:
                movie_info = self.parser.extract_movie_info(movie_item)
                
                # Search on TMDb
                tmdb_data = self.tmdb_service.search_movie(
                    movie_info['clean_title'],
                    movie_info['year']
                )
                
                if tmdb_data:
                    # Prepare movie data for XUI
                    xui_movie_data = self._prepare_xui_movie_data(movie_info, tmdb_data)
                    
                    # Check if movie exists in XUI
                    existing_movie = self.xui_db.get_movie_by_title(xui_movie_data['name'])
                    
                    if existing_movie:
                        # Update existing movie
                        success = self.xui_db.update_movie(existing_movie['id'], xui_movie_data)
                        if success:
                            results['updated'] += 1
                            results['details'].append({
                                'title': xui_movie_data['name'],
                                'status': 'updated',
                                'message': 'Movie updated successfully'
                            })
                        else:
                            results['failed'] += 1
                            results['details'].append({
                                'title': xui_movie_data['name'],
                                'status': 'failed',
                                'message': 'Failed to update movie'
                            })
                    else:
                        # Insert new movie
                        movie_id = self.xui_db.insert_movie(xui_movie_data)
                        if movie_id:
                            results['added'] += 1
                            results['details'].append({
                                'title': xui_movie_data['name'],
                                'status': 'added',
                                'message': f'Movie added with ID: {movie_id}'
                            })
                        else:
                            results['failed'] += 1
                            results['details'].append({
                                'title': xui_movie_data['name'],
                                'status': 'failed',
                                'message': 'Failed to add movie'
                            })
                else:
                    results['failed'] += 1
                    results['details'].append({
                        'title': movie_info['clean_title'],
                        'status': 'failed',
                        'message': 'Movie not found on TMDb'
                    })
                
                logger.info(f"Processed {idx}/{len(movies_to_sync)}: {movie_info['clean_title']}")
                
            except Exception as e:
                logger.error(f"Error syncing movie: {e}")
                results['failed'] += 1
                results['details'].append({
                    'title': movie_item.get('title', 'Unknown'),
                    'status': 'error',
                    'message': str(e)
                })
        
        # Log sync results
        self._log_sync_results(user_id, results)
        
        logger.info(f"Movie sync completed: {results}")
        return results
    
    def _prepare_xui_movie_data(self, movie_info: Dict, tmdb_data: Dict) -> Dict:
        """Prepare movie data for XUI database format"""
        
        # XUI One expects specific field names
        xui_movie = {
            'stream_type': 'movie',
            'stream_icon': tmdb_data.get('poster_path', ''),
            'name': tmdb_data.get('title', movie_info['clean_title']),
            'title': tmdb_data.get('title', movie_info['clean_title']),
            'year': tmdb_data.get('year', movie_info.get('year', '')),
            'rating': tmdb_data.get('vote_average', 0),
            'rating_5based': round(tmdb_data.get('vote_average', 0) / 2, 1),
            'duration': f"{tmdb_data.get('runtime', movie_info['duration'])} min",
            'duration_seconds': tmdb_data.get('runtime', movie_info['duration']) * 60,
            'plot': tmdb_data.get('overview', ''),
            'cast': ', '.join([actor['name'] for actor in tmdb_data.get('cast', [])[:5]]),
            'director': ', '.join(tmdb_data.get('directors', [])),
            'genre': ', '.join(tmdb_data.get('genres', [])),
            'releaseDate': tmdb_data.get('release_date', ''),
            'last_modified': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'youtube_trailer': '',
            'stream_url': movie_info['url'],
            'stream_url_direct': movie_info['url'],
            'container_extension': 'mp4',  # Default, can be detected from URL
            'custom_sid': '',  # Will be generated by XUI
            'added': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'category_id': self._get_or_create_category_id(movie_info['category']),
            'backdrop_path': tmdb_data.get('backdrop_path', ''),
            'tmdb_id': tmdb_data.get('tmdb_id'),
            'imdb_id': tmdb_data.get('imdb_id'),
            'is_adult': False
        }
        
        # Extract YouTube trailer if available
        trailers = tmdb_data.get('trailers', [])
        if trailers:
            xui_movie['youtube_trailer'] = f"https://www.youtube.com/watch?v={trailers[0]['key']}"
        
        # Detect container extension from URL
        url = movie_info['url'].lower()
        if url.endswith('.mp4'):
            xui_movie['container_extension'] = 'mp4'
        elif url.endswith('.mkv'):
            xui_movie['container_extension'] = 'mkv'
        elif url.endswith('.avi'):
            xui_movie['container_extension'] = 'avi'
        
        return xui_movie
    
    def _get_or_create_category_id(self, category_name: str) -> int:
        """Get or create category ID in XUI database"""
        # This is a simplified version
        # In production, you'd query the XUI categories table
        
        # For now, return a default category ID
        # You should implement proper category management
        category_map = {
            'Filmes': 1,
            'Movies': 1,
            'Filmes HD': 2,
            'Filmes 4K': 3,
            'Ação': 4,
            'Comédia': 5,
            'Drama': 6,
            'Terror': 7,
            'Ficção Científica': 8
        }
        
        return category_map.get(category_name, 1)  # Default to ID 1
    
    def _log_sync_results(self, user_id: int, results: Dict):
        """Log sync results to database"""
        try:
            db = SessionLocal()
            
            sync_log = SyncLog(
                user_id=user_id,
                log_type='info',
                operation='sync_movies',
                items_total=results['total'],
                items_processed=results['total'],
                items_added=results['added'],
                items_updated=results['updated'],
                items_failed=results['failed'],
                end_time=datetime.now(),
                duration_seconds=int((datetime.now() - sync_log.start_time).total_seconds()),
                details={'results': results['details']}
            )
            
            db.add(sync_log)
            db.commit()
            logger.info(f"Sync logged with ID: {sync_log.id}")
            
        except Exception as e:
            logger.error(f"Error logging sync results: {e}")
            db.rollback()
        finally:
            db.close()
EOF

    # Criar mais arquivos...
    create_more_backend_files
}

create_more_backend_files() {
    # Continuar criando todos os arquivos necessários
    # database/mysql.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/database/mysql.py <<'EOF'
"""
MySQL Database Configuration
"""

from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.config import settings

# Create engine
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    pool_size=10,
    max_overflow=20
)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Create base class for models
Base = declarative_base()

def get_db():
    """Dependency to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

    # models/user.py
    cat > $INSTALL_DIR/$BACKEND_DIR/app/models/user.py <<'EOF'
"""
User model for the VOD Sync System
"""

from sqlalchemy import Column, Integer, String, Boolean, Enum, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime
import enum
from app.database.mysql import Base

class UserLevel(enum.Enum):
    ADMIN = "admin"
    RESELLER = "reseller"
    USER = "user"

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(100))
    user_level = Column(Enum(UserLevel), default=UserLevel.USER)
    parent_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    license_key = Column(String(100), unique=True)
    is_active = Column(Boolean, default=True)
    max_clients = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login = Column(DateTime, nullable=True)
    
    # Relationships
    parent = relationship("User", remote_side=[id], backref="children")
    licenses = relationship("License", back_populates="user")
    xui_connections = relationship("XUIConnection", back_populates="user")
    m3u_lists = relationship("M3UList", back_populates="user")
    sync_logs = relationship("SyncLog", back_populates="user")
    content_categories = relationship("ContentCategory", back_populates="user")
    activities = relationship("UserActivity", back_populates="user")
    
    def to_dict(self):
        return {
            "id": self.id,
            "username": self.username,
            "email": self.email,
            "full_name": self.full_name,
            "user_level": self.user_level.value,
            "parent_id": self.parent_id,
            "license_key": self.license_key,
            "is_active": self.is_active,
            "max_clients": self.max_clients,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "last_login": self.last_login.isoformat() if self.last_login else None
        }
EOF

    # Criar um script de inicialização do sistema
    cat > $INSTALL_DIR/start_system.sh <<'EOF'
#!/bin/bash

# ============================================
# VOD Sync System - Startup Script
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_service() {
    if systemctl is-active --quiet $1; then
        echo -e "${GREEN}✓${NC} $1 is running"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not running"
        return 1
    fi
}

start_backend() {
    print_status "Starting Backend API..."
    cd /opt/vod_sync_system/backend
    source venv/bin/activate
    
    # Start in screen session
    screen -dmS vod_backend python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    
    sleep 3
    if curl -s http://localhost:8000/api/health > /dev/null; then
        print_status "Backend API started successfully"
    else
        print_error "Failed to start Backend API"
    fi
}

start_frontend() {
    print_status "Configuring Frontend..."
    
    # Configure Apache for frontend
    APACHE_CONF="/etc/apache2/sites-available/vod-sync.conf"
    
    cat > $APACHE_CONF <<'APACHE'
<VirtualHost *:80>
    ServerName localhost
    ServerAdmin admin@vodsync.com
    DocumentRoot /opt/vod_sync_system/frontend/public
    
    <Directory /opt/vod_sync_system/frontend/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Security headers
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/vod_sync_error.log
    CustomLog ${APACHE_LOG_DIR}/vod_sync_access.log combined
    
    # Proxy API requests to backend
    ProxyPreserveHost On
    ProxyPass /api/ http://localhost:8000/api/
    ProxyPassReverse /api/ http://localhost:8000/api/
</VirtualHost>
APACHE
    
    # Enable site
    a2ensite vod-sync.conf > /dev/null 2>&1
    a2enmod proxy proxy_http rewrite headers > /dev/null 2>&1
    
    # Restart Apache
    systemctl restart apache2
    
    print_status "Frontend configured"
}

start_scheduler() {
    print_status "Starting Scheduler Service..."
    
    # Create systemd service for scheduler
    cat > /etc/systemd/system/vod-scheduler.service <<'SERVICE'
[Unit]
Description=VOD Sync System Scheduler
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vod_sync_system/backend
Environment="PATH=/opt/vod_sync_system/backend/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/vod_sync_system/backend/venv/bin/python -m app.services.scheduler
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable vod-scheduler
    systemctl start vod-scheduler
    
    print_status "Scheduler service started"
}

show_status() {
    echo -e "\n${YELLOW}=== VOD Sync System Status ===${NC}\n"
    
    echo "Services:"
    check_service mysql
    check_service apache2
    check_service vod-scheduler
    
    echo -e "\nAPI Status:"
    if curl -s http://localhost:8000/api/health | grep -q "healthy"; then
        echo -e "${GREEN}✓ Backend API is healthy${NC}"
    else
        echo -e "${RED}✗ Backend API is not responding${NC}"
    fi
    
    echo -e "\nFrontend:"
    if curl -s http://localhost | grep -q "VOD Sync"; then
        echo -e "${GREEN}✓ Frontend is accessible${NC}"
    else
        echo -e "${RED}✗ Frontend is not accessible${NC}"
    fi
    
    echo -e "\n${YELLOW}Access Information:${NC}"
    echo "Frontend URL: http://$(hostname -I | awk '{print $1}')"
    echo "Backend API: http://$(hostname -I | awk '{print $1}'):8000"
    echo "Default Admin: admin / Admin@123"
}

main() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "  VOD Sync System Startup"
    echo "========================================"
    echo -e "${NC}"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    case "$1" in
        "start")
            start_backend
            start_frontend
            start_scheduler
            show_status
            ;;
        "stop")
            print_status "Stopping system..."
            systemctl stop vod-scheduler
            screen -S vod_backend -X quit
            systemctl stop apache2
            print_status "System stopped"
            ;;
        "restart")
            $0 stop
            sleep 2
            $0 start
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status}"
            exit 1
            ;;
    esac
}

main "$@"
EOF

    chmod +x $INSTALL_DIR/start_system.sh
}

setup_frontend() {
    print_step "Configurando frontend PHP..."
    
    # Criar arquivo index.php principal
    cat > $INSTALL_DIR/$FRONTEND_DIR/public/index.php <<'EOF'
<?php
/**
 * VOD Sync System - Frontend Entry Point
 */

// Define base path
define('BASE_PATH', dirname(__DIR__));
define('APP_PATH', BASE_PATH . '/app');
define('PUBLIC_PATH', __DIR__);

// Load configuration
require_once APP_PATH . '/config/config.php';

// Start session
session_start();

// Handle routing
$request_uri = strtok($_SERVER['REQUEST_URI'], '?');
$request_uri = trim($request_uri, '/');

// Define routes
$routes = [
    '' => 'views/dashboard.php',
    'login' => 'views/auth/login.php',
    'logout' => 'controllers/auth/logout.php',
    'dashboard' => 'views/dashboard.php',
    'xui-config' => 'views/xui/config.php',
    'm3u-lists' => 'views/m3u/lists.php',
    'movies' => 'views/content/movies.php',
    'series' => 'views/content/series.php',
    'sync' => 'views/sync/status.php',
    'users' => 'views/users/list.php',
    'licenses' => 'views/licenses/list.php',
    'settings' => 'views/settings/general.php',
    'api' => 'api.php'
];

// Check if route exists
if (array_key_exists($request_uri, $routes)) {
    $route_file = APP_PATH . '/' . $routes[$request_uri];
    
    if (file_exists($route_file)) {
        // Check authentication for protected routes
        $protected_routes = ['dashboard', 'xui-config', 'm3u-lists', 'movies', 'series', 'sync', 'users', 'licenses', 'settings'];
        
        if (in_array($request_uri, $protected_routes) && !isset($_SESSION['user_id'])) {
            header('Location: /login');
            exit;
        }
        
        require_once $route_file;
    } else {
        http_response_code(404);
        require_once APP_PATH . '/views/errors/404.php';
    }
} else {
    // Check if it's an API request
    if (strpos($request_uri, 'api/') === 0) {
        require_once APP_PATH . '/api.php';
    } else {
        http_response_code(404);
        require_once APP_PATH . '/views/errors/404.php';
    }
}
EOF

    # Criar arquivo de configuração
    cat > $INSTALL_DIR/$FRONTEND_DIR/app/config/config.php <<'EOF'
<?php
/**
 * Configuration file for VOD Sync System Frontend
 */

// Database configuration
define('DB_HOST', 'localhost');
define('DB_PORT', '3306');
define('DB_NAME', 'vod_sync_db');
define('DB_USER', 'vod_sync_user');
define('DB_PASS', 'SyncVod@2024');
define('DB_CHARSET', 'utf8mb4');

// Backend API configuration
define('API_BASE_URL', 'http://localhost:8000');
define('API_TIMEOUT', 30);

// Application settings
define('APP_NAME', 'VOD Sync System');
define('APP_VERSION', '2.0.0');
define('DEBUG_MODE', true);

// Security settings
define('SESSION_TIMEOUT', 3600); // 1 hour
define('CSRF_TOKEN_LIFE', 3600); // 1 hour

// Paths
define('BASE_URL', '');
define('ASSETS_URL', BASE_URL . '/assets');

// File upload settings
define('MAX_UPLOAD_SIZE', 10 * 1024 * 1024); // 10MB
define('ALLOWED_M3U_EXTENSIONS', ['m3u', 'm3u8', 'txt']);

// Create database connection
function get_db_connection() {
    static $connection = null;
    
    if ($connection === null) {
        try {
            $dsn = "mysql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
            $connection = new PDO($dsn, DB_USER, DB_PASS, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false
            ]);
        } catch (PDOException $e) {
            error_log("Database connection failed: " . $e->getMessage());
            die("Database connection error. Please check configuration.");
        }
    }
    
    return $connection;
}

// API call function
function call_api($endpoint, $method = 'GET', $data = null, $token = null) {
    $url = API_BASE_URL . $endpoint;
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, API_TIMEOUT);
    
    if ($method === 'POST') {
        curl_setopt($ch, CURLOPT_POST, true);
    } elseif ($method === 'PUT' || $method === 'DELETE') {
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    }
    
    $headers = ['Content-Type: application/json'];
    if ($token) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    
    if ($data) {
        $json_data = json_encode($data);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $json_data);
        $headers[] = 'Content-Length: ' . strlen($json_data);
    }
    
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($response === false) {
        return ['error' => 'API request failed', 'status' => 'error'];
    }
    
    $result = json_decode($response, true);
    $result['http_code'] = $http_code;
    
    return $result;
}

// Authentication check
function is_authenticated() {
    return isset($_SESSION['user_id']) && isset($_SESSION['user_level']);
}

// Check user level
function check_user_level($required_level) {
    if (!is_authenticated()) {
        return false;
    }
    
    $user_level = $_SESSION['user_level'];
    $levels = ['user' => 1, 'reseller' => 2, 'admin' => 3];
    
    return isset($levels[$user_level]) && 
           isset($levels[$required_level]) && 
           $levels[$user_level] >= $levels[$required_level];
}

// Generate CSRF token
function generate_csrf_token() {
    if (!isset($_SESSION['csrf_tokens'])) {
        $_SESSION['csrf_tokens'] = [];
    }
    
    $token = bin2hex(random_bytes(32));
    $_SESSION['csrf_tokens'][$token] = time();
    
    // Clean old tokens
    foreach ($_SESSION['csrf_tokens'] as $stored_token => $timestamp) {
        if (time() - $timestamp > CSRF_TOKEN_LIFE) {
            unset($_SESSION['csrf_tokens'][$stored_token]);
        }
    }
    
    return $token;
}

// Verify CSRF token
function verify_csrf_token($token) {
    if (!isset($_SESSION['csrf_tokens'][$token])) {
        return false;
    }
    
    $timestamp = $_SESSION['csrf_tokens'][$token];
    if (time() - $timestamp > CSRF_TOKEN_LIFE) {
        unset($_SESSION['csrf_tokens'][$token]);
        return false;
    }
    
    unset($_SESSION['csrf_tokens'][$token]);
    return true;
}

// Log activity
function log_activity($activity_type, $description) {
    if (!is_authenticated()) {
        return;
    }
    
    $db = get_db_connection();
    $stmt = $db->prepare("
        INSERT INTO user_activity 
        (user_id, activity_type, description, ip_address, user_agent) 
        VALUES (?, ?, ?, ?, ?)
    ");
    
    $stmt->execute([
        $_SESSION['user_id'],
        $activity_type,
        $description,
        $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0',
        $_SERVER['HTTP_USER_AGENT'] ?? 'Unknown'
    ]);
}
EOF

    # Criar página de login
    cat > $INSTALL_DIR/$FRONTEND_DIR/app/views/auth/login.php <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - VOD Sync System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
        }
        .login-card {
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        .login-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 15px 15px 0 0;
            padding: 30px;
            text-align: center;
        }
        .login-body {
            padding: 40px;
        }
        .form-control:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
            padding: 12px;
            font-weight: 600;
        }
        .btn-primary:hover {
            opacity: 0.9;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-md-5">
                <div class="login-card">
                    <div class="login-header">
                        <h2><i class="fas fa-sync-alt me-2"></i>VOD Sync System</h2>
                        <p class="mb-0">Sincronização Inteligente de Conteúdo</p>
                    </div>
                    
                    <div class="login-body">
                        <form id="loginForm">
                            <div class="mb-3">
                                <label for="username" class="form-label">
                                    <i class="fas fa-user me-2"></i>Usuário
                                </label>
                                <input type="text" class="form-control" id="username" 
                                       placeholder="Digite seu usuário" required>
                            </div>
                            
                            <div class="mb-3">
                                <label for="password" class="form-label">
                                    <i class="fas fa-lock me-2"></i>Senha
                                </label>
                                <input type="password" class="form-control" id="password" 
                                       placeholder="Digite sua senha" required>
                            </div>
                            
                            <div class="mb-3 form-check">
                                <input type="checkbox" class="form-check-input" id="remember">
                                <label class="form-check-label" for="remember">
                                    Lembrar-me
                                </label>
                            </div>
                            
                            <div class="d-grid gap-2">
                                <button type="submit" class="btn btn-primary btn-lg">
                                    <i class="fas fa-sign-in-alt me-2"></i>Entrar
                                </button>
                            </div>
                            
                            <div class="mt-3 text-center">
                                <a href="#" class="text-decoration-none">
                                    <small>Esqueceu a senha?</small>
                                </a>
                            </div>
                        </form>
                        
                        <div id="loginMessage" class="mt-3"></div>
                    </div>
                </div>
                
                <div class="text-center mt-3 text-white">
                    <small>Versão 2.0.0 © 2024 VOD Sync System</small>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        document.getElementById('loginForm').addEventListener('submit', function(e) {
            e.preventDefault();
            
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            const remember = document.getElementById('remember').checked;
            
            const messageDiv = document.getElementById('loginMessage');
            messageDiv.innerHTML = '';
            messageDiv.className = 'mt-3';
            
            // Show loading
            const submitBtn = this.querySelector('button[type="submit"]');
            const originalText = submitBtn.innerHTML;
            submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Autenticando...';
            submitBtn.disabled = true;
            
            // Call API
            fetch('/api/auth/login', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    username: username,
                    password: password
                })
            })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    messageDiv.className = 'mt-3 alert alert-success';
                    messageDiv.innerHTML = '<i class="fas fa-check-circle me-2"></i>' + data.message;
                    
                    // Store token if available
                    if (data.access_token) {
                        localStorage.setItem('auth_token', data.access_token);
                    }
                    
                    // Redirect to dashboard
                    setTimeout(() => {
                        window.location.href = '/dashboard';
                    }, 1000);
                } else {
                    messageDiv.className = 'mt-3 alert alert-danger';
                    messageDiv.innerHTML = '<i class="fas fa-exclamation-circle me-2"></i>' + (data.detail || 'Erro na autenticação');
                    submitBtn.innerHTML = originalText;
                    submitBtn.disabled = false;
                }
            })
            .catch(error => {
                console.error('Error:', error);
                messageDiv.className = 'mt-3 alert alert-danger';
                messageDiv.innerHTML = '<i class="fas fa-exclamation-circle me-2"></i>Erro na conexão com o servidor';
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
            });
        });
        
        // Focus on username field
        document.getElementById('username').focus();
    </script>
</body>
</html>
EOF

    # Criar dashboard
    cat > $INSTALL_DIR/$FRONTEND_DIR/app/views/dashboard.php <<'EOF'
<?php
require_once APP_PATH . '/views/layout/header.php';
?>

<div class="container-fluid">
    <div class="row">
        <!-- Sidebar -->
        <div class="col-md-2 sidebar">
            <?php include APP_PATH . '/views/layout/sidebar.php'; ?>
        </div>
        
        <!-- Main Content -->
        <div class="col-md-10 main-content">
            <!-- Dashboard Header -->
            <div class="dashboard-header">
                <h1><i class="fas fa-tachometer-alt me-2"></i>Dashboard</h1>
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item active">Dashboard</li>
                    </ol>
                </nav>
            </div>
            
            <!-- Stats Cards -->
            <div class="row stats-cards">
                <div class="col-md-3">
                    <div class="card stat-card bg-primary text-white">
                        <div class="card-body">
                            <div class="d-flex justify-content-between">
                                <div>
                                    <h6 class="card-title">Total Conteúdos</h6>
                                    <h2 id="totalContent">0</h2>
                                </div>
                                <div class="stat-icon">
                                    <i class="fas fa-film fa-2x"></i>
                                </div>
                            </div>
                            <p class="card-text">Filmes e séries sincronizados</p>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-3">
                    <div class="card stat-card bg-success text-white">
                        <div class="card-body">
                            <div class="d-flex justify-content-between">
                                <div>
                                    <h6 class="card-title">Filmes</h6>
                                    <h2 id="totalMovies">0</h2>
                                </div>
                                <div class="stat-icon">
                                    <i class="fas fa-video fa-2x"></i>
                                </div>
                            </div>
                            <p class="card-text">Filmes na biblioteca</p>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-3">
                    <div class="card stat-card bg-info text-white">
                        <div class="card-body">
                            <div class="d-flex justify-content-between">
                                <div>
                                    <h6 class="card-title">Séries</h6>
                                    <h2 id="totalSeries">0</h2>
                                </div>
                                <div class="stat-icon">
                                    <i class="fas fa-tv fa-2x"></i>
                                </div>
                            </div>
                            <p class="card-text">Séries na biblioteca</p>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-3">
                    <div class="card stat-card bg-warning text-white">
                        <div class="card-body">
                            <div class="d-flex justify-content-between">
                                <div>
                                    <h6 class="card-title">Última Sinc.</h6>
                                    <h5 id="lastSync">Nunca</h5>
                                </div>
                                <div class="stat-icon">
                                    <i class="fas fa-sync-alt fa-2x"></i>
                                </div>
                            </div>
                            <p class="card-text">Última sincronização</p>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- System Status -->
            <div class="row mt-4">
                <div class="col-md-8">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-chart-line me-2"></i>Status do Sistema
                            </h5>
                        </div>
                        <div class="card-body">
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="system-status-item">
                                        <h6>Status XUI</h6>
                                        <div class="d-flex align-items-center">
                                            <span id="xuiStatus" class="badge bg-danger">Desconectado</span>
                                            <button id="testXuiBtn" class="btn btn-sm btn-outline-primary ms-3">
                                                <i class="fas fa-plug me-1"></i>Testar
                                            </button>
                                        </div>
                                    </div>
                                    
                                    <div class="system-status-item mt-3">
                                        <h6>Próxima Sincronização</h6>
                                        <p id="nextSync" class="mb-0">Não agendada</p>
                                    </div>
                                    
                                    <div class="system-status-item mt-3">
                                        <h6>Licença</h6>
                                        <span id="licenseStatus" class="badge bg-success">Ativa</span>
                                        <small id="licenseExpiry" class="text-muted ms-2"></small>
                                    </div>
                                </div>
                                
                                <div class="col-md-6">
                                    <div class="system-status-item">
                                        <h6>API TMDb</h6>
                                        <span id="tmdbStatus" class="badge bg-danger">Não configurada</span>
                                    </div>
                                    
                                    <div class="system-status-item mt-3">
                                        <h6>Lista M3U Ativa</h6>
                                        <p id="activeM3U" class="mb-0">Nenhuma</p>
                                    </div>
                                    
                                    <div class="system-status-item mt-3">
                                        <h6>Uso de Disco</h6>
                                        <div class="progress">
                                            <div id="diskUsage" class="progress-bar" 
                                                 role="progressbar" style="width: 0%"></div>
                                        </div>
                                        <small id="diskUsageText" class="text-muted">0% usado</small>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-4">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-bolt me-2"></i>Ações Rápidas
                            </h5>
                        </div>
                        <div class="card-body">
                            <div class="d-grid gap-2">
                                <a href="/m3u-lists" class="btn btn-primary">
                                    <i class="fas fa-list me-2"></i>Gerenciar Listas M3U
                                </a>
                                <a href="/xui-config" class="btn btn-success">
                                    <i class="fas fa-cog me-2"></i>Configurar XUI
                                </a>
                                <a href="/movies" class="btn btn-info">
                                    <i class="fas fa-film me-2"></i>Gerenciar Filmes
                                </a>
                                <a href="/sync" class="btn btn-warning">
                                    <i class="fas fa-sync-alt me-2"></i>Sincronizar Agora
                                </a>
                            </div>
                        </div>
                    </div>
                    
                    <div class="card mt-3">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-history me-2"></i>Últimas Atividades
                            </h5>
                        </div>
                        <div class="card-body">
                            <div id="recentActivities" class="activity-list">
                                <div class="text-center text-muted">
                                    <i class="fas fa-spinner fa-spin"></i> Carregando...
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Recent Sync Logs -->
            <div class="row mt-4">
                <div class="col-12">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-clipboard-list me-2"></i>Últimas Sincronizações
                            </h5>
                        </div>
                        <div class="card-body">
                            <div class="table-responsive">
                                <table class="table table-hover">
                                    <thead>
                                        <tr>
                                            <th>Data/Hora</th>
                                            <th>Tipo</th>
                                            <th>Itens</th>
                                            <th>Adicionados</th>
                                            <th>Atualizados</th>
                                            <th>Status</th>
                                            <th>Ações</th>
                                        </tr>
                                    </thead>
                                    <tbody id="syncLogsTable">
                                        <tr>
                                            <td colspan="7" class="text-center">
                                                <i class="fas fa-spinner fa-spin"></i> Carregando...
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php
require_once APP_PATH . '/views/layout/footer.php';
?>

<script>
// Load dashboard data
document.addEventListener('DOMContentLoaded', function() {
    loadDashboardStats();
    loadRecentActivities();
    loadSyncLogs();
    checkSystemStatus();
    
    // Auto-refresh every 30 seconds
    setInterval(loadDashboardStats, 30000);
});

function loadDashboardStats() {
    fetch('/api/dashboard/stats', {
        headers: {
            'Authorization': 'Bearer ' + localStorage.getItem('auth_token')
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'success') {
            // Update stats
            document.getElementById('totalContent').textContent = 
                (parseInt(data.data.movies_count) + parseInt(data.data.series_count)).toLocaleString();
            document.getElementById('totalMovies').textContent = 
                data.data.movies_count.toLocaleString();
            document.getElementById('totalSeries').textContent = 
                data.data.series_count.toLocaleString();
            
            if (data.data.last_sync) {
                document.getElementById('lastSync').textContent = 
                    new Date(data.data.last_sync).toLocaleString('pt-BR');
            }
            
            // Update XUI status
            const xuiStatus = document.getElementById('xuiStatus');
            if (data.data.xui_connected) {
                xuiStatus.className = 'badge bg-success';
                xuiStatus.textContent = 'Conectado';
            } else {
                xuiStatus.className = 'badge bg-danger';
                xuiStatus.textContent = 'Desconectado';
            }
            
            // Update TMDb status
            const tmdbStatus = document.getElementById('tmdbStatus');
            if (data.data.tmdb_configured) {
                tmdbStatus.className = 'badge bg-success';
                tmdbStatus.textContent = 'Configurada';
            } else {
                tmdbStatus.className = 'badge bg-warning';
                tmdbStatus.textContent = 'Não configurada';
            }
            
            // Update disk usage
            const diskUsage = document.getElementById('diskUsage');
            const diskUsageText = document.getElementById('diskUsageText');
            diskUsage.style.width = data.data.disk_usage_percentage + '%';
            diskUsageText.textContent = data.data.disk_usage_percentage + '% usado';
        }
    })
    .catch(error => console.error('Error loading stats:', error));
}

function loadRecentActivities() {
    fetch('/api/dashboard/activities', {
        headers: {
            'Authorization': 'Bearer ' + localStorage.getItem('auth_token')
        }
    })
    .then(response => response.json())
    .then(data => {
        const container = document.getElementById('recentActivities');
        
        if (data.status === 'success' && data.data.length > 0) {
            let html = '';
            data.data.forEach(activity => {
                const timeAgo = getTimeAgo(activity.created_at);
                html += `
                <div class="activity-item">
                    <div class="activity-icon">
                        <i class="fas ${getActivityIcon(activity.activity_type)}"></i>
                    </div>
                    <div class="activity-content">
                        <p class="mb-0">${activity.description}</p>
                        <small class="text-muted">${timeAgo}</small>
                    </div>
                </div>`;
            });
            container.innerHTML = html;
        } else {
            container.innerHTML = '<p class="text-center text-muted">Nenhuma atividade recente</p>';
        }
    })
    .catch(error => {
        console.error('Error loading activities:', error);
    });
}

function loadSyncLogs() {
    fetch('/api/sync/logs?limit=5', {
        headers: {
            'Authorization': 'Bearer ' + localStorage.getItem('auth_token')
        }
    })
    .then(response => response.json())
    .then(data => {
        const tableBody = document.getElementById('syncLogsTable');
        
        if (data.status === 'success' && data.data.length > 0) {
            let html = '';
            data.data.forEach(log => {
                const statusBadge = getLogStatusBadge(log.log_type);
                const dateTime = new Date(log.start_time).toLocaleString('pt-BR');
                
                html += `
                <tr>
                    <td>${dateTime}</td>
                    <td>${log.operation}</td>
                    <td>${log.items_total}</td>
                    <td>${log.items_added}</td>
                    <td>${log.items_updated}</td>
                    <td>${statusBadge}</td>
                    <td>
                        <button class="btn btn-sm btn-info" onclick="viewLogDetails(${log.id})">
                            <i class="fas fa-eye"></i>
                        </button>
                    </td>
                </tr>`;
            });
            tableBody.innerHTML = html;
        } else {
            tableBody.innerHTML = `
            <tr>
                <td colspan="7" class="text-center">
                    Nenhum log de sincronização encontrado
                </td>
            </tr>`;
        }
    })
    .catch(error => {
        console.error('Error loading sync logs:', error);
        tableBody.innerHTML = `
        <tr>
            <td colspan="7" class="text-center text-danger">
                Erro ao carregar logs
            </td>
        </tr>`;
    });
}

function checkSystemStatus() {
    fetch('/api/dashboard/system-status', {
        headers: {
            'Authorization': 'Bearer ' + localStorage.getItem('auth_token')
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'success') {
            if (data.data.next_sync) {
                document.getElementById('nextSync').textContent = 
                    new Date(data.data.next_sync).toLocaleString('pt-BR');
            }
            
            if (data.data.active_m3u) {
                document.getElementById('activeM3U').textContent = data.data.active_m3u;
            }
        }
    });
}

function getTimeAgo(timestamp) {
    const now = new Date();
    const past = new Date(timestamp);
    const diffMs = now - past;
    const diffMins = Math.floor(diffMs / 60000);
    
    if (diffMins < 1) return 'Agora mesmo';
    if (diffMins < 60) return `${diffMins} min atrás`;
    
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours} h atrás`;
    
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays} dias atrás`;
}

function getActivityIcon(activityType) {
    const icons = {
        'login': 'fa-sign-in-alt',
        'logout': 'fa-sign-out-alt',
        'sync': 'fa-sync-alt',
        'config': 'fa-cog',
        'upload': 'fa-upload',
        'delete': 'fa-trash',
        'create': 'fa-plus',
        'update': 'fa-edit'
    };
    return icons[activityType] || 'fa-circle';
}

function getLogStatusBadge(logType) {
    const badges = {
        'info': '<span class="badge bg-info">Info</span>',
        'warning': '<span class="badge bg-warning">Aviso</span>',
        'error': '<span class="badge bg-danger">Erro</span>',
        'success': '<span class="badge bg-success">Sucesso</span>'
    };
    return badges[logType] || '<span class="badge bg-secondary">Desconhecido</span>';
}

function viewLogDetails(logId) {
    window.location.href = `/sync?log=${logId}`;
}

// Test XUI Connection
document.getElementById('testXuiBtn').addEventListener('click', function() {
    const btn = this;
    const originalText = btn.innerHTML;
    
    btn.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i>Testando...';
    btn.disabled = true;
    
    fetch('/api/xui/test-connection', {
        method: 'POST',
        headers: {
            'Authorization': 'Bearer ' + localStorage.getItem('auth_token'),
            'Content-Type': 'application/json'
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'success') {
            alert('Conexão com XUI testada com sucesso!');
        } else {
            alert('Erro na conexão com XUI: ' + (data.detail || 'Erro desconhecido'));
        }
    })
    .catch(error => {
        alert('Erro ao testar conexão com XUI');
    })
    .finally(() => {
        btn.innerHTML = originalText;
        btn.disabled = false;
        loadDashboardStats(); // Refresh stats
    });
});
</script>
EOF

    print_success "Frontend PHP configurado"
}

setup_crontab() {
    print_step "Configurando agendamento automático..."
    
    # Criar script de sincronização automática
    cat > $INSTALL_DIR/scripts/auto_sync.sh <<'EOF'
#!/bin/bash

# Auto-sync script for VOD Sync System

LOG_FILE="/opt/vod_sync_system/logs/cron_sync.log"
BACKEND_DIR="/opt/vod_sync_system/backend"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "========================================" >> $LOG_FILE
echo "Auto-sync started at: $TIMESTAMP" >> $LOG_FILE
echo "========================================" >> $LOG_FILE

# Activate virtual environment
cd $BACKEND_DIR
source venv/bin/activate

# Run sync command
python -m app.services.auto_sync >> $LOG_FILE 2>&1

# Check result
if [ $? -eq 0 ]; then
    echo "Auto-sync completed successfully" >> $LOG_FILE
else
    echo "Auto-sync failed" >> $LOG_FILE
fi

echo "========================================" >> $LOG_FILE
EOF

    chmod +x $INSTALL_DIR/scripts/auto_sync.sh
    
    # Adicionar ao crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/vod_sync_system/scripts/auto_sync.sh") | crontab -
    
    print_success "Agendamento automático configurado"
}

create_license_script() {
    print_step "Criando sistema de licenciamento..."
    
    cat > $INSTALL_DIR/scripts/license_manager.py <<'EOF'
#!/usr/bin/env python3
"""
License Manager for VOD Sync System
"""

import sys
import json
import requests
import hashlib
import uuid
from datetime import datetime, timedelta
from cryptography.fernet import Fernet

class LicenseManager:
    def __init__(self):
        self.license_file = "/opt/vod_sync_system/config/license.json"
        self.encryption_key = None
        
    def generate_license(self, license_type="monthly", duration_days=30, max_connections=1):
        """Generate a new license"""
        license_data = {
            "license_id": str(uuid.uuid4()),
            "license_key": self._generate_license_key(),
            "license_type": license_type,
            "issue_date": datetime.now().isoformat(),
            "expiry_date": (datetime.now() + timedelta(days=duration_days)).isoformat(),
            "max_connections": max_connections,
            "is_active": True,
            "product": "VOD Sync System",
            "version": "2.0.0"
        }
        
        # Save license
        self._save_license(license_data)
        
        return license_data
    
    def validate_license(self, license_key=None):
        """Validate a license"""
        try:
            if not license_key:
                # Load from file
                license_data = self._load_license()
                if not license_data:
                    return False, "No license found"
            else:
                license_data = {"license_key": license_key}
            
            # Check expiry
            expiry_date = datetime.fromisoformat(license_data.get("expiry_date"))
            if datetime.now() > expiry_date:
                return False, "License expired"
            
            # Check if active
            if not license_data.get("is_active", False):
                return False, "License inactive"
            
            # Additional validation logic here
            
            return True, "License valid"
            
        except Exception as e:
            return False, f"Validation error: {str(e)}"
    
    def _generate_license_key(self):
        """Generate a license key"""
        raw_key = f"VODSYS-{uuid.uuid4()}-{int(datetime.now().timestamp())}"
        hashed = hashlib.sha256(raw_key.encode()).hexdigest()[:20].upper()
        return f"VOD-{hashed}"
    
    def _save_license(self, license_data):
        """Save license to file"""
        try:
            with open(self.license_file, 'w') as f:
                json.dump(license_data, f, indent=2)
            return True
        except Exception as e:
            print(f"Error saving license: {e}")
            return False
    
    def _load_license(self):
        """Load license from file"""
        try:
            with open(self.license_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            return None
        except Exception as e:
            print(f"Error loading license: {e}")
            return None

def main():
    """CLI for license management"""
    manager = LicenseManager()
    
    if len(sys.argv) < 2:
        print("Usage: license_manager.py [generate|validate|info]")
        return
    
    command = sys.argv[1]
    
    if command == "generate":
        # Generate new license
        license_type = sys.argv[2] if len(sys.argv) > 2 else "monthly"
        duration = int(sys.argv[3]) if len(sys.argv) > 3 else 30
        connections = int(sys.argv[4]) if len(sys.argv) > 4 else 1
        
        license_data = manager.generate_license(license_type, duration, connections)
        print("\n" + "="*50)
        print("LICENSE GENERATED SUCCESSFULLY")
        print("="*50)
        print(f"License Key: {license_data['license_key']}")
        print(f"Type: {license_data['license_type']}")
        print(f"Expires: {license_data['expiry_date']}")
        print(f"Max Connections: {license_data['max_connections']}")
        print("="*50)
        
        # Save to file
        manager._save_license(license_data)
        print(f"License saved to: {manager.license_file}")
        
    elif command == "validate":
        # Validate license
        license_key = sys.argv[2] if len(sys.argv) > 2 else None
        valid, message = manager.validate_license(license_key)
        
        if valid:
            print(f"✓ {message}")
            return 0
        else:
            print(f"✗ {message}")
            return 1
            
    elif command == "info":
        # Show license info
        license_data = manager._load_license()
        if license_data:
            print(json.dumps(license_data, indent=2))
        else:
            print("No license information found")
    else:
        print(f"Unknown command: {command}")

if __name__ == "__main__":
    main()
EOF

    chmod +x $INSTALL_DIR/scripts/license_manager.py
    
    # Gerar licença inicial
    cd $INSTALL_DIR
    python3 scripts/license_manager.py generate lifetime 3650 999999 > /dev/null 2>&1
    
    print_success "Sistema de licenciamento criado"
}

setup_permissions() {
    print_step "Configurando permissões..."
    
    # Definir dono e permissões
    chown -R www-data:www-data $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR
    chmod -R 777 $INSTALL_DIR/logs
    chmod 600 $INSTALL_DIR/config/*.cnf 2>/dev/null
    
    # Permissões específicas
    chmod +x $INSTALL_DIR/*.sh
    chmod +x $INSTALL_DIR/scripts/*.py
    chmod +x $INSTALL_DIR/scripts/*.sh
    
    print_success "Permissões configuradas"
}

create_install_summary() {
    print_step "Criando resumo da instalação..."
    
    SUMMARY_FILE="$INSTALL_DIR/INSTALL_SUMMARY.txt"
    
    cat > $SUMMARY_FILE <<EOF
==================================================
VOD SYNC SYSTEM - INSTALAÇÃO CONCLUÍDA
==================================================

DATA DA INSTALAÇÃO: $(date)
VERSÃO DO SISTEMA: 2.0.0
DIRETÓRIO DE INSTALAÇÃO: $INSTALL_DIR

📁 ESTRUTURA DE DIRETÓRIOS:
├── backend/          - Backend Python (FastAPI)
├── frontend/         - Frontend PHP
├── logs/             - Logs do sistema
├── config/           - Arquivos de configuração
├── backups/          - Backups automáticos
└── scripts/          - Scripts utilitários

🌐 ACESSO AO SISTEMA:
Frontend: http://$(hostname -I | awk '{print $1}')/
Backend API: http://$(hostname -I | awk '{print $1}'):8000
API Docs: http://$(hostname -I | awk '{print $1}'):8000/api/docs

🔐 CREDENCIAIS PADRÃO:
Usuário: admin
Senha: Admin@123

📊 BANCO DE DADOS:
Host: localhost
Porta: 3306
Database: vod_sync_db
Usuário: vod_sync_user

🔧 SERVIÇOS CONFIGURADOS:
✅ MySQL/MariaDB
✅ Apache2 (Frontend)
✅ FastAPI Backend
✅ Scheduler Service
✅ Cron Jobs

⚙️ COMANDOS ÚTEIS:
Iniciar sistema: $INSTALL_DIR/start_system.sh start
Parar sistema: $INSTALL_DIR/start_system.sh stop
Reiniciar: $INSTALL_DIR/start_system.sh restart
Ver status: $INSTALL_DIR/start_system.sh status

Gerenciar licenças: $INSTALL_DIR/scripts/license_manager.py

📋 PRÓXIMOS PASSOS:

1. CONFIGURAR XUI ONE:
   - Acesse o painel: http://$(hostname -I | awk '{print $1}')/xui-config
   - Insira as credenciais do banco XUI
   - Teste a conexão

2. INSERIR LISTA M3U:
   - Acesse: http://$(hostname -I | awk '{print $1}')/m3u-lists
   - Cole sua lista M3U
   - Clique em "Escanear Lista"

3. CONFIGURAR API TMDb:
   - Obtenha uma chave API em: https://www.themoviedb.org/settings/api
   - Configure no painel de administração

4. SINCRONIZAR CONTEÚDO:
   - Escolha as categorias para filmes e séries
   - Execute a sincronização manual
   - Configure agendamento automático

🛠️ SUPORTE:
Documentação: Incluída no diretório /docs
Logs: $INSTALL_DIR/logs/
Backups automáticos: Diários em $INSTALL_DIR/backups/

⚠️ IMPORTANTE:
- Altere a senha padrão do administrador
- Configure backup automático do banco de dados
- Mantenha o sistema atualizado
- Revise as permissões de arquivos

==================================================
SISTEMA INSTALADO COM SUCESSO!
==================================================
EOF

    print_success "Resumo da instalação criado: $SUMMARY_FILE"
}

finalize_installation() {
    print_step "Finalizando instalação..."
    
    # Criar arquivo README
    cat > $INSTALL_DIR/README.md <<'EOF'
# VOD Sync System

Sistema completo para sincronização de filmes e séries a partir de listas M3U para o XUI One.

## Características Principais

- 🎯 Sincronização automática de conteúdo VOD
- 🔗 Integração direta com banco XUI One
- 🎬 Enriquecimento via TMDb (pt-BR)
- 👥 Hierarquia de usuários (Admin, Revendedor, Usuário)
- 🔐 Sistema de licenciamento
- ⚡ Sincronização agendada
- 📊 Dashboard completo

## Estrutura do Sistema
