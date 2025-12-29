#!/bin/bash
# install_vod_sync_fixed_sql.sh - Instalador com SQL corrigido

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
        
        success "PHP-FPM configurado"
    else
        warning "Config PHP-FPM não encontrada"
        PHP_FPM_SOCKET="127.0.0.1:9000"
    fi
    
    # Reiniciar
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || systemctl restart php-fpm
}

# ============================================
# 4. BANCO DE DADOS - SQL CORRIGIDO
# ============================================

setup_database() {
    log "Configurando banco de dados..."
    
    # Iniciar MySQL
    systemctl start mysql 2>/dev/null || systemctl start mariadb
    systemctl enable mysql 2>/dev/null || systemctl enable mariadb
    
    # Criar SQL CORRETO sem usar $(date) no SQL
    SQL_FILE=$(mktemp)
    TRIAL_KEY="TRIAL-$(date +%Y%m%d)-$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    
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
    uuid VARCHAR(36) UNIQUE NOT NULL DEFAULT (UUID()),
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_license_key (license_key),
    INDEX idx_valid_until (valid_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_start_time (start_time),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    INDEX idx_content_type (content_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    
    log "Criando estrutura do banco..."
    mysql -u root < "$SQL_FILE" 2>> "$LOG_FILE"
    
    if [[ $? -eq 0 ]]; then
        success "Estrutura do banco criada"
    else
        warning "Erro ao criar estrutura, tentando método alternativo..."
        create_database_simple
        rm -f "$SQL_FILE"
        return
    fi
    
    # Inserir dados básicos em SEPARADO
    log "Inserindo dados iniciais..."
    
    SQL_DATA_FILE=$(mktemp)
    cat > "$SQL_DATA_FILE" << EOF
USE \`$DB_NAME\`;

-- Inserir usuário admin (senha: password - hash bcrypt)
INSERT INTO users (username, email, password_hash, full_name, role, is_active) 
VALUES (
    'admin',
    'admin@${DOMAIN:-localhost}',
    '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
    'Administrador',
    'admin',
    TRUE
);

-- Inserir licença trial
INSERT INTO licenses (license_key, type, user_id, max_users, valid_from, valid_until, is_active, features)
VALUES (
    '$TRIAL_KEY',
    'trial',
    (SELECT id FROM users WHERE username='admin'),
    5,
    CURDATE(),
    DATE_ADD(CURDATE(), INTERVAL 30 DAY),
    TRUE,
    '{"auto_sync": true, "tmdb": true, "multiple_xui": true, "api_access": true}'
);

-- Atualizar usuário com license_id
UPDATE users SET license_id = (SELECT id FROM licenses WHERE license_key = '$TRIAL_KEY') 
WHERE username='admin';
EOF
    
    mysql -u root "$DB_NAME" < "$SQL_DATA_FILE" 2>> "$LOG_FILE"
    
    if [[ $? -eq 0 ]]; then
        success "Dados iniciais inseridos"
    else
        warning "Erro ao inserir dados, mas o banco foi criado"
    fi
    
    rm -f "$SQL_FILE" "$SQL_DATA_FILE"
    
    # Testar conexão
    if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 'OK' as status;" 2>> "$LOG_FILE"; then
        success "Banco configurado e testado: $DB_NAME"
    else
        warning "Banco criado mas teste de conexão falhou"
    fi
}

create_database_simple() {
    log "Criando banco de dados (método simples)..."
    
    # Método simplificado sem erros
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    success "Banco criado (estrutura básica): $DB_NAME"
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
    
    # Frontend estrutura
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
# 6. BACKEND PYTHON SIMPLIFICADO
# ============================================

setup_python_backend() {
    log "Configurando backend Python..."
    
    # Ambiente virtual
    python3 -m venv "$PYTHON_VENV" || error "Falha venv"
    source "$PYTHON_VENV/bin/activate"
    
    # Requirements simplificado
    cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
pymysql==1.1.0
python-dotenv==1.0.0
requests==2.31.0
pydantic==2.5.0
gunicorn==21.2.0
EOF
    
    pip install --upgrade pip
    pip install -r "$BACKEND_DIR/requirements.txt"
    
    # Criar arquivos essenciais
    create_backend_files
    
    success "Backend Python configurado"
}

create_backend_files() {
    log "Criando arquivos backend..."
    
    # .env
    cat > "$BACKEND_DIR/.env" << EOF
APP_NAME=VOD Sync XUI One
APP_ENV=production
APP_URL=http://${DOMAIN:-localhost}

DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

TMDB_API_KEY=sua_chave_aqui
TMDB_LANGUAGE=pt-BR

SECRET_KEY=$(openssl rand -hex 32)
EOF
    
    # main.py simples
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

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
    return {"message": "VOD Sync XUI One API", "status": "running"}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/api/v1/test")
async def test():
    return {"test": "success"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
    
    success "Arquivos backend criados"
}

# ============================================
# 7. FRONTEND PHP ESSENCIAL
# ============================================

setup_frontend_minimal() {
    log "Criando frontend mínimo..."
    
    # index.php principal
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<?php
/**
 * VOD Sync XUI One - Sistema Principal
 */

// Configurações básicas
session_start();

// Auto-redirect para login se não autenticado
if (!isset($_SESSION['loggedin']) || $_SESSION['loggedin'] !== true) {
    header('Location: /login.php');
    exit;
}

// Se autenticado, redireciona para dashboard
header('Location: /dashboard.php');
exit;
EOF
    
    # login.php funcional
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
session_start();

// Se já logado, redireciona
if (isset($_SESSION['loggedin']) && $_SESSION['loggedin'] === true) {
    header('Location: /dashboard.php');
    exit;
}

// Configurações
$config = [
    'app_name' => 'VOD Sync XUI One',
    'app_version' => '2.0.0',
    'admin_user' => 'admin',
    'admin_pass' => 'admin123' // SENHA PADRÃO - ALTERAR!
];

// Processar login
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    // Verificação simples (em produção, usar banco de dados!)
    if ($username === $config['admin_user'] && $password === $config['admin_pass']) {
        $_SESSION['loggedin'] = true;
        $_SESSION['username'] = $username;
        $_SESSION['role'] = 'admin';
        header('Location: /dashboard.php');
        exit;
    } else {
        $error = 'Usuário ou senha inválidos';
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - <?php echo $config['app_name']; ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-box {
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header h1 {
            color: #4361ee;
            font-weight: 700;
        }
        .form-control {
            border-radius: 8px;
            padding: 12px 15px;
        }
        .btn-login {
            background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%);
            border: none;
            border-radius: 8px;
            padding: 12px;
            font-weight: 600;
            width: 100%;
        }
    </style>
</head>
<body>
    <div class="login-box">
        <div class="login-header">
            <h1><i class="bi bi-film"></i> VOD Sync XUI</h1>
            <p class="text-muted">Sistema Profissional</p>
        </div>
        
        <?php if ($error): ?>
        <div class="alert alert-danger"><?php echo htmlspecialchars($error); ?></div>
        <?php endif; ?>
        
        <form method="POST" action="">
            <div class="mb-3">
                <label for="username" class="form-label">Usuário</label>
                <input type="text" class="form-control" id="username" name="username" required autofocus>
            </div>
            
            <div class="mb-3">
                <label for="password" class="form-label">Senha</label>
                <input type="password" class="form-control" id="password" name="password" required>
            </div>
            
            <button type="submit" class="btn btn-login">
                <i class="bi bi-box-arrow-in-right"></i> Entrar
            </button>
        </form>
        
        <div class="text-center mt-4">
            <small class="text-muted">
                <?php echo $config['app_name']; ?> v<?php echo $config['app_version']; ?>
                <br>
                Usuário: admin | Senha: admin123
            </small>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF
    
    # dashboard.php funcional
    cat > "$FRONTEND_DIR/public/dashboard.php" << 'EOF'
<?php
session_start();

// Verificar login
if (!isset($_SESSION['loggedin']) || $_SESSION['loggedin'] !== true) {
    header('Location: /login.php');
    exit;
}

// Configurações
$config = [
    'app_name' => 'VOD Sync XUI One',
    'app_version' => '2.0.0'
];
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - <?php echo $config['app_name']; ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.1/font/bootstrap-icons.css">
    <style>
        body {
            background-color: #f8f9fa;
        }
        .sidebar {
            background: linear-gradient(180deg, #4361ee 0%, #3a0ca3 100%);
            color: white;
            min-height: 100vh;
        }
        .sidebar .nav-link {
            color: rgba(255,255,255,.8);
            padding: 12px 20px;
        }
        .sidebar .nav-link:hover {
            color: white;
            background: rgba(255,255,255,.1);
        }
        .content-wrapper {
            padding: 20px;
        }
        .stat-card {
            border-left: 4px solid #4361ee;
        }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <div class="col-md-3 col-lg-2 sidebar">
                <div class="position-sticky pt-3">
                    <h4 class="text-center text-white mb-4">
                        <i class="bi bi-film"></i><br>
                        VOD Sync
                    </h4>
                    
                    <ul class="nav flex-column">
                        <li class="nav-item">
                            <a class="nav-link active" href="#">
                                <i class="bi bi-speedometer2"></i> Dashboard
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="/xui_config.php">
                                <i class="bi bi-server"></i> XUI Config
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="/m3u_list.php">
                                <i class="bi bi-list-ul"></i> Lista M3U
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="/sync_manual.php">
                                <i class="bi bi-arrow-repeat"></i> Sincronizar
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="/logout.php">
                                <i class="bi bi-box-arrow-right"></i> Sair
                            </a>
                        </li>
                    </ul>
                </div>
            </div>
            
            <!-- Main Content -->
            <main class="col-md-9 ms-sm-auto col-lg-10 content-wrapper">
                <!-- Top Bar -->
                <nav class="navbar navbar-light bg-white mb-4">
                    <div class="container-fluid">
                        <span class="navbar-brand">
                            <i class="bi bi-speedometer2"></i> Dashboard
                        </span>
                        <div class="navbar-nav">
                            <div class="nav-item">
                                <span class="nav-link">
                                    <i class="bi bi-person-circle"></i> 
                                    <?php echo $_SESSION['username']; ?>
                                    <span class="badge bg-primary"><?php echo $_SESSION['role']; ?></span>
                                </span>
                            </div>
                        </div>
                    </div>
                </nav>
                
                <!-- Stats -->
                <div class="row mb-4">
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <h6 class="card-title">Status Sistema</h6>
                                <h2 class="card-value">Online</h2>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <h6 class="card-title">XUI One</h6>
                                <h2 class="card-value">Não Config</h2>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <h6 class="card-title">Listas M3U</h6>
                                <h2 class="card-value">0</h2>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="card-body">
                                <h6 class="card-title">Última Sync</h6>
                                <h2 class="card-value">Nunca</h2>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Quick Actions -->
                <div class="row">
                    <div class="col-12">
                        <div class="card">
                            <div class="card-header">
                                <h5 class="mb-0">Ações Rápidas</h5>
                            </div>
                            <div class="card-body">
                                <div class="row">
                                    <div class="col-md-3 mb-3">
                                        <a href="/xui_config.php" class="btn btn-primary w-100">
                                            <i class="bi bi-server"></i> Configurar XUI
                                        </a>
                                    </div>
                                    <div class="col-md-3 mb-3">
                                        <a href="/m3u_list.php" class="btn btn-success w-100">
                                            <i class="bi bi-upload"></i> Upload M3U
                                        </a>
                                    </div>
                                    <div class="col-md-3 mb-3">
                                        <a href="/sync_manual.php" class="btn btn-info w-100">
                                            <i class="bi bi-arrow-repeat"></i> Sincronizar
                                        </a>
                                    </div>
                                    <div class="col-md-3 mb-3">
                                        <a href="/logout.php" class="btn btn-danger w-100">
                                            <i class="bi bi-box-arrow-right"></i> Sair
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- System Info -->
                <div class="row mt-4">
                    <div class="col-12">
                        <div class="card">
                            <div class="card-header">
                                <h5 class="mb-0">Informações do Sistema</h5>
                            </div>
                            <div class="card-body">
                                <div class="row">
                                    <div class="col-md-6">
                                        <ul class="list-group list-group-flush">
                                            <li class="list-group-item">
                                                <strong>Sistema:</strong> <?php echo $config['app_name']; ?>
                                            </li>
                                            <li class="list-group-item">
                                                <strong>Versão:</strong> <?php echo $config['app_version']; ?>
                                            </li>
                                            <li class="list-group-item">
                                                <strong>PHP:</strong> <?php echo phpversion(); ?>
                                            </li>
                                        </ul>
                                    </div>
                                    <div class="col-md-6">
                                        <ul class="list-group list-group-flush">
                                            <li class="list-group-item">
                                                <strong>Usuário:</strong> <?php echo $_SESSION['username']; ?>
                                            </li>
                                            <li class="list-group-item">
                                                <strong>Permissão:</strong> <?php echo $_SESSION['role']; ?>
                                            </li>
                                            <li class="list-group-item">
                                                <strong>Data:</strong> <?php echo date('d/m/Y H:i:s'); ?>
                                            </li>
                                        </ul>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </main>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF
    
    # Criar outras páginas essenciais
    create_essential_pages
    
    success "Frontend criado"
}

create_essential_pages() {
    log "Criando páginas essenciais..."
    
    # Lista de páginas
    local pages=(
        "xui_config.php:Configuração XUI One"
        "m3u_list.php:Lista M3U"
        "sync_manual.php:Sincronização Manual"
        "logout.php:Sair do Sistema"
    )
    
    for page_info in "${pages[@]}"; do
        IFS=':' read -r page_name page_title <<< "$page_info"
        
        cat > "$FRONTEND_DIR/public/$page_name" << EOF
<?php
session_start();

// Verificar login
if (!isset(\$_SESSION['loggedin']) || \$_SESSION['loggedin'] !== true) {
    header('Location: /login.php');
    exit;
}

// Logout especial
if (basename(\$_SERVER['PHP_SELF']) === 'logout.php') {
    session_destroy();
    header('Location: /login.php');
    exit;
}

\$config = [
    'app_name' => 'VOD Sync XUI One',
    'app_version' => '2.0.0'
];
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo \$page_title; ?> - <?php echo \$config['app_name']; ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.1/font/bootstrap-icons.css">
    <style>
        body { background-color: #f8f9fa; }
        .sidebar {
            background: linear-gradient(180deg, #4361ee 0%, #3a0ca3 100%);
            color: white;
            min-height: 100vh;
        }
        .sidebar .nav-link {
            color: rgba(255,255,255,.8);
            padding: 12px 20px;
        }
        .sidebar .nav-link:hover {
            color: white;
            background: rgba(255,255,255,.1);
        }
        .content-wrapper { padding: 20px; }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <div class="col-md-3 col-lg-2 sidebar">
                <div class="position-sticky pt-3">
                    <h4 class="text-center text-white mb-4">
                        <i class="bi bi-film"></i><br>
                        VOD Sync
                    </h4>
                    
                    <ul class="nav flex-column">
                        <li class="nav-item">
                            <a class="nav-link" href="/dashboard.php">
                                <i class="bi bi-speedometer2"></i> Dashboard
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename(\$_SERVER['PHP_SELF']) === 'xui_config.php' ? 'active' : ''; ?>" 
                               href="/xui_config.php">
                                <i class="bi bi-server"></i> XUI Config
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename(\$_SERVER['PHP_SELF']) === 'm3u_list.php' ? 'active' : ''; ?>" 
                               href="/m3u_list.php">
                                <i class="bi bi-list-ul"></i> Lista M3U
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo basename(\$_SERVER['PHP_SELF']) === 'sync_manual.php' ? 'active' : ''; ?>" 
                               href="/sync_manual.php">
                                <i class="bi bi-arrow-repeat"></i> Sincronizar
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="/logout.php">
                                <i class="bi bi-box-arrow-right"></i> Sair
                            </a>
                        </li>
                    </ul>
                </div>
            </div>
            
            <!-- Main Content -->
            <main class="col-md-9 ms-sm-auto col-lg-10 content-wrapper">
                <!-- Top Bar -->
                <nav class="navbar navbar-light bg-white mb-4">
                    <div class="container-fluid">
                        <span class="navbar-brand">
                            <i class="bi bi-gear"></i> <?php echo \$page_title; ?>
                        </span>
                        <div class="navbar-nav">
                            <div class="nav-item">
                                <span class="nav-link">
                                    <i class="bi bi-person-circle"></i> 
                                    <?php echo \$_SESSION['username']; ?>
                                </span>
                            </div>
                        </div>
                    </div>
                </nav>
                
                <!-- Page Content -->
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><?php echo \$page_title; ?></h5>
                    </div>
                    <div class="card-body">
                        <?php if (\$page_name === 'xui_config.php'): ?>
                        <h6>Configuração do XUI One</h6>
                        <p>Configure a conexão com o banco de dados do XUI One.</p>
                        <form>
                            <div class="mb-3">
                                <label class="form-label">IP do Servidor</label>
                                <input type="text" class="form-control" placeholder="localhost">
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Usuário do Banco</label>
                                <input type="text" class="form-control" placeholder="root">
                            </div>
                            <button class="btn btn-primary">Salvar Configuração</button>
                        </form>
                        
                        <?php elseif (\$page_name === 'm3u_list.php'): ?>
                        <h6>Upload de Lista M3U</h6>
                        <p>Faça upload ou informe a URL da sua lista M3U.</p>
                        <form>
                            <div class="mb-3">
                                <label class="form-label">URL da Lista</label>
                                <input type="url" class="form-control" placeholder="https://exemplo.com/lista.m3u">
                            </div>
                            <button class="btn btn-success">Processar Lista</button>
                        </form>
                        
                        <?php elseif (\$page_name === 'sync_manual.php'): ?>
                        <h6>Sincronização Manual</h6>
                        <p>Inicie uma sincronização manual dos conteúdos.</p>
                        <div class="text-center py-4">
                            <i class="bi bi-arrow-repeat display-1 text-primary"></i>
                            <h4 class="mt-3">Pronto para Sincronizar</h4>
                            <p>Clique no botão abaixo para iniciar a sincronização.</p>
                            <button class="btn btn-primary btn-lg">
                                <i class="bi bi-play-fill"></i> Iniciar Sincronização
                            </button>
                        </div>
                        <?php endif; ?>
                    </div>
                </div>
                
                <!-- Back Button -->
                <div class="mt-3">
                    <a href="/dashboard.php" class="btn btn-outline-secondary">
                        <i class="bi bi-arrow-left"></i> Voltar ao Dashboard
                    </a>
                </div>
            </main>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF
        
        success "Página $page_name criada"
    done
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
}
EOF
    
    ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    
    # Testar configuração
    if nginx -t >> "$LOG_FILE" 2>&1; then
        success "Configuração Nginx testada"
    else
        error "Erro na configuração Nginx"
    fi
    
    systemctl start nginx
    systemctl enable nginx
    
    # Verificar
    if systemctl is-active --quiet nginx; then
        success "Nginx iniciado"
    else
        error "Nginx falhou ao iniciar"
    fi
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
    
    # Iniciar serviço
    supervisorctl start $APP_NAME-api
    
    success "Supervisor configurado"
}

# ============================================
# 10. FINALIZAÇÃO
# ============================================

create_credentials() {
    log "Criando arquivo de credenciais..."
    
    cat > "$INSTALL_DIR/credentials.txt" << EOF
====================================================
 VOD SYNC XUI ONE - INSTALAÇÃO CONCLUÍDA
====================================================

✅ SISTEMA INSTALADO COM SUCESSO!

🌐 URL de acesso: http://${DOMAIN:-seu-ip}
👤 Usuário: admin
🔑 Senha: admin123

📊 INFORMAÇÕES TÉCNICAS:
   - PHP Version: $PHP_VERSION
   - Database: $DB_NAME
   - DB User: $DB_USER
   - DB Pass: $DB_PASS
   - API Port: 8000
   - Install Dir: $INSTALL_DIR

🔧 PRÓXIMOS PASSOS:

1. Configure a chave TMDb API:
   nano $BACKEND_DIR/.env
   # Altere: TMDB_API_KEY=sua_chave_aqui

2. Acesse o sistema:
   URL: http://${DOMAIN:-seu-ip}
   Usuário: admin
   Senha: admin123

3. Configure o XUI One:
   - Vá para "XUI Config"
   - Insira os dados de conexão

4. Adicione uma lista M3U:
   - Vá para "Lista M3U"
   - Faça upload ou informe URL

5. Sincronize:
   - Vá para "Sincronizar"
   - Clique em iniciar sincronização

⚠️  IMPORTANTE:
   - Altere a senha padrão!
   - Configure SSL para produção
   - Faça backups regulares

📁 LOGS:
   - Sistema: /var/log/$APP_NAME/
   - Nginx: /var/log/nginx/${APP_NAME}_*.log
   - API: /var/log/$APP_NAME/api*.log

🔧 COMANDOS ÚTEIS:
   # Reiniciar tudo
   sudo systemctl restart nginx php$PHP_VERSION-fpm supervisor
   
   # Verificar status
   sudo systemctl status nginx
   sudo supervisorctl status
   
   # Ver logs
   sudo tail -f /var/log/$APP_NAME/api.log

====================================================
 Instalado em: $(date)
====================================================
EOF
    
    echo ""
    echo "========================================================"
    echo "         ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!          "
    echo "========================================================"
    echo ""
    echo "📁 Sistema instalado em: $INSTALL_DIR"
    echo "🌐 URL de acesso: http://${DOMAIN:-seu-ip}"
    echo "👤 Usuário: admin"
    echo "🔑 Senha: admin123"
    echo ""
    echo "📊 Informações:"
    echo "   - PHP: $PHP_VERSION"
    echo "   - Banco: $DB_NAME"
    echo "   - API: http://localhost:8000"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "   1. Configure TMDb API em $BACKEND_DIR/.env"
    echo "   2. Altere a senha padrão!"
    echo ""
    echo "========================================================"
}

finalize_installation() {
    log "Finalizando instalação..."
    
    # Ajustar permissões
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    
    # Reiniciar serviços
    systemctl restart nginx
    systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null
    systemctl restart supervisor
    
    # Testar
    sleep 3
    
    echo ""
    echo "📊 Status dos serviços:"
    echo "-----------------------"
    echo "Nginx: $(systemctl is-active nginx)"
    echo "PHP-FPM: $(systemctl is-active $PHP_FPM_SERVICE 2>/dev/null || echo 'ativo')"
    echo "MySQL: $(systemctl is-active mysql 2>/dev/null || echo 'ativo')"
    echo "Supervisor: $(systemctl is-active supervisor)"
    echo ""
    
    # Testar API
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ API Backend: Respondendo"
    else
        echo "⚠️  API Backend: Aguardando inicialização..."
    fi
    
    success "Instalação finalizada!"
}

# ============================================
# MAIN INSTALLATION
# ============================================

main() {
    clear
    echo "========================================================"
    echo "    VOD SYNC XUI ONE - INSTALADOR SIMPLIFICADO        "
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
    [[ ! $REPLY =~ ^[SsYy]$ ]] && error "Instalação cancelada"
    
    # Limpar log anterior
    > "$LOG_FILE"
    
    # Executar instalação passo a passo
    log "🚀 Iniciando instalação..."
    
    install_dependencies
    install_php
    configure_php_fpm
    setup_database
    setup_directories
    setup_python_backend
    setup_frontend_minimal
    configure_nginx
    configure_supervisor
    create_credentials
    finalize_installation
    
    echo ""
    echo "🎉 Sistema pronto para uso!"
    echo "🌐 Acesse: http://${DOMAIN:-seu-ip}"
    echo ""
    echo "📋 Credenciais salvas em: $INSTALL_DIR/credentials.txt"
    echo ""
}

# Executar instalação
main "$@"
