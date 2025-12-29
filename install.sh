#!/bin/bash

# ==========================================
# INSTALADOR SINCRONIZADOR VOD XUI ONE - CORRIGIDO
# Ubuntu 20.04 LTS
# ==========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
DB_ROOT_PASSWORD=""

# Funções de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root"
        echo "Use: sudo bash install.sh"
        exit 1
    fi
}

# Verificar Ubuntu 20.04
check_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$VERSION_ID" != "20.04" ]]; then
            log_warning "Este instalador foi testado no Ubuntu 20.04"
            read -p "Continuar mesmo assim? (s/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Atualizar sistema
update_system() {
    log_info "Atualizando sistema..."
    apt-get update && apt-get upgrade -y
    log_success "Sistema atualizado"
}

# Instalar dependências
install_dependencies() {
    log_info "Instalando dependências do sistema..."
    
    # Remover Apache se existir
    systemctl stop apache2 2>/dev/null
    apt-get remove apache2 -y 2>/dev/null
    
    # Instalar Node.js 18.x
    log_info "Instalando Node.js 18.x..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Instalar MySQL 8.0
    log_info "Instalando MySQL 8.0..."
    apt-get install -y mysql-server mysql-client
    
    # Instalar PHP 8.1
    log_info "Instalando PHP 8.1..."
    apt-get install -y software-properties-common
    add-apt-repository ppa:ondrej/php -y
    apt-get update
    apt-get install -y php8.1 php8.1-cli php8.1-fpm php8.1-mysql php8.1-curl php8.1-mbstring php8.1-xml php8.1-zip
    
    # Instalar Nginx
    log_info "Instalando Nginx..."
    apt-get install -y nginx
    
    # Instalar outras dependências
    apt-get install -y git curl wget unzip build-essential
    
    log_success "Dependências instaladas"
}

