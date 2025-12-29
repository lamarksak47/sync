#!/bin/bash

# ==========================================
# INSTALADOR COMPLETO SINCRONIZADOR VOD XUI ONE
# Ubuntu 20.04 LTS
# ==========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    # Instalar PHP 8.1 (compatível com Ubuntu 20.04)
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
    
    # Criar banco de dados e usuário
    mysql -e "CREATE DATABASE IF NOT EXISTS sincronizador_vod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS 'vod_user'@'localhost' IDENTIFIED BY 'VodSync@2024';"
    mysql -e "GRANT ALL PRIVILEGES ON sincronizador_vod.* TO 'vod_user'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON xui.* TO 'vod_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Melhorar segurança do MySQL
    mysql_secure_installation <<EOF
n
y
y
y
y
EOF
    
    log_success "MySQL configurado"
}

# Criar estrutura de pastas
create_directory_structure() {
    log_info "Criando estrutura de pastas..."
    
    # Diretório principal
    mkdir -p /var/www/sincronizador-vod
    cd /var/www/sincronizador-vod
    
    # Estrutura completa
    mkdir -p backend/src/controllers
    mkdir -p backend/src/services
    mkdir -p backend/src/routes
    mkdir -p backend/src/database
    mkdir -p backend/src/utils
    mkdir -p backend/logs
    
    mkdir -p frontend/public/assets/css
    mkdir -p frontend/public/assets/js
    mkdir -p frontend/public/assets/images
    mkdir -p frontend/app/controllers
    mkdir -p frontend/app/models
    mkdir -p frontend/app/views
    mkdir -p frontend/app/helpers
    mkdir -p frontend/config
    
    mkdir -p database
    mkdir -p scripts
    mkdir -p logs
    mkdir -p backups
    
    log_success "Estrutura de pastas criada"
}

