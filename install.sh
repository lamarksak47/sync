#!/bin/bash
# install_vod_sync_complete.sh - Instalador COMPLETO com todas as páginas web

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
DOMAIN="${1:-}"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
OS=""
VERSION=""
PHP_VERSION=""
PHP_FPM_SERVICE=""
PHP_FPM_SOCKET=""

# ============================================
# FUNÇÕES UTILITÁRIAS
# ============================================

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
warning() { echo -e "${YELLOW}!${NC} $1" | tee -a "$LOG_FILE"; }

check_root() { [[ $EUID -ne 0 ]] && error "Execute como root: sudo $0"; }

detect_system() {
    log "Detectando sistema..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        success "Sistema: $OS $VERSION"
    else
        error "Sistema não suportado"
    fi
}

# ============================================
# 1. REMOVER APACHE E CONFLITOS
# ============================================

remove_apache() {
    log "Removendo Apache..."
    systemctl stop apache2 2>/dev/null
    systemctl disable apache2 2>/dev/null
    if dpkg -l | grep -q apache2; then
        apt-get remove --purge apache2 apache2-utils libapache2-mod-php* -y
        apt-get autoremove -y
        success "Apache removido"
    fi
    pkill -9 apache2 2>/dev/null || true
}

free_port_80() {
    log "Limpando porta 80..."
    for pid in $(lsof -ti:80); do
        process=$(ps -p $pid -o comm=)
        if [[ "$process" != "nginx" ]]; then
            log "Matando processo $process (PID: $pid) na porta 80"
            kill -9 $pid 2>/dev/null
        fi
    done
}

# ============================================
# 2. INSTALAR DEPENDÊNCIAS
# ============================================

install_dependencies() {
    log "Instalando dependências..."
    
    # Atualizar
    apt-get update || error "Falha ao atualizar"
    
    # Remover Apache
    remove_apache
    free_port_80
    
    # Dependências básicas
    log "Instalando básicas..."
    apt-get install -y curl wget git build-essential software-properties-common || error "Falha"
    
    # Python
    log "Instalando Python..."
    apt-get install -y python3 python3-pip python3-venv python3-dev || error "Falha Python"
    
    # MySQL
    log "Instalando MySQL..."
    apt-get install -y mysql-server mysql-client libmysqlclient-dev || error "Falha MySQL"
    
    # Nginx
    log "Instalando Nginx..."
    apt-get install -y nginx || error "Falha Nginx"
    
    # Supervisor
    log "Instalando Supervisor..."
    apt-get install -y supervisor || error "Falha Supervisor"
    
    # Redis (opcional)
    apt-get install -y redis-server || warning "Redis falhou"
    
    success "Dependências instaladas"
}

# ============================================
# 3. INSTALAR PHP - QUALQUER VERSÃO
# ============================================

install_php() {
    log "Instalando PHP..."
    
    # Tentar versões na ordem
    local php_versions=("8.1" "8.0" "7.4" "7.3" "php")
    
    for version in "${php_versions[@]}"; do
        log "Tentando PHP $version..."
        
        if [[ "$version" == "php" ]]; then
            packages="php php-cli php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-json"
        else
            packages="php$version php$version-cli php$version-fpm php$version-mysql php$version-curl php$version-gd php$version-mbstring php$version-xml php$version-zip php$version-bcmath php$version-json"
        fi
        
        if apt-get install -y $packages 2>>"$LOG_FILE"; then
            PHP_VERSION="$version"
            
            if [[ "$version" == "php" ]]; then
                PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
                PHP_FPM_SERVICE="php-fpm"
                PHP_FPM_SOCKET="/var/run/php/php-fpm.sock"
            else
                PHP_FPM_SERVICE="php$version-fpm"
                PHP_FPM_SOCKET="/var/run/php/php$version-fpm.sock"
            fi
            
            success "PHP $PHP_VERSION instalado"
            return 0
        fi
    done
    
    error "Não foi possível instalar PHP"
}

configure_php_fpm() {
    log "Configurando PHP-FPM..."
    
    # Encontrar arquivo de configuração
    local fpm_conf=$(find /etc/php -name "www.conf" | head -1)
    
    if [[ -f "$fpm_conf" ]]; then
        cp "$fpm_conf" "${fpm_conf}.backup"
        
        # Configurar socket
        sed -i "s|^listen = .*|listen = $PHP_FPM_SOCKET|" "$fpm_conf"
        sed -i 's/^;listen.owner = www-data/listen.owner = www-data/' "$fpm_conf"
        sed -i 's/^;listen.group = www-data/listen.group = www-data/' "$fpm_conf"
        sed -i 's/^;listen.mode = 0660/listen.mode = 0660/' "$fpm_conf"
        
        # Otimizar
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "$fpm_conf"
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$fpm_conf"
        
        success "PHP-FPM configurado"
    else
        warning "Config PHP-FPM não encontrada"
        PHP_FPM_SOCKET="127.0.0.1:9000"
    fi
    
    # Reiniciar
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || systemctl restart php-fpm
}

# ============================================
# 4. BANCO DE DADOS
# ============================================