# Configurar MySQL
setup_mysql() {
    log_info "Configurando MySQL..."
    
    # Iniciar serviço MySQL
    systemctl start mysql
    systemctl enable mysql
    
    # Configurar senha root se não estiver configurada
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        DB_ROOT_PASSWORD="RootMySQL@2024"
        log_info "Usando senha root padrão: $DB_ROOT_PASSWORD"
    fi
    
    # Configurar senha root do MySQL
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASSWORD}';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Criar banco de dados e usuário
    mysql -u root -p${DB_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS sincronizador_vod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
    mysql -u root -p${DB_ROOT_PASSWORD} -e "CREATE USER IF NOT EXISTS 'vod_user'@'localhost' IDENTIFIED BY 'VodSync@2024';" 2>/dev/null || true
    mysql -u root -p${DB_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON sincronizador_vod.* TO 'vod_user'@'localhost';" 2>/dev/null || true
    mysql -u root -p${DB_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    log_success "MySQL configurado"
}

# Criar estrutura de pastas
create_directory_structure() {
    log_info "Criando estrutura de pastas..."
    
    # Diretório principal
    mkdir -p /var/www/sincronizador-vod
    cd /var/www/sincronizador-vod
    
    # Estrutura completa
    mkdir -p backend/src/{controllers,services,routes,database,utils}
    mkdir -p backend/logs
    
    mkdir -p frontend/public/assets/{css,js,images}
    mkdir -p frontend/app/{controllers,models,views,helpers}
    mkdir -p frontend/config
    mkdir -p frontend/uploads
    
    mkdir -p database
    mkdir -p scripts
    mkdir -p logs
    mkdir -p backups
    
    log_success "Estrutura de pastas criada"
}

# Criar arquivos do backend Node.js CORRIGIDO (sem comentários no JSON)
create_backend_files() {
    log_info "Criando arquivos do backend Node.js..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # package.json CORRIGIDO - SEM COMENTÁRIOS
    # ==========================================
    cat > backend/package.json << 'EOF'
{
  "name": "sincronizador-vod-xui-backend",
  "version": "1.0.0",
  "description": "Sistema de sincronizacao VOD para XUI One",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "dev": "nodemon src/app.js",
    "test": "jest",
    "migrate": "node scripts/migrate.js"
  },
  "keywords": [
    "iptv",
    "vod",
    "xui",
    "synchronizer",
    "tmdb"
  ],
  "author": "Sincronizador VOD System",
  "license": "Commercial",
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.0",
    "axios": "^1.6.0",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "node-cron": "^3.0.3",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "express-validator": "^7.0.1",
    "winston": "^3.11.0",
    "helmet": "^7.0.0",
    "compression": "^1.7.4",
    "multer": "^1.4.5-lts.1",
    "express-rate-limit": "^7.1.5",
    "uuid": "^9.0.1",
    "moment": "^2.29.4",
    "socket.io": "^4.7.2",
    "m3u8-parser": "^6.1.0",
    "cheerio": "^1.0.0-rc.12"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "jest": "^29.7.0",
    "supertest": "^6.3.3"
  },
  "engines": {
    "node": ">=18.0.0",
    "npm": ">=8.0.0"
  }
}
EOF

    # ==========================================
    # .env.example
    # ==========================================
    cat > backend/.env.example << 'EOF'
PORT=3000
NODE_ENV=production
APP_URL=http://localhost
APP_NAME=Sincronizador VOD XUI One

DB_HOST=localhost
DB_PORT=3306
DB_USER=vod_user
DB_PASSWORD=VodSync@2024
DB_NAME=sincronizador_vod
DB_CHARSET=utf8mb4

JWT_SECRET=your_super_secret_jwt_key_change_in_production
JWT_EXPIRES_IN=24h

TMDB_API_KEY=your_tmdb_api_key_here
TMDB_LANGUAGE=pt-BR
TMDB_TIMEOUT=10000

XUI_DB_HOST=localhost
XUI_DB_PORT=3306
XUI_DB_USER=xui_user
XUI_DB_PASSWORD=xui_password
XUI_DB_NAME=xui

SYNC_BATCH_SIZE=50
MAX_RETRY_ATTEMPTS=3
LOG_LEVEL=info
UPLOAD_LIMIT=50mb
SESSION_SECRET=session_secret_change_in_production

SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASSWORD=your_app_password
EMAIL_FROM=noreply@sincronizador.com

LICENSE_KEY=DEMO-LICENSE-KEY-2024
LICENSE_EXPIRE_DAYS=30
EOF

    # ==========================================
    # app.js (versão simplificada para instalação)
    # ==========================================
    cat > backend/src/app.js << 'EOF'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const dotenv = require('dotenv');

// Carregar variáveis de ambiente
dotenv.config();

const app = express();

// Middlewares
app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false
}));
app.use(compression());
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: process.env.UPLOAD_LIMIT || '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Rota de health check
app.get('/api/health', async (req, res) => {
    res.status(200).json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        service: 'Sincronizador VOD XUI One',
        version: '1.0.0',
        environment: process.env.NODE_ENV
    });
});

// Rota de teste
app.get('/api/test', (req, res) => {
    res.json({
        success: true,
        message: 'API funcionando corretamente',
        data: {
            server_time: new Date().toISOString(),
            node_version: process.version,
            platform: process.platform
        }
    });
});

