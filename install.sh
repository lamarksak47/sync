#!/bin/bash

# ============================================
# INSTALADOR XUI ONE VODs SYNC - CONEXÃO REMOTA
# ============================================
# Sistema completo com conexão a banco XUI ONE remoto
# Autor: XUI ONE VODs Sync Team
# Versão: 3.0.0
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Constantes
SCRIPT_VERSION="3.0.0"
INSTALL_DIR="/opt/xui-one-vods-sync"
CONFIG_DIR="/etc/xui-one-vods-sync"
LOG_DIR="/var/log/xui-one-vods-sync"
WEB_DIR="/var/www/xui-vods-sync"
SERVICE_USER="xui-sync"
API_PORT="8001"
WEB_PORT="8080"
ADMIN_USER="admin"
ADMIN_PASS="admin123"

# Variáveis
IS_ROOT=false
IS_UBUNTU=false
MYSQL_LOCAL_PASS=""
ENABLE_SSL=false
DOMAIN_NAME=""
EMAIL=""

print_header() {
    clear
    echo -e "${PURPLE}"
    echo "============================================="
    echo "   XUI ONE VODs Sync - Instalador v$SCRIPT_VERSION"
    echo "       COM CONEXÃO REMOTA XUI ONE"
    echo "============================================="
    echo -e "${NC}"
}

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

generate_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        IS_ROOT=true
    else
        print_error "Execute como root: sudo $0"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            IS_UBUNTU=true
            print_success "Ubuntu detectado"
        else
            print_error "Só Ubuntu é suportado"
            exit 1
        fi
    fi
}

update_system() {
    print_status "Atualizando sistema..."
    apt-get update
    apt-get upgrade -y
    print_success "Sistema atualizado"
}

install_mysql_local() {
    print_status "Instalando MySQL local..."
    apt-get install -y mysql-server
    
    # Configura MySQL
    systemctl start mysql
    systemctl enable mysql
    
    # Gera senha para MySQL local
    MYSQL_LOCAL_PASS=$(generate_password)
    
    # Configura segurança
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_LOCAL_PASS';"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Cria banco para o sincronizador
    mysql -e "CREATE DATABASE IF NOT EXISTS xui_sync_manager CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS 'xui_sync_user'@'localhost' IDENTIFIED BY '$MYSQL_LOCAL_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON xui_sync_manager.* TO 'xui_sync_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    print_success "MySQL local instalado"
    print_info "Senha MySQL local: $MYSQL_LOCAL_PASS"
}

install_python() {
    print_status "Instalando Python e dependências..."
    apt-get install -y python3.8 python3.8-dev python3-pip python3.8-venv \
        python3-setuptools python3-wheel build-essential \
        libmysqlclient-dev libssl-dev libffi-dev
    
    # Cria ambiente virtual
    python3.8 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    
    # Instala dependências Python
    cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
mysql-connector-python==8.2.0
pydantic==2.5.0
python-multipart==0.0.6
aiohttp==3.9.1
requests==2.31.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
cryptography==41.0.7
jinja2==3.1.2
python-dateutil==2.8.2
pyyaml==6.0.1
celery==5.3.4
redis==5.0.1
flower==2.0.1
EOF
    
    pip install -r "$INSTALL_DIR/requirements.txt"
    deactivate
    print_success "Python instalado"
}

install_nginx() {
    print_status "Instalando Nginx..."
    apt-get install -y nginx
    print_success "Nginx instalado"
}

create_user() {
    print_status "Criando usuário do sistema..."
    if id "$SERVICE_USER" &>/dev/null; then
        userdel -r "$SERVICE_USER"
    fi
    useradd -r -s /bin/false -d "$INSTALL_DIR" -m "$SERVICE_USER"
    print_success "Usuário criado"
}

setup_directories() {
    print_status "Criando diretórios..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$WEB_DIR"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/api"
    mkdir -p "$INSTALL_DIR/web"
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    print_success "Diretórios criados"
}

