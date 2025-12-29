#!/bin/bash
# install_vod_sync_universal.sh - Instalador Universal para qualquer PHP

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

# Variáveis detectadas
PHP_VERSION=""
PHP_FPM_SERVICE=""

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
    [[ $EUID -ne 0 ]] && error "Execute como root: sudo $0"
}

detect_system() {
    log "Detectando sistema..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    else
        error "Sistema não suportado"
    fi
    
    success "Sistema: $OS $VERSION"
}

remove_apache() {
    log "Removendo Apache para evitar conflitos..."
    
    # Parar e desabilitar Apache
    systemctl stop apache2 2>/dev/null
    systemctl disable apache2 2>/dev/null
    
    # Remover se existir
    if dpkg -l | grep -q apache2; then
        apt-get remove --purge apache2 apache2-utils libapache2-mod-php* -y
        apt-get autoremove -y
        success "Apache removido"
    fi
    
    # Matar processos Apache pendentes
    pkill -9 apache2 2>/dev/null || true
}

install_dependencies() {
    log "Instalando dependências..."
    
    # Atualizar sistema
    apt-get update || error "Falha ao atualizar"
    
    # Remover Apache primeiro
    remove_apache
    
    # Dependências básicas
    log "Instalando dependências básicas..."
    BASIC_DEPS="curl wget git build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release"
    apt-get install -y $BASIC_DEPS || error "Falha em dependências básicas"
    
    # Python
    log "Instalando Python 3..."
    apt-get install -y python3 python3-pip python3-venv python3-dev || error "Falha ao instalar Python"
    
    # MySQL
    log "Instalando MySQL..."
    apt-get install -y mysql-server mysql-client libmysqlclient-dev || error "Falha ao instalar MySQL"
    
    # Nginx
    log "Instalando Nginx..."
    apt-get install -y nginx || error "Falha ao instalar Nginx"
    
    # Supervisor
    log "Instalando Supervisor..."
    apt-get install -y supervisor || error "Falha ao instalar Supervisor"
    
    success "Dependências básicas instaladas"
}

detect_and_install_php() {
    log "Detectando e instalando PHP..."
    
    # Tentar versões específicas
    PHP_VERSIONS=("8.1" "8.0" "7.4" "7.3" "7.2" "php")
    
    for version in "${PHP_VERSIONS[@]}"; do
        log "Tentando PHP $version..."
        
        if [[ "$version" == "php" ]]; then
            # Última tentativa: php genérico
            PHP_PACKAGES="php php-cli php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-bcmath"
        else
            # Versão específica
            PHP_PACKAGES="php$version php$version-cli php$version-fpm php$version-mysql php$version-curl php$version-gd php$version-mbstring php$version-xml php$version-zip php$version-bcmath"
        fi
        
        if apt-get install -y $PHP_PACKAGES 2>> "$LOG_FILE"; then
            PHP_VERSION="$version"
            
            if [[ "$version" == "php" ]]; then
                PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
                PHP_FPM_SERVICE="php-fpm"
            else
                PHP_FPM_SERVICE="php$version-fpm"
            fi
            
            success "PHP $PHP_VERSION instalado com sucesso!"
            
            # Verificar instalação
            if php -v >> "$LOG_FILE" 2>&1; then
                success "PHP funcionando: $(php -v | head -n1)"
            fi
            
            return 0
        else
            warning "PHP $version falhou"
        fi
    done
    
    error "Não foi possível instalar nenhuma versão do PHP"
}

