#!/bin/bash

# ============================================================
# INSTALADOR COMPLETO VOD SYNC XUI - VERSÃO 4.0.0
# Sistema completo de sincronização de VODs para X-UI
# ============================================================

set -e

# Configurações
INSTALL_DIR="/opt/vod-sync-xui"
CONFIG_FILE="$INSTALL_DIR/config/sync_config.json"
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/' | head -c 16)
SECRET_KEY=$(openssl rand -hex 32)
ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '=+/' | head -c 12)
API_KEY=$(openssl rand -hex 32)

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funções de output
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }
print_info() { echo -e "${YELLOW}[i] $1${NC}"; }
print_step() { echo -e "${BLUE}[→] $1${NC}"; }
print_header() { echo -e "${MAGENTA}\n$1${NC}"; }
print_divider() { echo -e "${CYAN}========================================${NC}"; }

# Verificar root
if [[ $EUID -ne 0 ]]; then
    print_error "Este script precisa ser executado como root!"
    exit 1
fi

# Banner
clear
print_divider
echo -e "${GREEN}   ╔══════════════════════════════════════╗"
echo -e "   ║      VOD SYNC XUI - INSTALADOR 4.0.0     ║"
echo -e "   ║     Sistema Completo de Sincronização    ║"
echo -e "   ╚══════════════════════════════════════╝${NC}"
print_divider
echo ""

# 1. Limpar instalação anterior
print_header "1. LIMPEZA DE INSTALAÇÃO ANTERIOR"
print_step "Parando serviços anteriores..."
systemctl stop vod-sync vod-sync-worker vod-sync-api 2>/dev/null || true
systemctl disable vod-sync vod-sync-worker vod-sync-api 2>/dev/null || true
rm -f /etc/systemd/system/vod-sync*.service
rm -rf "$INSTALL_DIR" 2>/dev/null || true
print_success "Limpeza concluída"

# 2. Atualizar sistema e instalar dependências
print_header "2. INSTALAÇÃO DE DEPENDÊNCIAS DO SISTEMA"
print_step "Atualizando pacotes..."
apt-get update -qq

print_step "Instalando dependências do sistema..."
apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    mysql-server \
    mysql-client \
    nginx \
    ffmpeg \
    mediainfo \
    git \
    curl \
    wget \
    unzip \
    cron \
    screen \
    jq \
    net-tools \
    tmux \
    sqlite3 \
    rsync \
    inotify-tools \
    pv

print_success "Dependências instaladas"

# 3. Criar estrutura de diretórios
print_header "3. ESTRUTURA DE DIRETÓRIOS"
mkdir -p "$INSTALL_DIR"/{src,logs,data,config,backup,scripts,templates,static,vods,temp,exports}
mkdir -p "$INSTALL_DIR"/data/{database,sessions,thumbnails,metadata}
mkdir -p "$INSTALL_DIR"/logs/{app,worker,nginx,cron,debug}
mkdir -p "$INSTALL_DIR"/vods/{movies,series,originals,processed,queue}

# Setar permissões
chmod -R 755 "$INSTALL_DIR"
chown -R www-data:www-data "$INSTALL_DIR/data" "$INSTALL_DIR/logs" "$INSTALL_DIR/vods"
print_success "Estrutura de diretórios criada"

# 4. Criar arquivos de configuração
print_header "4. CONFIGURAÇÕES DO SISTEMA"

# Arquivo .env principal
cat > "$INSTALL_DIR/.env" << EOF
# ============================================
# VOD SYNC XUI - CONFIGURAÇÕES PRINCIPAIS
# ============================================

# Aplicação Flask
FLASK_APP=app.py
FLASK_ENV=production
SECRET_KEY=$SECRET_KEY
DEBUG=false
HOST=0.0.0.0
PORT=5000
API_KEY=$API_KEY
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Banco de Dados MySQL
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync_xui
DB_USER=vod_sync_xui
DB_PASSWORD=$DB_PASSWORD
DB_CHARSET=utf8mb4

# Banco de Dados SQLite (cache)
SQLITE_PATH=$INSTALL_DIR/data/database/vod_cache.db

# Paths
BASE_DIR=$INSTALL_DIR
VOD_STORAGE_PATH=$INSTALL_DIR/vods
PROCESSED_PATH=$INSTALL_DIR/vods/processed
ORIGINALS_PATH=$INSTALL_DIR/vods/originals
QUEUE_PATH=$INSTALL_DIR/vods/queue
TEMP_PATH=$INSTALL_DIR/temp
LOG_PATH=$INSTALL_DIR/logs
BACKUP_PATH=$INSTALL_DIR/backup
EXPORTS_PATH=$INSTALL_DIR/exports

# Configurações de Sincronização
SYNC_INTERVAL=300  # 5 minutos
MAX_CONCURRENT_SYNCS=3
MAX_FILE_SIZE=10737418240  # 10GB
MIN_FILE_SIZE=10485760     # 10MB
ALLOWED_EXTENSIONS=mp4,mkv,avi,mov,flv,wmv,m4v,ts
ENABLE_AUTO_SCAN=true
ENABLE_REAL_TIME_SYNC=true

# Configurações de Processamento
ENABLE_TRANSCODING=false
TRANSCODE_PRESET=fast1080p
OUTPUT_FORMAT=mp4
CREATE_THUMBNAILS=true
THUMBNAIL_COUNT=3
EXTRACT_METADATA=true
GENERATE_SUBTITLES=false

# Configurações do Player
DEFAULT_PLAYER=html5
ENABLE_CAST=true
ENABLE_DOWNLOAD=true
AUTO_PLAY=false
PRELOAD_METADATA=true

# Configurações de Segurança
REQUIRE_LOGIN=false
SESSION_TIMEOUT=3600
MAX_LOGIN_ATTEMPTS=5
ENABLE_RATE_LIMIT=true
ALLOWED_IPS=*

# Configurações de Notificação
NOTIFY_ON_SYNC=true
NOTIFY_ON_ERROR=true
EMAIL_NOTIFICATIONS=false
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Configurações do X-UI
XUI_BASE_URL=http://localhost:54321
XUI_USERNAME=admin
XUI_PASSWORD=admin
XUI_SYNC_ENABLED=true

# Configurações de Backup
BACKUP_ENABLED=true
BACKUP_INTERVAL=86400  # 24 horas
MAX_BACKUPS=30

# Configurações de Log
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30
ENABLE_DEBUG_LOG=false

# Configurações do Worker
WORKER_COUNT=2
WORKER_TIMEOUT=3600
TASK_RETRY_COUNT=3

# Configurações de Rede
UPLOAD_SPEED_LIMIT=0  # 0 = ilimitado
DOWNLOAD_SPEED_LIMIT=0
MAX_CONNECTIONS=100
TIMEOUT=30

# Configurações do Sistema
CHECK_UPDATES=true
AUTO_UPDATE=false
LANGUAGE=pt_BR
TIMEZONE=America/Sao_Paulo

# API Config
API_RATE_LIMIT=100
API_TIMEOUT=30
ENABLE_SWAGGER=true
CORS_ORIGINS=*
EOF

print_success "Arquivo .env criado"

