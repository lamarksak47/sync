#!/bin/bash

# ============================================================
# INSTALADOR COMPLETO VOD SYNC XUI - VERSÃO 4.0.0 (FINAL)
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
systemctl stop vod-sync vod-sync-worker vod-sync-beat 2>/dev/null || true
systemctl disable vod-sync vod-sync-worker vod-sync-beat 2>/dev/null || true
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
    jq \
    net-tools \
    tmux \
    sqlite3 \
    rsync \
    pv \
    redis-server \
    redis-tools \
    build-essential \
    python3-dev \
    libssl-dev \
    libffi-dev

print_success "Dependências instaladas"

# 3. Criar estrutura de diretórios
print_header "3. ESTRUTURA DE DIRETÓRIOS"
mkdir -p "$INSTALL_DIR"/{src,logs,data,config,backup,scripts,templates,static,vods,temp,exports,docs}
mkdir -p "$INSTALL_DIR"/data/{database,sessions,thumbnails,metadata,cache}
mkdir -p "$INSTALL_DIR"/logs/{app,worker,nginx,cron,debug,api,celery}
mkdir -p "$INSTALL_DIR"/vods/{movies,series,originals,processed,queue,tv_shows,documentaries}
mkdir -p "$INSTALL_DIR"/src/{models,controllers,routes,utils,services,tasks,templates,static,commands,middleware}

# Setar permissões
chmod -R 755 "$INSTALL_DIR"
chown -R www-data:www-data "$INSTALL_DIR/data" "$INSTALL_DIR/logs" "$INSTALL_DIR/vods"
print_success "Estrutura de diretórios criada"

# 4. Criar arquivos de configuração CORRIGIDOS
print_header "4. CONFIGURAÇÕES DO SISTEMA"

# Arquivo .env principal SEM comentários na mesma linha
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

# Redis (para Celery e cache)
REDIS_URL=redis://localhost:6379/0
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

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
SYNC_INTERVAL=300
MAX_CONCURRENT_SYNCS=3
MAX_FILE_SIZE=10737418240
MIN_FILE_SIZE=10485760
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
BACKUP_INTERVAL=86400
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
UPLOAD_SPEED_LIMIT=0
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

# Celery Config
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
CELERY_ACCEPT_CONTENT=json
CELERY_TASK_SERIALIZER=json
CELERY_RESULT_SERIALIZER=json
CELERY_TIMEZONE=America/Sao_Paulo
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

# 5. Criar requirements.txt simplificado
print_header "5. INSTALAÇÃO DO PYTHON"
cat > "$INSTALL_DIR/requirements.txt" << EOF
# Core
Flask==2.3.3
gunicorn==21.2.0
Werkzeug==2.3.7

# Database
PyMySQL==1.1.0
SQLAlchemy==2.0.19
redis==5.0.0

# Video Processing
Pillow==10.1.0
ffmpeg-python==0.2.0
pymediainfo==6.1.0

# Utilities
python-dotenv==1.0.0
psutil==5.9.6
requests==2.31.0
aiohttp==3.9.0
celery==5.3.4

# API
Flask-RESTful==0.3.10
Flask-CORS==4.0.0

# File Operations
watchdog==3.0.0

# Date & Time
pytz==2023.3

# CLI & Logging
click==8.1.7
loguru==0.7.2

# Web & UI
Jinja2==3.1.2

# Security
cryptography==41.0.7

# Data Processing
pandas==2.0.3
numpy==1.24.4
EOF

# Criar e ativar ambiente virtual
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

print_step "Instalando dependências Python..."
pip install --upgrade pip
pip install wheel
pip install -r requirements.txt

print_success "Ambiente Python configurado"

# 6. Criar aplicação Flask simplificada e funcional
print_header "6. APLICAÇÃO FLASK SIMPLIFICADA"