// Rota raiz
app.get('/', (req, res) => {
    res.json({
        name: 'Sincronizador VOD XUI One API',
        version: '1.0.0',
        status: 'online',
        documentation: '/api/docs',
        endpoints: {
            health: '/api/health',
            test: '/api/test'
        }
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Erro não tratado:', err);
    res.status(err.status || 500).json({
        error: {
            message: err.message || 'Erro interno do servidor',
            timestamp: new Date().toISOString()
        }
    });
});

// Rota 404
app.use('*', (req, res) => {
    res.status(404).json({
        error: {
            message: 'Rota não encontrada',
            path: req.originalUrl,
            method: req.method
        }
    });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Servidor rodando na porta ${PORT}`);
    console.log(`Ambiente: ${process.env.NODE_ENV}`);
    console.log(`URL: http://localhost:${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('Recebido SIGTERM, encerrando graciosamente...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('Recebido SIGINT, encerrando graciosamente...');
    process.exit(0);
});
EOF

    # ==========================================
    # database/mysql.js (versão simplificada)
    # ==========================================
    cat > backend/src/database/mysql.js << 'EOF'
const mysql = require('mysql2/promise');

class Database {
    constructor() {
        this.config = {
            host: process.env.DB_HOST || 'localhost',
            port: process.env.DB_PORT || 3306,
            user: process.env.DB_USER || 'vod_user',
            password: process.env.DB_PASSWORD || 'VodSync@2024',
            database: process.env.DB_NAME || 'sincronizador_vod',
            charset: process.env.DB_CHARSET || 'utf8mb4',
            waitForConnections: true,
            connectionLimit: 10,
            queueLimit: 0
        };
        
        this.pool = null;
        this.initializePool();
    }
    
    initializePool() {
        try {
            this.pool = mysql.createPool(this.config);
            console.log('Pool de conexões MySQL inicializado');
        } catch (error) {
            console.error('Erro ao criar pool MySQL:', error);
            throw error;
        }
    }
    
    async query(sql, params = []) {
        let connection;
        try {
            connection = await this.pool.getConnection();
            const [results] = await connection.execute(sql, params);
            return results;
        } catch (error) {
            console.error('Erro na consulta MySQL:', error.message);
            throw error;
        } finally {
            if (connection) connection.release();
        }
    }
    
    async testConnection() {
        try {
            await this.query('SELECT 1');
            return true;
        } catch (error) {
            console.error('Teste de conexão MySQL falhou:', error.message);
            return false;
        }
    }
    
    async close() {
        if (this.pool) {
            await this.pool.end();
            console.log('Pool MySQL fechado');
        }
    }
}

module.exports = new Database();
EOF

    # ==========================================
    # utils/logger.js (versão simplificada)
    # ==========================================
    cat > backend/src/utils/logger.js << 'EOF'
const winston = require('winston');
const path = require('path');
const fs = require('fs');

// Criar diretório de logs se não existir
const logDir = path.join(__dirname, '../../logs');
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
}

// Criar logger
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
        winston.format.timestamp({
            format: 'YYYY-MM-DD HH:mm:ss'
        }),
        winston.format.errors({ stack: true }),
        winston.format.splat(),
        winston.format.json()
    ),
    defaultMeta: { service: 'sincronizador-vod' },
    transports: [
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.printf(({ timestamp, level, message, ...meta }) => {
                    return `${timestamp} [${level}]: ${message}`;
                })
            )
        }),
        new winston.transports.File({
            filename: path.join(logDir, 'error.log'),
            level: 'error',
            maxsize: 5242880,
            maxFiles: 5
        }),
        new winston.transports.File({
            filename: path.join(logDir, 'combined.log'),
            maxsize: 5242880,
            maxFiles: 10
        })
    ]
});

module.exports = logger;
EOF

    log_success "Arquivos do backend criados"
}

# Criar arquivos do frontend PHP (versão simplificada)
create_frontend_files() {
    log_info "Criando arquivos do frontend PHP..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # config/database.php
    # ==========================================
    cat > frontend/config/database.php << 'EOF'
<?php
define('DB_HOST', 'localhost');
define('DB_PORT', '3306');
define('DB_USER', 'vod_user');
define('DB_PASSWORD', 'VodSync@2024');
define('DB_NAME', 'sincronizador_vod');
define('DB_CHARSET', 'utf8mb4');

define('API_BASE_URL', 'http://localhost:3000/api');
define('API_TIMEOUT', 30);

session_start();

function getDatabaseConnection() {
    try {
        $dsn = "mysql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false
        ];
        
        $pdo = new PDO($dsn, DB_USER, DB_PASSWORD, $options);
        return $pdo;
        
    } catch (PDOException $e) {
        die("Erro na conexão com o banco de dados: " . $e->getMessage());
    }
}
?>
EOF

    # ==========================================
    # app/helpers/ApiClient.php (simplificado)
    # ==========================================
    cat > frontend/app/helpers/ApiClient.php << 'EOF'
<?php
class ApiClient {
    private $baseUrl;
    private $token;
    
    public function __construct() {
        $this->baseUrl = API_BASE_URL;
        $this->token = $_SESSION['api_token'] ?? null;
    }
    
    public function request($method, $endpoint, $data = []) {
        $url = $this->baseUrl . $endpoint;
        
        $headers = [
            'Content-Type: application/json',
        ];
        
        if ($this->token) {
            $headers[] = 'Authorization: Bearer ' . $this->token;
        }
        
        $ch = curl_init();
        
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, API_TIMEOUT);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        
        if ($method === 'POST') {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        } elseif ($method === 'PUT') {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        } elseif ($method === 'DELETE') {
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
        }
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        
        if (curl_errno($ch)) {
            throw new Exception('Erro na requisição: ' . curl_error($ch));
        }
        