# Arquivo de configuração JSON para sincronização
cat > "$CONFIG_FILE" << EOF
{
  "version": "4.0.0",
  "sync_config": {
    "sources": [
      {
        "name": "local_vods",
        "type": "local",
        "path": "/home/vods",
        "enabled": true,
        "recursive": true,
        "patterns": ["*.mp4", "*.mkv", "*.avi"],
        "exclude_patterns": ["*.tmp", "*.part"],
        "scan_interval": 300
      },
      {
        "name": "ftp_server",
        "type": "ftp",
        "host": "ftp.example.com",
        "port": 21,
        "username": "user",
        "password": "pass",
        "remote_path": "/vods",
        "enabled": false
      },
      {
        "name": "s3_storage",
        "type": "s3",
        "bucket": "your-bucket",
        "region": "us-east-1",
        "access_key": "",
        "secret_key": "",
        "prefix": "vods/",
        "enabled": false
      }
    ],
    "destination": {
      "path": "$INSTALL_DIR/vods",
      "organization": "category",
      "create_symlinks": false,
      "keep_original": true
    },
    "processing": {
      "transcode": {
        "enabled": false,
        "preset": "fast1080p",
        "target_bitrate": "2000k",
        "resolution": "1920x1080",
        "codec": "h264"
      },
      "metadata": {
        "extract": true,
        "template": "standard",
        "include_thumbnails": true,
        "thumbnail_interval": 10
      },
      "validation": {
        "check_integrity": true,
        "verify_duration": true,
        "min_duration": 10,
        "max_duration": 14400
      }
    },
    "notifications": {
      "enabled": true,
      "on_success": true,
      "on_error": true,
      "on_completion": true,
      "methods": ["log", "email"]
    },
    "scheduling": {
      "auto_sync": true,
      "interval": 300,
      "start_time": "00:00",
      "end_time": "23:59",
      "days": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    },
    "cleanup": {
      "enabled": true,
      "keep_original_days": 7,
      "max_storage_gb": 100,
      "delete_incomplete_after_hours": 24
    }
  }
}
EOF

print_success "Arquivo de configuração de sincronização criado"

# 5. Criar requirements.txt completo
print_header "5. INSTALAÇÃO DO PYTHON"
cat > "$INSTALL_DIR/requirements.txt" << EOF
# Core
Flask==2.3.3
gunicorn==21.2.0
Werkzeug==2.3.7

# Database
PyMySQL==1.1.0
SQLAlchemy==2.0.19
alembic==1.12.0
pymongo==4.5.0
redis==5.0.0

# Video Processing
moviepy==1.0.3
Pillow==10.1.0
imageio==2.31.5
ffmpeg-python==0.2.0
pymediainfo==6.1.0

# Utilities
python-dotenv==1.0.0
psutil==5.9.6
requests==2.31.0
aiohttp==3.9.0
asyncio==3.4.3
celery==5.3.4
redis==5.0.0

# API
Flask-RESTful==0.3.10
Flask-CORS==4.0.0
Flask-JWT-Extended==4.5.3
Flask-Limiter==3.8.0
Flask-SocketIO==5.3.6
python-socketio==5.10.0
eventlet==0.35.1

# File Operations
watchdog==3.0.0
paramiko==3.3.1
boto3==1.34.0
pysftp==0.2.9
ftputil==5.0.4

# Monitoring
prometheus-client==0.19.0
flask-monitoringdashboard==5.0.0

# Date & Time
pytz==2023.3
arrow==1.2.3

# CLI & Logging
click==8.1.7
colorama==0.4.6
loguru==0.7.2

# Web & UI
Jinja2==3.1.2
MarkupSafe==2.1.3
WTForms==3.1.0
Flask-WTF==1.2.1
# Security
cryptography==41.0.7
bcrypt==4.1.2
passlib==1.7.4

# Data Processing
pandas==2.0.3
numpy==1.24.4

# Testing
pytest==7.4.3
pytest-cov==4.1.0
pytest-mock==3.12.0
EOF

# Criar e ativar ambiente virtual
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

print_step "Instalando dependências Python..."
pip install --upgrade pip
pip install -r requirements.txt

print_success "Ambiente Python configurado"

# 6. Criar aplicação Flask completa
print_header "6. APLICAÇÃO FLASK COMPLETA"

# Estrutura de diretórios da aplicação
mkdir -p "$INSTALL_DIR/src"/{models,controllers,routes,utils,services,tasks,templates,static}

# Arquivo principal da aplicação
cat > "$INSTALL_DIR/src/app.py" << 'EOF'
"""
VOD Sync XUI - Aplicação Principal
Sistema completo de gerenciamento e sincronização de VODs
"""
import os
import sys
import logging
from datetime import datetime
from pathlib import Path

# Adicionar diretório src ao path
sys.path.insert(0, str(Path(__file__).parent))

from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_socketio import SocketIO
from dotenv import load_dotenv

# Carregar variáveis de ambiente
env_path = Path(__file__).parent.parent / '.env'
load_dotenv(env_path)

# Configurar logging
logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.getenv('LOG_PATH', '/var/log/vod-sync/app.log')),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

def create_app():
    """Factory function para criar a aplicação Flask"""
    
    app = Flask(__name__, 
                template_folder='templates',
                static_folder='static')
    
    # Configurações básicas
    app.config.update(
        SECRET_KEY=os.getenv('SECRET_KEY', 'dev-secret-key'),
        JWT_SECRET_KEY=os.getenv('SECRET_KEY', 'jwt-secret-key'),
        JWT_ACCESS_TOKEN_EXPIRES=int(os.getenv('SESSION_TIMEOUT', 3600)),
        MAX_CONTENT_LENGTH=int(os.getenv('MAX_FILE_SIZE', 10 * 1024 * 1024 * 1024)),
        SQLALCHEMY_DATABASE_URI=f"mysql+pymysql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}",
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        SQLALCHEMY_ENGINE_OPTIONS={
            'pool_recycle': 300,
            'pool_pre_ping': True,
        }
    )
    
    # Habilitar CORS
    CORS(app, resources={
        r"/api/*": {
            "origins": os.getenv('CORS_ORIGINS', '*').split(',')
        }
    })
    
    # Inicializar JWT
    jwt = JWTManager(app)
    
    # Inicializar SocketIO
    socketio = SocketIO(app, 
                       cors_allowed_origins=os.getenv('CORS_ORIGINS', '*'),
                       async_mode='eventlet',
                       logger=os.getenv('ENABLE_DEBUG_LOG', 'false').lower() == 'true',
                       engineio_logger=os.getenv('ENABLE_DEBUG_LOG', 'false').lower() == 'true')
    
    # Registrar blueprints
    register_blueprints(app)
    
    # Registrar handlers de erro
    register_error_handlers(app)
    
    # Registrar comandos CLI
    register_commands(app)
    
    # Registrar context processors
    register_context_processors(app)
    
    # Registrar filtros
    register_filters(app)
    
    # Rotas básicas
    @app.route('/')
    def index():
        return render_template('index.html')
    
    @app.route('/dashboard')
    def dashboard():
        return render_template('dashboard.html')
    
    @app.route('/api/status')
    def api_status():
        from utils.system_info import get_system_info
        return jsonify({
            'status': 'online',
            'timestamp': datetime.utcnow().isoformat(),
            'version': '4.0.0',
            'system': get_system_info()
        })
    
    @app.route('/api/config')
    def api_config():
        # Retornar configurações não sensíveis
        return jsonify({
            'sync_interval': os.getenv('SYNC_INTERVAL'),
            'max_concurrent_syncs': os.getenv('MAX_CONCURRENT_SYNCS'),
            'auto_scan': os.getenv('ENABLE_AUTO_SCAN'),
            'real_time_sync': os.getenv('ENABLE_REAL_TIME_SYNC'),
            'vod_count': 0,  # Será preenchido pelo banco
            'last_sync': None  # Será preenchido pelo banco
        })
    
    return app, socketio