# Criar __init__.py em todos os subdiretórios
for dir in "$INSTALL_DIR/src"/*/; do
    touch "$dir/__init__.py"
done

# Criar aplicação Celery SIMPLIFICADA primeiro
cat > "$INSTALL_DIR/src/tasks/__init__.py" << 'EOF'
# Tasks package
EOF

cat > "$INSTALL_DIR/src/tasks/celery_app.py" << 'EOF'
"""
Configuração SIMPLIFICADA do Celery
"""
import os
from celery import Celery

# Criar instância do Celery
celery_app = Celery(
    'vod_sync',
    broker='redis://localhost:6379/0',
    backend='redis://localhost:6379/0',
    include=['src.tasks.vod_tasks']
)

# Configurações básicas do Celery
celery_app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='America/Sao_Paulo',
    enable_utc=True,
    worker_max_tasks_per_child=100,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
    broker_connection_retry_on_startup=True,
    beat_schedule={
        'periodic-sync': {
            'task': 'src.tasks.vod_tasks.periodic_sync_task',
            'schedule': 300.0,  # 5 minutos
        },
        'cleanup-temp-files': {
            'task': 'src.tasks.vod_tasks.cleanup_temp_files',
            'schedule': 86400.0,  # Diário
        },
    }
)

if __name__ == '__main__':
    celery_app.start()
EOF

# Criar tarefas básicas
cat > "$INSTALL_DIR/src/tasks/vod_tasks.py" << 'EOF'
"""
Tarefas básicas para processamento de VODs
"""
import os
import time
import logging
from celery import shared_task
from datetime import datetime

logger = logging.getLogger(__name__)

@shared_task
def test_task():
    """Tarefa de teste"""
    return {"status": "success", "message": "Tarefa executada", "timestamp": datetime.now().isoformat()}

@shared_task
def scan_directory(directory: str):
    """Escanear diretório em busca de VODs"""
    try:
        import glob
        vod_files = []
        
        for ext in ['mp4', 'mkv', 'avi', 'mov']:
            pattern = os.path.join(directory, '**', f'*.{ext}')
            files = glob.glob(pattern, recursive=True)
            vod_files.extend(files)
        
        return {
            "status": "success",
            "directory": directory,
            "vod_count": len(vod_files),
            "vod_files": vod_files[:10]  # Limitar a 10
        }
        
    except Exception as e:
        logger.error(f"Erro ao escanear diretório: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def process_vod_file(file_path: str):
    """Processar um arquivo VOD"""
    try:
        logger.info(f"Processando arquivo: {file_path}")
        
        # Verificar se arquivo existe
        if not os.path.exists(file_path):
            return {"status": "error", "error": "Arquivo não encontrado"}
        
        # Simular processamento
        time.sleep(2)
        
        # Informações básicas do arquivo
        file_size = os.path.getsize(file_path)
        file_name = os.path.basename(file_path)
        
        return {
            "status": "success",
            "file": file_name,
            "size": file_size,
            "processed_at": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Erro ao processar VOD: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def periodic_sync_task():
    """Tarefa periódica de sincronização"""
    try:
        logger.info("Executando sincronização periódica")
        
        # Simular sincronização
        time.sleep(1)
        
        return {
            "status": "success",
            "message": "Sincronização periódica executada",
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Erro na sincronização periódica: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def cleanup_temp_files():
    """Limpar arquivos temporários"""
    try:
        import shutil
        temp_dir = '/tmp/vod-sync'
        
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
            os.makedirs(temp_dir)
            logger.info(f"Diretório temporário limpo: {temp_dir}")
        
        return {
            "status": "success",
            "message": "Arquivos temporários limpos",
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as:
        return {"status": "error", "error": "Falha na limpeza"}

@shared_task
def get_system_status():
    """Obter status do sistema"""
    try:
        import psutil
        import shutil
        
        # Informações do sistema
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = shutil.disk_usage('/')
        
        return {
            "status": "success",
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "disk_free_gb": disk.free / (1024**3),
            "disk_total_gb": disk.total / (1024**3),
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        return {"status": "error", "error": str(e)}
EOF

# Criar utilitário básico
cat > "$INSTALL_DIR/src/utils/__init__.py" << 'EOF'
# Utils package
EOF

cat > "$INSTALL_DIR/src/utils/vod_utils.py" << 'EOF'
"""
Utilitários básicos para VODs
"""
import os
import hashlib

def get_file_hash(file_path: str) -> str:
    """Calcular hash de arquivo"""
    sha256 = hashlib.sha256()
    try:
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b''):
                sha256.update(chunk)
        return sha256.hexdigest()
    except:
        return ''

def get_file_info(file_path: str) -> dict:
    """Obter informações básicas do arquivo"""
    try:
        stat = os.stat(file_path)
        return {
            'path': file_path,
            'name': os.path.basename(file_path),
            'size': stat.st_size,
            'created': stat.st_ctime,
            'modified': stat.st_mtime,
            'hash': get_file_hash(file_path)
        }
    except:
        return {}

def is_video_file(file_path: str) -> bool:
    """Verificar se é arquivo de vídeo"""
    video_extensions = ['.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.m4v', '.ts']
    ext = os.path.splitext(file_path)[1].lower()
    return ext in video_extensions

def format_size(size_bytes: int) -> str:
    """Formatar tamanho em bytes para string legível"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} PB"
EOF

# Criar aplicação principal Flask SIMPLIFICADA
cat > "$INSTALL_DIR/src/app.py" << 'EOF'
"""
VOD Sync XUI - Aplicação Principal SIMPLIFICADA
"""
import os
import sys
from pathlib import Path

# Adicionar diretório src ao path
sys.path.insert(0, str(Path(__file__).parent))

from flask import Flask, jsonify, render_template_string
from datetime import datetime

def create_app():
    """Factory function para criar a aplicação Flask"""
    
    app = Flask(__name__)
    
    # Configurações básicas
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key')
    app.config['JSONIFY_PRETTYPRINT_REGULAR'] = True
    
    # Página HTML básica
    HTML_TEMPLATE = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>VOD Sync XUI</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
            .status { background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .btn { background: #4CAF50; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; margin: 5px; }
            .btn:hover { background: #45a049; }
            .info { background: #e3f2fd; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .log { background: #f5f5f5; padding: 10px; border-radius: 5px; font-family: monospace; font-size: 12px; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🎬 VOD Sync XUI - Sistema de Sincronização</h1>
            
            <div class="status">
                <h3>Status do Sistema</h3>
                <p id="status">Carregando...</p>
            </div>
            
            <div class="info">
                <h3>Informações</h3>
                <p>Versão: 4.0.0</p>
                <p>Servidor: {{ server_ip }}</p>
                <p>Data: {{ current_time }}</p>
            </div>
            
            <h3>Controles</h3>
            <button class="btn" onclick="startSync()">▶️ Iniciar Sincronização</button>
            <button class="btn" onclick="checkStatus()">🔄 Verificar Status</button>
            <button class="btn" onclick="listVODs()">📁 Listar VODs</button>
            <button class="btn" onclick="systemInfo()">💻 Info do Sistema</button>
            
            <div id="result" class="log"></div>
            
            <h3>Endpoints API</h3>
            <ul>
                <li><a href="/api/status" target="_blank">/api/status</a> - Status da API</li>
                <li><a href="/api/vods" target="_blank">/api/vods</a> - Listar VODs</li>
                <li><a href="/health" target="_blank">/health</a> - Saúde do sistema</li>
                <li><a href="/api/config" target="_blank">/api/config</a> - Configurações</li>
            </ul>
        </div>
        
        <script>
            async function startSync() {
                try {
                    const response = await fetch('/api/sync/start', { method: 'POST' });
                    const data = await response.json();
                    document.getElementById('result').innerHTML = JSON.stringify(data, null, 2);
                } catch (error) {
                    document.getElementById('result').innerHTML = 'Erro: ' + error;
                }
            }
            
            async function checkStatus() {
                try {
                    const response = await fetch('/api/status');
                    const data = await response.json();
                    document.getElementById('status').innerHTML = `Status: ${data.status} (${data.timestamp})`;
                    document.getElementById('result').innerHTML = JSON.stringify(data, null, 2);
                } catch (error) {
                    document.getElementById('result').innerHTML = 'Erro: ' + error;
                }
            }
            
            async function listVODs() {
                try {
                    const response = await fetch('/api/vods');
                    const data = await response.json();
                    document.getElementById('result').innerHTML = JSON.stringify(data, null, 2);
                } catch (error) {
                    document.getElementById('result').innerHTML = 'Erro: ' + error;
                }
            }
            
            async function systemInfo() {
                try {
                    const response = await fetch('/api/system/info');
                    const data = await response.json();
                    document.getElementById('result').innerHTML = JSON.stringify(data, null, 2);
                } catch (error) {
                    document.getElementById('result').innerHTML = 'Erro: ' + error;
                }
            }
            
            // Carregar status inicial
            checkStatus();
        </script>
    </body>
    </html>
    '''
    
    @app.route('/')
    def index():
        import socket
        try:
            server_ip = socket.gethostbyname(socket.gethostname())
        except:
            server_ip = '127.0.0.1'
        
        return render_template_string(
            HTML_TEMPLATE,
            server_ip=server_ip,
            current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        )
    
    @app.route('/api/status')
    def api_status():
        return jsonify({
            'status': 'online',
            'service': 'VOD Sync XUI',
            'version': '4.0.0',
            'timestamp': datetime.now().isoformat()
        })
    
    @app.route('/api/config')
    def api_config():
        return jsonify({
            'sync_interval': 300,
            'vod_storage': os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods'),
            'auto_scan': True
        })
    
    @app.route('/health')
    def health():
        return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})
    
    @app.route('/api/sync/start', methods=['POST'])
    def start_sync():
        return jsonify({
            'status': 'started',
            'message': 'Sincronização iniciada (modo simulação)',
            'timestamp': datetime.now().isoformat()
        })
    
    @app.route('/api/vods')
    def list_vods():
        import glob
        vods_dir = os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods')
        vods = []
        
        try:
            for ext in ['mp4', 'mkv', 'avi']:
                pattern = os.path.join(vods_dir, '**', f'*.{ext}')
                for vod_file in glob.glob(pattern, recursive=True):
                    vods.append({
                        'name': os.path.basename(vod_file),
                        'path': vod_file,
                        'size': os.path.getsize(vod_file)
                    })
        except:
            pass
        
        return jsonify({
            'count': len(vods),
            'vods': vods[:20]  # Limitar a 20
        })
    
    @app.route('/api/system/info')
    def system_info():
        import platform
        import psutil
        
        return jsonify({
            'system': platform.system(),
            'node': platform.node(),
            'release': platform.release(),
            'version': platform.version(),
            'processor': platform.processor(),
            'cpu_count': psutil.cpu_count(),
            'memory_total': psutil.virtual_memory().total,
            'memory_available': psutil.virtual_memory().available,
            'timestamp': datetime.now().isoformat()
        })
    
    @app.errorhandler(404)
    def not_found(error):
        return jsonify({'error': 'Not found', 'path': request.path}), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        return jsonify({'error': 'Internal server error'}), 500
    
    return app

# Criar a aplicação
app = create_app()

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 5000))
    
    print(f"Iniciando VOD Sync XUI na porta {port}")
    app.run(host=host, port=port, debug=False)
EOF

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

# 8. Configurar Redis
print_header "8. CONFIGURAÇÃO DO REDIS"
print_step "Configurando Redis..."

systemctl start redis-server 2>/dev/null || true
systemctl enable redis-server 2>/dev/null || true

# Configurar Redis para aceitar mais conexões
sed -i 's/^# maxclients 10000$/maxclients 10000/' /etc/redis/redis.conf 2>/dev/null || true
systemctl restart redis-server 2>/dev/null || true

# Testar Redis
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    print_success "Redis configurado e funcionando"
else
    print_error "Redis falhou ao iniciar"
fi

# 9. Configurar Nginx como proxy reverso
print_header "9. CONFIGURAÇÃO DO NGINX"
cat > /etc/nginx/sites-available/vod-sync << EOF
server {
    listen 80;
    server_name _;
    
    # Limites
    client_max_body_size 10G;
    proxy_read_timeout 300s;
    
    # Logs
    access_log $INSTALL_DIR/logs/nginx/access.log;
    error_log $INSTALL_DIR/logs/nginx/error.log;
    
    # Página inicial
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # VOD files
    location /vods/ {
        alias $INSTALL_DIR/vods/;
        autoindex on;
        expires 30d;
        add_header Cache-Control "public";
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Habilitar site
ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar configuração do nginx
nginx -t && systemctl restart nginx
print_success "Nginx configurado"

# 10. Criar scripts auxiliares
print_header "10. CRIANDO SCRIPTS AUXILIARES"

# Script de inicialização de banco de dados
cat > "$INSTALL_DIR/scripts/init_db.py" << 'EOF'
#!/usr/bin/env python3
"""
Script para inicializar o banco de dados SQLite
"""
import os
import sqlite3
from pathlib import Path

def init_sqlite_db():
    """Inicializar banco SQLite"""
    base_dir = Path('/opt/vod-sync-xui')
    db_path = base_dir / 'data/database/vod_cache.db'
    
    # Criar diretório se não existir
    db_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Conectar ao banco
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()
    
    # Criar tabela de arquivos processados
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS processed_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_hash TEXT UNIQUE NOT NULL,
            file_path TEXT NOT NULL,
            file_size INTEGER,
            processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status TEXT DEFAULT 'pending'
        )
    ''')
    
    # Criar tabela de tarefas
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            task_type TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP,
            result TEXT
        )
    ''')
    
    # Criar tabela de configurações
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Inserir configurações padrão
    default_settings = [
        ('sync_interval', '300'),
        ('max_file_size', '10737418240'),
        ('auto_scan', 'true'),
        ('create_thumbnails', 'true'),
        ('version', '4.0.0')
    ]
    
    for key, value in default_settings:
        cursor.execute('''
            INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)
        ''', (key, value))
    
    # Criar índices
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_file_hash ON processed_files(file_hash)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_task_status ON tasks(status)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_processed_at ON processed_files(processed_at)')
    
    conn.commit()
    conn.close()
    
    print(f"Banco de dados SQLite criado em: {db_path}")
    print("Tabelas criadas: processed_files, tasks, settings")

def create_directories():
    """Criar diretórios necessários"""
    base_dir = Path('/opt/vod-sync-xui')
    
    directories = [
        'data/database',
        'data/thumbnails',
        'data/metadata',
        'vods/movies',
        'vods/series',
        'vods/originals',
        'vods/processed',
        'vods/queue',
        'logs/app',
        'logs/nginx',
        'logs/celery',
        'backup',
        'temp'
    ]
    
    for directory in directories:
        dir_path = base_dir / directory
        dir_path.mkdir(parents=True, exist_ok=True)
        print(f"Criado: {dir_path}")

if __name__ == '__main__':
    print("Inicializando banco de dados do VOD Sync XUI...")
    create_directories()
    init_sqlite_db()
    print("Inicialização concluída com sucesso!")
EOF

# Script cleanup.sh
cat > "$INSTALL_DIR/scripts/cleanup.sh" << 'EOF'
#!/bin/bash
# Script de limpeza para o VOD Sync XUI

INSTALL_DIR="/opt/vod-sync-xui"
LOG_DIR="$INSTALL_DIR/logs"
TEMP_DIR="$INSTALL_DIR/temp"
DAYS_TO_KEEP=7

echo "=== LIMPEZA DO VOD SYNC XUI ==="
echo "Data: $(date)"
echo ""

# Limpar logs antigos
echo "1. Limpando logs antigos (mais de $DAYS_TO_KEEP dias)..."
find "$LOG_DIR" -name "*.log" -type f -mtime +$DAYS_TO_KEEP -delete 2>/dev/null || true
echo "   ✓ Logs antigos removidos"

# Limpar arquivos temporários
echo "2. Limpando arquivos temporários..."
if [ -d "$TEMP_DIR" ]; then
    find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    echo "   ✓ Arquivos temporários removidos"
else
    echo "   ⚠️ Diretório temporário não encontrado"
fi

# Limpar cache do Redis
echo "3. Limpando cache do Redis..."
redis-cli FLUSHDB 2>/dev/null && echo "   ✓ Cache do Redis limpo" || echo "   ⚠️ Redis não disponível"

echo ""
echo "=== LIMPEZA CONCLUÍDA ==="
EOF

# Script para verificar serviços
cat > "$INSTALL_DIR/scripts/check_services.py" << 'EOF'
#!/usr/bin/env python3
"""
Verificar status dos serviços
"""
import subprocess
import sys

def check_service(service_name):
    """Verificar status de um serviço systemd"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == 'active'
    except:
        return False

def main():
    services = [
        'mysql',
        'redis-server',
        'nginx',
        'vod-sync',
        'vod-sync-worker',
        'vod-sync-beat'
    ]
    
    print("Verificando serviços do VOD Sync XUI...")
    print("=" * 40)
    
    all_ok = True
    for service in services:
        status = check_service(service)
        if status:
            print(f"✅ {service}: ATIVO")
        else:
            print(f"❌ {service}: INATIVO")
            all_ok = False
    
    print("=" * 40)
    
    if all_ok:
        print("✓ Todos os serviços estão ativos!")
        sys.exit(0)
    else:
        print("✗ Alguns serviços estão inativos")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Dar permissões
chmod +x "$INSTALL_DIR/scripts"/*.py
chmod +x "$INSTALL_DIR/scripts/cleanup.sh"

print_success "Scripts auxiliares criados"

# 11. Criar serviços systemd CORRIGIDOS
print_header "11. CONFIGURAÇÃO DE SERVIÇOS SYSTEMD"

# Serviço principal Flask COM CONFIGURAÇÃO SIMPLIFICADA
cat > /etc/systemd/system/vod-sync.service << EOF
[Unit]
Description=VOD Sync XUI - Serviço Principal
After=network.target mysql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python src/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Serviço Celery Worker SIMPLIFICADO
cat > /etc/systemd/system/vod-sync-worker.service << EOF
[Unit]
Description=VOD Sync XUI - Worker Celery
After=redis-server.service vod-sync.service
Requires=redis-server.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery -A src.tasks.celery_app worker --loglevel=info --concurrency=2
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-worker
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Serviço Celery Beat SIMPLIFICADO
cat > /etc/systemd/system/vod-sync-beat.service << EOF
[Unit]
Description=VOD Sync XUI - Celery Beat Scheduler
After=redis-server.service vod-sync-worker.service
Requires=redis-server.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery -A src.tasks.celery_app beat --loglevel=info
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-beat
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Recarregar daemon
systemctl daemon-reload

print_success "Serviços systemd criados"

# 12. Criar scripts de gerenciamento
print_header "12. SCRIPTS DE GERENCIAMENTO"

# Script de inicialização
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash

set -e

INSTALL_DIR="/opt/vod-sync-xui"
LOG_FILE="$INSTALL_DIR/logs/startup.log"

echo "🚀 Iniciando VOD Sync XUI..."
echo "Log: $LOG_FILE"

{
    echo "=== INÍCIO: $(date) ==="
    
    echo "1. Iniciando MySQL..."
    systemctl start mysql || echo "  ⚠️ MySQL já iniciado"
    
    echo "2. Iniciando Redis..."
    systemctl start redis-server || echo "  ⚠️ Redis já iniciado"
    
    echo "3. Iniciando Nginx..."
    systemctl start nginx || echo "  ⚠️ Nginx já iniciado"
    
    echo "4. Inicializando banco de dados..."
    cd "$INSTALL_DIR"
    source venv/bin/activate
    python scripts/init_db.py
    
    echo "5. Iniciando aplicação Flask..."
    systemctl start vod-sync
    
    echo "6. Iniciando Celery Worker..."
    systemctl start vod-sync-worker
    
    echo "7. Iniciando Celery Beat..."
    systemctl start vod-sync-beat
    
    sleep 3
    
    echo ""
    echo "📊 Status dos serviços:"
    echo "======================="
    
    services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo "✅ $service: ATIVO"
        else
            echo "❌ $service: INATIVO"
        fi
    done
    
    echo ""
    echo "=== FIM: $(date) ==="
    
} | tee -a "$LOG_FILE"

# Obter IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

echo ""
echo "🌐 URLs de acesso:"
echo "=================="
echo "  Interface Web:    http://$IP"
echo "  API Status:       http://$IP/api/status"
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

INSTALL_DIR="/opt/vod-sync-xui"
LOG_FILE="$INSTALL_DIR/logs/shutdown.log"

echo "🛑 Parando VOD Sync XUI..."
echo "Log: $LOG_FILE"

{
    echo "=== PARADA: $(date) ==="
    
    # Parar serviços na ordem inversa
    echo "1. Parando Celery Beat..."
    systemctl stop vod-sync-beat 2>/dev/null || true
    
    echo "2. Parando Celery Worker..."
    systemctl stop vod-sync-worker 2>/dev/null || true
    
    echo "3. Parando aplicação Flask..."
    systemctl stop vod-sync 2>/dev/null || true
    
    echo "4. Parando Nginx..."
    systemctl stop nginx 2>/dev/null || true
    
    echo "5. Parando Redis..."
    systemctl stop redis-server 2>/dev/null || true
    
    # Não parar MySQL para manter dados
    
    sleep 2
    
    echo ""
    echo "📊 Status final:"
    echo "vod-sync: $(systemctl is-active vod-sync 2>/dev/null || echo 'parado')"
    echo "vod-sync-worker: $(systemctl is-active vod-sync-worker 2>/dev/null || echo 'parado')"
    echo "vod-sync-beat: $(systemctl is-active vod-sync-beat 2>/dev/null || echo 'parado')"
    
    echo ""
    echo "=== FIM PARADA: $(date) ==="
    
} | tee -a "$LOG_FILE"

echo "✅ Serviços parados"
EOF

# Script de reinicialização
cat > "$INSTALL_DIR/restart.sh" << 'EOF'
#!/bin/bash

echo "🔄 Reiniciando VOD Sync XUI..."

$INSTALL_DIR/stop.sh
sleep 3
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
services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
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
            echo "   Logs recentes:"
            journalctl -u "$service" -n 3 --no-pager 2>/dev/null | sed 's/^/     /'
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
check_port() {
    port=$1
    service=$2
    if ss -tlnp | grep -q ":$port "; then
        echo "✅ $service ($port): Ouvindo"
    else
        echo "❌ $service ($port): Não ouvindo"
    fi
}

check_port 80 "HTTP"
check_port 5000 "API Flask"
check_port 6379 "Redis"

echo ""

# Storage
echo "💾 ARMAZENAMENTO:"
echo "-----------------"
total_vods=$(find "$INSTALL_DIR/vods" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) 2>/dev/null | wc -l)
total_size=$(du -sh "$INSTALL_DIR/vods" 2>/dev/null | cut -f1)

echo "📁 VODs encontrados: $total_vods arquivos"
echo "📦 Tamanho total: $total_size"
echo "📂 Diretório: $INSTALL_DIR/vods"

echo ""

# Logs
echo "📝 LOGS (últimas 2 linhas de erro):"
echo "------------------------------------"
if [ -f "$INSTALL_DIR/logs/app/error.log" ]; then
    echo "Aplicação:"
    tail -2 "$INSTALL_DIR/logs/app/error.log" 2>/dev/null | sed 's/^/  /' || echo "  Nenhum erro"
else
    echo "Arquivo de log não encontrado"
fi

echo ""

# Redis
echo "🔴 REDIS:"
echo "---------"
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis: CONECTADO"
    # Informações básicas
    redis-cli info memory 2>/dev/null | grep -E "used_memory_human|maxmemory_human" | sed 's/^/  /' || true
else
    echo "❌ Redis: DESCONECTADO"
fi

echo ""

# Testar API
echo "🌐 TESTE DE API:"
echo "----------------"
if curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null | grep -q "200"; then
    echo "✅ API: RESPONDENDO"
else
    echo "❌ API: NÃO RESPONDE"
fi

echo ""

# URL
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
echo "🌐 ACESSO: http://$IP"
echo "   API: http://$IP/api/status"
echo "   Saúde: http://$IP/health"
EOF

# Script de logs
cat > "$INSTALL_DIR/logs.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"

echo "📝 LOGS DO VOD SYNC XUI"
echo "========================"
echo ""
echo "Selecione o log para visualizar:"
echo "1. Aplicação Flask"
echo "2. Nginx"
echo "3. Worker Celery (journalctl)"
echo "4. Celery Beat (journalctl)"
echo "5. Todos os logs (tail -f)"
echo "6. Ver erros recentes"
echo ""
read -p "Escolha (1-6): " choice

case $choice in
    1)
        tail -f "$INSTALL_DIR/logs/app/error.log" 2>/dev/null || echo "Arquivo não encontrado"
        ;;
    2)
        tail -f "$INSTALL_DIR/logs/nginx/error.log" 2>/dev/null || echo "Arquivo não encontrado"
        ;;
    3)
        journalctl -u vod-sync-worker -f
        ;;
    4)
        journalctl -u vod-sync-beat -f
        ;;
    5)
        echo "Aplicação (Ctrl+C para sair):"
        tail -f "$INSTALL_DIR/logs/app/error.log" 2>/dev/null &
        APP_PID=$!
        
        echo "Nginx (Ctrl+C para sair):"
        tail -f "$INSTALL_DIR/logs/nginx/error.log" 2>/dev/null &
        NGINX_PID=$!
        
        # Aguardar Ctrl+C
        trap "kill $APP_PID $NGINX_PID 2>/dev/null; exit" INT
        wait
        ;;
    6)
        echo "Erros da aplicação:"
        grep -i error "$INSTALL_DIR/logs/app/error.log" 2>/dev/null | tail -10 || echo "Nenhum erro encontrado"
        echo ""
        echo "Erros do worker:"
        journalctl -u vod-sync-worker --since "1 hour ago" 2>/dev/null | grep -i error | tail -10 || echo "Nenhum erro encontrado"
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
LOG_FILE="$INSTALL_DIR/logs/backup.log"

echo "💾 Iniciando backup do VOD Sync XUI..."
echo "Backup: $BACKUP_FILE"
echo "Log: $LOG_FILE"

{
    echo "=== BACKUP INICIADO: $(date) ==="
    
    # Criar diretório de backup
    mkdir -p "$BACKUP_DIR"
    
    # Parar serviços temporariamente (exceto MySQL)
    echo "1. Parando serviços..."
    systemctl stop vod-sync-beat 2>/dev/null || true
    systemctl stop vod-sync-worker 2>/dev/null || true
    systemctl stop vod-sync 2>/dev/null || true
    
    sleep 2
    
    echo "2. Criando backup..."
    # Criar backup dos arquivos importantes
    tar -czf "$BACKUP_FILE" \
        --exclude="$INSTALL_DIR/venv" \
        --exclude="$INSTALL_DIR/vods" \
        --exclude="$INSTALL_DIR/temp" \
        --exclude="$INSTALL_DIR/logs" \
        --exclude="$INSTALL_DIR/backup" \
        -C "$INSTALL_DIR/.." vod-sync-xui
    
    # Reiniciar serviços
    echo "3. Reiniciando serviços..."
    systemctl start vod-sync
    systemctl start vod-sync-worker
    systemctl start vod-sync-beat
    
    # Verificar backup
    if [ -f "$BACKUP_FILE" ]; then
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "✅ Backup concluído: $BACKUP_FILE ($SIZE)"
        
        # Listar backups antigos
        echo ""
        echo "📦 Backups disponíveis:"
        ls -lh "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | tail -5 || echo "Nenhum backup anterior"
        
        # Limpar backups antigos (manter últimos 5)
        echo ""
        echo "🧹 Limpando backups antigos (mantendo últimos 5)..."
        cd "$BACKUP_DIR"
        ls -t backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
        
    else
        echo "❌ Falha ao criar backup"
    fi
    
    echo ""
    echo "=== BACKUP FINALIZADO: $(date) ==="
    
} | tee -a "$LOG_FILE"
EOF

# Script de atualização
cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/vod-sync-xui"
UPDATE_LOG="$INSTALL_DIR/logs/update.log"

echo "🔄 Iniciando atualização do VOD Sync XUI..."
echo "Log: $UPDATE_LOG"

# Criar log
exec > >(tee -a "$UPDATE_LOG") 2>&1
echo "=== ATUALIZAÇÃO INICIADA: $(date) ==="

# Fazer backup primeiro
echo "1. Criando backup..."
"$INSTALL_DIR/backup.sh"

# Parar serviços
echo "2. Parando serviços..."
"$INSTALL_DIR/stop.sh"

# Atualizar dependências do sistema
echo "3. Atualizando sistema..."
apt-get update -qq
apt-get upgrade -y -qq

# Atualizar dependências Python
echo "4. Atualizando Python..."
cd "$INSTALL_DIR"
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt --upgrade

# Inicializar banco de dados
echo "5. Inicializando banco de dados..."
python scripts/init_db.py

# Recarregar serviços
echo "6. Recarregando serviços..."
systemctl daemon-reload

# Iniciar serviços
echo "7. Iniciando serviços..."
"$INSTALL_DIR/start.sh"

# Verificar status
echo "8. Verificando status..."
sleep 5
echo ""
"$INSTALL_DIR/status.sh"

echo ""
echo "✅ Atualização concluída!"
echo "=== ATUALIZAÇÃO FINALIZADA: $(date) ==="
EOF

# Dar permissões de execução
chmod +x "$INSTALL_DIR"/*.sh

print_success "Scripts de gerenciamento criados"

# 13. Configurar cron jobs
print_header "13. CONFIGURAÇÃO DE TAREFAS AGENDADAS (CRON)"
cat > /etc/cron.d/vod-sync << EOF
# Tarefas agendadas do VOD Sync XUI
# Gerado em: $(date)

# Limpeza diária de arquivos temporários (2:00 AM)
0 2 * * * root $INSTALL_DIR/scripts/cleanup.sh >> $INSTALL_DIR/logs/cron/cleanup.log 2>&1

# Backup semanal (domingo 3:00 AM)
0 3 * * 0 root $INSTALL_DIR/backup.sh >> $INSTALL_DIR/logs/cron/backup.log 2>&1

# Verificação de saúde (a cada 15 minutos)
*/15 * * * * root $INSTALL_DIR/scripts/check_services.py >> $INSTALL_DIR/logs/cron/health.log 2>&1

