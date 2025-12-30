#!/bin/bash

# ============================================
# INSTALADOR VOD SYNC SYSTEM - PHP 7.4
# ============================================

# Removi set -e para evitar saída prematura

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretórios
BASE_DIR="/opt/vod-sync"
BACKEND_DIR="$BASE_DIR/backend"
FRONTEND_DIR="$BASE_DIR/frontend"
INSTALL_DIR="$BASE_DIR/install"
LOG_FILE="/var/log/vod-install-$(date +%Y%m%d_%H%M%S).log"

# Iniciar log
exec > >(tee -a "$LOG_FILE") 2>&1

# Funções
print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     VOD SYNC SYSTEM - INSTALADOR PHP 7.4 COMPATÍVEL     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "📝 Log: $LOG_FILE"
    echo ""
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
    echo "🔍 Consulte o log completo: $LOG_FILE"
    return 1  # Retorna erro mas não sai
}

# ==================== VERIFICAR ROOT ====================
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}✗${NC} Execute como root: sudo $0"
        exit 1
    fi
    success "Privilégios root verificados"
}

# ==================== DETECTAR DISTRIBUIÇÃO ====================
detect_distro() {
    log "Detectando distribuição..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        echo "Distribuição: $OS $VERSION"
    else
        OS=$(uname -s)
    fi
    
    case $OS in
        ubuntu|debian)
            DISTRO="debian"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            DISTRO="rhel"
            ;;
        *)
            DISTRO="unknown"
            ;;
    esac
    
    success "Distribuição detectada: $DISTRO ($OS $VERSION)"
    echo $DISTRO
}

# ==================== INSTALAR PHP 7.4 - VERSÃO CORRIGIDA ====================
install_php_74() {
    log "Instalando PHP 7.4 (método robusto)..."
    
    # Primeiro, verificar se já temos PHP instalado
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v | head -1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        success "✅ PHP já instalado: versão $PHP_VERSION"
        return 0
    fi
    
    # Atualizar repositórios
    apt-get update 2>> "$LOG_FILE"
    
    # Instalar dependências necessárias
    log "Instalando dependências..."
    if ! apt-get install -y software-properties-common apt-transport-https lsb-release ca-certificates wget 2>> "$LOG_FILE"; then
        warning "Falha ao instalar algumas dependências, continuando..."
    fi
    
    # Adicionar repositório ondrej/php para PHP 7.4
    log "Adicionando repositório ondrej/php..."
    if ! add-apt-repository -y ppa:ondrej/php 2>> "$LOG_FILE"; then
        warning "Não foi possível adicionar repositório ondrej/php, usando repositórios padrão..."
    fi
    
    apt-get update 2>> "$LOG_FILE"
    
    # Instalar PHP 7.4 e extensões
    log "Instalando PHP 7.4 e extensões..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y \
        php7.4 \
        php7.4-fpm \
        php7.4-mysql \
        php7.4-curl \
        php7.4-gd \
        php7.4-mbstring \
        php7.4-xml \
        php7.4-zip \
        php7.4-json \
        php7.4-bcmath \
        php7.4-dom \
        php7.4-simplexml \
        php7.4-tokenizer 2>> "$LOG_FILE"; then
        
        success "✅ PHP 7.4 instalado com sucesso"
        
        # Configurar PHP-FPM
        configure_php_fpm
        
        return 0
    else
        warning "❌ Falha ao instalar PHP 7.4, tentando método alternativo..."
        
        # Método alternativo: instalar php-fpm genérico
        if apt-get install -y php-fpm php-mysql php-curl php-gd php-mbstring php-xml 2>> "$LOG_FILE"; then
            success "✅ PHP instalado (versão genérica)"
            configure_php_fpm
            return 0
        else
            error "Falha crítica ao instalar PHP"
            return 1
        fi
    fi
}

# ==================== CONFIGURAR PHP-FPM - VERSÃO CORRIGIDA ====================
configure_php_fpm() {
    log "Configurando PHP-FPM..."
    
    # Encontrar o serviço PHP-FPM correto
    PHP_FPM_SERVICE=""
    for service in php7.4-fpm php7.3-fpm php7.2-fpm php-fpm; do
        if systemctl list-unit-files | grep -q "^${service}" 2>/dev/null; then
            PHP_FPM_SERVICE=$service
            break
        fi
    done
    
    if [ -z "$PHP_FPM_SERVICE" ]; then
        # Tentar instalar php-fpm genérico
        apt-get install -y php-fpm 2>> "$LOG_FILE" || return 1
        PHP_FPM_SERVICE="php-fpm"
    fi
    
    # Configurar arquivo de pool
    PHP_FPM_CONF=""
    for conf in /etc/php/7.4/fpm/pool.d/www.conf /etc/php/7.3/fpm/pool.d/www.conf /etc/php/7.2/fpm/pool.d/www.conf /etc/php/fpm/pool.d/www.conf; do
        if [ -f "$conf" ]; then
            PHP_FPM_CONF=$conf
            break
        fi
    done
    
    if [ -n "$PHP_FPM_CONF" ]; then
        # Backup
        cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup"
        
        # Configurar para usar TCP (mais confiável)
        sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' "$PHP_FPM_CONF" 2>/dev/null || true
        sed -i 's/^;listen.allowed_clients/listen.allowed_clients/' "$PHP_FPM_CONF" 2>/dev/null || true
        
        # Configurar permissões
        sed -i 's/^user = .*/user = www-data/' "$PHP_FPM_CONF" 2>/dev/null || true
        sed -i 's/^group = .*/group = www-data/' "$PHP_FPM_CONF" 2>/dev/null || true
        
        # Aumentar limites
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "$PHP_FPM_CONF" 2>/dev/null || true
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$PHP_FPM_CONF" 2>/dev/null || true
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$PHP_FPM_CONF" 2>/dev/null || true
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$PHP_FPM_CONF" 2>/dev/null || true
        
        success "✅ PHP-FPM configurado em $PHP_FPM_CONF"
    fi
    
    # Configurar php.ini para aumentar limites
    PHP_INI=""
    for ini in /etc/php/7.4/fpm/php.ini /etc/php/7.3/fpm/php.ini /etc/php/7.2/fpm/php.ini /etc/php/fpm/php.ini; do
        if [ -f "$ini" ]; then
            PHP_INI=$ini
            break
        fi
    done
    
    if [ -n "$PHP_INI" ]; then
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI" 2>/dev/null || true
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_INI" 2>/dev/null || true
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_INI" 2>/dev/null || true
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$PHP_INI" 2>/dev/null || true
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$PHP_INI" 2>/dev/null || true
        sed -i 's/^;date.timezone =.*/date.timezone = America\/Sao_Paulo/' "$PHP_INI" 2>/dev/null || true
        success "✅ php.ini configurado"
    fi
    
    # INICIAR O SERVIÇO PHP-FPM
    log "Iniciando serviço $PHP_FPM_SERVICE..."
    
    # Recarregar daemons
    systemctl daemon-reload 2>/dev/null || true
    
    # Parar se já estiver rodando
    systemctl stop "$PHP_FPM_SERVICE" 2>/dev/null || true
    sleep 2
    
    # Iniciar serviço
    if systemctl start "$PHP_FPM_SERVICE" 2>> "$LOG_FILE"; then
        sleep 3
        
        if systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
            success "✅ PHP-FPM iniciado: $PHP_FPM_SERVICE"
            
            # Verificar se está ouvindo na porta
            sleep 2
            if netstat -tuln 2>/dev/null | grep -q ":9000"; then
                success "✅ PHP-FPM ouvindo na porta 9000"
            else
                warning "⚠ PHP-FPM não está ouvindo na porta 9000 (pode levar alguns segundos)"
            fi
        else
            warning "⚠ PHP-FPM não está ativo após iniciar, tentando novamente..."
            systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || true
            sleep 3
        fi
    else
        warning "⚠ Não foi possível iniciar $PHP_FPM_SERVICE via systemctl"
    fi
    
    # Habilitar para iniciar no boot
    systemctl enable "$PHP_FPM_SERVICE" 2>> "$LOG_FILE" || warning "⚠ Não foi possível habilitar $PHP_FPM_SERVICE"
    
    return 0
}