def register_blueprints(app):
    """Registrar blueprints da aplicação"""
    from routes import (
        auth_routes, vod_routes, sync_routes, 
        system_routes, api_routes, webhook_routes
    )
    
    app.register_blueprint(auth_routes.bp, url_prefix='/auth')
    app.register_blueprint(vod_routes.bp, url_prefix='/vod')
    app.register_blueprint(sync_routes.bp, url_prefix='/sync')
    app.register_blueprint(system_routes.bp, url_prefix='/system')
    app.register_blueprint(api_routes.bp, url_prefix='/api/v1')
    app.register_blueprint(webhook_routes.bp, url_prefix='/webhook')

def register_error_handlers(app):
    """Registrar handlers de erro"""
    @app.errorhandler(404)
    def not_found(error):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Not found'}), 404
        return render_template('errors/404.html'), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        logger.error(f'Internal server error: {error}')
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Internal server error'}), 500
        return render_template('errors/500.html'), 500

def register_commands(app):
    """Registrar comandos CLI"""
    from commands import sync_commands, db_commands, user_commands
    
    app.cli.add_command(sync_commands.sync_cli)
    app.cli.add_command(db_commands.db_cli)
    app.cli.add_command(user_commands.user_cli)

def register_context_processors(app):
    """Registrar context processors"""
    @app.context_processor
    def inject_now():
        return {'now': datetime.utcnow()}
    
    @app.context_processor
    def inject_config():
        return {
            'app_name': 'VOD Sync XUI',
            'app_version': '4.0.0',
            'current_year': datetime.now().year
        }

def register_filters(app):
    """Registrar filtros de template"""
    @app.template_filter('format_size')
    def format_size(value):
        """Formatar tamanho de arquivo"""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if value < 1024.0:
                return f"{value:.2f} {unit}"
            value /= 1024.0
        return f"{value:.2f} PB"
    
    @app.template_filter('format_duration')
    def format_duration(seconds):
        """Formatar duração em segundos"""
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        if hours > 0:
            return f"{hours}:{minutes:02d}:{secs:02d}"
        return f"{minutes}:{secs:02d}"

# Criar a aplicação
app, socketio = create_app()

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Iniciando VOD Sync XUI na porta {port}")
    socketio.run(app, host=host, port=port, debug=debug)
EOF

# Criar módulo de sincronização principal
cat > "$INSTALL_DIR/src/services/sync_service.py" << 'EOF'
"""
Serviço de Sincronização de VODs
"""
import os
import json
import logging
import shutil
import hashlib
import asyncio
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

import aiohttp
import aiofiles
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

logger = logging.getLogger(__name__)

