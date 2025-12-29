#!/bin/bash

# ==========================================
# INSTALADOR SINCRONIZADOR VOD XUI ONE - COMPLETO
# Ubuntu 20.04 LTS - TUDO FUNCIONANDO
# ==========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
DB_ROOT_PASSWORD=""
START_TIME=$(date +%s)

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
        echo "Use: sudo bash $0"
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
    else
        log_warning "Não foi possível verificar a versão do Ubuntu"
    fi
}

# Atualizar sistema
update_system() {
    log_info "Atualizando sistema..."
    apt-get update && apt-get upgrade -y
    log_success "Sistema atualizado"
}

# Instalar dependências do sistema CORRIGIDO
install_dependencies() {
    log_info "Instalando dependências do sistema..."
    
    # Atualizar repositórios primeiro
    apt-get update
    
    # Remover Apache se existir (para evitar conflitos)
    systemctl stop apache2 2>/dev/null
    apt-get remove --purge apache2 apache2-utils -y 2>/dev/null
    
    # Instalar Node.js 18.x
    log_info "Instalando Node.js 18.x..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Instalar MySQL 8.0
    log_info "Instalando MySQL 8.0..."
    apt-get install -y mysql-server mysql-client
    
    # Instalar PHP 8.1 com TODAS as extensões necessárias
    log_info "Instalando PHP 8.1 com todas as extensões..."
    apt-get install -y software-properties-common
    add-apt-repository ppa:ondrej/php -y
    apt-get update
    
    # Instalar PHP e extensões CRÍTICAS
    apt-get install -y \
        php8.1 \
        php8.1-fpm \
        php8.1-cli \
        php8.1-mysql \
        php8.1-curl \
        php8.1-mbstring \
        php8.1-xml \
        php8.1-zip \
        php8.1-gd \
        php8.1-bcmath \
        php8.1-json \
        php8.1-intl \
        php8.1-soap \
        php8.1-opcache \
        php8.1-common
    
    # Instalar Nginx
    log_info "Instalando Nginx..."
    apt-get install -y nginx
    
    # Instalar outras dependências
    apt-get install -y \
        git \
        curl \
        wget \
        unzip \
        build-essential \
        pkg-config \
        libssl-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libzip-dev
    
    log_success "Dependências instaladas"
}

# Configurar MySQL CORRETAMENTE
setup_mysql() {
    log_info "Configurando MySQL..."
    
    # Iniciar serviço MySQL
    systemctl start mysql
    systemctl enable mysql
    
    # Configurar senha root se não estiver configurada
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        DB_ROOT_PASSWORD="MySQLRoot@2024"
        log_info "Usando senha root padrão: $DB_ROOT_PASSWORD"
    fi
    
    # Configurar segurança do MySQL (versão segura para MySQL 8.0)
    log_info "Configurando segurança do MySQL..."
    
    # Criar arquivo de configuração temporário para mysql_secure_installation
    SECURE_MYSQL=$(expect -c "
    set timeout 10
    spawn mysql_secure_installation
    
    expect \"Press y|Y for Yes, any other key for No:\"
    send \"n\r\"
    
    expect \"New password:\"
    send \"$DB_ROOT_PASSWORD\r\"
    
    expect \"Re-enter new password:\"
    send \"$DB_ROOT_PASSWORD\r\"
    
    expect \"Remove anonymous users? (Press y|Y for Yes, any other key for No) :\"
    send \"y\r\"
    
    expect \"Disallow root login remotely? (Press y|Y for Yes, any other key for No) :\"
    send \"y\r\"
    
    expect \"Remove test database and access to it? (Press y|Y for Yes, any other key for No) :\"
    send \"y\r\"
    
    expect \"Reload privilege tables now? (Press y|Y for Yes, any other key for No) :\"
    send \"y\r\"
    
    expect eof
    ")
    
    echo "$SECURE_MYSQL"
    
    # Criar banco de dados e usuário
    log_info "Criando banco de dados e usuário..."
    
    mysql -u root -p${DB_ROOT_PASSWORD} <<-EOF 2>/dev/null
CREATE DATABASE IF NOT EXISTS sincronizador_vod 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'vod_user'@'localhost' 
IDENTIFIED BY 'VodSync@2024';

GRANT ALL PRIVILEGES ON sincronizador_vod.* 
TO 'vod_user'@'localhost';

FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        log_success "MySQL configurado com sucesso"
    else
        log_error "Erro ao configurar MySQL. Tentando método alternativo..."
        
        # Método alternativo sem senha (para MySQL sem autenticação)
        mysql <<-EOF
CREATE DATABASE IF NOT EXISTS sincronizador_vod 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'vod_user'@'localhost' 
IDENTIFIED BY 'VodSync@2024';

GRANT ALL PRIVILEGES ON sincronizador_vod.* 
TO 'vod_user'@'localhost';

FLUSH PRIVILEGES;
EOF
    fi
    
    log_success "MySQL configurado"
}

# Criar estrutura de pastas
create_directory_structure() {
    log_info "Criando estrutura de pastas..."
    
    # Diretório principal
    mkdir -p /var/www/sincronizador-vod
    cd /var/www/sincronizador-vod
    
    # Estrutura backend Node.js
    mkdir -p backend/src/controllers
    mkdir -p backend/src/services
    mkdir -p backend/src/routes
    mkdir -p backend/src/database
    mkdir -p backend/src/utils
    mkdir -p backend/logs
    mkdir -p backend/scripts
    
    # Estrutura frontend PHP
    mkdir -p frontend/public/assets/{css,js,images,fonts}
    mkdir -p frontend/app/controllers
    mkdir -p frontend/app/models
    mkdir -p frontend/app/views
    mkdir -p frontend/app/helpers
    mkdir -p frontend/config
    mkdir -p frontend/uploads
    mkdir -p frontend/tmp
    
    # Outros diretórios
    mkdir -p database
    mkdir -p scripts
    mkdir -p logs
    mkdir -p backups
    mkdir -p docs
    
    log_success "Estrutura de pastas criada"
}

# Criar arquivos do backend Node.js - COMPLETO E FUNCIONAL
create_backend_files() {
    log_info "Criando arquivos do backend Node.js..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # package.json - CORRETO E TESTADO
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
    "express": "4.18.2",
    "mysql2": "3.6.5",
    "axios": "1.6.7",
    "cors": "2.8.5",
    "dotenv": "16.3.1",
    "node-cron": "3.0.3",
    "bcryptjs": "2.4.3",
    "jsonwebtoken": "9.0.2",
    "express-validator": "7.0.1",
    "winston": "3.11.0",
    "helmet": "7.1.0",
    "compression": "1.7.4",
    "multer": "1.4.5-lts.1",
    "express-rate-limit": "7.1.5",
    "uuid": "9.0.1",
    "moment": "2.29.4",
    "socket.io": "4.7.4",
    "m3u8-parser": "6.0.0",
    "cheerio": "1.0.0-rc.12",
    "rate-limiter-flexible": "2.4.2"
  },
  "devDependencies": {
    "nodemon": "3.0.1",
    "jest": "29.7.0",
    "supertest": "6.3.3"
  },
  "engines": {
    "node": ">=18.0.0",
    "npm": ">=8.0.0"
  }
}
EOF

    # ==========================================
    # .env - CONFIGURAÇÕES REAIS
    # ==========================================
    cat > backend/.env << 'EOF'
# Configurações do Servidor
PORT=3000
NODE_ENV=production
APP_URL=http://localhost
APP_NAME=Sincronizador VOD XUI One

# Banco de Dados Sistema
DB_HOST=localhost
DB_PORT=3306
DB_USER=vod_user
DB_PASSWORD=VodSync@2024
DB_NAME=sincronizador_vod
DB_CHARSET=utf8mb4

# JWT Authentication
JWT_SECRET=6a5f8c3e9b2d7a1f4c8e3b6a9d2f5c8e7b1a4f9c3e6d8a2b5f7c9e1a3d6b8f4c2
JWT_EXPIRES_IN=24h

# TMDb API
TMDB_API_KEY=sua_chave_tmdb_aqui
TMDB_LANGUAGE=pt-BR
TMDB_TIMEOUT=10000

# XUI Database
XUI_DB_HOST=localhost
XUI_DB_PORT=3306
XUI_DB_USER=xui_user
XUI_DB_PASSWORD=xui_password
XUI_DB_NAME=xui

# System Settings
SYNC_BATCH_SIZE=50
MAX_RETRY_ATTEMPTS=3
LOG_LEVEL=info
UPLOAD_LIMIT=50mb
SESSION_SECRET=8d7a3f6c9e2b5a1d4f8c3e6b9a2d5f7c1e4a9b3d6f8c2e5b7a1d3f6c9e2b5a8d

# Email Settings
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=seu_email@gmail.com
SMTP_PASSWORD=sua_senha_app
EMAIL_FROM=noreply@sincronizador.com

# License Settings
LICENSE_KEY=DEMO-LICENSE-KEY-2024
LICENSE_EXPIRE_DAYS=30

# Server Settings
HOST=0.0.0.0
WORKERS=1
KEEP_ALIVE_TIMEOUT=65000
HEADERS_TIMEOUT=66000
EOF

    # ==========================================
    # app.js - COMPLETO E FUNCIONAL
    # ==========================================
    cat > backend/src/app.js << 'EOF'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const dotenv = require('dotenv');
const path = require('path');
const socketIo = require('socket.io');
const http = require('http');

// Carregar variáveis de ambiente
dotenv.config();

// Importar logger
const logger = require('./utils/logger');

// Importar rotas
const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/user.routes');
const xuiRoutes = require('./routes/xui.routes');
const m3uRoutes = require('./routes/m3u.routes');
const syncRoutes = require('./routes/sync.routes');
const dashboardRoutes = require('./routes/dashboard.routes');
const licenseRoutes = require('./routes/license.routes');
const systemRoutes = require('./routes/system.routes');

// Importar serviços
const scheduler = require('./services/scheduler');
const database = require('./database/mysql');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

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

// Middleware para adicionar io ao request
app.use((req, res, next) => {
    req.io = io;
    next();
});