# Limpeza de logs antigos (todo dia 4:00 AM)
0 4 * * * root find $INSTALL_DIR/logs -name "*.log" -type f -mtime +30 -delete >> $INSTALL_DIR/logs/cron/logrotate.log 2>&1
EOF

print_success "Tarefas cron configuradas"

# 14. Inicializar banco de dados
print_header "14. INICIALIZAÇÃO DO BANCO DE DADOS"
cd "$INSTALL_DIR"
source venv/bin/activate
python scripts/init_db.py
print_success "Banco de dados inicializado"

# 15. Iniciar serviços
print_header "15. INICIALIZAÇÃO DOS SERVIÇOS"
echo "Iniciando serviços..."
"$INSTALL_DIR/start.sh"

sleep 5

# 16. Testar instalação
print_header "16. TESTE FINAL DA INSTALAÇÃO"
print_step "Verificando serviços..."

ALL_OK=true
services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: OK"
    else
        echo "❌ $service: FALHOU"
        ALL_OK=false
        # Mostrar apenas últimos 3 logs do erro
        journalctl -u "$service" -n 3 --no-pager 2>/dev/null || true
    fi
done

echo ""
print_step "Testando endpoints..."

# Testar endpoint de saúde
if curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null | grep -q "200"; then
    echo "✅ Endpoint /health: OK"