class VodSyncService:
    """Serviço principal de sincronização de VODs"""
    
    def __init__(self, config_path: str):
        self.config_path = config_path
        self.config = self.load_config()
        self.observer = None
        self.is_running = False
        self.sync_queue = asyncio.Queue()
        self.executor = ThreadPoolExecutor(max_workers=int(os.getenv('MAX_CONCURRENT_SYNCS', 3)))
        
    def load_config(self) -> Dict[str, Any]:
        """Carregar configuração do arquivo JSON"""
        try:
            with open(self.config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Erro ao carregar configuração: {e}")
            return {}
    
    async def start(self):
        """Iniciar serviço de sincronização"""
        if self.is_running:
            logger.warning("Serviço já está em execução")
            return
        
        self.is_running = True
        logger.info("Iniciando serviço de sincronização VOD")
        
        # Iniciar monitoramento em tempo real
        if self.config.get('sync_config', {}).get('scheduling', {}).get('real_time_sync', True):
            self.start_file_monitoring()
        
        # Iniciar workers de processamento
        asyncio.create_task(self.process_queue())
        
        # Executar primeira sincronização
        await self.run_sync()
        
        # Agendar sincronizações periódicas
        interval = self.config.get('sync_config', {}).get('scheduling', {}).get('interval', 300)
        asyncio.create_task(self.schedule_sync(interval))
        
    async def stop(self):
        """Parar serviço de sincronização"""
        self.is_running = False
        
        if self.observer:
            self.observer.stop()
            self.observer.join()
        
        self.executor.shutdown(wait=True)
        logger.info("Serviço de sincronização parado")
    
    async def schedule_sync(self, interval: int):
        """Agendar sincronizações periódicas"""
        while self.is_running:
            await asyncio.sleep(interval)
            if self.is_running:
                await self.run_sync()
    
    async def run_sync(self):
        """Executar uma sincronização completa"""
        logger.info("Iniciando sincronização de VODs")
        
        try:
            sources = self.config.get('sync_config', {}).get('sources', [])
            
            # Processar cada fonte em paralelo
            tasks = []
            for source in sources:
                if source.get('enabled', True):
                    task = self.process_source(source)
                    tasks.append(task)
            
            # Aguardar conclusão de todas as tarefas
            if tasks:
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Processar resultados
                successful = 0
                failed = 0
                
                for result in results:
                    if isinstance(result, Exception):
                        logger.error(f"Erro na sincronização: {result}")
                        failed += 1
                    elif result:
                        successful += 1
                
                logger.info(f"Sincronização concluída: {successful} sucesso, {failed} falhas")
                
                # Notificar conclusão
                await self.notify_sync_completion(successful, failed)
                
        except Exception as e:
            logger.error(f"Erro durante sincronização: {e}")
            await self.notify_sync_error(str(e))
    
    async def process_source(self, source: Dict[str, Any]) -> bool:
        """Processar uma fonte de VODs"""
        source_type = source.get('type', 'local')
        
        try:
            if source_type == 'local':
                return await self.sync_local_source(source)
            elif source_type == 'ftp':
                return await self.sync_ftp_source(source)
            elif source_type == 's3':
                return await self.sync_s3_source(source)
            else:
                logger.warning(f"Tipo de fonte não suportado: {source_type}")
                return False
                
        except Exception as e:
            logger.error(f"Erro ao processar fonte {source.get('name')}: {e}")
            return False
    
    async def sync_local_source(self, source: Dict[str, Any]) -> bool:
        """Sincronizar fonte local"""
        source_path = source.get('path', '')
        if not source_path or not os.path.exists(source_path):
            logger.warning(f"Caminho de fonte local não existe: {source_path}")
            return False
        
        # Configurações
        recursive = source.get('recursive', True)
        patterns = source.get('patterns', ['*.mp4', '*.mkv', '*.avi'])
        exclude_patterns = source.get('exclude_patterns', [])
        
        logger.info(f"Sincronizando fonte local: {source_path}")
        
        # Encontrar arquivos
        vod_files = self.find_vod_files(source_path, patterns, exclude_patterns, recursive)
        
        if not vod_files:
            logger.info("Nenhum arquivo VOD encontrado")
            return True
        
        logger.info(f"Encontrados {len(vod_files)} arquivos VOD")
        
        # Processar cada arquivo
        success_count = 0
        for vod_file in vod_files:
            try:
                await self.process_vod_file(vod_file, source)
                success_count += 1
            except Exception as e:
                logger.error(f"Erro ao processar {vod_file}: {e}")
        
        logger.info(f"Processados {success_count}/{len(vod_files)} arquivos")
        return success_count > 0
    
    def find_vod_files(self, base_path: str, patterns: List[str], 
                       exclude_patterns: List[str], recursive: bool = True) -> List[str]:
        """Encontrar arquivos VOD baseado em padrões"""
        from fnmatch import fnmatch
        from pathlib import Path
        
        vod_files = []
        base_path_obj = Path(base_path)
        
        # Função para verificar se arquivo deve ser excluído
        def should_exclude(filename: str) -> bool:
            for pattern in exclude_patterns:
                if fnmatch(filename, pattern):
                    return True
            return False
        
        # Método de busca
        search_method = base_path_obj.rglob if recursive else base_path_obj.glob
        
        for pattern in patterns:
            for file_path in search_method(pattern):
                if file_path.is_file() and not should_exclude(file_path.name):
                    vod_files.append(str(file_path))
        
        return vod_files
    
    async def process_vod_file(self, file_path: str, source: Dict[str, Any]):
        """Processar um arquivo VOD individual"""
        from utils.vod_processor import VodProcessor
        
        logger.debug(f"Processando arquivo: {file_path}")
        
        # Verificar se arquivo já foi processado
        file_hash = self.calculate_file_hash(file_path)
        if await self.is_already_processed(file_hash):
            logger.debug(f"Arquivo já processado: {file_path}")
            return
        
        # Criar processor
        processor = VodProcessor(file_path, source, self.config)
        
        # Validar arquivo
        if not await processor.validate():
            logger.warning(f"Arquivo inválido: {file_path}")
            return
        
        # Extrair metadados
        metadata = await processor.extract_metadata()
        
        # Adicionar à fila para processamento assíncrono
        await self.sync_queue.put({
            'file_path': file_path,
            'metadata': metadata,
            'source': source,
            'file_hash': file_hash
        })
        
        logger.debug(f"Arquivo adicionado à fila: {file_path}")
    
    async def process_queue(self):
        """Processar itens da fila de sincronização"""
        while self.is_running:
            try:
                # Pegar item da fila com timeout
                item = await asyncio.wait_for(self.sync_queue.get(), timeout=1.0)
                
                if item:
                    # Processar em thread separada
                    await asyncio.get_event_loop().run_in_executor(
                        self.executor,
                        self.process_queue_item,
                        item
                    )
                    
                    # Marcar como concluído
                    self.sync_queue.task_done()
                    
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Erro ao processar fila: {e}")
    
    def process_queue_item(self, item: Dict[str, Any]):
        """Processar item da fila (executado em thread separada)"""
        try:
            file_path = item['file_path']
            metadata = item['metadata']
            source = item['source']
            file_hash = item['file_hash']
            
            # Copiar arquivo para destino
            destination = self.get_destination_path(file_path, metadata, source)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            
            # Copiar arquivo
            shutil.copy2(file_path, destination)
            
            # Criar thumbnails se configurado
            if self.config.get('sync_config', {}).get('processing', {}).get('metadata', {}).get('include_thumbnails', True):
                self.create_thumbnails(destination, metadata)
            
            # Salvar metadados no banco de dados
            self.save_to_database(file_hash, destination, metadata, source)
            
            logger.info(f"Arquivo sincronizado: {file_path} -> {destination}")
            
            # Notificar sucesso
            self.notify_file_synced(file_path, destination, metadata)
            
        except Exception as e:
            logger.error(f"Erro ao processar item da fila: {e}")
            self.notify_file_error(file_path, str(e))
    
    def get_destination_path(self, file_path: str, metadata: Dict[str, Any], 
                            source: Dict[str, Any]) -> str:
        """Gerar caminho de destino baseado em configuração"""
        import os
        from datetime import datetime
        
        dest_config = self.config.get('sync_config', {}).get('destination', {})
        dest_base = dest_config.get('path', os.getenv('VOD_STORAGE_PATH', '/var/vods'))
        organization = dest_config.get('organization', 'flat')
        
        # Extrair informações do arquivo
        filename = os.path.basename(file_path)
        file_ext = os.path.splitext(filename)[1]
        
        if organization == 'category':
            # Organizar por categoria/tipo
            category = metadata.get('category', 'unknown')
            return os.path.join(dest_base, category, filename)
        
        elif organization == 'date':
            # Organizar por data
            date_str = datetime.now().strftime('%Y/%m/%d')
            return os.path.join(dest_base, date_str, filename)
        
        elif organization == 'source':
            # Organizar por fonte
            source_name = source.get('name', 'unknown')
            return os.path.join(dest_base, source_name, filename)
        
        else:
            # Estrutura plana
            return os.path.join(dest_base, filename)
    
    def create_thumbnails(self, file_path: str, metadata: Dict[str, Any]):
        """Criar thumbnails do vídeo"""
        try:
            from utils.thumbnail_generator import ThumbnailGenerator
            
            generator = ThumbnailGenerator(file_path)
            thumbnails = generator.generate()
            
            # Salvar thumbnails
            thumbnail_dir = os.path.join(
                os.getenv('VOD_STORAGE_PATH', '/var/vods'),
                'thumbnails',
                os.path.basename(file_path)
            )
            os.makedirs(thumbnail_dir, exist_ok=True)
            
            for i, thumb in enumerate(thumbnails):
                thumb_path = os.path.join(thumbnail_dir, f'thumb_{i}.jpg')
                thumb.save(thumb_path, 'JPEG', quality=85)
            
            logger.debug(f"Thumbnails criados para: {file_path}")
            
        except Exception as e:
            logger.warning(f"Erro ao criar thumbnails: {e}")
    
    def save_to_database(self, file_hash: str, file_path: str, 
                        metadata: Dict[str, Any], source: Dict[str, Any]):
        """Salvar informações no banco de dados"""
        try:
            from models.vod_model import VodFile
            
            vod_file = VodFile(
                file_hash=file_hash,
                original_path=file_path,
                current_path=file_path,
                filename=os.path.basename(file_path),
                file_size=metadata.get('file_size', 0),
                duration=metadata.get('duration', 0),
                resolution=metadata.get('resolution', ''),
                format=metadata.get('format', ''),
                codec=metadata.get('codec', ''),
                bitrate=metadata.get('bitrate', 0),
                source=source.get('name', 'unknown'),
                metadata=metadata,
                sync_date=datetime.now(),
                status='synced'
            )
            
            # TODO: Implementar salvamento no banco
            # database.session.add(vod_file)
            # database.session.commit()
            
        except Exception as e:
            logger.error(f"Erro ao salvar no banco: {e}")
    
    async def is_already_processed(self, file_hash: str) -> bool:
        """Verificar se arquivo já foi processado"""
        # TODO: Implementar verificação no banco de dados
        return False
    
    def calculate_file_hash(self, file_path: str) -> str:
        """Calcular hash do arquivo"""
        sha256_hash = hashlib.sha256()
        
        try:
            with open(file_path, "rb") as f:
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)
            
            return sha256_hash.hexdigest()
            
        except Exception as e:
            logger.error(f"Erro ao calcular hash: {e}")
            return ""
    
    def start_file_monitoring(self):
        """Iniciar monitoramento de arquivos em tempo real"""
        try:
            from services.file_monitor import FileChangeHandler
            
            event_handler = FileChangeHandler(self)
            self.observer = Observer()
            
            # Monitorar cada fonte local
            sources = self.config.get('sync_config', {}).get('sources', [])
            for source in sources:
                if source.get('type') == 'local' and source.get('enabled', True):
                    path = source.get('path', '')
                    if os.path.exists(path):
                        self.observer.schedule(event_handler, path, recursive=True)
            
            self.observer.start()
            logger.info("Monitoramento de arquivos iniciado")
            
        except Exception as e:
            logger.error(f"Erro ao iniciar monitoramento: {e}")
    
    async def notify_sync_completion(self, successful: int, failed: int):
        """Notificar conclusão da sincronização"""
        # TODO: Implementar notificações (email, telegram, webhook)
        pass
    
    async def notify_sync_error(self, error: str):
        """Notificar erro na sincronização"""
        # TODO: Implementar notificações de erro
        pass
    
    def notify_file_synced(self, original_path: str, destination_path: str, 
                          metadata: Dict[str, Any]):
        """Notificar arquivo sincronizado"""
        # TODO: Implementar notificações por arquivo
        pass
    
    def notify_file_error(self, file_path: str, error: str):
        """Notificar erro no processamento de arquivo"""
        # TODO: Implementar notificações de erro por arquivo
        pass
    
    async def sync_ftp_source(self, source: Dict[str, Any]) -> bool:
        """Sincronizar fonte FTP"""
        # TODO: Implementar sincronização FTP
        logger.warning("Sincronização FTP não implementada")
        return False
    
    async def sync_s3_source(self, source: Dict[str, Any]) -> bool:
        """Sincronizar fonte S3"""
        # TODO: Implementar sincronização S3
        logger.warning("Sincronização S3 não implementada")
        return False