# Criar arquivos do backend Node.js
create_backend_files() {
    log_info "Criando arquivos do backend Node.js..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # package.json
    # ==========================================
    cat > backend/package.json << 'EOF'
{
  "name": "sincronizador-vod-xui-backend",
  "version": "1.0.0",
  "description": "Sistema de sincronização VOD para XUI One",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "dev": "nodemon src/app.js",
    "test": "jest",
    "migrate": "node scripts/migrate.js"
  },
  "keywords": ["iptv", "vod", "xui", "synchronizer", "tmdb"],
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
    "rate-limit-flexible": "^2.4.1",
    "uuid": "^9.0.1",
    "moment": "^2.29.4",
    "socket.io": "^4.7.2"
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
# ==========================================
# CONFIGURAÇÕES DO SERVIDOR
# ==========================================
PORT=3000
NODE_ENV=production
APP_URL=http://localhost
APP_NAME=Sincronizador VOD XUI One

# ==========================================
# BANCO DE DADOS DO SISTEMA
# ==========================================
DB_HOST=localhost
DB_PORT=3306
DB_USER=vod_user
DB_PASSWORD=VodSync@2024
DB_NAME=sincronizador_vod
DB_CHARSET=utf8mb4

# ==========================================
# JWT AUTHENTICATION
# ==========================================
JWT_SECRET=your_super_secret_jwt_key_change_in_production_@2024!
JWT_EXPIRES_IN=24h

# ==========================================
# TMDb API CONFIGURATION
# ==========================================
TMDB_API_KEY=your_tmdb_api_key_here
TMDB_LANGUAGE=pt-BR
TMDB_TIMEOUT=10000

# ==========================================
# XUI DATABASE DEFAULTS
# ==========================================
XUI_DB_HOST=localhost
XUI_DB_PORT=3306
XUI_DB_USER=xui_user
XUI_DB_PASSWORD=xui_password
XUI_DB_NAME=xui

# ==========================================
# SYSTEM SETTINGS
# ==========================================
SYNC_BATCH_SIZE=50
MAX_RETRY_ATTEMPTS=3
LOG_LEVEL=info
UPLOAD_LIMIT=50mb
SESSION_SECRET=session_secret_change_in_production

# ==========================================
# EMAIL SETTINGS (Optional)
# ==========================================
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASSWORD=your_app_password
EMAIL_FROM=noreply@sincronizador.com

# ==========================================
# LICENSE SETTINGS
# ==========================================
LICENSE_KEY=DEMO-LICENSE-KEY-2024
LICENSE_EXPIRE_DAYS=30
EOF

    # ==========================================
    # app.js
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
    const dbStatus = await database.testConnection();
    
    res.status(200).json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        service: 'Sincronizador VOD XUI One',
        version: '1.0.0',
        database: dbStatus ? 'connected' : 'disconnected',
        environment: process.env.NODE_ENV
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
            ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
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

server.listen(PORT, '0.0.0.0', async () => {
    logger.info(`Servidor rodando na porta ${PORT}`);
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
    # database/mysql.js
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
    # utils/logger.js
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
            maxsize: 5242880, // 5MB
            maxFiles: 5
        }),
        
        // Arquivo de todos os logs
        new winston.transports.File({
            filename: path.join(logDir, 'combined.log'),
            maxsize: 5242880, // 5MB
            maxFiles: 10
        }),
        
        // Arquivo de sincronização
        new winston.transports.File({
            filename: path.join(logDir, 'sync.log'),
            level: 'info',
            maxsize: 10485760, // 10MB
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
    # services/tmdbService.js
    # ==========================================
    cat > backend/src/services/tmdbService.js << 'EOF'
const axios = require('axios');
const logger = require('../utils/logger');

class TMDBService {
    constructor() {
        this.apiKey = process.env.TMDB_API_KEY;
        this.language = process.env.TMDB_LANGUAGE || 'pt-BR';
        this.baseURL = 'https://api.themoviedb.org/3';
        
        if (!this.apiKey || this.apiKey === 'your_tmdb_api_key_here') {
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
            hits: 0, // Seria necessário rastrear hits/misses
            misses: 0
        };
    }
}

module.exports = new TMDBService();
EOF

    # ==========================================
    # services/m3uParser.js
    # ==========================================
    cat > backend/src/services/m3uParser.js << 'EOF'
const logger = require('../utils/logger');

class M3UParser {
    constructor() {
        this.currentItem = null;
        this.items = [];
        this.categories = {
            movies: new Map(),
            series: new Map()
        };
        this.stats = {
            total: 0,
            movies: 0,
            series: 0,
            other: 0,
            errors: 0
        };
    }
    
    parse(content) {
        try {
            this.reset();
            
            if (!content || typeof content !== 'string') {
                throw new Error('Conteúdo M3U inválido ou vazio');
            }
            
            // Verificar se é um arquivo M3U válido
            if (!content.startsWith('#EXTM3U')) {
                throw new Error('Arquivo M3U inválido. Deve começar com #EXTM3U');
            }
            
            const lines = content.split('\n');
            let lineNumber = 0;
            
            for (let i = 0; i < lines.length; i++) {
                lineNumber = i + 1;
                const line = lines[i].trim();
                
                if (!line) continue;
                
                if (line.startsWith('#EXTINF:')) {
                    this.parseExtInf(line, lineNumber);
                } else if (line.startsWith('#EXTGRP:')) {
                    this.parseExtGrp(line);
                } else if (line.startsWith('#EXTVLCOPT:')) {
                    this.parseVlcOption(line);
                } else if (line.startsWith('http') || line.startsWith('rtmp') || line.startsWith('rtsp')) {
                    this.parseUrl(line);
                    this.finalizeItem(lineNumber);
                } else if (line.startsWith('#EXTM3U')) {
                    // Header, ignorar
                    continue;
                } else if (line.startsWith('#')) {
                    // Outras tags EXT, ignorar por enquanto
                    continue;
                } else if (line.includes('://')) {
                    // URL sem tag EXTINF (formato inválido mas tentar processar)
                    logger.warn(`Linha ${lineNumber}: URL sem tag EXTINF: ${line.substring(0, 50)}...`);
                    this.parseUrl(line);
                    if (this.currentItem) {
                        this.finalizeItem(lineNumber);
                    }
                }
            }
            
            // Processar itens restantes
            if (this.currentItem && this.currentItem.url) {
                this.finalizeItem(lineNumber);
            }
            
            logger.info('Análise M3U concluída:', {
                total: this.stats.total,
                movies: this.stats.movies,
                series: this.stats.series,
                categories: this.getCategoriesCount()
            });
            
            return {
                success: true,
                items: this.items,
                categories: {
                    movies: Array.from(this.categories.movies.entries())
                        .map(([name, data]) => ({ 
                            name, 
                            count: data.count,
                            items: data.items || []
                        })),
                    series: Array.from(this.categories.series.entries())
                        .map(([name, data]) => ({ 
                            name, 
                            count: data.count,
                            items: data.items || []
                        }))
                },
                stats: { ...this.stats },
                metadata: {
                    total_lines: lines.length,
                    processed_lines: lineNumber,
                    valid_items: this.items.length
                }
            };
            
        } catch (error) {
            logger.error('Erro ao analisar M3U:', {
                error: error.message,
                stack: error.stack
            });
            
            return {
                success: false,
                error: error.message,
                items: [],
                categories: { movies: [], series: [] },
                stats: this.stats
            };
        }
    }
    
    reset() {
        this.currentItem = null;
        this.items = [];
        this.categories = {
            movies: new Map(),
            series: new Map()
        };
        this.stats = {
            total: 0,
            movies: 0,
            series: 0,
            other: 0,
            errors: 0
        };
    }
    
    parseExtInf(line, lineNumber) {
        try {
            // Padrão: #EXTINF:-1 tvg-id="ID" tvg-name="NAME" tvg-logo="LOGO" group-title="GROUP",Display Name
            const match = line.match(/#EXTINF:(-?\d+)\s*(.*)/);
            if (!match) {
                throw new Error(`Formato EXTINF inválido na linha ${lineNumber}`);
            }
            
            const [, duration, rest] = match;
            const attributes = this.parseAttributes(rest);
            
            this.currentItem = {
                duration: parseInt(duration),
                name: attributes.name || '',
                group: attributes.group_title || attributes.group || 'Sem Categoria',
                logo: attributes.tvg_logo || '',
                id: attributes.tvg_id || '',
                language: attributes.tvg_language || 'pt',
                country: attributes.tvg_country || 'BR',
                attributes,
                raw_line: line,
                line_number: lineNumber
            };
            
        } catch (error) {
            logger.warn(`Erro ao parsear EXTINF na linha ${lineNumber}:`, error.message);
            this.stats.errors++;
        }
    }
    
    parseAttributes(rest) {
        const attributes = {};
        
        // Extrair nome (depois da última vírgula)
        const lastComma = rest.lastIndexOf(',');
        if (lastComma !== -1) {
            attributes.name = rest.substring(lastComma + 1).trim();
            rest = rest.substring(0, lastComma);
        }
        
        // Extrair atributos no formato chave="valor"
        const attrRegex = /(\w+)=("([^"]*)"|'([^']*)'|([^"'\s]*))/g;
        let match;
        
        while ((match = attrRegex.exec(rest)) !== null) {
            const key = match[1];
            const value = match[3] || match[4] || match[5];
            attributes[key] = value;
        }
        
        return attributes;
    }
    
    parseExtGrp(line) {
        if (this.currentItem) {
            const group = line.replace('#EXTGRP:', '').trim();
            this.currentItem.group = group;
        }
    }
    
    parseVlcOption(line) {
        // Ignorar opções do VLC por enquanto
        // Poderiam ser usadas para configurações específicas
    }
    
    parseUrl(url) {
        if (this.currentItem) {
            this.currentItem.url = url.trim();
            this.currentItem.protocol = this.extractProtocol(url);
            this.currentItem.extension = this.extractExtension(url);
        }
    }
    
    extractProtocol(url) {
        const match = url.match(/^(\w+):\/\//);
        return match ? match[1] : 'http';
    }
    
    extractExtension(url) {
        // Remover parâmetros de query
        const cleanUrl = url.split('?')[0].split('#')[0];
        const match = cleanUrl.match(/\.([a-zA-Z0-9]{2,4})$/);
        return match ? match[1].toLowerCase() : 'mp4';
    }
    
    finalizeItem(lineNumber) {
        if (this.currentItem && this.currentItem.url) {
            // Determinar tipo (filme ou série)
            this.currentItem.type = this.determineType(this.currentItem);
            
            // Adicionar ID único
            this.currentItem.id = `item_${Date.now()}_${this.items.length}`;
            
            // Adicionar à lista
            this.items.push({ ...this.currentItem });
            
            // Atualizar estatísticas
            this.stats.total++;
            if (this.currentItem.type === 'movie') {
                this.stats.movies++;
            } else if (this.currentItem.type === 'series') {
                this.stats.series++;
            } else {
                this.stats.other++;
            }
            
            // Atualizar categorias
            this.updateCategories(this.currentItem);
            
            this.currentItem = null;
        } else if (this.currentItem) {
            logger.warn(`Linha ${lineNumber}: Item sem URL: ${this.currentItem.name}`);
            this.stats.errors++;
            this.currentItem = null;
        }
    }
    
    determineType(item) {
        const name = item.name || '';
        const group = item.group || '';
        
        // Heurísticas para determinar tipo
        const seriesPatterns = [
            /S\d+E\d+/i,        // S01E01
            /Temporada\s*\d+/i, // Temporada 1
            /Season\s*\d+/i,    // Season 1
            /Episódio\s*\d+/i,  // Episódio 1
            /\d+x\d+/i,         // 1x01
            /\[S\d+E\d+\]/i,    // [S01E01]
            /\(S\d+E\d+\)/i     // (S01E01)
        ];
        
        const moviePatterns = [
            /\((\d{4})\)/,       // (2023)
            /\[(\d{4})\]/        // [2023]
        ];
        
        // Verificar se é série
        for (const pattern of seriesPatterns) {
            if (pattern.test(name) || pattern.test(group)) {
                return 'series';
            }
        }
        
        // Verificar se é filme
        for (const pattern of moviePatterns) {
            if (pattern.test(name)) {
                return 'movie';
            }
        }
        
        // Baseado no nome do grupo
        const groupLower = group.toLowerCase();
        if (groupLower.includes('series') || groupLower.includes('série') || 
            groupLower.includes('serie') || groupLower.includes('tv show')) {
            return 'series';
        }
        
        if (groupLower.includes('movie') || groupLower.includes('filme') || 
            groupLower.includes('cinema') || groupLower.includes('film')) {
            return 'movie';
        }
        
        // Baseado no nome
        const nameLower = name.toLowerCase();
        if (nameLower.includes('episodio') || nameLower.includes('episódio') || 
            nameLower.includes('episode') || nameLower.includes('temporada') || 
            nameLower.includes('season')) {
            return 'series';
        }
        
        // Padrão: se tem duração maior que 60 minutos e não tem padrão de série, provavelmente é filme
        if (item.duration > 3600 && !seriesPatterns.some(p => p.test(name))) {
            return 'movie';
        }
        
        // Default
        return 'other';
    }
    
    updateCategories(item) {
        if (!item.group || item.type === 'other') {
            return;
        }
        
        const categoryMap = this.categories[item.type];
        
        if (!categoryMap.has(item.group)) {
            categoryMap.set(item.group, {
                count: 0,
                items: []
            });
        }
        
        const category = categoryMap.get(item.group);
        category.count++;
        category.items.push({
            id: item.id,
            name: item.name,
            duration: item.duration,
            logo: item.logo
        });
    }
    
    getCategoriesCount() {
        return {
            movies: this.categories.movies.size,
            series: this.categories.series.size,
            total: this.categories.movies.size + this.categories.series.size
        };
    }
    
    filterByCategory(items, category, type) {
        return items.filter(item => 
            item.type === type && 
            item.group === category
        );
    }
    
    getItemsByType(type) {
        return this.items.filter(item => item.type === type);
    }
    
    getSampleItems(limit = 5) {
        return {
            movies: this.items.filter(i => i.type === 'movie').slice(0, limit),
            series: this.items.filter(i => i.type === 'series').slice(0, limit)
        };
    }
    
    validateItem(item) {
        const errors = [];
        
        if (!item.name || item.name.trim() === '') {
            errors.push('Nome não especificado');
        }
        
        if (!item.url || !item.url.includes('://')) {
            errors.push('URL inválida');
        }
        
        if (!item.type || !['movie', 'series', 'other'].includes(item.type)) {
            errors.push('Tipo inválido');
        }
        
        return {
            valid: errors.length === 0,
            errors: errors
        };
    }
}

module.exports = M3UParser;
EOF

    log_success "Arquivos do backend criados"
}

# Criar arquivos do frontend PHP
create_frontend_files() {
    log_info "Criando arquivos do frontend PHP..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # index.php (Dashboard)
    # ==========================================
    cat > frontend/public/index.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';
require_once '../app/helpers/Session.php';

// Inicializar sessão
Session::start();

// Verificar autenticação
if (!Session::isLoggedIn()) {
    header('Location: login.php');
    exit;
}

// Inicializar API Client
$api = new ApiClient();

// Obter dados do dashboard
$dashboardData = [];
try {
    $response = $api->request('GET', '/dashboard');
    if ($response['success']) {
        $dashboardData = $response['data'];
    }
} catch (Exception $e) {
    $error = $e->getMessage();
}

// Obter estatísticas
$stats = $dashboardData['stats'] ?? [];
$recentSyncs = $dashboardData['recent_syncs'] ?? [];
$xuiStatus = $dashboardData['xui_status'] ?? 'Desconectado';
$lastSync = $dashboardData['last_sync'] ?? 'Nunca';
$nextSync = $dashboardData['next_sync'] ?? 'Não agendado';

// Obter tipo de usuário
$userType = Session::get('user_type', 'usuario');
$username = Session::get('username', 'Usuário');
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
    
    <!-- Custom CSS -->
    <link rel="stylesheet" href="assets/css/custom.css">
    
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
        
        .user-badge {
            position: absolute;
            top: 20px;
            right: 20px;
            background-color: var(--secondary-color);
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9rem;
        }
        
        .sync-progress {
            background: linear-gradient(90deg, var(--primary-color), var(--secondary-color));
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.7; }
            100% { opacity: 1; }
        }
        
        .toast {
            background-color: #252525;
            border: 1px solid #333;
            color: #e0e0e0;
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
        
        <!-- Status Cards -->
        <div class="row mb-4">
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-<?php echo $xuiStatus == 'Conectado' ? 'success' : 'danger'; ?>">
                    <div class="card-body">
                        <i class="bi bi-database text-<?php echo $xuiStatus == 'Conectado' ? 'success' : 'danger'; ?>"></i>
                        <h6 class="card-title text-muted">Status XUI</h6>
                        <h2 class="mb-0">
                            <span class="badge bg-<?php echo $xuiStatus == 'Conectado' ? 'success' : 'danger'; ?>">
                                <?php echo $xuiStatus; ?>
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
                        <h5 class="mb-0"><?php echo $lastSync; ?></h5>
                        <small class="text-muted">Data/Hora</small>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-warning">
                    <div class="card-body">
                        <i class="bi bi-calendar-check text-warning"></i>
                        <h6 class="card-title text-muted">Próxima Sinc.</h6>
                        <h5 class="mb-0"><?php echo $nextSync; ?></h5>
                        <small class="text-muted">Agendamento</small>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-primary">
                    <div class="card-body">
                        <i class="bi bi-collection-play text-primary"></i>
                        <h6 class="card-title text-muted">Total Conteúdos</h6>
                        <h2 class="mb-0"><?php echo $stats['total_content'] ?? '0'; ?></h2>
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
                                        <i class="bi bi-film text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Filmes</h6>
                                        <h3 class="mb-0"><?php echo $stats['movies_count'] ?? '0'; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-success rounded p-3 me-3">
                                        <i class="bi bi-tv text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Séries</h6>
                                        <h3 class="mb-0"><?php echo $stats['series_count'] ?? '0'; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-info rounded p-3 me-3">
                                        <i class="bi bi-list-check text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Listas M3U</h6>
                                        <h3 class="mb-0"><?php echo $stats['m3u_lists_count'] ?? '0'; ?></h3>
                                    </div>
                                </div>
                            </div>
                            <div class="col-6 mb-3">
                                <div class="d-flex align-items-center">
                                    <div class="bg-warning rounded p-3 me-3">
                                        <i class="bi bi-clock-history text-white fs-4"></i>
                                    </div>
                                    <div>
                                        <h6 class="mb-0 text-muted">Agendamentos</h6>
                                        <h3 class="mb-0"><?php echo $stats['schedules_count'] ?? '0'; ?></h3>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="mt-4">
                            <h6 class="text-muted mb-3">Progresso do Sistema</h6>
                            <div class="progress mb-2" style="height: 10px;">
                                <div class="progress-bar bg-success" style="width: 75%"></div>
                            </div>
                            <div class="d-flex justify-content-between small text-muted">
                                <span>75% Concluído</span>
                                <span>Status: Ativo</span>
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
                                    <i class="bi bi-cpu fs-1 text-success"></i>
                                    <h6 class="mt-2 mb-1">Backend API</h6>
                                    <span class="badge bg-success">Online</span>
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
                                    <i class="bi bi-cloud fs-1 text-<?php echo !empty($stats['tmdb_status']) && $stats['tmdb_status'] ? 'success' : 'warning'; ?>"></i>
                                    <h6 class="mt-2 mb-1">TMDb API</h6>
                                    <span class="badge bg-<?php echo !empty($stats['tmdb_status']) && $stats['tmdb_status'] ? 'success' : 'warning'; ?>">
                                        <?php echo !empty($stats['tmdb_status']) && $stats['tmdb_status'] ? 'Conectado' : 'Pendente'; ?>
                                    </span>
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
    
    <!-- Socket.io for real-time updates -->
    <script src="https://cdn.socket.io/4.6.0/socket.io.min.js"></script>
    
    <!-- Custom JS -->
    <script src="assets/js/app.js"></script>
    
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
        
        // Conectar ao WebSocket para atualizações em tempo real
        const socket = io('http://localhost:3000');
        
        socket.on('connect', function() {
            console.log('Conectado ao servidor WebSocket');
            
            // Inscrever para atualizações do dashboard
            socket.emit('subscribe', 'dashboard');
        });
        
        socket.on('sync_progress', function(data) {
            // Atualizar progresso em tempo real
            if (data.progress) {
                console.log('Progresso da sincronização:', data.progress);
                // Aqui você poderia atualizar a UI com o progresso
            }
        });
        
        socket.on('sync_complete', function(data) {
            // Recarregar dados quando uma sincronização for concluída
            if (data.success) {
                location.reload();
            }
        });
        
        // Atualizar status a cada 30 segundos
        setInterval(function() {
            $.ajax({
                url: '/api/health',
                method: 'GET',
                success: function(data) {
                    console.log('Health check:', data);
                }
            });
        }, 30000);
    </script>
</body>
</html>
EOF

    # ==========================================
    # config/database.php
    # ==========================================
    cat > frontend/config/database.php << 'EOF'
<?php
// ==========================================
// CONFIGURAÇÃO DO BANCO DE DADOS - Sincronizador VOD
// ==========================================

// Configurações do banco de dados do sistema
define('DB_HOST', 'localhost');
define('DB_PORT', '3306');
define('DB_USER', 'vod_user');
define('DB_PASSWORD', 'VodSync@2024');
define('DB_NAME', 'sincronizador_vod');
define('DB_CHARSET', 'utf8mb4');

// Configuração da API Node.js
define('API_BASE_URL', 'http://localhost:3000/api');
define('API_TIMEOUT', 30);
define('API_DEBUG', false);

// Configurações do sistema
define('APP_NAME', 'Sincronizador VOD XUI One');
define('APP_VERSION', '1.0.0');
define('APP_URL', 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost'));
define('APP_ENV', 'production'); // production, development

// Configurações de segurança
define('SESSION_NAME', 'vod_sync_session');
define('SESSION_LIFETIME', 86400); // 24 horas em segundos
define('SESSION_PATH', '/');
define('SESSION_DOMAIN', '');
define('SESSION_SECURE', false); // true para HTTPS
define('SESSION_HTTPONLY', true);
define('SESSION_SAMESITE', 'Lax');

// Configurações de upload
define('MAX_UPLOAD_SIZE', 100 * 1024 * 1024); // 100MB
define('ALLOWED_M3U_EXTENSIONS', ['m3u', 'm3u8']);
define('UPLOAD_PATH', __DIR__ . '/../uploads/');

// Configurações de e-mail
define('SMTP_HOST', '');
define('SMTP_PORT', 587);
define('SMTP_USER', '');
define('SMTP_PASSWORD', '');
define('EMAIL_FROM', 'noreply@sincronizador.com');
define('EMAIL_FROM_NAME', 'Sincronizador VOD');

// Configurações de licença
define('LICENSE_KEY', 'DEMO-LICENSE-KEY-2024');
define('LICENSE_CHECK_INTERVAL', 86400); // 24 horas

// Configurações de cache
define('CACHE_ENABLED', true);
define('CACHE_TTL', 3600); // 1 hora

// Configurações de log
define('LOG_ENABLED', true);
define('LOG_PATH', __DIR__ . '/../logs/');
define('LOG_LEVEL', 'INFO'); // DEBUG, INFO, WARNING, ERROR

// Timezone
date_default_timezone_set('America/Sao_Paulo');

// Error reporting
if (APP_ENV === 'development') {
    error_reporting(E_ALL);
    ini_set('display_errors', 1);
} else {
    error_reporting(0);
    ini_set('display_errors', 0);
}

// Criar diretórios necessários
$required_dirs = [
    LOG_PATH,
    UPLOAD_PATH,
    UPLOAD_PATH . 'm3u/',
    UPLOAD_PATH . 'backups/',
    UPLOAD_PATH . 'exports/'
];

foreach ($required_dirs as $dir) {
    if (!file_exists($dir)) {
        mkdir($dir, 0755, true);
    }
}

// Função para conectar ao banco de dados
function getDatabaseConnection() {
    try {
        $dsn = "mysql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_PERSISTENT => false,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES " . DB_CHARSET
        ];
        
        $pdo = new PDO($dsn, DB_USER, DB_PASSWORD, $options);
        return $pdo;
        
    } catch (PDOException $e) {
        error_log("Erro na conexão com o banco de dados: " . $e->getMessage());
        
        // Em ambiente de desenvolvimento, mostrar erro
        if (APP_ENV === 'development') {
            die("Erro na conexão com o banco de dados: " . $e->getMessage());
        } else {
            die("Erro interno do servidor. Por favor, tente novamente mais tarde.");
        }
    }
}

// Função para log
function writeLog($message, $level = 'INFO', $context = []) {
    if (!LOG_ENABLED) return;
    
    $logLevels = ['DEBUG', 'INFO', 'WARNING', 'ERROR'];
    $currentLevelIndex = array_search(LOG_LEVEL, $logLevels);
    $messageLevelIndex = array_search(strtoupper($level), $logLevels);
    
    if ($messageLevelIndex < $currentLevelIndex) return;
    
    $logFile = LOG_PATH . date('Y-m-d') . '.log';
    $timestamp = date('Y-m-d H:i:s');
    $contextStr = !empty($context) ? json_encode($context) : '';
    
    $logMessage = "[$timestamp] [$level] $message $contextStr" . PHP_EOL;
    
    file_put_contents($logFile, $logMessage, FILE_APPEND | LOCK_EX);
}

// Inicializar sessão com configurações personalizadas
function initSession() {
    session_name(SESSION_NAME);
    session_set_cookie_params([
        'lifetime' => SESSION_LIFETIME,
        'path' => SESSION_PATH,
        'domain' => SESSION_DOMAIN,
        'secure' => SESSION_SECURE,
        'httponly' => SESSION_HTTPONLY,
        'samesite' => SESSION_SAMESITE
    ]);
    
    session_start();
    
    // Regenerar ID da sessão periodicamente
    if (!isset($_SESSION['created'])) {
        $_SESSION['created'] = time();
    } else if (time() - $_SESSION['created'] > 1800) {
        session_regenerate_id(true);
        $_SESSION['created'] = time();
    }
}

// Verificar se a licença é válida
function checkLicense() {
    // Implementação simplificada
    // Em produção, isso seria verificado contra um servidor de licença
    $licenseFile = __DIR__ . '/../license.key';
    
    if (file_exists($licenseFile)) {
        $licenseKey = trim(file_get_contents($licenseFile));
        if ($licenseKey === LICENSE_KEY) {
            return true;
        }
    }
    
    // Verificação online (simplificada)
    try {
        $apiClient = new ApiClient();
        $response = $apiClient->request('POST', '/license/check', [
            'license_key' => LICENSE_KEY
        ]);
        
        return $response['success'] ?? false;
    } catch (Exception $e) {
        writeLog('Erro na verificação de licença: ' . $e->getMessage(), 'ERROR');
        return false;
    }
}

// Incluir classes necessárias
require_once __DIR__ . '/../app/helpers/ApiClient.php';
require_once __DIR__ . '/../app/helpers/Session.php';

// Inicializar sessão
initSession();

// Verificar licença (apenas uma vez por sessão)
if (!isset($_SESSION['license_checked'])) {
    $_SESSION['license_valid'] = checkLicense();
    $_SESSION['license_checked'] = time();
}

// Redirecionar se a licença não for válida
if (!($_SESSION['license_valid'] ?? false)) {
    if (basename($_SERVER['PHP_SELF']) !== 'license.php') {
        header('Location: license.php');
        exit;
    }
}
?>
EOF

    # ==========================================
    # app/helpers/ApiClient.php
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
            writeLog("API Request: $method $url", 'DEBUG', [
                'data' => $data,
                'response' => $response,
                'http_code' => $httpCode
            ]);
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
                    header('Location: login.php');
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
    
    public function testXUIConnection($config) {
        return $this->request('POST', '/xui/test', $config);
    }
    
    public function saveXUIConfig($config) {
        return $this->request('POST', '/xui/save', $config);
    }
    
    public function getXUIConfig() {
        return $this->request('GET', '/xui/config');
    }
    
    public function scanM3U($m3uContent, $listName = 'Nova Lista') {
        return $this->request('POST', '/m3u/scan', [
            'm3u_content' => $m3uContent,
            'list_name' => $listName
        ]);
    }
    
    public function getCategories($listId, $type) {
        return $this->request('GET', '/m3u/categories', [
            'listId' => $listId,
            'type' => $type
        ]);
    }
    
    public function startSync($data) {
        return $this->request('POST', '/sync/start', $data);
    }
    
    public function getSyncProgress($logId) {
        return $this->request('GET', '/sync/progress/' . $logId);
    }
    
    public function getDashboardData() {
        return $this->request('GET', '/dashboard');
    }
    
    public function getLogs($limit = 50, $offset = 0) {
        return $this->request('GET', '/sync/logs', [
            'limit' => $limit,
            'offset' => $offset
        ]);
    }
    
    public function createSchedule($scheduleData) {
        return $this->request('POST', '/schedules/create', $scheduleData);
    }
    
    public function getSchedules() {
        return $this->request('GET', '/schedules');
    }
    
    public function updateSchedule($scheduleId, $scheduleData) {
        return $this->request('PUT', '/schedules/' . $scheduleId, $scheduleData);
    }
    
    public function deleteSchedule($scheduleId) {
        return $this->request('DELETE', '/schedules/' . $scheduleId);
    }
    
    // Métodos para administradores
    
    public function getUsers($limit = 50, $offset = 0) {
        return $this->request('GET', '/admin/users', [
            'limit' => $limit,
            'offset' => $offset
        ]);
    }
    
    public function createUser($userData) {
        return $this->request('POST', '/admin/users', $userData);
    }
    
    public function updateUser($userId, $userData) {
        return $this->request('PUT', '/admin/users/' . $userId, $userData);
    }
    
    public function deleteUser($userId) {
        return $this->request('DELETE', '/admin/users/' . $userId);
    }
    
    public function getLicenses() {
        return $this->request('GET', '/admin/licenses');
    }
    
    public function createLicense($licenseData) {
        return $this->request('POST', '/admin/licenses', $licenseData);
    }
    
    // Health check
    public function healthCheck() {
        return $this->request('GET', '/health');
    }
    
    // Verificar se a API está online
    public function isOnline() {
        try {
            $response = $this->healthCheck();
            return $response['success'] ?? false;
        } catch (Exception $e) {
            return false;
        }
    }
}
?>
EOF

    # ==========================================
    # app/helpers/Session.php
    # ==========================================
    cat > frontend/app/helpers/Session.php << 'EOF'
<?php
class Session {
    public static function start() {
        if (session_status() === PHP_SESSION_NONE) {
            session_start();
        }
    }
    
    public static function set($key, $value) {
        $_SESSION[$key] = $value;
    }
    
    public static function get($key, $default = null) {
        return $_SESSION[$key] ?? $default;
    }
    
    public static function has($key) {
        return isset($_SESSION[$key]);
    }
    
    public static function remove($key) {
        if (self::has($key)) {
            unset($_SESSION[$key]);
        }
    }
    
    public static function destroy() {
        session_destroy();
        $_SESSION = [];
    }
    
    public static function isLoggedIn() {
        return self::get('logged_in', false) === true;
    }
    
    public static function requireLogin() {
        if (!self::isLoggedIn()) {
            header('Location: login.php');
            exit;
        }
    }
    
    public static function requireUserType($requiredType) {
        self::requireLogin();
        
        $userType = self::get('user_type', 'usuario');
        $hierarchy = ['usuario', 'revendedor', 'admin'];
        
        $userIndex = array_search($userType, $hierarchy);
        $requiredIndex = array_search($requiredType, $hierarchy);
        
        if ($userIndex < $requiredIndex) {
            header('Location: index.php');
            exit;
        }
    }
    
    public static function isAdmin() {
        return self::get('user_type') === 'admin';
    }
    
    public static function isReseller() {
        return self::get('user_type') === 'revendedor';
    }
    
    public static function isUser() {
        return self::get('user_type') === 'usuario';
    }
    
    public static function getUserId() {
        return self::get('user_id');
    }
    
    public static function getUsername() {
        return self::get('username');
    }
    
    public static function getUserType() {
        return self::get('user_type');
    }
    
    public static function setFlash($type, $message) {
        self::set('flash', [
            'type' => $type,
            'message' => $message
        ]);
    }
    
    public static function getFlash() {
        $flash = self::get('flash');
        self::remove('flash');
        return $flash;
    }
    
    public static function hasFlash() {
        return self::has('flash');
    }
    
    public static function setOldInput($data) {
        self::set('old_input', $data);
    }
    
    public static function getOldInput($key = null, $default = null) {
        $old = self::get('old_input', []);
        
        if ($key === null) {
            return $old;
        }
        
        return $old[$key] ?? $default;
    }
    
    public static function clearOldInput() {
        self::remove('old_input');
    }
    
    public static function setErrors($errors) {
        self::set('errors', $errors);
    }
    
    public static function getErrors($key = null) {
        $errors = self::get('errors', []);
        
        if ($key === null) {
            return $errors;
        }
        
        return $errors[$key] ?? [];
    }
    
    public static function hasErrors($key = null) {
        if ($key === null) {
            return !empty(self::get('errors', []));
        }
        
        return !empty(self::getErrors($key));
    }
    
    public static function clearErrors() {
        self::remove('errors');
    }
}
?>
EOF

    # ==========================================
    # login.php
    # ==========================================
    cat > frontend/public/login.php << 'EOF'
<?php
require_once '../config/database.php';
require_once '../app/helpers/ApiClient.php';
require_once '../app/helpers/Session.php';

// Inicializar sessão
Session::start();

// Redirecionar se já estiver logado
if (Session::isLoggedIn()) {
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
            
            if ($api->login($username, $password)) {
                Session::setFlash('success', 'Login realizado com sucesso!');
                header('Location: index.php');
                exit;
            } else {
                $error = $api->getLastError() ?: 'Usuário ou senha incorretos.';
            }
        } catch (Exception $e) {
            $error = 'Erro ao conectar com o servidor: ' . $e->getMessage();
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
        
        .alert {
            border-radius: 8px;
            border: none;
        }
        
        .form-label {
            font-weight: 600;
            color: #2c3e50;
        }
        
        .input-group-text {
            background-color: #f8f9fa;
            border: 2px solid #e0e0e0;
            border-right: none;
        }
        
        .login-footer {
            text-align: center;
            padding: 20px;
            border-top: 1px solid #e0e0e0;
            background-color: #f8f9fa;
            color: #666;
            font-size: 0.9rem;
        }
        
        .login-footer a {
            color: #3498db;
            text-decoration: none;
        }
        
        .login-footer a:hover {
            text-decoration: underline;
        }
        
        .system-info {
            margin-top: 20px;
            text-align: center;
            color: rgba(255, 255, 255, 0.8);
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
                
                <?php if (Session::hasFlash()): 
                    $flash = Session::getFlash();
                ?>
                <div class="alert alert-<?php echo $flash['type']; ?> alert-dismissible fade show" role="alert">
                    <i class="bi bi-check-circle me-2"></i>
                    <?php echo htmlspecialchars($flash['message']); ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                <?php endif; ?>
                
                <form method="POST" action="">
                    <div class="mb-3">
                        <label for="username" class="form-label">
                            <i class="bi bi-person"></i> Usuário
                        </label>
                        <div class="input-group">
                            <span class="input-group-text">
                                <i class="bi bi-person-fill"></i>
                            </span>
                            <input type="text" 
                                   class="form-control" 
                                   id="username" 
                                   name="username" 
                                   placeholder="Digite seu usuário"
                                   required
                                   autofocus>
                        </div>
                    </div>
                    
                    <div class="mb-4">
                        <label for="password" class="form-label">
                            <i class="bi bi-key"></i> Senha
                        </label>
                        <div class="input-group">
                            <span class="input-group-text">
                                <i class="bi bi-lock-fill"></i>
                            </span>
                            <input type="password" 
                                   class="form-control" 
                                   id="password" 
                                   name="password" 
                                   placeholder="Digite sua senha"
                                   required>
                        </div>
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
                    <small>Versão 1.0.0</small>
                </p>
            </div>
        </div>
        
        <div class="system-info">
            <p>
                <i class="bi bi-info-circle"></i> 
                Sistema profissional para sincronização de conteúdo VOD
            </p>
        </div>
    </div>
    
    <!-- Bootstrap JS Bundle with Popper -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        // Foco no campo de usuário
        document.getElementById('username').focus();
        
        // Mostrar/ocultar senha
        document.addEventListener('DOMContentLoaded', function() {
            const passwordInput = document.getElementById('password');
            const toggleButton = document.createElement('button');
            toggleButton.type = 'button';
            toggleButton.className = 'btn btn-outline-secondary';
            toggleButton.innerHTML = '<i class="bi bi-eye"></i>';
            toggleButton.style.position = 'absolute';
            toggleButton.style.right = '5px';
            toggleButton.style.top = '5px';
            toggleButton.style.zIndex = '5';
            
            const inputGroup = passwordInput.parentElement;
            inputGroup.style.position = 'relative';
            inputGroup.appendChild(toggleButton);
            
            toggleButton.addEventListener('click', function() {
                const type = passwordInput.getAttribute('type') === 'password' ? 'text' : 'password';
                passwordInput.setAttribute('type', type);
                this.innerHTML = type === 'password' ? '<i class="bi bi-eye"></i>' : '<i class="bi bi-eye-slash"></i>';
            });
        });
    </script>
</body>
</html>
<?php
// Limpar flash messages após exibição
Session::clearErrors();
Session::clearOldInput();
?>
EOF

    log_success "Arquivos do frontend criados"
}

# Criar arquivos de banco de dados
create_database_files() {
    log_info "Criando arquivos do banco de dados..."
    
    cd /var/www/sincronizador-vod
    
    # ==========================================
    # database/schema.sql
    # ==========================================
    cat > database/schema.sql << 'EOF'
-- ==========================================
-- SCHEMA DO SISTEMA SINCRONIZADOR VOD XUI ONE
-- Banco de dados: sincronizador_vod
-- ==========================================

-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS sincronizador_vod 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE sincronizador_vod;

-- ==========================================
-- TABELA: users (Usuários do sistema)
-- ==========================================
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
    deleted_at TIMESTAMP NULL,
    INDEX idx_parent_id (parent_id),
    INDEX idx_user_type (user_type),
    INDEX idx_is_active (is_active),
    FOREIGN KEY (parent_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: user_profiles (Perfis de usuários)
-- ==========================================
CREATE TABLE user_profiles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT UNIQUE NOT NULL,
    full_name VARCHAR(255),
    phone VARCHAR(20),
    address TEXT,
    company VARCHAR(255),
    website VARCHAR(255),
    avatar_url VARCHAR(500),
    notifications_enabled BOOLEAN DEFAULT TRUE,
    language VARCHAR(10) DEFAULT 'pt-BR',
    timezone VARCHAR(50) DEFAULT 'America/Sao_Paulo',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: licenses (Licenças do sistema)
-- ==========================================
CREATE TABLE licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_key VARCHAR(100) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    product_name VARCHAR(100) DEFAULT 'Sincronizador VOD XUI One',
    license_type ENUM('trial', 'basic', 'professional', 'enterprise') DEFAULT 'basic',
    max_users INT DEFAULT 1,
    max_connections INT DEFAULT 1,
    expires_at DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    activation_date TIMESTAMP NULL,
    last_check TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_expires_at (expires_at),
    INDEX idx_is_active (is_active),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: xui_connections (Conexões XUI)
-- ==========================================
CREATE TABLE xui_connections (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    connection_name VARCHAR(100) NOT NULL,
    xui_ip VARCHAR(45) NOT NULL,
    xui_port INT DEFAULT 3306,
    db_user VARCHAR(100) NOT NULL,
    db_password VARCHAR(255) NOT NULL,
    db_name VARCHAR(100) DEFAULT 'xui',
    ssl_enabled BOOLEAN DEFAULT FALSE,
    ssl_ca VARCHAR(500),
    ssl_cert VARCHAR(500),
    ssl_key VARCHAR(500),
    test_status ENUM('success', 'failed', 'pending') DEFAULT 'pending',
    test_message TEXT,
    last_test TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    sync_settings JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_is_active (is_active),
    INDEX idx_is_default (is_default),
    UNIQUE KEY unique_user_connection (user_id, connection_name),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: m3u_lists (Listas M3U)
-- ==========================================
CREATE TABLE m3u_lists (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    list_name VARCHAR(100) NOT NULL,
    list_description TEXT,
    m3u_content LONGTEXT NOT NULL,
    source_url VARCHAR(500),
    file_name VARCHAR(255),
    file_size INT DEFAULT 0,
    total_items INT DEFAULT 0,
    movies_count INT DEFAULT 0,
    series_count INT DEFAULT 0,
    other_count INT DEFAULT 0,
    parsing_errors INT DEFAULT 0,
    last_scanned TIMESTAMP NULL,
    scan_duration INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    scan_results JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_is_active (is_active),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: detected_categories (Categorias detectadas)
-- ==========================================
CREATE TABLE detected_categories (
    id INT PRIMARY KEY AUTO_INCREMENT,
    m3u_list_id INT NOT NULL,
    category_type ENUM('movie', 'series', 'other') NOT NULL,
    category_name VARCHAR(200) NOT NULL,
    items_count INT DEFAULT 0,
    selected_for_sync BOOLEAN DEFAULT FALSE,
    sync_priority INT DEFAULT 5,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_m3u_list_id (m3u_list_id),
    INDEX idx_category_type (category_type),
    INDEX idx_selected_for_sync (selected_for_sync),
    UNIQUE KEY unique_category (m3u_list_id, category_type, category_name),
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: schedules (Agendamentos)
-- ==========================================
CREATE TABLE schedules (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    schedule_name VARCHAR(100) NOT NULL,
    schedule_type ENUM('daily', 'weekly', 'monthly', 'custom') DEFAULT 'daily',
    schedule_time TIME NOT NULL,
    days_of_week VARCHAR(20) DEFAULT '1,2,3,4,5,6,7',
    days_of_month VARCHAR(100) DEFAULT '',
    m3u_list_id INT NULL,
    categories JSON,
    sync_type ENUM('full', 'incremental') DEFAULT 'incremental',
    enabled BOOLEAN DEFAULT TRUE,
    last_run TIMESTAMP NULL,
    next_run TIMESTAMP NULL,
    last_run_duration INT DEFAULT 0,
    last_run_status ENUM('success', 'failed', 'running') DEFAULT NULL,
    last_run_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_enabled (enabled),
    INDEX idx_next_run (next_run),
    INDEX idx_last_run_status (last_run_status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: sync_logs (Logs de sincronização)
-- ==========================================
CREATE TABLE sync_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    sync_type ENUM('manual', 'auto', 'api') NOT NULL,
    schedule_id INT NULL,
    xui_connection_id INT NULL,
    m3u_list_id INT NULL,
    items_total INT DEFAULT 0,
    items_processed INT DEFAULT 0,
    items_added INT DEFAULT 0,
    items_updated INT DEFAULT 0,
    items_skipped INT DEFAULT 0,
    items_failed INT DEFAULT 0,
    duration_seconds INT DEFAULT 0,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    status ENUM('running', 'completed', 'failed', 'cancelled') DEFAULT 'running',
    error_message TEXT,
    log_details JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_sync_type (sync_type),
    INDEX idx_schedule_id (schedule_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE SET NULL,
    FOREIGN KEY (xui_connection_id) REFERENCES xui_connections(id) ON DELETE SET NULL,
    FOREIGN KEY (m3u_list_id) REFERENCES m3u_lists(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: sync_items (Itens sincronizados)
-- ==========================================
CREATE TABLE sync_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    sync_log_id INT NOT NULL,
    item_type ENUM('movie', 'series', 'other') NOT NULL,
    item_name VARCHAR(500) NOT NULL,
    item_category VARCHAR(200),
    xui_content_id VARCHAR(100),
    operation ENUM('add', 'update', 'skip', 'error') NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    error_message TEXT,
    metadata JSON,
    processing_time INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sync_log_id (sync_log_id),
    INDEX idx_operation (operation),
    INDEX idx_status (status),
    INDEX idx_item_type (item_type),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (sync_log_id) REFERENCES sync_logs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: system_settings (Configurações do sistema)
-- ==========================================
CREATE TABLE system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type ENUM('string', 'int', 'bool', 'json', 'array') DEFAULT 'string',
    category VARCHAR(50) DEFAULT 'general',
    is_public BOOLEAN DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_setting_key (setting_key),
    INDEX idx_category (category),
    INDEX idx_is_public (is_public)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: api_keys (Chaves da API)
-- ==========================================
CREATE TABLE api_keys (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    api_key VARCHAR(100) UNIQUE NOT NULL,
    api_secret VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    permissions JSON,
    last_used TIMESTAMP NULL,
    usage_count INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_api_key (api_key),
    INDEX idx_is_active (is_active),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: audit_logs (Logs de auditoria)
-- ==========================================
CREATE TABLE audit_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INT,
    details JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_action (action),
    INDEX idx_created_at (created_at),
    INDEX idx_entity (entity_type, entity_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- TABELA: notifications (Notificações)
-- ==========================================
CREATE TABLE notifications (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    notification_type ENUM('info', 'success', 'warning', 'error') DEFAULT 'info',
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    action_url VARCHAR(500),
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_is_read (is_read),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- DADOS INICIAIS
-- ==========================================

-- Inserir usuário administrador padrão (senha: Admin@2024)
-- A senha será hasheada pelo sistema
INSERT INTO users (username, email, password, user_type, is_active) VALUES
('admin', 'admin@sincronizador.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'admin', TRUE);

-- Inserir perfil do administrador
INSERT INTO user_profiles (user_id, full_name, language, timezone) VALUES
(1, 'Administrador do Sistema', 'pt-BR', 'America/Sao_Paulo');

-- Inserir licença padrão
INSERT INTO licenses (license_key, user_id, license_type, max_users, max_connections, expires_at, is_active, activation_date) VALUES
('DEMO-LICENSE-KEY-2024', 1, 'professional', 10, 5, DATE_ADD(CURDATE(), INTERVAL 365 DAY), TRUE, NOW());

-- Inserir configurações do sistema
INSERT INTO system_settings (setting_key, setting_value, setting_type, category, is_public, description) VALUES
-- Configurações gerais
('app_name', 'Sincronizador VOD XUI One', 'string', 'general', TRUE, 'Nome do aplicativo'),
('app_version', '1.0.0', 'string', 'general', TRUE, 'Versão do aplicativo'),
('maintenance_mode', 'false', 'bool', 'general', TRUE, 'Modo de manutenção'),
('default_language', 'pt-BR', 'string', 'general', TRUE, 'Idioma padrão'),
('timezone', 'America/Sao_Paulo', 'string', 'general', TRUE, 'Fuso horário padrão'),
('date_format', 'd/m/Y', 'string', 'general', TRUE, 'Formato de data'),
('time_format', 'H:i', 'string', 'general', TRUE, 'Formato de hora'),

-- Configurações do TMDb
('tmdb_api_key', '', 'string', 'tmdb', FALSE, 'Chave da API TMDb'),
('tmdb_language', 'pt-BR', 'string', 'tmdb', FALSE, 'Idioma do TMDb'),
('tmdb_region', 'BR', 'string', 'tmdb', FALSE, 'Região do TMDb'),
('tmdb_cache_duration', '86400', 'int', 'tmdb', FALSE, 'Duração do cache em segundos'),

-- Configurações de sincronização
('sync_batch_size', '50', 'int', 'sync', FALSE, 'Tamanho do lote de sincronização'),
('max_retry_attempts', '3', 'int', 'sync', FALSE, 'Tentativas máximas de retry'),
('sync_timeout', '300', 'int', 'sync', FALSE, 'Timeout da sincronização em segundos'),
('auto_cleanup_days', '30', 'int', 'sync', FALSE, 'Dias para limpeza automática de logs'),

-- Configurações de e-mail
('smtp_host', '', 'string', 'email', FALSE, 'Servidor SMTP'),
('smtp_port', '587', 'int', 'email', FALSE, 'Porta SMTP'),
('smtp_username', '', 'string', 'email', FALSE, 'Usuário SMTP'),
('smtp_password', '', 'string', 'email', FALSE, 'Senha SMTP'),
('smtp_encryption', 'tls', 'string', 'email', FALSE, 'Criptografia SMTP'),
('email_from', 'noreply@sincronizador.com', 'string', 'email', FALSE, 'E-mail remetente'),
('email_from_name', 'Sincronizador VOD', 'string', 'email', FALSE, 'Nome do remetente'),

-- Configurações de segurança
('session_lifetime', '1440', 'int', 'security', FALSE, 'Tempo de vida da sessão em minutos'),
('login_attempts', '5', 'int', 'security', FALSE, 'Tentativas de login permitidas'),
('login_lockout', '15', 'int', 'security', FALSE, 'Tempo de bloqueio em minutos'),
('password_min_length', '8', 'int', 'security', TRUE, 'Comprimento mínimo da senha'),
('password_require_numbers', 'true', 'bool', 'security', TRUE, 'Requer números na senha'),
('password_require_special_chars', 'true', 'bool', 'security', TRUE, 'Requer caracteres especiais'),

-- Configurações do painel
('dashboard_refresh_interval', '30', 'int', 'dashboard', TRUE, 'Intervalo de atualização do dashboard em segundos'),
('items_per_page', '25', 'int', 'dashboard', TRUE, 'Itens por página'),
('default_theme', 'dark', 'string', 'dashboard', TRUE, 'Tema padrão'),

-- Configurações de notificação
('notify_on_sync_complete', 'true', 'bool', 'notifications', FALSE, 'Notificar ao completar sincronização'),
('notify_on_sync_error', 'true', 'bool', 'notifications', FALSE, 'Notificar em erro de sincronização'),
('notify_on_license_expiry', 'true', 'bool', 'notifications', FALSE, 'Notificar antes da expiração da licença');

-- ==========================================
-- VIEWS ÚTEIS
-- ==========================================

-- View para estatísticas do usuário
CREATE VIEW user_stats AS
SELECT 
    u.id,
    u.username,
    u.user_type,
    COUNT(DISTINCT xc.id) as xui_connections_count,
    COUNT(DISTINCT ml.id) as m3u_lists_count,
    COUNT(DISTINCT s.id) as schedules_count,
    COUNT(DISTINCT sl.id) as sync_logs_count,
    MAX(sl.created_at) as last_sync_date
FROM users u
LEFT JOIN xui_connections xc ON u.id = xc.user_id AND xc.is_active = TRUE
LEFT JOIN m3u_lists ml ON u.id = ml.user_id
LEFT JOIN schedules s ON u.id = s.user_id AND s.enabled = TRUE
LEFT JOIN sync_logs sl ON u.id = sl.user_id
GROUP BY u.id, u.username, u.user_type;

-- View para resumo de sincronizações
CREATE VIEW sync_summary AS
SELECT 
    DATE(sl.created_at) as sync_date,
    sl.user_id,
    u.username,
    sl.sync_type,
    COUNT(*) as total_syncs,
    SUM(sl.items_total) as total_items,
    SUM(sl.items_added) as items_added,
    SUM(sl.items_updated) as items_updated,
    SUM(sl.items_failed) as items_failed,
    AVG(sl.duration_seconds) as avg_duration,
    SUM(CASE WHEN sl.status = 'completed' THEN 1 ELSE 0 END) as successful_syncs,
    SUM(CASE WHEN sl.status = 'failed' THEN 1 ELSE 0 END) as failed_syncs
FROM sync_logs sl
JOIN users u ON sl.user_id = u.id
GROUP BY DATE(sl.created_at), sl.user_id, u.username, sl.sync_type;

-- View para próximos agendamentos
CREATE VIEW upcoming_schedules AS
SELECT 
    s.*,
    u.username,
    ml.list_name,
    TIMESTAMP(DATE(NOW()), s.schedule_time) as next_execution
FROM schedules s
JOIN users u ON s.user_id = u.id
LEFT JOIN m3u_lists ml ON s.m3u_list_id = ml.id
WHERE s.enabled = TRUE
AND (s.next_run IS NULL OR s.next_run > NOW())
ORDER BY s.schedule_time;

-- ==========================================
-- PROCEDURES ÚTEIS
-- ==========================================

-- Procedure para limpar logs antigos
DELIMITER //
CREATE PROCEDURE cleanup_old_logs(IN days_to_keep INT)
BEGIN
    -- Limpar logs de sincronização
    DELETE FROM sync_logs 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY)
    AND status != 'running';
    
    -- Limpar itens de sincronização
    DELETE si FROM sync_items si
    LEFT JOIN sync_logs sl ON si.sync_log_id = sl.id
    WHERE sl.id IS NULL OR sl.created_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    
    -- Limpar logs de auditoria
    DELETE FROM audit_logs 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    
    -- Limpar notificações lidas antigas
    DELETE FROM notifications 
    WHERE is_read = TRUE 
    AND created_at < DATE_SUB(NOW(), INTERVAL 30 DAY);
END //
DELIMITER ;

-- Procedure para atualizar próximo agendamento
DELIMITER //
CREATE PROCEDURE update_next_schedule_run(IN schedule_id INT)
BEGIN
    DECLARE s_type VARCHAR(20);
    DECLARE s_time TIME;
    DECLARE s_days VARCHAR(20);
    DECLARE next_date DATE;
    
    SELECT schedule_type, schedule_time, days_of_week 
    INTO s_type, s_time, s_days
    FROM schedules WHERE id = schedule_id;
    
    SET next_date = CURDATE();
    
    IF s_type = 'daily' THEN
        SET next_date = DATE_ADD(next_date, INTERVAL 1 DAY);
    ELSEIF s_type = 'weekly' THEN
        -- Encontrar próximo dia da semana válido
        SET next_date = DATE_ADD(next_date, INTERVAL 1 DAY);
        WHILE FIND_IN_SET(DAYOFWEEK(next_date), s_days) = 0 DO
            SET next_date = DATE_ADD(next_date, INTERVAL 1 DAY);
        END WHILE;
    END IF;
    
    UPDATE schedules 
    SET next_run = TIMESTAMP(next_date, s_time)
    WHERE id = schedule_id;
END //
DELIMITER ;

-- ==========================================
-- TRIGGERS ÚTEIS
-- ==========================================

-- Trigger para auditoria de usuários
DELIMITER //
CREATE TRIGGER users_audit_trigger
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    IF OLD.is_active != NEW.is_active THEN
        INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
        VALUES (
            NEW.id,
            CONCAT('user_', IF(NEW.is_active, 'activated', 'deactivated')),
            'user',
            NEW.id,
            JSON_OBJECT(
                'old_status', OLD.is_active,
                'new_status', NEW.is_active,
                'changed_at', NOW()
            )
        );
    END IF;
END //
DELIMITER ;

-- Trigger para log de sincronização
DELIMITER //
CREATE TRIGGER sync_log_complete_trigger
AFTER UPDATE ON sync_logs
FOR EACH ROW
BEGIN
    IF OLD.status = 'running' AND NEW.status = 'completed' THEN
        -- Atualizar tempo de execução
        SET NEW.end_time = NOW();
        SET NEW.duration_seconds = TIMESTAMPDIFF(SECOND, NEW.start_time, NEW.end_time);
        
        -- Criar notificação para o usuário
        INSERT INTO notifications (user_id, notification_type, title, message, action_url)
        VALUES (
            NEW.user_id,
            'success',
            'Sincronização Concluída',
            CONCAT('Sincronização ', NEW.sync_type, ' concluída com sucesso. ',
                   NEW.items_added, ' adicionados, ',
                   NEW.items_updated, ' atualizados, ',
                   NEW.items_failed, ' falhas.'),
            CONCAT('/logs.php?log_id=', NEW.id)
        );
    END IF;
END //
DELIMITER ;

-- ==========================================
-- ÍNDICES ADICIONAIS PARA PERFORMANCE
-- ==========================================

-- Índices para queries frequentes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_xui_connections_last_test ON xui_connections(last_test);
CREATE INDEX idx_m3u_lists_last_scanned ON m3u_lists(last_scanned);
CREATE INDEX idx_schedules_last_run ON schedules(last_run);
CREATE INDEX idx_sync_logs_start_time ON sync_logs(start_time);
CREATE INDEX idx_sync_items_sync_log_id_status ON sync_items(sync_log_id, status);
CREATE INDEX idx_notifications_user_read ON notifications(user_id, is_read);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- ==========================================
-- FIM DO SCHEMA
-- ==========================================
EOF

    # ==========================================
    # database/seed.sql (Dados iniciais)
    # ==========================================
    cat > database/seed.sql << 'EOF'
-- ==========================================
-- DADOS INICIAIS PARA SISTEMA SINCRONIZADOR VOD
-- ==========================================

USE sincronizador_vod;

-- Inserir mais usuários de exemplo
INSERT INTO users (username, email, password, user_type, parent_id, is_active) VALUES
-- Revendedor 1
('revendedor1', 'revendedor1@exemplo.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'revendedor', 1, TRUE),

-- Usuários do revendedor 1
('cliente1', 'cliente1@exemplo.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'usuario', 2, TRUE),
('cliente2', 'cliente2@exemplo.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'usuario', 2, TRUE),

-- Revendedor 2
('revendedor2', 'revendedor2@exemplo.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'revendedor', 1, TRUE),

-- Usuários do revendedor 2
('cliente3', 'cliente3@exemplo.com', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 'usuario', 5, TRUE);

-- Inserir perfis para os novos usuários
INSERT INTO user_profiles (user_id, full_name, phone, company) VALUES
(2, 'Revendedor Master', '(11) 99999-9999', 'IPTV Solutions'),
(3, 'Cliente Premium 1', '(21) 98888-8888', 'Empresa A'),
(4, 'Cliente Premium 2', '(31) 97777-7777', 'Empresa B'),
(5, 'Revendedor Gold', '(41) 96666-6666', 'Streaming Pro'),
(6, 'Cliente VIP', '(51) 95555-5555', 'Empresa C');

-- Inserir conexões XUI de exemplo
INSERT INTO xui_connections (user_id, connection_name, xui_ip, xui_port, db_user, db_password, db_name, test_status, is_active, is_default) VALUES
-- Conexões para admin
(1, 'Servidor Principal', '192.168.1.100', 3306, 'xui_admin', 'senha_forte_123', 'xui', 'success', TRUE, TRUE),
(1, 'Servidor Backup', '192.168.1.101', 3306, 'xui_user', 'outra_senha_456', 'xui_backup', 'success', TRUE, FALSE),

-- Conexão para revendedor 1
(2, 'Meu XUI Principal', '10.0.0.50', 3306, 'revendedor_xui', 'minha_senha_789', 'xui', 'success', TRUE, TRUE),

-- Conexão para cliente 1
(3, 'Servidor do Cliente', '172.16.0.10', 3306, 'cliente_user', 'cliente_pass_123', 'xui', 'success', TRUE, TRUE);

-- Inserir listas M3U de exemplo
INSERT INTO m3u_lists (user_id, list_name, list_description, m3u_content, total_items, movies_count, series_count, last_scanned) VALUES
(1, 'Lista Premium Global', 'Lista completa com filmes e séries internacionais', '#EXTM3U\n#EXTINF:-1 tvg-id="Movie1" group-title="Ação",Filme de Ação 1 (2023)\nhttp://exemplo.com/filme1.mp4', 1000, 600, 400, NOW()),
(1, 'Lista Nacional', 'Conteúdo brasileiro e português', '#EXTM33U\n#EXTINF:-1 tvg-id="Series1" group-title="Novelas",Novela Brasileira S01E01\nhttp://exemplo.com/novela1.mp4', 500, 200, 300, NOW()),
(2, 'Lista Revendedor', 'Conteúdo para revenda', '#EXTM3U\n#EXTINF:-1 tvg-id="Movie2" group-title="Ficção",Filme Ficção 1 (2022)\nhttp://exemplo.com/filme2.mp4', 800, 400, 400, NOW());

-- Inserir categorias detectadas de exemplo
INSERT INTO detected_categories (m3u_list_id, category_type, category_name, items_count, selected_for_sync) VALUES
-- Categorias da lista 1 (Filmes)
(1, 'movie', 'Ação', 150, TRUE),
(1, 'movie', 'Comédia', 120, TRUE),
(1, 'movie', 'Drama', 90, TRUE),
(1, 'movie', 'Ficção Científica', 80, FALSE),
(1, 'movie', 'Terror', 60, TRUE),

-- Categorias da lista 1 (Séries)
(1, 'series', 'Drama', 100, TRUE),
(1, 'series', 'Comédia', 80, TRUE),
(1, 'series', 'Ficção Científica', 70, TRUE),
(1, 'series', 'Animação', 50, FALSE),
(1, 'series', 'Documentário', 30, TRUE),

-- Categorias da lista 2
(2, 'movie', 'Nacional', 120, TRUE),
(2, 'movie', 'Internacional', 80, FALSE),
(2, 'series', 'Novelas', 150, TRUE),
(2, 'series', 'Séries Nacionais', 50, TRUE),

-- Categorias da lista 3
(3, 'movie', 'Lançamentos', 200, TRUE),
(3, 'movie', 'Clássicos', 100, TRUE),
(3, 'series', 'Séries Premium', 150, TRUE),
(3, 'series', 'Infantil', 50, FALSE);

-- Inserir agendamentos de exemplo
INSERT INTO schedules (user_id, schedule_name, schedule_type, schedule_time, days_of_week, m3u_list_id, enabled, next_run) VALUES
(1, 'Sincronização Diária', 'daily', '02:00:00', '1,2,3,4,5,6,7', 1, TRUE, TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '02:00:00')),
(1, 'Sincronização Fim de Semana', 'weekly', '03:00:00', '6,7', 2, TRUE, TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL (6 - WEEKDAY(CURDATE())) DAY), '03:00:00')),
(2, 'Sincronização Revendedor', 'daily', '04:00:00', '1,2,3,4,5', 3, TRUE, TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '04:00:00')),
(3, 'Sincronização Cliente', 'daily', '01:00:00', '1,2,3,4,5,6,7', NULL, FALSE, NULL);

-- Inserir logs de sincronização de exemplo
INSERT INTO sync_logs (user_id, sync_type, schedule_id, xui_connection_id, m3u_list_id, items_total, items_processed, items_added, items_updated, items_failed, duration_seconds, status, start_time, end_time) VALUES
(1, 'manual', NULL, 1, 1, 1000, 1000, 450, 300, 250, 1800, 'completed', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY) + INTERVAL 1800 SECOND),
(1, 'auto', 1, 1, 1, 50, 50, 10, 35, 5, 300, 'completed', DATE_SUB(NOW(), INTERVAL 12 HOUR), DATE_SUB(NOW(), INTERVAL 12 HOUR) + INTERVAL 300 SECOND),
(1, 'manual', NULL, 2, 2, 500, 480, 200, 250, 30, 1200, 'completed', DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY) + INTERVAL 1200 SECOND),
(2, 'manual', NULL, 3, 3, 800, 800, 350, 400, 50, 2400, 'completed', DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY) + INTERVAL 2400 SECOND),
(1, 'auto', 2, 1, 1, 100, 95, 25, 60, 10, 600, 'failed', DATE_SUB(NOW(), INTERVAL 6 HOUR), DATE_SUB(NOW(), INTERVAL 6 HOUR) + INTERVAL 600 SECOND);

-- Inserir itens de sincronização de exemplo
INSERT INTO sync_items (sync_log_id, item_type, item_name, item_category, operation, status, metadata) VALUES
(1, 'movie', 'Avengers: Endgame (2019)', 'Ação', 'add', 'completed', '{"tmdb_id": 299534, "year": 2019, "rating": 8.4}'),
(1, 'movie', 'The Irishman (2019)', 'Drama', 'update', 'completed', '{"tmdb_id": 398978, "year": 2019, "rating": 7.8}'),
(1, 'series', 'Stranger Things S04', 'Ficção Científica', 'add', 'completed', '{"tmdb_id": 66732, "season": 4, "episodes": 9}'),
(2, 'movie', 'Dune (2021)', 'Ficção Científica', 'add', 'completed', '{"tmdb_id": 438631, "year": 2021, "rating": 8.0}'),
(2, 'series', 'The Crown S04', 'Drama', 'update', 'completed', '{"tmdb_id": 65494, "season": 4, "episodes": 10}'),
(3, 'movie', 'Cidade de Deus (2002)', 'Nacional', 'add', 'completed', '{"tmdb_id": 598, "year": 2002, "rating": 8.6}'),
(4, 'movie', 'The Batman (2022)', 'Ação', 'add', 'completed', '{"tmdb_id": 414906, "year": 2022, "rating": 7.8}'),
(5, 'movie', 'Titanic (1997)', 'Drama', 'error', 'failed', '{"error": "Erro de conexão com XUI"}');

-- Inserir chaves API de exemplo
INSERT INTO api_keys (user_id, api_key, api_secret, name, permissions, is_active) VALUES
(1, 'admin_key_123', 'secret_hash_abc', 'API Administrativa', '["users:read", "users:write", "sync:all"]', TRUE),
(2, 'reseller_key_456', 'secret_hash_def', 'API Revendedor', '["sync:read", "sync:write", "content:read"]', TRUE),
(3, 'client_key_789', 'secret_hash_ghi', 'API Cliente', '["sync:read", "content:read"]', TRUE);

-- Inserir logs de auditoria de exemplo
INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details, ip_address, user_agent) VALUES
(1, 'user_login', 'user', 1, '{"browser": "Chrome", "os": "Windows 10"}', '192.168.1.1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124'),
(1, 'sync_started', 'sync', 1, '{"type": "manual", "items": 1000}', '192.168.1.1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124'),
(2, 'user_created', 'user', 3, '{"username": "cliente1", "email": "cliente1@exemplo.com"}', '10.0.0.50', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/14.0.3'),
(1, 'settings_updated', 'system', NULL, '{"setting": "tmdb_api_key", "changed_by": "admin"}', '192.168.1.1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124');

-- Inserir notificações de exemplo
INSERT INTO notifications (user_id, notification_type, title, message, is_read, action_url) VALUES
(1, 'success', 'Sincronização Concluída', 'Sincronização manual concluída com sucesso: 450 adicionados, 300 atualizados, 250 falhas.', FALSE, '/logs.php?log_id=1'),
(1, 'warning', 'Licença Expirando', 'Sua licença expira em 15 dias. Renove para continuar usando todos os recursos.', FALSE, '/license.php'),
(2, 'info', 'Novo Cliente', 'Cliente "cliente1" foi criado com sucesso em sua conta.', TRUE, '/clients.php?id=3'),
(1, 'error', 'Falha na Sincronização', 'A sincronização automática das 02:00 falhou. Verifique os logs para mais detalhes.', FALSE, '/logs.php?log_id=5');

-- ==========================================
-- ATUALIZAÇÕES PÓS-INSERÇÃO
-- ==========================================

-- Atualizar estatísticas das listas M3U baseado nas categorias
UPDATE m3u_lists ml
JOIN (
    SELECT 
        m3u_list_id,
        SUM(CASE WHEN category_type = 'movie' THEN items_count ELSE 0 END) as movies,
        SUM(CASE WHEN category_type = 'series' THEN items_count ELSE 0 END) as series,
        SUM(CASE WHEN category_type = 'other' THEN items_count ELSE 0 END) as other,
        SUM(items_count) as total
    FROM detected_categories
    GROUP BY m3u_list_id
) stats ON ml.id = stats.m3u_list_id
SET 
    ml.movies_count = stats.movies,
    ml.series_count = stats.series,
    ml.other_count = stats.other,
    ml.total_items = stats.total;

-- Atualizar últimos logins
UPDATE users SET last_login = NOW(), login_count = 10 WHERE id = 1;
UPDATE users SET last_login = DATE_SUB(NOW(), INTERVAL 1 DAY), login_count = 5 WHERE id = 2;
UPDATE users SET last_login = DATE_SUB(NOW(), INTERVAL 2 DAY), login_count = 3 WHERE id = 3;
UPDATE users SET last_login = DATE_SUB(NOW(), INTERVAL 3 DAY), login_count = 2 WHERE id = 4;
UPDATE users SET last_login = DATE_SUB(NOW(), INTERVAL 4 DAY), login_count = 1 WHERE id = 5;
UPDATE users SET last_login = DATE_SUB(NOW(), INTERVAL 5 DAY), login_count = 1 WHERE id = 6;

-- ==========================================
-- RELATÓRIO DE VERIFICAÇÃO
-- ==========================================

SELECT '=== VERIFICAÇÃO DE DADOS INICIAIS ===' as info;

SELECT 'Usuários:' as tabela, COUNT(*) as quantidade FROM users
UNION ALL
SELECT 'Conexões XUI:', COUNT(*) FROM xui_connections
UNION ALL
SELECT 'Listas M3U:', COUNT(*) FROM m3u_lists
UNION ALL
SELECT 'Categorias:', COUNT(*) FROM detected_categories
UNION ALL
SELECT 'Agendamentos:', COUNT(*) FROM schedules
UNION ALL
SELECT 'Logs Sync:', COUNT(*) FROM sync_logs
UNION ALL
SELECT 'Itens Sync:', COUNT(*) FROM sync_items
UNION ALL
SELECT 'Notificações:', COUNT(*) FROM notifications;

SELECT '=== DADOS DO ADMINISTRADOR ===' as info;
SELECT 
    u.username,
    u.email,
    u.user_type,
    up.full_name,
    l.license_key,
    l.expires_at,
    (SELECT COUNT(*) FROM xui_connections WHERE user_id = u.id) as conexoes_xui,
    (SELECT COUNT(*) FROM m3u_lists WHERE user_id = u.id) as listas_m3u,
    (SELECT COUNT(*) FROM schedules WHERE user_id = u.id) as agendamentos
FROM users u
LEFT JOIN user_profiles up ON u.id = up.user_id
LEFT JOIN licenses l ON u.id = l.user_id
WHERE u.id = 1;

-- ==========================================
-- FIM DOS DADOS INICIAIS
-- ==========================================
EOF

    log_success "Arquivos do banco de dados criados"
}

# Configurar Nginx
setup_nginx() {
    log_info "Configurando Nginx..."
    
    # Criar configuração do Nginx
    cat > /etc/nginx/sites-available/sincronizador-vod << 'EOF'
# ==========================================
# CONFIGURAÇÃO NGINX - SINCRONIZADOR VOD XUI ONE
# ==========================================

server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    root /var/www/sincronizador-vod/frontend/public;
    index index.php index.html index.htm;
    
    # Logs
    access_log /var/log/nginx/sincronizador-vod.access.log;
    error_log /var/log/nginx/sincronizador-vod.error.log;
    
    # Configurações de segurança
    server_tokens off;
    
    # Headers de segurança
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    # Configurações do cliente
    client_max_body_size 100M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    
    # Configurações de buffer
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # Configurações de timeout
    send_timeout 300s;
    keepalive_timeout 65;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Frontend PHP
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    # Arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files $uri =404;
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
        
        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Buffer
        proxy_buffers 16 16k;
        proxy_buffer_size 32k;
    }
    
    # WebSocket para atualizações em tempo real
    location /socket.io/ {
        proxy_pass http://127.0.0.1:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
    
    # PHP-FPM
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        
        include fastcgi_params;
        
        # Timeouts
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
        fastcgi_connect_timeout 300s;
        
        # Buffer
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
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

# Redirecionar HTTP para HTTPS (quando habilitado)
# server {
#     listen 80;
#     server_name seu-dominio.com;
#     return 301 https://$server_name$request_uri;
# }
EOF
    
    # Remover configuração padrão do Nginx
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
    
    # Configurar pool PHP-FPM
    cat > /etc/php/8.1/fpm/pool.d/sincronizador-vod.conf << 'EOF'
[sincronizador-vod]
user = www-data
group = www-data

listen = /var/run/php/php8.1-fpm-sincronizador.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 5
pm.min_spare_servers = 3
pm.max_spare_servers = 10

pm.max_requests = 500

chdir = /

security.limit_extensions = .php .php7 .php8 .php81

php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[memory_limit] = 256M

php_flag[display_errors] = off
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php8.1-fpm-sincronizador-error.log
php_admin_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT

env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
EOF
    
    # Configurações adicionais do PHP
    cat >> /etc/php/8.1/fpm/php.ini << 'EOF'

; Configurações específicas do Sincronizador VOD
date.timezone = America/Sao_Paulo
session.gc_maxlifetime = 1440
session.cookie_secure = 0
session.cookie_httponly = 1
session.cookie_samesite = Lax

upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
max_input_time = 300
memory_limit = 256M

display_errors = Off
log_errors = On
error_log = /var/log/php8.1-fpm-error.log
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
EOF
    
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
Documentation=https://sincronizador-vod.com
After=network.target mysql.service
Requires=mysql.service

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

# Configurar permissões
setup_permissions() {
    log_info "Configurando permissões..."
    
    # Definir proprietário
    chown -R www-data:www-data /var/www/sincronizador-vod
    
    # Configurar permissões
    find /var/www/sincronizador-vod -type d -exec chmod 755 {} \;
    find /var/www/sincronizador-vod -type f -exec chmod 644 {} \;
    
    # Permissões especiais
    chmod 755 /var/www/sincronizador-vod/backend/src/app.js
    chmod 755 /var/www/sincronizador-vod/frontend/public/index.php
    chmod 755 /var/www/sincronizador-vod/frontend/public/login.php
    
    # Diretórios de logs e uploads com permissões de escrita
    chmod 775 /var/www/sincronizador-vod/backend/logs
    chmod 775 /var/www/sincronizador-vod/logs
    chmod 775 /var/www/sincronizador-vod/frontend/uploads
    
    # Criar link simbólico para logs
    ln -sf /var/www/sincronizador-vod/backend/logs /var/log/sincronizador-vod
    
    log_success "Permissões configuradas"
}

# Instalar dependências do Node.js
install_node_dependencies() {
    log_info "Instalando dependências do Node.js..."
    
    cd /var/www/sincronizador-vod/backend
    
    # Copiar .env.example para .env
    cp .env.example .env
    
    # Gerar chaves JWT secretas
    jwt_secret=$(openssl rand -hex 32)
    session_secret=$(openssl rand -hex 32)
    
    # Atualizar .env com valores reais
    sed -i "s|your_super_secret_jwt_key_change_in_production_@2024!|${jwt_secret}|g" .env
    sed -i "s|session_secret_change_in_production|${session_secret}|g" .env
    sed -i "s|VodSync@2024|${DB_PASSWORD}|g" .env
    
    # Instalar dependências
    npm install --production
    
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
    
    # Importar dados iniciais
    mysql -u root -p${DB_ROOT_PASSWORD} sincronizador_vod < /var/www/sincronizador-vod/database/seed.sql
    
    if [ $? -eq 0 ]; then
        log_success "Dados iniciais importados"
    else
        log_warning "Alguns dados iniciais podem não ter sido importados"
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

# Configurar cron jobs
setup_cron_jobs() {
    log_info "Configurando cron jobs..."
    
    # Backup diário do banco de dados
    cat > /etc/cron.daily/sincronizador-vod-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/www/sincronizador-vod/backups"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="sincronizador_vod"

mkdir -p $BACKUP_DIR

# Backup do banco de dados
mysqldump -u vod_user -pVodSync@2024 $DB_NAME | gzip > $BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz

# Manter apenas últimos 7 backups
ls -tp $BACKUP_DIR/*.sql.gz | tail -n +8 | xargs -I {} rm -- {}

# Backup dos logs
tar -czf $BACKUP_DIR/logs_${DATE}.tar.gz /var/www/sincronizador-vod/logs/ 2>/dev/null || true

# Limpar logs antigos (mais de 30 dias)
find /var/www/sincronizador-vod/logs -name "*.log" -mtime +30 -delete
EOF
    
    chmod +x /etc/cron.daily/sincronizador-vod-backup
    
    # Verificação de saúde do sistema
    cat > /etc/cron.hourly/sincronizador-vod-health << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/sincronizador-vod/health.log"

# Verificar se o serviço Node.js está rodando
if ! systemctl is-active --quiet sincronizador-vod; then
    echo "$(date): Serviço Node.js parado, reiniciando..." >> $LOG_FILE
    systemctl restart sincronizador-vod
fi

# Verificar se o Nginx está rodando
if ! systemctl is-active --quiet nginx; then
    echo "$(date): Serviço Nginx parado, reiniciando..." >> $LOG_FILE
    systemctl restart nginx
fi

# Verificar se o MySQL está rodando
if ! systemctl is-active --quiet mysql; then
    echo "$(date): Serviço MySQL parado, reiniciando..." >> $LOG_FILE
    systemctl restart mysql
fi
EOF
    
    chmod +x /etc/cron.hourly/sincronizador-vod-health
    
    log_success "Cron jobs configurados"
}

# Criar script de manutenção
create_maintenance_scripts() {
    log_info "Criando scripts de manutenção..."
    
    cd /var/www/sincronizador-vod/scripts
    
    # Script de backup
    cat > backup.sh << 'EOF'
#!/bin/bash
# Script de backup do Sincronizador VOD

BACKUP_DIR="/var/www/sincronizador-vod/backups"
DATE=$(date +%Y%m%d_%H%M%S)
CONFIG_DIR="/var/www/sincronizador-vod"
DB_NAME="sincronizador_vod"

echo "Iniciando backup do Sincronizador VOD..."
echo "Data/Hora: $(date)"

# Criar diretório de backup
mkdir -p $BACKUP_DIR/$DATE

# Backup do banco de dados
echo "Backup do banco de dados..."
mysqldump -u vod_user -pVodSync@2024 $DB_NAME > $BACKUP_DIR/$DATE/database.sql

# Backup dos arquivos de configuração
echo "Backup dos arquivos de configuração..."
tar -czf $BACKUP_DIR/$DATE/config.tar.gz \
    $CONFIG_DIR/backend/.env \
    $CONFIG_DIR/frontend/config/database.php \
    $CONFIG_DIR/database/

# Backup dos logs
echo "Backup dos logs..."
tar -czf $BACKUP_DIR/$DATE/logs.tar.gz $CONFIG_DIR/logs/ $CONFIG_DIR/backend/logs/

# Criar arquivo único de backup
cd $BACKUP_DIR/$DATE
tar -czf ../sincronizador_vod_backup_$DATE.tar.gz .

# Limpar diretório temporário
cd ..
rm -rf $DATE

echo "Backup concluído: $BACKUP_DIR/sincronizador_vod_backup_$DATE.tar.gz"
echo "Tamanho: $(du -h $BACKUP_DIR/sincronizador_vod_backup_$DATE.tar.gz | cut -f1)"
EOF
    
    # Script de restore
    cat > restore.sh << 'EOF'
#!/bin/bash
# Script de restore do Sincronizador VOD

if [ -z "$1" ]; then
    echo "Uso: $0 <arquivo_de_backup>"
    echo "Exemplo: $0 sincronizador_vod_backup_20240101_120000.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"
BACKUP_DIR="/var/www/sincronizador-vod/backups"
TEMP_DIR="/tmp/restore_$(date +%s)"

if [ ! -f "$BACKUP_FILE" ]; then
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    else
        echo "Arquivo de backup não encontrado: $BACKUP_FILE"
        exit 1
    fi
fi

echo "Iniciando restore do Sincronizador VOD..."
echo "Arquivo: $BACKUP_FILE"

# Criar diretório temporário
mkdir -p $TEMP_DIR

# Extrair backup
echo "Extraindo backup..."
tar -xzf "$BACKUP_FILE" -C $TEMP_DIR

# Restaurar banco de dados
echo "Restaurando banco de dados..."
mysql -u vod_user -pVodSync@2024 sincronizador_vod < $TEMP_DIR/database.sql

# Restaurar arquivos de configuração
echo "Restaurando arquivos de configuração..."
tar -xzf $TEMP_DIR/config.tar.gz -C /

# Restaurar logs (opcional)
read -p "Restaurar logs? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "Restaurando logs..."
    tar -xzf $TEMP_DIR/logs.tar.gz -C /
fi

# Limpar diretório temporário
rm -rf $TEMP_DIR

echo "Restore concluído!"
echo "Reinicie os serviços:"
echo "  systemctl restart sincronizador-vod"
echo "  systemctl restart nginx"
echo "  systemctl restart mysql"
EOF
    
    # Script de atualização
    cat > update.sh << 'EOF'
#!/bin/bash
# Script de atualização do Sincronizador VOD

echo "Iniciando atualização do Sincronizador VOD..."
echo "Data/Hora: $(date)"

# Parar serviços
echo "Parando serviços..."
systemctl stop sincronizador-vod

# Backup antes de atualizar
echo "Criando backup antes da atualização..."
./scripts/backup.sh

# Atualizar código do repositório Git (se estiver usando)
if [ -d "/var/www/sincronizador-vod/.git" ]; then
    echo "Atualizando código do Git..."
    cd /var/www/sincronizador-vod
    git pull origin main
fi

# Atualizar dependências do Node.js
echo "Atualizando dependências do Node.js..."
cd /var/www/sincronizador-vod/backend
npm install --production

# Atualizar banco de dados (se houver migrações)
if [ -f "scripts/migrate.js" ]; then
    echo "Atualizando banco de dados..."
    node scripts/migrate.js
fi

# Reiniciar serviços
echo "Reiniciando serviços..."
systemctl start sincronizador-vod

echo "Atualização concluída!"
echo "Verifique o status dos serviços:"
echo "  systemctl status sincronizador-vod"
echo "  systemctl status nginx"
echo "  systemctl status mysql"
EOF
    
    # Script de status
    cat > status.sh << 'EOF'
#!/bin/bash
# Script de status do Sincronizador VOD

echo "=== STATUS DO SINCRONIZADOR VOD ==="
echo "Data/Hora: $(date)"
echo

# Verificar serviços
echo "SERVIÇOS:"
echo "---------"
systemctl status sincronizador-vod --no-pager | head -10
echo
systemctl status nginx --no-pager | head -10
echo
systemctl status mysql --no-pager | head -10
echo

# Verificar espaço em disco
echo "ESPAÇO EM DISCO:"
echo "---------------"
df -h /var/www
echo

# Verificar uso de memória
echo "USO DE MEMÓRIA:"
echo "--------------"
free -h
echo

# Verificar logs recentes
echo "LOGS RECENTES (últimas 10 linhas):"
echo "---------------------------------"
tail -10 /var/log/sincronizador-vod/combined.log 2>/dev/null || echo "Log não encontrado"
echo

# Verificar banco de dados
echo "BANCO DE DADOS:"
echo "--------------"
echo "Usuários: $(mysql -u vod_user -pVodSync@2024 -sN -e "SELECT COUNT(*) FROM sincronizador_vod.users" 2>/dev/null || echo "Erro")"
echo "Listas M3U: $(mysql -u vod_user -pVodSync@2024 -sN -e "SELECT COUNT(*) FROM sincronizador_vod.m3u_lists" 2>/dev/null || echo "Erro")"
echo "Sincronizações: $(mysql -u vod_user -pVodSync@2024 -sN -e "SELECT COUNT(*) FROM sincronizador_vod.sync_logs" 2/dev/null || echo "Erro")"
echo

# Verificar API
echo "API STATUS:"
echo "----------"
curl -s http://localhost:3000/api/health | python3 -m json.tool 2>/dev/null || echo "API não responde"
EOF
    
    chmod +x *.sh
    
    log_success "Scripts de manutenção criados"
}

# Configurar SSL (opcional)
setup_ssl() {
    log_info "Configurando SSL (opcional)..."
    
    read -p "Deseja configurar SSL com Let's Encrypt? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        if command -v certbot >/dev/null 2>&1; then
            echo "Por favor, configure seu domínio primeiro."
            echo "Certifique-se de que o DNS aponte para este servidor."
            read -p "Digite o domínio (ex: sincronizador.seudominio.com): " domain
            
            if [ -n "$domain" ]; then
                certbot --nginx -d $domain
                if [ $? -eq 0 ]; then
                    log_success "SSL configurado para $domain"
                else
                    log_warning "Não foi possível configurar SSL"
                fi
            fi
        else
            log_warning "Certbot não instalado. Instale com: apt-get install certbot python3-certbot-nginx"
        fi
    fi
}

# Finalizar instalação
finalize_installation() {
    log_info "Finalizando instalação..."
    
    # Iniciar serviços
    systemctl start sincronizador-vod
    systemctl start nginx
    systemctl start mysql
    systemctl start php8.1-fpm
    
    # Verificar status dos serviços
    echo
    echo "=== STATUS DOS SERVIÇOS ==="
    systemctl is-active sincronizador-vod && echo "✅ Backend Node.js: ATIVO" || echo "❌ Backend Node.js: INATIVO"
    systemctl is-active nginx && echo "✅ Nginx: ATIVO" || echo "❌ Nginx: INATIVO"
    systemctl is-active mysql && echo "✅ MySQL: ATIVO" || echo "❌ MySQL: INATIVO"
    systemctl is-active php8.1-fpm && echo "✅ PHP-FPM: ATIVO" || echo "❌ PHP-FPM: INATIVO"
    
    # Testar API
    echo
    echo "=== TESTE DA API ==="
    api_response=$(curl -s http://localhost:3000/api/health)
    if echo "$api_response" | grep -q "ok"; then
        echo "✅ API: RESPONDENDO"
    else
        echo "❌ API: NÃO RESPONDE"
        echo "Resposta: $api_response"
    fi
    
    # Testar frontend
    echo
    echo "=== TESTE DO FRONTEND ==="
    frontend_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    if [ "$frontend_response" = "200" ]; then
        echo "✅ Frontend: ACESSÍVEL"
    else
        echo "❌ Frontend: NÃO ACESSÍVEL (HTTP $frontend_response)"
    fi
    
    # Criar arquivo de informações da instalação
    cat > /var/www/sincronizador-vod/INSTALACAO.txt << EOF
==========================================
INFORMAÇÕES DA INSTALAÇÃO - SINCRONIZADOR VOD
==========================================

DATA DA INSTALAÇÃO: $(date)
VERSÃO: 1.0.0
SISTEMA: Ubuntu 20.04 LTS

==========================================
CREDENCIAIS DE ACESSO
==========================================

PAINEL WEB: http://$(hostname -I | awk '{print $1}')/
    ou: http://localhost/

USUÁRIO ADMIN: admin
SENHA ADMIN: Admin@2024

API BACKEND: http://localhost:3000/api
DOCUMENTAÇÃO API: http://localhost:3000/api/docs

==========================================
BANCO DE DADOS
==========================================

HOST: localhost
PORTA: 3306
BANCO: sincronizador_vod
USUÁRIO: vod_user
SENHA: VodSync@2024

==========================================
DIRETÓRIOS IMPORTANTES
==========================================

CÓDIGO FONTE: /var/www/sincronizador-vod/
BACKEND: /var/www/sincronizador-vod/backend/
FRONTEND: /var/www/sincronizador-vod/frontend/
LOGS: /var/www/sincronizador-vod/logs/
BACKUPS: /var/www/sincronizador-vod/backups/
SCRIPTS: /var/www/sincronizador-vod/scripts/

==========================================
SERVIÇOS
==========================================

Backend Node.js: systemctl status sincronizador-vod
Web Server: systemctl status nginx
Banco de Dados: systemctl status mysql
PHP-FPM: systemctl status php8.1-fpm

==========================================
COMANDOS ÚTEIS
==========================================

# Reiniciar todos os serviços
systemctl restart sincronizador-vod nginx mysql php8.1-fpm

# Verificar logs do backend
tail -f /var/www/sincronizador-vod/backend/logs/combined.log

# Backup manual
cd /var/www/sincronizador-vod && ./scripts/backup.sh

# Restaurar backup
cd /var/www/sincronizador-vod && ./scripts/restore.sh <arquivo_backup>

# Atualizar sistema
cd /var/www/sincronizador-vod && ./scripts/update.sh

# Verificar status
cd /var/www/sincronizador-vod && ./scripts/status.sh

==========================================
PRÓXIMOS PASSOS
==========================================

1. Acesse o painel web: http://$(hostname -I | awk '{print $1}')/
2. Faça login com admin/Admin@2024
3. Configure sua chave da API TMDb nas configurações
4. Adicione uma conexão XUI One
5. Importe sua primeira lista M3U
6. Configure agendamentos automáticos

==========================================
SUPORTE
==========================================

Documentação: Consulte a pasta /docs/
Problemas: Verifique os logs em /var/www/sincronizador-vod/logs/
Backup: Backups automáticos diários em /var/www/sincronizador-vod/backups/

==========================================
SEGURANÇA
==========================================

1. ALTERE A SENHA DO ADMINISTRADOR após o primeiro login
2. Configure SSL/TLS para acesso seguro
3. Mantenha o sistema atualizado
4. Faça backups regularmente
5. Use firewall e mantenha portas fechadas

==========================================
EOF
    
    log_success "Instalação finalizada!"
    
    echo
    echo "=========================================="
    echo " 🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "=========================================="
    echo
    echo "📋 INFORMAÇÕES IMPORTANTES:"
    echo "----------------------------"
    echo "• Sistema instalado em: /var/www/sincronizador-vod/"
    echo "• Painel web: http://$(hostname -I | awk '{print $1}')/"
    echo "• Usuário: admin"
    echo "• Senha: Admin@2024"
    echo
    echo "🚀 PRÓXIMOS PASSOS:"
    echo "-------------------"
    echo "1. Acesse o painel web acima"
    echo "2. Altere a senha do administrador"
    echo "3. Configure a API TMDb (obtenha em: https://www.themoviedb.org)"
    echo "4. Adicione suas conexões XUI One"
    echo "5. Importe suas listas M3U"
    echo
    echo "📊 COMANDOS DE GERENCIAMENTO:"
    echo "---------------------------"
    echo "• systemctl status sincronizador-vod"
    echo "• tail -f /var/www/sincronizador-vod/logs/combined.log"
    echo "• cd /var/www/sincronizador-vod && ./scripts/status.sh"
    echo
    echo "🔧 PARA SUPORTE:"
    echo "----------------"
    echo "• Consulte o arquivo: /var/www/sincronizador-vod/INSTALACAO.txt"
    echo "• Verifique os logs em: /var/www/sincronizador-vod/logs/"
    echo
    echo "⚠️  IMPORTANTE:"
    echo "----------------"
    echo "• ALTERE A SENHA PADRÃO IMEDIATAMENTE!"
    echo "• Configure SSL/TLS para produção"
    echo "• Faça backup regularmente"
    echo
    echo "=========================================="
}

# Função principal
main() {
    clear
    echo "=========================================="
    echo " INSTALADOR SINCRONIZADOR VOD XUI ONE"
    echo "        Ubuntu 20.04 LTS"
    echo "=========================================="
    echo
    
    # Obter senha do MySQL root
    read -sp "Digite a senha root do MySQL: " DB_ROOT_PASSWORD
    echo
    
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
    setup_cron_jobs
    create_maintenance_scripts
    setup_ssl
    finalize_installation
    
    echo "Instalação concluída em: $(date)"
    echo "Tempo total: $SECONDS segundos"
}

# Executar instalação
main "$@"