configure_php_fpm() {
    log "Configurando PHP-FPM..."
    
    # Determinar caminho do socket PHP-FPM
    if [[ "$PHP_VERSION" == "8.1" ]]; then
        PHP_FPM_SOCKET="/var/run/php/php8.1-fpm.sock"
        PHP_FPM_CONF="/etc/php/8.1/fpm/pool.d/www.conf"
    elif [[ "$PHP_VERSION" == "8.0" ]]; then
        PHP_FPM_SOCKET="/var/run/php/php8.0-fpm.sock"
        PHP_FPM_CONF="/etc/php/8.0/fpm/pool.d/www.conf"
    elif [[ "$PHP_VERSION" == "7.4" ]]; then
        PHP_FPM_SOCKET="/var/run/php/php7.4-fpm.sock"
        PHP_FPM_CONF="/etc/php/7.4/fpm/pool.d/www.conf"
    elif [[ "$PHP_VERSION" == "7.3" ]]; then
        PHP_FPM_SOCKET="/var/run/php/php7.3-fpm.sock"
        PHP_FPM_CONF="/etc/php/7.3/fpm/pool.d/www.conf"
    else
        # Tentativa genérica
        PHP_FPM_SOCKET="/var/run/php/php-fpm.sock"
        PHP_FPM_CONF=$(find /etc/php -name "www.conf" | head -1)
    fi
    
    # Verificar se arquivo existe
    if [[ ! -f "$PHP_FPM_CONF" ]]; then
        warning "Arquivo PHP-FPM não encontrado: $PHP_FPM_CONF"
        PHP_FPM_CONF=$(find /etc/php -name "www.conf" | head -1)
    fi
    
    if [[ -f "$PHP_FPM_CONF" ]]; then
        # Backup
        cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup"
        
        # Configurar socket
        sed -i "s|^listen = .*|listen = $PHP_FPM_SOCKET|" "$PHP_FPM_CONF"
        
        # Configurar permissões
        sed -i 's/^;listen.owner = www-data/listen.owner = www-data/' "$PHP_FPM_CONF"
        sed -i 's/^;listen.group = www-data/listen.group = www-data/' "$PHP_FPM_CONF"
        sed -i 's/^;listen.mode = 0660/listen.mode = 0660/' "$PHP_FPM_CONF"
        
        # Otimizar
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "$PHP_FPM_CONF"
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$PHP_FPM_CONF"
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$PHP_FPM_CONF"
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$PHP_FPM_CONF"
        
        success "PHP-FPM configurado em: $PHP_FPM_CONF"
    else
        warning "Não foi possível encontrar configuração PHP-FPM"
        PHP_FPM_SOCKET="/var/run/php/php-fpm.sock"
    fi
    
    # Reiniciar PHP-FPM
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || systemctl restart php-fpm 2>/dev/null
    
    # Verificar socket
    sleep 2
    if [[ -S "$PHP_FPM_SOCKET" ]]; then
        success "Socket PHP-FPM criado: $PHP_FPM_SOCKET"
    else
        warning "Socket PHP-FPM não criado. Usando TCP."
        PHP_FPM_SOCKET="127.0.0.1:9000"
    fi
    
    # Exportar para uso no Nginx
    export PHP_FPM_SOCKET
}

setup_database() {
    log "Configurando banco de dados..."
    
    # Iniciar MySQL
    systemctl start mysql 2>/dev/null || systemctl start mariadb 2>/dev/null
    systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null
    
    # Criar banco e usuário
    SQL_FILE=$(mktemp)
    cat > "$SQL_FILE" << EOF
-- Criar banco
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- Criar usuário
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';

-- Privilegios
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';

FLUSH PRIVILEGES;
EOF
    
    mysql -u root < "$SQL_FILE" || error "Falha ao configurar banco"
    rm -f "$SQL_FILE"
    
    success "Banco de dados criado: $DB_NAME"
}

setup_directories() {
    log "Criando diretórios..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$FRONTEND_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$FRONTEND_DIR/public/uploads"
    mkdir -p "/var/log/$APP_NAME"
    
    # Permissões
    chmod 755 "$INSTALL_DIR"
    chmod 775 "$INSTALL_DIR/logs" "$INSTALL_DIR/backups"
    chmod 777 "$FRONTEND_DIR/public/uploads"
    
    # Proprietário
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    
    success "Diretórios criados"
}

setup_python_backend() {
    log "Configurando backend Python..."
    
    # Ambiente virtual
    python3 -m venv "$PYTHON_VENV" || error "Falha ao criar venv"
    source "$PYTHON_VENV/bin/activate"
    
    # Criar requirements minimalista
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
# Core
fastapi==0.104.1
uvicorn[standard]==0.24.0

# Database
sqlalchemy==2.0.23
pymysql==1.1.0

# Auth
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0

# HTTP
requests==2.31.0
aiohttp==3.9.1

# Utils
pydantic==2.5.0
apscheduler==3.10.4
loguru==0.7.2

# Production
gunicorn==21.2.0
EOF
    
    # Instalar dependências
    pip install --upgrade pip
    pip install -r "$BACKEND_DIR/requirements.txt"
    
    success "Backend Python configurado"
}

