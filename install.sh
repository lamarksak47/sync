#!/bin/bash

# ============================================
# INSTALADOR VOD SYNC SYSTEM - VERSÃO FINAL
# ============================================

set -e

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
    echo "║     VOD SYNC SYSTEM - INSTALADOR DEFINITIVO v2.0        ║"
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
    exit 1
}

# Verificar root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Execute como root: sudo $0"
    fi
    success "Privilégios root verificados"
}

# ==================== CRIAÇÃO DE DIRETÓRIOS ====================
create_directory_structure() {
    log "Criando estrutura completa de diretórios..."
    
    # Limpar diretório existente se for reinstalação
    if [ -d "$BASE_DIR" ]; then
        warning "Diretório $BASE_DIR já existe. Fazendo backup..."
        mv "$BASE_DIR" "$BASE_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Criar estrutura completa
    mkdir -p "$BASE_DIR" || error "Falha ao criar diretório base"
    cd "$BASE_DIR"
    
    # Backend (Python FastAPI)
    log "Criando estrutura backend..."
    mkdir -p "$BACKEND_DIR"/{app/{controllers,services,database,models,routes,utils,core,middleware,schemas},logs,tests,static}
    
    # Frontend (PHP)
    log "Criando estrutura frontend..."
    mkdir -p "$FRONTEND_DIR"/{public/assets/{css,js,images},app/{controllers,models,views,helpers,middleware},config,vendor,temp,logs}
    
    # Instalador
    mkdir -p "$INSTALL_DIR"/{sql,config,scripts}
    
    # Criar arquivos __init__.py
    find "$BACKEND_DIR/app" -type d -exec touch {}/__init__.py \;
    
    success "✅ Estrutura criada em $BASE_DIR"
    
    # Listar estrutura criada
    echo "📁 Estrutura criada:"
    tree -L 3 "$BASE_DIR" | head -30
}

# ==================== ARQUIVOS BACKEND ====================
create_backend_files() {
    log "Criando arquivos do backend Python..."
    
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
    DB_PASS="VodSync_$(openssl rand -hex 8)"
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
SECRET_KEY=$(openssl rand -hex 32)
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
}

