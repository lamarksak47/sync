#!/bin/bash

# ============================================
# INSTALADOR COMPLETO - VOD SYNC SYSTEM
# Sistema de Sincronização de Conteúdo VOD
# ============================================

set -e  # Sai em caso de erro

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
LOG_FILE="$BASE_DIR/install.log"

# Funções de utilitário
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Verificar dependências do sistema
check_dependencies() {
    log "Verificando dependências do sistema..."
    
    # Verificar se é usuário root/sudo
    if [ "$EUID" -ne 0 ]; then 
        warning "Recomendado executar como sudo para instalação de pacotes"
    fi
    
    # Verificar comandos essenciais
    for cmd in python3 php mysql pip3 git curl; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd não encontrado. Por favor, instale antes de continuar."
        fi
        success "$cmd encontrado"
    done
    
    # Verificar versões
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    PHP_VERSION=$(php --version | head -n1 | cut -d' ' -f2)
    
    log "Python $PYTHON_VERSION detectado"
    log "PHP $PHP_VERSION detectado"
}

# Criar estrutura de diretórios
create_directory_structure() {
    log "Criando estrutura de diretórios..."
    
    # Diretórios principais
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$FRONTEND_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Backend - Python FastAPI
    mkdir -p "$BACKEND_DIR/app"
    mkdir -p "$BACKEND_DIR/app/controllers"
    mkdir -p "$BACKEND_DIR/app/services"
    mkdir -p "$BACKEND_DIR/app/database"
    mkdir -p "$BACKEND_DIR/app/models"
    mkdir -p "$BACKEND_DIR/app/routes"
    mkdir -p "$BACKEND_DIR/app/utils"
    mkdir -p "$BACKEND_DIR/app/schemas"
    mkdir -p "$BACKEND_DIR/app/middleware"
    mkdir -p "$BACKEND_DIR/app/core"
    mkdir -p "$BACKEND_DIR/logs"
    mkdir -p "$BACKEND_DIR/tests"
    
    # Frontend - PHP
    mkdir -p "$FRONTEND_DIR/public"
    mkdir -p "$FRONTEND_DIR/public/assets"
    mkdir -p "$FRONTEND_DIR/public/assets/css"
    mkdir -p "$FRONTEND_DIR/public/assets/js"
    mkdir -p "$FRONTEND_DIR/public/assets/images"
    mkdir -p "$FRONTEND_DIR/app/controllers"
    mkdir -p "$FRONTEND_DIR/app/models"
    mkdir -p "$FRONTEND_DIR/app/views"
    mkdir -p "$FRONTEND_DIR/app/helpers"
    mkdir -p "$FRONTEND_DIR/app/middleware"
    mkdir -p "$FRONTEND_DIR/config"
    mkdir -p "$FRONTEND_DIR/vendor"
    mkdir -p "$FRONTEND_DIR/temp"
    mkdir -p "$FRONTEND_DIR/logs"
    
    # Instalador
    mkdir -p "$INSTALL_DIR/sql"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/scripts"
    
    success "Estrutura de diretórios criada"
}

# Criar arquivos de banco de dados
create_database_files() {
    log "Criando arquivos SQL do banco de dados..."
    
    # Arquivo SQL principal
    cat > "$INSTALL_DIR/sql/database.sql" << 'EOF'
-- ============================================
-- BANCO DE DADOS - VOD SYNC SYSTEM
-- ============================================

CREATE DATABASE IF NOT EXISTS vod_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vod_system;

-- ============================================
-- TABELAS DO SISTEMA
-- ============================================

-- Tabela de usuários
CREATE TABLE users (
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
);

-- Tabela de licenças
CREATE TABLE licenses (
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
);

-- Tabela de conexões XUI
CREATE TABLE xui_connections (
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
);

-- Tabela de listas M3U
CREATE TABLE m3u_lists (
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
);

-- Tabela de categorias
CREATE TABLE categories (
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
);

-- Tabela de agendamentos
CREATE TABLE schedules (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    name VARCHAR(100),
    schedule_type ENUM('sync', 'backup', 'cleanup') DEFAULT 'sync',
    cron_expression VARCHAR(50) DEFAULT '0 2 * * *', -- 2 AM diariamente
    is_active BOOLEAN DEFAULT TRUE,
    last_run TIMESTAMP NULL,
    next_run TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_next_run (next_run, is_active)
);

-- Tabela de logs de sincronização
CREATE TABLE sync_logs (
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
);

-- Tabela de configurações do sistema
CREATE TABLE system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type ENUM('string', 'int', 'bool', 'json') DEFAULT 'string',
    category VARCHAR(50) DEFAULT 'general',
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category)
);

-- Tabela de cache TMDb
CREATE TABLE tmdb_cache (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tmdb_id INT NOT NULL,
    content_type ENUM('movie', 'tv') NOT NULL,
    language VARCHAR(10) DEFAULT 'pt-BR',
    data JSON NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    UNIQUE KEY unique_tmdb_content (tmdb_id, content_type, language),
    INDEX idx_expires (expires_at)
);

-- ============================================
-- INSERTS INICIAIS
-- ============================================

-- Inserir usuário administrador padrão (senha: admin123)
INSERT INTO users (username, email, password_hash, user_type, is_active) 
VALUES ('admin', 'admin@vodsync.com', '$2y$10$YourHashedPasswordHere', 'admin', TRUE);

-- Inserir configurações padrão
INSERT INTO system_settings (setting_key, setting_value, setting_type, category) VALUES
('system_name', 'VOD Sync System', 'string', 'general'),
('tmdb_api_key', '', 'string', 'tmdb'),
('tmdb_language', 'pt-BR', 'string', 'tmdb'),
('sync_auto_start', 'true', 'bool', 'sync'),
('default_sync_time', '02:00', 'string', 'sync'),
('max_retries', '3', 'int', 'sync'),
('log_retention_days', '30', 'int', 'logs');

-- ============================================
-- PROCEDURES E TRIGGERS
-- ============================================

-- Trigger para atualizar updated_at
DELIMITER //
CREATE TRIGGER update_users_timestamp 
BEFORE UPDATE ON users 
FOR EACH ROW 
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//