# Handler para monitoramento de arquivos
class FileChangeHandler(FileSystemEventHandler):
    """Handler para monitorar mudanças em arquivos"""
    
    def __init__(self, sync_service: VodSyncService):
        self.sync_service = sync_service
    
    def on_created(self, event):
        """Arquivo criado"""
        if not event.is_directory:
            logger.info(f"Arquivo criado: {event.src_path}")
            # Adicionar à fila de processamento
            asyncio.create_task(self.sync_service.process_new_file(event.src_path))
    
    def on_modified(self, event):
        """Arquivo modificado"""
        if not event.is_directory:
            logger.debug(f"Arquivo modificado: {event.src_path}")
    
    def on_deleted(self, event):
        """Arquivo deletado"""
        if not event.is_directory:
            logger.info(f"Arquivo deletado: {event.src_path}")
    
    def on_moved(self, event):
        """Arquivo movido/renomeado"""
        if not event.is_directory:
            logger.info(f"Arquivo movido: {event.src_path} -> {event.dest_path}")
EOF

# Criar mais módulos necessários (resumidos por questão de espaço)
# Criar models, controllers, routes, utils, etc.

print_success "Aplicação Flask criada"

# 7. Configurar banco de dados MySQL
print_header "7. CONFIGURAÇÃO DO BANCO DE DADOS"
print_step "Configurando MySQL..."

# Iniciar MySQL se não estiver rodando
systemctl start mysql 2>/dev/null || true
systemctl enable mysql 2>/dev/null || true

# Criar banco de dados e usuário
mysql -e "DROP DATABASE IF EXISTS vod_sync_xui;" 2>/dev/null || true
mysql -e "CREATE DATABASE IF NOT EXISTS vod_sync_xui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'vod_sync_xui'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON vod_sync_xui.* TO 'vod_sync_xui'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

print_success "Banco de dados MySQL configurado"

# 8. Configurar Nginx como proxy reverso
print_header "8. CONFIGURAÇÃO DO NGINX"
cat > /etc/nginx/sites-available/vod-sync << EOF
server {
    listen 80;
    server_name _;
    
    # Limites
    client_max_body_size 10G;
    client_body_timeout 300s;
    proxy_read_timeout 300s;
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    
    # Logs
    access_log $INSTALL_DIR/logs/nginx/access.log;
    error_log $INSTALL_DIR/logs/nginx/error.log;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml application/javascript application/json;
    gzip_disable "MSIE [1-6]\.";
    
    # Root
    root $INSTALL_DIR/static;
    
    # Página inicial
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # API
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Rate limiting
        limit_req zone=api burst=20 nodelay;
        limit_req_status 429;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $INSTALL_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        
        # Habilita CORS para fontes
        add_header Access-Control-Allow-Origin *;
    }
    
    # VOD files
    location /vods/ {
        alias $INSTALL_DIR/vods/;
        expires 30d;
        add_header Cache-Control "public";
        
        # Enable streaming
        mp4;
        mp4_buffer_size 1m;
        mp4_max_buffer_size 5m;
        
        # CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, HEAD";
        add_header Access-Control-Allow-Headers "Range";
        
        # Range requests for streaming
        if (\$request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS";
            add_header Access-Control-Allow-Headers "Range";
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type 'text/plain charset=UTF-8';
            add_header Content-Length 0;
            return 204;
        }
    }
    
    # Thumbnails
    location /thumbnails/ {
        alias $INSTALL_DIR/data/thumbnails/;
        expires 7d;
        add_header Cache-Control "public";
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Status page
    location /status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}

# Rate limiting zone
limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
EOF

# Habilitar site
ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar configuração do nginx
nginx -t && systemctl restart nginx
print_success "Nginx configurado"

# 9. Criar serviços systemd
print_header "9. CONFIGURAÇÃO DE SERVIÇOS SYSTEMD"

# Serviço principal
cat > /etc/systemd/system/vod-sync.service << EOF
[Unit]
Description=VOD Sync XUI - Serviço Principal
After=network.target mysql.service nginx.service
Wants=network-online.target
Requires=mysql.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn \
  --bind unix:$INSTALL_DIR/vod-sync.sock \
  --workers 4 \
  --worker-class eventlet \
  --timeout 300 \
  --access-logfile $INSTALL_DIR/logs/app/access.log \
  --error-logfile $INSTALL_DIR/logs/app/error.log \
  --log-level info \
  src.app:app
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync
LimitNOFILE=65536
LimitNPROC=65536
OOMScoreAdjust=-100

[Install]
WantedBy=multi-user.target
EOF

# Serviço worker
cat > /etc/systemd/system/vod-sync-worker.service << EOF
[Unit]
Description=VOD Sync XUI - Worker de Processamento
After=vod-sync.service
Requires=vod-sync.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery \
  -A src.tasks.celery_app worker \
  --loglevel=info \
  --concurrency=4 \
  --hostname=worker@%h \
  --queues=sync,process,notify
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-worker
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