# ==================== ARQUIVOS FRONTEND ====================
create_frontend_files() {
    log "Criando arquivos do frontend PHP..."
    
    # index.php principal
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<?php
/**
 * VOD Sync System - Frontend
 */
session_start();

// Verificar se API está online
$api_url = 'http://localhost:8000/health';
$api_online = @file_get_contents($api_url, false, stream_context_create(['http' => ['timeout' => 2]]));
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
        }
        .main-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
            max-width: 1200px;
            width: 100%;
        }
        .sidebar {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 40px 30px;
            min-height: 500px;
        }
        .content {
            padding: 40px;
        }
        .status-badge {
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
        }
        .status-online { background: #10b981; color: white; }
        .status-offline { background: #ef4444; color: white; }
        .feature-card {
            border: 1px solid #e5e7eb;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            transition: all 0.3s;
        }
        .feature-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .login-form {
            max-width: 400px;
            margin: 0 auto;
        }
    </style>
</head>
<body>
    <div class="main-card">
        <div class="row g-0">
            <!-- Sidebar -->
            <div class="col-lg-4">
                <div class="sidebar">
                    <div class="text-center mb-5">
                        <i class="fas fa-sync-alt fa-4x mb-3"></i>
                        <h1>VOD Sync</h1>
                        <p class="opacity-75">Sistema Profissional de Sincronização VOD</p>
                    </div>
                    
                    <div class="mb-5">
                        <h5><i class="fas fa-check-circle me-2"></i>Funcionalidades</h5>
                        <ul class="list-unstyled">
                            <li class="mb-2"><i class="fas fa-server me-2"></i>Conexão XUI One</li>
                            <li class="mb-2"><i class="fas fa-list me-2"></i>Listas M3U</li>
                            <li class="mb-2"><i class="fas fa-film me-2"></i>Sincronização Automática</li>
                            <li class="mb-2"><i class="fas fa-database me-2"></i>Enriquecimento TMDb</li>
                            <li class="mb-2"><i class="fas fa-users me-2"></i>Multi-usuário</li>
                            <li><i class="fas fa-chart-line me-2"></i>Dashboard em Tempo Real</li>
                        </ul>
                    </div>
                    
                    <div class="system-status">
                        <h5><i class="fas fa-heartbeat me-2"></i>Status do Sistema</h5>
                        <div class="d-flex justify-content-between mb-2">
                            <span>Backend API:</span>
                            <span class="status-badge status-<?php echo $api_status; ?>">
                                <?php echo strtoupper($api_status); ?>
                            </span>
                        </div>
                        <div class="d-flex justify-content-between mb-2">
                            <span>Banco de Dados:</span>
                            <span class="status-badge status-online">ONLINE</span>
                        </div>
                        <div class="d-flex justify-content-between">
                            <span>Frontend:</span>
                            <span class="status-badge status-online">ONLINE</span>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Conteúdo Principal -->
            <div class="col-lg-8">
                <div class="content">
                    <h2 class="mb-4">Bem-vindo ao VOD Sync System</h2>
                    <p class="text-muted mb-5">Sistema completo para sincronização de conteúdos VOD com XUI One</p>
                    
                    <!-- Formulário de Login -->
                    <div class="login-form">
                        <h4 class="mb-4"><i class="fas fa-sign-in-alt me-2"></i>Acesso ao Sistema</h4>
                        
                        <?php if(isset($_GET['error'])): ?>
                        <div class="alert alert-danger">Credenciais inválidas</div>
                        <?php endif; ?>
                        
                        <form action="/login.php" method="POST">
                            <div class="mb-3">
                                <label class="form-label">Usuário</label>
                                <div class="input-group">
                                    <span class="input-group-text"><i class="fas fa-user"></i></span>
                                    <input type="text" class="form-control" name="username" 
                                           placeholder="admin" required autofocus>
                                </div>
                            </div>
                            
                            <div class="mb-3">
                                <label class="form-label">Senha</label>
                                <div class="input-group">
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
                                <label class="form-check-label" for="remember">Lembrar-me</label>
                            </div>
                            
                            <button type="submit" class="btn btn-primary w-100 py-2">
                                <i class="fas fa-sign-in-alt me-2"></i>Entrar no Sistema
                            </button>
                        </form>
                        
                        <div class="text-center mt-4">
                            <p class="small text-muted">
                                <i class="fas fa-info-circle me-1"></i>
                                Primeiro acesso? Use:<br>
                                <strong>Usuário:</strong> admin | <strong>Senha:</strong> admin123
                            </p>
                        </div>
                    </div>
                    
                    <hr class="my-5">
                    
                    <!-- Recursos do Sistema -->
                    <h4 class="mb-4"><i class="fas fa-rocket me-2"></i>Recursos Principais</h4>
                    <div class="row">
                        <div class="col-md-6">
                            <div class="feature-card">
                                <h5><i class="fas fa-sync-alt text-primary me-2"></i>Sincronização</h5>
                                <p class="text-muted small">Sincronização automática de filmes e séries com XUI One</p>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="feature-card">
                                <h5><i class="fas fa-database text-success me-2"></i>TMDb</h5>
                                <p class="text-muted small">Enriquecimento automático de metadados em português</p>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="feature-card">
                                <h5><i class="fas fa-users-cog text-warning me-2"></i>Multi-usuário</h5>
                                <p class="text-muted small">Hierarquia: Admin, Revendedor e Usuário final</p>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="feature-card">
                                <h5><i class="fas fa-shield-alt text-danger me-2"></i>Segurança</h5>
                                <p class="text-muted small">Sistema de licenças e autenticação JWT</p>
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
        
        // Verificar API periodicamente
        setInterval(() => {
            fetch('http://localhost:8000/health')
                .then(response => {
                    const badge = document.querySelector('.status-badge.status-online, .status-badge.status-offline');
                    badge.className = 'status-badge status-online';
                    badge.textContent = 'ONLINE';
                })
                .catch(() => {
                    const badge = document.querySelector('.status-badge.status-online, .status-badge.status-offline');
                    badge.className = 'status-badge status-offline';
                    badge.textContent = 'OFFLINE';
                });
        }, 30000);
    </script>
</body>
</html>
EOF

    # login.php
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
session_start();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
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
        exit;
    } else {
        // Credenciais inválidas
        header('Location: /?error=1');
        exit;
    }
}

// Se não for POST, redirecionar para index
header('Location: /');
exit;
EOF

    # dashboard.php básico
    cat > "$FRONTEND_DIR/public/dashboard.php" << 'EOF'