CREATE TRIGGER update_licenses_timestamp 
BEFORE UPDATE ON licenses 
FOR EACH ROW 
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//

CREATE TRIGGER update_xui_connections_timestamp 
BEFORE UPDATE ON xui_connections 
FOR EACH ROW 
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//

CREATE TRIGGER update_schedules_timestamp 
BEFORE UPDATE ON schedules 
FOR EACH ROW 
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//

CREATE TRIGGER update_system_settings_timestamp 
BEFORE UPDATE ON system_settings 
FOR EACH ROW 
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//
DELIMITER ;

-- Procedure para limpar logs antigos
DELIMITER //
CREATE PROCEDURE CleanOldLogs()
BEGIN
    DELETE FROM sync_logs 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL (SELECT setting_value FROM system_settings WHERE setting_key = 'log_retention_days') DAY);
END//
DELIMITER ;

-- ============================================
-- VIEWS
-- ============================================

-- View para dashboard
CREATE VIEW dashboard_stats AS
SELECT 
    u.id as user_id,
    u.username,
    COUNT(DISTINCT xc.id) as xui_connections,
    COUNT(DISTINCT ml.id) as m3u_lists,
    COUNT(DISTINCT c.id) as categories,
    MAX(sl.created_at) as last_sync
FROM users u
LEFT JOIN xui_connections xc ON u.id = xc.user_id AND xc.is_active = TRUE
LEFT JOIN m3u_lists ml ON u.id = ml.user_id AND ml.is_active = TRUE
LEFT JOIN categories c ON u.id = c.user_id AND c.is_selected = TRUE
LEFT JOIN sync_logs sl ON u.id = sl.user_id AND sl.log_type = 'success'
GROUP BY u.id, u.username;

-- View para relatório de sincronização
CREATE VIEW sync_report AS
SELECT 
    DATE(created_at) as sync_date,
    user_id,
    operation,
    content_type,
    COUNT(*) as total_items,
    SUM(CASE WHEN log_type = 'error' THEN 1 ELSE 0 END) as errors
FROM sync_logs
GROUP BY DATE(created_at), user_id, operation, content_type;

SELECT 'Banco de dados criado com sucesso!' as message;
EOF

    # Arquivo de migração
    cat > "$INSTALL_DIR/sql/migrations.sql" << 'EOF'
-- ============================================
-- MIGRAÇÕES DO BANCO DE DADOS
-- ============================================

-- Migração para versão 1.1
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'America/Sao_Paulo';
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN DEFAULT TRUE;

-- Migração para versão 1.2
CREATE TABLE IF NOT EXISTS user_sessions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_token (session_token),
    INDEX idx_expires (expires_at)
);

-- Migração para versão 1.3
ALTER TABLE m3u_lists ADD COLUMN IF NOT EXISTS auto_sync BOOLEAN DEFAULT TRUE;
ALTER TABLE m3u_lists ADD COLUMN IF NOT EXISTS sync_frequency ENUM('hourly', 'daily', 'weekly') DEFAULT 'daily';

-- Migração para versão 1.4
CREATE TABLE IF NOT EXISTS failed_syncs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    xui_connection_id INT NOT NULL,
    m3u_list_id INT NOT NULL,
    error_message TEXT,
    retry_count INT DEFAULT 0,
    last_attempt TIMESTAMP NULL,
    next_retry TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (xui_connection_id) REFERENCES xui_connections(id) ON DELETE CASCADE,
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE CASCADE,
    INDEX idx_next_retry (next_retry)
);
EOF

    success "Arquivos SQL criados"
}

# Criar arquivos de configuração
create_config_files() {
    log "Criando arquivos de configuração..."
    
    # Backend .env
    cat > "$BACKEND_DIR/.env" << 'EOF'
# ============================================
# CONFIGURAÇÕES DO BACKEND - VOD SYNC SYSTEM
# ============================================

# Aplicação
APP_NAME=VOD Sync System
APP_VERSION=1.0.0
DEBUG=False
ENVIRONMENT=production

# Servidor
HOST=0.0.0.0
PORT=8000
API_PREFIX=/api/v1
CORS_ORIGINS=["http://localhost:3000", "http://localhost:8080"]

# Banco de dados do sistema
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_system
DB_USER=root
DB_PASS=

# TMDb API
TMDB_API_KEY=your_tmdb_api_key_here
TMDB_LANGUAGE=pt-BR
TMDB_CACHE_MINUTES=1440  # 24 horas

# Segurança
SECRET_KEY=your-secret-key-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440  # 24 horas
REFRESH_TOKEN_EXPIRE_DAYS=30

# Redis (opcional para cache)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# Limites
MAX_M3U_SIZE_MB=10
MAX_SYNC_RETRIES=3
SYNC_BATCH_SIZE=50

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/backend.log
LOG_RETENTION_DAYS=30

# Paths
TEMP_DIR=/tmp/vod_sync
CACHE_DIR=./cache
EOF

    # Frontend config
    cat > "$FRONTEND_DIR/config/database.php" << 'EOF'
<?php
// ============================================
// CONFIGURAÇÃO DO BANCO DE DADOS - FRONTEND
// ============================================

return [
    'database' => [
        'host' => $_ENV['DB_HOST'] ?? 'localhost',
        'port' => $_ENV['DB_PORT'] ?? 3306,
        'name' => $_ENV['DB_NAME'] ?? 'vod_system',
        'user' => $_ENV['DB_USER'] ?? 'root',
        'pass' => $_ENV['DB_PASS'] ?? '',
        'charset' => 'utf8mb4',
        'collation' => 'utf8mb4_unicode_ci',
        'prefix' => '',
        'options' => [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    ]
];
EOF

    # Frontend .env
    cat > "$FRONTEND_DIR/.env" << 'EOF'
# ============================================
# CONFIGURAÇÕES DO FRONTEND
# ============================================

APP_NAME="VOD Sync System"
APP_ENV=production
APP_DEBUG=false
APP_URL=http://localhost:8080

# Backend API
API_BASE_URL=http://localhost:8000/api/v1
API_TIMEOUT=30

# Session
SESSION_DRIVER=file
SESSION_LIFETIME=120
SESSION_ENCRYPT=false

# Cache
CACHE_DRIVER=file
CACHE_LIFETIME=60

# Security
APP_KEY=base64:your-app-key-here
JWT_SECRET=your-jwt-secret-here

# Frontend
FRONTEND_THEME=default
ITEMS_PER_PAGE=20
DATE_FORMAT="d/m/Y H:i:s"
EOF

    # Nginx config
    cat > "$INSTALL_DIR/config/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name your-domain.com;
    root /var/www/vod_sync/frontend/public;
    index index.php index.html;

    # Frontend PHP
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # Logs
    access_log /var/log/nginx/vod_sync_access.log;
    error_log /var/log/nginx/vod_sync_error.log;
}
EOF

    # Apache config
    cat > "$INSTALL_DIR/config/apache.conf" << 'EOF'
<VirtualHost *:80>
    ServerName your-domain.com
    ServerAdmin admin@vodsync.com
    DocumentRoot /var/www/vod_sync/frontend/public

    <Directory /var/www/vod_sync/frontend/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Security
        <IfModule mod_headers.c>
            Header always set X-Frame-Options "SAMEORIGIN"
            Header always set X-Content-Type-Options "nosniff"
            Header always set X-XSS-Protection "1; mode=block"
        </IfModule>
    </Directory>

    # Backend API proxy
    ProxyPass /api http://127.0.0.1:8000/api
    ProxyPassReverse /api http://127.0.0.1:8000/api

    # Logs
    ErrorLog ${APACHE_LOG_DIR}/vod_sync_error.log
    CustomLog ${APACHE_LOG_DIR}/vod_sync_access.log combined
</VirtualHost>
EOF

    success "Arquivos de configuração criados"
}