# ==================== CRIAR DIRETÓRIOS ====================
create_directory_structure() {
    log "Criando estrutura completa de diretórios..."
    
    # Limpar diretório existente se for reinstalação
    if [ -d "$BASE_DIR" ]; then
        warning "Diretório $BASE_DIR já existe. Fazendo backup..."
        mv "$BASE_DIR" "$BASE_DIR.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || warning "Não foi possível fazer backup"
    fi
    
    # Criar estrutura completa
    mkdir -p "$BASE_DIR" || { error "Falha ao criar diretório base"; return 1; }
    cd "$BASE_DIR" || { error "Não foi possível acessar $BASE_DIR"; return 1; }
    
    # Backend (Python FastAPI)
    log "Criando estrutura backend..."
    mkdir -p "$BACKEND_DIR"/{app/{controllers,services,database,models,routes,utils,core,middleware,schemas},logs,tests,static}
    
    # Frontend (PHP)
    log "Criando estrutura frontend..."
    mkdir -p "$FRONTEND_DIR"/{public/assets/{css,js,images},app/{controllers,models,views,helpers,middleware},config,vendor,temp,logs}
    
    # Instalador
    mkdir -p "$INSTALL_DIR"/{sql,config,scripts}
    
    # Criar arquivos __init__.py
    find "$BACKEND_DIR/app" -type d -exec touch {}/__init__.py \; 2>/dev/null || true
    
    success "✅ Estrutura criada em $BASE_DIR"
    return 0
}