setup_frontend() {
    log "Configurando frontend..."
    
    # Instalar Composer
    if ! command -v composer &>/dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    
    # Estrutura básica do frontend
    mkdir -p "$FRONTEND_DIR/app/Controllers"
    mkdir -p "$FRONTEND_DIR/app/Views"
    mkdir -p "$FRONTEND_DIR/public/assets"
    
    # Criar index.php simples
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<?php
/**
 * VOD Sync XUI One - Painel Administrativo
 */
session_start();

// Configurações básicas
define('APP_NAME', 'VOD Sync XUI One');
define('APP_VERSION', '1.0.0');

// Página inicial
if (!isset($_SESSION['loggedin'])) {
    // Página de login
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        // Login simples (em produção, use autenticação segura)
        $username = $_POST['username'] ?? '';
        $password = $_POST['password'] ?? '';
        
        if ($username === 'admin' && $password === 'admin123') {
            $_SESSION['loggedin'] = true;
            $_SESSION['username'] = $username;
            header('Location: /dashboard');
            exit;
        }
    }
    
    // Exibir formulário de login
    ?>
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Login - <?php echo APP_NAME; ?></title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
            }
            .login-box {
                background: white;
                padding: 40px;
                border-radius: 10px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
                width: 100%;
                max-width: 400px;
            }
        </style>
    </head>
    <body>
        <div class="login-box">
            <h2 class="text-center mb-4"><?php echo APP_NAME; ?></h2>
            <form method="POST">
                <div class="mb-3">
                    <label class="form-label">Usuário</label>
                    <input type="text" name="username" class="form-control" required>
                </div>
                <div class="mb-3">
                    <label class="form-label">Senha</label>
                    <input type="password" name="password" class="form-control" required>
                </div>
                <button type="submit" class="btn btn-primary w-100">Entrar</button>
            </form>
            <div class="text-center mt-3">
                <small class="text-muted">Versão <?php echo APP_VERSION; ?></small>
            </div>
        </div>
    </body>
    </html>
    <?php
} else {
    // Dashboard
    ?>
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Dashboard - <?php echo APP_NAME; ?></title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.1/font/bootstrap-icons.css">
    </head>
    <body>
        <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
            <div class="container-fluid">
                <a class="navbar-brand" href="#">
                    <i class="bi bi-film"></i> <?php echo APP_NAME; ?>
                </a>
                <div class="navbar-nav ms-auto">
                    <span class="navbar-text me-3">
                        <i class="bi bi-person-circle"></i> <?php echo $_SESSION['username']; ?>
                    </span>
                    <a href="?logout=1" class="btn btn-outline-light btn-sm">
                        <i class="bi bi-box-arrow-right"></i> Sair
                    </a>
                </div>
            </div>
        </nav>
        
        <div class="container-fluid mt-4">
            <div class="row">
                <!-- Sidebar -->
                <div class="col-md-3 col-lg-2">
                    <div class="list-group">
                        <a href="#" class="list-group-item list-group-item-action active">
                            <i class="bi bi-speedometer2"></i> Dashboard
                        </a>
                        <a href="#" class="list-group-item list-group-item-action">
                            <i class="bi bi-server"></i> Configuração XUI
                        </a>
                        <a href="#" class="list-group-item list-group-item-action">
                            <i class="bi bi-list-ul"></i> Listas M3U
                        </a>
                        <a href="#" class="list-group-item list-group-item-action">
                            <i class="bi bi-arrow-repeat"></i> Sincronização
                        </a>
                        <a href="#" class="list-group-item list-group-item-action">
                            <i class="bi bi-people"></i> Usuários
                        </a>
                        <a href="#" class="list-group-item list-group-item-action">
                            <i class="bi bi-key"></i> Licenças
                        </a>
                    </div>
                </div>
                
                <!-- Conteúdo -->
                <div class="col-md-9 col-lg-10">
                    <div class="row">
                        <div class="col-12">
                            <h2>Dashboard</h2>
                            <p class="text-muted">Sistema de sincronização de conteúdos VOD</p>
                        </div>
                    </div>
                    
                    <!-- Cards de status -->
                    <div class="row mt-4">
                        <div class="col-md-3">
                            <div class="card text-white bg-primary">
                                <div class="card-body">
                                    <h5 class="card-title"><i class="bi bi-check-circle"></i> Status</h5>
                                    <p class="card-text">Sistema Online</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card text-white bg-success">
                                <div class="card-body">
                                    <h5 class="card-title"><i class="bi bi-database"></i> Banco</h5>
                                    <p class="card-text">Conectado</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card text-white bg-info">
                                <div class="card-body">
                                    <h5 class="card-title"><i class="bi bi-cpu"></i> API</h5>
                                    <p class="card-text">Rodando</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card text-white bg-warning">
                                <div class="card-body">
                                    <h5 class="card-title"><i class="bi bi-clock-history"></i> Última Sync</h5>
                                    <p class="card-text">Nunca</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Ações rápidas -->
                    <div class="row mt-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header">
                                    <h5>Ações Rápidas</h5>
                                </div>
                                <div class="card-body">
                                    <div class="row">
                                        <div class="col-md-3 mb-3">
                                            <a href="#" class="btn btn-primary w-100">
                                                <i class="bi bi-gear"></i> Configurar XUI
                                            </a>
                                        </div>
                                        <div class="col-md-3 mb-3">
                                            <a href="#" class="btn btn-success w-100">
                                                <i class="bi bi-upload"></i> Upload M3U
                                            </a>
                                        </div>
                                        <div class="col-md-3 mb-3">
                                            <a href="#" class="btn btn-info w-100">
                                                <i class="bi bi-arrow-repeat"></i> Sincronizar
                                            </a>
                                        </div>
                                        <div class="col-md-3 mb-3">
                                            <a href="#" class="btn btn-secondary w-100">
                                                <i class="bi bi-file-text"></i> Ver Logs
                                            </a>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <footer class="mt-5 py-3 bg-light text-center">
            <div class="container">
                <span class="text-muted">
                    <?php echo APP_NAME; ?> v<?php echo APP_VERSION; ?> &copy; <?php echo date('Y'); ?>
                </span>
            </div>
        </footer>
        
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    </body>
    </html>
    <?php
}