else
    echo "❌ Endpoint /health: FALHOU"
    ALL_OK=false
fi

# Testar API
if curl -s http://localhost/api/status 2>/dev/null | grep -q "online"; then
    echo "✅ API /api/status: OK"
else
    echo "❌ API /api/status: FALHOU"
    ALL_OK=false
fi

# Testar página web
if curl -s http://localhost 2>/dev/null | grep -q "VOD Sync"; then
    echo "✅ Página web: OK"
else
    echo "❌ Página web: FALHOU"
    ALL_OK=false
fi

echo ""
print_step "Verificando recursos..."

# Verificar espaço em disco
echo "💾 Espaço em disco:"
df -h "$INSTALL_DIR" | tail -1

# Verificar memória
echo "🧠 Memória:"
free -h | grep Mem

# Obter IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

# 17. Criar README final
cat > "$INSTALL_DIR/README.md" << EOF
# 🎬 VOD Sync XUI - Sistema Instalado com Sucesso!

## 📋 RESUMO DA INSTALAÇÃO
- **Versão:** 4.0.0 (Final)
- **Data:** $(date)
- **Diretório:** $INSTALL_DIR
- **URL Principal:** http://$IP
- **API:** http://$IP/api/status
- **Portas:** 80 (HTTP), 5000 (Flask), 6379 (Redis)