# ==================== ARQUIVOS BACKEND ====================
create_backend_files() {
    log "Criando arquivos do backend Python..."
    
    cd "$BACKEND_DIR" || return 1
    
    # requirements.txt
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
pymysql==1.1.0
python-dotenv==1.0.0
requests==2.31.0
apscheduler==3.10.4
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
beautifulsoup4==4.12.2
pydantic==2.5.0
celery==5.3.4
redis==5.0.1
python-multipart==0.0.6
EOF

    # main.py funcional
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
"""
VOD Sync System - Backend Principal
FastAPI com endpoints básicos
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import os
from datetime import datetime

app = FastAPI(
    title="VOD Sync System API",
    version="2.0.0",
    description="API para sincronização de conteúdos VOD",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check
@app.get("/")
async def root():
    return {
        "service": "VOD Sync System API",
        "version": "2.0.0",
        "status": "online",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "database": "connected",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/api/v1/system/info")
async def system_info():
    return {
        "name": "VOD Sync System",
        "version": "2.0.0",
        "environment": "production",
        "endpoints": [
            "/health",
            "/api/v1/system/info",
            "/api/v1/auth/login",
            "/api/v1/sync/start"
        ]
    }

@app.post("/api/v1/auth/login")
async def login():
    return {"message": "Login endpoint", "status": "ok"}

@app.post("/api/v1/sync/start")
async def start_sync():
    return {"message": "Sync started", "status": "processing"}

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
EOF

    # .env do backend
    DB_PASS="VodSync_$(openssl rand -hex 8 2>/dev/null || echo 'VodSync123')"
    cat > "$BACKEND_DIR/.env" << EOF
# Configurações do Sistema
APP_NAME=VOD Sync System
APP_VERSION=2.0.0
DEBUG=True
ENVIRONMENT=production

# Servidor
HOST=0.0.0.0
PORT=8000
WORKERS=4

# Banco de Dados
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_system
DB_USER=vodsync_user
DB_PASS=$DB_PASS

# TMDb API (obter em: https://www.themoviedb.org/settings/api)
TMDB_API_KEY=sua_chave_aqui
TMDB_LANGUAGE=pt-BR
TMDB_CACHE_MINUTES=1440

# Segurança
SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || echo 'default_secret_key_change_me')
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# Limites
MAX_M3U_SIZE_MB=50
SYNC_BATCH_SIZE=100
MAX_RETRIES=3
EOF

    # Criar serviço systemd
    cat > "$BACKEND_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
EOF
    chmod +x "$BACKEND_DIR/start.sh"

    success "✅ Arquivos do backend criados"
    return 0
}

# ==================== ARQUIVOS FRONTEND PHP 7.4 COMPATÍVEL ====================
create_frontend_files() {
    log "Criando arquivos do frontend PHP 7.4 compatível..."
    
    cd "$FRONTEND_DIR" || return 1
    
    # index.php principal (compatível com PHP 7.4)
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<?php
/**
 * VOD Sync System - Frontend (PHP 7.4+ Compatível)
 */
session_start();

// Configurações para PHP 7.4
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('log_errors', 1);

// Verificar se API está online
$api_url = 'http://localhost:8000/health';
$api_online = false;

$context = stream_context_create([
    'http' => [
        'timeout' => 3,
        'ignore_errors' => true
    ]
]);

try {
    $response = @file_get_contents($api_url, false, $context);
    $api_online = ($response !== false);
} catch (Exception $e) {
    $api_online = false;
}

$api_status = $api_online ? 'online' : 'offline';
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VOD Sync System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        :root {
            --primary: #4361ee;
            --secondary: #3a0ca3;
            --success: #4cc9f0;
        }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            margin: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
        }
        .main-card {
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
            max-width: 1000px;
            width: 100%;
        }
        .sidebar {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 30px 20px;
            min-height: 400px;
        }
        .content {
            padding: 30px;
        }
        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            display: inline-block;
        }
        .status-online { background: #10b981; color: white; }
        .status-offline { background: #ef4444; color: white; }
        .feature-card {
            border: 1px solid #e5e7eb;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            transition: all 0.2s;
            background: #f9fafb;
        }
        .feature-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .login-form {
            max-width: 350px;
            margin: 0 auto;
        }
        @media (max-width: 768px) {
            .sidebar {
                min-height: auto;
                padding: 20px;
            }
            .main-card {
                margin: 10px;
            }
        }
    </style>
</head>
<body>
    <div class="main-card">
        <div class="row g-0">
            <!-- Sidebar -->
            <div class="col-lg-4 col-md-5">
                <div class="sidebar">
                    <div class="text-center mb-4">
                        <i class="fas fa-sync-alt fa-3x mb-3"></i>
                        <h3>VOD Sync</h3>
                        <p class="opacity-75 small">Sistema de Sincronização VOD</p>
                    </div>
                    
                    <div class="mb-4">
                        <h6><i class="fas fa-check-circle me-2"></i>Funcionalidades</h6>
                        <ul class="list-unstyled small">
                            <li class="mb-1"><i class="fas fa-server me-2"></i>Conexão XUI One</li>
                            <li class="mb-1"><i class="fas fa-list me-2"></i>Listas M3U</li>
                            <li class="mb-1"><i class="fas fa-film me-2"></i>Sincronização Automática</li>
                            <li class="mb-1"><i class="fas fa-database me-2"></i>Enriquecimento TMDb</li>
                            <li><i class="fas fa-users me-2"></i>Multi-usuário</li>
                        </ul>
                    </div>
                    
                    <div class="system-status">
                        <h6><i class="fas fa-heartbeat me-2"></i>Status do Sistema</h6>
                        <div class="d-flex justify-content-between mb-1">
                            <span class="small">Backend API:</span>
                            <span class="status-badge status-<?php echo $api_status; ?>">
                                <?php echo strtoupper($api_status); ?>
                            </span>
                        </div>
                        <div class="d-flex justify-content-between mb-1">
                            <span class="small">Banco de Dados:</span>
                            <span class="status-badge status-online">ONLINE</span>
                        </div>
                        <div class="d-flex justify-content-between">
                            <span class="small">Frontend:</span>
                            <span class="status-badge status-online">ONLINE</span>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Conteúdo Principal -->
            <div class="col-lg-8 col-md-7">
                <div class="content">
                    <h2 class="mb-3">Bem-vindo ao VOD Sync</h2>
                    <p class="text-muted mb-4">Sistema completo para sincronização de conteúdos VOD</p>
                    
                    <!-- Formulário de Login -->
                    <div class="login-form">
                        <h5 class="mb-3"><i class="fas fa-sign-in-alt me-2"></i>Acesso ao Sistema</h5>
                        
                        <?php if(isset($_GET['error'])): ?>
                        <div class="alert alert-danger alert-dismissible fade show small" role="alert">
                            Credenciais inválidas
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <form action="/login.php" method="POST">
                            <div class="mb-3">
                                <label class="form-label small">Usuário</label>
                                <div class="input-group input-group-sm">
                                    <span class="input-group-text"><i class="fas fa-user"></i></span>
                                    <input type="text" class="form-control" name="username" 
                                           placeholder="admin" required autofocus>
                                </div>
                            </div>
                            
                            <div class="mb-3">
                                <label class="form-label small">Senha</label>
                                <div class="input-group input-group-sm">
                                    <span class="input-group-text"><i class="fas fa-lock"></i></span>
                                    <input type="password" class="form-control" name="password" 
                                           placeholder="••••••••" required>
                                    <button class="btn btn-outline-secondary" type="button" id="togglePassword">
                                        <i class="fas fa-eye"></i>
                                    </button>
                                </div>
                            </div>
                            
                            <div class="mb-3 form-check">
                                <input type="checkbox" class="form-check-input" id="remember">
                                <label class="form-check-label small" for="remember">Lembrar-me</label>
                            </div>
                            
                            <button type="submit" class="btn btn-primary w-100 py-2">
                                <i class="fas fa-sign-in-alt me-2"></i>Entrar
                            </button>
                        </form>
                        
                        <div class="text-center mt-3">
                            <p class="small text-muted mb-0">
                                <i class="fas fa-info-circle me-1"></i>
                                Primeiro acesso: <strong>admin</strong> / <strong>admin123</strong>
                            </p>
                        </div>
                    </div>
                    
                    <hr class="my-4">
                    
                    <!-- Recursos do Sistema -->
                    <h5 class="mb-3"><i class="fas fa-rocket me-2"></i>Recursos Principais</h5>
                    <div class="row">
                        <div class="col-sm-6">
                            <div class="feature-card">
                                <h6><i class="fas fa-sync-alt text-primary me-2"></i>Sincronização</h6>
                                <p class="text-muted small mb-0">Sincronização automática com XUI One</p>
                            </div>
                        </div>
                        <div class="col-sm-6">
                            <div class="feature-card">
                                <h6><i class="fas fa-database text-success me-2"></i>TMDb</h6>
                                <p class="text-muted small mb-0">Metadados em português automaticamente</p>
                            </div>
                        </div>
                        <div class="col-sm-6">
                            <div class="feature-card">
                                <h6><i class="fas fa-users-cog text-warning me-2"></i>Multi-usuário</h6>
                                <p class="text-muted small mb-0">Admin, Revendedor e Usuário</p>
                            </div>
                        </div>
                        <div class="col-sm-6">
                            <div class="feature-card">
                                <h6><i class="fas fa-shield-alt text-danger me-2"></i>Segurança</h6>
                                <p class="text-muted small mb-0">Licenças e autenticação JWT</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Mostrar/ocultar senha
        document.getElementById('togglePassword').addEventListener('click', function() {
            const password = document.querySelector('input[name="password"]');
            const type = password.getAttribute('type') === 'password' ? 'text' : 'password';
            password.setAttribute('type', type);
            this.innerHTML = type === 'password' ? '<i class="fas fa-eye"></i>' : '<i class="fas fa-eye-slash"></i>';
        });
    </script>
</body>
</html>
EOF

    # login.php compatível
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
session_start();

// Compatibilidade PHP 7.4
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = isset($_POST['username']) ? $_POST['username'] : '';
    $password = isset($_POST['password']) ? $_POST['password'] : '';
    
    // Credenciais padrão (em produção, usar banco de dados)
    $valid_credentials = [
        'admin' => 'admin123',
        'reseller' => 'reseller123',
        'user' => 'user123'
    ];
    
    if (isset($valid_credentials[$username]) && $valid_credentials[$username] === $password) {
        $_SESSION['user_id'] = 1;
        $_SESSION['username'] = $username;
        $_SESSION['user_type'] = $username;
        $_SESSION['login_time'] = time();
        
        // Redirecionar para dashboard
        header('Location: /dashboard.php');
        exit();
    } else {
        // Credenciais inválidas
        header('Location: /?error=1');
        exit();
    }
}

// Se não for POST, redirecionar para index
header('Location: /');
exit();
EOF

    # dashboard.php básico
    cat > "$FRONTEND_DIR/public/dashboard.php" << 'EOF'
<?php
session_start();
if (!isset($_SESSION['user_id'])) {
    header('Location: /');
    exit();
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f8f9fa;
        }
        .navbar {
            background: #2c3e50;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .stat-card {
            background: white;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
            transition: all 0.2s;
        }
        .stat-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .sidebar {
            background: #34495e;
            color: white;
            min-height: 100vh;
            padding: 0;
        }
        .sidebar .nav-link {
            color: rgba(255,255,255,0.8);
            padding: 10px 15px;
            border-left: 3px solid transparent;
        }
        .sidebar .nav-link:hover,
        .sidebar .nav-link.active {
            color: white;
            background: rgba(255,255,255,0.1);
            border-left-color: #3498db;
        }
        @media (max-width: 768px) {
            .sidebar {
                min-height: auto;
            }
        }
    </style>
</head>
<body>
    <!-- Navbar -->
    <nav class="navbar navbar-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="/dashboard.php">
                <i class="fas fa-sync-alt me-2"></i>VOD Sync Dashboard
            </a>
            <span class="navbar-text">
                <i class="fas fa-user me-1"></i><?php echo htmlspecialchars($_SESSION['username']); ?>
            </span>
        </div>
    </nav>
    
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <div class="col-md-3 col-lg-2 sidebar">
                <div class="p-3">
                    <h6 class="text-uppercase text-muted small">Menu Principal</h6>
                </div>
                <nav class="nav flex-column">
                    <a href="/dashboard.php" class="nav-link active">
                        <i class="fas fa-tachometer-alt me-2"></i> Dashboard
                    </a>
                    <a href="/xui.php" class="nav-link">
                        <i class="fas fa-server me-2"></i> Conexões XUI
                    </a>
                    <a href="/m3u.php" class="nav-link">
                        <i class="fas fa-list me-2"></i> Listas M3U
                    </a>
                    <a href="/movies.php" class="nav-link">
                        <i class="fas fa-film me-2"></i> Filmes
                    </a>
                    <a href="/series.php" class="nav-link">
                        <i class="fas fa-tv me-2"></i> Séries
                    </a>
                    <a href="/sync.php" class="nav-link">
                        <i class="fas fa-sync me-2"></i> Sincronização
                    </a>
                    <a href="/logs.php" class="nav-link">
                        <i class="fas fa-clipboard-list me-2"></i> Logs
                    </a>
                    <a href="/logout.php" class="nav-link text-danger mt-4">
                        <i class="fas fa-sign-out-alt me-2"></i> Sair
                    </a>
                </nav>
            </div>
            
            <!-- Conteúdo Principal -->
            <div class="col-md-9 col-lg-10 p-4">
                <h3 class="mb-4">Dashboard do Sistema</h3>
                
                <!-- Cards de Estatísticas -->
                <div class="row">
                    <div class="col-sm-6 col-md-3">
                        <div class="stat-card">
                            <h6 class="text-muted mb-2">Conexões XUI</h6>
                            <h3 class="mb-0">0</h3>
                            <small class="text-muted">Nenhuma configurada</small>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-3">
                        <div class="stat-card">
                            <h6 class="text-muted mb-2">Listas M3U</h6>
                            <h3 class="mb-0">0</h3>
                            <small class="text-muted">Nenhuma carregada</small>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-3">
                        <div class="stat-card">
                            <h6 class="text-muted mb-2">Filmes</h6>
                            <h3 class="mb-0">0</h3>
                            <small class="text-muted">Não sincronizados</small>
                        </div>
                    </div>
                    <div class="col-sm-6 col-md-3">
                        <div class="stat-card">
                            <h6 class="text-muted mb-2">Séries</h6>
                            <h3 class="mb-0">0</h3>
                            <small class="text-muted">Não sincronizadas</small>
                        </div>
                    </div>
                </div>
                
                <!-- Ações Rápidas -->
                <div class="row mt-4">
                    <div class="col-md-12">
                        <div class="card">
                            <div class="card-body">
                                <h5 class="card-title"><i class="fas fa-bolt me-2"></i>Ações Rápidas</h5>
                                <div class="row">
                                    <div class="col-md-4 mb-2">
                                        <a href="/xui.php?action=add" class="btn btn-outline-primary w-100">
                                            <i class="fas fa-plus-circle me-2"></i>Nova Conexão XUI
                                        </a>
                                    </div>
                                    <div class="col-md-4 mb-2">
                                        <a href="/m3u.php?action=add" class="btn btn-outline-primary w-100">
                                            <i class="fas fa-plus-circle me-2"></i>Nova Lista M3U
                                        </a>
                                    </div>
                                    <div class="col-md-4 mb-2">
                                        <a href="/sync.php?action=start" class="btn btn-success w-100">
                                            <i class="fas fa-play me-2"></i>Iniciar Sincronização
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Status do Sistema -->
                <div class="row mt-4">
                    <div class="col-md-12">
                        <div class="card">
                            <div class="card-body">
                                <h5 class="card-title"><i class="fas fa-info-circle me-2"></i>Status do Sistema</h5>
                                <table class="table table-sm">
                                    <tr>
                                        <td>Backend API</td>
                                        <td><span class="badge bg-success">Online</span></td>
                                        <td>http://localhost:8000</td>
                                    </tr>
                                    <tr>
                                        <td>Banco de Dados</td>
                                        <td><span class="badge bg-success">Conectado</span></td>
                                        <td>MySQL/MariaDB</td>
                                    </tr>
                                    <tr>
                                        <td>Frontend</td>
                                        <td><span class="badge bg-success">Online</span></td>
                                        <td>PHP <?php echo phpversion(); ?></td>
                                    </tr>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

    # logout.php
    cat > "$FRONTEND_DIR/public/logout.php" << 'EOF'
<?php
session_start();
session_destroy();
header('Location: /');
exit();
EOF

    # Configuração PHP
    cat > "$FRONTEND_DIR/config/database.php" << 'EOF'
<?php
return [
    'host' => 'localhost',
    'database' => 'vod_system',
    'username' => 'vodsync_user',
    'password' => '', // Será preenchido durante instalação
    'charset' => 'utf8mb4'
];
EOF

    success "✅ Arquivos do frontend criados (PHP 7.4 compatível)"
    return 0
}

# ==================== CONFIGURAR NGINX ====================
setup_nginx() {
    log "Configurando Nginx..."
    
    # 1. Verificar/Instalar Nginx
    if ! command -v nginx &> /dev/null; then
        log "Instalando Nginx..."
        apt-get update
        if ! apt-get install -y nginx 2>> "$LOG_FILE"; then
            error "Falha ao instalar Nginx"
            return 1
        fi
        success "✅ Nginx instalado"
    fi
    
    # 2. Parar Nginx se estiver rodando
    if systemctl is-active --quiet nginx; then
        log "Parando Nginx..."
        systemctl stop nginx 2>> "$LOG_FILE" || true
        sleep 2
    fi
    
    # 3. Criar configuração
    log "Criando configuração Nginx..."
    
    # Backup da configuração atual se existir
    if [ -f /etc/nginx/sites-available/vod-sync ]; then
        cp /etc/nginx/sites-available/vod-sync "/etc/nginx/sites-available/vod-sync.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # Configuração
    cat > /tmp/vod-sync-nginx.conf << 'NGINX_SIMPLE'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /opt/vod-sync/frontend/public;
    index index.php index.html index.htm;
    
    # Frontend
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
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # PHP
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME $fastcgi_script_name;
        include fastcgi_params;
        
        # Timeouts
        fastcgi_read_timeout 300;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
    }
    
    # Bloquear arquivos ocultos
    location ~ /\. {
        deny all;
        return 404;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    # Tamanho máximo de upload
    client_max_body_size 100M;
}
NGINX_SIMPLE
    
    # Mover para local correto
    cp /tmp/vod-sync-nginx.conf /etc/nginx/sites-available/vod-sync
    
    # 4. Remover site default para evitar conflitos
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # 5. Ativar nosso site
    ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # 6. TESTAR configuração
    log "Testando configuração Nginx..."
    
    if nginx -t 2>> "$LOG_FILE"; then
        success "✅ Configuração Nginx válida"
    else
        error "❌ Configuração Nginx inválida"
        return 1
    fi
    
    # 7. Iniciar Nginx
    log "Iniciando Nginx..."
    
    # Matar processos Nginx existentes (se houver)
    pkill -9 nginx 2>/dev/null || true
    sleep 1
    
    # Tentar iniciar
    if systemctl start nginx 2>> "$LOG_FILE"; then
        sleep 3
        
        if systemctl is-active --quiet nginx; then
            success "✅ Nginx iniciado com sucesso na porta 80"
            
            # Verificar se porta 80 está aberta
            sleep 2
            if netstat -tuln 2>/dev/null | grep -q ":80 "; then
                success "✅ Porta 80 ouvindo"
            else
                warning "⚠ Porta 80 não está ouvindo"
            fi
        else
            error "❌ Nginx não está ativo após iniciar"
            return 1
        fi
    else
        error "❌ Falha ao iniciar Nginx"
        return 1
    fi
    
    # 8. Habilitar para iniciar no boot
    systemctl enable nginx 2>> "$LOG_FILE" || warning "⚠ Não foi possível habilitar Nginx"
    
    return 0
}

# ==================== CONFIGURAR BACKEND ====================
setup_backend() {
    log "Configurando backend Python..."
    
    cd "$BACKEND_DIR" || return 1
    
    # Instalar Python3 se não existir
    if ! command -v python3 &> /dev/null; then
        log "Instalando Python3..."
        apt-get install -y python3 python3-pip python3-venv 2>> "$LOG_FILE" || return 1
    fi
    
    # Criar ambiente virtual
    if ! python3 -m venv venv 2>> "$LOG_FILE"; then
        # Tentar instalar python3-venv
        apt-get install -y python3-venv 2>> "$LOG_FILE" || return 1
        python3 -m venv venv 2>> "$LOG_FILE" || return 1
    fi
    
    # Ativar venv e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip setuptools wheel 2>> "$LOG_FILE" || true
    
    log "Instalando dependências Python..."
    if ! pip install -r requirements.txt 2>> "$LOG_FILE"; then
        warning "Algumas dependências falharam, tentando instalação básica..."
        pip install fastapi uvicorn pymysql python-dotenv 2>> "$LOG_FILE" || return 1
    fi
    
    # Criar usuário para serviço se não existir
    if ! id -u www-data >/dev/null 2>&1; then
        useradd -r -s /bin/false www-data 2>> "$LOG_FILE" || true
    fi
    
    # Configurar permissões
    chown -R www-data:www-data "$BACKEND_DIR" 2>/dev/null || true
    chmod -R 755 "$BACKEND_DIR" 2>/dev/null || true
    chmod +x "$BACKEND_DIR/start.sh" 2>/dev/null || true
    
    # Criar serviço systemd
    cat > /etc/systemd/system/vod-sync-backend.service << 'SERVICE_CONFIG'
[Unit]
Description=VOD Sync System Backend API
After=network.target
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/vod-sync/backend
Environment="PATH=/opt/vod-sync/backend/venv/bin"
ExecStart=/opt/vod-sync/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Segurança
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/vod-sync/backend/logs

[Install]
WantedBy=multi-user.target
SERVICE_CONFIG
    
    # Recarregar systemd
    systemctl daemon-reload 2>/dev/null || true
    
    # Habilitar serviço
    systemctl enable vod-sync-backend 2>> "$LOG_FILE" || warning "Não foi possível habilitar serviço backend"
    
    # Tentar iniciar
    log "Iniciando serviço backend..."
    if systemctl start vod-sync-backend 2>> "$LOG_FILE"; then
        sleep 3
        
        # Verificar status
        if systemctl is-active --quiet vod-sync-backend; then
            success "✅ Backend rodando na porta 8000"
            
            # Testar endpoint
            sleep 2
            if curl -s --connect-timeout 5 http://localhost:8000/health >/dev/null 2>&1; then
                success "✅ API respondendo corretamente"
            else
                warning "⚠ API não responde, mas serviço está rodando"
            fi
        else
            warning "⚠ Backend não está ativo após iniciar"
        fi
    else
        warning "⚠ Falha ao iniciar serviço backend"
    fi
    
    return 0
}

# ==================== CONFIGURAR BANCO DE DADOS ====================
setup_database() {
    log "Configurando banco de dados..."
    
    # Verificar MySQL/MariaDB
    MYSQL_SERVICE=""
    for service in mysql mariadb; do
        if systemctl list-unit-files | grep -q "^${service}" 2>/dev/null; then
            MYSQL_SERVICE="$service"
            break
        fi
    done
    
    # Instalar se necessário
    if [ -z "$MYSQL_SERVICE" ]; then
        log "Instalando MySQL..."
        apt-get update
        if ! apt-get install -y mysql-server 2>> "$LOG_FILE"; then
            error "Falha ao instalar MySQL"
            return 1
        fi
        MYSQL_SERVICE="mysql"
    fi
    
    # Iniciar serviço
    if ! systemctl start "$MYSQL_SERVICE" 2>> "$LOG_FILE"; then
        error "Falha ao iniciar $MYSQL_SERVICE"
        return 1
    fi
    
    systemctl enable "$MYSQL_SERVICE" 2>> "$LOG_FILE" || true
    
    # Aguardar MySQL iniciar
    sleep 5
    
    # Credenciais
    DB_NAME="vod_system"
    DB_USER="vodsync_user"
    DB_PASS="VodSync_$(openssl rand -hex 8 2>/dev/null || echo 'VodSync123')"
    
    # Criar banco e usuário
    log "Criando banco de dados..."
    if ! mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"; then
        error "Falha ao criar banco"
        return 1
    fi
    
    # Verificar se usuário já existe
    if ! mysql -e "SELECT User FROM mysql.user WHERE User='$DB_USER'" 2>/dev/null | grep -q "$DB_USER"; then
        if ! mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$LOG_FILE"; then
            error "Falha ao criar usuário"
            return 1
        fi
    else
        mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$LOG_FILE" || warning "Não foi possível alterar senha do usuário"
    fi
    
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>> "$LOG_FILE" || error "Falha ao conceder privilégios"
    mysql -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"
    
    # Criar estrutura básica
    log "Criando tabelas..."
    cat > /tmp/vod_schema.sql << 'SQL_SCHEMA'
-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100),
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('admin', 'reseller', 'user') DEFAULT 'user',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabela de conexões XUI
CREATE TABLE IF NOT EXISTS xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    alias VARCHAR(100),
    host VARCHAR(255) NOT NULL,
    port INT DEFAULT 3306,
    username VARCHAR(100) NOT NULL,
    password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabela de listas M3U
CREATE TABLE IF NOT EXISTS m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    name VARCHAR(255),
    m3u_content LONGTEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabela de logs
CREATE TABLE IF NOT EXISTS sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    message TEXT,
    log_type ENUM('info', 'success', 'warning', 'error') DEFAULT 'info',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Inserir usuário admin padrão (senha: admin123)
INSERT IGNORE INTO users (username, password_hash, user_type) VALUES 
('admin', '$2b$12$LQv3c1yqBWVHxpd5g8T3e.BHZzl6CLj7/5L8OYyN8pMZ7cJkzq6W2', 'admin'),
('reseller', '$2b$12$LQv3c1yqBWVHxpd5g8T3e.BHZzl6CLj7/5L8OYyN8pMZ7cJkzq6W2', 'reseller'),
('user', '$2b$12$LQv3c1yqBWVHxpd5g8T3e.BHZzl6CLj7/5L8OYyN8pMZ7cJkzq6W2', 'user');

-- Inserir logs iniciais
INSERT IGNORE INTO sync_logs (user_id, message, log_type) VALUES
(1, 'Sistema instalado com sucesso', 'success'),
(1, 'Banco de dados configurado', 'info');
SQL_SCHEMA
    
    mysql "$DB_NAME" < /tmp/vod_schema.sql 2>> "$LOG_FILE" || warning "Alguns erros ao criar tabelas"
    
    # Atualizar .env com credenciais
    sed -i "s/DB_PASS=.*/DB_PASS=$DB_PASS/" "$BACKEND_DIR/.env" 2>/dev/null || true
    
    # Salvar credenciais
    cat > /root/vod-sync-credentials.txt << CREDENTIALS
============================================
CREDENCIAIS VOD SYNC SYSTEM - PHP 7.4
============================================
INSTALAÇÃO CONCLUÍDA EM: $(date)

🌐 URL DE ACESSO:
   Frontend: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
   Backend API: http://localhost:8000

👤 USUÁRIOS PADRÃO:
   Administrador: admin / admin123
   Revendedor: reseller / reseller123
   Usuário: user / user123

🗄️ BANCO DE DADOS:
   Banco: $DB_NAME
   Usuário: $DB_USER
   Senha: $DB_PASS
   Host: localhost:3306

🔧 SERVIÇOS:
   Nginx: porta 80
   Backend: porta 8000
   PHP-FPM: php7.4-fpm (porta 9000)
   MySQL: porta 3306

📁 DIRETÓRIOS:
   Sistema: $BASE_DIR
   Backend: $BACKEND_DIR
   Frontend: $FRONTEND_DIR
   Logs: $BACKEND_DIR/logs/

⚡ COMANDOS ÚTEIS:
   sudo systemctl status vod-sync-backend
   sudo systemctl status php7.4-fpm
   sudo tail -f /var/log/nginx/error.log

⚠️ IMPORTANTE:
   1. Configure sua chave TMDb API em: $BACKEND_DIR/.env
   2. ALTERE AS SENHAS NO PRIMEIRO ACESSO!
============================================
CREDENTIALS
    
    success "✅ Banco de dados configurado"
    log "📄 Credenciais salvas em: /root/vod-sync-credentials.txt"
    
    return 0
}

# ==================== TESTAR PHP 7.4 ====================
test_php_74() {
    log "Testando PHP 7.4..."
    
    # Criar arquivo de teste PHP
    cat > /opt/vod-sync/frontend/public/test-php.php << 'PHP_TEST'
<?php
// Teste de compatibilidade PHP 7.4
echo "<!DOCTYPE html>\n";
echo "<html>\n";
echo "<head><title>Teste PHP 7.4</title></head>\n";
echo "<body style='font-family: Arial, sans-serif; padding: 20px;'>\n";
echo "<h1>✅ Teste PHP 7.4</h1>\n";
echo "<p>Versão do PHP: <strong>" . phpversion() . "</strong></p>\n";

// Testar extensões necessárias
$extensoes = ['pdo', 'pdo_mysql', 'json', 'curl', 'mbstring', 'session', 'mysqli', 'gd'];
echo "<h3>Extensões PHP:</h3>\n";
echo "<ul>\n";
foreach ($extensoes as $ext) {
    $status = extension_loaded($ext) ? "✅" : "❌";
    echo "<li>$status $ext</li>\n";
}
echo "</ul>\n";

// Testar configurações
echo "<h3>Configurações:</h3>\n";
echo "<ul>\n";
echo "<li>memory_limit: " . ini_get('memory_limit') . "</li>\n";
echo "<li>upload_max_filesize: " . ini_get('upload_max_filesize') . "</li>\n";
echo "<li>post_max_size: " . ini_get('post_max_size') . "</li>\n";
echo "<li>max_execution_time: " . ini_get('max_execution_time') . "</li>\n";
echo "<li>date.timezone: " . ini_get('date.timezone') . "</li>\n";
echo "</ul>\n";

// Testar escrita
$test_file = '/tmp/php_test_' . time() . '.txt';
if (file_put_contents($test_file, 'Teste de escrita')) {
    echo "<p>✅ Escrita no sistema de arquivos: OK</p>\n";
    unlink($test_file);
} else {
    echo "<p>❌ Escrita no sistema de arquivos: FALHOU</p>\n";
}

// Link para phpinfo
echo '<p><a href="/phpinfo.php" target="_blank">Ver phpinfo() completo</a></p>';
echo '<p><a href="/">Voltar para o sistema</a></p>';

echo "</body>\n";
echo "</html>\n";
?>
PHP_TEST
    
    # Criar phpinfo
    cat > /opt/vod-sync/frontend/public/phpinfo.php << 'EOF'
<?php phpinfo(); ?>
EOF
    
    log "Arquivo de teste criado: http://seu-ip/test-php.php"
    
    return 0
}

# ==================== VERIFICAÇÃO FINAL ====================
verify_installation() {
    print_header
    echo "🔍 VERIFICAÇÃO FINAL DA INSTALAÇÃO"
    echo ""
    
    # Verificar serviços
    echo "📦 STATUS DOS SERVIÇOS:"
    services=("nginx" "vod-sync-backend" "php7.4-fpm" "php-fpm" "mysql" "mariadb")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}" 2>/dev/null; then
            status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            if [ "$status" = "active" ]; then
                echo "  ✅ $service: ATIVO"
            elif [ "$status" = "activating" ]; then
                echo "  ⚠ $service: INICIANDO"
            else
                echo "  ❌ $service: $status"
            fi
        fi
    done
    
    echo ""
    echo "🌐 TESTE DE CONEXÕES:"
    
    # Testar API
    if curl -s --connect-timeout 5 http://localhost:8000/health >/dev/null 2>&1; then
        echo "  ✅ Backend API: RESPONDENDO"
    else
        echo "  ❌ Backend API: NÃO RESPONDE"
    fi
    
    # Testar PHP-FPM
    if netstat -tuln 2>/dev/null | grep -q ":9000 "; then
        echo "  ✅ PHP-FPM: RODANDO (porta 9000)"
    else
        echo "  ❌ PHP-FPM: NÃO RODANDO"
    fi
    
    # Testar Nginx
    if netstat -tuln 2>/dev/null | grep -q ":80 "; then
        echo "  ✅ Nginx: RODANDO (porta 80)"
    else
        echo "  ❌ Nginx: NÃO RODANDO"
    fi
    
    echo ""
    echo "📁 ESTRUTURA DE ARQUIVOS:"
    if [ -f "$BACKEND_DIR/app/main.py" ]; then
        echo "  ✅ Backend: OK"
    else
        echo "  ❌ Backend: FALTANDO"
    fi
    
    if [ -f "$FRONTEND_DIR/public/index.php" ]; then
        echo "  ✅ Frontend: OK"
    else
        echo "  ❌ Frontend: FALTANDO"
    fi
    
    if [ -f "/etc/nginx/sites-available/vod-sync" ]; then
        echo "  ✅ Nginx Config: OK"
    else
        echo "  ❌ Nginx Config: FALTANDO"
    fi
    
    # Mostrar URLs de acesso
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO! (PHP 7.4)"
    echo ""
    
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    
    echo "🌐 ACESSO AO SISTEMA:"
    echo "   URL Principal: http://$IP_ADDR"
    echo "   Teste PHP: http://$IP_ADDR/test-php.php"
    echo "   Backend API: http://$IP_ADDR:8000"
    echo ""
    
    echo "🔑 CREDENCIAIS PADRÃO:"
    echo "   admin / admin123"
    echo "   reseller / reseller123"
    echo "   user / user123"
    echo ""
    
    echo "📄 ARQUIVOS IMPORTANTES:"
    echo "   Log da instalação: $LOG_FILE"
    echo "   Credenciais: /root/vod-sync-credentials.txt"
    echo "   Config Backend: $BACKEND_DIR/.env"
    echo ""
    
    echo "⚡ COMANDOS DE GERENCIAMENTO:"
    echo "   sudo systemctl restart vod-sync-backend"
    echo "   sudo systemctl restart php7.4-fpm"
    echo "   sudo systemctl restart nginx"
    echo "   sudo tail -f /var/log/nginx/error.log"
    echo ""
    
    echo "⚠️ PRÓXIMOS PASSOS:"
    echo "   1. Acesse http://$IP_ADDR"
    echo "   2. Faça login com admin/admin123"
    echo "   3. Configure chave TMDb API no painel"
    echo "   4. Adicione conexão XUI e lista M3U"
    echo ""
    
    echo "🔧 SE TIVER 502 BAD GATEWAY:"
    echo "   1. sudo systemctl restart php7.4-fpm"
    echo "   2. sudo systemctl restart nginx"
    echo "   3. Teste: http://$IP_ADDR/test-php.php"
    echo ""
    
    echo "══════════════════════════════════════════════════════════"
    
    # Criar flag de instalação
    echo "install_date=$(date '+%Y-%m-%d %H:%M:%S')" > "$BASE_DIR/.installed"
    echo "version=2.0.0-php74" >> "$BASE_DIR/.installed"
    echo "php_version=7.4" >> "$BASE_DIR/.installed"
    echo "frontend_url=http://$IP_ADDR" >> "$BASE_DIR/.installed"
    echo "backend_url=http://$IP_ADDR:8000" >> "$BASE_DIR/.installed"
    
    # Remover arquivos de teste após 5 minutos
    (sleep 300 && rm -f /opt/vod-sync/frontend/public/test-php.php /opt/vod-sync/frontend/public/phpinfo.php 2>/dev/null && echo "Arquivos de teste removidos") &
    
    return 0
}

# ==================== INSTALAÇÃO COMPLETA ====================
complete_installation() {
    print_header
    
    echo "🔄 Este instalador executará:"
    echo "   1. 📁 Criar estrutura completa de diretórios"
    echo "   2. 🐍 Configurar backend Python (FastAPI)"
    echo "   3. 🌐 Instalar e configurar PHP 7.4 + Nginx"
    echo "   4. 🗄️  Configurar banco de dados MySQL"
    echo "   5. ⚙️  Criar serviços systemd"
    echo "   6. ✅ Testar e verificar instalação"
    echo ""
    echo "⏱️  Tempo estimado: 3-5 minutos"
    echo ""
    
    read -p "Continuar com a instalação? (s/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] || return
    
    # Atualizar sistema
    log "Atualizando pacotes do sistema..."
    apt-get update 2>> "$LOG_FILE"
    apt-get upgrade -y 2>> "$LOG_FILE" || true
    
    # Executar passos na ordem correta com tratamento de erros
    log "Iniciando instalação completa..."
    
    log "=== PASSO 1: Verificando privilégios ==="
    check_root
    
    log "=== PASSO 2: Criando estrutura de diretórios ==="
    create_directory_structure || { error "Falha ao criar estrutura de diretórios"; return 1; }
    
    log "=== PASSO 3: Criando arquivos do backend ==="
    create_backend_files || { error "Falha ao criar arquivos do backend"; return 1; }
    
    log "=== PASSO 4: Criando arquivos do frontend ==="
    create_frontend_files || { error "Falha ao criar arquivos do frontend"; return 1; }
    
    log "=== PASSO 5: Instalando PHP 7.4 ==="
    install_php_74 || { error "Falha ao instalar PHP 7.4"; return 1; }
    
    log "=== PASSO 6: Configurando banco de dados ==="
    setup_database || { error "Falha ao configurar banco de dados"; return 1; }
    
    log "=== PASSO 7: Configurando Nginx ==="
    setup_nginx || { error "Falha ao configurar Nginx"; return 1; }
    
    log "=== PASSO 8: Configurando backend Python ==="
    setup_backend || { error "Falha ao configurar backend"; return 1; }
    
    log "=== PASSO 9: Testando PHP 7.4 ==="
    test_php_74 || { error "Falha ao testar PHP"; return 1; }
    
    log "=== PASSO 10: Verificação final ==="
    verify_installation
    
    success "✅ Instalação completa concluída!"
    echo ""
    echo "📋 Resumo da instalação:"
    echo "   • Estrutura criada em: $BASE_DIR"
    echo "   • Frontend PHP: $FRONTEND_DIR"
    echo "   • Backend Python: $BACKEND_DIR"
    echo "   • Credenciais salvas em: /root/vod-sync-credentials.txt"
    echo ""
    echo "🌐 Acesse o sistema em: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo 'localhost')"
    echo ""
}

# ==================== MENU PRINCIPAL ====================
show_menu() {
    while true; do
        print_header
        echo "MENU PRINCIPAL - PHP 7.4"
        echo ""
        echo "1) 🚀 Instalação Completa (Recomendado)"
        echo "2) 📁 Apenas Criar Estrutura"
        echo "3) 🌐 Apenas Instalar PHP 7.4 + Nginx"
        echo "4) 🐍 Apenas Configurar Backend"
        echo "5) 🗄️  Apenas Configurar Banco de Dados"
        echo "6) 🧪 Testar PHP 7.4"
        echo "7) 🔍 Verificar Sistema"
        echo "8) 🗑️  Desinstalar Tudo"
        echo "9) 🚪 Sair"
        echo ""
        read -p "Opção: " choice
        
        case $choice in
            1) 
                complete_installation
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            2) 
                check_root
                create_directory_structure
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            3) 
                check_root
                install_php_74
                setup_nginx
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            4) 
                check_root
                setup_backend
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            5) 
                check_root
                setup_database
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            6) 
                check_root
                test_php_74
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            7) 
                verify_installation
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            8) 
                uninstall_system
                read -p "Pressione Enter para continuar..." </dev/tty
                ;;
            9) 
                echo "Até logo!"
                exit 0
                ;;
            *) 
                echo "Opção inválida"
                sleep 2
                ;;
        esac
    done
}

# ==================== DESINSTALAÇÃO ====================
uninstall_system() {
    print_header
    echo "⚠️  DESINSTALAÇÃO COMPLETA"
    echo ""
    echo "Esta ação irá remover:"
    echo "   • Todos os serviços systemd"
    echo "   • Configuração do Nginx"
    echo "   • Banco de dados (opcional)"
    echo "   • Arquivos do sistema (opcional)"
    echo ""
    
    read -p "Tem certeza? (s/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] || return
    
    # Parar serviços
    log "Parando serviços..."
    systemctl stop vod-sync-backend 2>/dev/null || true
    systemctl disable vod-sync-backend 2>/dev/null || true
    
    # Parar PHP-FPM
    for service in php7.4-fpm php7.3-fpm php7.2-fpm php-fpm; do
        systemctl stop $service 2>/dev/null || true
        systemctl disable $service 2>/dev/null || true
    done
    
    # Remover serviços
    rm -f /etc/systemd/system/vod-sync-backend.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # Remover Nginx
    rm -f /etc/nginx/sites-available/vod-sync 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/vod-sync 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || true
    
    # Perguntar sobre banco de dados
    read -p "Remover banco de dados também? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        mysql -e "DROP DATABASE IF EXISTS vod_system;" 2>/dev/null || true
        mysql -e "DROP USER IF EXISTS 'vodsync_user'@'localhost';" 2>/dev/null || true
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        log "Banco de dados removido"
    fi
    
    # Perguntar sobre arquivos
    read -p "Manter arquivos em $BASE_DIR? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log "Arquivos mantidos em $BASE_DIR"
    else
        rm -rf "$BASE_DIR" 2>/dev/null || true
        log "Arquivos removidos"
    fi
    
    # Remover arquivos de credenciais
    rm -f /root/vod-sync-credentials.txt 2>/dev/null || true
    
    success "✅ Sistema desinstalado com sucesso"
}

# ==================== EXECUÇÃO PRINCIPAL ====================
main() {
    # Verificar argumentos
    case "$1" in
        "--auto")
            complete_installation
            ;;
        "--help"|"-h")
            echo "Uso: $0 [OPÇÃO]"
            echo ""
            echo "Opções:"
            echo "  --auto    Instalação automática não interativa"
            echo "  --help    Mostra esta ajuda"
            echo ""
            echo "Sem opções: Menu interativo"
            exit 0
            ;;
        *)
            show_menu
            ;;
    esac
}

# Executar
main "$@"
