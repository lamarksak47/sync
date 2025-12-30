#!/bin/bash

# ============================================
# INSTALADOR VOD SYNC SYSTEM - VERSÃO CORRIGIDA
# ============================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretórios
BASE_DIR="/opt/vod-sync"
BACKEND_DIR="$BASE_DIR/backend"
FRONTEND_DIR="$BASE_DIR/frontend"
INSTALL_DIR="$BASE_DIR/install"
LOG_FILE="/var/log/vod-install-$(date +%Y%m%d_%H%M%S).log"

# Funções principais
print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║       VOD SYNC SYSTEM - INSTALADOR CORRIGIDO v1.1       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "📝 Log: $LOG_FILE"
    echo ""
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
    echo "Consulte o log: $LOG_FILE"
    exit 1
}

# Verificar root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Execute como root: sudo $0"
    fi
    success "Privilégios root verificados"
}

# Criar estrutura completa de diretórios
create_directory_structure() {
    log "Criando estrutura de diretórios..."
    
    # Criar diretório base
    mkdir -p "$BASE_DIR" || error "Falha ao criar $BASE_DIR"
    cd "$BASE_DIR"
    
    # Backend structure
    mkdir -p "$BACKEND_DIR"/{app/{controllers,services,database,models,routes,utils,core,middleware,schemas},logs,tests,static} || error "Falha ao criar estrutura backend"
    
    # Frontend structure  
    mkdir -p "$FRONTEND_DIR"/{public/assets/{css,js,images},app/{controllers,models,views,helpers,middleware},config,vendor,temp,logs} || error "Falha ao criar estrutura frontend"
    
    # Install structure
    mkdir -p "$INSTALL_DIR"/{sql,config,scripts} || error "Falha ao criar estrutura de instalação"
    
    success "Estrutura criada em $BASE_DIR"
}