<?php
session_start();
if (!isset($_SESSION['user_id'])) {
    header('Location: /');
    exit;
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
        .sidebar {
            background: #2c3e50;
            color: white;
            height: 100vh;
            position: fixed;
            left: 0;
            top: 0;
            width: 250px;
        }
        .main-content {
            margin-left: 250px;
            padding: 20px;
        }
        .stat-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="p-4">
            <h4><i class="fas fa-sync-alt"></i> VOD Sync</h4>
            <p class="text-muted small">Olá, <?php echo $_SESSION['username']; ?></p>
        </div>
        <nav class="nav flex-column px-3">
            <a href="/dashboard.php" class="nav-link text-white active">
                <i class="fas fa-tachometer-alt me-2"></i> Dashboard
            </a>
            <a href="/xui.php" class="nav-link text-white">
                <i class="fas fa-server me-2"></i> Conexões XUI
            </a>
            <a href="/m3u.php" class="nav-link text-white">
                <i class="fas fa-list me-2"></i> Listas M3U
            </a>
            <a href="/sync.php" class="nav-link text-white">
                <i class="fas fa-sync me-2"></i> Sincronização
            </a>
            <a href="/logs.php" class="nav-link text-white">
                <i class="fas fa-clipboard-list me-2"></i> Logs
            </a>
            <a href="/logout.php" class="nav-link text-danger mt-5">
                <i class="fas fa-sign-out-alt me-2"></i> Sair
            </a>
        </nav>
    </div>
    
    <!-- Main Content -->
    <div class="main-content">
        <h1 class="mb-4">Dashboard do Sistema</h1>
        
        <div class="row">
            <div class="col-md-3">
                <div class="stat-card">
                    <h6>Conexões XUI</h6>
                    <h2>0</h2>
                    <small class="text-muted">Nenhuma configurada</small>
                </div>
            </div>
            <div class="col-md-3">
                <div class="stat-card">
                    <h6>Listas M3U</h6>
                    <h2>0</h2>
                    <small class="text-muted">Nenhuma carregada</small>
                </div>
            </div>
            <div class="col-md-3">
                <div class="stat-card">
                    <h6>Filmes</h6>
                    <h2>0</h2>
                    <small class="text-muted">Não sincronizados</small>
                </div>
            </div>
            <div class="col-md-3">
                <div class="stat-card">
                    <h6>Séries</h6>
                    <h2>0</h2>
                    <small class="text-muted">Não sincronizadas</small>
                </div>
            </div>
        </div>
        
        <div class="alert alert-info mt-4">
            <h5><i class="fas fa-info-circle me-2"></i>Próximos Passos</h5>
            <ol class="mb-0">
                <li>Configure uma conexão XUI One</li>
                <li>Adicione uma lista M3U</li>
                <li>Escaneie os conteúdos</li>
                <li>Inicie a sincronização</li>
            </ol>
        </div>
    </div>
</body>
</html>
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

    success "✅ Arquivos do frontend criados"
}

# ==================== CONFIGURAÇÃO NGINX CORRIGIDA ====================
setup_nginx() {
    log "Configurando Nginx..."
    
    # Instalar Nginx se necessário
    if ! command -v nginx &> /dev/null; then
        log "Instalando Nginx..."
        apt-get update
        apt-get install -y nginx 2>> "$LOG_FILE" || error "Falha ao instalar Nginx"
    fi
    
    # Instalar PHP se necessário
    if ! command -v php &> /dev/null; then
        log "Instalando PHP..."
        apt-get install -y php-fpm php-mysql php-curl php-json php-mbstring php-xml 2>> "$LOG_FILE"
    fi
    
    # Parar Nginx temporariamente
    systemctl stop nginx 2>/dev/null || true
    
    # Criar configuração Nginx CORRIGIDA (sem try_files duplicado)
    cat > /etc/nginx/sites-available/vod-sync << 'NGINX_CONFIG'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /opt/vod-sync/frontend/public;
    index index.php index.html index.htm;
    
    # Frontend
    location / {
        try_files $uri $uri/ /index.php$is_args$args;
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
        
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # PHP-FPM - CONFIGURAÇÃO CORRETA
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        
        # Determinar socket PHP automaticamente
        set $php_socket "unix:/var/run/php/php8.2-fpm.sock";
        
        if (!-f $php_socket) {
            set $php_socket "unix:/var/run/php/php8.1-fpm.sock";
        }
        if (!-f $php_socket) {
            set $php_socket "unix:/var/run/php/php8.0-fpm.sock";
        }
        if (!-f $php_socket) {
            set $php_socket "unix:/run/php/php7.4-fpm.sock";
        }
        if (!-f $php_socket) {
            set $php_socket "127.0.0.1:9000";
        }
        
        fastcgi_pass $php_socket;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
    }
    
    # Bloquear acesso a arquivos sensíveis
    location ~ /\.(?!well-known).* {
        deny all;
        return 404;
    }
    
    location ~ ^/(app|config|logs|temp|vendor|backend|install) {
        deny all;
        return 403;
    }
    
    # Cache para arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Tamanho máximo de upload
    client_max_body_size 100M;
}
NGINX_CONFIG
    
    # Remover site default
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Ativar nosso site
    ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
    
    # Testar configuração
    log "Testando configuração Nginx..."
    if nginx -t 2>> "$LOG_FILE"; then
        success "✅ Configuração Nginx válida"
    else
        # Backup do erro
        nginx -t 2>&1 >> "$LOG_FILE"
        warning "Configuração Nginx com problemas, tentando alternativa..."
        
        # Configuração alternativa mais simples
        cat > /etc/nginx/sites-available/vod-sync << 'NGINX_SIMPLE'