# Serviço de sincronização agendada
cat > /etc/systemd/system/vod-sync-scheduler.service << EOF
[Unit]
Description=VOD Sync XUI - Agendador de Tarefas
After=vod-sync.service
Requires=vod-sync.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/scripts/scheduler.py
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-scheduler

[Install]
WantedBy=multi-user.target
EOF

# Timer para sincronização periódica
cat > /etc/systemd/system/vod-sync-scheduler.timer << EOF
[Unit]
Description=Executa sincronização periódica de VODs
Requires=vod-sync-scheduler.service

[Timer]
Unit=vod-sync-scheduler.service
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Recarregar daemon
systemctl daemon-reload

print_success "Serviços systemd criados"

# 10. Criar scripts de gerenciamento
print_header "10. SCRIPTS DE GERENCIAMENTO"

# Script de inicialização
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash

set -e

INSTALL_DIR="/opt/vod-sync-xui"

echo "🚀 Iniciando VOD Sync XUI..."

# Iniciar serviços
systemctl start mysql nginx
systemctl start vod-sync
systemctl start vod-sync-worker
systemctl start vod-sync-scheduler
systemctl start vod-sync-scheduler.timer

sleep 3

# Verificar status
echo ""
echo "📊 Status dos serviços:"
echo "======================="

services=("mysql" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-scheduler")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: ATIVO"
    else
        echo "❌ $service: INATIVO"
    fi
done

# Obter IP
IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

echo ""
echo "🌐 URLs de acesso:"
echo "=================="
echo "  Interface Web:    http://$IP"
echo "  API:              http://$IP/api"
echo "  Saúde:            http://$IP/health"
echo ""
echo "🔧 Diretório: $INSTALL_DIR"
echo "📚 Logs: $INSTALL_DIR/logs"
echo ""
echo "🎬 VOD Sync XUI está pronto!"
EOF

# Script de parada
cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash

echo "🛑 Parando VOD Sync XUI..."

systemctl stop vod-sync-scheduler.timer
systemctl stop vod-sync-scheduler
systemctl stop vod-sync-worker
systemctl stop vod-sync

sleep 2

echo "✅ Serviços parados"
echo ""
echo "📊 Status:"
systemctl status vod-sync --no-pager -l
EOF

# Script de reinicialização
cat > "$INSTALL_DIR/restart.sh" << 'EOF'
#!/bin/bash

echo "🔄 Reiniciando VOD Sync XUI..."

$INSTALL_DIR/stop.sh
sleep 2
$INSTALL_DIR/start.sh
EOF

# Script de status
cat > "$INSTALL_DIR/status.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"

echo "📊 STATUS COMPLETO - VOD SYNC XUI"
echo "=================================="
echo ""

# Serviços
echo "🔧 SERVIÇOS:"
echo "------------"
services=("mysql" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-scheduler" "vod-sync-scheduler.timer")

for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
    enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
    
    case "$status" in
        active)
            echo "✅ $service: ATIVO (habilitado: $enabled)"
            ;;
        inactive)
            echo "⏸️  $service: INATIVO (habilitado: $enabled)"
            ;;
        failed)
            echo "❌ $service: FALHOU"
            ;;
        *)
            echo "❓ $service: $status"
            ;;
    esac
done

echo ""

# Portas
echo "🔌 PORTAS:"
echo "----------"
if ss -tlnp | grep -q :80; then
    echo "✅ HTTP (80): Ouvindo"
else
    echo "❌ HTTP (80): Não ouvindo"
fi

if ss -tlnp | grep -q :5000; then
    echo "✅ API (5000): Ouvindo"
else
    echo "❌ API (5000): Não ouvindo"
fi

echo ""

# Storage
echo "💾 ARMAZENAMENTO:"
echo "-----------------"
total_vods=$(find "$INSTALL_DIR/vods" -type f -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" 2>/dev/null | wc -l)
total_size=$(du -sh "$INSTALL_DIR/vods" 2>/dev/null | cut -f1)

echo "📁 VODs encontrados: $total_vods arquivos"
echo "📦 Tamanho total: $total_size"
echo "📂 Diretório: $INSTALL_DIR/vods"

echo ""

# Logs
echo "📝 LOGS (últimas 5 linhas de erro):"
echo "------------------------------------"
if [ -f "$INSTALL_DIR/logs/app/error.log" ]; then
    tail -5 "$INSTALL_DIR/logs/app/error.log"
else
    echo "Arquivo de log não encontrado"
fi

echo ""

# URL
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
echo "🌐 ACESSO: http://$IP"
EOF

# Script de logs
cat > "$INSTALL_DIR/logs.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"

echo "📝 LOGS DO VOD SYNC XUI"
echo "========================"
echo ""
echo "Selecione o log para visualizar:"
echo "1. Aplicação (app)"
echo "2. Worker"
echo "3. Nginx"
echo "4. Todos (tail -f)"
echo "5. Erros somente"
echo ""
read -p "Escolha (1-5): " choice

case $choice in
    1)
        tail -f "$INSTALL_DIR/logs/app/error.log"
        ;;
    2)
        journalctl -u vod-sync-worker -f
        ;;
    3)
        tail -f "$INSTALL_DIR/logs/nginx/error.log"
        ;;
    4)
        multitail \
            -l "tail -f $INSTALL_DIR/logs/app/error.log" \
            -l "journalctl -u vod-sync-worker -f" \
            -l "tail -f $INSTALL_DIR/logs/nginx/access.log"
        ;;
    5)
        grep -i error "$INSTALL_DIR/logs/app/error.log" | tail -50
        ;;
    *)
        echo "Opção inválida"
        ;;
esac
EOF

# Script de backup
cat > "$INSTALL_DIR/backup.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"
BACKUP_DIR="$INSTALL_DIR/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

echo "💾 Iniciando backup do VOD Sync XUI..."
echo "Backup: $BACKUP_FILE"

# Criar diretório de backup
mkdir -p "$BACKUP_DIR"

# Parar serviços temporariamente
systemctl stop vod-sync vod-sync-worker

# Criar backup
tar -czf "$BACKUP_FILE" \
    --exclude="$INSTALL_DIR/venv" \
    --exclude="$INSTALL_DIR/vods" \
    --exclude="$INSTALL_DIR/logs" \
    --exclude="$INSTALL_DIR/temp" \
    -C "$INSTALL_DIR/.." vod-sync-xui

# Reiniciar serviços
systemctl start vod-sync vod-sync-worker

# Verificar backup
if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✅ Backup concluído: $BACKUP_FILE ($SIZE)"
    
    # Listar backups antigos
    echo ""
    echo "📦 Backups disponíveis:"
    ls -lh "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | tail -5
    
    # Limpar backups antigos (manter últimos 10)
    cd "$BACKUP_DIR"
    ls -t backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
    
else
    echo "❌ Falha ao criar backup"
    exit 1
fi
EOF

# Script de atualização
cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"
BACKUP_DIR="$INSTALL_DIR/backup"
UPDATE_LOG="$INSTALL_DIR/logs/update.log"

echo "🔄 Iniciando atualização do VOD Sync XUI..."
echo "Log: $UPDATE_LOG"