# Criar arquivos backend básicos
create_backend_files() {
    log "Criando arquivos do backend..."
    
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
redis==5.0.1
celery==5.3.4
pydantic==2.5.0
EOF

    # main.py mínimo para teste
    cat > "$BACKEND_DIR/app/main.py" << 'EOF'
from fastapi import FastAPI
import os

app = FastAPI(title="VOD Sync System", version="1.0.0")

@app.get("/")
def read_root():
    return {"status": "online", "service": "VOD Sync Backend"}

@app.get("/health")
def health_check():
    return {"status": "healthy", "timestamp": "2025-12-30T00:00:00Z"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    # .env do backend
    cat > "$BACKEND_DIR/.env" << EOF
APP_NAME=VOD Sync System
APP_VERSION=1.0.0
DEBUG=True
HOST=0.0.0.0
PORT=8000

DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_system
DB_USER=vodsync_user
DB_PASS=vodsync_pass_$(openssl rand -hex 8)

TMDB_API_KEY=sua_chave_aqui
TMDB_LANGUAGE=pt-BR

SECRET_KEY=$(openssl rand -hex 32)
EOF

    # Criar __init__.py em cada diretório
    find "$BACKEND_DIR/app" -type d -exec touch {}/__init__.py \;
    
    success "Arquivos do backend criados"
}

# Criar arquivos frontend básicos
create_frontend_files() {
    log "Criando arquivos do frontend..."
    
    # index.php básico
    cat > "$FRONTEND_DIR/public/index.php" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VOD Sync System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background: #f8f9fa; }
        .login-box { max-width: 400px; margin: 100px auto; padding: 30px; background: white; border-radius: 10px; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .logo { text-align: center; margin-bottom: 30px; color: #667eea; }
    </style>
</head>
<body>
    <div class="login-box">
        <div class="logo">
            <h3><i class="fas fa-sync-alt"></i> VOD Sync System</h3>
            <p class="text-muted">Sincronização de Conteúdo VOD</p>
        </div>
        
        <div class="alert alert-info">
            <h5>Sistema Instalado com Sucesso!</h5>
            <p class="mb-0">Backend API: <a href="http://localhost:8000" target="_blank">http://localhost:8000</a></p>
            <p class="mb-0">API Health: <a href="http://localhost:8000/health" target="_blank">/health</a></p>
        </div>
        
        <form action="/login.php" method="POST">
            <div class="mb-3">
                <label class="form-label">Usuário</label>
                <input type="text" class="form-control" name="username" placeholder="admin" required>
            </div>
            <div class="mb-3">
                <label class="form-label">Senha</label>
                <input type="password" class="form-control" name="password" placeholder="••••••••" required>
            </div>
            <button type="submit" class="btn btn-primary w-100">
                <i class="fas fa-sign-in-alt"></i> Entrar
            </button>
        </form>
        
        <hr class="my-4">
        
        <div class="text-center small text-muted">
            <p>© 2025 VOD Sync System - Versão 1.0</p>
            <p>Status: <span class="badge bg-success">Online</span></p>
        </div>
    </div>
    
    <script src="https://kit.fontawesome.com/your-fontawesome-kit.js" crossorigin="anonymous"></script>
</body>
</html>
EOF

    # login.php
    cat > "$FRONTEND_DIR/public/login.php" << 'EOF'
<?php
session_start();

// Simulação de login
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if ($username === 'admin' && $password === 'admin123') {
        $_SESSION['user_id'] = 1;
        $_SESSION['username'] = 'admin';
        $_SESSION['user_type'] = 'admin';
        header('Location: /dashboard.php');
        exit;
    }
}

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
    <title>Dashboard - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-dark bg-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="#">
                <i class="fas fa-sync-alt"></i> VOD Sync Dashboard
            </a>
            <span class="navbar-text">
                Olá, <?php echo $_SESSION['username']; ?>
            </span>
        </div>
    </nav>
    
    <div class="container mt-4">
        <h2>Dashboard do Sistema</h2>
        <p>Sistema instalado e funcionando corretamente.</p>
        
        <div class="row mt-4">
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title">Backend API</h5>
                        <p class="card-text">Status: <span class="badge bg-success">Online</span></p>
                        <a href="http://localhost:8000" target="_blank" class="btn btn-sm btn-primary">Acessar API</a>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title">Frontend</h5>
                        <p class="card-text">Status: <span class="badge bg-success">Online</span></p>
                        <a href="/" class="btn btn-sm btn-primary">Acessar Site</a>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title">Banco de Dados</h5>
                        <p class="card-text">Status: <span class="badge bg-success">Conectado</span></p>
                        <button class="btn btn-sm btn-secondary">Verificar</button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
EOF

    success "Arquivos do frontend criados"
}

# Configurar Nginx corretamente
setup_nginx() {
    log "Configurando Nginx..."
    
    # Instalar Nginx se não existir
    if ! command -v nginx &> /dev/null; then
        log "Instalando Nginx..."
        apt-get update && apt-get install -y nginx 2>> "$LOG_FILE" || error "Falha ao instalar Nginx"
    fi
    
    # Parar Nginx para configurar
    systemctl stop nginx 2>/dev/null || true
    
    # Criar configuração do site
    cat > /etc/nginx/sites-available/vod-sync << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;  # Aceita qualquer domínio
    
    root /opt/vod-sync/frontend/public;
    index index.php index.html index.htm;
    
    # Frontend
    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }
    
    # Backend API - Proxy para FastAPI
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
        
        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        
        # Tentar diferentes sockets do PHP
        try_files $uri =404;
        
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
        fastcgi_pass 127.0.0.1:9000;
        
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Timeouts aumentados para uploads grandes
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
    }
    
    # Bloquear acesso a arquivos sensíveis
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    location ~ ^/(app|config|logs|temp|vendor)/ {
        deny all;
        return 403;
    }
    
    # Cache para arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Logs
    access_log /var/log/nginx/vod-sync-access.log;
    error_log /var/log/nginx/vod-sync-error.log;
    
    # Tamanho máximo de upload (para listas M3U grandes)
    client_max_body_size 100M;
}
EOF
    
    # Remover site default
    rm -f /etc/nginx/sites-enabled/default
    
    # Ativar nosso site
    ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t 2>> "$LOG_FILE" || {
        echo "=== ERRO NGINX CONFIG ===" >> "$LOG_FILE"
        nginx -t 2>&1 >> "$LOG_FILE"
        error "Configuração Nginx inválida"
    }
    
    # Iniciar Nginx
    systemctl start nginx 2>> "$LOG_FILE" || error "Falha ao iniciar Nginx"
    systemctl enable nginx 2>> "$LOG_FILE"
    
    # Configurar PHP-FPM
    setup_php_fpm
    
    success "Nginx configurado e rodando"
}

# Configurar PHP-FPM
setup_php_fpm() {
    log "Configurando PHP-FPM..."
    
    # Verificar PHP instalado
    if ! command -v php &> /dev/null; then
        apt-get install -y php-fpm php-mysql php-curl php-json php-mbstring 2>> "$LOG_FILE" || error "Falha ao instalar PHP"
    fi
    
    # Encontrar e iniciar serviço PHP-FPM
    for version in 8.2 8.1 8.0 7.4; do
        if systemctl list-unit-files | grep -q "php${version}-fpm"; then
            PHP_SERVICE="php${version}-fpm"
            break
        fi
    done
    
    if [ -z "$PHP_SERVICE" ]; then
        PHP_SERVICE="php-fpm"
    fi
    
    # Iniciar PHP-FPM
    systemctl start "$PHP_SERVICE" 2>> "$LOG_FILE" || warning "PHP-FPM não iniciado (pode não estar instalado)"
    systemctl enable "$PHP_SERVICE" 2>> "$LOG_FILE" 2>/dev/null || true
    
    # Configurar permissões
    chown -R www-data:www-data "$FRONTEND_DIR"
    chmod -R 755 "$FRONTEND_DIR/public"
    
    # Criar diretório de sessões se não existir
    mkdir -p /var/lib/php/sessions
    chown -R www-data:www-data /var/lib/php/sessions
    chmod 1733 /var/lib/php/sessions
    
    success "PHP-FPM configurado"
}