        curl_close($ch);
        
        return json_decode($response, true) ?? [
            'success' => false,
            'error' => 'Resposta inválida da API'
        ];
    }
    
    public function login($username, $password) {
        $response = $this->request('POST', '/auth/login', [
            'username' => $username,
            'password' => $password
        ]);
        
        if ($response['success'] && isset($response['data']['token'])) {
            $_SESSION['api_token'] = $response['data']['token'];
            $_SESSION['user_id'] = $response['data']['user']['id'] ?? null;
            $_SESSION['username'] = $response['data']['user']['username'] ?? $username;
            $_SESSION['user_type'] = $response['data']['user']['user_type'] ?? 'usuario';
            $_SESSION['logged_in'] = true;
            return true;
        }
        
        return false;
    }
    
    public function healthCheck() {
        return $this->request('GET', '/health');
    }
}
?>
EOF

    # ==========================================
    # index.php (dashboard simplificado)
    # ==========================================
    cat > frontend/public/index.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';

$api = new ApiClient();
$health = $api->healthCheck();
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sincronizador VOD XUI One</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .main-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
            max-width: 800px;
            width: 100%;
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #1a252f 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .content {
            padding: 40px;
        }
        .status-card {
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 20px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .btn-custom {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 10px;
            font-weight: 600;
            transition: all 0.3s;
        }
        .btn-custom:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 20px rgba(52, 152, 219, 0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="main-card">
            <div class="header">
                <h1><i class="bi bi-film"></i> Sincronizador VOD</h1>
                <p class="lead">XUI One Synchronizer</p>
            </div>
            
            <div class="content">
                <div class="row">
                    <div class="col-md-6">
                        <div class="status-card" style="background: #e8f4fc;">
                            <h3><i class="bi bi-cpu"></i> Status do Sistema</h3>
                            <div class="mt-4">
                                <?php if ($health['success']): ?>
                                    <div class="alert alert-success">
                                        <i class="bi bi-check-circle"></i> Sistema Online
                                    </div>
                                    <p>Versão: <?php echo $health['version'] ?? '1.0.0'; ?></p>
                                <?php else: ?>
                                    <div class="alert alert-danger">
                                        <i class="bi bi-exclamation-triangle"></i> Sistema Offline
                                    </div>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="status-card" style="background: #f0f8ff;">
                            <h3><i class="bi bi-lightning-charge"></i> Ações Rápidas</h3>
                            <div class="mt-4">
                                <a href="login.php" class="btn btn-custom w-100 mb-3">
                                    <i class="bi bi-box-arrow-in-right"></i> Login
                                </a>
                                <a href="#" class="btn btn-outline-primary w-100 mb-3">
                                    <i class="bi bi-book"></i> Documentação
                                </a>
                                <a href="#" class="btn btn-outline-secondary w-100">
                                    <i class="bi bi-question-circle"></i> Ajuda
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="row mt-4">
                    <div class="col-12">
                        <div class="alert alert-info">
                            <h5><i class="bi bi-info-circle"></i> Sistema Instalado com Sucesso!</h5>
                            <p class="mb-0">
                                O Sincronizador VOD XUI One foi instalado com sucesso em seu servidor.
                                Faça login para começar a configurar e usar o sistema.
                            </p>
                        </div>
                        
                        <div class="text-center mt-4">
                            <h5>Informações Técnicas</h5>
                            <div class="row mt-3">
                                <div class="col-md-3">
                                    <div class="p-3 bg-light rounded">
                                        <small>Backend API</small>
                                        <h6 class="mb-0">Node.js</h6>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="p-3 bg-light rounded">
                                        <small>Frontend</small>
                                        <h6 class="mb-0">PHP 8.1</h6>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="p-3 bg-light rounded">
                                        <small>Banco de Dados</small>
                                        <h6 class="mb-0">MySQL 8.0</h6>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="p-3 bg-light rounded">
                                        <small>Web Server</small>
                                        <h6 class="mb-0">Nginx</h6>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="footer text-center p-3 bg-light">
                <small class="text-muted">
                    Sincronizador VOD XUI One v1.0.0 &copy; 2024
                    | <a href="#" class="text-decoration-none">Documentação</a>
                    | <a href="#" class="text-decoration-none">Suporte</a>
                </small>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css"></script>
</body>
</html>
EOF

    # ==========================================
    # login.php (simplificado)
    # ==========================================
    cat > frontend/public/login.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';

session_start();

if (isset($_SESSION['logged_in']) && $_SESSION['logged_in'] === true) {
    header('Location: index.php');
    exit;
}

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if (empty($username) || empty($password)) {
        $error = 'Por favor, preencha todos os campos.';
    } else {
        $api = new ApiClient();
        
        // Login padrão (para teste)
        if ($username === 'admin' && $password === 'Admin@2024') {
            $_SESSION['logged_in'] = true;
            $_SESSION['username'] = 'admin';
            $_SESSION['user_type'] = 'admin';
            header('Location: index.php');
            exit;
        } else {
            $error = 'Usuário ou senha incorretos.';
        }
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - Sincronizador VOD</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
            width: 100%;
            max-width: 400px;
            overflow: hidden;
        }
        .login-header {
            background: linear-gradient(135deg, #2c3e50 0%, #1a252f 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .login-body {
            padding: 40px;
        }
        .btn-login {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            border: none;
            padding: 12px;
            border-radius: 10px;
            font-weight: 600;
            width: 100%;
        }
        .form-control {
            border-radius: 10px;
            padding: 12px;
            border: 2px solid #e0e0e0;
        }
        .form-control:focus {
            border-color: #3498db;
            box-shadow: 0 0 0 0.25rem rgba(52, 152, 219, 0.25);
        }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="login-header">
            <h2><i class="bi bi-film"></i> Sincronizador VOD</h2>
            <p class="mb-0">XUI One Synchronizer</p>
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
                    <label for="username" class="form-label">Usuário</label>
                    <input type="text" class="form-control" id="username" name="username" 
                           placeholder="Digite seu usuário" required autofocus>
                </div>
                
                <div class="mb-4">
                    <label for="password" class="form-label">Senha</label>
                    <input type="password" class="form-control" id="password" name="password" 
                           placeholder="Digite sua senha" required>
                </div>
                
                <button type="submit" class="btn btn-login">
                    <i class="bi bi-box-arrow-in-right"></i> Entrar
                </button>
            </form>
            
            <div class="mt-4 text-center">
                <small class="text-muted">
                    Credenciais padrão: admin / Admin@2024
                </small>
            </div>
        </div>
        
        <div class="login-footer text-center p-3 bg-light">
            <small class="text-muted">
                Sistema de Sincronização VOD XUI One v1.0.0
            </small>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
</body>
</html>
EOF

    log_success "Arquivos do frontend criados"
}

# Criar arquivos de banco de dados simplificados
create_database_files() {
    log_info "Criando arquivos do banco de dados..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # database/schema.sql (simplificado)
    # ==========================================
    cat > database/schema.sql << 'EOF'
-- Schema simplificado para instalação inicial

CREATE DATABASE IF NOT EXISTS sincronizador_vod 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE sincronizador_vod;

-- Tabela de usuários
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    user_type ENUM('admin', 'revendedor', 'usuario') DEFAULT 'usuario',
    license_key VARCHAR(100) UNIQUE,
    parent_id INT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP NULL,
    login_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_parent_id (parent_id),
    INDEX idx_user_type (user_type),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de conexões XUI
CREATE TABLE xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    connection_name VARCHAR(100) NOT NULL,
    xui_ip VARCHAR(45) NOT NULL,
    xui_port INT DEFAULT 3306,
    db_user VARCHAR(100) NOT NULL,
    db_password VARCHAR(255) NOT NULL,
    db_name VARCHAR(100) DEFAULT 'xui',
    is_active BOOLEAN DEFAULT TRUE,
    last_test TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de listas M3U
CREATE TABLE m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    list_name VARCHAR(100) NOT NULL,
    m3u_content LONGTEXT NOT NULL,
    total_items INT DEFAULT 0,
    movies_count INT DEFAULT 0,
    series_count INT DEFAULT 0,
    last_scanned TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de sincronização
CREATE TABLE sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    sync_type ENUM('manual', 'auto') NOT NULL,
    items_total INT DEFAULT 0,
    items_added INT DEFAULT 0,
    items_updated INT DEFAULT 0,
    items_failed INT DEFAULT 0,
    duration_seconds INT DEFAULT 0,
    status ENUM('running', 'completed', 'failed') DEFAULT 'running',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inserir usuário administrador
INSERT INTO users (username, email, password, user_type, is_active) VALUES
('admin', 'admin@sincronizador.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'admin', TRUE);
EOF

    log_success "Arquivos do banco de dados criados"
}

# Configurar Nginx
setup_nginx() {
    log_info "Configurando Nginx..."
    
    cat > /etc/nginx/sites-available/sincronizador-vod << 'EOF'
server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    root /var/www/sincronizador-vod/frontend/public;
    index index.php index.html index.htm;
    
    access_log /var/log/nginx/sincronizador-vod.access.log;
    error_log /var/log/nginx/sincronizador-vod.error.log;
    
    client_max_body_size 100M;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
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
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
        fastcgi_connect_timeout 300s;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~ /(config|app|database|backups|logs|\.env|\.git) {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
    
    # Remover configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Habilitar site
    ln -sf /etc/nginx/sites-available/sincronizador-vod /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t
    
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        systemctl enable nginx
        log_success "Nginx configurado"
    else
        log_error "Erro na configuração do Nginx"
        exit 1
    fi
}

# Configurar PHP-FPM
setup_php_fpm() {
    log_info "Configurando PHP-FPM..."
    
    # Configurações do PHP
    sed -i 's/^;date\.timezone =$/date.timezone = America\/Sao_Paulo/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^upload_max_filesize = .*$/upload_max_filesize = 100M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^post_max_size = .*$/post_max_size = 100M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^max_execution_time = .*$/max_execution_time = 300/' /etc/php/8.1/fpm/php.ini
    
    systemctl restart php8.1-fpm
    systemctl enable php8.1-fpm
    
    log_success "PHP-FPM configurado"
}

# Configurar Node.js como serviço
setup_nodejs_service() {
    log_info "Configurando Node.js como serviço..."
    
    cat > /etc/systemd/system/sincronizador-vod.service << 'EOF'
[Unit]
Description=Sincronizador VOD XUI One - Backend API
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/sincronizador-vod/backend
Environment=NODE_ENV=production
Environment=PATH=/usr/bin:/usr/local/bin
ExecStart=/usr/bin/node /var/www/sincronizador-vod/backend/src/app.js
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

StandardOutput=journal
StandardError=journal
SyslogIdentifier=sincronizador-vod

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sincronizador-vod
    
    log_success "Serviço Node.js configurado"
}

# Configurar permissões
setup_permissions() {
    log_info "Configurando permissões..."
    
    # Definir proprietário
    chown -R www-data:www-data /var/www/sincronizador-vod
    
    # Configurar permissões
    find /var/www/sincronizador-vod -type d -exec chmod 755 {} \;
    find /var/www/sincronizador-vod -type f -exec chmod 644 {} \;
    
    # Permissões especiais
    chmod +x /var/www/sincronizador-vod/backend/src/app.js
    
    # Diretórios de logs com permissões de escrita
    chmod 775 /var/www/sincronizador-vod/backend/logs
    chmod 775 /var/www/sincronizador-vod/logs
    chmod 775 /var/www/sincronizador-vod/frontend/uploads
    
    log_success "Permissões configuradas"
}

# Instalar dependências do Node.js CORRIGIDO
install_node_dependencies() {
    log_info "Instalando dependências do Node.js..."
    
    cd /var/www/sincronizador-vod/backend
    
    # Copiar .env.example para .env
    cp .env.example .env
    
    # Gerar chaves JWT secretas
    jwt_secret=$(openssl rand -hex 32)
    session_secret=$(openssl rand -hex 32)
    
    # Atualizar .env com valores reais
    sed -i "s|your_super_secret_jwt_key_change_in_production|${jwt_secret}|g" .env
    sed -i "s|session_secret_change_in_production|${session_secret}|g" .env
    
    # Atualizar npm
    npm install -g npm@latest
    
    # Instalar dependências uma por uma para evitar erros
    log_info "Instalando dependências individualmente..."
    
    # Instalar core dependencies primeiro
    npm install express@^4.18.2
    npm install mysql2@^3.6.0
    npm install axios@^1.6.0
    npm install cors@^2.8.5
    npm install dotenv@^16.3.1
    
    # Instalar outras dependências
    npm install node-cron@^3.0.3 bcryptjs@^2.4.3 jsonwebtoken@^9.0.2
    npm install express-validator@^7.0.1 winston@^3.11.0 helmet@^7.0.0
    npm install compression@^1.7.4 multer@^1.4.5-lts.1 express-rate-limit@^7.1.5
    npm install uuid@^9.0.1 moment@^2.29.4 socket.io@^4.7.2
    npm install m3u8-parser@^6.1.0 cheerio@^1.0.0-rc.12
    
    if [ $? -eq 0 ]; then
        log_success "Dependências do Node.js instaladas"
    else
        log_error "Erro ao instalar dependências do Node.js"
        exit 1
    fi
}

# Importar banco de dados
import_database() {
    log_info "Importando banco de dados..."
    
    # Importar schema
    mysql -u root -p${DB_ROOT_PASSWORD} < /var/www/sincronizador-vod/database/schema.sql
    
    if [ $? -eq 0 ]; then
        log_success "Schema importado"
    else
        log_error "Erro ao importar schema"
        exit 1
    fi
}

# Configurar firewall
setup_firewall() {
    log_info "Configurando firewall..."
    
    # Verificar se o UFW está instalado
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        ufw --force enable
        log_success "Firewall configurado"
    else
        log_warning "UFW não instalado, pulando configuração do firewall"
    fi
}

# Criar script de manutenção
create_maintenance_scripts() {
    log_info "Criando scripts de manutenção..."
    
    cd /var/www/sincronizador-vod/scripts
    
    # Script de status
    cat > status.sh << 'EOF'
#!/bin/bash
echo "=== STATUS DO SINCRONIZADOR VOD ==="
echo "Data/Hora: $(date)"
echo
echo "SERVIÇOS:"
echo "---------"
systemctl status sincronizador-vod --no-pager | head -5
echo
systemctl status nginx --no-pager | head -5
echo
systemctl status mysql --no-pager | head -5
echo
systemctl status php8.1-fpm --no-pager | head -5
echo
echo "API STATUS:"
echo "----------"
curl -s http://localhost:3000/api/health || echo "API não responde"
EOF
    
    chmod +x status.sh
    
    log_success "Scripts de manutenção criados"
}

# Finalizar instalação
finalize_installation() {
    log_info "Finalizando instalação..."
    
    # Iniciar serviços
    systemctl start sincronizador-vod
    systemctl start nginx
    systemctl start mysql
    systemctl start php8.1-fpm
    
    # Aguardar alguns segundos
    sleep 5
    
    # Verificar status dos serviços
    echo
    echo "=== STATUS DOS SERVIÇOS ==="
    if systemctl is-active sincronizador-vod >/dev/null 2>&1; then
        echo "✅ Backend Node.js: ATIVO"
    else
        echo "❌ Backend Node.js: INATIVO"
    fi
    
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "✅ Nginx: ATIVO"
    else
        echo "❌ Nginx: INATIVO"
    fi
    
    if systemctl is-active mysql >/dev/null 2>&1; then
        echo "✅ MySQL: ATIVO"
    else
        echo "❌ MySQL: INATIVO"
    fi
    
    if systemctl is-active php8.1-fpm >/dev/null 2>&1; then
        echo "✅ PHP-FPM: ATIVO"
    else
        echo "❌ PHP-FPM: INATIVO"
    fi
    
    # Testar API
    echo
    echo "=== TESTE DA API ==="
    api_response=$(curl -s http://localhost:3000/api/health 2>/dev/null || echo "{}")
    if echo "$api_response" | grep -q "ok"; then
        echo "✅ API: RESPONDENDO"
    else
        echo "❌ API: NÃO RESPONDE"
    fi
    
    # Testar frontend
    echo
    echo "=== TESTE DO FRONTEND ==="
    frontend_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
    if [ "$frontend_response" = "200" ]; then
        echo "✅ Frontend: ACESSÍVEL"
    else
        echo "❌ Frontend: NÃO ACESSÍVEL (HTTP $frontend_response)"
    fi
    
    # Criar arquivo de informações
    local_ip=$(hostname -I | awk '{print $1}')
    
    cat > /var/www/sincronizador-vod/INSTALACAO.txt << EOF
==========================================
INFORMAÇÕES DA INSTALAÇÃO - SINCRONIZADOR VOD
==========================================

DATA DA INSTALAÇÃO: $(date)
VERSÃO: 1.0.0

==========================================
ACESSO AO SISTEMA
==========================================

PAINEL WEB: http://${local_ip}/
            http://localhost/

USUÁRIO: admin
SENHA: Admin@2024

API: http://localhost:3000/api

==========================================
DIRETÓRIOS
==========================================

PROJETO: /var/www/sincronizador-vod/
BACKEND: /var/www/sincronizador-vod/backend/
FRONTEND: /var/www/sincronizador-vod/frontend/
LOGS: /var/www/sincronizador-vod/logs/
BANCO: /var/www/sincronizador-vod/database/

==========================================
COMANDOS ÚTEIS
==========================================

# Reiniciar serviços
systemctl restart sincronizador-vod nginx mysql

# Verificar status
cd /var/www/sincronizador-vod/scripts && ./status.sh

# Verificar logs do backend
tail -f /var/www/sincronizador-vod/backend/logs/combined.log

==========================================
PRÓXIMOS PASSOS
==========================================

1. Acesse http://${local_ip}/
2. Faça login com admin/Admin@2024
3. Configure sua chave TMDb
4. Adicione conexão XUI
5. Importe lista M3U

==========================================
SUPORTE
==========================================

Verifique os logs em caso de problemas:
- Backend: /var/www/sincronizador-vod/backend/logs/
- Nginx: /var/log/nginx/sincronizador-vod.error.log
- Sistema: journalctl -u sincronizador-vod

==========================================
EOF
    
    echo
    echo "=========================================="
    echo " 🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "=========================================="
    echo
    echo "📋 INFORMAÇÕES IMPORTANTES:"
    echo "----------------------------"
    echo "• Sistema instalado em: /var/www/sincronizador-vod/"
    echo "• Painel web: http://${local_ip}/"
    echo "• Usuário: admin"
    echo "• Senha: Admin@2024"
    echo
    echo "🚀 PARA COMEÇAR:"
    echo "----------------"
    echo "1. Acesse: http://${local_ip}/"
    echo "2. Faça login com as credenciais acima"
    echo "3. Configure o sistema"
    echo
    echo "🔧 COMANDOS DE GERENCIAMENTO:"
    echo "---------------------------"
    echo "• systemctl status sincronizador-vod"
    echo "• tail -f /var/www/sincronizador-vod/backend/logs/combined.log"
    echo "• cd /var/www/sincronizador-vod/scripts && ./status.sh"
    echo
    echo "⚠️  IMPORTANTE:"
    echo "----------------"
    echo "• Altere a senha padrão após o primeiro login!"
    echo "• Consulte o arquivo INSTALACAO.txt para mais detalhes"
    echo
    echo "=========================================="
}

# Função principal
main() {
    clear
    echo "=========================================="
    echo " INSTALADOR SINCRONIZADOR VOD XUI ONE"
    echo "        Ubuntu 20.04 LTS"
    echo "        VERSÃO CORRIGIDA"
    echo "=========================================="
    echo
    
    # Obter senha do MySQL root
    echo "Digite a senha root do MySQL:"
    echo "(Deixe em branco para usar a senha padrão)"
    read -s DB_ROOT_PASSWORD
    
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        DB_ROOT_PASSWORD="RootMySQL@2024"
        echo "Usando senha padrão: $DB_ROOT_PASSWORD"
    fi
    
    # Etapas de instalação
    check_root
    check_ubuntu_version
    update_system
    install_dependencies
    setup_mysql
    create_directory_structure
    create_backend_files
    create_frontend_files
    create_database_files
    setup_nginx
    setup_php_fpm
    setup_nodejs_service
    setup_permissions
    install_node_dependencies
    import_database
    setup_firewall
    create_maintenance_scripts
    finalize_installation
    
    echo "Instalação concluída em: $(date)"
}

# Executar instalação
main "$@"