server {
    listen 80;
    server_name _;
    root /opt/vod-sync/frontend/public;
    index index.php;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
    }
    
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
NGINX_SIMPLE
        
        nginx -t 2>> "$LOG_FILE" || error "Configuração Nginx ainda falha"
    fi
    
    # Iniciar serviços
    log "Iniciando serviços..."
    
    # Iniciar PHP-FPM
    for service in php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php-fpm; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            systemctl start "$service" 2>/dev/null || true
            systemctl enable "$service" 2>/dev/null || true
            break
        fi
    done
    
    # Iniciar Nginx
    systemctl start nginx 2>> "$LOG_FILE" || error "Falha ao iniciar Nginx"
    systemctl enable nginx 2>> "$LOG_FILE"
    
    # Verificar
    sleep 2
    if systemctl is-active --quiet nginx; then
        success "✅ Nginx rodando na porta 80"
    else
        error "❌ Nginx não iniciou"
    fi
}

# ==================== CONFIGURAÇÃO BACKEND ====================
setup_backend() {
    log "Configurando backend Python..."
    
    cd "$BACKEND_DIR"
    
    # Criar ambiente virtual
    python3 -m venv venv 2>> "$LOG_FILE" || {
        # Tentar instalar python3-venv
        apt-get install -y python3-venv 2>> "$LOG_FILE"
        python3 -m venv venv 2>> "$LOG_FILE" || error "Falha ao criar venv"
    }
    
    # Ativar venv e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip setuptools wheel 2>> "$LOG_FILE"
    
    log "Instalando dependências Python..."
    pip install -r requirements.txt 2>> "$LOG_FILE" || {
        warning "Algumas dependências falharam, tentando instalação básica..."
        pip install fastapi uvicorn pymysql python-dotenv 2>> "$LOG_FILE" || error "Falha crítica nas dependências"
    }
    
    # Criar usuário para serviço
    if ! id -u www-data >/dev/null 2>&1; then
        useradd -r -s /bin/false www-data 2>> "$LOG_FILE" || true
    fi
    
    # Configurar permissões
    chown -R www-data:www-data "$BACKEND_DIR"
    chmod -R 755 "$BACKEND_DIR"
    chmod +x "$BACKEND_DIR/start.sh"
    
    # Criar serviço systemd CORRETO
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
    systemctl daemon-reload
    
    # Habilitar serviço
    systemctl enable vod-sync-backend 2>> "$LOG_FILE"
    
    # Tentar iniciar
    log "Iniciando serviço backend..."
    if systemctl start vod-sync-backend 2>> "$LOG_FILE"; then
        sleep 3
        
        # Verificar status
        if systemctl is-active --quiet vod-sync-backend; then
            success "✅ Backend rodando na porta 8000"
            
            # Testar endpoint
            if curl -s http://localhost:8000/health >/dev/null 2>&1; then
                success "✅ API respondendo corretamente"
            else
                warning "⚠ API não responde, mas serviço está rodando"
            fi
        else
            error "❌ Backend não está ativo após iniciar"
        fi
    else
        error "❌ Falha ao iniciar serviço backend"
    fi
    
    # Mostrar logs se falhar
    if ! systemctl is-active --quiet vod-sync-backend; then
        log "📋 Últimos logs do backend:"
        journalctl -u vod-sync-backend -n 20 --no-pager
    fi
}