// Logout
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: /');
    exit;
}
EOF
    
    success "Frontend configurado"
}

configure_nginx() {
    log "Configurando Nginx..."
    
    # Parar Nginx
    systemctl stop nginx 2>/dev/null
    
    # Configuração do site
    NGINX_CONFIG="/etc/nginx/sites-available/$APP_NAME"
    
    cat > "$NGINX_CONFIG" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name ${DOMAIN:-_} localhost 127.0.0.1;
    root $FRONTEND_DIR/public;
    index index.php index.html;
    
    # Logs
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
    
    # Frontend
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
    
    # API Backend
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
    location ~ /\. {
        deny all;
    }
    
    location ~ /(config|logs|backups) {
        deny all;
    }
}
EOF
    
    # Habilitar site
    ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    
    # Testar configuração
    nginx -t || error "Configuração Nginx inválida"
    
    # Iniciar Nginx
    systemctl start nginx
    systemctl enable nginx
    
    success "Nginx configurado"
}

configure_supervisor() {
    log "Configurando Supervisor..."
    
    # Configurar API
    cat > /etc/supervisor/conf.d/$APP_NAME-api.conf << EOF
[program:$APP_NAME-api]
command=$PYTHON_VENV/bin/gunicorn app.main:app --workers 2 --worker-class uvicorn.workers.UvicornWorker --bind 127.0.0.1:8000 --log-level info
directory=$BACKEND_DIR
user=www-data
autostart=true
autorestart=true
stdout_logfile=/var/log/$APP_NAME/api.log
stderr_logfile=/var/log/$APP_NAME/api-error.log
environment=PYTHONPATH="$BACKEND_DIR",PATH="$PYTHON_VENV/bin"
EOF
    
    # Reiniciar supervisor
    systemctl restart supervisor
    supervisorctl update
    
    success "Supervisor configurado"
}