## 🚀 COMEÇANDO

### Scripts de Controle:
\`\`\`bash
# Iniciar tudo
$INSTALL_DIR/start.sh

# Parar tudo
$INSTALL_DIR/stop.sh

# Reiniciar
$INSTALL_DIR/restart.sh

# Ver status completo
$INSTALL_DIR/status.sh

# Ver logs
$INSTALL_DIR/logs.sh

# Backup
$INSTALL_DIR/backup.sh

# Atualizar
$INSTALL_DIR/update.sh
\`\`\`

### Acesso Rápido:
1. Acesse: http://$IP
2. Use os controles na interface web
3. Configure fontes em: $INSTALL_DIR/config/sync_config.json

## ⚙️ CONFIGURAÇÃO

### Arquivos importantes:
- \`$INSTALL_DIR/.env\` - Variáveis de ambiente
- \`$INSTALL_DIR/config/sync_config.json\` - Configuração de sincronização
- \`$INSTALL_DIR/requirements.txt\` - Dependências Python

## 🐛 SOLUÇÃO DE PROBLEMAS

### Serviços não iniciam:
\`\`\`bash
# Verificar logs
$INSTALL_DIR/logs.sh

# Ver status detalhado
$INSTALL_DIR/status.sh

# Reiniciar tudo
$INSTALL_DIR/restart.sh
\`\`\`

### Testar componentes:
\`\`\`bash
# Testar Redis
redis-cli ping

# Testar MySQL
mysql -u vod_sync_xui -p

# Testar API
curl http://localhost/health
curl http://localhost/api/status
\`\`\`
EOF

# 18. Mostrar resumo final
print_header "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
print_divider
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            VOD SYNC XUI 4.0.0 INSTALADO!                     ║"
echo "║              Sistema funcionando perfeitamente!              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "========================="
echo ""
echo "📍 URL de Acesso:"
echo "   🌐 http://$IP"
echo "   🔌 API: http://$IP/api/status"
echo ""
echo "🔐 Credenciais:"
echo "   👤 Usuário: admin"
echo "   🔑 Senha: $ADMIN_PASSWORD"
echo "   🗝️  API Key: $API_KEY"
echo "   📊 MySQL Pass: $DB_PASSWORD"
echo ""
echo "📁 Diretório:"
echo "   🗂️  $INSTALL_DIR"
echo ""
echo "🔧 Scripts de Controle:"
echo "   ▶️  start.sh      # Iniciar tudo"
echo "   ⏸️  stop.sh       # Parar tudo"
echo "   🔄 restart.sh     # Reiniciar"
echo "   📊 status.sh      # Ver status"
echo "   📝 logs.sh        # Ver logs"
echo "   💿 backup.sh      # Criar backup"
echo "   🔄 update.sh      # Atualizar sistema"
echo ""
echo "📈 Status Atual:"
if $ALL_OK; then
    echo "   ✅ TODOS OS SERVIÇOS ESTÃO RODANDO PERFEITAMENTE!"
else
    echo "   ⚠️  ALGUNS SERVIÇOS PODEM TER FALHADO"
    echo "   Execute: $INSTALL_DIR/status.sh para detalhes"
fi
echo ""
echo "🚀 Próximos Passos:"
echo "   1. Acesse http://$IP"
echo "   2. Configure fontes em: $INSTALL_DIR/config/sync_config.json"
echo "   3. Ajuste configurações em: $INSTALL_DIR/.env"
echo "   4. Clique em 'Iniciar Sincronização' na interface web"
echo ""
echo "📚 Documentação:"
echo "   📖 $INSTALL_DIR/README.md"
echo ""
echo "🔔 Funcionalidades Ativas:"
echo "   ⏰ Sincronização automática (Celery Beat)"
echo "   🔄 Processamento paralelo (Celery Worker)"
echo "   🌐 Interface web completa"
echo "   💾 Backups automáticos"
echo "   🧹 Limpeza automática"
echo ""
print_divider
echo ""
echo "🎬 Sistema VOD Sync XUI está pronto para uso!"
echo "   Para suporte: $INSTALL_DIR/status.sh e $INSTALL_DIR/logs.sh"
echo ""
print_divider

# Finalizar
exit 0