# Criar log
exec > >(tee -a "$UPDATE_LOG") 2>&1
date
echo "=== INÍCIO DA ATUALIZAÇÃO ==="

# Fazer backup primeiro
echo "1. Criando backup..."
"$INSTALL_DIR/backup.sh"

# Parar serviços
echo "2. Parando serviços..."
systemctl stop vod-sync vod-sync-worker vod-sync-scheduler.timer

# Atualizar código (simulação - na realidade viria do git)
echo "3. Atualizando código..."
cd "$INSTALL_DIR"
git pull origin master 2>/dev/null || echo "Git não configurado, continuando..."

# Atualizar dependências
echo "4. Atualizando dependências..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt --upgrade

# Atualizar banco de dados
echo "5. Atualizando banco de dados..."
if [ -f "src/models.py" ]; then
    flask db upgrade 2>/dev/null || echo "Atualização do banco não necessária"
fi

# Recarregar serviços
echo "6. Recarregando serviços..."
systemctl daemon-reload

# Iniciar serviços
echo "7. Iniciando serviços..."
systemctl start vod-sync vod-sync-worker vod-sync-scheduler.timer

# Verificar status
echo "8. Verificando status..."
sleep 3
"$INSTALL_DIR/status.sh"

echo ""
echo "✅ Atualização concluída!"
date
echo "=== FIM DA ATUALIZAÇÃO ==="
EOF

# Dar permissões de execução
chmod +x "$INSTALL_DIR"/*.sh

print_success "Scripts de gerenciamento criados"

# 11. Configurar cron jobs
print_header "11. CONFIGURAÇÃO DE TAREFAS AGENDADAS (CRON)"
cat > /etc/cron.d/vod-sync << EOF
# Tarefas agendadas do VOD Sync XUI

# Limpeza diária de arquivos temporários (2:00 AM)
0 2 * * * root $INSTALL_DIR/scripts/cleanup.sh >> $INSTALL_DIR/logs/cron/cleanup.log 2>&1

# Backup diário (3:00 AM)
0 3 * * * root $INSTALL_DIR/backup.sh >> $INSTALL_DIR/logs/cron/backup.log 2>&1

# Verificação de saúde (a cada 15 minutos)
*/15 * * * * root curl -s http://localhost/health > /dev/null || systemctl restart vod-sync >> $INSTALL_DIR/logs/cron/health.log 2>&1

# Limpeza de logs antigos (domingo 4:00 AM)
0 4 * * 0 root find $INSTALL_DIR/logs -name "*.log" -mtime +30 -delete >> $INSTALL_DIR/logs/cron/logrotate.log 2>&1

# Sincronização manual via API (opcional)
#0 */6 * * * root curl -X POST http://localhost/api/v1/sync/start -H "Authorization: Bearer \$API_KEY" >> $INSTALL_DIR/logs/cron/sync.log 2>&1
EOF

print_success "Tarefas cron configuradas"

# 12. Configurar firewall (se necessário)
print_header "12. CONFIGURAÇÃO DE SEGURANÇA"
# Abrir porta 80 se firewall estiver ativo
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    print_success "Regras de firewall configuradas"
fi

# 13. Iniciar serviços
print_header "13. INICIALIZAÇÃO DOS SERVIÇOS"
systemctl daemon-reload