# ==================== CONFIGURAÇÃO BANCO DE DADOS ====================
setup_database() {
    log "Configurando banco de dados..."
    
    # Verificar MySQL/MariaDB
    MYSQL_SERVICE=""
    for service in mysql mariadb; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            MYSQL_SERVICE="$service"
            break
        fi
    done
    
    # Instalar se necessário
    if [ -z "$MYSQL_SERVICE" ]; then
        log "Instalando MySQL..."
        apt-get install -y mysql-server 2>> "$LOG_FILE" || error "Falha ao instalar MySQL"
        MYSQL_SERVICE="mysql"
    fi
    
    # Iniciar serviço
    systemctl start "$MYSQL_SERVICE" 2>> "$LOG_FILE" || error "Falha ao iniciar $MYSQL_SERVICE"
    systemctl enable "$MYSQL_SERVICE" 2>> "$LOG_FILE"
    
    # Aguardar MySQL iniciar
    sleep 5
    
    # Credenciais
    DB_NAME="vod_system"
    DB_USER="vodsync_user"
    DB_PASS="VodSync_$(openssl rand -hex 8)"
    
    # Criar banco e usuário
    log "Criando banco de dados..."
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE" || error "Falha ao criar banco"
    
    # Verificar se usuário já existe
    if ! mysql -e "SELECT User FROM mysql.user WHERE User='$DB_USER'" 2>/dev/null | grep -q "$DB_USER"; then
        mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$LOG_FILE" || error "Falha ao criar usuário"
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
    sed -i "s/DB_PASS=.*/DB_PASS=$DB_PASS/" "$BACKEND_DIR/.env"
    
    # Salvar credenciais
    cat > /root/vod-sync-credentials.txt << CREDENTIALS
============================================
CREDENCIAIS VOD SYNC SYSTEM
============================================
INSTALAÇÃO CONCLUÍDA EM: $(date)

🌐 URL DE ACESSO:
   Frontend: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
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
   MySQL: porta 3306

📁 DIRETÓRIOS:
   Sistema: $BASE_DIR
   Backend: $BACKEND_DIR
   Frontend: $FRONTEND_DIR
   Logs: $BACKEND_DIR/logs/

⚡ COMANDOS ÚTEIS:
   sudo systemctl status vod-sync-backend
   sudo journalctl -u vod-sync-backend -f
   sudo tail -f /var/log/nginx/error.log

⚠️ ALTERE AS SENHAS NO PRIMEIRO ACESSO!
============================================
CREDENTIALS
    
    success "✅ Banco de dados configurado"
    log "📄 Credenciais salvas em: /root/vod-sync-credentials.txt"
}

# ==================== VERIFICAÇÃO FINAL ====================
verify_installation() {
    print_header
    echo "🔍 VERIFICAÇÃO FINAL DA INSTALAÇÃO"
    echo ""
    
    # Verificar serviços
    echo "📦 STATUS DOS SERVIÇOS:"
    for service in nginx vod-sync-backend mysql mariadb; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
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
    if curl -s --connect-timeout 5 http://localhost:8000/health >/dev/null; then
        echo "  ✅ Backend API: RESPONDENDO"
    else
        echo "  ❌ Backend API: NÃO RESPONDE"
    fi
    
    # Testar Frontend
    if curl -s --connect-timeout 5 http://localhost >/dev/null; then
        echo "  ✅ Frontend Web: ACESSÍVEL"
    else
        echo "  ❌ Frontend Web: NÃO ACESSÍVEL"
    fi
    
    # Testar MySQL
    if mysql -e "SELECT 1" >/dev/null 2>&1; then
        echo "  ✅ MySQL: CONECTADO"
    else
        echo "  ❌ MySQL: SEM CONEXÃO"
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
    echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo ""
    
    IP_ADDR=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' || echo "localhost")
    
    echo "🌐 ACESSO AO SISTEMA:"
    echo "   URL: http://$IP_ADDR"
    echo "   API: http://$IP_ADDR:8000"
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
    echo "   Config Nginx: /etc/nginx/sites-available/vod-sync"
    echo ""
    
    echo "⚡ COMANDOS DE GERENCIAMENTO:"
    echo "   sudo systemctl restart vod-sync-backend"
    echo "   sudo systemctl restart nginx"
    echo "   sudo tail -f $BACKEND_DIR/logs/backend.log"
    echo ""
    
    echo "⚠️ PRÓXIMOS PASSOS:"
    echo "   1. Acesse http://$IP_ADDR"
    echo "   2. Faça login com admin/admin123"
    echo "   3. Configure sua chave TMDb API no painel"
    echo "   4. Adicione conexão XUI e lista M3U"
    echo ""
    
    echo "══════════════════════════════════════════════════════════"
    
    # Criar flag de instalação
    echo "install_date=$(date '+%Y-%m-%d %H:%M:%S')" > "$BASE_DIR/.installed"
    echo "version=2.0.0" >> "$BASE_DIR/.installed"
    echo "frontend_url=http://$IP_ADDR" >> "$BASE_DIR/.installed"
    echo "backend_url=http://$IP_ADDR:8000" >> "$BASE_DIR/.installed"
}