create_config_files() {
    print_status "Criando arquivos de configuração..."
    
    # Configuração da API
    cat > "$CONFIG_DIR/api.env" << EOF
# Configurações da API
API_ENV=production
API_HOST=0.0.0.0
API_PORT=$API_PORT
API_KEY=xui_sync_$(generate_password)_key

# Banco local do sincronizador
DB_HOST=localhost
DB_PORT=3306
DB_NAME=xui_sync_manager
DB_USER=xui_sync_user
DB_PASSWORD=$MYSQL_LOCAL_PASS

# Segurança
JWT_SECRET=$(generate_password)
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# Admin padrão
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS

# Logs
LOG_DIR=$LOG_DIR
LOG_LEVEL=info
EOF

    # Configuração do Web
    cat > "$CONFIG_DIR/web.env" << EOF
WEB_PORT=$WEB_PORT
API_URL=http://localhost:$API_PORT
SESSION_SECRET=$(generate_password)
SITE_NAME=XUI ONE VODs Sync
EOF

    print_success "Configurações criadas"
}

create_api_structure() {
    print_status "Criando estrutura da API..."
    
    # Estrutura principal
    mkdir -p "$INSTALL_DIR/api/app"
    mkdir -p "$INSTALL_DIR/api/app/core"
    mkdir -p "$INSTALL_DIR/api/app/api"
    mkdir -p "$INSTALL_DIR/api/app/models"
    mkdir -p "$INSTALL_DIR/api/app/schemas"
    mkdir -p "$INSTALL_DIR/api/app/services"
    mkdir -p "$INSTALL_DIR/api/app/utils"
    mkdir -p "$INSTALL_DIR/api/app/db"
    mkdir -p "$INSTALL_DIR/api/static"
    mkdir -p "$INSTALL_DIR/api/templates"
    
    # Arquivo principal da API
    cat > "$INSTALL_DIR/api/main.py" << 'EOF'
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import mysql.connector
from mysql.connector import Error
import logging
import json
import hashlib
import secrets
from datetime import datetime
from typing import Dict, List, Optional
from pydantic import BaseModel
import os
from pathlib import Path

# Configuração
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="XUI ONE VODs Sync API", version="3.0.0")

# Templates
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")

# Banco de dados local do sincronizador
def get_local_db():
    conn = mysql.connector.connect(
        host="localhost",
        user="xui_sync_user",
        password=os.getenv("DB_PASSWORD", ""),
        database="xui_sync_manager"
    )
    return conn

# Models
class XUIConnection(BaseModel):
    id: str
    name: str
    host: str
    port: int = 3306
    username: str
    password: str
    database: str = "xui"
    is_active: bool = True
    created_at: str

class User(BaseModel):
    id: int
    username: str
    password_hash: str
    is_admin: bool = False

# Banco de dados inicial
def init_database():
    conn = get_local_db()
    cursor = conn.cursor()
    
    # Tabela de conexões XUI ONE
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS xui_connections (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            host VARCHAR(100) NOT NULL,
            port INT DEFAULT 3306,
            username VARCHAR(100) NOT NULL,
            password VARCHAR(255) NOT NULL,
            database VARCHAR(100) DEFAULT 'xui',
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Tabela de usuários
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(50) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            is_admin BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Tabela de logs de sincronização
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sync_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            connection_id VARCHAR(50),
            action VARCHAR(50),
            items_processed INT,
            items_added INT,
            items_updated INT,
            status VARCHAR(20),
            error_message TEXT,
            started_at TIMESTAMP,
            completed_at TIMESTAMP
        )
    """)
    
    # Insere admin padrão se não existir
    cursor.execute("SELECT COUNT(*) FROM users WHERE username = 'admin'")
    if cursor.fetchone()[0] == 0:
        import hashlib
        password_hash = hashlib.sha256('admin123'.encode()).hexdigest()
        cursor.execute(
            "INSERT INTO users (username, password_hash, is_admin) VALUES (%s, %s, %s)",
            ('admin', password_hash, True)
        )
    
    conn.commit()
    cursor.close()
    conn.close()

# Inicializa banco
init_database()

# Funções de autenticação
def verify_password(plain_password, hashed_password):
    return hashlib.sha256(plain_password.encode()).hexdigest() == hashed_password

def get_user(username: str):
    conn = get_local_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
    user = cursor.fetchone()
    cursor.close()
    conn.close()
    return user

# Rotas
@app.get("/", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/login")
async def login(request: Request):
    form = await request.form()
    username = form.get("username")
    password = form.get("password")
    
    user = get_user(username)
    if not user or not verify_password(password, user['password_hash']):
        return RedirectResponse("/?error=1", status_code=302)
    
    # Cria token de sessão
    token = secrets.token_hex(32)
    response = RedirectResponse("/dashboard", status_code=302)
    response.set_cookie(key="session_token", value=token, httponly=True)
    
    # Salva sessão (em produção, use Redis)
    conn = get_local_db()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO user_sessions (user_id, token) VALUES (%s, %s)",
        (user['id'], token)
    )
    conn.commit()
    cursor.close()
    conn.close()
    
    return response

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    token = request.cookies.get("session_token")
    if not token:
        return RedirectResponse("/", status_code=302)
    
    return templates.TemplateResponse("dashboard.html", {"request": request})

# API para gerenciar conexões XUI ONE
@app.get("/api/connections")
async def get_connections():
    conn = get_local_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, name, host, port, database, is_active FROM xui_connections")
    connections = cursor.fetchall()
    cursor.close()
    conn.close()
    return {"connections": connections}

@app.post("/api/connections")
async def create_connection(connection: dict):
    conn = get_local_db()
    cursor = conn.cursor()
    
    connection_id = secrets.token_hex(8)
    cursor.execute(
        """INSERT INTO xui_connections 
           (id, name, host, port, username, password, database, is_active) 
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
        (connection_id, connection['name'], connection['host'], connection['port'],
         connection['username'], connection['password'], connection['database'], True)
    )
    
    conn.commit()
    cursor.close()
    conn.close()
    
    return {"id": connection_id, "message": "Conexão criada"}