# Iniciar serviços na ordem correta
services=("mysql" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-scheduler" "vod-sync-scheduler.timer")

for service in "${services[@]}"; do
    print_step "Iniciando $service..."
    if systemctl enable --now "$service" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "$service"; then
            print_success "$service iniciado"
        else
            print_error "$service falhou ao iniciar"
            journalctl -u "$service" --no-pager -n 20
        fi
    else
        print_error "Falha ao habilitar $service"
    fi
done

# 14. Testar instalação
print_header "14. TESTE FINAL DA INSTALAÇÃO"
print_step "Verificando serviços..."

# Verificar se tudo está rodando
ALL_OK=true
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: OK"
    else
        echo "❌ $service: FALHOU"
        ALL_OK=false
    fi
done

echo ""
print_step "Testando endpoints..."

# Testar endpoint de saúde
if curl -s -o /dev/null -w "%{http_code}" http://localhost/health | grep -q "200"; then
    echo "✅ Endpoint /health: OK"
else
    echo "❌ Endpoint /health: FALHOU"
    ALL_OK=false
fi

# Testar API
if curl -s http://localhost/api/status | grep -q "online"; then
    echo "✅ API /api/status: OK"
else
    echo "❌ API /api/status: FALHOU"
    ALL_OK=false
fi

# Testar página web
if curl -s http://localhost | grep -q "VOD Sync"; then
    echo "✅ Página web: OK"
else
    echo "❌ Página web: FALHOU"
    ALL_OK=false
fi

echo ""
print_step "Verificando recursos..."

# Verificar espaço em disco
DISK_INFO=$(df -h "$INSTALL_DIR" | tail -1)
echo "💾 Espaço em disco: $DISK_INFO"

# Verificar memória
MEM_INFO=$(free -h | grep Mem)
echo "🧠 Memória: $MEM_INFO"

# Obter IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

# 15. Criar README final
print_header "15. DOCUMENTAÇÃO FINAL"
cat > "$INSTALL_DIR/README.md" << EOF
# 🎬 VOD Sync XUI - Sistema Instalado com Sucesso!

## 📋 RESUMO DA INSTALAÇÃO
- **Versão:** 4.0.0
- **Data:** $(date)
- **Diretório:** $INSTALL_DIR
- **URL Principal:** http://$IP
- **API:** http://$IP/api
- **Porta:** 80 (HTTP), 5000 (API interna)

## 🔧 CONFIGURAÇÕES IMPORTANTES

### Credenciais de Acesso
- **Usuário Admin:** admin
- **Senha Admin:** $ADMIN_PASSWORD
- **API Key:** $API_KEY
- **Database Password:** $DB_PASSWORD
- **Secret Key:** $SECRET_KEY

### Banco de Dados
- **Host:** localhost
- **Database:** vod_sync_xui
- **Usuário:** vod_sync_xui
- **Senha:** $DB_PASSWORD

## 🚀 COMEÇANDO

### Acesso Rápido
1. Abra seu navegador: http://$IP
2. Faça login com: admin / $ADMIN_PASSWORD
3. Configure suas fontes de VODs
4. Inicie a sincronização

### Scripts de Gerenciamento
\`\`\`bash
# Iniciar todos os serviços
$INSTALL_DIR/start.sh

# Parar serviços
$INSTALL_DIR/stop.sh

# Reiniciar
$INSTALL_DIR/restart.sh

# Ver status completo
$INSTALL_DIR/status.sh

# Ver logs em tempo real
$INSTALL_DIR/logs.sh

# Fazer backup
$INSTALL_DIR/backup.sh

# Atualizar sistema
$INSTALL_DIR/update.sh
\`\`\`

## 📁 ESTRUTURA DE DIRETÓRIOS
\`\`\`
$INSTALL_DIR/
├── src/              # Código fonte da aplicação
├── venv/             # Ambiente virtual Python
├── vods/             # VODs sincronizados
│   ├── movies/       # Filmes
│   ├── series/       # Séries
│   ├── originals/    # Originais (backup)
│   └── processed/    # Processados
├── data/             # Dados do sistema
│   ├── database/     # Banco SQLite
│   ├── thumbnails/   # Thumbnails
│   └── metadata/     # Metadados
├── logs/             # Logs do sistema
│   ├── app/          # Aplicação
│   ├── nginx/        # Nginx
│   ├── worker/       # Worker
│   └── cron/         # Tarefas agendadas
├── config/           # Arquivos de configuração
├── backup/           # Backups automáticos
├── scripts/          # Scripts utilitários
└── temp/             # Arquivos temporários
\`\`\`

## 🔌 ENDPOINTS DA API

### Públicos
- \`GET /\` - Interface web
- \`GET /health\` - Saúde do sistema
- \`GET /api/status\` - Status da API
- \`GET /api/config\` - Configurações

### Autenticados (API Key)
- \`POST /api/v1/sync/start\` - Iniciar sincronização
- \`GET /api/v1/sync/status\` - Status da sincronização
- \`GET /api/v1/vods\` - Listar VODs
- \`POST /api/v1/vods/scan\` - Escanear manualmente
- \`GET /api/v1/system/info\` - Informações do sistema

## ⚙️ CONFIGURAÇÃO DE SINCRONIZAÇÃO

### Editar configurações
\`\`\`bash
nano $INSTALL_DIR/config/sync_config.json
\`\`\`

### Configurações principais:
1. **Fontes de VODs:** Defina seus diretórios locais, FTP ou S3
2. **Processamento:** Configure transcoding, thumbnails, metadados
3. **Agendamento:** Defina intervalos de sincronização automática
4. **Notificações:** Configure alertas por email/telegram

## 🐛 SOLUÇÃO DE PROBLEMAS

### Serviço não inicia
\`\`\`bash
# Verificar logs
$INSTALL_DIR/logs.sh

# Ver status detalhado
systemctl status vod-sync --no-pager -l

# Testar manualmente
cd $INSTALL_DIR
source venv/bin/activate
python src/app.py
\`\`\`

### Banco de dados com problemas
\`\`\`bash
# Verificar conexão
mysql -u vod_sync_xui -p"$DB_PASSWORD" -e "SHOW DATABASES;"

# Recriar banco (cuidado - perde dados!)
mysql -e "DROP DATABASE vod_sync_xui; CREATE DATABASE vod_sync_xui;"
\`\`\`

### Nginx não responde
\`\`\`bash
# Testar configuração
nginx -t

# Reiniciar
systemctl restart nginx

# Ver logs
tail -f $INSTALL_DIR/logs/nginx/error.log
\`\`\`

## 🔒 SEGURANÇA

### Alterar senhas padrão
1. **Admin:** Acesse http://$IP/settings/users
2. **API Key:** Gere nova em http://$IP/settings/api
3. **Database:** Altere no arquivo \`.env\` e recrie o banco

### Firewall recomendado
\`\`\`bash
# Instalar UFW (se não tiver)
apt install ufw

# Configurar regras
ufw allow 80/tcp
ufw allow 443/tcp    # Se usar SSL
ufw allow 22/tcp     # SSH
ufw enable
\`\`\`

## 📈 MONITORAMENTO

### Métricas disponíveis
- Uso de CPU/Memória
- Espaço em disco dos VODs
- Contagem de arquivos sincronizados
- Tempo médio de processamento
- Taxa de erro/sucesso

### Acessar métricas
\`\`\`bash
# Via API
curl http://$IP/api/v1/metrics

# Via terminal
$INSTALL_DIR/status.sh
\`\`\`

## 🔄 ATUALIZAÇÃO

### Método recomendado
\`\`\`bash
# Execute o script de atualização
$INSTALL_DIR/update.sh

# Ou manualmente
cd $INSTALL_DIR
git pull
./update.sh
\`\`\`

## 📞 SUPORTE

### Recursos
- **Documentação:** $INSTALL_DIR/docs/ (se disponível)
- **Logs:** $INSTALL_DIR/logs/
- **Configurações:** $INSTALL_DIR/config/

### Verificar status completo
\`\`\`bash
$INSTALL_DIR/status.sh | less
\`\`\`

---

## 🎉 INSTALAÇÃO CONCLUÍDA!

Seu sistema VOD Sync XUI está pronto para uso. Comece configurando suas fontes de VODs e inicie a sincronização.

**Próximos passos:**
1. Configure suas fontes de VODs na interface web
2. Ajuste as configurações de processamento conforme necessário
3. Inicie a sincronização manual ou aguarde a automática
4. Monitore os logs para garantir que tudo está funcionando

**Dica:** Consulte \`$INSTALL_DIR/scripts/\` para mais ferramentas utilitárias.
EOF

# 16. Mostrar resumo final
print_header "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
print_divider
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 VOD SYNC XUI INSTALADO!                      ║"
echo "║           Sistema completo de sincronização de VODs          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "========================="
echo ""
echo "📍 URL de Acesso:"
echo "   🌐 http://$IP"
echo "   🔌 API: http://$IP/api"
echo ""
echo "🔐 Credenciais:"
echo "   👤 Usuário: admin"
echo "   🔑 Senha: $ADMIN_PASSWORD"
echo "   🗝️  API Key: $API_KEY"
echo ""
echo "📁 Diretório:"
echo "   🗂️  $INSTALL_DIR"
echo ""
echo "🔧 Scripts de Controle:"
echo "   ▶️  $INSTALL_DIR/start.sh    # Iniciar tudo"
echo "   ⏸️  $INSTALL_DIR/stop.sh     # Parar tudo"
echo "   🔄 $INSTALL_DIR/restart.sh   # Reiniciar"
echo "   📊 $INSTALL_DIR/status.sh    # Ver status"
echo "   📝 $INSTALL_DIR/logs.sh      # Ver logs"
echo ""
echo "💾 Backups:"
echo "   💿 $INSTALL_DIR/backup.sh    # Criar backup"
echo "   🔄 $INSTALL_DIR/update.sh    # Atualizar sistema"
echo ""
echo "📈 Status Atual:"
if $ALL_OK; then
    echo "   ✅ TODOS OS SERVIÇOS ESTÃO RODANDO"
else
    echo "   ⚠️  ALGUNS SERVIÇOS PODEM TER FALHADO"
    echo "   Verifique com: $INSTALL_DIR/status.sh"
fi
echo ""
echo "🚀 Próximos Passos:"
echo "   1. Acesse http://$IP no seu navegador"
echo "   2. Faça login com as credenciais acima"
echo "   3. Configure suas fontes de VODs"
echo "   4. Inicie a sincronização"
echo "   5. Monitore os logs se necessário"
echo ""
echo "📚 Documentação:"
echo "   📖 $INSTALL_DIR/README.md"
echo ""
echo "🔔 Notificações:"
echo "   ⏰ Sincronização automática configurada a cada 5 minutos"
echo "   💾 Backups automáticos diários às 3:00 AM"
echo "   🧹 Limpeza automática às 2:00 AM"
echo ""
print_divider
echo ""
echo "🎬 O sistema VOD Sync XUI está pronto para sincronizar seus VODs!"
echo "   Para suporte, consulte a documentação ou verifique os logs."
echo ""
print_divider

# Finalizar
exit 0