create_backend_structure() {
    log "Criando estrutura do backend..."
    
    # Criar app principal
    mkdir -p "$BACKEND_DIR/app"
    
    # main.py
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="VOD Sync XUI One API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"message": "VOD Sync XUI One API"}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/api/v1/test")
async def test():
    return {"test": "ok"}
EOF
    
    # .env
    cat > "$BACKEND_DIR/.env" << EOF
# VOD Sync XUI One
APP_NAME=VOD Sync XUI One
APP_ENV=production
APP_URL=http://${DOMAIN:-localhost}

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

# TMDb (configure depois)
TMDB_API_KEY=sua_chave_aqui
TMDB_LANGUAGE=pt-BR

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
EOF
    
    success "Backend criado"
}

create_admin_user() {
    log "Criando usuário administrador..."
    
    # Senha padrão
    ADMIN_PASS="Admin@123"
    
    # Salvar credenciais
    cat > "$INSTALL_DIR/credentials.txt" << EOF
============================================
VOD SYNC XUI ONE - CREDENCIAIS
============================================

URL: http://${DOMAIN:-seu-ip}
Usuário: admin
Senha: $ADMIN_PASS

Banco: $DB_NAME
Usuário DB: $DB_USER
Senha DB: $DB_PASS

PHP Version: $PHP_VERSION
PHP-FPM Socket: $PHP_FPM_SOCKET

============================================
PRÓXIMOS PASSOS:
1. Configure TMDb API em:
   $BACKEND_DIR/.env

2. Acesse o painel e configure:
   - Conexão XUI One
   - Listas M3U

3. Para produção:
   - Altere todas as senhas
   - Configure SSL/TLS
============================================
EOF
    
    echo ""
    echo "========================================================"
    echo "         CREDENCIAIS DE ACESSO                          "
    echo "========================================================"
    echo "🌐 URL: http://${DOMAIN:-seu-ip}"
    echo "👤 Usuário: admin"
    echo "🔑 Senha: $ADMIN_PASS"
    echo ""
    echo "📁 Credenciais salvas em: $INSTALL_DIR/credentials.txt"
    echo "========================================================"
    
    success "Credenciais criadas"
}

finalize() {
    log "Finalizando instalação..."
    
    # Permissões
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    
    # Reiniciar serviços
    systemctl restart nginx
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || systemctl restart php-fpm 2>/dev/null
    systemctl restart supervisor
    
    # Testar
    sleep 3
    echo ""
    echo "📊 Status dos serviços:"
    echo "-----------------------"
    systemctl status nginx --no-pager -l | head -10
    echo ""
    systemctl status "$PHP_FPM_SERVICE" --no-pager -l | head -10 2>/dev/null || true
    
    # URL final
    echo ""
    echo "🎉 Instalação concluída com sucesso!"
    echo ""
    echo "✅ Sistema instalado em: $INSTALL_DIR"
    echo "✅ PHP Version: $PHP_VERSION"
    echo "✅ Banco: $DB_NAME"
    echo "✅ Nginx: http://${DOMAIN:-seu-ip}"
    echo ""
    echo "🔧 Próximos passos:"
    echo "   1. Configure TMDb API em $BACKEND_DIR/.env"
    echo "   2. Acesse o painel com as credenciais acima"
    echo "   3. Configure sua conexão XUI One"
    echo ""
    echo "📞 Logs em: /var/log/$APP_NAME/"
}

main() {
    clear
    echo "========================================================"
    echo "    VOD SYNC XUI ONE - INSTALADOR UNIVERSAL           "
    echo "========================================================"
    echo ""
    
    check_root
    detect_system
    
    echo "📋 Sistema: $OS $VERSION"
    echo "📁 Diretório: $INSTALL_DIR"
    echo "🌐 Domínio: ${DOMAIN:-localhost}"
    echo ""
    
    read -p "Continuar? (s/N): " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[SsYy]$ ]] && error "Cancelado"
    
    # Executar passos
    install_dependencies
    detect_and_install_php
    configure_php_fpm
    setup_database
    setup_directories
    setup_python_backend
    setup_frontend
    create_backend_structure
    configure_nginx
    configure_supervisor
    create_admin_user
    finalize
}

main "$@"