@app.post("/api/connections/{connection_id}/test")
async def test_connection(connection_id: str):
    conn = get_local_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM xui_connections WHERE id = %s", (connection_id,))
    connection = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not connection:
        raise HTTPException(status_code=404, detail="Conexão não encontrada")
    
    try:
        # Tenta conectar ao banco remoto do XUI ONE
        remote_conn = mysql.connector.connect(
            host=connection['host'],
            port=connection['port'],
            user=connection['username'],
            password=connection['password'],
            database=connection['database']
        )
        
        cursor = remote_conn.cursor()
        
        # Verifica se é banco do XUI ONE
        cursor.execute("SHOW TABLES LIKE 'streams'")
        has_streams = cursor.fetchone() is not None
        
        cursor.execute("SHOW TABLES LIKE 'categories'")
        has_categories = cursor.fetchone() is not None
        
        cursor.close()
        remote_conn.close()
        
        return {
            "success": True,
            "is_xui_database": has_streams or has_categories,
            "has_streams": has_streams,
            "has_categories": has_categories
        }
        
    except Error as e:
        return {
            "success": False,
            "error": str(e)
        }

@app.post("/api/connections/{connection_id}/sync")
async def sync_connection(connection_id: str):
    conn = get_local_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM xui_connections WHERE id = %s", (connection_id,))
    connection = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not connection:
        raise HTTPException(status_code=404, detail="Conexão não encontrada")
    
    try:
        # Conecta ao banco remoto do XUI ONE
        remote_conn = mysql.connector.connect(
            host=connection['host'],
            port=connection['port'],
            user=connection['username'],
            password=connection['password'],
            database=connection['database']
        )
        
        cursor = remote_conn.cursor(dictionary=True)
        
        # Sincroniza categorias
        cursor.execute("SELECT * FROM categories")
        categories = cursor.fetchall()
        
        # Sincroniza streams (VODs)
        cursor.execute("""
            SELECT * FROM streams 
            WHERE stream_type = 'movie' OR stream_type = 'series'
        """)
        vods = cursor.fetchall()
        
        cursor.close()
        remote_conn.close()
        
        # Aqui você processaria os dados e salvaria localmente
        # Por enquanto, só retorna as contagens
        
        return {
            "success": True,
            "categories_count": len(categories),
            "vods_count": len(vods),
            "message": f"Encontrados {len(categories)} categorias e {len(vods)} VODs"
        }
        
    except Error as e:
        return {
            "success": False,
            "error": str(e)
        }

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "xui-vods-sync"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF

    # Templates HTML
    mkdir -p "$INSTALL_DIR/api/templates"
    
    # Template de login
    cat > "$INSTALL_DIR/api/templates/login.html" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XUI ONE VODs Sync - Login</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
        }
        .login-container {
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            max-width: 400px;
            width: 100%;
            padding: 40px;
        }
        .brand {
            text-align: center;
            margin-bottom: 30px;
        }
        .brand h2 {
            color: #333;
            font-weight: bold;
        }
        .brand p {
            color: #666;
            font-size: 14px;
        }
        .form-control {
            padding: 12px;
            border-radius: 5px;
        }
        .btn-login {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
            color: white;
            padding: 12px;
            border-radius: 5px;
            font-weight: bold;
            width: 100%;
        }
        .alert {
            margin-top: 15px;
        }
        .features {
            margin-top: 30px;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-md-4">
                <div class="login-container">
                    <div class="brand">
                        <h2>🎬 XUI ONE VODs Sync</h2>
                        <p>Sincronizador de Catálogo Remoto</p>
                    </div>
                    
                    {% if error %}
                    <div class="alert alert-danger">
                        Usuário ou senha incorretos
                    </div>
                    {% endif %}
                    
                    <form method="post" action="/login">
                        <div class="mb-3">
                            <label class="form-label">Usuário</label>
                            <input type="text" name="username" class="form-control" required 
                                   placeholder="Digite seu usuário">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Senha</label>
                            <input type="password" name="password" class="form-control" required 
                                   placeholder="Digite sua senha">
                        </div>
                        
                        <button type="submit" class="btn btn-login">
                            🔐 Entrar no Sistema
                        </button>
                    </form>
                    
                    <div class="features mt-4">
                        <p><strong>Credenciais padrão:</strong></p>
                        <p>Usuário: <code>admin</code></p>
                        <p>Senha: <code>admin123</code></p>
                        <p class="mt-3"><small>Após login, configure a conexão com o banco do XUI ONE</small></p>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
EOF

    # Template do dashboard
    cat > "$INSTALL_DIR/api/templates/dashboard.html" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - XUI ONE VODs Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary-color: #667eea;
            --secondary-color: #764ba2;
        }
        body {
            background-color: #f8f9fa;
        }
        .sidebar {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            color: white;
            min-height: 100vh;
            position: fixed;
            width: 250px;
        }
        .sidebar-header {
            padding: 20px;
            text-align: center;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .nav-link {
            color: rgba(255,255,255,0.8);
            padding: 12px 20px;
            border-left: 4px solid transparent;
            transition: all 0.3s;
        }
        .nav-link:hover, .nav-link.active {
            color: white;
            background: rgba(255,255,255,0.1);
            border-left-color: white;
        }
        .nav-link i {
            width: 25px;
        }
        .main-content {
            margin-left: 250px;
            padding: 20px;
        }
        .card-dashboard {
            border: none;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.05);
            transition: transform 0.3s;
        }
        .card-dashboard:hover {
            transform: translateY(-5px);
        }
        .btn-primary {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            border: none;
        }
        .connection-status {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 5px;
        }
        .status-connected { background-color: #28a745; }
        .status-disconnected { background-color: #dc3545; }
        .status-testing { background-color: #ffc107; }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="sidebar-header">
            <h4><i class="fas fa-film"></i> XUI ONE Sync</h4>
            <p class="small mb-0">v3.0.0</p>
        </div>
        
        <nav class="nav flex-column mt-4">
            <a class="nav-link active" href="#">
                <i class="fas fa-tachometer-alt"></i> Dashboard
            </a>
            <a class="nav-link" href="#" data-bs-toggle="modal" data-bs-target="#addConnectionModal">
                <i class="fas fa-database"></i> Nova Conexão XUI
            </a>
            <a class="nav-link" href="#" id="connectionsTab">
                <i class="fas fa-server"></i> Conexões XUI ONE
            </a>
            <a class="nav-link" href="#">
                <i class="fas fa-sync-alt"></i> Sincronizar
            </a>
            <a class="nav-link" href="#">
                <i class="fas fa-history"></i> Logs
            </a>
            <a class="nav-link" href="#">
                <i class="fas fa-cog"></i> Configurações
            </a>
            <a class="nav-link" href="/logout" style="margin-top: 50px;">
                <i class="fas fa-sign-out-alt"></i> Sair
            </a>
        </nav>
    </div>
    
    <!-- Main Content -->
    <div class="main-content">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h3>Dashboard</h3>
            <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addConnectionModal">
                <i class="fas fa-plus me-2"></i> Nova Conexão XUI ONE
            </button>
        </div>
        
        <!-- Stats -->
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card card-dashboard">
                    <div class="card-body">
                        <h6 class="text-muted">Conexões XUI</h6>
                        <h2 id="connectionsCount">0</h2>
                        <small class="text-muted">Servidores configurados</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card card-dashboard">
                    <div class="card-body">
                        <h6 class="text-muted">VODs Sincronizados</h6>
                        <h2 id="vodsCount">0</h2>
                        <small class="text-muted">Total de itens</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card card-dashboard">
                    <div class="card-body">
                        <h6 class="text-muted">Última Sinc.</h6>
                        <h2 id="lastSync">-</h2>
                        <small class="text-muted">há --</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card card-dashboard">
                    <div class="card-body">
                        <h6 class="text-muted">Status</h6>
                        <h2 id="systemStatus">🟢</h2>
                        <small class="text-muted">Sistema operacional</small>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Conexões XUI ONE -->
        <div class="card card-dashboard">
            <div class="card-header">
                <h5 class="mb-0">Conexões com XUI ONE</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-hover" id="connectionsTable">
                        <thead>
                            <tr>
                                <th>Nome</th>
                                <th>Host/IP</th>
                                <th>Banco</th>
                                <th>Status</th>
                                <th>Última Sinc.</th>
                                <th>Ações</th>
                            </tr>
                        </thead>
                        <tbody id="connectionsList">
                            <!-- Lista será preenchida por JavaScript -->
                        </tbody>
                    </table>
                </div>
                
                <div class="text-center py-5" id="noConnections">
                    <i class="fas fa-database fa-3x text-muted mb-3"></i>
                    <h5 class="text-muted">Nenhuma conexão configurada</h5>
                    <p class="text-muted">Clique em "Nova Conexão XUI ONE" para começar</p>
                </div>
            </div>
        </div>
        
        <!-- Instruções -->
        <div class="card card-dashboard mt-4">
            <div class="card-header">
                <h5 class="mb-0">Como configurar conexão com XUI ONE</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-6">
                        <h6><i class="fas fa-info-circle text-primary me-2"></i>Informações necessárias:</h6>
                        <ul>
                            <li><strong>IP/Host:</strong> Endereço da máquina onde o XUI ONE está instalado</li>
                            <li><strong>Porta MySQL:</strong> Normalmente 3306</li>
                            <li><strong>Usuário MySQL:</strong> Usuário do banco do XUI ONE</li>
                            <li><strong>Senha MySQL:</strong> Senha do banco do XUI ONE</li>
                            <li><strong>Nome do banco:</strong> Normalmente "xui"</li>
                        </ul>
                    </div>
                    <div class="col-md-6">
                        <h6><i class="fas fa-shield-alt text-success me-2"></i>Requisitos:</h6>
                        <ul>
                            <li>O MySQL do XUI ONE deve permitir conexões remotas</li>
                            <li>Firewall deve permitir acesso à porta 3306</li>
                            <li>Usuário MySQL deve ter permissões de leitura</li>
                            <li>Conexão de rede entre as máquinas</li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Modal: Adicionar Conexão -->
    <div class="modal fade" id="addConnectionModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Nova Conexão XUI ONE</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <form id="connectionForm">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Nome da Conexão *</label>
                                <input type="text" class="form-control" name="name" 
                                       placeholder="Ex: Servidor Principal XUI" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Host/IP *</label>
                                <input type="text" class="form-control" name="host" 
                                       placeholder="Ex: 192.168.1.100 ou xui.meuserver.com" required>
                            </div>
                        </div>
                        
                        <div class="row">
                            <div class="col-md-3 mb-3">
                                <label class="form-label">Porta MySQL</label>
                                <input type="number" class="form-control" name="port" value="3306">
                            </div>
                            <div class="col-md-5 mb-3">
                                <label class="form-label">Usuário MySQL *</label>
                                <input type="text" class="form-control" name="username" 
                                       placeholder="Usuário do banco XUI" required>
                            </div>
                            <div class="col-md-4 mb-3">
                                <label class="form-label">Senha *</label>
                                <input type="password" class="form-control" name="password" required>
                            </div>
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Nome do Banco</label>
                            <input type="text" class="form-control" name="database" value="xui">
                            <small class="text-muted">Normalmente "xui" para XUI ONE</small>
                        </div>
                        
                        <div class="alert alert-info">
                            <i class="fas fa-info-circle me-2"></i>
                            <strong>Importante:</strong> Certifique-se que o MySQL do XUI ONE permite conexões remotas
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                    <button type="button" class="btn btn-success" id="testConnectionBtn">
                        <i class="fas fa-vial me-1"></i> Testar Conexão
                    </button>
                    <button type="button" class="btn btn-primary" id="saveConnectionBtn">
                        <i class="fas fa-save me-1"></i> Salvar Conexão
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
        $(document).ready(function() {
            loadConnections();
            
            // Testar conexão
            $('#testConnectionBtn').click(function() {
                const formData = {
                    name: $('input[name="name"]').val(),
                    host: $('input[name="host"]').val(),
                    port: $('input[name="port"]').val(),
                    username: $('input[name="username"]').val(),
                    password: $('input[name="password"]').val(),
                    database: $('input[name="database"]').val()
                };
                
                // Validação básica
                if (!formData.host || !formData.username || !formData.password) {
                    alert('Preencha os campos obrigatórios: Host, Usuário e Senha');
                    return;
                }
                
                // Simula teste de conexão
                $('#testConnectionBtn').html('<i class="fas fa-spinner fa-spin me-1"></i> Testando...');
                
                // Em produção, aqui seria uma chamada AJAX para a API
                setTimeout(function() {
                    $('#testConnectionBtn').html('<i class="fas fa-vial me-1"></i> Testar Conexão');
                    alert('Funcionalidade de teste será implementada na API\n\n' +
                          'A API testará:\n' +
                          '1. Conexão com MySQL remoto\n' +
                          '2. Verificação se é banco XUI ONE\n' +
                          '3. Permissões de leitura');
                }, 1000);
            });
            
            // Salvar conexão
            $('#saveConnectionBtn').click(function() {
                const formData = {
                    name: $('input[name="name"]').val(),
                    host: $('input[name="host"]').val(),
                    port: $('input[name="port"]').val() || 3306,
                    username: $('input[name="username"]').val(),
                    password: $('input[name="password"]').val(),
                    database: $('input[name="database"]').val() || 'xui'
                };
                
                // Validação
                if (!formData.name || !formData.host || !formData.username || !formData.password) {
                    alert('Preencha todos os campos obrigatórios');
                    return;
                }
                
                // Salva via API
                $.ajax({
                    url: '/api/connections',
                    method: 'POST',
                    contentType: 'application/json',
                    data: JSON.stringify(formData),
                    success: function(response) {
                        alert('Conexão salva com sucesso! ID: ' + response.id);
                        $('#addConnectionModal').modal('hide');
                        loadConnections();
                    },
                    error: function() {
                        alert('Erro ao salvar conexão. Verifique se a API está rodando.');
                    }
                });
            });
        });
        
        function loadConnections() {
            $.ajax({
                url: '/api/connections',
                method: 'GET',
                success: function(response) {
                    const connections = response.connections || [];
                    const tbody = $('#connectionsList');
                    const noConnections = $('#noConnections');
                    const countElement = $('#connectionsCount');
                    
                    countElement.text(connections.length);
                    
                    if (connections.length === 0) {
                        tbody.hide();
                        noConnections.show();
                        return;
                    }
                    
                    noConnections.hide();
                    tbody.show().empty();
                    
                    connections.forEach(conn => {
                        const row = `
                            <tr>
                                <td><strong>${conn.name}</strong></td>
                                <td>${conn.host}:${conn.port}</td>
                                <td>${conn.database}</td>
                                <td>
                                    <span class="connection-status ${conn.is_active ? 'status-connected' : 'status-disconnected'}"></span>
                                    ${conn.is_active ? 'Conectado' : 'Desconectado'}
                                </td>
                                <td>-</td>
                                <td>
                                    <button class="btn btn-sm btn-outline-primary me-1" onclick="testConnection('${conn.id}')">
                                        <i class="fas fa-vial"></i>
                                    </button>
                                    <button class="btn btn-sm btn-outline-success" onclick="syncConnection('${conn.id}')">
                                        <i class="fas fa-sync-alt"></i>
                                    </button>
                                </td>
                            </tr>
                        `;
                        tbody.append(row);
                    });
                }
            });
        }
        
        function testConnection(connectionId) {
            $.ajax({
                url: `/api/connections/${connectionId}/test`,
                method: 'POST',
                success: function(response) {
                    if (response.success) {
                        alert(`✅ Conexão bem-sucedida!\n\n` +
                              `É banco XUI ONE: ${response.is_xui_database ? 'Sim' : 'Não'}\n` +
                              `Tem tabela streams: ${response.has_streams ? 'Sim' : 'Não'}\n` +
                              `Tem tabela categories: ${response.has_categories ? 'Sim' : 'Não'}`);
                    } else {
                        alert(`❌ Falha na conexão:\n${response.error}`);
                    }
                }
            });
        }
        
        function syncConnection(connectionId) {
            if (!confirm('Iniciar sincronização com este servidor XUI ONE?')) return;
            
            $.ajax({
                url: `/api/connections/${connectionId}/sync`,
                method: 'POST',
                success: function(response) {
                    if (response.success) {
                        alert(`✅ Sincronização iniciada!\n\n` +
                              `Categorias encontradas: ${response.categories_count}\n` +
                              `VODs encontrados: ${response.vods_count}\n\n` +
                              `${response.message}`);
                    } else {
                        alert(`❌ Erro na sincronização:\n${response.error}`);
                    }
                }
            });
        }
    </script>
</body>
</html>
EOF

    print_success "Estrutura da API criada"
}

create_systemd_service() {
    print_status "Criando serviços systemd..."
    
    # Serviço da API
    cat > /etc/systemd/system/xui-vods-api.service << EOF
[Unit]
Description=XUI ONE VODs Sync API
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/api
EnvironmentFile=$CONFIG_DIR/api.env
ExecStart=$INSTALL_DIR/venv/bin/python main.py
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/api.log
StandardError=append:$LOG_DIR/api-error.log

[Install]
WantedBy=multi-user.target
EOF

    print_success "Serviço systemd criado"
}

setup_nginx() {
    print_status "Configurando Nginx..."
    
    cat > /etc/nginx/sites-available/xui-vods-sync << EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    access_log /var/log/nginx/xui-vods-access.log;
    error_log /var/log/nginx/xui-vods-error.log;
}
EOF

    ln -sf /etc/nginx/sites-available/xui-vods-sync /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t
    print_success "Nginx configurado"
}

setup_firewall() {
    print_status "Configurando firewall..."
    
    apt-get install -y ufw
    ufw --force enable
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow $API_PORT/tcp
    
    print_success "Firewall configurado"
}

create_util_scripts() {
    print_status "Criando scripts utilitários..."
    
    # Script de status
    cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
echo "=== STATUS XUI ONE VODs Sync ==="
echo ""
echo "Serviços:"
echo "---------"
systemctl status xui-vods-api --no-pager | grep -E "Active:|Main PID:"
echo ""
echo "Portas:"
echo "-------"
netstat -tlnp | grep -E ":80|:$API_PORT" || echo "Portas não encontradas"
echo ""
echo "Logs recentes:"
echo "--------------"
tail -20 /var/log/xui-one-vods-sync/api.log 2>/dev/null || echo "Log não encontrado"
EOF

    # Script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="$INSTALL_DIR/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_\$DATE.tar.gz"

echo "Criando backup..."
mkdir -p "\$BACKUP_DIR"

# Backup do banco
mysqldump -u xui_sync_user -p$MYSQL_LOCAL_PASS xui_sync_manager > /tmp/db_backup.sql

# Cria arquivo compactado
tar -czf "\$BACKUP_DIR/\$BACKUP_FILE" \
    -C /tmp db_backup.sql \
    -C "$CONFIG_DIR" .

rm -f /tmp/db_backup.sql
echo "Backup criado: \$BACKUP_DIR/\$BACKUP_FILE"
EOF

    # Script de restore
    cat > "$INSTALL_DIR/scripts/restore.sh" << 'EOF'
#!/bin/bash
if [ -z "\$1" ]; then
    echo "Uso: \$0 <arquivo_backup.tar.gz>"
    exit 1
fi

BACKUP_FILE="\$1"
TEMP_DIR="/tmp/restore_\$(date +%s)"

echo "Restaurando backup..."
mkdir -p "\$TEMP_DIR"
tar -xzf "\$BACKUP_FILE" -C "\$TEMP_DIR"

# Restaura banco
if [ -f "\$TEMP_DIR/db_backup.sql" ]; then
    mysql -u xui_sync_user -p$MYSQL_LOCAL_PASS xui_sync_manager < "\$TEMP_DIR/db_backup.sql"
fi

# Restaura configurações
if [ -d "\$TEMP_DIR/etc" ]; then
    cp -r "\$TEMP_DIR/etc/xui-one-vods-sync/"* "$CONFIG_DIR/"
fi

rm -rf "\$TEMP_DIR"
echo "Backup restaurado! Reinicie os serviços."
EOF

    chmod +x "$INSTALL_DIR/scripts/"*.sh
    print_success "Scripts criados"
}

start_services() {
    print_status "Iniciando serviços..."
    
    systemctl daemon-reload
    systemctl enable xui-vods-api
    systemctl start xui-vods-api
    systemctl restart nginx
    
    sleep 3
    
    if systemctl is-active --quiet xui-vods-api; then
        print_success "API iniciada com sucesso"
    else
        print_error "Falha ao iniciar API"
        journalctl -u xui-vods-api -n 20
    fi
}

show_summary() {
    print_header
    echo -e "${GREEN}✅ INSTALAÇÃO CONCLUÍDA!${NC}"
    echo ""
    echo "=========================================="
    echo "         XUI ONE VODs Sync v3.0"
    echo "    Sincronizador com Conexão Remota"
    echo "=========================================="
    echo ""
    echo "🌐 ACESSO AO SISTEMA:"
    echo "   URL: http://$(curl -s ifconfig.me):$API_PORT"
    echo "   Ou: http://seu-ip:$API_PORT"
    echo ""
    echo "🔐 LOGIN INICIAL:"
    echo "   Usuário: $ADMIN_USER"
    echo "   Senha: $ADMIN_PASS"
    echo ""
    echo "📋 CONFIGURAÇÃO DO XUI ONE REMOTO:"
    echo "   1. Faça login no sistema"
    echo "   2. Clique em 'Nova Conexão XUI ONE'"
    echo "   3. Informe os dados do banco remoto:"
    echo "      - IP da máquina do XUI ONE"
    echo "      - Usuário MySQL do XUI ONE"
    echo "      - Senha MySQL do XUI ONE"
    echo "      - Porta MySQL (geralmente 3306)"
    echo "      - Nome do banco (geralmente 'xui')"
    echo ""
    echo "⚙️  SERVIÇOS:"
    echo "   Status: systemctl status xui-vods-api"
    echo "   Logs: journalctl -u xui-vods-api -f"
    echo "   Reiniciar: systemctl restart xui-vods-api"
    echo ""
    echo "📁 DIRETÓRIOS:"
    echo "   Instalação: $INSTALL_DIR"
    echo "   Configurações: $CONFIG_DIR"
    echo "   Logs: $LOG_DIR"
    echo "   Backups: $INSTALL_DIR/backups"
    echo ""
    echo "🔧 SCRIPTS ÚTEIS:"
    echo "   Status: $INSTALL_DIR/scripts/status.sh"
    echo "   Backup: $INSTALL_DIR/scripts/backup.sh"
    echo "   Restore: $INSTALL_DIR/scripts/restore.sh"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "   1. Altere a senha do admin após primeiro login"
    echo "   2. Configure backup regular"
    echo "   3. O MySQL do XUI ONE deve permitir conexões remotas"
    echo ""
    echo "=========================================="
    echo ""
    
    # Salva informações em arquivo
    cat > "$INSTALL_DIR/INSTALL_INFO.txt" << EOF
XUI ONE VODs Sync - Informações da Instalação
=============================================
Data: $(date)
Versão: 3.0.0

URL de Acesso: http://$(curl -s ifconfig.me):$API_PORT
Login Inicial: $ADMIN_USER / $ADMIN_PASS

Dados do MySQL Local:
  Host: localhost
  Usuário: xui_sync_user
  Senha: $MYSQL_LOCAL_PASS
  Banco: xui_sync_manager

Configuração de Conexão Remota:
  1. Acesse o sistema
  2. Clique em "Nova Conexão XUI ONE"
  3. Informe dados do banco remoto do XUI ONE

Comandos Úteis:
  systemctl status xui-vods-api
  journalctl -u xui-vods-api -f
  $INSTALL_DIR/scripts/status.sh

⚠️ ALTERE A SENHA DO ADMIN IMEDIATAMENTE!
EOF
    
    print_success "Informações salvas em: $INSTALL_DIR/INSTALL_INFO.txt"
}

main() {
    print_header
    check_root
    check_os
    update_system
    install_mysql_local
    install_python
    install_nginx
    create_user
    setup_directories
    create_config_files
    create_api_structure
    create_systemd_service
    setup_nginx
    setup_firewall
    create_util_scripts
    start_services
    show_summary
}

main 2>&1 | tee "$LOG_DIR/install.log"