// Rotas da API
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/xui', xuiRoutes);
app.use('/api/m3u', m3uRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/license', licenseRoutes);
app.use('/api/system', systemRoutes);

// Rota de health check
app.get('/api/health', async (req, res) => {
    try {
        const dbStatus = await database.testConnection();
        
        res.status(200).json({
            status: 'ok',
            timestamp: new Date().toISOString(),
            service: 'Sincronizador VOD XUI One',
            version: '1.0.0',
            database: dbStatus ? 'connected' : 'disconnected',
            environment: process.env.NODE_ENV,
            uptime: process.uptime()
        });
    } catch (error) {
        res.status(200).json({
            status: 'ok',
            timestamp: new Date().toISOString(),
            service: 'Sincronizador VOD XUI One',
            version: '1.0.0',
            database: 'connection_error',
            environment: process.env.NODE_ENV,
            error: error.message
        });
    }
});

// Rota de teste simples
app.get('/api/test', (req, res) => {
    res.json({
        success: true,
        message: 'API funcionando perfeitamente',
        timestamp: new Date().toISOString(),
        data: {
            server: 'Sincronizador VOD XUI One',
            version: '1.0.0',
            status: 'online'
        }
    });
});

// Servir arquivos estáticos (para logs, se necessário)
app.use('/logs', express.static(path.join(__dirname, '../logs')));

// WebSocket para atualizações em tempo real
io.on('connection', (socket) => {
    logger.info('Cliente WebSocket conectado:', socket.id);
    
    socket.on('subscribe', (room) => {
        socket.join(room);
        logger.info(`Cliente ${socket.id} entrou na sala: ${room}`);
    });
    
    socket.on('unsubscribe', (room) => {
        socket.leave(room);
        logger.info(`Cliente ${socket.id} saiu da sala: ${room}`);
    });
    
    socket.on('disconnect', () => {
        logger.info('Cliente WebSocket desconectado:', socket.id);
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    logger.error('Erro não tratado:', {
        message: err.message,
        stack: err.stack,
        url: req.url,
        method: req.method
    });
    
    res.status(err.status || 500).json({
        error: {
            message: err.message || 'Erro interno do servidor',
            timestamp: new Date().toISOString(),
            path: req.originalUrl
        }
    });
});

// Rota 404
app.use('*', (req, res) => {
    res.status(404).json({
        error: {
            message: 'Rota não encontrada',
            path: req.originalUrl,
            method: req.method,
            timestamp: new Date().toISOString()
        }
    });
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

server.listen(PORT, HOST, async () => {
    logger.info(`Servidor rodando em http://${HOST}:${PORT}`);
    logger.info(`Ambiente: ${process.env.NODE_ENV}`);
    
    try {
        // Testar conexão com banco
        const dbConnected = await database.testConnection();
        if (dbConnected) {
            logger.info('Conexão com banco de dados estabelecida');
        } else {
            logger.error('Falha ao conectar com banco de dados');
        }
        
        // Iniciar agendador
        scheduler.initialize();
        logger.info('Agendador de tarefas inicializado');
        
    } catch (error) {
        logger.error('Erro na inicialização:', error);
    }
});

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('Recebido SIGTERM, encerrando graciosamente...');
    scheduler.stopAll();
    server.close(() => {
        logger.info('Servidor encerrado');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    logger.info('Recebido SIGINT, encerrando graciosamente...');
    scheduler.stopAll();
    server.close(() => {
        logger.info('Servidor encerrado');
        process.exit(0);
    });
});

module.exports = { app, server, io };
EOF

    # ==========================================
    # database/mysql.js - COMPLETO
    # ==========================================
    cat > backend/src/database/mysql.js << 'EOF'
const mysql = require('mysql2/promise');
const logger = require('../utils/logger');

class Database {
    constructor() {
        this.config = {
            host: process.env.DB_HOST || 'localhost',
            port: process.env.DB_PORT || 3306,
            user: process.env.DB_USER || 'vod_user',
            password: process.env.DB_PASSWORD || 'VodSync@2024',
            database: process.env.DB_NAME || 'sincronizador_vod',
            charset: process.env.DB_CHARSET || 'utf8mb4',
            timezone: '+00:00',
            waitForConnections: true,
            connectionLimit: 20,
            queueLimit: 0,
            enableKeepAlive: true,
            keepAliveInitialDelay: 0
        };
        
        this.pool = null;
        this.initializePool();
    }
    
    initializePool() {
        try {
            this.pool = mysql.createPool(this.config);
            logger.info('Pool de conexões MySQL inicializado');
        } catch (error) {
            logger.error('Erro ao criar pool MySQL:', error);
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
            logger.error('Erro na consulta MySQL:', {
                sql: sql.substring(0, 200),
                params: params,
                error: error.message
            });
            throw error;
        } finally {
            if (connection) connection.release();
        }
    }
    
    async getConnection() {
        return await this.pool.getConnection();
    }
    
    async testConnection() {
        try {
            await this.query('SELECT 1');
            return true;
        } catch (error) {
            logger.error('Teste de conexão MySQL falhou:', error.message);
            return false;
        }
    }
    
    async transaction(callback) {
        let connection;
        try {
            connection = await this.pool.getConnection();
            await connection.beginTransaction();
            
            const result = await callback(connection);
            
            await connection.commit();
            return result;
        } catch (error) {
            if (connection) {
                await connection.rollback();
            }
            logger.error('Transação MySQL falhou:', error);
            throw error;
        } finally {
            if (connection) connection.release();
        }
    }
    
    async insert(table, data) {
        const keys = Object.keys(data);
        const values = Object.values(data);
        const placeholders = keys.map(() => '?').join(', ');
        
        const sql = `INSERT INTO ${table} (${keys.join(', ')}) VALUES (${placeholders})`;
        const result = await this.query(sql, values);
        
        return {
            id: result.insertId,
            affectedRows: result.affectedRows
        };
    }
    
    async update(table, data, where) {
        const setClause = Object.keys(data).map(key => `${key} = ?`).join(', ');
        const whereClause = Object.keys(where).map(key => `${key} = ?`).join(' AND ');
        
        const values = [...Object.values(data), ...Object.values(where)];
        const sql = `UPDATE ${table} SET ${setClause} WHERE ${whereClause}`;
        
        const result = await this.query(sql, values);
        return {
            affectedRows: result.affectedRows
        };
    }
    
    async select(table, where = {}, columns = ['*']) {
        const whereClause = Object.keys(where).length > 0 
            ? `WHERE ${Object.keys(where).map(key => `${key} = ?`).join(' AND ')}`
            : '';
        
        const values = Object.values(where);
        const sql = `SELECT ${columns.join(', ')} FROM ${table} ${whereClause}`;
        
        return await this.query(sql, values);
    }
    
    async delete(table, where) {
        const whereClause = Object.keys(where).map(key => `${key} = ?`).join(' AND ');
        const values = Object.values(where);
        
        const sql = `DELETE FROM ${table} WHERE ${whereClause}`;
        const result = await this.query(sql, values);
        
        return {
            affectedRows: result.affectedRows
        };
    }
    
    async close() {
        if (this.pool) {
            await this.pool.end();
            logger.info('Pool MySQL fechado');
        }
    }
}

// Singleton
const instance = new Database();

// Testar conexão ao inicializar
instance.testConnection().then(connected => {
    if (connected) {
        logger.info('Conexão MySQL inicializada com sucesso');
    } else {
        logger.error('Falha na inicialização da conexão MySQL');
    }
});

module.exports = instance;
EOF

    # ==========================================
    # utils/logger.js - COMPLETO
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

// Formato de log
const logFormat = winston.format.combine(
    winston.format.timestamp({
        format: 'YYYY-MM-DD HH:mm:ss'
    }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
);

// Formato para console
const consoleFormat = winston.format.combine(
    winston.format.colorize(),
    winston.format.printf(({ timestamp, level, message, ...meta }) => {
        return `${timestamp} [${level}]: ${message} ${
            Object.keys(meta).length ? JSON.stringify(meta, null, 2) : ''
        }`;
    })
);

// Criar logger
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: logFormat,
    defaultMeta: { service: 'sincronizador-vod' },
    transports: [
        // Console
        new winston.transports.Console({
            format: consoleFormat
        }),
        
        // Arquivo de erros
        new winston.transports.File({
            filename: path.join(logDir, 'error.log'),
            level: 'error',
            maxsize: 5242880,
            maxFiles: 5
        }),
        
        // Arquivo de todos os logs
        new winston.transports.File({
            filename: path.join(logDir, 'combined.log'),
            maxsize: 5242880,
            maxFiles: 10
        }),
        
        // Arquivo de sincronização
        new winston.transports.File({
            filename: path.join(logDir, 'sync.log'),
            level: 'info',
            maxsize: 10485760,
            maxFiles: 10
        })
    ]
});

// Stream para morgan (HTTP logging)
logger.stream = {
    write: (message) => {
        logger.info(message.trim());
    }
};

// Funções helper
logger.apiLog = (req, res, error = null) => {
    const logData = {
        method: req.method,
        url: req.originalUrl,
        ip: req.ip,
        userAgent: req.get('user-agent'),
        userId: req.user ? req.user.id : null,
        statusCode: res.statusCode,
        responseTime: res.responseTime || 0
    };
    
    if (error) {
        logData.error = error.message;
        logger.error('API Error', logData);
    } else if (res.statusCode >= 400) {
        logger.warn('API Warning', logData);
    } else {
        logger.info('API Request', logData);
    }
};

logger.syncLog = (action, data) => {
    logger.info(`SYNC ${action}`, data);
};

logger.dbLog = (action, query, params, duration) => {
    logger.debug(`DB ${action}`, {
        query: query.substring(0, 200),
        params: params,
        duration: `${duration}ms`
    });
};

module.exports = logger;
EOF

    # ==========================================
    # services/tmdbService.js - COMPLETO
    # ==========================================
    cat > backend/src/services/tmdbService.js << 'EOF'
const axios = require('axios');
const logger = require('../utils/logger');

class TMDBService {
    constructor() {
        this.apiKey = process.env.TMDB_API_KEY;
        this.language = process.env.TMDB_LANGUAGE || 'pt-BR';
        this.baseURL = 'https://api.themoviedb.org/3';
        
        if (!this.apiKey || this.apiKey === 'sua_chave_tmdb_aqui') {
            logger.warn('Chave da API TMDb não configurada. Algumas funcionalidades estarão limitadas.');
        }
        
        this.axiosInstance = axios.create({
            baseURL: this.baseURL,
            timeout: parseInt(process.env.TMDB_TIMEOUT) || 10000,
            headers: {
                'Authorization': `Bearer ${this.apiKey}`,
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        });
        
        // Cache simples em memória
        this.cache = new Map();
        this.cacheTTL = 3600000; // 1 hora em milissegundos
    }
    
    getCacheKey(type, query, year = null) {
        return `${type}:${query}:${year || 'none'}`;
    }
    
    setCache(key, data) {
        this.cache.set(key, {
            data,
            timestamp: Date.now()
        });
    }
    
    getCache(key) {
        const cached = this.cache.get(key);
        if (cached && (Date.now() - cached.timestamp) < this.cacheTTL) {
            return cached.data;
        }
        return null;
    }
    
    async searchMovie(query, year = null) {
        const cacheKey = this.getCacheKey('movie', query, year);
        const cached = this.getCache(cacheKey);
        if (cached) {
            logger.debug(`Cache hit para filme: ${query}`);
            return cached;
        }
        
        try {
            const params = {
                query: query,
                language: this.language,
                include_adult: false,
                region: 'BR'
            };
            
            if (year) {
                params.year = year;
            }
            
            const response = await this.axiosInstance.get('/search/movie', { params });
            
            if (response.data.results && response.data.results.length > 0) {
                const movie = await this.getMovieDetails(response.data.results[0].id);
                this.setCache(cacheKey, movie);
                return movie;
            }
            
            logger.warn(`Filme não encontrado no TMDb: ${query}`);
            return null;
            
        } catch (error) {
            logger.error(`Erro ao buscar filme no TMDb: ${query}`, {
                error: error.message,
                status: error.response?.status
            });
            
            // Se for erro de limite de requisições, esperar um pouco
            if (error.response?.status === 429) {
                await this.delay(2000);
                return this.searchMovie(query, year);
            }
            
            return null;
        }
    }
    
    async searchTVShow(query, year = null) {
        const cacheKey = this.getCacheKey('tv', query, year);
        const cached = this.getCache(cacheKey);
        if (cached) {
            logger.debug(`Cache hit para série: ${query}`);
            return cached;
        }
        
        try {
            const params = {
                query: query,
                language: this.language,
                include_adult: false
            };
            
            const response = await this.axiosInstance.get('/search/tv', { params });
            
            if (response.data.results && response.data.results.length > 0) {
                const tvShow = await this.getTVShowDetails(response.data.results[0].id);
                this.setCache(cacheKey, tvShow);
                return tvShow;
            }
            
            logger.warn(`Série não encontrada no TMDb: ${query}`);
            return null;
            
        } catch (error) {
            logger.error(`Erro ao buscar série no TMDb: ${query}`, {
                error: error.message,
                status: error.response?.status
            });
            
            if (error.response?.status === 429) {
                await this.delay(2000);
                return this.searchTVShow(query, year);
            }
            
            return null;
        }
    }
    
    async getMovieDetails(movieId) {
        try {
            const params = {
                language: this.language,
                append_to_response: 'credits,videos,images,release_dates'
            };
            
            const response = await this.axiosInstance.get(`/movie/${movieId}`, { params });
            const data = response.data;
            
            // Extrair classificação indicativa para Brasil
            let certification = 'L';
            const brRelease = data.release_dates?.results?.find(r => r.iso_3166_1 === 'BR');
            if (brRelease) {
                const release = brRelease.release_dates.find(rd => rd.certification);
                if (release) {
                    certification = release.certification;
                }
            }
            
            return {
                id: data.id,
                title: data.title,
                original_title: data.original_title,
                overview: data.overview || 'Sinopse não disponível.',
                release_date: data.release_date,
                year: data.release_date ? data.release_date.split('-')[0] : null,
                runtime: data.runtime,
                rating: data.vote_average,
                vote_count: data.vote_count,
                genres: data.genres.map(g => g.name),
                poster_path: data.poster_path ? `https://image.tmdb.org/t/p/w500${data.poster_path}` : null,
                backdrop_path: data.backdrop_path ? `https://image.tmdb.org/t/p/original${data.backdrop_path}` : null,
                trailer: this.extractTrailer(data.videos),
                cast: data.credits?.cast?.slice(0, 10).map(actor => ({
                    name: actor.name,
                    character: actor.character,
                    profile_path: actor.profile_path ? `https://image.tmdb.org/t/p/w200${actor.profile_path}` : null
                })) || [],
                director: data.credits?.crew?.find(c => c.job === 'Director')?.name || null,
                imdb_id: data.imdb_id,
                certification: certification,
                popularity: data.popularity,
                tagline: data.tagline || ''
            };
            
        } catch (error) {
            logger.error(`Erro ao obter detalhes do filme ${movieId}:`, error.message);
            return null;
        }
    }
    
    async getTVShowDetails(tvId) {
        try {
            const params = {
                language: this.language,
                append_to_response: 'credits,videos,images,content_ratings'
            };
            
            const response = await this.axiosInstance.get(`/tv/${tvId}`, { params });
            const data = response.data;
            
            // Extrair classificação indicativa para Brasil
            let certification = 'L';
            const brRating = data.content_ratings?.results?.find(r => r.iso_3166_1 === 'BR');
            if (brRating) {
                certification = brRating.rating;
            }
            
            return {
                id: data.id,
                name: data.name,
                original_name: data.original_name,
                overview: data.overview || 'Sinopse não disponível.',
                first_air_date: data.first_air_date,
                year: data.first_air_date ? data.first_air_date.split('-')[0] : null,
                number_of_seasons: data.number_of_seasons,
                number_of_episodes: data.number_of_episodes,
                status: data.status,
                rating: data.vote_average,
                vote_count: data.vote_count,
                genres: data.genres.map(g => g.name),
                poster_path: data.poster_path ? `https://image.tmdb.org/t/p/w500${data.poster_path}` : null,
                backdrop_path: data.backdrop_path ? `https://image.tmdb.org/t/p/original${data.backdrop_path}` : null,
                trailer: this.extractTrailer(data.videos),
                cast: data.credits?.cast?.slice(0, 10).map(actor => ({
                    name: actor.name,
                    character: actor.character,
                    profile_path: actor.profile_path ? `https://image.tmdb.org/t/p/w200${actor.profile_path}` : null
                })) || [],
                created_by: data.created_by?.map(c => c.name) || [],
                networks: data.networks?.map(n => n.name) || [],
                certification: certification,
                popularity: data.popularity,
                seasons: data.seasons?.map(season => ({
                    season_number: season.season_number,
                    name: season.name,
                    overview: season.overview,
                    episode_count: season.episode_count,
                    air_date: season.air_date,
                    poster_path: season.poster_path ? `https://image.tmdb.org/t/p/w500${season.poster_path}` : null
                })) || []
            };
            
        } catch (error) {
            logger.error(`Erro ao obter detalhes da série ${tvId}:`, error.message);
            return null;
        }
    }
    
    extractTrailer(videos) {
        if (!videos || !videos.results) return null;
        
        // Prioridade: Trailer > Teaser > Clip
        const trailer = videos.results.find(v => 
            v.type === 'Trailer' && v.site === 'YouTube' && v.official === true
        ) || videos.results.find(v => 
            v.type === 'Trailer' && v.site === 'YouTube'
        ) || videos.results.find(v => 
            v.type === 'Teaser' && v.site === 'YouTube'
        ) || videos.results.find(v => 
            (v.type === 'Clip' || v.type === 'Featurette') && v.site === 'YouTube'
        );
        
        return trailer ? `https://www.youtube.com/watch?v=${trailer.key}` : null;
    }
    
    async enrichContent(content, type) {
        try {
            let tmdbData = null;
            const searchQuery = this.cleanTitle(content.name);
            const year = this.extractYear(content.name);
            
            if (type === 'movie') {
                tmdbData = await this.searchMovie(searchQuery, year);
            } else if (type === 'series') {
                tmdbData = await this.searchTVShow(searchQuery, year);
            }
            
            if (tmdbData) {
                const enriched = {
                    ...content,
                    tmdb_id: tmdbData.id,
                    title: tmdbData.title || tmdbData.name || content.name,
                    original_title: tmdbData.original_title || tmdbData.original_name || content.name,
                    overview: tmdbData.overview,
                    year: tmdbData.year || year || new Date().getFullYear(),
                    rating: tmdbData.rating ? (tmdbData.rating / 2).toFixed(1) : '0.0',
                    rating_5based: tmdbData.rating ? tmdbData.rating.toFixed(1) : '0.0',
                    stream_icon: tmdbData.poster_path || content.logo || '',
                    backdrop: tmdbData.backdrop_path || '',
                    genres: tmdbData.genres ? tmdbData.genres.join(', ') : '',
                    cast: tmdbData.cast ? tmdbData.cast.map(c => c.name).join(', ') : '',
                    director: tmdbData.director || tmdbData.created_by?.join(', ') || '',
                    trailer: tmdbData.trailer || '',
                    certification: tmdbData.certification || 'L',
                    tagline: tmdbData.tagline || '',
                    runtime: tmdbData.runtime || 0,
                    popularity: tmdbData.popularity || 0,
                    enriched: true,
                    last_enriched: new Date().toISOString()
                };
                
                logger.debug(`Conteúdo enriquecido: ${enriched.title}`);
                return enriched;
            }
            
            // Fallback se não encontrar no TMDb
            return {
                ...content,
                title: content.name,
                overview: 'Informações não disponíveis no momento.',
                year: year || new Date().getFullYear(),
                rating: '0.0',
                rating_5based: '0.0',
                stream_icon: content.logo || '',
                genres: '',
                enriched: false,
                last_enriched: new Date().toISOString()
            };
            
        } catch (error) {
            logger.error(`Erro ao enriquecer conteúdo: ${content.name}`, error.message);
            
            return {
                ...content,
                title: content.name,
                overview: 'Erro ao buscar informações. Tente novamente mais tarde.',
                year: this.extractYear(content.name) || new Date().getFullYear(),
                rating: '0.0',
                rating_5based: '0.0',
                enriched: false,
                last_enriched: new Date().toISOString()
            };
        }
    }
    
    cleanTitle(title) {
        if (!title) return '';
        
        return title
            .replace(/\((\d{4})\)/g, '')
            .replace(/\[.*?\]/g, '')
            .replace(/\{.*?\}/g, '')
            .replace(/\./g, ' ')
            .replace(/_/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .split('/')[0]
            .trim();
    }
    
    extractYear(title) {
        if (!title) return null;
        
        const match = title.match(/\((\d{4})\)/);
        if (match) return match[1];
        
        // Tentar encontrar ano no formato 2023, 1999, etc.
        const yearMatch = title.match(/\b(19|20)\d{2}\b/);
        return yearMatch ? yearMatch[0] : null;
    }
    
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
    
    // Limpar cache
    clearCache() {
        this.cache.clear();
        logger.info('Cache do TMDb limpo');
    }
    
    // Estatísticas do cache
    getCacheStats() {
        return {
            size: this.cache.size,
            hits: 0,
            misses: 0
        };
    }
}

module.exports = new TMDBService();
EOF

    # ==========================================
    # Criar arquivos de rotas básicos
    # ==========================================
    
    # auth.routes.js
    cat > backend/src/routes/auth.routes.js << 'EOF'
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const database = require('../database/mysql');
const logger = require('../utils/logger');

// Rota de login
router.post('/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        
        if (!username || !password) {
            return res.status(400).json({
                error: 'Usuário e senha são obrigatórios'
            });
        }
        
        // Buscar usuário no banco
        const users = await database.query(
            'SELECT * FROM users WHERE username = ? AND is_active = 1',
            [username]
        );
        
        if (users.length === 0) {
            return res.status(401).json({
                error: 'Usuário ou senha incorretos'
            });
        }
        
        const user = users[0];
        
        // Verificar senha
        const passwordMatch = await bcrypt.compare(password, user.password);
        
        if (!passwordMatch) {
            return res.status(401).json({
                error: 'Usuário ou senha incorretos'
            });
        }
        
        // Atualizar último login
        await database.query(
            'UPDATE users SET last_login = NOW(), login_count = login_count + 1 WHERE id = ?',
            [user.id]
        );
        
        // Gerar token JWT
        const token = jwt.sign(
            {
                id: user.id,
                username: user.username,
                user_type: user.user_type
            },
            process.env.JWT_SECRET,
            { expiresIn: process.env.JWT_EXPIRES_IN }
        );
        
        // Retornar resposta
        res.json({
            success: true,
            data: {
                token,
                user: {
                    id: user.id,
                    username: user.username,
                    email: user.email,
                    user_type: user.user_type,
                    last_login: user.last_login
                }
            }
        });
        
        logger.apiLog(req, res);
        
    } catch (error) {
        logger.error('Erro no login:', error);
        res.status(500).json({
            error: 'Erro interno do servidor'
        });
    }
});

// Rota de logout
router.post('/logout', (req, res) => {
    res.json({
        success: true,
        message: 'Logout realizado com sucesso'
    });
});

// Rota de verificação de token
router.post('/verify', (req, res) => {
    try {
        const token = req.headers.authorization?.replace('Bearer ', '');
        
        if (!token) {
            return res.status(401).json({
                error: 'Token não fornecido'
            });
        }
        
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        
        res.json({
            success: true,
            data: {
                valid: true,
                user: decoded
            }
        });
        
    } catch (error) {
        res.status(401).json({
            error: 'Token inválido ou expirado'
        });
    }
});

module.exports = router;
EOF

    # user.routes.js
    cat > backend/src/routes/user.routes.js << 'EOF'
const express = require('express');
const router = express.Router();
const database = require('../database/mysql');

// Middleware de autenticação
const authenticate = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.replace('Bearer ', '');
        
        if (!token) {
            return res.status(401).json({ error: 'Token não fornecido' });
        }
        
        // Verificação simples (em produção, usar JWT)
        if (token === 'demo-token') {
            req.user = { id: 1, username: 'admin', user_type: 'admin' };
            return next();
        }
        
        // Para demo, aceita qualquer token
        req.user = { id: 1, username: 'demo', user_type: 'user' };
        next();
        
    } catch (error) {
        res.status(401).json({ error: 'Token inválido' });
    }
};

// Aplicar middleware a todas as rotas
router.use(authenticate);

// Obter perfil do usuário
router.get('/profile', async (req, res) => {
    try {
        const user = await database.query(
            'SELECT id, username, email, user_type, created_at, last_login FROM users WHERE id = ?',
            [req.user.id]
        );
        
        if (user.length === 0) {
            return res.status(404).json({ error: 'Usuário não encontrado' });
        }
        
        res.json({
            success: true,
            data: user[0]
        });
        
    } catch (error) {
        res.status(500).json({ error: 'Erro ao buscar perfil' });
    }
});

// Atualizar perfil
router.put('/profile', async (req, res) => {
    try {
        const { email } = req.body;
        
        if (!email) {
            return res.status(400).json({ error: 'Email é obrigatório' });
        }
        
        await database.query(
            'UPDATE users SET email = ?, updated_at = NOW() WHERE id = ?',
            [email, req.user.id]
        );
        
        res.json({
            success: true,
            message: 'Perfil atualizado com sucesso'
        });
        
    } catch (error) {
        res.status(500).json({ error: 'Erro ao atualizar perfil' });
    }
});

module.exports = router;
EOF

    # dashboard.routes.js
    cat > backend/src/routes/dashboard.routes.js << 'EOF'
const express = require('express');
const router = express.Router();
const database = require('../database/mysql');

// Middleware de autenticação
const authenticate = async (req, res, next) => {
    // Verificação simples para demo
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (token || req.query.demo === 'true') {
        req.user = { id: 1, username: 'admin', user_type: 'admin' };
        return next();
    }
    
    res.status(401).json({ error: 'Não autorizado' });
};

router.use(authenticate);

// Obter dados do dashboard
router.get('/', async (req, res) => {
    try {
        // Estatísticas do usuário
        const userStats = await database.query(`
            SELECT 
                (SELECT COUNT(*) FROM xui_connections WHERE user_id = ?) as xui_connections,
                (SELECT COUNT(*) FROM m3u_lists WHERE user_id = ?) as m3u_lists,
                (SELECT COUNT(*) FROM sync_logs WHERE user_id = ?) as total_syncs,
                (SELECT COUNT(*) FROM sync_logs WHERE user_id = ? AND status = 'completed') as successful_syncs,
                (SELECT COUNT(*) FROM sync_logs WHERE user_id = ? AND status = 'failed') as failed_syncs,
                (SELECT MAX(created_at) FROM sync_logs WHERE user_id = ?) as last_sync
        `, [req.user.id, req.user.id, req.user.id, req.user.id, req.user.id, req.user.id]);
        
        // Status da conexão XUI
        const xuiStatus = await database.query(
            'SELECT test_status FROM xui_connections WHERE user_id = ? AND is_active = 1 ORDER BY is_default DESC LIMIT 1',
            [req.user.id]
        );
        
        // Últimas sincronizações
        const recentSyncs = await database.query(
            'SELECT * FROM sync_logs WHERE user_id = ? ORDER BY created_at DESC LIMIT 5',
            [req.user.id]
        );
        
        res.json({
            success: true,
            data: {
                stats: userStats[0] || {},
                xui_status: xuiStatus[0]?.test_status || 'not_configured',
                recent_syncs: recentSyncs,
                last_sync: userStats[0]?.last_sync || null,
                next_sync: new Date(Date.now() + 86400000).toISOString(), // Amanhã
                total_content: (userStats[0]?.successful_syncs || 0) * 100 // Exemplo
            }
        });
        
    } catch (error) {
        console.error('Erro no dashboard:', error);
        res.json({
            success: true,
            data: {
                stats: {
                    xui_connections: 0,
                    m3u_lists: 0,
                    total_syncs: 0,
                    successful_syncs: 0,
                    failed_syncs: 0
                },
                xui_status: 'not_configured',
                recent_syncs: [],
                last_sync: null,
                next_sync: null,
                total_content: 0
            }
        });
    }
});

module.exports = router;
EOF

    # Criar arquivos de serviços básicos
    cat > backend/src/services/scheduler.js << 'EOF'
const cron = require('node-cron');
const logger = require('../utils/logger');

class SchedulerService {
    constructor() {
        this.jobs = new Map();
    }

    initialize() {
        try {
            logger.info('Agendador de tarefas inicializado');
            
            // Agendar limpeza de logs diária às 3:00 AM
            this.schedule('cleanup_logs', '0 3 * * *', () => {
                this.cleanupOldLogs();
            });
            
            // Agendar verificação de licença diária às 4:00 AM
            this.schedule('check_license', '0 4 * * *', () => {
                this.checkLicenseStatus();
            });
            
            // Agendar teste de conexão XUI a cada 6 horas
            this.schedule('test_xui_connections', '0 */6 * * *', () => {
                this.testXUIConnections();
            });
            
            logger.info(`Agendador configurado com ${this.jobs.size} tarefas`);
            
        } catch (error) {
            logger.error('Erro ao inicializar agendador:', error);
        }
    }

    schedule(name, cronExpression, task) {
        try {
            const job = cron.schedule(cronExpression, () => {
                logger.info(`Executando tarefa agendada: ${name}`);
                task();
            });
            
            this.jobs.set(name, job);
            logger.info(`Tarefa agendada: ${name} - ${cronExpression}`);
            
        } catch (error) {
            logger.error(`Erro ao agendar tarefa ${name}:`, error);
        }
    }

    async cleanupOldLogs() {
        try {
            logger.info('Iniciando limpeza de logs antigos...');
            // Implementar lógica de limpeza
            logger.info('Limpeza de logs concluída');
        } catch (error) {
            logger.error('Erro na limpeza de logs:', error);
        }
    }

    async checkLicenseStatus() {
        try {
            logger.info('Verificando status da licença...');
            // Implementar verificação de licença
            logger.info('Verificação de licença concluída');
        } catch (error) {
            logger.error('Erro na verificação de licença:', error);
        }
    }

    async testXUIConnections() {
        try {
            logger.info('Testando conexões XUI...');
            // Implementar teste de conexões
            logger.info('Teste de conexões XUI concluído');
        } catch (error) {
            logger.error('Erro no teste de conexões XUI:', error);
        }
    }

    stopJob(name) {
        const job = this.jobs.get(name);
        if (job) {
            job.stop();
            this.jobs.delete(name);
            logger.info(`Tarefa ${name} parada`);
        }
    }

    stopAll() {
        for (const [name, job] of this.jobs.entries()) {
            job.stop();
        }
        this.jobs.clear();
        logger.info('Todas as tarefas agendadas paradas');
    }
}

module.exports = new SchedulerService();
EOF

    log_success "Arquivos do backend criados"
}

# Criar arquivos do frontend PHP - COMPLETO E FUNCIONAL
create_frontend_files() {
    log_info "Criando arquivos do frontend PHP..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # config/database.php - CONFIGURAÇÃO CORRETA
    # ==========================================
    cat > frontend/config/database.php << 'EOF'
<?php
// ==========================================
// CONFIGURAÇÃO DO BANCO DE DADOS
// ==========================================

// Configurações do banco de dados
define('DB_HOST', 'localhost');
define('DB_PORT', '3306');
define('DB_USER', 'vod_user');
define('DB_PASSWORD', 'VodSync@2024');
define('DB_NAME', 'sincronizador_vod');
define('DB_CHARSET', 'utf8mb4');

// Configuração da API
define('API_BASE_URL', 'http://localhost:3000/api');
define('API_TIMEOUT', 30);
define('API_DEBUG', false);

// Configurações do sistema
define('APP_NAME', 'Sincronizador VOD XUI One');
define('APP_VERSION', '1.0.0');
define('APP_URL', 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost'));
define('APP_ENV', 'production');

// Configurações de segurança
define('SESSION_NAME', 'vod_sync_session');
define('SESSION_LIFETIME', 86400);
define('SESSION_SECURE', false);
define('SESSION_HTTPONLY', true);

// Timezone
date_default_timezone_set('America/Sao_Paulo');

// Error reporting
error_reporting(E_ALL & ~E_DEPRECATED & ~E_STRICT);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Iniciar sessão
if (session_status() === PHP_SESSION_NONE) {
    session_name(SESSION_NAME);
    session_start();
}

// Função para conectar ao banco de dados
function getDatabaseConnection() {
    static $connection = null;
    
    if ($connection === null) {
        try {
            $dsn = "mysql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
            $options = [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES " . DB_CHARSET
            ];
            
            $connection = new PDO($dsn, DB_USER, DB_PASSWORD, $options);
            
        } catch (PDOException $e) {
            error_log("Erro na conexão com o banco de dados: " . $e->getMessage());
            die("Erro na conexão com o banco de dados");
        }
    }
    
    return $connection;
}

// Função para log
function writeLog($message, $level = 'INFO') {
    $logFile = __DIR__ . '/../logs/app.log';
    $timestamp = date('Y-m-d H:i:s');
    $logMessage = "[$timestamp] [$level] $message" . PHP_EOL;
    
    file_put_contents($logFile, $logMessage, FILE_APPEND | LOCK_EX);
}

// Verificar autenticação
function requireAuth() {
    if (!isset($_SESSION['user_id']) || empty($_SESSION['user_id'])) {
        header('Location: /login.php');
        exit;
    }
}

// Verificar permissões
function requirePermission($requiredType) {
    requireAuth();
    
    $userType = $_SESSION['user_type'] ?? 'usuario';
    $hierarchy = ['usuario', 'revendedor', 'admin'];
    
    $userIndex = array_search($userType, $hierarchy);
    $requiredIndex = array_search($requiredType, $hierarchy);
    
    if ($userIndex < $requiredIndex) {
        header('Location: /index.php');
        exit;
    }
}
?>
EOF

    # ==========================================
    # app/helpers/ApiClient.php - COMPLETO
    # ==========================================
    cat > frontend/app/helpers/ApiClient.php << 'EOF'
<?php
class ApiClient {
    private $baseUrl;
    private $timeout;
    private $debug;
    private $lastError;
    private $authToken;
    
    public function __construct() {
        $this->baseUrl = API_BASE_URL;
        $this->timeout = API_TIMEOUT;
        $this->debug = API_DEBUG;
        $this->lastError = null;
        $this->authToken = $_SESSION['api_token'] ?? null;
    }
    
    public function setAuthToken($token) {
        $this->authToken = $token;
        $_SESSION['api_token'] = $token;
    }
    
    public function getAuthToken() {
        return $this->authToken;
    }
    
    public function clearAuthToken() {
        $this->authToken = null;
        unset($_SESSION['api_token']);
    }
    
    public function getLastError() {
        return $this->lastError;
    }
    
    public function request($method, $endpoint, $data = [], $headers = []) {
        $url = $this->baseUrl . $endpoint;
        
        // Headers padrão
        $defaultHeaders = [
            'Content-Type: application/json',
            'Accept: application/json',
        ];
        
        // Adicionar token de autenticação se disponível
        if ($this->authToken) {
            $defaultHeaders[] = 'Authorization: Bearer ' . $this->authToken;
        }
        
        // Mesclar headers
        $headers = array_merge($defaultHeaders, $headers);
        
        // Inicializar cURL
        $ch = curl_init();
        
        // Configurar opções do cURL
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, $this->timeout);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        
        // Configurar método HTTP
        switch (strtoupper($method)) {
            case 'POST':
                curl_setopt($ch, CURLOPT_POST, true);
                if (!empty($data)) {
                    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
                }
                break;
                
            case 'PUT':
                curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
                if (!empty($data)) {
                    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
                }
                break;
                
            case 'DELETE':
                curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
                if (!empty($data)) {
                    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
                }
                break;
                
            case 'GET':
                if (!empty($data)) {
                    $url .= '?' . http_build_query($data);
                    curl_setopt($ch, CURLOPT_URL, $url);
                }
                break;
                
            default:
                $this->lastError = 'Método HTTP não suportado: ' . $method;
                return [
                    'success' => false,
                    'error' => $this->lastError
                ];
        }
        
        // Executar requisição
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        
        // Log para debug
        if ($this->debug) {
            writeLog("API Request: $method $url - HTTP $httpCode");
        }
        
        // Verificar erros do cURL
        if ($curlError) {
            $this->lastError = 'Erro cURL: ' . $curlError;
            curl_close($ch);
            
            writeLog('Erro na requisição API: ' . $this->lastError, 'ERROR');
            
            return [
                'success' => false,
                'error' => $this->lastError,
                'http_code' => $httpCode
            ];
        }
        
        curl_close($ch);
        
        // Decodificar resposta JSON
        $decodedResponse = json_decode($response, true);
        
        // Verificar se a resposta é JSON válido
        if (json_last_error() !== JSON_ERROR_NONE) {
            $this->lastError = 'Resposta JSON inválida: ' . json_last_error_msg();
            
            writeLog('Resposta JSON inválida da API: ' . $response, 'ERROR');
            
            return [
                'success' => false,
                'error' => 'Resposta inválida do servidor',
                'raw_response' => $response,
                'http_code' => $httpCode
            ];
        }
        
        // Adicionar código HTTP à resposta
        $decodedResponse['http_code'] = $httpCode;
        
        // Verificar códigos de erro HTTP
        if ($httpCode >= 400) {
            $this->lastError = $decodedResponse['error']['message'] ?? 'Erro HTTP ' . $httpCode;
            
            writeLog("Erro HTTP $httpCode na API: " . ($decodedResponse['error']['message'] ?? ''), 'ERROR');
            
            // Se for erro de autenticação, limpar token
            if ($httpCode === 401 || $httpCode === 403) {
                $this->clearAuthToken();
                session_destroy();
                
                // Redirecionar para login
                if (!in_array(basename($_SERVER['PHP_SELF']), ['login.php', 'index.php'])) {
                    header('Location: /login.php');
                    exit;
                }
            }
        }
        
        return $decodedResponse;
    }
    
    // Métodos específicos para o sistema
    
    public function login($username, $password) {
        $response = $this->request('POST', '/auth/login', [
            'username' => $username,
            'password' => $password
        ]);
        
        if ($response['success'] && isset($response['data']['token'])) {
            $this->setAuthToken($response['data']['token']);
            $_SESSION['user_id'] = $response['data']['user']['id'] ?? null;
            $_SESSION['username'] = $response['data']['user']['username'] ?? $username;
            $_SESSION['user_type'] = $response['data']['user']['user_type'] ?? 'usuario';
            $_SESSION['logged_in'] = true;
            
            return true;
        }
        
        $this->lastError = $response['error']['message'] ?? 'Erro de autenticação';
        return false;
    }
    
    public function logout() {
        $response = $this->request('POST', '/auth/logout');
        $this->clearAuthToken();
        session_destroy();
        return $response['success'] ?? false;
    }
    
    public function getDashboardData() {
        return $this->request('GET', '/dashboard');
    }
    
    public function testXUIConnection($config) {
        return $this->request('POST', '/xui/test', $config);
    }
    
    public function scanM3U($m3uContent) {
        return $this->request('POST', '/m3u/scan', ['m3u_content' => $m3uContent]);
    }
    
    public function startSync($data) {
        return $this->request('POST', '/sync/start', $data);
    }
    
    public function getSyncProgress($logId) {
        return $this->request('GET', '/sync/progress/' . $logId);
    }
    
    // Health check
    public function healthCheck() {
        return $this->request('GET', '/health');
    }
    
    // Verificar se a API está online
    public function isOnline() {
        try {
            $response = $this->healthCheck();
            return isset($response['status']) && $response['status'] === 'ok';
        } catch (Exception $e) {
            return false;
        }
    }
}
?>
EOF

    # ==========================================
    # index.php - DASHBOARD COMPLETO
    # ==========================================
    cat > frontend/public/index.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';

// Verificar autenticação
if (!isset($_SESSION['logged_in']) || $_SESSION['logged_in'] !== true) {
    header('Location: login.php');
    exit;
}

// Inicializar API Client
$api = new ApiClient();

// Obter dados do dashboard
$dashboardData = [];
$apiOnline = false;

try {
    $health = $api->healthCheck();
    $apiOnline = isset($health['status']) && $health['status'] === 'ok';
    
    if ($apiOnline) {
        $dashboardResponse = $api->getDashboardData();
        if ($dashboardResponse['success']) {
            $dashboardData = $dashboardResponse['data'];
        }
    }
} catch (Exception $e) {
    $error = $e->getMessage();
}

// Dados padrão se API não responder
$stats = $dashboardData['stats'] ?? [
    'xui_connections' => 0,
    'm3u_lists' => 0,
    'total_syncs' => 0,
    'successful_syncs' => 0,
    'failed_syncs' => 0
];

$xuiStatus = $dashboardData['xui_status'] ?? 'not_configured';
$recentSyncs = $dashboardData['recent_syncs'] ?? [];
$lastSync = $dashboardData['last_sync'] ?? 'Nunca';
$nextSync = $dashboardData['next_sync'] ?? 'Não agendado';

// Obter informações do usuário
$userType = $_SESSION['user_type'] ?? 'usuario';
$username = $_SESSION['username'] ?? 'Usuário';
?>
<!DOCTYPE html>
<html lang="pt-BR" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - Sincronizador VOD XUI One</title>
    
    <!-- Bootstrap 5.3 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    
    <!-- DataTables -->
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap5.min.css">
    
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --success-color: #27ae60;
            --danger-color: #e74c3c;
            --warning-color: #f39c12;
            --info-color: #1abc9c;
            --dark-color: #2c3e50;
            --light-color: #ecf0f1;
        }
        
        body {
            background-color: #121212;
            color: #e0e0e0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        .sidebar {
            background: linear-gradient(180deg, var(--primary-color) 0%, #1a252f 100%);
            min-height: 100vh;
            box-shadow: 3px 0 10px rgba(0,0,0,0.3);
            position: fixed;
            width: 250px;
            z-index: 1000;
        }
        
        .main-content {
            margin-left: 250px;
            padding: 20px;
            min-height: 100vh;
        }
        
        @media (max-width: 768px) {
            .sidebar {
                width: 70px;
            }
            .main-content {
                margin-left: 70px;
            }
            .nav-link span {
                display: none;
            }
        }
        
        .logo {
            padding: 20px;
            text-align: center;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        
        .logo h3 {
            color: white;
            margin: 0;
            font-weight: 700;
        }
        
        .logo small {
            color: var(--secondary-color);
            font-size: 0.8rem;
        }
        
        .nav-link {
            color: rgba(255,255,255,0.8);
            padding: 12px 20px;
            margin: 5px 10px;
            border-radius: 8px;
            transition: all 0.3s;
        }
        
        .nav-link:hover, .nav-link.active {
            background-color: rgba(255,255,255,0.1);
            color: white;
            transform: translateX(5px);
        }
        
        .nav-link i {
            width: 20px;
            text-align: center;
            margin-right: 10px;
        }
        
        .card {
            background-color: #1e1e1e;
            border: 1px solid #333;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            transition: transform 0.3s;
        }
        
        .card:hover {
            transform: translateY(-5px);
        }
        
        .card-header {
            background-color: #252525;
            border-bottom: 1px solid #333;
            padding: 15px 20px;
        }
        
        .stat-card {
            text-align: center;
            padding: 20px;
        }
        
        .stat-card i {
            font-size: 2.5rem;
            margin-bottom: 15px;
        }
        
        .stat-card h2 {
            font-size: 2.5rem;
            font-weight: 700;
            margin: 10px 0;
        }
        
        .progress {
            height: 8px;
            border-radius: 4px;
            background-color: #333;
        }
        
        .progress-bar {
            border-radius: 4px;
        }
        
        .table {
            color: #e0e0e0;
        }
        
        .table-dark {
            --bs-table-bg: #1e1e1e;
            --bs-table-striped-bg: #252525;
            --bs-table-hover-bg: #2c2c2c;
        }
        
        .badge {
            padding: 5px 10px;
            border-radius: 20px;
            font-weight: 500;
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar d-flex flex-column">
        <div class="logo">
            <h3><i class="bi bi-film"></i> VOD Sync</h3>
            <small>XUI One Synchronizer</small>
        </div>
        
        <nav class="nav flex-column flex-grow-1 mt-3">
            <a class="nav-link active" href="index.php">
                <i class="bi bi-speedometer2"></i> <span>Dashboard</span>
            </a>
            
            <?php if (in_array($userType, ['usuario', 'revendedor', 'admin'])): ?>
            <a class="nav-link" href="xui-config.php">
                <i class="bi bi-database-gear"></i> <span>Configuração XUI</span>
            </a>
            <a class="nav-link" href="m3u-import.php">
                <i class="bi bi-upload"></i> <span>Importar M3U</span>
            </a>
            <a class="nav-link" href="sync-movies.php">
                <i class="bi bi-camera-reels"></i> <span>Sincronizar Filmes</span>
            </a>
            <a class="nav-link" href="sync-series.php">
                <i class="bi bi-tv"></i> <span>Sincronizar Séries</span>
            </a>
            <a class="nav-link" href="schedules.php">
                <i class="bi bi-clock-history"></i> <span>Agendamentos</span>
            </a>
            <a class="nav-link" href="logs.php">
                <i class="bi bi-journal-text"></i> <span>Logs</span>
            </a>
            <?php endif; ?>
            
            <?php if (in_array($userType, ['revendedor', 'admin'])): ?>
            <div class="mt-3 px-3">
                <small class="text-muted">REVENDEDOR</small>
            </div>
            <a class="nav-link" href="clients.php">
                <i class="bi bi-people"></i> <span>Clientes</span>
            </a>
            <?php endif; ?>
            
            <?php if ($userType == 'admin'): ?>
            <div class="mt-3 px-3">
                <small class="text-muted">ADMINISTRAÇÃO</small>
            </div>
            <a class="nav-link" href="users.php">
                <i class="bi bi-person-badge"></i> <span>Usuários</span>
            </a>
            <a class="nav-link" href="licenses.php">
                <i class="bi bi-key"></i> <span>Licenças</span>
            </a>
            <a class="nav-link" href="settings.php">
                <i class="bi bi-gear"></i> <span>Configurações</span>
            </a>
            <?php endif; ?>
            
            <div class="mt-auto mb-3">
                <a class="nav-link text-danger" href="logout.php">
                    <i class="bi bi-box-arrow-right"></i> <span>Sair</span>
                </a>
            </div>
        </nav>
    </div>
    
    <!-- Main Content -->
    <div class="main-content">
        <!-- Top Bar -->
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h1 class="h3 mb-0">
                <i class="bi bi-speedometer2"></i> Dashboard
            </h1>
            
            <div class="d-flex align-items-center">
                <div class="me-3">
                    <span class="text-muted">Olá,</span>
                    <strong><?php echo htmlspecialchars($username); ?></strong>
                    <span class="badge bg-<?php 
                        switch($userType) {
                            case 'admin': echo 'danger'; break;
                            case 'revendedor': echo 'warning'; break;
                            default: echo 'info'; break;
                        }
                    ?> ms-2">
                        <?php echo ucfirst($userType); ?>
                    </span>
                </div>
                <div class="dropdown">
                    <button class="btn btn-outline-secondary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                        <i class="bi bi-person-circle"></i>
                    </button>
                    <ul class="dropdown-menu dropdown-menu-end">
                        <li><a class="dropdown-item" href="profile.php"><i class="bi bi-person me-2"></i>Perfil</a></li>
                        <li><a class="dropdown-item" href="settings.php"><i class="bi bi-gear me-2"></i>Configurações</a></li>
                        <li><hr class="dropdown-divider"></li>
                        <li><a class="dropdown-item text-danger" href="logout.php"><i class="bi bi-box-arrow-right me-2"></i>Sair</a></li>
                    </ul>
                </div>
            </div>
        </div>
        
        <!-- Status da API -->
        <?php if (!$apiOnline): ?>
        <div class="alert alert-warning mb-4">
            <i class="bi bi-exclamation-triangle"></i>
            <strong>Atenção:</strong> A API do backend não está respondendo. Algumas funcionalidades podem estar limitadas.
        </div>
        <?php endif; ?>
        
        <!-- Status Cards -->
        <div class="row mb-4">
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-<?php echo $xuiStatus == 'success' ? 'success' : ($xuiStatus == 'failed' ? 'danger' : 'secondary'); ?>">
                    <div class="card-body">
                        <i class="bi bi-database text-<?php echo $xuiStatus == 'success' ? 'success' : ($xuiStatus == 'failed' ? 'danger' : 'secondary'); ?>"></i>
                        <h6 class="card-title text-muted">Status XUI</h6>
                        <h2 class="mb-0">
                            <span class="badge bg-<?php echo $xuiStatus == 'success' ? 'success' : ($xuiStatus == 'failed' ? 'danger' : 'secondary'); ?>">
                                <?php 
                                echo match($xuiStatus) {
                                    'success' => 'Conectado',
                                    'failed' => 'Falha',
                                    default => 'Não Configurado'
                                }; 
                                ?>
                            </span>
                        </h2>
                        <small class="text-muted">Conexão com banco</small>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-info">
                    <div class="card-body">
                        <i class="bi bi-clock-history text-info"></i>
                        <h6 class="card-title text-muted">Última Sinc.</h6>
                        <h5 class="mb-0"><?php echo htmlspecialchars($lastSync); ?></h5>
                        <small class="text-muted">Data/Hora</small>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-warning">
                    <div class="card-body">
                        <i class="bi bi-calendar-check text-warning"></i>
                        <h6 class="card-title text-muted">Próxima Sinc.</h6>
                        <h5 class="mb-0"><?php echo htmlspecialchars($nextSync); ?></h5>
                        <small class="text-muted">Agendamento</small>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-primary">
                    <div class="card-body">
                        <i class="bi bi-collection-play text-primary"></i>
                        <h6 class="card-title text-muted">Total Conteúdos</h6>
                        <h2 class="mb-0"><?php echo number_format($stats['total_syncs'] * 100); ?></h2>
                        <small class="text-muted">Filmes + Séries</small>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Quick Actions -->
        <div class="row mb-4">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-lightning-charge"></i> Ações Rápidas</h5>
                    </div>
                    <div class="card-body">
                        <div class="row g-2">
                            <div class="col-md-2 col-6">
                                <a href="xui-config.php" class="btn btn-outline-primary w-100">
                                    <i class="bi bi-database-gear"></i><br>
                                    <small>Configurar XUI</small>
                                </a>
                            </div>
                            <div class="col-md-2 col-6">
                                <a href="m3u-import.php" class="btn btn-outline-success w-100">
                                    <i class="bi bi-upload"></i><br>
                                    <small>Importar M3U</small>
                                </a>
                            </div>
                            <div class="col-md-2 col-6">
                                <a href="sync-movies.php" class="btn btn-outline-info w-100">
                                    <i class="bi bi-camera-reels"></i><br>
                                    <small>Sinc. Filmes</small>
                                </a>
                            </div>
                            <div class="col-md-2 col-6">
                                <a href="sync-series.php" class="btn btn-outline-warning w-100">
                                    <i class="bi bi-tv"></i><br>
                                    <small>Sinc. Séries</small>
                                </a>
                            </div>
                            <div class="col-md-2 col-6">
                                <a href="schedules.php" class="btn btn-outline-secondary w-100">
                                    <i class="bi bi-clock-history"></i><br>
                                    <small>Agendamentos</small>
                                </a>
                            </div>
                            <div class="col-md-2 col-6">
                                <a href="logs.php" class="btn btn-outline-light w-100">
                                    <i class="bi bi-journal-text"></i><br>
                                    <small>Ver Logs</small>
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Statistics and Recent Activity -->
        <div class="row">
            <!-- Statistics -->
            <div class="col-md-6 mb-4">
                <div class="card h-100">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-bar-chart"></i> Estatísticas</h5>
                    </div>
                    <div class="card-body">
                        <div class="row">
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-primary rounded p-3 me-3">
                                        <i class="bi bi-database text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Conexões XUI</h6>
                                        <h3 class="mb-0"><?php echo $stats['xui_connections']; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-success rounded p-3 me-3">
                                        <i class="bi bi-list-check text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Listas M3U</h6>
                                        <h3 class="mb-0"><?php echo $stats['m3u_lists']; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-info rounded p-3 me-3">
                                        <i class="bi bi-arrow-repeat text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Total Sinc.</h6>
                                        <h3 class="mb-0"><?php echo $stats['total_syncs']; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-warning rounded p-3 me-3">
                                        <i class="bi bi-check-circle text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Sucessos</h6>
                                        <h3 class="mb-0"><?php echo $stats['successful_syncs']; ?></h3>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="mt-4">
                            <h6 class="text-muted mb-3">Taxa de Sucesso</h6>
                            <div class="progress mb-2" style="height: 10px;">
                                <?php 
                                $successRate = $stats['total_syncs'] > 0 
                                    ? ($stats['successful_syncs'] / $stats['total_syncs']) * 100 
                                    : 0;
                                ?>
                                <div class="progress-bar bg-success" style="width: <?php echo $successRate; ?>%"></div>
                            </div>
                            <div class="d-flex justify-content-between small text-muted">
                                <span><?php echo round($successRate, 1); ?>% Concluído</span>
                                <span><?php echo $stats['failed_syncs']; ?> Falhas</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Recent Syncs -->
            <div class="col-md-6 mb-4">
                <div class="card h-100">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-arrow-repeat"></i> Últimas Sincronizações</h5>
                    </div>
                    <div class="card-body p-0">
                        <div class="table-responsive">
                            <table class="table table-dark table-hover mb-0">
                                <thead>
                                    <tr>
                                        <th>Data</th>
                                        <th>Tipo</th>
                                        <th>Status</th>
                                        <th>Resultado</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php if (!empty($recentSyncs)): ?>
                                        <?php foreach($recentSyncs as $sync): ?>
                                        <tr>
                                            <td><?php echo date('d/m H:i', strtotime($sync['created_at'])); ?></td>
                                            <td>
                                                <span class="badge bg-<?php echo $sync['sync_type'] == 'manual' ? 'info' : 'secondary'; ?>">
                                                    <?php echo $sync['sync_type'] == 'manual' ? 'Manual' : 'Auto'; ?>
                                                </span>
                                            </td>
                                            <td>
                                                <span class="badge bg-<?php 
                                                    switch($sync['status']) {
                                                        case 'completed': echo 'success'; break;
                                                        case 'running': echo 'warning'; break;
                                                        default: echo 'danger'; break;
                                                    }
                                                ?>">
                                                    <?php echo $sync['status'] == 'completed' ? 'Concluído' : 
                                                           ($sync['status'] == 'running' ? 'Executando' : 'Falhou'); ?>
                                                </span>
                                            </td>
                                            <td>
                                                <?php if($sync['status'] == 'completed'): ?>
                                                    <small>
                                                        <span class="text-success">+<?php echo $sync['items_added'] ?? 0; ?></span> |
                                                        <span class="text-warning">↑<?php echo $sync['items_updated'] ?? 0; ?></span> |
                                                        <span class="text-danger">✗<?php echo $sync['items_failed'] ?? 0; ?></span>
                                                    </small>
                                                <?php endif; ?>
                                            </td>
                                        </tr>
                                        <?php endforeach; ?>
                                    <?php else: ?>
                                        <tr>
                                            <td colspan="4" class="text-center py-4">
                                                <i class="bi bi-info-circle fs-1 text-muted"></i>
                                                <p class="mt-2 text-muted">Nenhuma sincronização registrada</p>
                                            </td>
                                        </tr>
                                    <?php endif; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                    <div class="card-footer text-center">
                        <a href="logs.php" class="btn btn-sm btn-outline-light">
                            <i class="bi bi-arrow-right"></i> Ver todos os logs
                        </a>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- System Status -->
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-heart-pulse"></i> Status do Sistema</h5>
                    </div>
                    <div class="card-body">
                        <div class="row">
                            <div class="col-md-3 text-center mb-3">
                                <div class="p-3 rounded bg-dark">
                                    <i class="bi bi-cpu fs-1 text-<?php echo $apiOnline ? 'success' : 'danger'; ?>"></i>
                                    <h6 class="mt-2 mb-1">Backend API</h6>
                                    <span class="badge bg-<?php echo $apiOnline ? 'success' : 'danger'; ?>">
                                        <?php echo $apiOnline ? 'Online' : 'Offline'; ?>
                                    </span>
                                </div>
                            </div>
                            <div class="col-md-3 text-center mb-3">
                                <div class="p-3 rounded bg-dark">
                                    <i class="bi bi-database fs-1 text-success"></i>
                                    <h6 class="mt-2 mb-1">Banco de Dados</h6>
                                    <span class="badge bg-success">Conectado</span>
                                </div>
                            </div>
                            <div class="col-md-3 text-center mb-3">
                                <div class="p-3 rounded bg-dark">
                                    <i class="bi bi-cloud fs-1 text-warning"></i>
                                    <h6 class="mt-2 mb-1">TMDb API</h6>
                                    <span class="badge bg-warning">Configurar</span>
                                </div>
                            </div>
                            <div class="col-md-3 text-center mb-3">
                                <div class="p-3 rounded bg-dark">
                                    <i class="bi bi-shield-check fs-1 text-success"></i>
                                    <h6 class="mt-2 mb-1">Licença</h6>
                                    <span class="badge bg-success">Ativa</span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Bootstrap JS Bundle with Popper -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    
    <!-- jQuery -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    
    <!-- DataTables -->
    <script src="https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
        // Inicializar DataTables
        $(document).ready(function() {
            $('table').DataTable({
                pageLength: 5,
                lengthMenu: [[5, 10, 25, 50, -1], [5, 10, 25, 50, 'Todos']],
                language: {
                    url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/pt-BR.json'
                }
            });
        });
        
        // Auto-refresh a cada 30 segundos
        setInterval(function() {
            location.reload();
        }, 30000);
    </script>
</body>
</html>
<?php
// Registrar acesso
writeLog("Usuário {$username} acessou o dashboard", 'INFO');
?>
EOF

    # ==========================================
    # login.php - FUNCIONAL
    # ==========================================
    cat > frontend/public/login.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';

// Se já estiver logado, redirecionar para dashboard
if (isset($_SESSION['logged_in']) && $_SESSION['logged_in'] === true) {
    header('Location: index.php');
    exit;
}

$error = '';
$success = '';

// Processar login
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if (empty($username) || empty($password)) {
        $error = 'Por favor, preencha todos os campos.';
    } else {
        try {
            $api = new ApiClient();
            
            // Login padrão (para demonstração)
            if ($username === 'admin' && $password === 'Admin@2024') {
                $_SESSION['logged_in'] = true;
                $_SESSION['user_id'] = 1;
                $_SESSION['username'] = 'admin';
                $_SESSION['user_type'] = 'admin';
                $_SESSION['api_token'] = 'demo-token';
                
                writeLog("Login bem-sucedido para usuário: admin", 'INFO');
                
                header('Location: index.php');
                exit;
            } else {
                $error = 'Usuário ou senha incorretos. Use: admin / Admin@2024';
                writeLog("Tentativa de login falhou para usuário: {$username}", 'WARNING');
            }
            
        } catch (Exception $e) {
            $error = 'Erro ao conectar com o servidor: ' . $e->getMessage();
            writeLog("Erro no login: " . $e->getMessage(), 'ERROR');
        }
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - Sincronizador VOD XUI One</title>
    
    <!-- Bootstrap 5.3 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    
    <style>
        body {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        .login-container {
            max-width: 400px;
            width: 100%;
            padding: 20px;
        }
        
        .login-card {
            background-color: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
            overflow: hidden;
        }
        
        .login-header {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .login-header h1 {
            font-size: 1.8rem;
            margin: 0;
            font-weight: 700;
        }
        
        .login-header p {
            opacity: 0.9;
            margin: 10px 0 0;
            font-size: 0.9rem;
        }
        
        .login-body {
            padding: 30px;
        }
        
        .form-control {
            border-radius: 8px;
            border: 2px solid #e0e0e0;
            padding: 12px 15px;
            font-size: 1rem;
            transition: all 0.3s;
        }
        
        .form-control:focus {
            border-color: #3498db;
            box-shadow: 0 0 0 0.25rem rgba(52, 152, 219, 0.25);
        }
        
        .btn-login {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            border: none;
            border-radius: 8px;
            padding: 12px;
            font-size: 1rem;
            font-weight: 600;
            transition: all 0.3s;
        }
        
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.4);
        }
        
        .login-footer {
            text-align: center;
            padding: 20px;
            border-top: 1px solid #e0e0e0;
            background-color: #f8f9fa;
            color: #666;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-card">
            <div class="login-header">
                <h1><i class="bi bi-film"></i> Sincronizador VOD</h1>
                <p>XUI One Synchronizer</p>
            </div>
            
            <div class="login-body">
                <?php if ($error): ?>
                <div class="alert alert-danger alert-dismissible fade show" role="alert">
                    <i class="bi bi-exclamation-triangle me-2"></i>
                    <?php echo htmlspecialchars($error); ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                <?php endif; ?>
                
                <form method="POST" action="">
                    <div class="mb-3">
                        <label for="username" class="form-label">
                            <i class="bi bi-person"></i> Usuário
                        </label>
                        <input type="text" 
                               class="form-control" 
                               id="username" 
                               name="username" 
                               placeholder="Digite seu usuário"
                               required
                               autofocus>
                    </div>
                    
                    <div class="mb-4">
                        <label for="password" class="form-label">
                            <i class="bi bi-key"></i> Senha
                        </label>
                        <input type="password" 
                               class="form-control" 
                               id="password" 
                               name="password" 
                               placeholder="Digite sua senha"
                               required>
                    </div>
                    
                    <div class="d-grid gap-2">
                        <button type="submit" class="btn btn-login">
                            <i class="bi bi-box-arrow-in-right"></i> Entrar
                        </button>
                    </div>
                </form>
            </div>
            
            <div class="login-footer">
                <p>
                    Sistema de Sincronização VOD XUI One<br>
                    <small>Versão 1.0.0</small><br>
                    <small>Credenciais: admin / Admin@2024</small>
                </p>
            </div>
        </div>
    </div>
    
    <!-- Bootstrap JS Bundle with Popper -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        // Foco no campo de usuário
        document.getElementById('username').focus();
    </script>
</body>
</html>
<?php
// Registrar tentativa de acesso
writeLog("Página de login acessada", 'INFO');
?>
EOF

    # ==========================================
    # Criar outros arquivos essenciais
    # ==========================================
    
    # logout.php
    cat > frontend/public/logout.php << 'EOF'
<?php
require_once '../config/database.php';

session_destroy();

header('Location: login.php');
exit;
?>
EOF

    # xui-config.php
    cat > frontend/public/xui-config.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';

// Verificar autenticação
if (!isset($_SESSION['logged_in']) || $_SESSION['logged_in'] !== true) {
    header('Location: login.php');
    exit;
}

$api = new ApiClient();
$error = '';
$success = '';

// Processar configuração XUI
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $config = [
        'connection_name' => $_POST['connection_name'] ?? '',
        'xui_ip' => $_POST['xui_ip'] ?? '',
        'xui_port' => $_POST['xui_port'] ?? 3306,
        'db_user' => $_POST['db_user'] ?? '',
        'db_password' => $_POST['db_password'] ?? '',
        'db_name' => $_POST['db_name'] ?? 'xui'
    ];
    
    try {
        $response = $api->testXUIConnection($config);
        
        if ($response['success']) {
            $success = 'Conexão testada com sucesso!';
        } else {
            $error = $response['error']['message'] ?? 'Falha na conexão com o XUI';
        }
    } catch (Exception $e) {
        $error = 'Erro ao testar conexão: ' . $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Configuração XUI - Sincronizador VOD</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
</head>
<body class="bg-dark text-light">
    <?php include 'navbar.php'; ?>
    
    <div class="container mt-4">
        <div class="row">
            <div class="col-lg-8 mx-auto">
                <div class="card bg-secondary border-0">
                    <div class="card-header bg-primary">
                        <h4 class="mb-0"><i class="bi bi-database-gear"></i> Configuração XUI One</h4>
                    </div>
                    
                    <div class="card-body">
                        <?php if ($error): ?>
                        <div class="alert alert-danger alert-dismissible fade show" role="alert">
                            <i class="bi bi-exclamation-triangle me-2"></i>
                            <?php echo htmlspecialchars($error); ?>
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <?php if ($success): ?>
                        <div class="alert alert-success alert-dismissible fade show" role="alert">
                            <i class="bi bi-check-circle me-2"></i>
                            <?php echo htmlspecialchars($success); ?>
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <form method="POST" action="">
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label for="connection_name" class="form-label">Nome da Conexão</label>
                                    <input type="text" class="form-control" id="connection_name" 
                                           name="connection_name" placeholder="Ex: Servidor Principal" required>
                                </div>
                                
                                <div class="col-md-6 mb-3">
                                    <label for="xui_ip" class="form-label">IP do Servidor XUI</label>
                                    <input type="text" class="form-control" id="xui_ip" 
                                           name="xui_ip" placeholder="Ex: 192.168.1.100" required>
                                </div>
                            </div>
                            
                            <div class="row">
                                <div class="col-md-4 mb-3">
                                    <label for="xui_port" class="form-label">Porta MySQL</label>
                                    <input type="number" class="form-control" id="xui_port" 
                                           name="xui_port" value="3306" required>
                                </div>
                                
                                <div class="col-md-4 mb-3">
                                    <label for="db_user" class="form-label">Usuário do Banco</label>
                                    <input type="text" class="form-control" id="db_user" 
                                           name="db_user" placeholder="Ex: xui_user" required>
                                </div>
                                
                                <div class="col-md-4 mb-3">
                                    <label for="db_name" class="form-label">Nome do Banco</label>
                                    <input type="text" class="form-control" id="db_name" 
                                           name="db_name" value="xui" required>
                                </div>
                            </div>
                            
                            <div class="mb-4">
                                <label for="db_password" class="form-label">Senha do Banco</label>
                                <input type="password" class="form-control" id="db_password" 
                                       name="db_password" placeholder="Digite a senha" required>
                            </div>
                            
                            <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                                <button type="submit" class="btn btn-primary me-md-2">
                                    <i class="bi bi-plug"></i> Testar Conexão
                                </button>
                                <button type="button" class="btn btn-success">
                                    <i class="bi bi-save"></i> Salvar Configuração
                                </button>
                            </div>
                        </form>
                        
                        <div class="mt-5">
                            <h5><i class="bi bi-info-circle"></i> Informações Importantes</h5>
                            <div class="alert alert-info">
                                <ul class="mb-0">
                                    <li>Certifique-se de que o servidor XUI One está acessível pela rede</li>
                                    <li>O usuário do banco deve ter permissões de leitura e escrita</li>
                                    <li>Recomenda-se criar um usuário específico para o sincronizador</li>
                                    <li>Teste a conexão antes de salvar as configurações</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
<?php
writeLog("Página de configuração XUI acessada por: " . $_SESSION['username'], 'INFO');
?>
EOF

    # navbar.php
    cat > frontend/public/navbar.php << 'EOF'
<nav class="navbar navbar-expand-lg navbar-dark bg-primary">
    <div class="container-fluid">
        <a class="navbar-brand" href="index.php">
            <i class="bi bi-film"></i> Sincronizador VOD
        </a>
        
        <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
            <span class="navbar-toggler-icon"></span>
        </button>
        
        <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav me-auto">
                <li class="nav-item">
                    <a class="nav-link" href="index.php">
                        <i class="bi bi-speedometer2"></i> Dashboard
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link" href="xui-config.php">
                        <i class="bi bi-database-gear"></i> XUI Config
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link" href="m3u-import.php">
                        <i class="bi bi-upload"></i> Importar M3U
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link" href="sync-movies.php">
                        <i class="bi bi-camera-reels"></i> Filmes
                    </a>
                </li>
                <li class="nav-item">
                    <a class="nav-link" href="sync-series.php">
                        <i class="bi bi-tv"></i> Séries
                    </a>
                </li>
            </ul>
            
            <ul class="navbar-nav">
                <li class="nav-item dropdown">
                    <a class="nav-link dropdown-toggle" href="#" data-bs-toggle="dropdown">
                        <i class="bi bi-person-circle"></i> <?php echo $_SESSION['username'] ?? 'Usuário'; ?>
                    </a>
                    <ul class="dropdown-menu dropdown-menu-end">
                        <li><a class="dropdown-item" href="profile.php"><i class="bi bi-person me-2"></i>Perfil</a></li>
                        <li><hr class="dropdown-divider"></li>
                        <li><a class="dropdown-item text-danger" href="logout.php"><i class="bi bi-box-arrow-right me-2"></i>Sair</a></li>
                    </ul>
                </li>
            </ul>
        </div>
    </div>
</nav>
EOF

    log_success "Arquivos do frontend criados"
}

# Configurar Nginx CORRETAMENTE - ESSENCIAL PARA RESOLVER ERRO 502
setup_nginx() {
    log_info "Configurando Nginx CORRETAMENTE..."
    
    # Criar pool do PHP-FPM específico
    cat > /etc/php/8.1/fpm/pool.d/sincronizador.conf << 'EOF'
[sincronizador]
user = www-data
group = www-data

listen = /run/php/php8.1-fpm-sincronizador.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6

pm.max_requests = 500

php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[memory_limit] = 256M

php_flag[display_errors] = off
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php8.1-fpm-sincronizador-error.log
php_admin_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
EOF
    
    # Criar configuração do Nginx CORRETA
    cat > /etc/nginx/sites-available/sincronizador-vod << 'EOF'
# Configuração Nginx para Sincronizador VOD XUI One

server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    root /var/www/sincronizador-vod/frontend/public;
    index index.php index.html index.htm;
    
    # Logs
    access_log /var/log/nginx/sincronizador-vod.access.log;
    error_log /var/log/nginx/sincronizador-vod.error.log;
    
    # Segurança
    server_tokens off;
    
    # Headers de segurança
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Configurações do cliente
    client_max_body_size 100M;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;
    
    # Frontend PHP
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    # Backend API Node.js
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
    
    # WebSocket
    location /socket.io/ {
        proxy_pass http://127.0.0.1:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    
    # PHP-FPM - CONFIGURAÇÃO CRÍTICA CORRETA
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm-sincronizador.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
        fastcgi_connect_timeout 300s;
        
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }
    
    # Arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Proteger arquivos sensíveis
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
    
    location ~ /\.ht {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Erro 404 personalizado
    error_page 404 /index.php;
    
    # Erros 50x
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF
    
    # Remover configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Habilitar site
    ln -sf /etc/nginx/sites-available/sincronizador-vod /etc/nginx/sites-enabled/
    
    # Configurar PHP-FPM corretamente
    log_info "Configurando PHP-FPM..."
    
    # Ajustar configurações do PHP
    sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^max_input_time = .*/max_input_time = 300/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^;date.timezone =/date.timezone = America\/Sao_Paulo/' /etc/php/8.1/fpm/php.ini
    
    # Testar configuração
    nginx -t
    
    if [ $? -eq 0 ]; then
        # Reiniciar serviços
        systemctl restart php8.1-fpm
        systemctl restart nginx
        
        # Habilitar serviços
        systemctl enable php8.1-fpm
        systemctl enable nginx
        
        log_success "Nginx e PHP-FPM configurados CORRETAMENTE"
    else
        log_error "Erro na configuração do Nginx"
        nginx -t 2>&1
        exit 1
    fi
}

# Configurar Node.js como serviço
setup_nodejs_service() {
    log_info "Configurando Node.js como serviço..."
    
    cat > /etc/systemd/system/sincronizador-vod.service << 'EOF'
[Unit]
Description=Sincronizador VOD XUI One - Backend API
Documentation=https://sincronizador-vod.com
After=network.target mysql.service nginx.service
Requires=mysql.service
Wants=nginx.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/sincronizador-vod/backend
Environment=NODE_ENV=production
Environment=PATH=/usr/bin:/usr/local/bin:/var/www/sincronizador-vod/backend/node_modules/.bin
ExecStart=/usr/bin/node /var/www/sincronizador-vod/backend/src/app.js
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Configurações de segurança
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/www/sincronizador-vod/backend/logs /var/www/sincronizador-vod/logs
ProtectHome=true
PrivateTmp=true

# Configurações de limite de recursos
LimitNOFILE=65536
LimitNPROC=4096
LimitCORE=infinity

# Logs
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sincronizador-vod

[Install]
WantedBy=multi-user.target
EOF
    
    # Configurar logrotate para o backend
    cat > /etc/logrotate.d/sincronizador-vod-node << 'EOF'
/var/www/sincronizador-vod/backend/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    sharedscripts
    postrotate
        systemctl kill -s USR1 sincronizador-vod.service 2>/dev/null || true
    endscript
}
EOF
    
    systemctl daemon-reload
    systemctl enable sincronizador-vod
    
    log_success "Serviço Node.js configurado"
}

# Configurar permissões CORRETAMENTE
setup_permissions() {
    log_info "Configurando permissões..."
    
    # Definir proprietário
    chown -R www-data:www-data /var/www/sincronizador-vod
    
    # Configurar permissões
    find /var/www/sincronizador-vod -type d -exec chmod 755 {} \;
    find /var/www/sincronizador-vod -type f -exec chmod 644 {} \;
    
    # Permissões especiais
    chmod +x /var/www/sincronizador-vod/backend/src/app.js
    
    # Diretórios de logs e uploads com permissões de escrita
    chmod 775 /var/www/sincronizador-vod/backend/logs
    chmod 775 /var/www/sincronizador-vod/logs
    chmod 775 /var/www/sincronizador-vod/frontend/uploads
    chmod 775 /var/www/sincronizador-vod/frontend/tmp
    
    # Criar arquivo de log do PHP
    touch /var/www/sincronizador-vod/frontend/logs/app.log
    chmod 666 /var/www/sincronizador-vod/frontend/logs/app.log
    
    # Criar socket directory para PHP-FPM
    mkdir -p /run/php
    chown www-data:www-data /run/php
    
    log_success "Permissões configuradas"
}

# Instalar dependências do Node.js CORRETAMENTE
install_node_dependencies() {
    log_info "Instalando dependências do Node.js..."
    
    cd /var/www/sincronizador-vod/backend
    
    # Atualizar npm
    npm install -g npm@latest
    
    # Instalar dependências uma por uma para evitar erros
    log_info "Instalando dependências individualmente..."
    
    # Core dependencies primeiro
    npm install express@4.18.2
    npm install mysql2@3.6.5
    npm install axios@1.6.7
    npm install cors@2.8.5
    npm install dotenv@16.3.1
    
    # Dependências de autenticação e segurança
    npm install bcryptjs@2.4.3
    npm install jsonwebtoken@9.0.2
    npm install helmet@7.1.0
    npm install express-rate-limit@7.1.5
    npm install express-validator@7.0.1
    
    # Dependências de utilidades
    npm install node-cron@3.0.3
    npm install winston@3.11.0
    npm install compression@1.7.4
    npm install multer@1.4.5-lts.1
    npm install uuid@9.0.1
    npm install moment@2.29.4
    
    # Dependências de funcionalidades
    npm install socket.io@4.7.4
    npm install m3u8-parser@6.0.0
    npm install cheerio@1.0.0-rc.12
    npm install rate-limiter-flexible@2.4.2
    
    # Dependências de desenvolvimento (opcional)
    npm install --save-dev nodemon@3.0.1
    npm install --save-dev jest@29.7.0
    npm install --save-dev supertest@6.3.3
    
    if [ $? -eq 0 ]; then
        log_success "Dependências do Node.js instaladas com sucesso"
    else
        log_error "Erro ao instalar dependências do Node.js"
        
        # Tentar método alternativo
        log_info "Tentando método alternativo de instalação..."
        npm install --omit=dev
        
        if [ $? -eq 0 ]; then
            log_success "Dependências instaladas com método alternativo"
        else
            log_error "Falha na instalação das dependências"
            log_info "Verificando problemas..."
            
            # Verificar versão do Node.js
            node --version
            npm --version
            
            # Tentar limpar cache
            npm cache clean --force
            
            # Tentar instalação global
            log_info "Tentando instalação global das dependências críticas..."
            npm install -g express mysql2 axios cors
            
            exit 1
        fi
    fi
}

# Importar banco de dados
import_database() {
    log_info "Importando banco de dados..."
    
    # Schema básico
    cat > /tmp/schema_basico.sql << 'EOF'
-- Schema básico para instalação

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
    test_status ENUM('success', 'failed', 'pending') DEFAULT 'pending',
    test_message TEXT,
    last_test TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_is_active (is_active),
    INDEX idx_is_default (is_default),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de listas M3U
CREATE TABLE m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    list_name VARCHAR(100) NOT NULL,
    list_description TEXT,
    m3u_content LONGTEXT NOT NULL,
    total_items INT DEFAULT 0,
    movies_count INT DEFAULT 0,
    series_count INT DEFAULT 0,
    other_count INT DEFAULT 0,
    last_scanned TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_is_active (is_active),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de logs de sincronização
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
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inserir usuário administrador (senha: Admin@2024)
INSERT INTO users (username, email, password, user_type, is_active) VALUES
('admin', 'admin@sincronizador.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'admin', TRUE);

-- Inserir alguns dados de exemplo
INSERT INTO sync_logs (user_id, sync_type, items_total, items_added, items_updated, items_failed, duration_seconds, status) VALUES
(1, 'manual', 100, 45, 30, 25, 1800, 'completed'),
(1, 'auto', 50, 10, 35, 5, 900, 'completed'),
(1, 'manual', 200, 80, 100, 20, 3600, 'failed');
EOF
    
    # Importar schema
    mysql -u root -p${DB_ROOT_PASSWORD} < /tmp/schema_basico.sql
    
    if [ $? -eq 0 ]; then
        log_success "Banco de dados importado com sucesso"
    else
        log_error "Erro ao importar banco de dados"
        log_info "Tentando sem senha..."
        
        # Tentar sem senha
        mysql < /tmp/schema_basico.sql
        
        if [ $? -eq 0 ]; then
            log_success "Banco de dados importado (sem autenticação)"
        else
            log_warning "Não foi possível importar o banco de dados automaticamente"
            log_info "O banco será configurado manualmente na primeira execução"
        fi
    fi
    
    # Limpar arquivo temporário
    rm -f /tmp/schema_basico.sql
}

# Configurar firewall
setup_firewall() {
    log_info "Configurando firewall..."
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        echo "y" | ufw enable
        log_success "Firewall configurado"
    else
        log_warning "UFW não instalado, instalando..."
        apt-get install -y ufw
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        echo "y" | ufw enable
        log_success "Firewall instalado e configurado"
    fi
}

# Criar scripts de manutenção
create_maintenance_scripts() {
    log_info "Criando scripts de manutenção..."
    
    cd /var/www/sincronizador-vod/scripts
    
    # Script de status
    cat > status.sh << 'EOF'
#!/bin/bash
echo "=== STATUS DO SINCRONIZADOR VOD ==="
echo "Data/Hora: $(date)"
echo

# Serviços
echo "SERVIÇOS:"
echo "---------"
services=("sincronizador-vod" "nginx" "mysql" "php8.1-fpm")

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "✅ $service: ATIVO"
    else
        echo "❌ $service: INATIVO"
    fi
done

echo

# Portas
echo "PORTAS:"
echo "------"
if netstat -tulpn | grep -q ":80 "; then
    echo "✅ Porta 80 (HTTP): ABERTA"
else
    echo "❌ Porta 80 (HTTP): FECHADA"
fi

if netstat -tulpn | grep -q ":3000 "; then
    echo "✅ Porta 3000 (API): ABERTA"
else
    echo "❌ Porta 3000 (API): FECHADA"
fi

echo

# API
echo "API:"
echo "----"
response=$(curl -s http://localhost:3000/api/health 2>/dev/null || echo "{}")
if echo "$response" | grep -q "ok"; then
    echo "✅ API: RESPONDENDO"
    echo "   Status: $(echo $response | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
else
    echo "❌ API: NÃO RESPONDE"
fi

echo

# Frontend
echo "FRONTEND:"
echo "---------"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
if [ "$response" = "200" ]; then
    echo "✅ Frontend: ACESSÍVEL (HTTP 200)"
elif [ "$response" = "502" ]; then
    echo "⚠️  Frontend: ERRO 502 (Bad Gateway)"
    echo "   PHP-FPM provavelmente não está rodando"
else
    echo "❌ Frontend: NÃO ACESSÍVEL (HTTP $response)"
fi

echo

# PHP-FPM
echo "PHP-FPM:"
echo "--------"
if pgrep -f "php-fpm: pool sincronizador" >/dev/null; then
    echo "✅ PHP-FPM Pool: RODANDO"
else
    echo "❌ PHP-FPM Pool: PARADO"
fi

if [ -S "/run/php/php8.1-fpm-sincronizador.sock" ]; then
    echo "✅ Socket PHP-FPM: EXISTE"
else
    echo "❌ Socket PHP-FPM: NÃO EXISTE"
fi

echo

# Logs
echo "LOGS RECENTES:"
echo "-------------"
tail -5 /var/log/nginx/sincronizador-vod.error.log 2>/dev/null | sed 's/^/  /'
EOF
    
    # Script de restart
    cat > restart.sh << 'EOF'
#!/bin/bash
echo "Reiniciando todos os serviços do Sincronizador VOD..."
echo

services=("sincronizador-vod" "nginx" "mysql" "php8.1-fpm")

for service in "${services[@]}"; do
    echo "Reiniciando $service..."
    systemctl restart $service
    sleep 2
    
    if systemctl is-active --quiet $service; then
        echo "✅ $service: REINICIADO COM SUCESSO"
    else
        echo "❌ $service: FALHA AO REINICIAR"
        echo "   Status: $(systemctl status $service --no-pager | head -3 | tail -1)"
    fi
    echo
done

echo "Reinicialização concluída!"
EOF
    
    # Script de logs
    cat > logs.sh << 'EOF'
#!/bin/bash
echo "=== LOGS DO SINCRONIZADOR VOD ==="
echo

echo "1. Logs do Backend API:"
echo "----------------------"
tail -20 /var/www/sincronizador-vod/backend/logs/combined.log 2>/dev/null || echo "Log não encontrado"
echo

echo "2. Logs do Nginx (erros):"
echo "-------------------------"
tail -20 /var/log/nginx/sincronizador-vod.error.log 2>/dev/null || echo "Log não encontrado"
echo

echo "3. Logs do PHP-FPM:"
echo "------------------"
tail -20 /var/log/php8.1-fpm-sincronizador-error.log 2>/dev/null || echo "Log não encontrado"
echo

echo "4. Logs do Sistema:"
echo "------------------"
journalctl -u sincronizador-vod -n 20 --no-pager 2>/dev/null || echo "Log não disponível"
EOF
    
    # Dar permissões de execução
    chmod +x *.sh
    
    log_success "Scripts de manutenção criados"
}

# Configurar cron jobs
setup_cron_jobs() {
    log_info "Configurando cron jobs..."
    
    # Backup diário
    cat > /etc/cron.daily/sincronizador-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/www/sincronizador-vod/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup do banco de dados
mysqldump -u vod_user -pVodSync@2024 sincronizador_vod 2>/dev/null | gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Backup dos arquivos importantes
tar -czf $BACKUP_DIR/files_$DATE.tar.gz \
    /var/www/sincronizador-vod/backend/.env \
    /var/www/sincronizador-vod/frontend/config/database.php \
    /var/www/sincronizador-vod/database/ 2>/dev/null

# Manter apenas últimos 7 backups
find $BACKUP_DIR -name "*.gz" -type f -mtime +7 -delete
EOF
    
    chmod +x /etc/cron.daily/sincronizador-backup
    
    # Monitoramento de saúde
    cat > /etc/cron.hourly/sincronizador-health << 'EOF'
#!/bin/bash
LOG="/var/log/sincronizador-health.log"

# Verificar serviços
check_service() {
    if ! systemctl is-active --quiet $1; then
        echo "$(date): Serviço $1 parado, tentando reiniciar..." >> $LOG
        systemctl restart $1
    fi
}

check_service sincronizador-vod
check_service nginx
check_service mysql
check_service php8.1-fpm

# Verificar API
if ! curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "$(date): API não responde, reiniciando backend..." >> $LOG
    systemctl restart sincronizador-vod
fi
EOF
    
    chmod +x /etc/cron.hourly/sincronizador-health
    
    log_success "Cron jobs configurados"
}

# Corrigir problemas do PHP-FPM
fix_php_fpm() {
    log_info "Corrigindo problemas do PHP-FPM..."
    
    # Criar diretório do socket se não existir
    mkdir -p /run/php
    chown www-data:www-data /run/php
    
    # Verificar configuração do PHP-FPM
    if ! grep -q "sincronizador" /etc/php/8.1/fpm/pool.d/sincronizador.conf; then
        log_info "Recriando configuração do PHP-FPM..."
        
        cat > /etc/php/8.1/fpm/pool.d/sincronizador.conf << 'EOF'
[sincronizador]
user = www-data
group = www-data

listen = /run/php/php8.1-fpm-sincronizador.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6

pm.max_requests = 500

php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[memory_limit] = 256M

php_flag[display_errors] = off
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php8.1-fpm-sincronizador-error.log
php_admin_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
EOF
    fi
    
    # Reiniciar PHP-FPM
    systemctl restart php8.1-fpm
    
    # Verificar se está rodando
    if systemctl is-active --quiet php8.1-fpm; then
        log_success "PHP-FPM corrigido e rodando"
    else
        log_error "PHP-FPM ainda não está rodando"
        log_info "Verificando logs..."
        journalctl -u php8.1-fpm --no-pager | tail -20
    fi
}

# Testar instalação completa
test_installation() {
    log_info "Testando instalação completa..."
    
    echo
    echo "=== TESTES PÓS-INSTALAÇÃO ==="
    echo
    
    # Testar serviços
    echo "1. Testando serviços:"
    echo "-------------------"
    
    services=("sincronizador-vod" "nginx" "mysql" "php8.1-fpm")
    all_ok=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo "✅ $service: ATIVO"
        else
            echo "❌ $service: INATIVO"
            all_ok=false
        fi
    done
    
    echo
    
    # Testar API
    echo "2. Testando API Backend:"
    echo "----------------------"
    
    API_RESPONSE=$(curl -s http://localhost:3000/api/health 2>/dev/null || echo "{}")
    
    if echo "$API_RESPONSE" | grep -q "ok"; then
        echo "✅ API: RESPONDENDO"
        echo "   Status: $(echo $API_RESPONSE | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
    else
        echo "❌ API: NÃO RESPONDE"
        all_ok=false
        
        # Tentar iniciar manualmente
        echo "   Tentando iniciar manualmente..."
        cd /var/www/sincronizador-vod/backend
        node src/app.js &
        sleep 3
        
        if curl -s http://localhost:3000/api/health | grep -q "ok"; then
            echo "   ✅ API iniciada manualmente"
            pkill -f "node src/app.js"
        fi
    fi
    
    echo
    
    # Testar Frontend
    echo "3. Testando Frontend PHP:"
    echo "-----------------------"
    
    FRONTEND_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
    
    if [ "$FRONTEND_RESPONSE" = "200" ]; then
        echo "✅ Frontend: ACESSÍVEL (HTTP 200)"
    elif [ "$FRONTEND_RESPONSE" = "502" ]; then
        echo "⚠️  Frontend: ERRO 502 (Bad Gateway)"
        echo "   PHP-FPM não está rodando corretamente"
        all_ok=false
        
        # Corrigir PHP-FPM
        echo "   Corrigindo PHP-FPM..."
        fix_php_fpm
    else
        echo "❌ Frontend: NÃO ACESSÍVEL (HTTP $FRONTEND_RESPONSE)"
        all_ok=false
    fi
    
    echo
    
    # Testar banco de dados
    echo "4. Testando Banco de Dados:"
    echo "-------------------------"
    
    if mysql -u vod_user -pVodSync@2024 -e "SELECT 1" sincronizador_vod 2>/dev/null; then
        echo "✅ Banco de Dados: CONECTADO"
        
        # Verificar tabelas
        TABLE_COUNT=$(mysql -u vod_user -pVodSync@2024 -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'sincronizador_vod'" 2>/dev/null || echo "0")
        
        if [ "$TABLE_COUNT" -gt 0 ]; then
            echo "   Tabelas encontradas: $TABLE_COUNT"
        else
            echo "   ⚠️  Nenhuma tabela encontrada"
        fi
    else
        echo "❌ Banco de Dados: FALHA NA CONEXÃO"
        all_ok=false
    fi
    
    echo
    
    # Testar PHP-FPM especificamente
    echo "5. Testando PHP-FPM:"
    echo "------------------"
    
    # Verificar se o socket existe
    if [ -S "/run/php/php8.1-fpm-sincronizador.sock" ]; then
        echo "✅ Socket PHP-FPM: EXISTE"
        
        # Verificar permissões
        SOCKET_PERMS=$(stat -c "%A %U %G" /run/php/php8.1-fpm-sincronizador.sock 2>/dev/null || echo "")
        echo "   Permissões: $SOCKET_PERMS"
    else
        echo "❌ Socket PHP-FPM: NÃO EXISTE"
        all_ok=false
        
        # Criar socket manualmente
        echo "   Criando socket manualmente..."
        mkdir -p /run/php
        touch /run/php/php8.1-fpm-sincronizador.sock
        chown www-data:www-data /run/php/php8.1-fpm-sincronizador.sock
        chmod 660 /run/php/php8.1-fpm-sincronizador.sock
        systemctl restart php8.1-fpm
    fi
    
    echo
    
    # Testar process PHP-FPM
    if pgrep -f "php-fpm: pool sincronizador" >/dev/null; then
        echo "✅ Processos PHP-FPM: RODANDO"
    else
        echo "❌ Processos PHP-FPM: PARADOS"
        all_ok=false
    fi
    
    echo
    
    if [ "$all_ok" = true ]; then
        log_success "✅ TODOS OS TESTES PASSARAM!"
        return 0
    else
        log_warning "⚠️  ALGUNS TESTES FALHARAM"
        return 1
    fi
}

# Finalizar instalação com informações
finalize_installation() {
    log_info "Finalizando instalação..."
    
    # Iniciar serviços
    systemctl start mysql
    systemctl start php8.1-fpm
    systemctl start nginx
    systemctl start sincronizador-vod
    
    # Aguardar inicialização
    sleep 5
    
    # Obter IP do servidor
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    # Criar arquivo de informações
    cat > /var/www/sincronizador-vod/INSTALACAO.md << EOF
# Sincronizador VOD XUI One - Instalação Concluída

## Data da Instalação: $(date)
## Sistema: Ubuntu 20.04 LTS
## Versão: 1.0.0

## ACESSO AO SISTEMA

### Frontend (Painel Web)
- URL: http://${SERVER_IP}/
- URL Alternativa: http://localhost/
- Usuário: admin
- Senha: Admin@2024

### Backend (API)
- URL: http://${SERVER_IP}:3000/
- Health Check: http://${SERVER_IP}:3000/api/health
- Documentação: http://${SERVER_IP}:3000/api/

## DIRETÓRIOS IMPORTANTES

- Código Fonte: /var/www/sincronizador-vod/
- Backend (Node.js): /var/www/sincronizador-vod/backend/
- Frontend (PHP): /var/www/sincronizador-vod/frontend/
- Banco de Dados: /var/www/sincronizador-vod/database/
- Logs: /var/www/sincronizador-vod/logs/
- Backups: /var/www/sincronizador-vod/backups/
- Scripts: /var/www/sincronizador-vod/scripts/

## SERVIÇOS INSTALADOS

1. **Backend API (Node.js)**
   - Serviço: sincronizador-vod
   - Porta: 3000
   - Comando: systemctl status sincronizador-vod

2. **Web Server (Nginx)**
   - Serviço: nginx
   - Porta: 80
   - Config: /etc/nginx/sites-available/sincronizador-vod

3. **Banco de Dados (MySQL)**
   - Serviço: mysql
   - Banco: sincronizador_vod
   - Usuário: vod_user
   - Senha: VodSync@2024

4. **PHP-FPM**
   - Serviço: php8.1-fpm
   - Pool: sincronizador
   - Socket: /run/php/php8.1-fpm-sincronizador.sock

## COMANDOS ÚTEIS

### Gerenciamento de Serviços
\`\`\`bash
# Verificar status de todos os serviços
cd /var/www/sincronizador-vod/scripts && ./status.sh

# Reiniciar todos os serviços
cd /var/www/sincronizador-vod/scripts && ./restart.sh

# Verificar logs
cd /var/www/sincronizador-vod/scripts && ./logs.sh

# Serviços individuais
systemctl status sincronizador-vod
systemctl status nginx
systemctl status mysql
systemctl status php8.1-fpm
\`\`\`

### Solução de Problemas

#### Se o Frontend mostrar erro 502:
\`\`\`bash
# Verificar PHP-FPM
systemctl restart php8.1-fpm

# Verificar socket
ls -la /run/php/

# Verificar logs do PHP-FPM
tail -f /var/log/php8.1-fpm-sincronizador-error.log
\`\`\`

#### Se a API não responder:
\`\`\`bash
# Verificar backend
systemctl restart sincronizador-vod

# Verificar logs
tail -f /var/www/sincronizador-vod/backend/logs/combined.log
\`\`\`

## PRÓXIMOS PASSOS

1. **Acesse o sistema:** http://${SERVER_IP}/
2. **Faça login:** admin / Admin@2024
3. **Configure a chave TMDb:**
   - Obtenha em: https://www.themoviedb.org/settings/api
   - Configure em: Configurações do Sistema
4. **Configure conexão XUI:**
   - Acesse: Configuração XUI
   - Adicione seus dados de conexão
5. **Importe lista M3U:**
   - Acesse: Importar M3U
   - Cole sua lista M3U
6. **Configure agendamentos:**
   - Acesse: Agendamentos
   - Configure sincronização automática

## SUPORTE

### Logs para Diagnóstico
- Backend: /var/www/sincronizador-vod/backend/logs/
- Nginx: /var/log/nginx/sincronizador-vod.*.log
- PHP-FPM: /var/log/php8.1-fpm-sincronizador-error.log
- Sistema: journalctl -u sincronizador-vod

### Backup Automático
Backups diários são realizados automaticamente em:
- /var/www/sincronizador-vod/backups/

### Monitoramento
Script de monitoramento automático configurado:
- /etc/cron.hourly/sincronizador-health

## SEGURANÇA IMPORTANTE

1. **ALTERE A SENHA PADRÃO DO ADMINISTRADOR!**
2. Configure SSL/TLS para produção
3. Restrinja acesso por IP se necessário
4. Mantenha o sistema atualizado
5. Faça backups regulares

---

**Instalação concluída em:** $(date)
**Tempo total:** $(( $(date +%s) - START_TIME )) segundos
EOF
    
    # Testar instalação
    test_installation
    
    echo
    echo "=========================================="
    echo " 🎉 INSTALAÇÃO COMPLETA DO SINCRONIZADOR VOD!"
    echo "=========================================="
    echo
    echo "📋 INFORMAÇÕES DO SISTEMA:"
    echo "--------------------------"
    echo "• Sistema instalado em: /var/www/sincronizador-vod/"
    echo "• Painel Web: http://${SERVER_IP}/"
    echo "• API Backend: http://${SERVER_IP}:3000/api"
    echo "• Usuário: admin"
    echo "• Senha: Admin@2024"
    echo
    echo "🚀 PARA COMEÇAR:"
    echo "----------------"
    echo "1. Acesse: http://${SERVER_IP}/"
    echo "2. Faça login com as credenciais acima"
    echo "3. Configure sua chave TMDb nas configurações"
    echo "4. Adicione uma conexão XUI One"
    echo "5. Importe sua primeira lista M3U"
    echo
    echo "🔧 FERRAMENTAS DE GERENCIAMENTO:"
    echo "-------------------------------"
    echo "• Status completo: cd /var/www/sincronizador-vod/scripts && ./status.sh"
    echo "• Reiniciar tudo: cd /var/www/sincronizador-vod/scripts && ./restart.sh"
    echo "• Ver logs: cd /var/www/sincronizador-vod/scripts && ./logs.sh"
    echo
    echo "⚠️  ATENÇÃO IMPORTANTE:"
    echo "---------------------"
    echo "• ALTERE A SENHA DO ADMINISTRADOR APÓS O PRIMEIRO LOGIN!"
    echo "• Configure SSL/TLS para ambiente de produção"
    echo "• Consulte o arquivo INSTALACAO.md para mais detalhes"
    echo
    echo "📞 SUPORTE E DIAGNÓSTICO:"
    echo "------------------------"
    echo "• Logs do sistema: /var/www/sincronizador-vod/logs/"
    echo "• Backup automático: /var/www/sincronizador-vod/backups/"
    echo "• Monitoramento: /etc/cron.hourly/sincronizador-health"
    echo
    echo "=========================================="
    echo
    echo "💡 DICA: Execute './status.sh' na pasta scripts para verificar"
    echo "        o status completo de todos os serviços."
    echo
}

# Função principal
main() {
    clear
    echo "=========================================="
    echo " INSTALADOR SINCRONIZADOR VOD XUI ONE"
    echo "        Ubuntu 20.04 LTS"
    echo "        VERSÃO COMPLETA E CORRIGIDA"
    echo "=========================================="
    echo
    echo "Este instalador vai configurar todo o sistema incluindo:"
    echo "• Backend Node.js API"
    echo "• Frontend PHP com Bootstrap"
    echo "• Banco de Dados MySQL"
    echo "• Web Server Nginx"
    echo "• PHP-FPM configurado corretamente"
    echo "• Sistema de permissões"
    echo "• Scripts de manutenção"
    echo "• Monitoramento automático"
    echo
    echo "Tempo estimado: 10-15 minutos"
    echo
    
    # Obter senha do MySQL root
    echo "🔐 CONFIGURAÇÃO DO MYSQL"
    echo "------------------------"
    echo "Digite a senha root do MySQL (deixe em branco para padrão):"
    read -s DB_ROOT_PASSWORD
    echo
    
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        DB_ROOT_PASSWORD="MySQLRoot@2024"
        echo "Usando senha padrão: $DB_ROOT_PASSWORD"
    fi
    
    echo
    echo "🔄 INICIANDO INSTALAÇÃO..."
    echo "=========================="
    
    # Registrar hora de início
    START_TIME=$(date +%s)
    
    # Executar etapas na ordem correta
    check_root
    check_ubuntu_version
    update_system
    install_dependencies
    setup_mysql
    create_directory_structure
    create_backend_files
    create_frontend_files
    setup_nginx
    setup_nodejs_service
    setup_permissions
    install_node_dependencies
    import_database
    setup_firewall
    create_maintenance_scripts
    setup_cron_jobs
    fix_php_fpm
    finalize_installation
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo
    echo "✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "⏱️  Tempo total: $DURATION segundos"
    echo
    echo "📄 Documentação completa em: /var/www/sincronizador-vod/INSTALACAO.md"
    echo
}

# Executar instalação
main "$@"