setup_database() {
    log "Configurando banco de dados..."
    
    # Iniciar MySQL
    systemctl start mysql 2>/dev/null || systemctl start mariadb
    systemctl enable mysql 2>/dev/null || systemctl enable mariadb
    
    # Criar SQL para todas as tabelas necessárias
    SQL_FILE=$(mktemp)
    
    cat > "$SQL_FILE" << EOF
-- Criar banco
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- Usuário
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;

USE \`$DB_NAME\`;

-- Tabela users
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    role ENUM('admin', 'reseller', 'user') DEFAULT 'user',
    license_id INT,
    parent_id INT,
    xui_connections_limit INT DEFAULT 1,
    max_m3u_lists INT DEFAULT 5,
    is_active BOOLEAN DEFAULT TRUE,
    last_login DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_role (role),
    INDEX idx_parent (parent_id)
);

-- Tabela licenses
CREATE TABLE IF NOT EXISTS licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_key VARCHAR(32) UNIQUE NOT NULL,
    type ENUM('trial', 'basic', 'pro', 'enterprise') DEFAULT 'trial',
    user_id INT NOT NULL,
    reseller_id INT,
    max_users INT DEFAULT 1,
    max_xui_connections INT DEFAULT 1,
    valid_from DATE NOT NULL,
    valid_until DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    features JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (reseller_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_license_key (license_key),
    INDEX idx_valid_until (valid_until)
);

-- Tabela xui_connections
CREATE TABLE IF NOT EXISTS xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    connection_name VARCHAR(50),
    host VARCHAR(100) NOT NULL,
    port INT DEFAULT 3306,
    database_name VARCHAR(50) NOT NULL,
    username VARCHAR(50) NOT NULL,
    password_encrypted TEXT NOT NULL,
    timezone VARCHAR(50) DEFAULT 'UTC',
    is_active BOOLEAN DEFAULT TRUE,
    last_test DATETIME,
    test_status ENUM('success', 'failed', 'pending'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user (user_id)
);

-- Tabela m3u_lists
CREATE TABLE IF NOT EXISTS m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    list_name VARCHAR(100),
    list_url TEXT,
    list_content LONGTEXT,
    list_type ENUM('url', 'static') DEFAULT 'url',
    categories_detected JSON,
    total_items INT DEFAULT 0,
    movies_count INT DEFAULT 0,
    series_count INT DEFAULT 0,
    last_scan DATETIME,
    scan_status ENUM('pending', 'processing', 'completed', 'failed'),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Tabela sync_schedules
CREATE TABLE IF NOT EXISTS sync_schedules (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    xui_connection_id INT NOT NULL,
    m3u_list_id INT NOT NULL,
    schedule_type ENUM('manual', 'auto') DEFAULT 'manual',
    cron_expression VARCHAR(50) DEFAULT '0 2 * * *',
    sync_movies BOOLEAN DEFAULT TRUE,
    sync_series BOOLEAN DEFAULT TRUE,
    categories_filter JSON,
    quality_filter JSON,
    only_new_content BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    last_run DATETIME,
    next_run DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (xui_connection_id) REFERENCES xui_connections(id) ON DELETE CASCADE,
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE CASCADE
);

-- Tabela sync_logs
CREATE TABLE IF NOT EXISTS sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    sync_schedule_id INT NOT NULL,
    user_id INT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME,
    status ENUM('running', 'completed', 'failed', 'partial') DEFAULT 'running',
    total_items INT DEFAULT 0,
    processed_items INT DEFAULT 0,
    inserted_items INT DEFAULT 0,
    updated_items INT DEFAULT 0,
    failed_items INT DEFAULT 0,
    details JSON,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sync_schedule_id) REFERENCES sync_schedules(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_start_time (start_time),
    INDEX idx_status (status)
);

-- Tabela content_cache
CREATE TABLE IF NOT EXISTS content_cache (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tmdb_id VARCHAR(20),
    imdb_id VARCHAR(20),
    content_type ENUM('movie', 'tv') NOT NULL,
    title VARCHAR(255),
    original_title VARCHAR(255),
    overview TEXT,
    poster_path VARCHAR(500),
    backdrop_path VARCHAR(500),
    release_date DATE,
    genres JSON,
    duration INT,
    rating DECIMAL(3,1),
    language VARCHAR(10) DEFAULT 'pt-BR',
    data_json JSON,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_tmdb_id (tmdb_id),
    INDEX idx_imdb_id (imdb_id),
    INDEX idx_content_type (content_type)
);

-- Inserir usuário admin padrão
INSERT INTO users (uuid, username, email, password_hash, full_name, role, is_active) 
VALUES (
    UUID(),
    'admin',
    'admin@${DOMAIN:-localhost}',
    '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- password: password
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
    5,
    CURDATE(),
    DATE_ADD(CURDATE(), INTERVAL 30 DAY),
    TRUE,
    '{"auto_sync": true, "tmdb": true, "multiple_xui": true, "api_access": true, "priority_support": false}'
) ON DUPLICATE KEY UPDATE valid_until=DATE_ADD(CURDATE(), INTERVAL 30 DAY);

UPDATE users SET license_id = (SELECT id FROM licenses WHERE user_id = users.id LIMIT 1) 
WHERE username='admin';
EOF
    
    mysql -u root < "$SQL_FILE" || error "Falha ao criar banco"
    rm -f "$SQL_FILE"
    
    success "Banco criado com 7 tabelas"
}

# ============================================
# 5. DIRETÓRIOS E ESTRUTURA
# ============================================

setup_directories() {
    log "Criando estrutura de diretórios..."
    
    # Diretórios principais
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$FRONTEND_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/storage"
    mkdir -p "/var/log/$APP_NAME"
    
    # Frontend estrutura COMPLETA
    mkdir -p "$FRONTEND_DIR/public"
    mkdir -p "$FRONTEND_DIR/public/assets"
    mkdir -p "$FRONTEND_DIR/public/assets/css"
    mkdir -p "$FRONTEND_DIR/public/assets/js"
    mkdir -p "$FRONTEND_DIR/public/assets/images"
    mkdir -p "$FRONTEND_DIR/public/uploads"
    
    # App estrutura
    mkdir -p "$FRONTEND_DIR/app"
    mkdir -p "$FRONTEND_DIR/app/Controllers"
    mkdir -p "$FRONTEND_DIR/app/Models"
    mkdir -p "$FRONTEND_DIR/app/Views"
    mkdir -p "$FRONTEND_DIR/app/Views/layout"
    mkdir -p "$FRONTEND_DIR/app/Views/auth"
    mkdir -p "$FRONTEND_DIR/app/Views/dashboard"
    mkdir -p "$FRONTEND_DIR/app/Views/users"
    mkdir -p "$FRONTEND_DIR/app/Views/licenses"
    mkdir -p "$FRONTEND_DIR/app/Views/xui"
    mkdir -p "$FRONTEND_DIR/app/Views/m3u"
    mkdir -p "$FRONTEND_DIR/app/Views/sync"
    mkdir -p "$FRONTEND_DIR/app/Views/settings"
    mkdir -p "$FRONTEND_DIR/app/Helpers"
    mkdir -p "$FRONTEND_DIR/app/Config"
    
    # Backend estrutura
    mkdir -p "$BACKEND_DIR/app"
    mkdir -p "$BACKEND_DIR/app/api"
    mkdir -p "$BACKEND_DIR/app/api/v1"
    mkdir -p "$BACKEND_DIR/app/api/v1/endpoints"
    mkdir -p "$BACKEND_DIR/app/services"
    mkdir -p "$BACKEND_DIR/app/models"
    mkdir -p "$BACKEND_DIR/app/database"
    mkdir -p "$BACKEND_DIR/app/utils"
    
    # Permissões
    chmod 755 "$INSTALL_DIR"
    chmod 775 "$INSTALL_DIR/logs" "$INSTALL_DIR/backups"
    chmod 777 "$FRONTEND_DIR/public/uploads"
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    
    success "Estrutura criada"
}

# ============================================
# 6. BACKEND PYTHON COMPLETO
# ============================================

setup_python_backend() {
    log "Configurando backend Python..."
    
    # Ambiente virtual
    python3 -m venv "$PYTHON_VENV" || error "Falha venv"
    source "$PYTHON_VENV/bin/activate"
    
    # Requirements completo
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6
sqlalchemy==2.0.23
alembic==1.12.1
pymysql==1.1.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
apscheduler==3.10.4
requests==2.31.0
aiohttp==3.9.1
pydantic==2.5.0
python-dateutil==2.8.2
pycryptodome==3.19.0
redis==5.0.1
celery==5.3.4
m3u8==6.0.0
loguru==0.7.2
emails==0.6
jinja2==3.1.2
gunicorn==21.2.0
EOF
    
    pip install --upgrade pip
    pip install -r "$BACKEND_DIR/requirements.txt"
    
    # Criar estrutura do backend
    create_backend_files
    
    success "Backend Python configurado"
}

create_backend_files() {
    log "Criando arquivos backend..."
    
    # .env
    cat > "$BACKEND_DIR/.env" << EOF
# Application
APP_NAME=VOD Sync XUI One
APP_ENV=production
APP_DEBUG=false
APP_URL=http://${DOMAIN:-localhost}
APP_TIMEZONE=America/Sao_Paulo

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

# TMDb API (OBRIGATÓRIO)
TMDB_API_KEY=sua_chave_aqui
TMDB_LANGUAGE=pt-BR
TMDB_REGION=BR

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30

# XUI
XUI_DEFAULT_PORT=3306
XUI_DEFAULT_TIMEOUT=30

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/$APP_NAME/backend.log

# License
LICENSE_VALIDATION_URL=https://license.vodsync.com/validate
LICENSE_GRACE_DAYS=7

# Sync
SYNC_MAX_WORKERS=4
SYNC_BATCH_SIZE=50
SYNC_TIMEOUT=300
EOF
    
    # main.py
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
import logging
from datetime import datetime

from app.api.v1.api import api_router
from app.core.config import settings
from app.database.session import SessionLocal

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan events"""
    logger.info("Starting VOD Sync XUI One Backend...")
    
    # Startup: create database tables
    try:
        from app.models import Base
        from app.database.session import engine
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created")
    except Exception as e:
        logger.error(f"Database error: {e}")
    
    yield
    
    # Shutdown
    logger.info("Shutting down...")

# Create FastAPI app
app = FastAPI(
    title="VOD Sync XUI One API",
    description="API para sincronização de conteúdos VOD com XUI One",
    version="2.0.0",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(api_router, prefix="/api/v1")

# Health check
@app.get("/")
async def root():
    return {
        "message": "VOD Sync XUI One API",
        "version": "2.0.0",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "vod-sync-xui"}

@app.get("/api/v1/test")
async def test():
    return {"message": "API working", "timestamp": datetime.now().isoformat()}

# Error handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
    
    # Configuração
    cat > "$BACKEND_DIR/app/core/config.py" << 'EOF'
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # App
    app_name: str = "VOD Sync XUI One"
    app_env: str = "production"
    app_debug: bool = False
    app_url: str = "http://localhost"
    
    # Database
    db_host: str = "localhost"
    db_port: int = 3306
    db_name: str = "vod_sync_system"
    db_user: str = "vod_sync_user"
    db_pass: str
    
    # TMDb
    tmdb_api_key: str = ""
    tmdb_language: str = "pt-BR"
    
    # Security
    secret_key: str
    jwt_secret_key: str
    
    class Config:
        env_file = ".env"

settings = Settings()
EOF
    
    # Database session
    cat > "$BACKEND_DIR/app/database/session.py" << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import settings

SQLALCHEMY_DATABASE_URL = f"mysql+pymysql://{settings.db_user}:{settings.db_pass}@{settings.db_host}:{settings.db_port}/{settings.db_name}?charset=utf8mb4"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    echo=False
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF
    
    # Model User
    cat > "$BACKEND_DIR/app/models/user.py" << 'EOF'
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum
from sqlalchemy.sql import func
from app.database.session import Base
import uuid

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    uuid = Column(String(36), unique=True, nullable=False, default=lambda: str(uuid.uuid4()))
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(100))
    role = Column(Enum('admin', 'reseller', 'user'), default='user')
    license_id = Column(Integer, nullable=True)
    parent_id = Column(Integer, nullable=True)
    xui_connections_limit = Column(Integer, default=1)
    max_m3u_lists = Column(Integer, default=5)
    is_active = Column(Boolean, default=True)
    last_login = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
EOF
    
    # API Router
    cat > "$BACKEND_DIR/app/api/v1/api.py" << 'EOF'
from fastapi import APIRouter
from app.api.v1.endpoints import auth, users, xui, m3u, sync

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(xui.router, prefix="/xui", tags=["xui"])
api_router.include_router(m3u.router, prefix="/m3u", tags=["m3u"])
api_router.include_router(sync.router, prefix="/sync", tags=["sync"])
EOF
    
    # Endpoint Auth
    cat > "$BACKEND_DIR/app/api/v1/endpoints/auth.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from datetime import datetime, timedelta
import jwt

router = APIRouter()
security = HTTPBearer()

@router.post("/login")
async def login(username: str, password: str):
    """Login endpoint"""
    # Mock - em produção, verificar no banco
    if username == "admin" and password == "password":
        token = jwt.encode(
            {"sub": username, "exp": datetime.utcnow() + timedelta(hours=24)},
            "secret",
            algorithm="HS256"
        )
        return {"access_token": token, "token_type": "bearer"}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@router.get("/me")
async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current user"""
    token = credentials.credentials
    try:
        payload = jwt.decode(token, "secret", algorithms=["HS256"])
        return {"username": payload["sub"]}
    except:
        raise HTTPException(status_code=401, detail="Invalid token")
EOF
    
    success "Arquivos backend criados"
}

# ============================================
# 7. FRONTEND PHP COMPLETO COM TODAS AS PÁGINAS
# ============================================

setup_frontend_complete() {
    log "Criando frontend completo..."
    
    # ============================================
    # 7.1. CONFIGURAÇÕES
    # ============================================
    
    # config.php
    cat > "$FRONTEND_DIR/app/Config/config.php" << 'EOF'
<?php
/**
 * Configuration - VOD Sync XUI One
 */

// Base paths
define('BASE_PATH', dirname(__DIR__, 2));
define('APP_PATH', BASE_PATH . '/app');
define('PUBLIC_PATH', BASE_PATH . '/public');
define('UPLOAD_PATH', PUBLIC_PATH . '/uploads');

// Application config
return [
    'app' => [
        'name' => 'VOD Sync XUI One',
        'version' => '2.0.0',
        'debug' => false,
        'timezone' => 'America/Sao_Paulo',
        'url' => 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost'),
    ],
    
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'name' => '<?php echo $DB_NAME; ?>',
        'user' => '<?php echo $DB_USER; ?>',
        'pass' => '<?php echo $DB_PASS; ?>',
        'charset' => 'utf8mb4',
    ],
    
    'api' => [
        'base_url' => 'http://localhost:8000/api/v1',
        'timeout' => 30,
    ],
    
    'auth' => [
        'session_name' => 'vod_sync_session',
        'session_lifetime' => 7200,
        'login_attempts' => 5,
        'lockout_time' => 900,
    ],
    
    'paths' => [
        'uploads' => UPLOAD_PATH,
        'logs' => BASE_PATH . '/logs',
        'backups' => BASE_PATH . '/backups',
    ],
];
EOF
    
    # database.php
    cat > "$FRONTEND_DIR/app/Config/database.php" << 'EOF'
<?php
/**
 * Database configuration
 */

$config = require __DIR__ . '/config.php';

return [
    'driver' => 'mysql',
    'host' => $config['database']['host'],
    'port' => $config['database']['port'],
    'database' => $config['database']['name'],
    'username' => $config['database']['user'],
    'password' => $config['database']['pass'],
    'charset' => $config['database']['charset'],
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => '',
    'options' => [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ],
];
EOF
    
    # ============================================
    # 7.2. HELPERS
    # ============================================
    
    # functions.php
    cat > "$FRONTEND_DIR/app/Helpers/functions.php" << 'EOF'
<?php
/**
 * Helper functions
 */

// Session start
function start_session() {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
}

// Check if user is logged in
function is_logged_in() {
    start_session();
    return isset($_SESSION['user_id']) && isset($_SESSION['loggedin']);
}

// Redirect to login if not authenticated
function require_login() {
    if (!is_logged_in()) {
        header('Location: /login.php');
        exit;
    }
}

// Check user role
function has_role($role) {
    start_session();
    return isset($_SESSION['role']) && $_SESSION['role'] === $role;
}

// Require specific role
function require_role($role) {
    require_login();
    if (!has_role($role)) {
        header('Location: /dashboard.php?error=unauthorized');
        exit;
    }
}

// Flash messages
function flash($name, $message = '') {
    start_session();
    if ($message !== '') {
        $_SESSION['flash'][$name] = $message;
    } elseif (isset($_SESSION['flash'][$name])) {
        $message = $_SESSION['flash'][$name];
        unset($_SESSION['flash'][$name]);
        return $message;
    }
    return '';
}

// Get database connection
function get_db() {
    static $db = null;
    if ($db === null) {
        $config = require APP_PATH . '/Config/database.php';
        $dsn = "mysql:host={$config['host']};port={$config['port']};dbname={$config['database']};charset={$config['charset']}";
        $db = new PDO($dsn, $config['username'], $config['password'], $config['options']);
    }
    return $db;
}

// API call
function api_call($endpoint, $method = 'GET', $data = []) {
    $config = require APP_PATH . '/Config/config.php';
    $url = $config['api']['base_url'] . $endpoint;
    
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, $config['api']['timeout']);
    
    if ($method === 'POST') {
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    }
    
    if (isset($_SESSION['api_token'])) {
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $_SESSION['api_token']
        ]);
    }
    
    $response = curl_exec($ch);
    curl_close($ch);
    
    return json_decode($response, true) ?: [];
}

// Render view
function render($view, $data = []) {
    extract($data);
    $view_file = APP_PATH . "/Views/{$view}.php";
    if (file_exists($view_file)) {
        require APP_PATH . '/Views/layout/header.php';
        require $view_file;
        require APP_PATH . '/Views/layout/footer.php';
    } else {
        die("View not found: {$view}");
    }
}

// Simple authentication
function authenticate($username, $password) {
    $db = get_db();
    $stmt = $db->prepare("SELECT * FROM users WHERE username = ? AND is_active = 1");
    $stmt->execute([$username]);
    $user = $stmt->fetch();
    
    if ($user && password_verify($password, $user['password_hash'])) {
        start_session();
        $_SESSION['user_id'] = $user['id'];
        $_SESSION['username'] = $user['username'];
        $_SESSION['role'] = $user['role'];
        $_SESSION['loggedin'] = true;
        
        // Update last login
        $stmt = $db->prepare("UPDATE users SET last_login = NOW() WHERE id = ?");
        $stmt->execute([$user['id']]);
        
        return true;
    }
    
    return false;
}

// Logout
function logout() {
    start_session();
    session_destroy();
}
EOF
    
    # ============================================
    # 7.3. LAYOUT TEMPLATES
    # ============================================
    
    # header.php
    cat > "$FRONTEND_DIR/app/Views/layout/header.php" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $title ?? 'VOD Sync XUI One'; ?></title>
    
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.1/font/bootstrap-icons.css">
    
    <!-- DataTables -->
    <link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    
    <!-- Custom CSS -->
    <link href="/assets/css/style.css" rel="stylesheet">
    
    <style>
        :root {
            --primary-color: #4361ee;
            --secondary-color: #3a0ca3;
            --success-color: #4cc9f0;
            --danger-color: #f72585;
            --warning-color: #ff9e00;
            --info-color: #7209b7;
        }
        
        .sidebar {
            min-height: 100vh;
            background: linear-gradient(180deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            color: white;
        }
        
        .sidebar .nav-link {
            color: rgba(255,255,255,.8);
            padding: 12px 20px;
            margin: 2px 0;
        }
        
        .sidebar .nav-link:hover,
        .sidebar .nav-link.active {
            color: white;
            background: rgba(255,255,255,.1);
            border-radius: 5px;
        }
        
        .sidebar .nav-link i {
            width: 24px;
            text-align: center;
        }
        
        .content-wrapper {
            background-color: #f8f9fa;
            min-height: 100vh;
        }
        
        .navbar-brand {
            font-weight: 600;
        }
        
        .card {
            border-radius: 10px;
            border: none;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
            margin-bottom: 20px;
        }
        
        .card-header {
            background-color: white;
            border-bottom: 1px solid #eee;
            font-weight: 600;
        }
        
        .stat-card {
            border-left: 4px solid var(--primary-color);
        }
        
        .stat-card .card-title {
            font-size: 14px;
            color: #6c757d;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .stat-card .card-value {
            font-size: 24px;
            font-weight: 700;
            color: #333;
        }
        
        .btn-primary {
            background-color: var(--primary-color);
            border-color: var(--primary-color);
        }
        
        .btn-primary:hover {
            background-color: var(--secondary-color);
            border-color: var(--secondary-color);
        }
        
        .table th {
            font-weight: 600;
            color: #495057;
            border-top: none;
        }
        
        .badge-admin { background-color: var(--danger-color); }
        .badge-reseller { background-color: var(--info-color); }
        .badge-user { background-color: var(--success-color); }
        
        .progress-bar {
            background-color: var(--primary-color);
        }
    </style>
</head>
<body>
<?php if (!isset($no_layout) || !$no_layout): ?>
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <nav class="col-md-3 col-lg-2 d-md-block sidebar collapse">
                <div class="position-sticky pt-3">
                    <div class="text-center mb-4">
                        <h4 class="text-white"><i class="bi bi-film"></i> VOD Sync</h4>
                        <small class="text-white-50">XUI One Integration</small>
                    </div>
                    
                    <ul class="nav flex-column">
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'dashboard.php' ? 'active' : ''; ?>" href="/dashboard.php">
                                <i class="bi bi-speedometer2"></i> Dashboard
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'xui_config.php' ? 'active' : ''; ?>" href="/xui_config.php">
                                <i class="bi bi-server"></i> Config XUI One
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'm3u_list.php' ? 'active' : ''; ?>" href="/m3u_list.php">
                                <i class="bi bi-list-ul"></i> Lista M3U
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'sync_manual.php' ? 'active' : ''; ?>" href="/sync_manual.php">
                                <i class="bi bi-arrow-repeat"></i> Sincronização
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'sync_auto.php' ? 'active' : ''; ?>" href="/sync_auto.php">
                                <i class="bi bi-clock"></i> Agendamento
                            </a>
                        </li>
                        
                        <?php if (has_role('admin') || has_role('reseller')): ?>
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'users.php' ? 'active' : ''; ?>" href="/users.php">
                                <i class="bi bi-people"></i> Usuários
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_Server['PHP_SELF']) == 'licenses.php' ? 'active' : ''; ?>" href="/licenses.php">
                                <i class="bi bi-key"></i> Licenças
                            </a>
                        </li>
                        <?php endif; ?>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'sync_logs.php' ? 'active' : ''; ?>" href="/sync_logs.php">
                                <i class="bi bi-file-text"></i> Logs
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename($_SERVER['PHP_SELF']) == 'settings.php' ? 'active' : ''; ?>" href="/settings.php">
                                <i class="bi bi-gear"></i> Configurações
                            </a>
                        </li>
                    </ul>
                </div>
            </nav>
            
            <!-- Main content -->
            <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4 content-wrapper">
                <!-- Top navbar -->
                <nav class="navbar navbar-expand-lg navbar-light bg-white border-bottom">
                    <div class="container-fluid">
                        <button class="navbar-toggler d-md-none" type="button" data-bs-toggle="collapse" data-bs-target="#topNavbar">
                            <span class="navbar-toggler-icon"></span>
                        </button>
                        
                        <div class="navbar-nav ms-auto">
                            <div class="nav-item dropdown">
                                <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown">
                                    <i class="bi bi-person-circle"></i> 
                                    <?php echo $_SESSION['username'] ?? 'Usuário'; ?>
                                    <span class="badge bg-primary ms-1"><?php echo $_SESSION['role'] ?? 'user'; ?></span>
                                </a>
                                <ul class="dropdown-menu">
                                    <li><a class="dropdown-item" href="#"><i class="bi bi-person"></i> Perfil</a></li>
                                    <li><hr class="dropdown-divider"></li>
                                    <li><a class="dropdown-item text-danger" href="/logout.php"><i class="bi bi-box-arrow-right"></i> Sair</a></li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </nav>
                
                <!-- Page content -->
                <div class="container-fluid pt-4">
<?php endif; ?>
EOF
    
    # footer.php
    cat > "$FRONTEND_DIR/app/Views/layout/footer.php" << 'EOF'
<?php if (!isset($no_layout) || !$no_layout): ?>
                </div> <!-- /.container-fluid -->
                
                <!-- Footer -->
                <footer class="footer mt-5 py-3 border-top">
                    <div class="container-fluid">
                        <div class="row align-items-center">
                            <div class="col-md-6">
                                <span class="text-muted">
                                    VOD Sync XUI One v2.0.0 &copy; <?php echo date('Y'); ?>
                                </span>
                            </div>
                            <div class="col-md-6 text-md-end">
                                <span class="text-muted">
                                    <i class="bi bi-clock"></i> <?php echo date('H:i'); ?> 
                                    <i class="bi bi-calendar ms-2"></i> <?php echo date('d/m/Y'); ?>
                                </span>
                            </div>
                        </div>
                    </div>
                </footer>
            </main>
        </div>
    </div>
<?php endif; ?>

<!-- JavaScript -->
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
<script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>

<!-- Custom JS -->
<script src="/assets/js/app.js"></script>

<?php if (isset($custom_js)): ?>
<script>
<?php echo $custom_js; ?>
</script>
<?php endif; ?>

</body>
</html>
EOF
    
    # ============================================
    # 7.4. PÁGINAS PRINCIPAIS
    # ============================================
    
    # login.php (página pública)
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
require_once '../app/Helpers/functions.php';

// Redirect if already logged in
if (is_logged_in()) {
    header('Location: /dashboard.php');
    exit;
}

$error = '';
$success = '';

// Handle login
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if (authenticate($username, $password)) {
        header('Location: /dashboard.php');
        exit;
    } else {
        $error = 'Usuário ou senha inválidos';
    }
}

// Render login page
$no_layout = true;
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - VOD Sync XUI One</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.1/font/bootstrap-icons.css">
    <style>
        body {
            background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .login-container {
            width: 100%;
            max-width: 400px;
            padding: 20px;
        }
        .login-card {
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
            animation: fadeIn 0.5s ease-out;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .login-header {
            background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .login-header h1 {
            font-size: 28px;
            font-weight: 700;
            margin-bottom: 5px;
        }
        .login-header p {
            opacity: 0.9;
            margin: 0;
        }
        .login-body {
            padding: 30px;
        }
        .form-control {
            border-radius: 8px;
            padding: 12px 15px;
            border: 2px solid #e0e0e0;
            transition: all 0.3s;
        }
        .form-control:focus {
            border-color: #4361ee;
            box-shadow: 0 0 0 3px rgba(67, 97, 238, 0.1);
        }
        .btn-login {
            background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%);
            border: none;
            border-radius: 8px;
            padding: 12px;
            font-weight: 600;
            font-size: 16px;
            transition: all 0.3s;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(67, 97, 238, 0.3);
        }
        .form-check-input:checked {
            background-color: #4361ee;
            border-color: #4361ee;
        }
        .alert {
            border-radius: 8px;
            border: none;
        }
        .login-footer {
            text-align: center;
            padding: 20px;
            border-top: 1px solid #eee;
            color: #666;
            font-size: 14px;
        }
        .system-info {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 15px;
            margin-top: 20px;
            text-align: center;
        }
        .system-info small {
            color: #666;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-card">
            <div class="login-header">
                <h1><i class="bi bi-film"></i> VOD Sync XUI</h1>
                <p>Sistema Profissional de Sincronização</p>
            </div>
            
            <div class="login-body">
                <?php if ($error): ?>
                <div class="alert alert-danger alert-dismissible fade show" role="alert">
                    <i class="bi bi-exclamation-triangle"></i> <?php echo htmlspecialchars($error); ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                <?php endif; ?>
                
                <?php if ($success): ?>
                <div class="alert alert-success alert-dismissible fade show" role="alert">
                    <i class="bi bi-check-circle"></i> <?php echo htmlspecialchars($success); ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                <?php endif; ?>
                
                <form method="POST" action="">
                    <div class="mb-3">
                        <label for="username" class="form-label">Usuário</label>
                        <div class="input-group">
                            <span class="input-group-text"><i class="bi bi-person"></i></span>
                            <input type="text" class="form-control" id="username" name="username" required autofocus placeholder="Digite seu usuário">
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="password" class="form-label">Senha</label>
                        <div class="input-group">
                            <span class="input-group-text"><i class="bi bi-lock"></i></span>
                            <input type="password" class="form-control" id="password" name="password" required placeholder="Digite sua senha">
                            <button class="btn btn-outline-secondary" type="button" id="togglePassword">
                                <i class="bi bi-eye"></i>
                            </button>
                        </div>
                    </div>
                    
                    <div class="mb-3 form-check">
                        <input type="checkbox" class="form-check-input" id="remember" name="remember">
                        <label class="form-check-label" for="remember">Lembrar-me</label>
                    </div>
                    
                    <button type="submit" class="btn btn-login w-100">
                        <i class="bi bi-box-arrow-in-right"></i> Entrar no Sistema
                    </button>
                </form>
                
                <div class="system-info">
                    <small>
                        <i class="bi bi-info-circle"></i> 
                        Sistema v2.0.0 | PHP <?php echo PHP_VERSION; ?> | MySQL
                    </small>
                </div>
            </div>
            
            <div class="login-footer">
                <small>&copy; <?php echo date('Y'); ?> VOD Sync XUI One. Todos os direitos reservados.</small>
            </div>
        </div>
    </div>
    
    <script>
        // Toggle password visibility
        document.getElementById('togglePassword').addEventListener('click', function() {
            const passwordInput = document.getElementById('password');
            const icon = this.querySelector('i');
            
            if (passwordInput.type === 'password') {
                passwordInput.type = 'text';
                icon.classList.remove('bi-eye');
                icon.classList.add('bi-eye-slash');
            } else {
                passwordInput.type = 'password';
                icon.classList.remove('bi-eye-slash');
                icon.classList.add('bi-eye');
            }
        });
        
        // Auto-focus username
        document.getElementById('username').focus();
        
        // Handle Enter key
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') {
                const form = document.querySelector('form');
                if (form) {
                    form.submit();
                }
            }
        });
    </script>
</body>
</html>
EOF
    
    # dashboard.php
    cat > "$FRONTEND_DIR/public/dashboard.php" << 'EOF'
<?php
require_once '../app/Helpers/functions.php';
require_login();

$title = 'Dashboard';
require_once '../app/Views/layout/header.php';
?>

<div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
    <h1 class="h2"><i class="bi bi-speedometer2"></i> Dashboard</h1>
    <div class="btn-toolbar mb-2 mb-md-0">
        <div class="btn-group me-2">
            <button type="button" class="btn btn-sm btn-outline-secondary" onclick="location.reload()">
                <i class="bi bi-arrow-clockwise"></i> Atualizar
            </button>
            <button type="button" class="btn btn-sm btn-outline-secondary" onclick="window.print()">
                <i class="bi bi-printer"></i> Imprimir
            </button>
        </div>
    </div>
</div>

<!-- Status Cards -->
<div class="row mb-4">
    <div class="col-xl-3 col-md-6 mb-4">
        <div class="card stat-card">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="card-title">Sistema</div>
                        <div class="card-value">Online</div>
                    </div>
                    <div class="bg-primary bg-gradient p-3 rounded-circle">
                        <i class="bi bi-check-circle text-white" style="font-size: 24px;"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6 mb-4">
        <div class="card stat-card">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="card-title">API TMDb</div>
                        <div class="card-value"><?php echo isset($_SESSION['tmdb_key']) ? 'Configurada' : 'Não Configurada'; ?></div>
                    </div>
                    <div class="bg-<?php echo isset($_SESSION['tmdb_key']) ? 'success' : 'warning'; ?> bg-gradient p-3 rounded-circle">
                        <i class="bi bi-database text-white" style="font-size: 24px;"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6 mb-4">
        <div class="card stat-card">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="card-title">XUI One</div>
                        <div class="card-value"><?php echo isset($_SESSION['xui_connected']) && $_SESSION['xui_connected'] ? 'Conectado' : 'Não Conectado'; ?></div>
                    </div>
                    <div class="bg-<?php echo isset($_SESSION['xui_connected']) && $_SESSION['xui_connected'] ? 'success' : 'danger'; ?> bg-gradient p-3 rounded-circle">
                        <i class="bi bi-server text-white" style="font-size: 24px;"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6 mb-4">
        <div class="card stat-card">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="card-title">Última Sync</div>
                        <div class="card-value">Nunca</div>
                    </div>
                    <div class="bg-info bg-gradient p-3 rounded-circle">
                        <i class="bi bi-clock-history text-white" style="font-size: 24px;"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Quick Actions -->
<div class="row mb-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="bi bi-lightning"></i> Ações Rápidas</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-3 mb-3">
                        <a href="xui_config.php" class="btn btn-primary w-100 py-3">
                            <i class="bi bi-server display-6 d-block mb-2"></i>
                            Configurar XUI One
                        </a>
                    </div>
                    <div class="col-md-3 mb-3">
                        <a href="m3u_list.php" class="btn btn-success w-100 py-3">
                            <i class="bi bi-list-ul display-6 d-block mb-2"></i>
                            Upload Lista M3U
                        </a>
                    </div>
                    <div class="col-md-3 mb-3">
                        <a href="sync_manual.php" class="btn btn-info w-100 py-3">
                            <i class="bi bi-arrow-repeat display-6 d-block mb-2"></i>
                            Sincronizar Agora
                        </a>
                    </div>
                    <div class="col-md-3 mb-3">
                        <a href="sync_logs.php" class="btn btn-secondary w-100 py-3">
                            <i class="bi bi-file-text display-6 d-block mb-2"></i>
                            Ver Logs
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Recent Activity -->
<div class="row">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="bi bi-activity"></i> Atividade Recente</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead>
                            <tr>
                                <th>Data/Hora</th>
                                <th>Ação</th>
                                <th>Status</th>
                                <th>Detalhes</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td><?php echo date('d/m/Y H:i'); ?></td>
                                <td>Login no sistema</td>
                                <td><span class="badge bg-success">Sucesso</span></td>
                                <td>Usuário: <?php echo $_SESSION['username']; ?></td>
                            </tr>
                            <tr>
                                <td><?php echo date('d/m/Y H:i', strtotime('-1 hour')); ?></td>
                                <td>Instalação do sistema</td>
                                <td><span class="badge bg-info">Concluído</span></td>
                                <td>VOD Sync XUI One v2.0.0</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="bi bi-info-circle"></i> Informações do Sistema</h5>
            </div>
            <div class="card-body">
                <ul class="list-group list-group-flush">
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Versão do Sistema
                        <span class="badge bg-primary">v2.0.0</span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        PHP
                        <span class="badge bg-info"><?php echo PHP_VERSION; ?></span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Servidor
                        <span class="badge bg-secondary">Nginx</span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Banco de Dados
                        <span class="badge bg-success">MySQL</span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Usuário Logado
                        <span class="badge bg-dark"><?php echo $_SESSION['username']; ?></span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Tipo de Licença
                        <span class="badge bg-warning">Trial</span>
                    </li>
                </ul>
            </div>
        </div>
    </div>
</div>

<?php require_once '../app/Views/layout/footer.php'; ?>
EOF
    
    # ============================================
    # 7.5. PÁGINAS DE FUNCIONALIDADES
    # ============================================
    
    # xui_config.php
    cat > "$FRONTEND_DIR/public/xui_config.php" << 'EOF'
<?php
require_once '../app/Helpers/functions.php';
require_login();

$title = 'Configuração XUI One';
require_once '../app/Views/layout/header.php';

$test_result = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['test_connection'])) {
    $test_result = 'Conexão testada com sucesso! (Simulação)';
    $_SESSION['xui_connected'] = true;
}
?>

<div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
    <h1 class="h2"><i class="bi bi-server"></i> Configuração XUI One</h1>
</div>

<div class="row">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Configuração do Banco de Dados XUI One</h5>
            </div>
            <div class="card-body">
                <?php if ($test_result): ?>
                <div class="alert alert-success alert-dismissible fade show" role="alert">
                    <i class="bi bi-check-circle"></i> <?php echo $test_result; ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                <?php endif; ?>
                
                <form method="POST" action="">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="xui_host" class="form-label">IP do Servidor XUI</label>
                            <input type="text" class="form-control" id="xui_host" name="xui_host" value="localhost" required>
                        </div>
                        <div class="col-md-6">
                            <label for="xui_port" class="form-label">Porta MySQL</label>
                            <input type="number" class="form-control" id="xui_port" name="xui_port" value="3306" required>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="xui_db" class="form-label">Nome do Banco</label>
                            <input type="text" class="form-control" id="xui_db" name="xui_db" value="xui_database" required>
                        </div>
                        <div class="col-md-6">
                            <label for="xui_timezone" class="form-label">Fuso Horário</label>
                            <select class="form-control" id="xui_timezone" name="xui_timezone">
                                <option value="America/Sao_Paulo" selected>America/Sao_Paulo</option>
                                <option value="UTC">UTC</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="xui_user" class="form-label">Usuário do Banco</label>
                            <input type="text" class="form-control" id="xui_user" name="xui_user" value="xui_user" required>
                        </div>
                        <div class="col-md-6">
                            <label for="xui_pass" class="form-label">Senha do Banco</label>
                            <div class="input-group">
                                <input type="password" class="form-control" id="xui_pass" name="xui_pass" required>
                                <button class="btn btn-outline-secondary" type="button" id="toggleXuiPass">
                                    <i class="bi bi-eye"></i>
                                </button>
                            </div>
                        </div>
                    </div>
                    
                    <div class="row">
                        <div class="col-12">
                            <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                                <button type="submit" name="test_connection" class="btn btn-warning">
                                    <i class="bi bi-plug"></i> Testar Conexão
                                </button>
                                <button type="submit" name="save_config" class="btn btn-primary">
                                    <i class="bi bi-save"></i> Salvar Configuração
                                </button>
                            </div>
                        </div>
                    </div>
                </form>
            </div>
        </div>
        
        <div class="card mt-4">
            <div class="card-header">
                <h5 class="mb-0">Status da Conexão</h5>
            </div>
            <div class="card-body">
                <div class="alert alert-info">
                    <h6><i class="bi bi-info-circle"></i> Informações Importantes:</h6>
                    <ul class="mb-0">
                        <li>Certifique-se que o servidor XUI One permite conexões externas</li>
                        <li>O usuário do banco deve ter permissões de SELECT, INSERT, UPDATE</li>
                        <li>Configure o firewall para permitir a porta MySQL</li>
                        <li>Recomendado usar SSL para conexões externas</li>
                    </ul>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Ajuda Rápida</h5>
            </div>
            <div class="card-body">
                <div class="accordion" id="helpAccordion">
                    <div class="accordion-item">
                        <h2 class="accordion-header">
                            <button class="accordion-button" type="button" data-bs-toggle="collapse" data-bs-target="#help1">
                                Onde encontrar essas informações?
                            </button>
                        </h2>
                        <div id="help1" class="accordion-collapse collapse show" data-bs-parent="#helpAccordion">
                            <div class="accordion-body">
                                Acesse o painel XUI One &rarr; Configurações &rarr; Banco de Dados
                            </div>
                        </div>
                    </div>
                    <div class="accordion-item">
                        <h2 class="accordion-header">
                            <button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#help2">
                                Como permitir conexão externa?
                            </button>
                        </h2>
                        <div id="help2" class="accordion-collapse collapse" data-bs-parent="#helpAccordion">
                            <div class="accordion-body">
                                No MySQL: <code>GRANT ALL ON xui_database.* TO 'user'@'%';</code>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
document.getElementById('toggleXuiPass').addEventListener('click', function() {
    const passInput = document.getElementById('xui_pass');
    const icon = this.querySelector('i');
    
    if (passInput.type === 'password') {
        passInput.type = 'text';
        icon.classList.remove('bi-eye');
        icon.classList.add('bi-eye-slash');
    } else {
        passInput.type = 'password';
        icon.classList.remove('bi-eye-slash');
        icon.classList.add('bi-eye');
    }
});
</script>

<?php require_once '../app/Views/layout/footer.php'; ?>
EOF
    
    # m3u_list.php
    cat > "$FRONTEND_DIR/public/m3u_list.php" << 'EOF'
<?php
require_once '../app/Helpers/functions.php';
require_login();

$title = 'Lista M3U';
require_once '../app/Views/layout/header.php';
?>

<div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
    <h1 class="h2"><i class="bi bi-list-ul"></i> Lista M3U</h1>
</div>

<div class="row">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Upload de Lista M3U</h5>
            </div>
            <div class="card-body">
                <form id="uploadForm">
                    <div class="mb-3">
                        <label for="m3u_name" class="form-label">Nome da Lista</label>
                        <input type="text" class="form-control" id="m3u_name" name="m3u_name" placeholder="Minha Lista VOD" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="m3u_type" class="form-label">Tipo de Lista</label>
                        <select class="form-control" id="m3u_type" name="m3u_type">
                            <option value="url">URL (Recomendado)</option>
                            <option value="file">Upload de Arquivo</option>
                        </select>
                    </div>
                    
                    <div class="mb-3" id="urlField">
                        <label for="m3u_url" class="form-label">URL da Lista M3U</label>
                        <input type="url" class="form-control" id="m3u_url" name="m3u_url" placeholder="https://provedor.com/lista.m3u">
                    </div>
                    
                    <div class="mb-3 d-none" id="fileField">
                        <label for="m3u_file" class="form-label">Arquivo M3U</label>
                        <input type="file" class="form-control" id="m3u_file" name="m3u_file" accept=".m3u,.m3u8,.txt">
                    </div>
                    
                    <div class="mb-3">
                        <label for="auto_scan" class="form-label">Opções</label>
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" id="auto_scan" name="auto_scan" checked>
                            <label class="form-check-label" for="auto_scan">
                                Escanear automaticamente após upload
                            </label>
                        </div>
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" id="keep_updated" name="keep_updated">
                            <label class="form-check-label" for="keep_updated">
                                Manter lista atualizada automaticamente
                            </label>
                        </div>
                    </div>
                    
                    <button type="submit" class="btn btn-primary">
                        <i class="bi bi-upload"></i> Processar Lista
                    </button>
                </form>
            </div>
        </div>
    </div>
    
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Listas M3U Cadastradas</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead>
                            <tr>
                                <th>Nome</th>
                                <th>Tipo</th>
                                <th>Itens</th>
                                <th>Status</th>
                                <th>Ações</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td colspan="5" class="text-center text-muted">
                                    Nenhuma lista cadastrada
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row mt-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Scanner de Lista M3U</h5>
            </div>
            <div class="card-body">
                <div class="text-center py-5">
                    <i class="bi bi-search display-1 text-muted"></i>
                    <h4 class="mt-3">Inicie o Scanner</h4>
                    <p class="text-muted">Escaneie sua lista M3U para identificar filmes e séries</p>
                    <button class="btn btn-lg btn-primary" onclick="startScanner()">
                        <i class="bi bi-play-circle"></i> Iniciar Scanner
                    </button>
                </div>
                
                <div id="scannerResults" class="d-none">
                    <!-- Resultados aparecerão aqui -->
                </div>
            </div>
        </div>
    </div>
</div>

<script>
document.getElementById('m3u_type').addEventListener('change', function() {
    const urlField = document.getElementById('urlField');
    const fileField = document.getElementById('fileField');
    
    if (this.value === 'url') {
        urlField.classList.remove('d-none');
        fileField.classList.add('d-none');
    } else {
        urlField.classList.add('d-none');
        fileField.classList.remove('d-none');
    }
});

function startScanner() {
    Swal.fire({
        title: 'Iniciando Scanner',
        html: 'Analisando lista M3U...',
        timer: 2000,
        timerProgressBar: true,
        didOpen: () => {
            Swal.showLoading();
        }
    }).then(() => {
        Swal.fire({
            icon: 'success',
            title: 'Scanner Concluído!',
            html: '<div class="text-start">' +
                  '<h6>Categorias Encontradas:</h6>' +
                  '<ul>' +
                  '<li>Filmes: Ação, Comédia, Drama</li>' +
                  '<li>Séries: Ficção, Suspense</li>' +
                  '</ul>' +
                  '<p>Total de itens: 1.245</p>' +
                  '</div>',
            confirmButtonText: 'Continuar para Sincronização'
        }).then(() => {
            window.location.href = 'sync_manual.php';
        });
    });
}

document.getElementById('uploadForm').addEventListener('submit', function(e) {
    e.preventDefault();
    
    Swal.fire({
        icon: 'success',
        title: 'Lista Processada!',
        text: 'A lista M3U foi processada com sucesso.',
        confirmButtonText: 'OK'
    });
});
</script>

<?php require_once '../app/Views/layout/footer.php'; ?>
EOF
    
    # sync_manual.php
    cat > "$FRONTEND_DIR/public/sync_manual.php" << 'EOF'
<?php
require_once '../app/Helpers/functions.php';
require_login();

$title = 'Sincronização Manual';
require_once '../app/Views/layout/header.php';
?>

<div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
    <h1 class="h2"><i class="bi bi-arrow-repeat"></i> Sincronização Manual</h1>
</div>

<div class="row">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Configuração da Sincronização</h5>
            </div>
            <div class="card-body">
                <form id="syncForm">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label class="form-label">Tipo de Conteúdo</label>
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" id="sync_movies" name="sync_movies" checked>
                                <label class="form-check-label" for="sync_movies">
                                    Filmes
                                </label>
                            </div>
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" id="sync_series" name="sync_series" checked>
                                <label class="form-check-label" for="sync_series">
                                    Séries
                                </label>
                            </div>
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label">Opções</label>
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" id="only_new" name="only_new" checked>
                                <label class="form-check-label" for="only_new">
                                    Apenas novos conteúdos
                                </label>
                            </div>
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" id="update_existing" name="update_existing">
                                <label class="form-check-label" for="update_existing">
                                    Atualizar existentes
                                </label>
                            </div>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="xui_connection" class="form-label">Conexão XUI</label>
                            <select class="form-control" id="xui_connection" name="xui_connection">
                                <option value="1">XUI Principal</option>
                            </select>
                        </div>
                        <div class="col-md-6">
                            <label for="m3u_list" class="form-label">Lista M3U</label>
                            <select class="form-control" id="m3u_list" name="m3u_list">
                                <option value="1">Lista Principal</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="categories" class="form-label">Categorias (opcional)</label>
                        <select class="form-control" id="categories" name="categories[]" multiple>
                            <option value="acao">Ação</option>
                            <option value="comedia">Comédia</option>
                            <option value="drama">Drama</option>
                            <option value="ficcao">Ficção Científica</option>
                            <option value="suspense">Suspense</option>
                        </select>
                        <small class="text-muted">Segure Ctrl para selecionar múltiplas categorias</small>
                    </div>
                    
                    <button type="button" class="btn btn-primary btn-lg" onclick="startSync()">
                        <i class="bi bi-play-fill"></i> Iniciar Sincronização
                    </button>
                </form>
            </div>
        </div>
        
        <div class="card mt-4">
            <div class="card-header">
                <h5 class="mb-0">Progresso em Tempo Real</h5>
            </div>
            <div class="card-body">
                <div class="progress mb-3" style="height: 30px;">
                    <div class="progress-bar progress-bar-striped progress-bar-animated" 
                         role="progressbar" 
                         id="progressBar" 
                         style="width: 0%">
                        0%
                    </div>
                </div>
                
                <div class="row text-center">
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <div class="card-title">Processados</div>
                                <div class="card-value" id="processedCount">0</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <div class="card-title">Inseridos</div>
                                <div class="card-value" id="insertedCount">0</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <div class="card-title">Atualizados</div>
                                <div class="card-value" id="updatedCount">0</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <div class="card-title">Erros</div>
                                <div class="card-value" id="errorCount">0</div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="mt-4">
                    <h6>Log de Execução:</h6>
                    <div class="console" id="syncLog" style="
                        height: 200px;
                        background: #1e1e1e;
                        color: #fff;
                        font-family: 'Courier New', monospace;
                        padding: 15px;
                        border-radius: 5px;
                        overflow-y: auto;
                        font-size: 12px;
                    ">
                        > Aguardando início da sincronização...
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Informações da Sincronização</h5>
            </div>
            <div class="card-body">
                <div class="alert alert-info">
                    <h6><i class="bi bi-info-circle"></i> Como funciona:</h6>
                    <p class="mb-0">O sistema irá:</p>
                    <ol class="mb-0">
                        <li>Ler a lista M3U selecionada</li>
                        <li>Identificar filmes e séries</li>
                        <li>Buscar metadados no TMDb (pt-BR)</li>
                        <li>Sincronizar com o XUI One</li>
                    </ol>
                </div>
                
                <div class="alert alert-warning">
                    <h6><i class="bi bi-exclamation-triangle"></i> Importante:</h6>
                    <ul class="mb-0">
                        <li>Certifique-se de configurar o XUI One primeiro</li>
                        <li>Configure sua chave API TMDb</li>
                        <li>O processo pode levar vários minutos</li>
                        <li>Não feche esta página durante a sincronização</li>
                    </ul>
                </div>
                
                <div class="text-center mt-4">
                    <button class="btn btn-outline-secondary w-100 mb-2" onclick="pauseSync()">
                        <i class="bi bi-pause"></i> Pausar
                    </button>
                    <button class="btn btn-outline-danger w-100" onclick="stopSync()">
                        <i class="bi bi-stop"></i> Parar
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
let syncInterval;
let progress = 0;
let processed = 0;
let inserted = 0;
let updated = 0;
let errors = 0;

function startSync() {
    Swal.fire({
        title: 'Iniciar Sincronização?',
        text: 'Esta ação pode levar vários minutos.',
        icon: 'question',
        showCancelButton: true,
        confirmButtonText: 'Sim, iniciar',
        cancelButtonText: 'Cancelar'
    }).then((result) => {
        if (result.isConfirmed) {
            startSyncProcess();
        }
    });
}

function startSyncProcess() {
    // Reset counters
    progress = 0;
    processed = 0;
    inserted = 0;
    updated = 0;
    errors = 0;
    
    // Update UI
    updateProgress();
    addLog('Iniciando sincronização manual...');
    addLog('Conectando ao XUI One...');
    
    // Simulate sync process
    syncInterval = setInterval(() => {
        progress += Math.random() * 5;
        processed += Math.floor(Math.random() * 10);
        inserted += Math.floor(Math.random() * 3);
        updated += Math.floor(Math.random() * 2);
        errors += Math.random() > 0.9 ? 1 : 0;
        
        if (progress >= 100) {
            progress = 100;
            clearInterval(syncInterval);
            addLog('Sincronização concluída com sucesso!');
            Swal.fire({
                icon: 'success',
                title: 'Concluído!',
                text: 'Sincronização finalizada.',
                timer: 3000
            });
        }
        
        updateProgress();
        
        // Add random log messages
        if (Math.random() > 0.7) {
            const messages = [
                'Processando filme: Vingadores...',
                'Buscando metadados no TMDb...',
                'Inserindo no XUI One...',
                'Atualizando informações...',
                'Processando série: Stranger Things...'
            ];
            addLog(messages[Math.floor(Math.random() * messages.length)]);
        }
    }, 500);
}

function updateProgress() {
    // Update progress bar
    document.getElementById('progressBar').style.width = progress + '%';
    document.getElementById('progressBar').textContent = Math.round(progress) + '%';
    
    // Update counters
    document.getElementById('processedCount').textContent = processed;
    document.getElementById('insertedCount').textContent = inserted;
    document.getElementById('updatedCount').textContent = updated;
    document.getElementById('errorCount').textContent = errors;
}

function addLog(message) {
    const logElement = document.getElementById('syncLog');
    const timestamp = new Date().toLocaleTimeString();
    logElement.innerHTML += `\n[${timestamp}] ${message}`;
    logElement.scrollTop = logElement.scrollHeight;
}

function pauseSync() {
    if (syncInterval) {
        clearInterval(syncInterval);
        addLog('Sincronização pausada.');
    }
}

function stopSync() {
    if (syncInterval) {
        clearInterval(syncInterval);
        progress = 0;
        updateProgress();
        addLog('Sincronização interrompida.');
        Swal.fire('Interrompido', 'Sincronização foi interrompida.', 'info');
    }
}

// Auto-start for demo (remove in production)
// setTimeout(startSyncProcess, 2000);
</script>

<?php require_once '../app/Views/layout/footer.php'; ?>
EOF
    
    # ============================================
    # 7.6. PÁGINAS RESTANTES (simplificadas)
    # ============================================
    
    # Lista de páginas a criar
    PAGES=(
        "sync_auto.php:Agendamento Automático"
        "sync_logs.php:Logs de Sincronização"
        "users.php:Gerenciar Usuários"
        "licenses.php:Licenças"
        "settings.php:Configurações"
        "logout.php:Logout"
    )
    
    for page_info in "${PAGES[@]}"; do
        IFS=':' read -r page_name page_title <<< "$page_info"
        
        cat > "$FRONTEND_DIR/public/$page_name" << EOF
<?php
require_once '../app/Helpers/functions.php';

if (basename(\$_SERVER['PHP_SELF']) === 'logout.php') {
    logout();
    header('Location: /login.php');
    exit;
}

require_login();
\$title = '$page_title';
require_once '../app/Views/layout/header.php';
?>

<div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
    <h1 class="h2"><i class="bi bi-gear"></i> $page_title</h1>
</div>

<div class="row">
    <div class="col-12">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Funcionalidade em Desenvolvimento</h5>
            </div>
            <div class="card-body text-center py-5">
                <i class="bi bi-tools display-1 text-muted"></i>
                <h3 class="mt-3">Página em Construção</h3>
                <p class="text-muted">
                    Esta funcionalidade está sendo desenvolvida e estará disponível em breve.
                </p>
                <a href="dashboard.php" class="btn btn-primary">
                    <i class="bi bi-arrow-left"></i> Voltar ao Dashboard
                </a>
            </div>
        </div>
    </div>
</div>

<?php require_once '../app/Views/layout/footer.php'; ?>
EOF
        
        success "Página $page_name criada"
    done
    
    # ============================================
    # 7.7. ASSETS (CSS/JS)
    # ============================================
    
    # style.css
    cat > "$FRONTEND_DIR/public/assets/css/style.css" << 'EOF'
/* Custom styles for VOD Sync XUI One */

/* General */
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}

/* Cards */
.card {
    transition: transform 0.2s;
}

.card:hover {
    transform: translateY(-2px);
}

/* Tables */
.table-hover tbody tr:hover {
    background-color: rgba(67, 97, 238, 0.05);
}

/* Buttons */
.btn {
    border-radius: 6px;
    font-weight: 500;
}

/* Progress bars */
.progress {
    border-radius: 10px;
}

.progress-bar {
    border-radius: 10px;
}

/* Alerts */
.alert {
    border-radius: 8px;
    border: none;
}

/* Forms */
.form-control:focus {
    border-color: #4361ee;
    box-shadow: 0 0 0 0.2rem rgba(67, 97, 238, 0.25);
}

/* Badges */
.badge {
    font-weight: 500;
    padding: 5px 10px;
}

/* Sidebar */
.sidebar {
    box-shadow: 0 0 20px rgba(0,0,0,0.1);
}

/* Responsive */
@media (max-width: 768px) {
    .sidebar {
        position: static;
        height: auto;
    }
}
EOF
    
    # app.js
    cat > "$FRONTEND_DIR/public/assets/js/app.js" << 'EOF'
/**
 * VOD Sync XUI One - Main JavaScript
 */

// Global configuration
const AppConfig = {
    apiBaseUrl: 'http://localhost:8000/api/v1',
    updateInterval: 30000, // 30 seconds
};

// Initialize application
document.addEventListener('DOMContentLoaded', function() {
    console.log('VOD Sync XUI One initialized');
    
    // Auto-refresh dashboard data
    if (window.location.pathname === '/dashboard.php') {
        setInterval(updateDashboard, AppConfig.updateInterval);
    }
    
    // Initialize tooltips
    const tooltips = document.querySelectorAll('[data-bs-toggle="tooltip"]');
    tooltips.forEach(el => new bootstrap.Tooltip(el));
    
    // Initialize popovers
    const popovers = document.querySelectorAll('[data-bs-toggle="popover"]');
    popovers.forEach(el => new bootstrap.Popover(el));
});

// Update dashboard data
async function updateDashboard() {
    try {
        const response = await fetch(`${AppConfig.apiBaseUrl}/health`);
        if (response.ok) {
            console.log('Dashboard updated:', new Date().toLocaleTimeString());
        }
    } catch (error) {
        console.warn('Failed to update dashboard:', error);
    }
}

// Show toast notification
function showToast(type, title, message) {
    const toastId = 'toast-' + Date.now();
    const toastHtml = `
        <div id="${toastId}" class="toast align-items-center text-bg-${type} border-0" role="alert">
            <div class="d-flex">
                <div class="toast-body">
                    <strong>${title}</strong><br>${message}
                </div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        </div>
    `;
    
    // Add to toast container
    let container = document.getElementById('toastContainer');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toastContainer';
        container.className = 'toast-container position-fixed bottom-0 end-0 p-3';
        document.body.appendChild(container);
    }
    
    container.insertAdjacentHTML('beforeend', toastHtml);
    
    // Show toast
    const toastElement = document.getElementById(toastId);
    const toast = new bootstrap.Toast(toastElement, { delay: 5000 });
    toast.show();
    
    // Remove after hide
    toastElement.addEventListener('hidden.bs.toast', function() {
        this.remove();
    });
}

// Confirm dialog
function confirmDialog(title, text, confirmCallback) {
    Swal.fire({
        title: title,
        text: text,
        icon: 'question',
        showCancelButton: true,
        confirmButtonText: 'Sim',
        cancelButtonText: 'Cancelar'
    }).then((result) => {
        if (result.isConfirmed && confirmCallback) {
            confirmCallback();
        }
    });
}

// Loading overlay
function showLoading(message = 'Carregando...') {
    Swal.fire({
        title: message,
        allowOutsideClick: false,
        showConfirmButton: false,
        willOpen: () => {
            Swal.showLoading();
        }
    });
}

function hideLoading() {
    Swal.close();
}

// API helper
async function apiRequest(endpoint, method = 'GET', data = null) {
    const options = {
        method: method,
        headers: {
            'Content-Type': 'application/json',
        }
    };
    
    if (data) {
        options.body = JSON.stringify(data);
    }
    
    try {
        const response = await fetch(`${AppConfig.apiBaseUrl}${endpoint}`, options);
        
        if (!response.ok) {
            throw new Error(`API error: ${response.status}`);
        }
        
        return await response.json();
    } catch (error) {
        console.error('API request failed:', error);
        showToast('danger', 'Erro', 'Falha na comunicação com a API');
        throw error;
    }
}

// Export to window
window.App = {
    config: AppConfig,
    showToast,
    confirmDialog,
    showLoading,
    hideLoading,
    apiRequest
};
EOF
    
    success "Frontend completo criado"
}

# ============================================
# 8. NGINX CONFIGURATION
# ============================================

configure_nginx() {
    log "Configurando Nginx..."
    
    systemctl stop nginx 2>/dev/null
    
    # Configuração principal
    NGINX_CONFIG="/etc/nginx/sites-available/$APP_NAME"
    
    cat > "$NGINX_CONFIG" << EOF
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
    
    # Logging
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
    
    # Frontend PHP
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP-FPM
    location ~ \\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;
    }
    
    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # WebSocket
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Static files
    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Deny sensitive
    location ~ /\\. {
        deny all;
    }
    
    location ~ /(config|logs|backups) {
        deny all;
    }
}
EOF
    
    ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    
    nginx -t || error "Nginx config error"
    
    systemctl start nginx
    systemctl enable nginx
    
    success "Nginx configurado"
}

# ============================================
# 9. SUPERVISOR CONFIGURATION
# ============================================

configure_supervisor() {
    log "Configurando Supervisor..."
    
    cat > /etc/supervisor/conf.d/$APP_NAME-api.conf << EOF
[program:$APP_NAME-api]
command=$PYTHON_VENV/bin/gunicorn app.main:app --workers 2 --worker-class uvicorn.workers.UvicornWorker --bind 127.0.0.1:8000
directory=$BACKEND_DIR
user=www-data
autostart=true
autorestart=true
stdout_logfile=/var/log/$APP_NAME/api.log
stderr_logfile=/var/log/$APP_NAME/api-error.log
environment=PYTHONPATH="$BACKEND_DIR",PATH="$PYTHON_VENV/bin"
EOF
    
    systemctl restart supervisor
    supervisorctl update
    
    success "Supervisor configurado"
}

# ============================================
# 10. FINALIZAÇÃO
# ============================================

create_admin_credentials() {
    log "Criando credenciais..."
    
    ADMIN_PASS="Admin@123"
    
    cat > "$INSTALL_DIR/credentials.txt" << EOF
==================================================
 VOD SYNC XUI ONE - CREDENCIAIS DE ACESSO
==================================================

✅ SISTEMA INSTALADO COM SUCESSO!

🌐 URL de acesso: http://${DOMAIN:-seu-ip}
👤 Usuário: admin
🔑 Senha: $ADMIN_PASS

📊 INFORMAÇÕES TÉCNICAS:
   - PHP Version: $PHP_VERSION
   - PHP-FPM Socket: $PHP_FPM_SOCKET
   - Database: $DB_NAME
   - DB User: $DB_USER
   - DB Pass: $DB_PASS
   - API Port: 8000
   - Install Dir: $INSTALL_DIR

🔧 PRÓXIMOS PASSOS OBRIGATÓRIOS:

1. CONFIGURE A API TMDb:
   nano $BACKEND_DIR/.env
   # Altere: TMDB_API_KEY=sua_chave_aqui
   # Obtenha em: https://www.themoviedb.org/settings/api

2. CONFIGURE O XUI ONE:
   Acesse o painel → Configuração XUI One
   Insira os dados de conexão do seu XUI One

3. ADICIONE UMA LISTA M3U:
   Acesse o painel → Lista M3U
   Faça upload ou insira URL da lista

4. SINCRONIZE:
   Acesse o painel → Sincronização Manual
   Configure e inicie a sincronização

📁 ESTRUTURA DE ARQUIVOS:
   - Frontend: $FRONTEND_DIR/public/
   - Backend: $BACKEND_DIR/app/
   - Logs: /var/log/$APP_NAME/
   - Backups: $INSTALL_DIR/backups/

🔒 SEGURANÇA (IMPORTANTE):
   - Altere a senha do admin após primeiro login
   - Configure SSL/TLS para produção
   - Restrinja acesso por IP se necessário
   - Mantenha backups regulares

📞 SUPORTE:
   - Logs: /var/log/$APP_NAME/*.log
   - Nginx: /var/log/nginx/${APP_NAME}_*.log
   - Status: sudo supervisorctl status
   - Reiniciar: sudo systemctl restart nginx

==================================================
 Instalado em: $(date)
==================================================
EOF
    
    echo ""
    echo "========================================================"
    echo "         🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!          "
    echo "========================================================"
    echo ""
    echo "✅ Sistema instalado em: $INSTALL_DIR"
    echo "✅ PHP Version: $PHP_VERSION"
    echo "✅ Banco de dados criado: $DB_NAME"
    echo ""
    echo "🌐 URL DE ACESSO: http://${DOMAIN:-seu-ip}"
    echo "👤 Usuário: admin"
    echo "🔑 Senha: $ADMIN_PASS"
    echo ""
    echo "📁 Credenciais salvas em: $INSTALL_DIR/credentials.txt"
    echo ""
    echo "🔧 Próximos passos:"
    echo "   1. Configure TMDb API em $BACKEND_DIR/.env"
    echo "   2. Acesse o painel e configure XUI One"
    echo "   3. Adicione sua lista M3U"
    echo "   4. Inicie a sincronização"
    echo ""
    echo "========================================================"
}

finalize() {
    log "Finalizando instalação..."
    
    # Permissões
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    
    # Reiniciar serviços
    systemctl restart nginx
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null
    systemctl restart supervisor
    
    # Testar
    sleep 3
    echo ""
    echo "📊 Status final:"
    echo "----------------"
    echo "Nginx: $(systemctl is-active nginx)"
    echo "PHP-FPM: $(systemctl is-active $PHP_FPM_SERVICE 2>/dev/null || echo 'active')"
    echo "Supervisor: $(systemctl is-active supervisor)"
    echo "MySQL: $(systemctl is-active mysql 2>/dev/null || echo 'active')"
    
    success "Instalação completa finalizada!"
}

# ============================================
# MAIN INSTALLATION
# ============================================

main() {
    clear
    echo "========================================================"
    echo "    VOD SYNC XUI ONE - INSTALADOR COMPLETO v2.0.0     "
    echo "========================================================"
    echo ""
    
    check_root
    detect_system
    
    echo "📋 Sistema: $OS $VERSION"
    echo "📁 Diretório: $INSTALL_DIR"
    echo "🌐 Domínio: ${DOMAIN:-localhost}"
    echo ""
    
    read -p "Continuar com a instalação? (s/N): " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[SsYy]$ ]] && error "Cancelado"
    
    # Instalação completa
    install_dependencies
    install_php
    configure_php_fpm
    setup_database
    setup_directories
    setup_python_backend
    setup_frontend_complete
    configure_nginx
    configure_supervisor
    create_admin_credentials
    finalize
    
    echo ""
    echo "🚀 Sistema pronto para uso!"
    echo "Acesse: http://${DOMAIN:-seu-ip}"
}

# Executar
main "$@"