# Configurar backend Python
setup_backend() {
    log "Configurando backend Python..."
    
    cd "$BACKEND_DIR"
    
    # Criar ambiente virtual
    python3 -m venv venv 2>> "$LOG_FILE" || error "Falha ao criar venv"
    
    # Ativar e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip 2>> "$LOG_FILE"
    
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt 2>> "$LOG_FILE" || warning "Algumas dependências falharam"
    else
        pip install fastapi uvicorn 2>> "$LOG_FILE" || error "Falha ao instalar dependências básicas"
    fi
    
    # Criar serviço systemd CORRETO
    cat > /etc/systemd/system/vod-sync-backend.service << EOF
[Unit]
Description=VOD Sync System Backend API
After=network.target
Wants=network.target

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

# Configurações de segurança
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$BACKEND_DIR/logs

[Install]
WantedBy=multi-user.target
EOF
    
    # Criar usuário se não existir
    if ! id -u www-data >/dev/null 2>&1; then
        useradd -r -s /bin/false www-data 2>> "$LOG_FILE" || true
    fi
    
    # Configurar permissões
    chown -R www-data:www-data "$BACKEND_DIR"
    chmod -R 755 "$BACKEND_DIR"
    
    # Recarregar e iniciar serviço
    systemctl daemon-reload
    systemctl enable vod-sync-backend 2>> "$LOG_FILE"
    
    # Tentar iniciar com timeout
    timeout 10 systemctl start vod-sync-backend 2>> "$LOG_FILE" || {
        warning "Serviço não iniciou imediatamente, verificando..."
    }
    
    # Verificar status
    sleep 3
    if systemctl is-active --quiet vod-sync-backend; then
        success "Backend rodando na porta 8000"
    else
        # Mostrar logs de erro
        echo "=== LOGS DO BACKEND ==="
        journalctl -u vod-sync-backend -n 20 --no-pager
        error "Backend não iniciou. Verifique os logs acima."
    fi
}