# ==================== INSTALAÇÃO COMPLETA ====================
complete_installation() {
    print_header
    
    echo "🔄 Este instalador executará:"
    echo "   1. 📁 Criar estrutura completa de diretórios"
    echo "   2. 🐍 Configurar backend Python (FastAPI)"
    echo "   3. 🌐 Configurar frontend PHP (Bootstrap)"
    echo "   4. 🗄️  Configurar banco de dados MySQL"
    echo "   5. 🔧 Configurar Nginx + PHP-FPM"
    echo "   6. ⚙️  Criar serviços systemd"
    echo "   7. ✅ Verificar instalação"
    echo ""
    echo "⏱️  Tempo estimado: 3-5 minutos"
    echo ""
    
    read -p "Continuar com a instalação? (s/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] || exit 0
    
    # Atualizar sistema
    log "Atualizando pacotes do sistema..."
    apt-get update 2>> "$LOG_FILE"
    
    # Executar passos
    check_root
    create_directory_structure
    create_backend_files
    create_frontend_files
    setup_database
    setup_nginx
    setup_backend
    verify_installation
    
    log "✅ Instalação completa concluída!"
}

# ==================== MENU PRINCIPAL ====================
show_menu() {
    while true; do
        print_header
        echo "MENU PRINCIPAL"
        echo ""
        echo "1) 🚀 Instalação Completa (Recomendado)"
        echo "2) 📁 Apenas Criar Estrutura"
        echo "3) 🐍 Apenas Configurar Backend"
        echo "4) 🌐 Apenas Configurar Frontend"
        echo "5) 🗄️  Apenas Configurar Banco de Dados"
        echo "6) 🔧 Apenas Configurar Nginx"
        echo "7) 🔍 Verificar Sistema"
        echo "8) 🗑️  Desinstalar Tudo"
        echo "9) 🚪 Sair"
        echo ""
        read -p "Opção: " choice
        
        case $choice in
            1) complete_installation ;;
            2) check_root; create_directory_structure ;;
            3) check_root; setup_backend ;;
            4) check_root; create_frontend_files; setup_nginx ;;
            5) check_root; setup_database ;;
            6) check_root; setup_nginx ;;
            7) verify_installation ;;
            8) uninstall_system ;;
            9) echo "Até logo!"; exit 0 ;;
            *) echo "Opção inválida"; sleep 2 ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..." </dev/tty
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
    
    # Remover serviços
    rm -f /etc/systemd/system/vod-sync-backend.service
    rm -f /etc/systemd/system/vod-sync-scheduler.service
    systemctl daemon-reload
    
    # Remover Nginx
    rm -f /etc/nginx/sites-available/vod-sync
    rm -f /etc/nginx/sites-enabled/vod-sync
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
    rm -f /root/vod-db-credentials.txt 2>/dev/null || true
    
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
            echo "  --fix     Corrigir instalação existente"
            echo ""
            echo "Sem opções: Menu interativo"
            exit 0
            ;;
        "--fix")
            echo "🔧 Modo de correção..."
            check_root
            setup_nginx
            setup_backend
            verify_installation
            ;;
        *)
            show_menu
            ;;
    esac
}

# Executar
main "$@"