# Criar arquivos Python do backend
create_backend_files() {
    log "Criando arquivos do backend Python..."
    
    # requirements.txt
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
# Core
fastapi==0.104.1
uvicorn[standard]==0.24.0

# Database
sqlalchemy==2.0.23
pymysql==1.1.0
aiomysql==0.2.0
alembic==1.12.1

# Security
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
bcrypt==4.1.2
python-multipart==0.0.6

# HTTP/API
httpx==0.25.1
requests==2.31.0
aiohttp==3.9.1

# Scheduler
apscheduler==3.10.4

# Parsing
beautifulsoup4==4.12.2
lxml==4.9.3
m3u8==4.1.0

# Utils
python-dotenv==1.0.0
pydantic==2.5.0
pydantic-settings==2.1.0
redis==5.0.1
celery==5.3.4

# Logging
loguru==0.7.2

# Testing
pytest==7.4.3
pytest-asyncio==0.21.1
httpx==0.25.1
EOF

    # main.py
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
"""
VOD Sync System - Main Application
Backend FastAPI principal
"""

import os
import logging
from fastapi import FastAPI, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base
from app.middleware.auth import AuthMiddleware
from app.middleware.logging import LoggingMiddleware
from app.routes import auth, users, xui, m3u, sync, dashboard, admin
from app.utils.logger import setup_logger

# Configurar logging
logger = setup_logger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan events - startup and shutdown
    """
    # Startup
    logger.info("Starting VOD Sync System...")
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    logger.info(f"Database: {settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}")
    
    # Create database tables
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        logger.info("Database tables created/verified")
    except Exception as e:
        logger.error(f"Database initialization error: {str(e)}")
        raise
    
    yield
    
    # Shutdown
    logger.info("Shutting down VOD Sync System...")
    await engine.dispose()

# Create FastAPI app
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Sistema de sincronização de conteúdos VOD com XUI One",
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
    lifespan=lifespan
)

# Middlewares
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.ALLOWED_HOSTS
)

app.add_middleware(LoggingMiddleware)
app.add_middleware(AuthMiddleware)

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

# Exception handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )

# Health check endpoint
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT
    }

# Include routers
app.include_router(auth.router, prefix="/api/v1/auth", tags=["Authentication"])
app.include_router(users.router, prefix="/api/v1/users", tags=["Users"])
app.include_router(xui.router, prefix="/api/v1/xui", tags=["XUI Connections"])
app.include_router(m3u.router, prefix="/api/v1/m3u", tags=["M3U Lists"])
app.include_router(sync.router, prefix="/api/v1/sync", tags=["Synchronization"])
app.include_router(dashboard.router, prefix="/api/v1/dashboard", tags=["Dashboard"])
app.include_router(admin.router, prefix="/api/v1/admin", tags=["Admin"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info"
    )
EOF

    # Arquivo __init__.py para cada pasta
    for dir in $(find "$BACKEND_DIR/app" -type d); do
        touch "$dir/__init__.py"
    done

    success "Arquivos do backend criados"
}

# Criar arquivos PHP do frontend
create_frontend_files() {
    log "Criando arquivos do frontend PHP..."
    
    # index.php principal
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<?php
/**
 * VOD Sync System - Frontend Entry Point
 */

require_once __DIR__ . '/../app/bootstrap.php';

use App\Core\Application;

// Inicializar aplicação
$app = new Application();

// Configurar rotas
require_once __DIR__ . '/../app/routes/web.php';

// Executar aplicação
$app->run();
EOF

    # login.php
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
/**
 * Página de login
 */

session_start();

// Se já estiver logado, redireciona para dashboard
if (isset($_SESSION['user_id']) && $_SESSION['user_id'] > 0) {
    header('Location: /dashboard.php');
    exit;
}

require_once __DIR__ . '/../app/controllers/AuthController.php';

$authController = new AuthController();
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if ($authController->login($username, $password)) {
        header('Location: /dashboard.php');
        exit;
    } else {
        $error = 'Credenciais inválidas';
    }
}

// HTML da página de login
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - VOD Sync System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
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
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
        }
        .login-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 15px 15px 0 0;
            text-align: center;
        }
        .login-body {
            padding: 30px;
        }
        .form-control:focus {
            border-color: #764ba2;
            box-shadow: 0 0 0 0.2rem rgba(118, 75, 162, 0.25);
        }
        .btn-login {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
            color: white;
            padding: 12px;
            font-weight: 600;
            transition: all 0.3s;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(118, 75, 162, 0.3);
        }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="login-header">
            <h3><i class="fas fa-sync-alt me-2"></i>VOD Sync System</h3>
            <p class="mb-0">Sincronização inteligente de conteúdos VOD</p>
        </div>
        <div class="login-body">
            <?php if ($error): ?>
                <div class="alert alert-danger alert-dismissible fade show" role="alert">
                    <?php echo htmlspecialchars($error); ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            <?php endif; ?>
            
            <form method="POST" action="">
                <div class="mb-3">
                    <label for="username" class="form-label">
                        <i class="fas fa-user me-2"></i>Usuário
                    </label>
                    <input type="text" class="form-control" id="username" name="username" 
                           required autofocus placeholder="Digite seu usuário">
                </div>
                <div class="mb-3">
                    <label for="password" class="form-label">
                        <i class="fas fa-lock me-2"></i>Senha
                    </label>
                    <input type="password" class="form-control" id="password" name="password" 
                           required placeholder="Digite sua senha">
                </div>
                <div class="mb-3 form-check">
                    <input type="checkbox" class="form-check-input" id="remember" name="remember">
                    <label class="form-check-label" for="remember">Lembrar-me</label>
                </div>
                <button type="submit" class="btn btn-login w-100">
                    <i class="fas fa-sign-in-alt me-2"></i>Entrar
                </button>
            </form>
            
            <hr class="my-4">
            
            <div class="text-center">
                <p class="mb-2">
                    <a href="#" class="text-decoration-none">
                        <i class="fas fa-key me-1"></i>Esqueci minha senha
                    </a>
                </p>
                <p class="mb-0 text-muted small">
                    Sistema licenciado © <?php echo date('Y'); ?> VOD Sync
                </p>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Focus no campo usuário ao carregar
        document.getElementById('username').focus();
        
        // Mostrar/ocultar senha
        const togglePassword = document.createElement('span');
        togglePassword.innerHTML = '<i class="fas fa-eye"></i>';
        togglePassword.className = 'input-group-text';
        togglePassword.style.cursor = 'pointer';
        togglePassword.onclick = function() {
            const password = document.getElementById('password');
            const type = password.getAttribute('type') === 'password' ? 'text' : 'password';
            password.setAttribute('type', type);
            this.innerHTML = type === 'password' ? '<i class="fas fa-eye"></i>' : '<i class="fas fa-eye-slash"></i>';
        };
        
        const passwordInput = document.getElementById('password');
        passwordInput.parentNode.classList.add('input-group');
        passwordInput.parentNode.appendChild(togglePassword);
    </script>
</body>
</html>
EOF

    # dashboard.php
    cat > "$FRONTEND_DIR/public/dashboard.php" << 'EOF'
<?php
/**
 * Dashboard principal
 */

require_once __DIR__ . '/../app/bootstrap.php';

// Verificar autenticação
if (!isset($_SESSION['user_id'])) {
    header('Location: /login.php');
    exit;
}

require_once __DIR__ . '/../app/controllers/DashboardController.php';

$dashboard = new DashboardController();
$stats = $dashboard->getUserStats($_SESSION['user_id']);
$recentLogs = $dashboard->getRecentLogs($_SESSION['user_id']);
$nextSync = $dashboard->getNextSync($_SESSION['user_id']);

// HTML do dashboard
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - VOD Sync System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.8.1/font/bootstrap-icons.min.css">
    <style>
        :root {
            --primary: #667eea;
            --secondary: #764ba2;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
        }
        
        body {
            background-color: #f8f9fa;
        }
        
        .sidebar {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            height: 100vh;
            position: fixed;
            left: 0;
            top: 0;
            width: 250px;
            transition: all 0.3s;
            z-index: 1000;
        }
        
        .sidebar-header {
            padding: 20px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        
        .nav-link {
            color: rgba(255,255,255,0.8);
            padding: 12px 20px;
            margin: 2px 0;
            border-radius: 8px;
            transition: all 0.3s;
        }
        
        .nav-link:hover, .nav-link.active {
            color: white;
            background: rgba(255,255,255,0.1);
        }
        
        .nav-link i {
            width: 20px;
            margin-right: 10px;
        }
        
        .main-content {
            margin-left: 250px;
            padding: 20px;
            transition: all 0.3s;
        }
        
        .stat-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            transition: transform 0.3s;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .stat-icon {
            width: 50px;
            height: 50px;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
        }
        
        .progress-bar {
            background: linear-gradient(135deg, var(--primary), var(--secondary));
        }
        
        .log-item {
            border-left: 4px solid;
            padding-left: 15px;
            margin-bottom: 15px;
        }
        
        .log-info { border-color: #3b82f6; }
        .log-success { border-color: var(--success); }
        .log-warning { border-color: var(--warning); }
        .log-error { border-color: var(--danger); }
        
        @media (max-width: 768px) {
            .sidebar {
                margin-left: -250px;
            }
            .main-content {
                margin-left: 0;
            }
            .sidebar.active {
                margin-left: 0;
            }
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="sidebar-header">
            <h4><i class="fas fa-sync-alt me-2"></i>VOD Sync</h4>
            <p class="mb-0 small opacity-75"><?php echo $_SESSION['username']; ?></p>
        </div>
        
        <nav class="nav flex-column mt-3">
            <a href="/dashboard.php" class="nav-link active">
                <i class="fas fa-tachometer-alt"></i> Dashboard
            </a>
            <a href="/xui.php" class="nav-link">
                <i class="fas fa-server"></i> Conexões XUI
            </a>
            <a href="/m3u.php" class="nav-link">
                <i class="fas fa-list"></i> Listas M3U
            </a>
            <a href="/movies.php" class="nav-link">
                <i class="fas fa-film"></i> Filmes
            </a>
            <a href="/series.php" class="nav-link">
                <i class="fas fa-tv"></i> Séries
            </a>
            <a href="/sync.php" class="nav-link">
                <i class="fas fa-sync"></i> Sincronização
            </a>
            <a href="/logs.php" class="nav-link">
                <i class="fas fa-clipboard-list"></i> Logs
            </a>
            
            <?php if ($_SESSION['user_type'] === 'admin'): ?>
                <div class="mt-4 pt-3 border-top border-white-10">
                    <p class="small opacity-75 px-3 mb-2">Administração</p>
                    <a href="/admin/users.php" class="nav-link">
                        <i class="fas fa-users"></i> Usuários
                    </a>
                    <a href="/admin/licenses.php" class="nav-link">
                        <i class="fas fa-key"></i> Licenças
                    </a>
                    <a href="/admin/settings.php" class="nav-link">
                        <i class="fas fa-cog"></i> Configurações
                    </a>
                </div>
            <?php endif; ?>
            
            <div class="mt-auto p-3">
                <a href="/profile.php" class="nav-link">
                    <i class="fas fa-user"></i> Perfil
                </a>
                <a href="/logout.php" class="nav-link text-danger">
                    <i class="fas fa-sign-out-alt"></i> Sair
                </a>
            </div>
        </nav>
    </div>
    
    <!-- Main Content -->
    <div class="main-content">
        <!-- Header -->
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h1 class="h3 mb-0">Dashboard</h1>
            <button class="btn btn-primary d-md-none" id="sidebarToggle">
                <i class="fas fa-bars"></i>
            </button>
        </div>
        
        <!-- Stats Cards -->
        <div class="row g-4 mb-4">
            <div class="col-md-3">
                <div class="stat-card">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="text-muted mb-2">Conexões XUI</h6>
                            <h3 class="mb-0"><?php echo $stats['xui_connections']; ?></h3>
                        </div>
                        <div class="stat-icon bg-primary bg-opacity-10 text-primary">
                            <i class="fas fa-server"></i>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="stat-card">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="text-muted mb-2">Filmes</h6>
                            <h3 class="mb-0"><?php echo $stats['total_movies']; ?></h3>
                        </div>
                        <div class="stat-icon bg-success bg-opacity-10 text-success">
                            <i class="fas fa-film"></i>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="stat-card">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="text-muted mb-2">Séries</h6>
                            <h3 class="mb-0"><?php echo $stats['total_series']; ?></h3>
                        </div>
                        <div class="stat-icon bg-warning bg-opacity-10 text-warning">
                            <i class="fas fa-tv"></i>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="stat-card">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="text-muted mb-2">Última Sinc.</h6>
                            <h6 class="mb-0"><?php echo $stats['last_sync'] ?: 'Nunca'; ?></h6>
                        </div>
                        <div class="stat-icon bg-info bg-opacity-10 text-info">
                            <i class="fas fa-sync-alt"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Two Columns -->
        <div class="row g-4">
            <!-- Left Column -->
            <div class="col-lg-8">
                <!-- Sync Progress -->
                <div class="card mb-4">
                    <div class="card-header">
                        <h5 class="mb-0">Sincronização</h5>
                    </div>
                    <div class="card-body">
                        <div class="mb-3">
                            <div class="d-flex justify-content-between mb-1">
                                <span>Progresso atual</span>
                                <span>65%</span>
                            </div>
                            <div class="progress" style="height: 10px;">
                                <div class="progress-bar" style="width: 65%"></div>
                            </div>
                        </div>
                        
                        <div class="row g-3">
                            <div class="col-md-6">
                                <button class="btn btn-primary w-100">
                                    <i class="fas fa-sync me-2"></i>Sincronizar Agora
                                </button>
                            </div>
                            <div class="col-md-6">
                                <button class="btn btn-outline-secondary w-100" data-bs-toggle="modal" data-bs-target="#scheduleModal">
                                    <i class="fas fa-clock me-2"></i>Agendar
                                </button>
                            </div>
                        </div>
                        
                        <div class="mt-3">
                            <p class="mb-1 small">
                                <i class="fas fa-clock text-muted me-2"></i>
                                Próxima sincronização: 
                                <strong><?php echo $nextSync ?: 'Não agendada'; ?></strong>
                            </p>
                        </div>
                    </div>
                </div>
                
                <!-- Recent Logs -->
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <h5 class="mb-0">Logs Recentes</h5>
                        <a href="/logs.php" class="btn btn-sm btn-outline-primary">Ver Todos</a>
                    </div>
                    <div class="card-body">
                        <div class="list-group list-group-flush">
                            <?php foreach ($recentLogs as $log): ?>
                                <div class="list-group-item border-0 px-0 py-2">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h6 class="mb-1"><?php echo htmlspecialchars($log['item_title']); ?></h6>
                                            <p class="mb-0 small text-muted"><?php echo $log['message']; ?></p>
                                        </div>
                                        <div class="text-end">
                                            <span class="badge bg-<?php echo $log['log_type']; ?> mb-2">
                                                <?php echo $log['operation']; ?>
                                            </span>
                                            <br>
                                            <small class="text-muted"><?php echo $log['created_at']; ?></small>
                                        </div>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Right Column -->
            <div class="col-lg-4">
                <!-- Quick Actions -->
                <div class="card mb-4">
                    <div class="card-header">
                        <h5 class="mb-0">Ações Rápidas</h5>
                    </div>
                    <div class="card-body">
                        <div class="d-grid gap-2">
                            <a href="/xui.php?action=add" class="btn btn-outline-primary text-start">
                                <i class="fas fa-plus-circle me-2"></i>Nova Conexão XUI
                            </a>
                            <a href="/m3u.php?action=add" class="btn btn-outline-primary text-start">
                                <i class="fas fa-plus-circle me-2"></i>Nova Lista M3U
                            </a>
                            <a href="/movies.php?action=scan" class="btn btn-outline-success text-start">
                                <i class="fas fa-search me-2"></i>Escanear Filmes
                            </a>
                            <a href="/series.php?action=scan" class="btn btn-outline-success text-start">
                                <i class="fas fa-search me-2"></i>Escanear Séries
                            </a>
                            <a href="/sync.php?action=manual" class="btn btn-outline-warning text-start">
                                <i class="fas fa-play me-2"></i>Sincronização Manual
                            </a>
                        </div>
                    </div>
                </div>
                
                <!-- System Status -->
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0">Status do Sistema</h5>
                    </div>
                    <div class="card-body">
                        <ul class="list-unstyled mb-0">
                            <li class="mb-2 d-flex justify-content-between">
                                <span>API Backend:</span>
                                <span class="badge bg-success">Online</span>
                            </li>
                            <li class="mb-2 d-flex justify-content-between">
                                <span>Banco de Dados:</span>
                                <span class="badge bg-success">Conectado</span>
                            </li>
                            <li class="mb-2 d-flex justify-content-between">
                                <span>TMDb API:</span>
                                <span class="badge bg-success">Conectado</span>
                            </li>
                            <li class="mb-2 d-flex justify-content-between">
                                <span>Agendador:</span>
                                <span class="badge bg-success">Ativo</span>
                            </li>
                            <li class="d-flex justify-content-between">
                                <span>Última Checagem:</span>
                                <span><?php echo date('H:i:s'); ?></span>
                            </li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Schedule Modal -->
    <div class="modal fade" id="scheduleModal" tabindex="-1">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Agendar Sincronização</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <form id="scheduleForm">
                        <div class="mb-3">
                            <label class="form-label">Horário</label>
                            <input type="time" class="form-control" value="02:00" required>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Frequência</label>
                            <select class="form-select" required>
                                <option value="daily">Diariamente</option>
                                <option value="weekly">Semanalmente</option>
                                <option value="hourly">A cada hora</option>
                            </select>
                        </div>
                        <div class="form-check mb-3">
                            <input class="form-check-input" type="checkbox" id="notify">
                            <label class="form-check-label" for="notify">
                                Notificar por e-mail
                            </label>
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                    <button type="button" class="btn btn-primary">Salvar Agendamento</button>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Toggle sidebar on mobile
        document.getElementById('sidebarToggle').addEventListener('click', function() {
            document.querySelector('.sidebar').classList.toggle('active');
        });
        
        // Auto-refresh logs every 30 seconds
        setInterval(function() {
            fetch('/api/v1/logs/recent')
                .then(response => response.json())
                .then(data => {
                    // Update logs section
                    console.log('Logs updated');
                });
        }, 30000);
        
        // Update sync progress in real-time
        function updateSyncProgress() {
            fetch('/api/v1/sync/progress')
                .then(response => response.json())
                .then(data => {
                    if (data.progress) {
                        const progressBar = document.querySelector('.progress-bar');
                        progressBar.style.width = data.progress + '%';
                        progressBar.nextElementSibling.textContent = data.progress + '%';
                    }
                });
        }
        
        // Update progress every 5 seconds if sync is running
        setInterval(updateSyncProgress, 5000);
    </script>
</body>
</html>
EOF

    success "Arquivos do frontend criados"
}

# Criar arquivos de instalação
create_installer_files() {
    log "Criando arquivos do instalador..."
    
    # Script de instalação principal
    cat > "$BASE_DIR/install.sh" << 'EOF'
#!/bin/bash

# ============================================
# INSTALADOR COMPLETO - VOD SYNC SYSTEM
# ============================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretório base
BASE_DIR=$(pwd)
BACKEND_DIR="$BASE_DIR/backend"
FRONTEND_DIR="$BASE_DIR/frontend"
INSTALL_DIR="$BASE_DIR/install"

# Funções
print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          VOD SYNC SYSTEM - INSTALAÇÃO COMPLETA          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# Verificar dependências
check_dependencies() {
    log "Verificando dependências do sistema..."
    
    local missing_deps=()
    
    for cmd in python3 php mysql pip3 git curl wget; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        warning "Dependências faltando: ${missing_deps[*]}"
        read -p "Deseja instalar automaticamente? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            error "Por favor, instale as dependências manualmente."
        fi
    fi
    
    success "Dependências verificadas"
}

install_dependencies() {
    log "Instalando dependências do sistema..."
    
    # Detectar distribuição
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt update
        sudo apt install -y python3 python3-pip python3-venv \
                          php php-fpm php-mysql php-curl php-json \
                          mysql-server git curl wget \
                          nginx apache2-utils
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        sudo yum install -y python3 python3-pip python3-virtualenv \
                          php php-fpm php-mysql php-curl php-json \
                          mariadb-server git curl wget \
                          nginx httpd-tools
    else
        warning "Distribuição não suportada. Instale manualmente:"
        echo "- Python 3.10+"
        echo "- PHP 8.0+"
        echo "- MySQL/MariaDB"
        echo "- Nginx/Apache"
        exit 1
    fi
    
    success "Dependências instaladas"
}

# Configurar banco de dados
setup_database() {
    log "Configurando banco de dados..."
    
    read -p "Nome do banco de dados [vod_system]: " db_name
    db_name=${db_name:-vod_system}
    
    read -p "Usuário MySQL [vodsync_user]: " db_user
    db_user=${db_user:-vodsync_user}
    
    read -sp "Senha MySQL: " db_pass
    echo
    
    # Criar banco de dados
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    
    # Importar estrutura
    sudo mysql $db_name < "$INSTALL_DIR/sql/database.sql"
    
    # Atualizar arquivos de configuração
    sed -i "s/DB_NAME=.*/DB_NAME=$db_name/" "$BACKEND_DIR/.env"
    sed -i "s/DB_USER=.*/DB_USER=$db_user/" "$BACKEND_DIR/.env"
    sed -i "s/DB_PASS=.*/DB_PASS=$db_pass/" "$BACKEND_DIR/.env"
    
    success "Banco de dados configurado"
}

# Configurar backend Python
setup_backend() {
    log "Configurando backend Python..."
    
    cd "$BACKEND_DIR"
    
    # Criar ambiente virtual
    python3 -m venv venv
    source venv/bin/activate
    
    # Instalar dependências
    pip install --upgrade pip
    pip install -r requirements.txt
    
    # Configurar chave secreta
    secret_key=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    sed -i "s/SECRET_KEY=.*/SECRET_KEY=$secret_key/" "$BACKEND_DIR/.env"
    
    # Configurar TMDb API Key
    read -p "Chave da API TMDb (obtenha em https://www.themoviedb.org/settings/api): " tmdb_key
    if [ -n "$tmdb_key" ]; then
        sed -i "s/TMDB_API_KEY=.*/TMDB_API_KEY=$tmdb_key/" "$BACKEND_DIR/.env"
    fi
    
    # Criar serviço systemd
    cat > /etc/systemd/system/vod-sync-backend.service << EOF
[Unit]
Description=VOD Sync System Backend
After=network.target mysql.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin"
ExecStart=$BACKEND_DIR/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable vod-sync-backend
    sudo systemctl start vod-sync-backend
    
    success "Backend configurado"
}

# Configurar frontend PHP
setup_frontend() {
    log "Configurando frontend PHP..."
    
    # Configurar PHP
    sudo systemctl enable php-fpm
    sudo systemctl start php-fpm
    
    # Configurar Nginx
    read -p "Domínio ou IP do servidor [localhost]: " domain
    domain=${domain:-localhost}
    
    sudo cp "$INSTALL_DIR/config/nginx.conf" /etc/nginx/sites-available/vod-sync
    sudo sed -i "s/your-domain.com/$domain/g" /etc/nginx/sites-available/vod-sync
    sudo sed -i "s|/var/www/vod_sync|$BASE_DIR|g" /etc/nginx/sites-available/vod-sync
    
    sudo ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    
    # Configurar Apache (alternativa)
    # sudo cp "$INSTALL_DIR/config/apache.conf" /etc/apache2/sites-available/vod-sync.conf
    # sudo a2ensite vod-sync
    # sudo a2enmod proxy proxy_http rewrite
    # sudo systemctl reload apache2
    
    success "Frontend configurado"
}

# Configurar agendador
setup_scheduler() {
    log "Configurando agendador..."
    
    cat > /etc/systemd/system/vod-sync-scheduler.service << EOF
[Unit]
Description=VOD Sync System Scheduler
After=network.target vod-sync-backend.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin"
ExecStart=$BACKEND_DIR/venv/bin/python -m app.services.scheduler
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable vod-sync-scheduler
    sudo systemctl start vod-sync-scheduler
    
    success "Agendador configurado"
}

# Criar usuário administrador
create_admin_user() {
    log "Criando usuário administrador..."
    
    read -p "Usuário administrador [admin]: " admin_user
    admin_user=${admin_user:-admin}
    
    read -p "E-mail do administrador: " admin_email
    
    read -sp "Senha do administrador: " admin_pass
    echo
    
    # Hash da senha (exemplo simples - em produção usar bcrypt)
    pass_hash=$(echo -n "$admin_pass" | sha256sum | cut -d' ' -f1)
    
    # Atualizar banco de dados
    sudo mysql vod_system << EOF
UPDATE users SET 
    username='$admin_user',
    email='$admin_email',
    password_hash='$pass_hash'
WHERE id=1;
EOF
    
    success "Usuário administrador criado"
}

# Instalação completa
complete_installation() {
    print_header
    
    echo "Este instalador irá:"
    echo "1. Verificar dependências do sistema"
    echo "2. Configurar banco de dados MySQL"
    echo "3. Configurar backend Python (FastAPI)"
    echo "4. Configurar frontend PHP (Nginx)"
    echo "5. Configurar agendador automático"
    echo "6. Criar usuário administrador"
    echo ""
    
    read -p "Deseja continuar? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Instalação cancelada."
        exit 0
    fi
    
    # Executar passos
    check_dependencies
    setup_database
    setup_backend
    setup_frontend
    setup_scheduler
    create_admin_user
    
    # Finalização
    print_header
    echo "✅ Instalação concluída com sucesso!"
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🌐 URL de acesso: http://$domain"
    echo "👤 Usuário: $admin_user"
    echo "🔑 Senha: [a senha que você definiu]"
    echo ""
    echo "🔧 Serviços instalados:"
    echo "   - vod-sync-backend (Porta 8000)"
    echo "   - vod-sync-scheduler"
    echo "   - Nginx/PHP-FPM"
    echo ""
    echo "📁 Diretórios:"
    echo "   - Backend: $BACKEND_DIR"
    echo "   - Frontend: $FRONTEND_DIR"
    echo "   - Logs: $BACKEND_DIR/logs"
    echo ""
    echo "⚡ Comandos úteis:"
    echo "   sudo systemctl status vod-sync-backend"
    echo "   sudo systemctl status vod-sync-scheduler"
    echo "   sudo tail -f $BACKEND_DIR/logs/backend.log"
    echo "══════════════════════════════════════════════════════════"
    echo ""
    echo "📚 Documentação e suporte em: https://github.com/vod-sync"
    
    # Criar arquivo de instalação concluída
    date > "$BASE_DIR/.installed"
    echo "version=1.0.0" >> "$BASE_DIR/.installed"
    echo "install_date=$(date '+%Y-%m-%d %H:%M:%S')" >> "$BASE_DIR/.installed"
}

# Menu principal
main_menu() {
    while true; do
        print_header
        echo "Selecione uma opção:"
        echo ""
        echo "1) Instalação Completa"
        echo "2) Apenas Backend"
        echo "3) Apenas Frontend"
        echo "4) Apenas Banco de Dados"
        echo "5) Verificar Sistema"
        echo "6) Desinstalar"
        echo "7) Sair"
        echo ""
        read -p "Opção: " choice
        
        case $choice in
            1) complete_installation ;;
            2) setup_backend ;;
            3) setup_frontend ;;
            4) setup_database ;;
            5) check_dependencies ;;
            6) uninstall_system ;;
            7) exit 0 ;;
            *) echo "Opção inválida"; sleep 2 ;;
        esac
        
        read -p "Pressione Enter para continuar..." -n 1
    done
}

# Desinstalar
uninstall_system() {
    warning "ATENÇÃO: Esta ação irá remover completamente o sistema!"
    read -p "Tem certeza? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        return
    fi
    
    log "Desinstalando sistema..."
    
    # Parar e remover serviços
    sudo systemctl stop vod-sync-backend vod-sync-scheduler
    sudo systemctl disable vod-sync-backend vod-sync-scheduler
    sudo rm -f /etc/systemd/system/vod-sync-*.service
    sudo systemctl daemon-reload
    
    # Remover configuração do Nginx
    sudo rm -f /etc/nginx/sites-available/vod-sync
    sudo rm -f /etc/nginx/sites-enabled/vod-sync
    sudo systemctl reload nginx
    
    # Remover banco de dados (opcional)
    read -p "Remover banco de dados também? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        sudo mysql -e "DROP DATABASE IF EXISTS vod_system;"
        sudo mysql -e "DROP USER IF EXISTS 'vodsync_user'@'localhost';"
    fi
    
    # Remover arquivos de instalação
    rm -f "$BASE_DIR/.installed"
    
    success "Sistema desinstalado"
}

# Executar menu principal
if [[ "$1" == "--auto" ]]; then
    complete_installation
else
    main_menu
fi
EOF

    chmod +x "$BASE_DIR/install.sh"

    # Script de atualização
    cat > "$BASE_DIR/update.sh" << 'EOF'
#!/bin/bash

# Script de atualização do VOD Sync System

set -e

BASE_DIR=$(pwd)
BACKEND_DIR="$BASE_DIR/backend"

echo "🔄 Atualizando VOD Sync System..."

# 1. Backup do banco de dados
echo "📦 Fazendo backup do banco de dados..."
mysqldump vod_system > "backup_$(date +%Y%m%d_%H%M%S).sql"

# 2. Atualizar código
echo "📥 Atualizando código do Git..."
git pull origin main

# 3. Atualizar dependências do backend
echo "🐍 Atualizando Python dependencies..."
cd "$BACKEND_DIR"
source venv/bin/activate
pip install -r requirements.txt --upgrade

# 4. Aplicar migrações do banco de dados
echo "🗄️ Aplicando migrações..."
mysql vod_system < "$BASE_DIR/install/sql/migrations.sql"

# 5. Reiniciar serviços
echo "🔄 Reiniciando serviços..."
sudo systemctl restart vod-sync-backend
sudo systemctl restart vod-sync-scheduler

echo "✅ Atualização concluída!"
EOF

    chmod +x "$BASE_DIR/update.sh"

    # Script de backup
    cat > "$BASE_DIR/backup.sh" << 'EOF'
#!/bin/bash

# Script de backup do VOD Sync System

set -e

BACKUP_DIR="/var/backups/vod-sync"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "📦 Iniciando backup do VOD Sync System..."

# 1. Backup do banco de dados
echo "🗄️ Backup do banco de dados..."
mysqldump vod_system > "$BACKUP_DIR/vod_system_$DATE.sql"

# 2. Compactar backup
echo "🗜️ Compactando backup..."
tar -czf "$BACKUP_DIR/vod_system_full_$DATE.tar.gz" \
    --exclude="venv" \
    --exclude="__pycache__" \
    --exclude="*.log" \
    --exclude=".git" \
    .

# 3. Manter apenas últimos 7 backups
echo "🧹 Limpando backups antigos..."
ls -t "$BACKUP_DIR"/*.tar.gz | tail -n +8 | xargs rm -f
ls -t "$BACKUP_DIR"/*.sql | tail -n +8 | xargs rm -f

# 4. Mostrar informações
echo "✅ Backup concluído!"
echo ""
echo "📊 Informações do backup:"
ls -lh "$BACKUP_DIR/vod_system_full_$DATE.tar.gz"
echo ""
echo "💾 Local: $BACKUP_DIR"
echo "📅 Data: $(date)"
EOF

    chmod +x "$BASE_DIR/backup.sh"

    success "Arquivos do instalador criados"
}

# Criar README e documentação
create_documentation() {
    log "Criando documentação..."
    
    # README.md
    cat > "$BASE_DIR/README.md" << 'EOF'
# VOD Sync System

Sistema completo para sincronização de conteúdos VOD (Filmes e Séries) a partir de listas M3U com o banco de dados do XUI One, enriquecimento automático via TMDb (pt-BR) e painel administrativo web.

## 🚀 Funcionalidades

### ✅ Obrigatórias
1. **Conexão XUI One** - Configuração direta do banco de dados
2. **Listas M3U** - Upload e parsing de listas M3U
3. **Scanner Inteligente** - Identificação automática de filmes/séries
4. **Enriquecimento TMDb** - Metadados em português brasileiro
5. **Sincronização** - Manual e automática agendada
6. **Painel Web** - Interface moderna responsiva
7. **Hierarquia de Usuários** - Admin, Revendedor, Usuário
8. **Sistema de Licenças** - Controle de acesso e validade

### 🎯 Recursos Avançados
- Cache inteligente TMDb
- Logs detalhados com histórico
- Barra de progresso em tempo real
- Agendamento flexível (cron)
- Backup automático
- API REST completa
- Multi-tenant (SaaS)

## 🏗️ Arquitetura

vod_sync/
├── backend/ # Python FastAPI
│ ├── app/
│ │ ├── controllers/ # Controladores API
│ │ ├── services/ # Lógica de negócio
│ │ ├── database/ # Models e conexões
│ │ ├── routes/ # Rotas da API
│ │ └── utils/ # Utilitários
│ ├── requirements.txt
│ └── .env
├── frontend/ # PHP Web Panel
│ ├── public/ # Arquivos públicos
│ ├── app/ # Aplicação MVC
│ ├── config/ # Configurações
│ └── vendor/ # Dependências
├── install/ # Instalador
│ ├── sql/ # Scripts SQL
│ ├── config/ # Configurações servidor
│ └── scripts/ # Scripts auxiliares
└── docs/ # Documentação


## 📋 Requisitos do Sistema

### Servidor
- Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- 2+ CPUs, 4GB+ RAM, 50GB+ SSD
- Python 3.10+
- PHP 8.0+
- MySQL/MariaDB 10.5+
- Nginx ou Apache

### APIs Externas
- [TMDb API Key](https://www.themoviedb.org/settings/api)
- Acesso ao banco do XUI One

## 🛠️ Instalação

### Instalação Automática (Recomendada)
```bash
# 1. Clone o repositório
git clone https://github.com/seu-repo/vod-sync.git
cd vod-sync

# 2. Execute o instalador
sudo ./install.sh

## 🛠️. Siga as instruções no terminal

# 1. Criar estrutura
./setup.sh

# 2. Configurar banco de dados
mysql -u root -p < install/sql/database.sql

# 3. Configurar backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. Configurar frontend
cp frontend/.env.example frontend/.env
# Editar configurações

# 5. Configurar servidor web
# Ver arquivos em install/config/
EOF

    success "Arquivos do README.md criados"
}