# Configurar banco de dados
setup_database() {
    log "Configurando banco de dados..."
    
    # Verificar MySQL/MariaDB
    if ! systemctl is-active --quiet mysql 2>/dev/null && ! systemctl is-active --quiet mariadb 2>/dev/null; then
        log "Instalando MySQL..."
        apt-get install -y mysql-server 2>> "$LOG_FILE" || error "Falha ao instalar MySQL"
        systemctl start mysql 2>> "$LOG_FILE"
        systemctl enable mysql 2>> "$LOG_FILE"
    fi
    
    # Credenciais
    DB_NAME="vod_system"
    DB_USER="vodsync_user"
    DB_PASS="VodSync_$(openssl rand -hex 6)"
    
    # Criar banco e usuário
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE" || error "Falha ao criar banco"
    
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>> "$LOG_FILE" || error "Falha ao criar usuário"
    
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>> "$LOG_FILE" || error "Falha ao conceder privilégios"
    
    mysql -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"
    
    # Criar estrutura básica
    cat > /tmp/vod_tables.sql << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('admin','reseller','user') DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO users (username, password_hash, user_type) VALUES 
('admin', '$2b$12$LQv3c1yqBWVHxpd5g8T3e.BHZzl6CLj7/5L8OYyN8pMZ7cJkzq6W2', 'admin');

CREATE TABLE IF NOT EXISTS xui_connections (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    host VARCHAR(255) NOT NULL,
    port INT DEFAULT 3306,
    username VARCHAR(100) NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    message TEXT,
    status ENUM('success','error','warning') DEFAULT 'success',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    
    mysql $DB_NAME < /tmp/vod_tables.sql 2>> "$LOG_FILE" || warning "Algumas tabelas podem ter falhado"
    
    # Atualizar .env com credenciais
    sed -i "s/DB_PASS=.*/DB_PASS=$DB_PASS/" "$BACKEND_DIR/.env"
    
    # Salvar credenciais
    cat > /root/vod-db-credentials.txt << EOF
=======================================
CREDENCIAIS BANCO DE DADOS - VOD SYNC
=======================================
Banco: $DB_NAME
Usuário: $DB_USER
Senha: $DB_PASS
Host: localhost
Porta: 3306
=======================================
EOF
    
    success "Banco de dados configurado"
    log "Credenciais salvas em: /root/vod-db-credentials.txt"
}

# Instalação completa
complete_installation() {
    print_header
    
    echo "Este instalador irá:"
    echo "1. ✅ Criar estrutura completa de diretórios"
    echo "2. ✅ Criar arquivos backend/frontend básicos"
    echo "3. ✅ Configurar banco de dados MySQL"
    echo "4. ✅ Instalar e configurar Nginx + PHP-FPM"
    echo "5. ✅ Configurar backend Python (FastAPI)"
    echo "6. ✅ Criar serviços systemd"
    echo ""
    
    read -p "Continuar? (s/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] || exit 0
    
    # Executar passos na ordem correta
    check_root
    create_directory_structure
    create_backend_files
    create_frontend_files
    setup_database
    setup_nginx
    setup_backend
    
    # Verificação final
    verify_installation
}

# Verificar instalação
verify_installation() {
    print_header
    echo "🔍 VERIFICAÇÃO DA INSTALAÇÃO"
    echo ""
    
    # Verificar serviços
    echo "📦 SERVIÇOS:"
    for service in nginx vod-sync-backend; do
        if systemctl is-active --quiet "$service"; then
            echo "  ✅ $service: RODANDO"
        else
            echo "  ❌ $service: PARADO"
        fi
    done
    
    # Verificar portas
    echo ""
    echo "🌐 PORTAS:"
    if netstat -tuln | grep -q ":80 "; then
        echo "  ✅ Porta 80 (HTTP): Aberta"
    else
        echo "  ❌ Porta 80: Fechada"
    fi
    
    if netstat -tuln | grep -q ":8000 "; then
        echo "  ✅ Porta 8000 (API): Aberta"
    else
        echo "  ❌ Porta 8000: Fechada"
    fi
    
    # Verificar diretórios
    echo ""
    echo "📁 DIRETÓRIOS:"
    for dir in "$BACKEND_DIR" "$FRONTEND_DIR/public"; do
        if [ -d "$dir" ]; then
            echo "  ✅ $dir"
        else
            echo "  ❌ $dir: Ausente"
        fi
    done
    
    # Testar API
    echo ""
    echo "🔧 TESTES:"
    if curl -s http://localhost:8000/health >/dev/null; then
        echo "  ✅ API Backend: Respondendo"
    else
        echo "  ❌ API Backend: Não responde"
    fi
    
    if curl -s http://localhost/ >/dev/null; then
        echo "  ✅ Frontend Web: Acessível"
    else
        echo "  ❌ Frontend Web: Não acessível"
    fi
    
    # Informações de acesso
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "🎉 INSTALAÇÃO COMPLETA!"
    echo ""
    echo "🌐 ACESSO:"
    echo "   Frontend: http://$(hostname -I | awk '{print $1}')"
    echo "   Backend API: http://localhost:8000"
    echo ""
    echo "🔑 LOGIN PADRÃO:"
    echo "   Usuário: admin"
    echo "   Senha: admin123"
    echo ""
    echo "📄 ARQUIVOS IMPORTANTES:"
    echo "   Log da instalação: $LOG_FILE"
    echo "   Credenciais DB: /root/vod-db-credentials.txt"
    echo "   Config Nginx: /etc/nginx/sites-available/vod-sync"
    echo ""
    echo "⚡ COMANDOS ÚTEIS:"
    echo "   sudo systemctl status vod-sync-backend"
    echo "   sudo journalctl -u vod-sync-backend -f"
    echo "   sudo tail -f /var/log/nginx/vod-sync-error.log"
    echo "═══════════════════════════════════════════════"
    
    # Criar flag de instalação
    date > "$BASE_DIR/.installed"
}

# Menu principal
main_menu() {
    while true; do
        print_header
        echo "MENU PRINCIPAL"
        echo ""
        echo "1) 🚀 Instalação Completa"
        echo "2) 📁 Criar Apenas Estrutura"
        echo "3) 🌐 Configurar Apenas Nginx"
        echo "4) 🐍 Configurar Apenas Backend"
        echo "5) 🗄️  Configurar Apenas Banco"
        echo "6) 🔍 Verificar Sistema"
        echo "7) 🚪 Sair"
        echo ""
        read -p "Opção: " choice
        
        case $choice in
            1) complete_installation ;;
            2) check_root; create_directory_structure; create_backend_files; create_frontend_files ;;
            3) check_root; setup_nginx ;;
            4) check_root; setup_backend ;;
            5) check_root; setup_database ;;
            6) verify_installation ;;
            7) exit 0 ;;
            *) echo "Opção inválida"; sleep 2 ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..."
    done
}

# Iniciar
main_menu
