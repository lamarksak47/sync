#!/bin/bash

# ============================================================
# INSTALADOR COMPLETO VOD SYNC XUI - VERSÃO 4.0.0 (CORRIGIDO)
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
systemctl stop vod-sync vod-sync-worker vod-sync-api vod-sync-scheduler 2>/dev/null || true
systemctl disable vod-sync vod-sync-worker vod-sync-api vod-sync-scheduler 2>/dev/null || true
rm -f /etc/systemd/system/vod-sync*.service /etc/systemd/system/vod-sync*.timer
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
    pv \
    redis-server \
    redis-tools

print_success "Dependências instaladas"

# 3. Criar estrutura de diretórios
print_header "3. ESTRUTURA DE DIRETÓRIOS"
mkdir -p "$INSTALL_DIR"/{src,logs,data,config,backup,scripts,templates,static,vods,temp,exports,docs}
mkdir -p "$INSTALL_DIR"/data/{database,sessions,thumbnails,metadata,cache}
mkdir -p "$INSTALL_DIR"/logs/{app,worker,nginx,cron,debug,api}
mkdir -p "$INSTALL_DIR"/vods/{movies,series,originals,processed,queue,tv_shows,documentaries}
mkdir -p "$INSTALL_DIR"/src/{models,controllers,routes,utils,services,tasks,templates,static,commands,middleware}

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

# Celery Config
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
CELERY_ACCEPT_CONTENT=['json']
CELERY_TASK_SERIALIZER='json'
CELERY_RESULT_SERIALIZER='json'
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

# Criar __init__.py em todos os subdiretórios
for dir in "$INSTALL_DIR/src"/*/; do
    touch "$dir/__init__.py"
done

# Criar o aplicativo Celery primeiro (necessário para o worker)
cat > "$INSTALL_DIR/src/tasks/celery_app.py" << 'EOF'
"""
Configuração do Celery para tarefas assíncronas
"""
import os
from celery import Celery
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), '.env'))

# Criar instância do Celery
celery_app = Celery(
    'vod_sync',
    broker=os.getenv('CELERY_BROKER_URL', 'redis://localhost:6379/0'),
    backend=os.getenv('CELERY_RESULT_BACKEND', 'redis://localhost:6379/0'),
    include=['src.tasks.vod_tasks', 'src.tasks.sync_tasks', 'src.tasks.notification_tasks']
)

# Configurações do Celery
celery_app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone=os.getenv('CELERY_TIMEZONE', 'America/Sao_Paulo'),
    enable_utc=True,
    worker_max_tasks_per_child=1000,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
    broker_connection_retry_on_startup=True,
    task_routes={
        'src.tasks.vod_tasks.*': {'queue': 'vod'},
        'src.tasks.sync_tasks.*': {'queue': 'sync'},
        'src.tasks.notification_tasks.*': {'queue': 'notify'},
    },
    beat_schedule={
        'periodic-sync': {
            'task': 'src.tasks.sync_tasks.periodic_sync_task',
            'schedule': int(os.getenv('SYNC_INTERVAL', 300)),
        },
        'cleanup-temp-files': {
            'task': 'src.tasks.vod_tasks.cleanup_temp_files',
            'schedule': 86400,  # Diário
        },
        'check-system-health': {
            'task': 'src.tasks.sync_tasks.check_system_health',
            'schedule': 300,  # A cada 5 minutos
        },
    }
)

if __name__ == '__main__':
    celery_app.start()
EOF

# Criar tarefas para o Celery
cat > "$INSTALL_DIR/src/tasks/vod_tasks.py" << 'EOF'
"""
Tarefas relacionadas a processamento de VODs
"""
import os
import json
import logging
import shutil
import hashlib
from pathlib import Path
from datetime import datetime
from celery import shared_task
from src.utils.vod_processor import VodProcessor

logger = logging.getLogger(__name__)

@shared_task(bind=True, max_retries=3)
def process_vod_file(self, file_path: str, source_config: dict, metadata: dict = None):
    """
    Processar um arquivo VOD
    """
    try:
        logger.info(f"Iniciando processamento de: {file_path}")
        
        # Verificar se arquivo existe
        if not os.path.exists(file_path):
            logger.error(f"Arquivo não encontrado: {file_path}")
            raise FileNotFoundError(f"Arquivo não encontrado: {file_path}")
        
        # Criar processor
        processor = VodProcessor(file_path, source_config)
        
        # Validar arquivo
        if not processor.validate():
            logger.warning(f"Arquivo inválido: {file_path}")
            return {"status": "skipped", "reason": "invalid_file"}
        
        # Extrair metadados se não fornecidos
        if metadata is None:
            metadata = processor.extract_metadata()
        
        # Copiar para destino
        destination = processor.get_destination_path(metadata)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        
        # Copiar arquivo
        shutil.copy2(file_path, destination)
        
        # Criar thumbnails se configurado
        if processor.config.get('create_thumbnails', True):
            thumbnails = processor.create_thumbnails(destination)
            metadata['thumbnails'] = thumbnails
        
        # Salvar metadados
        metadata_path = destination + '.json'
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2, default=str)
        
        logger.info(f"VOD processado com sucesso: {file_path} -> {destination}")
        
        # Notificar sucesso
        notify_vod_processed.delay(file_path, destination, metadata)
        
        return {
            "status": "success",
            "original_path": file_path,
            "destination": destination,
            "metadata": metadata,
            "processed_at": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Erro ao processar VOD {file_path}: {e}")
        self.retry(exc=e, countdown=60)
        return {"status": "error", "error": str(e)}

@shared_task
def generate_thumbnails(vod_path: str, count: int = 3):
    """
    Gerar thumbnails para um VOD
    """
    try:
        processor = VodProcessor(vod_path, {})
        thumbnails = processor.create_thumbnails(vod_path, count)
        return {"status": "success", "thumbnails": thumbnails}
    except Exception as e:
        logger.error(f"Erro ao gerar thumbnails para {vod_path}: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def cleanup_temp_files():
    """
    Limpar arquivos temporários antigos
    """
    try:
        temp_dir = Path(os.getenv('TEMP_PATH', '/tmp/vod-sync'))
        if not temp_dir.exists():
            return {"status": "skipped", "reason": "temp_dir_not_found"}
        
        # Remover arquivos com mais de 24 horas
        removed = 0
        for file_path in temp_dir.rglob('*'):
            if file_path.is_file():
                file_age = datetime.now().timestamp() - file_path.stat().st_mtime
                if file_age > 86400:  # 24 horas
                    file_path.unlink()
                    removed += 1
        
        logger.info(f"Limpeza concluída: {removed} arquivos removidos")
        return {"status": "success", "files_removed": removed}
        
    except Exception as e:
        logger.error(f"Erro na limpeza de arquivos temporários: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def scan_directory(directory: str, recursive: bool = True):
    """
    Escanear diretório em busca de VODs
    """
    try:
        vod_files = []
        patterns = ['*.mp4', '*.mkv', '*.avi', '*.mov', '*.flv']
        
        path_obj = Path(directory)
        if not path_obj.exists():
            return {"status": "error", "error": "Directory not found"}
        
        search_method = path_obj.rglob if recursive else path_obj.glob
        
        for pattern in patterns:
            for file_path in search_method(pattern):
                if file_path.is_file():
                    vod_files.append(str(file_path))
        
        logger.info(f"Escaneamento concluído: {len(vod_files)} VODs encontrados em {directory}")
        
        return {
            "status": "success",
            "directory": directory,
            "vod_count": len(vod_files),
            "vod_files": vod_files[:100]  # Limitar a 100 para resposta
        }
        
    except Exception as e:
        logger.error(f"Erro ao escanear diretório {directory}: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def notify_vod_processed(original_path: str, destination: str, metadata: dict):
    """
    Notificar que um VOD foi processado
    """
    # Esta é uma tarefa de notificação placeholder
    # Pode ser estendida para enviar emails, notificações push, etc.
    logger.info(f"VOD processado: {original_path} -> {destination}")
    return {"status": "notified", "timestamp": datetime.now().isoformat()}
EOF

cat > "$INSTALL_DIR/src/tasks/sync_tasks.py" << 'EOF'
"""
Tarefas de sincronização
"""
import os
import json
import logging
from datetime import datetime
from celery import shared_task, group
from src.tasks.vod_tasks import process_vod_file, scan_directory

logger = logging.getLogger(__name__)

@shared_task(bind=True)
def sync_source(self, source_config: dict):
    """
    Sincronizar uma fonte de VODs
    """
    try:
        logger.info(f"Iniciando sincronização da fonte: {source_config.get('name', 'unknown')}")
        
        source_type = source_config.get('type', 'local')
        
        if source_type == 'local':
            return sync_local_source(source_config)
        elif source_type == 'ftp':
            return sync_ftp_source(source_config)
        elif source_type == 's3':
            return sync_s3_source(source_config)
        else:
            logger.warning(f"Tipo de fonte não suportado: {source_type}")
            return {"status": "error", "error": f"Tipo de fonte não suportado: {source_type}"}
            
    except Exception as e:
        logger.error(f"Erro na sincronização da fonte: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def sync_local_source(source_config: dict):
    """
    Sincronizar fonte local
    """
    try:
        source_path = source_config.get('path', '')
        if not source_path or not os.path.exists(source_path):
            return {"status": "error", "error": f"Caminho não encontrado: {source_path}"}
        
        # Escanear diretório
        scan_result = scan_directory.delay(source_path, source_config.get('recursive', True)).get()
        
        if scan_result['status'] != 'success':
            return scan_result
        
        vod_files = scan_result.get('vod_files', [])
        
        # Processar cada arquivo em paralelo
        tasks = []
        for vod_file in vod_files:
            task = process_vod_file.s(vod_file, source_config)
            tasks.append(task)
        
        # Executar tarefas em grupo
        if tasks:
            job = group(tasks)
            result = job.apply_async()
            
            # Aguardar resultados (opcional - pode ser assíncrono)
            # results = result.get(disable_sync_subtasks=False)
            
            logger.info(f"Sincronização local iniciada: {len(vod_files)} arquivos")
            
            return {
                "status": "started",
                "source": source_config.get('name'),
                "vod_count": len(vod_files),
                "task_group_id": result.id
            }
        else:
            return {
                "status": "completed",
                "source": source_config.get('name'),
                "vod_count": 0,
                "message": "Nenhum VOD encontrado"
            }
            
    except Exception as e:
        logger.error(f"Erro na sincronização local: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def sync_ftp_source(source_config: dict):
    """
    Sincronizar fonte FTP (placeholder)
    """
    logger.warning("Sincronização FTP não implementada")
    return {"status": "not_implemented", "source": source_config.get('name')}

@shared_task
def sync_s3_source(source_config: dict):
    """
    Sincronizar fonte S3 (placeholder)
    """
    logger.warning("Sincronização S3 não implementada")
    return {"status": "not_implemented", "source": source_config.get('name')}

@shared_task
def periodic_sync_task():
    """
    Tarefa periódica de sincronização
    """
    try:
        config_path = os.path.join(os.getenv('BASE_DIR', '/opt/vod-sync-xui'), 'config/sync_config.json')
        
        if not os.path.exists(config_path):
            return {"status": "error", "error": "Config file not found"}
        
        with open(config_path, 'r') as f:
            config = json.load(f)
        
        sources = config.get('sync_config', {}).get('sources', [])
        
        # Filtrar fontes habilitadas
        enabled_sources = [src for src in sources if src.get('enabled', True)]
        
        if not enabled_sources:
            return {"status": "skipped", "reason": "no_enabled_sources"}
        
        # Executar sincronização para cada fonte
        tasks = []
        for source in enabled_sources:
            task = sync_source.delay(source)
            tasks.append(task.id)
        
        logger.info(f"Sincronização periódica iniciada: {len(tasks)} fontes")
        
        return {
            "status": "started",
            "timestamp": datetime.now().isoformat(),
            "source_count": len(tasks),
            "task_ids": tasks
        }
        
    except Exception as e:
        logger.error(f"Erro na sincronização periódica: {e}")
        return {"status": "error", "error": str(e)}

@shared_task
def check_system_health():
    """
    Verificar saúde do sistema
    """
    import psutil
    import shutil
    
    try:
        disk_usage = shutil.disk_usage(os.getenv('VOD_STORAGE_PATH', '/'))
        memory = psutil.virtual_memory()
        cpu_percent = psutil.cpu_percent(interval=1)
        
        health_data = {
            "timestamp": datetime.now().isoformat(),
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "disk_free_gb": disk_usage.free / (1024**3),
            "disk_total_gb": disk_usage.total / (1024**3),
            "disk_used_percent": (disk_usage.used / disk_usage.total) * 100,
            "status": "healthy"
        }
        
        # Verificar se há problemas
        if cpu_percent > 90:
            health_data["status"] = "warning"
            health_data["issues"] = ["CPU usage high"]
        
        if memory.percent > 90:
            health_data["status"] = "warning"
            health_data.setdefault("issues", []).append("Memory usage high")
        
        if disk_usage.free < 5 * 1024**3:  # Menos de 5GB livres
            health_data["status"] = "critical"
            health_data.setdefault("issues", []).append("Low disk space")
        
        logger.debug(f"Verificação de saúde: {health_data['status']}")
        
        return health_data
        
    except Exception as e:
        logger.error(f"Erro na verificação de saúde: {e}")
        return {"status": "error", "error": str(e)}
EOF

cat > "$INSTALL_DIR/src/tasks/notification_tasks.py" << 'EOF'
"""
Tarefas de notificação
"""
import logging
from datetime import datetime
from celery import shared_task

logger = logging.getLogger(__name__)

@shared_task
def send_email_notification(subject: str, message: str, recipient: str = None):
    """
    Enviar notificação por email (placeholder)
    """
    logger.info(f"Email notification: {subject} - {message[:50]}...")
    # TODO: Implementar envio real de email
    return {"status": "sent", "method": "email", "timestamp": datetime.now().isoformat()}

@shared_task
def send_telegram_notification(message: str, chat_id: str = None):
    """
    Enviar notificação por Telegram (placeholder)
    """
    logger.info(f"Telegram notification: {message[:50]}...")
    # TODO: Implementar envio real para Telegram
    return {"status": "sent", "method": "telegram", "timestamp": datetime.now().isoformat()}

@shared_task
def send_webhook_notification(url: str, data: dict):
    """
    Enviar notificação para webhook (placeholder)
    """
    import requests
    try:
        response = requests.post(url, json=data, timeout=10)
        return {
            "status": "sent",
            "method": "webhook",
            "status_code": response.status_code,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Erro ao enviar webhook: {e}")
        return {"status": "error", "error": str(e)}
EOF

# Criar utilitários
cat > "$INSTALL_DIR/src/utils/vod_processor.py" << 'EOF'
"""
Processador de arquivos VOD
"""
import os
import json
import hashlib
import subprocess
from pathlib import Path
from datetime import datetime
import pymediainfo

class VodProcessor:
    def __init__(self, file_path: str, source_config: dict = None):
        self.file_path = file_path
        self.source_config = source_config or {}
        self.metadata = {}
        
    def validate(self) -> bool:
        """Validar arquivo VOD"""
        try:
            # Verificar se arquivo existe
            if not os.path.exists(self.file_path):
                return False
            
            # Verificar tamanho mínimo
            min_size = self.source_config.get('min_size', 10 * 1024 * 1024)  # 10MB padrão
            file_size = os.path.getsize(self.file_path)
            if file_size < min_size:
                return False
            
            # Verificar extensão
            allowed_extensions = self.source_config.get('allowed_extensions', ['mp4', 'mkv', 'avi', 'mov'])
            file_ext = Path(self.file_path).suffix[1:].lower()
            if file_ext not in allowed_extensions:
                return False
            
            # Verificar se é um arquivo de vídeo válido (teste básico com ffprobe)
            try:
                cmd = ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name', '-of', 'default=noprint_wrappers=1:nokey=1', self.file_path]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                if result.returncode != 0:
                    return False
            except:
                # Se ffprobe falhar, tentar com mediainfo
                try:
                    media_info = pymediainfo.MediaInfo.parse(self.file_path)
                    if not media_info.tracks:
                        return False
                except:
                    return False
            
            return True
            
        except Exception as e:
            print(f"Erro na validação: {e}")
            return False
    
    def extract_metadata(self) -> dict:
        """Extrair metadados do arquivo VOD"""
        try:
            file_path = Path(self.file_path)
            
            # Metadados básicos do arquivo
            stat = file_path.stat()
            self.metadata = {
                'filename': file_path.name,
                'file_size': stat.st_size,
                'created_at': datetime.fromtimestamp(stat.st_ctime).isoformat(),
                'modified_at': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'file_hash': self._calculate_file_hash(),
                'path': str(file_path),
                'extension': file_path.suffix[1:].lower()
            }
            
            # Metadados do vídeo usando mediainfo
            try:
                media_info = pymediainfo.MediaInfo.parse(self.file_path)
                
                video_tracks = [track for track in media_info.tracks if track.track_type == 'Video']
                audio_tracks = [track for track in media_info.tracks if track.track_type == 'Audio']
                
                if video_tracks:
                    video = video_tracks[0]
                    self.metadata.update({
                        'duration': float(getattr(video, 'duration', 0)) / 1000,  # Converter para segundos
                        'width': getattr(video, 'width', 0),
                        'height': getattr(video, 'height', 0),
                        'codec': getattr(video, 'codec_id', ''),
                        'frame_rate': getattr(video, 'frame_rate', 0),
                        'bitrate': getattr(video, 'bit_rate', 0),
                        'resolution': f"{getattr(video, 'width', 0)}x{getattr(video, 'height', 0)}"
                    })
                
                if audio_tracks:
                    audio = audio_tracks[0]
                    self.metadata.update({
                        'audio_codec': getattr(audio, 'codec_id', ''),
                        'audio_channels': getattr(audio, 'channel_s', 0),
                        'audio_bitrate': getattr(audio, 'bit_rate', 0),
                        'audio_sample_rate': getattr(audio, 'sampling_rate', 0)
                    })
                
                # Informações gerais
                general_tracks = [track for track in media_info.tracks if track.track_type == 'General']
                if general_tracks:
                    general = general_tracks[0]
                    self.metadata.update({
                        'format': getattr(general, 'format', ''),
                        'overall_bitrate': getattr(general, 'overall_bit_rate', 0),
                        'duration': float(getattr(general, 'duration', 0)) / 1000
                    })
                    
            except Exception as e:
                print(f"Erro ao extrair metadados com mediainfo: {e}")
            
            # Tentar extrair mais informações com ffprobe
            try:
                cmd = [
                    'ffprobe', '-v', 'quiet', '-print_format', 'json',
                    '-show_format', '-show_streams', self.file_path
                ]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                
                if result.returncode == 0:
                    ffprobe_data = json.loads(result.stdout)
                    self.metadata['ffprobe'] = ffprobe_data
                    
                    # Adicionar informações úteis do ffprobe
                    if 'format' in ffprobe_data:
                        format_info = ffprobe_data['format']
                        self.metadata.update({
                            'format_name': format_info.get('format_name', ''),
                            'format_long_name': format_info.get('format_long_name', ''),
                            'tags': format_info.get('tags', {})
                        })
                    
            except Exception as e:
                print(f"Erro ao extrair metadados com ffprobe: {e}")
            
            return self.metadata
            
        except Exception as e:
            print(f"Erro geral na extração de metadados: {e}")
            return self.metadata
    
    def create_thumbnails(self, video_path: str = None, count: int = 3) -> list:
        """Criar thumbnails do vídeo"""
        thumbnails = []
        target_path = video_path or self.file_path
        
        try:
            # Extrair duração do vídeo
            cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', target_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return thumbnails
            
            duration = float(result.stdout.strip())
            
            # Criar diretório para thumbnails
            thumb_dir = Path(target_path).parent / 'thumbnails'
            thumb_dir.mkdir(exist_ok=True)
            
            # Gerar thumbnails em intervalos regulares
            for i in range(count):
                # Calcular tempo para o thumbnail
                time_point = duration * (i + 1) / (count + 1)
                
                # Nome do arquivo thumbnail
                thumb_name = f"{Path(target_path).stem}_thumb_{i+1}.jpg"
                thumb_path = thumb_dir / thumb_name
                
                # Gerar thumbnail com ffmpeg
                cmd = [
                    'ffmpeg', '-ss', str(time_point),
                    '-i', target_path,
                    '-vframes', '1',
                    '-q:v', '2',
                    '-vf', 'scale=320:-1',
                    '-y',
                    str(thumb_path)
                ]
                
                subprocess.run(cmd, capture_output=True, timeout=30)
                
                if thumb_path.exists():
                    thumbnails.append(str(thumb_path))
            
            return thumbnails
            
        except Exception as e:
            print(f"Erro ao criar thumbnails: {e}")
            return thumbnails
    
    def get_destination_path(self, metadata: dict = None) -> str:
        """Gerar caminho de destino para o arquivo"""
        if metadata is None:
            metadata = self.metadata
        
        base_dir = os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods')
        organization = self.source_config.get('organization', 'category')
        
        filename = Path(self.file_path).name
        
        if organization == 'category':
            # Tentar determinar categoria pelo nome ou metadados
            category = self._guess_category(metadata)
            return os.path.join(base_dir, category, filename)
        
        elif organization == 'date':
            # Organizar por data
            date_str = datetime.now().strftime('%Y/%m/%d')
            return os.path.join(base_dir, date_str, filename)
        
        elif organization == 'type':
            # Organizar por tipo (filme/série)
            file_type = self._guess_file_type(metadata)
            return os.path.join(base_dir, file_type, filename)
        
        else:
            # Estrutura plana
            return os.path.join(base_dir, filename)
    
    def _calculate_file_hash(self) -> str:
        """Calcular hash do arquivo"""
        sha256 = hashlib.sha256()
        try:
            with open(self.file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b''):
                    sha256.update(chunk)
            return sha256.hexdigest()
        except:
            return ''
    
    def _guess_category(self, metadata: dict) -> str:
        """Tentar adivinhar a categoria do conteúdo"""
        filename = metadata.get('filename', '').lower()
        
        if any(word in filename for word in ['movie', 'film', 'filme']):
            return 'movies'
        elif any(word in filename for word in ['series', 'season', 'episode', 'série']):
            return 'series'
        elif any(word in filename for word in ['documentary', 'documentario']):
            return 'documentaries'
        elif any(word in filename for word in ['tv', 'show']):
            return 'tv_shows'
        else:
            return 'others'
    
    def _guess_file_type(self, metadata: dict) -> str:
        """Tentar adivinhar o tipo de arquivo"""
        duration = metadata.get('duration', 0)
        
        if duration > 3600:  # Mais de 1 hora
            return 'movies'
        elif 1200 < duration <= 3600:  # 20min a 1 hora
            return 'episodes'
        elif duration <= 1200:  # Até 20 minutos
            return 'shorts'
        else:
            return 'unknown'
EOF

# Criar aplicação principal Flask
cat > "$INSTALL_DIR/src/app.py" << 'EOF'
"""
VOD Sync XUI - Aplicação Principal
"""
import os
import sys
import logging
from pathlib import Path

# Adicionar diretório src ao path
sys.path.insert(0, str(Path(__file__).parent))

from flask import Flask, jsonify, render_template
from flask_cors import CORS
from dotenv import load_dotenv

# Carregar variáveis de ambiente
env_path = Path(__file__).parent.parent / '.env'
load_dotenv(env_path)

# Configurar logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(os.getenv('LOG_PATH', '/opt/vod-sync-xui/logs'), 'app.log')),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

def create_app():
    """Factory function para criar a aplicação Flask"""
    
    app = Flask(__name__)
    
    # Configurações básicas
    app.config.update(
        SECRET_KEY=os.getenv('SECRET_KEY', 'dev-secret-key'),
        JSONIFY_PRETTYPRINT_REGULAR=True,
        JSON_SORT_KEYS=False,
        MAX_CONTENT_LENGTH=int(os.getenv('MAX_FILE_SIZE', 10 * 1024 * 1024 * 1024))
    )
    
    # Habilitar CORS
    CORS(app)
    
    # Rotas básicas
    @app.route('/')
    def index():
        return render_template('index.html')
    
    @app.route('/api/status')
    def api_status():
        return jsonify({
            'status': 'online',
            'service': 'VOD Sync XUI',
            'version': '4.0.0',
            'timestamp': os.path.getmtime(__file__)
        })
    
    @app.route('/api/config')
    def api_config():
        return jsonify({
            'sync_interval': os.getenv('SYNC_INTERVAL'),
            'max_concurrent_syncs': os.getenv('MAX_CONCURRENT_SYNCS'),
            'auto_scan': os.getenv('ENABLE_AUTO_SCAN'),
            'vod_storage': os.getenv('VOD_STORAGE_PATH'),
            'allowed_extensions': os.getenv('ALLOWED_EXTENSIONS')
        })
    
    @app.route('/health')
    def health():
        return jsonify({'status': 'healthy'})
    
    @app.route('/api/v1/sync/start', methods=['POST'])
    def start_sync():
        from src.tasks.sync_tasks import periodic_sync_task
        result = periodic_sync_task.delay()
        return jsonify({
            'status': 'started',
            'task_id': result.id,
            'message': 'Sincronização iniciada'
        })
    
    @app.route('/api/v1/sync/status/<task_id>')
    def sync_status(task_id):
        from src.tasks.celery_app import celery_app
        result = celery_app.AsyncResult(task_id)
        return jsonify({
            'task_id': task_id,
            'status': result.status,
            'result': result.result if result.ready() else None
        })
    
    @app.route('/api/v1/vods')
    def list_vods():
        import glob
        vods_dir = os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods')
        vods = []
        
        for ext in ['mp4', 'mkv', 'avi', 'mov']:
            for vod_file in glob.glob(f"{vods_dir}/**/*.{ext}", recursive=True):
                vods.append({
                    'path': vod_file,
                    'name': os.path.basename(vod_file),
                    'size': os.path.getsize(vod_file),
                    'modified': os.path.getmtime(vod_file)
                })
        
        return jsonify({
            'count': len(vods),
            'vods': vods[:100]  # Limitar a 100 resultados
        })
    
    @app.errorhandler(404)
    def not_found(error):
        return jsonify({'error': 'Not found'}), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        logger.error(f'Internal server error: {error}')
        return jsonify({'error': 'Internal server error'}), 500
    
    logger.info("Aplicação Flask criada com sucesso")
    return app

# Criar a aplicação
app = create_app()

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Iniciando VOD Sync XUI na porta {port}")
    app.run(host=host, port=port, debug=debug)
EOF

# Criar arquivos de templates básicos
mkdir -p "$INSTALL_DIR/src/templates"
cat > "$INSTALL_DIR/src/templates/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VOD Sync XUI - Sistema de Sincronização</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
            max-width: 800px;
            width: 100%;
        }
        
        .header {
            background: linear-gradient(135deg, #4a6ee0 0%, #6a11cb 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header .version {
            opacity: 0.9;
            font-size: 1.1em;
        }
        
        .content {
            padding: 40px;
        }
        
        .status-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            border-left: 5px solid #4a6ee0;
        }
        
        .status-card h3 {
            color: #333;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .status-icon {
            width: 24px;
            height: 24px;
            border-radius: 50%;
            background: #4CAF50;
            display: inline-block;
        }
        
        .status-list {
            list-style: none;
        }
        
        .status-list li {
            padding: 8px 0;
            border-bottom: 1px solid #eee;
            display: flex;
            justify-content: space-between;
        }
        
        .status-list li:last-child {
            border-bottom: none;
        }
        
        .status-value {
            font-weight: bold;
            color: #4a6ee0;
        }
        
        .actions {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 30px;
        }
        
        .btn {
            padding: 15px 25px;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #4a6ee0 0%, #6a11cb 100%);
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(106, 17, 203, 0.3);
        }
        
        .btn-secondary {
            background: #f8f9fa;
            color: #333;
            border: 2px solid #ddd;
        }
        
        .btn-secondary:hover {
            background: #e9ecef;
            border-color: #4a6ee0;
        }
        
        .btn-icon {
            font-size: 1.2em;
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
            border-top: 1px solid #eee;
        }
        
        @media (max-width: 600px) {
            .header {
                padding: 30px 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .content {
                padding: 20px;
            }
            
            .actions {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎬 VOD Sync XUI</h1>
            <div class="version">Versão 4.0.0</div>
            <p>Sistema Completo de Sincronização de VODs</p>
        </div>
        
        <div class="content">
            <div class="status-card">
                <h3><span class="status-icon"></span> Status do Sistema</h3>
                <ul class="status-list" id="statusList">
                    <li>Carregando status...</li>
                </ul>
            </div>
            
            <div class="actions">
                <button class="btn btn-primary" onclick="startSync()">
                    <span class="btn-icon">🔄</span>
                    Iniciar Sincronização
                </button>
                <button class="btn btn-secondary" onclick="listVods()">
                    <span class="btn-icon">📁</span>
                    Listar VODs
                </button>
                <button class="btn btn-secondary" onclick="openAPI()">
                    <span class="btn-icon">🔧</span>
                    API Docs
                </button>
                <button class="btn btn-secondary" onclick="refreshStatus()">
                    <span class="btn-icon">🔄</span>
                    Atualizar Status
                </button>
            </div>
        </div>
        
        <div class="footer">
            <p>Sistema VOD Sync XUI &copy; 2024 - Todos os direitos reservados</p>
            <p id="serverTime">Carregando tempo do servidor...</p>
        </div>
    </div>
    
    <script>
        async function loadStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                
                const configResponse = await fetch('/api/config');
                const config = await configResponse.json();
                
                const healthResponse = await fetch('/health');
                const health = await healthResponse.json();
                
                const statusList = document.getElementById('statusList');
                statusList.innerHTML = `
                    <li>Status do Serviço: <span class="status-value">${data.status}</span></li>
                    <li>Versão: <span class="status-value">${data.version}</span></li>
                    <li>Intervalo de Sincronização: <span class="status-value">${config.sync_interval}s</span></li>
                    <li>Sincronização Automática: <span class="status-value">${config.auto_scan ? 'Ativada' : 'Desativada'}</span></li>
                    <li>Extensões Permitidas: <span class="status-value">${config.allowed_extensions}</span></li>
                    <li>Saúde do Sistema: <span class="status-value">${health.status}</span></li>
                `;
                
                document.getElementById('serverTime').textContent = 
                    `Servidor: ${new Date(data.timestamp * 1000).toLocaleString()}`;
                    
            } catch (error) {
                document.getElementById('statusList').innerHTML = 
                    '<li style="color: #dc3545;">Erro ao carregar status do sistema</li>';
            }
        }
        
        async function startSync() {
            try {
                const response = await fetch('/api/v1/sync/start', {
                    method: 'POST'
                });
                const result = await response.json();
                
                alert(`Sincronização iniciada! Task ID: ${result.task_id}`);
                
                // Monitorar progresso
                monitorTask(result.task_id);
                
            } catch (error) {
                alert('Erro ao iniciar sincronização: ' + error.message);
            }
        }
        
        async function monitorTask(taskId) {
            const checkInterval = setInterval(async () => {
                try {
                    const response = await fetch(`/api/v1/sync/status/${taskId}`);
                    const result = await response.json();
                    
                    if (result.status === 'SUCCESS' || result.status === 'FAILURE') {
                        clearInterval(checkInterval);
                        alert(`Sincronização ${result.status.toLowerCase()}!`);
                        refreshStatus();
                    }
                } catch (error) {
                    clearInterval(checkInterval);
                }
            }, 2000);
        }
        
        async function listVods() {
            try {
                const response = await fetch('/api/v1/vods');
                const result = await response.json();
                
                alert(`Encontrados ${result.count} VODs no sistema`);
                
                if (result.vods && result.vods.length > 0) {
                    const vodList = result.vods.slice(0, 5).map(vod => 
                        `📁 ${vod.name} (${Math.round(vod.size / (1024*1024))}MB)`
                    ).join('\n');
                    
                    if (result.count > 5) {
                        alert(`${vodList}\n\n... e mais ${result.count - 5} arquivos`);
                    } else {
                        alert(vodList);
                    }
                }
                
            } catch (error) {
                alert('Erro ao listar VODs: ' + error.message);
            }
        }
        
        function openAPI() {
            window.open('/api/status', '_blank');
        }
        
        function refreshStatus() {
            loadStatus();
        }
        
        // Carregar status inicial
        loadStatus();
        
        // Atualizar status a cada 30 segundos
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
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

# Testar Redis
if redis-cli ping | grep -q "PONG"; then
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
    
    # Página inicial
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # API
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $INSTALL_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin *;
    }
    
    # VOD files
    location /vods/ {
        alias $INSTALL_DIR/vods/;
        expires 30d;
        add_header Cache-Control "public";
        
        # Enable CORS for streaming
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS";
        add_header Access-Control-Allow-Headers "Range";
        
        # Handle range requests for video streaming
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

# Script scheduler.py
cat > "$INSTALL_DIR/scripts/scheduler.py" << 'EOF'
#!/usr/bin/env python3
"""
Agendador de tarefas para o VOD Sync XUI
"""
import os
import sys
import time
import logging
from datetime import datetime
from pathlib import Path

# Adicionar diretório src ao path
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from tasks.celery_app import celery_app
from tasks.sync_tasks import periodic_sync_task

# Configurar logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(os.getenv('LOG_PATH', '/opt/vod-sync-xui/logs'), 'scheduler.log')),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

def main():
    """Função principal do agendador"""
    logger.info("Iniciando agendador do VOD Sync XUI")
    
    try:
        # Verificar conexão com Redis
        celery_app.connection().ensure_connection()
        logger.info("Conexão com Redis estabelecida")
        
        # Executar tarefa inicial
        logger.info("Executando sincronização inicial...")
        result = periodic_sync_task.delay()
        
        # Aguardar um pouco para verificar se a tarefa foi aceita
        time.sleep(5)
        
        if result.ready():
            logger.info(f"Tarefa inicial concluída: {result.result}")
        else:
            logger.info(f"Tarefa inicial em execução: {result.id}")
        
        # Manter o script em execução
        logger.info("Agendador rodando. Pressione Ctrl+C para sair.")
        
        while True:
            time.sleep(60)
            # Verificar saúde periódica
            health_check = celery_app.control.inspect().ping()
            if not health_check:
                logger.warning("Não foi possível verificar a saúde do worker")
            
    except KeyboardInterrupt:
        logger.info("Agendador interrompido pelo usuário")
    except Exception as e:
        logger.error(f"Erro no agendador: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Script cleanup.sh
cat > "$INSTALL_DIR/scripts/cleanup.sh" << 'EOF'
#!/bin/bash
# Script de limpeza para o VOD Sync XUI

INSTALL_DIR="/opt/vod-sync-xui"
LOG_DIR="$INSTALL_DIR/logs"
TEMP_DIR="$INSTALL_DIR/temp"
DAYS_TO_KEEP=30

echo "=== LIMPEZA DO VOD SYNC XUI ==="
echo "Data: $(date)"
echo ""

# Limpar logs antigos
echo "1. Limpando logs antigos (mais de $DAYS_TO_KEEP dias)..."
find "$LOG_DIR" -name "*.log" -type f -mtime +$DAYS_TO_KEEP -delete
echo "   Logs antigos removidos"

# Limpar arquivos temporários
echo "2. Limpando arquivos temporários..."
if [ -d "$TEMP_DIR" ]; then
    find "$TEMP_DIR" -type f -mtime +1 -delete
    echo "   Arquivos temporários removidos"
else
    echo "   Diretório temporário não encontrado"
fi

# Limpar cache do Redis se configurado
echo "3. Limpando cache do Redis..."
if command -v redis-cli &> /dev/null; then
    redis-cli FLUSHDB ASYNC
    echo "   Cache do Redis limpo"
else
    echo "   Redis não encontrado"
fi

# Verificar espaço em disco
echo "4. Verificando espaço em disco..."
df -h "$INSTALL_DIR"

# Verificar tamanho dos diretórios
echo ""
echo "5. Tamanho dos diretórios principais:"
du -sh "$INSTALL_DIR"/{vods,logs,data,temp} 2>/dev/null || true

echo ""
echo "=== LIMPEZA CONCLUÍDA ==="
EOF

# Script de inicialização simplificado
cat > "$INSTALL_DIR/scripts/init_db.py" << 'EOF'
#!/usr/bin/env python3
"""
Script para inicializar o banco de dados
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

def main():
    print("Inicializando banco de dados do VOD Sync XUI...")
    
    # Criar diretórios necessários
    directories = [
        'data/database',
        'data/thumbnails',
        'data/metadata',
        'vods/movies',
        'vods/series',
        'vods/originals',
        'vods/processed',
        'vods/queue'
    ]
    
    base_dir = Path('/opt/vod-sync-xui')
    for directory in directories:
        dir_path = base_dir / directory
        dir_path.mkdir(parents=True, exist_ok=True)
        print(f"  Criado: {dir_path}")
    
    # Criar arquivo SQLite de cache
    import sqlite3
    cache_db = base_dir / 'data/database/vod_cache.db'
    
    if not cache_db.exists():
        conn = sqlite3.connect(str(cache_db))
        cursor = conn.cursor()
        
        # Criar tabela de cache de arquivos processados
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS processed_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_hash TEXT UNIQUE NOT NULL,
                file_path TEXT NOT NULL,
                file_size INTEGER,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                source TEXT,
                destination TEXT,
                status TEXT
            )
        ''')
        
        # Criar tabela de metadados
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS vod_metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_hash TEXT UNIQUE NOT NULL,
                filename TEXT,
                duration REAL,
                width INTEGER,
                height INTEGER,
                codec TEXT,
                bitrate INTEGER,
                format TEXT,
                metadata_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Criar índices
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_file_hash ON processed_files(file_hash)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_processed_at ON processed_files(processed_at)')
        
        conn.commit()
        conn.close()
        print(f"  Banco de dados SQLite criado: {cache_db}")
    
    print("Banco de dados inicializado com sucesso!")

if __name__ == '__main__':
    main()
EOF

# Dar permissões
chmod +x "$INSTALL_DIR/scripts"/*.py
chmod +x "$INSTALL_DIR/scripts/cleanup.sh"

print_success "Scripts auxiliares criados"

# 11. Criar serviços systemd corrigidos
print_header "11. CONFIGURAÇÃO DE SERVIÇOS SYSTEMD"

# Serviço principal Flask
cat > /etc/systemd/system/vod-sync.service << EOF
[Unit]
Description=VOD Sync XUI - Serviço Principal
After=network.target mysql.service redis-server.service nginx.service
Requires=mysql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn \
  --bind 127.0.0.1:5000 \
  --workers 2 \
  --threads 4 \
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

[Install]
WantedBy=multi-user.target
EOF

# Serviço Celery Worker corrigido
cat > /etc/systemd/system/vod-sync-worker.service << EOF
[Unit]
Description=VOD Sync XUI - Worker Celery
After=network.target redis-server.service vod-sync.service
Requires=redis-server.service
BindsTo=vod-sync.service

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
  --concurrency=2 \
  --hostname=worker@%h
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

# Serviço Celery Beat para tarefas agendadas
cat > /etc/systemd/system/vod-sync-beat.service << EOF
[Unit]
Description=VOD Sync XUI - Celery Beat Scheduler
After=network.target redis-server.service vod-sync-worker.service
Requires=redis-server.service vod-sync-worker.service
BindsTo=vod-sync-worker.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/celery \
  -A src.tasks.celery_app beat \
  --loglevel=info \
  --scheduler celery.beat.PersistentScheduler \
  --schedule $INSTALL_DIR/celerybeat-schedule
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-beat
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

# Remover serviço scheduler antigo
rm -f /etc/systemd/system/vod-sync-scheduler.service /etc/systemd/system/vod-sync-scheduler.timer 2>/dev/null || true

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

echo "🚀 Iniciando VOD Sync XUI..."

# Iniciar serviços na ordem correta
echo "1. Iniciando MySQL..."
systemctl start mysql

echo "2. Iniciando Redis..."
systemctl start redis-server

echo "3. Iniciando Nginx..."
systemctl start nginx

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

# Verificar status
echo ""
echo "📊 Status dos serviços:"
echo "======================="

services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: ATIVO"
    else
        echo "❌ $service: INATIVO"
        echo "   Logs: journalctl -u $service -n 20 --no-pager"
    fi
done

# Obter IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

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

# Parar serviços na ordem inversa
systemctl stop vod-sync-beat
systemctl stop vod-sync-worker
systemctl stop vod-sync
systemctl stop nginx
systemctl stop redis-server
# Não parar MySQL para manter dados

sleep 2

echo "✅ Serviços parados"
echo ""
echo "📊 Status:"
echo "vod-sync: $(systemctl is-active vod-sync)"
echo "vod-sync-worker: $(systemctl is-active vod-sync-worker)"
echo "vod-sync-beat: $(systemctl is-active vod-sync-beat)"
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
services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

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
            journalctl -u "$service" -n 5 --no-pager
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

if ss -tlnp | grep -q :6379; then
    echo "✅ Redis (6379): Ouvindo"
else
    echo "❌ Redis (6379): Não ouvindo"
fi

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
echo "📝 LOGS (últimas 3 linhas de erro):"
echo "------------------------------------"
if [ -f "$INSTALL_DIR/logs/app/error.log" ]; then
    echo "Aplicação:"
    tail -3 "$INSTALL_DIR/logs/app/error.log" 2>/dev/null || echo "  Nenhum erro"
else
    echo "Arquivo de log não encontrado"
fi

echo ""

# Redis
echo "🔴 REDIS:"
echo "---------"
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis: CONECTADO"
    redis_info=$(redis-cli info memory 2>/dev/null | grep -E "used_memory_human|maxmemory_human" || echo "")
    echo "   $redis_info"
else
    echo "❌ Redis: DESCONECTADO"
fi

echo ""

# URL
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
echo "🌐 ACESSO: http://$IP"
echo "   API Status: http://$IP/api/status"
echo "   Health: http://$IP/health"
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
echo "2. Nginx"
echo "3. Worker Celery"
echo "4. Todos (multitail)"
echo "5. Ver erros recentes"
echo ""
read -p "Escolha (1-5): " choice

case $choice in
    1)
        tail -f "$INSTALL_DIR/logs/app/error.log"
        ;;
    2)
        tail -f "$INSTALL_DIR/logs/nginx/error.log"
        ;;
    3)
        journalctl -u vod-sync-worker -f
        ;;
    4)
        if command -v multitail >/dev/null; then
            multitail \
                -l "tail -f $INSTALL_DIR/logs/app/error.log" \
                -l "tail -f $INSTALL_DIR/logs/nginx/access.log" \
                -l "journalctl -u vod-sync-worker -f"
        else
            echo "Instale multitail: apt-get install multitail"
            echo "Visualizando apenas logs da aplicação:"
            tail -f "$INSTALL_DIR/logs/app/error.log"
        fi
        ;;
    5)
        echo "Erros da aplicação:"
        grep -i error "$INSTALL_DIR/logs/app/error.log" | tail -20
        echo ""
        echo "Erros do worker:"
        journalctl -u vod-sync-worker --since "1 hour ago" | grep -i error | tail -20
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
$INSTALL_DIR/stop.sh

# Criar backup (excluindo arquivos grandes e temporários)
tar -czf "$BACKUP_FILE" \
    --exclude="$INSTALL_DIR/venv" \
    --exclude="$INSTALL_DIR/vods" \
    --exclude="$INSTALL_DIR/temp" \
    --exclude="$INSTALL_DIR/logs" \
    --exclude="$INSTALL_DIR/backup" \
    -C "$INSTALL_DIR/.." vod-sync-xui

# Reiniciar serviços
$INSTALL_DIR/start.sh

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
"$INSTALL_DIR/stop.sh"

# Atualizar código do git (se existir)
echo "3. Atualizando código..."
cd "$INSTALL_DIR"
if [ -d ".git" ]; then
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || echo "Git não configurado ou falha"
fi

# Atualizar dependências
echo "4. Atualizando dependências..."
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
"$INSTALL_DIR/status.sh"

echo ""
echo "✅ Atualização concluída!"
date
echo "=== FIM DA ATUALIZAÇÃO ==="
EOF

# Dar permissões de execução
chmod +x "$INSTALL_DIR"/*.sh

print_success "Scripts de gerenciamento criados"

# 13. Configurar cron jobs
print_header "13. CONFIGURAÇÃO DE TAREFAS AGENDADAS (CRON)"
cat > /etc/cron.d/vod-sync << EOF
# Tarefas agendadas do VOD Sync XUI
# Editado em: $(date)

# Limpeza diária de arquivos temporários (2:00 AM)
0 2 * * * root $INSTALL_DIR/scripts/cleanup.sh >> $INSTALL_DIR/logs/cron/cleanup.log 2>&1

# Backup semanal (domingo 3:00 AM)
0 3 * * 0 root $INSTALL_DIR/backup.sh >> $INSTALL_DIR/logs/cron/backup.log 2>&1

# Verificação de saúde (a cada 10 minutos)
*/10 * * * * root curl -s -o /dev/null -w "%{http_code}" http://localhost/health | grep -q "200" || systemctl restart vod-sync >> $INSTALL_DIR/logs/cron/health.log 2>&1

# Limpeza de logs antigos (todo dia 4:00 AM)
0 4 * * * root find $INSTALL_DIR/logs -name "*.log" -type f -mtime +30 -delete >> $INSTALL_DIR/logs/cron/logrotate.log 2>&1

# Sincronização manual (opcional - descomente se quiser)
#0 */6 * * * root curl -X POST http://localhost/api/v1/sync/start >> $INSTALL_DIR/logs/cron/sync.log 2>&1
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
systemctl daemon-reload

# Iniciar serviços na ordem correta
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
        journalctl -u "$service" -n 10 --no-pager
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

# 17. Criar README final
print_header "17. DOCUMENTAÇÃO FINAL"
cat > "$INSTALL_DIR/README.md" << EOF
# 🎬 VOD Sync XUI - Sistema Instalado com Sucesso!

## 📋 RESUMO DA INSTALAÇÃO
- **Versão:** 4.0.0 (Corrigida)
- **Data:** $(date)
- **Diretório:** $INSTALL_DIR
- **URL Principal:** http://$IP
- **API:** http://$IP/api
- **Porta:** 80 (HTTP), 5000 (API), 6379 (Redis)

## 🔧 CONFIGURAÇÕES IMPORTANTES

### Credenciais de Acesso
- **Usuário Admin:** admin
- **Senha Admin:** $ADMIN_PASSWORD
- **API Key:** $API_KEY
- **Database Password:** $DB_PASSWORD
- **Secret Key:** $SECRET_KEY

### Banco de Dados
- **MySQL Host:** localhost
- **Database:** vod_sync_xui
- **Usuário:** vod_sync_xui
- **Senha:** $DB_PASSWORD

### Redis
- **Host:** localhost
- **Porta:** 6379
- **DB:** 0

## 🚀 COMEÇANDO

### Acesso Rápido
1. Abra seu navegador: http://$IP
2. A interface web será carregada
3. Use os botões para controlar o sistema

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
│   ├── tasks/        # Tarefas Celery
│   ├── utils/        # Utilitários
│   └── templates/    # Templates HTML
├── venv/             # Ambiente virtual Python
├── vods/             # VODs sincronizados
│   ├── movies/       # Filmes
│   ├── series/       # Séries
│   ├── originals/    # Originais
│   └── processed/    # Processados
├── data/             # Dados do sistema
│   ├── database/     # Banco SQLite
│   ├── thumbnails/   # Thumbnails
│   └── metadata/     # Metadados
├── logs/             # Logs do sistema
│   ├── app/          # Aplicação
│   ├── nginx/        # Nginx
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

### Controle
- \`POST /api/v1/sync/start\` - Iniciar sincronização
- \`GET /api/v1/sync/status/<task_id>\` - Status da tarefa
- \`GET /api/v1/vods\` - Listar VODs

## ⚙️ CONFIGURAÇÃO DE SINCRONIZAÇÃO

### Editar configurações
\`\`\`bash
nano $INSTALL_DIR/config/sync_config.json
nano $INSTALL_DIR/.env
\`\`\`

### Configurações principais:
1. **Fontes de VODs:** Defina diretórios locais em \`sync_config.json\`
2. **Processamento:** Configure em \`.env\`
3. **Agendamento:** Automático via Celery Beat
4. **Notificações:** Configure email/telegram no \`.env\`

## 🐛 SOLUÇÃO DE PROBLEMAS

### Serviço não inicia
\`\`\`bash
# Verificar logs
$INSTALL_DIR/logs.sh

# Ver status detalhado
$INSTALL_DIR/status.sh

# Ver logs do systemd
journalctl -u vod-sync --no-pager -n 50
journalctl -u vod-sync-worker --no-pager -n 50
\`\`\`

### Redis com problemas
\`\`\`bash
# Verificar status
systemctl status redis-server

# Testar conexão
redis-cli ping

# Reiniciar
systemctl restart redis-server
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

### Alterar senhas
1. **Admin:** Edite no arquivo \`.env\`
2. **Database:** Altere no \`.env\` e recrie o usuário MySQL
3. **API Key:** Gere nova no \`.env\`

### Firewall recomendado
\`\`\`bash
# Instalar UFW
apt install ufw

# Configurar regras
ufw allow 80/tcp
ufw allow 443/tcp    # Se usar SSL
ufw allow 22/tcp     # SSH
ufw enable
\`\`\`

## 📈 MONITORAMENTO

### Métricas
- Use o script de status: \`$INSTALL_DIR/status.sh\`
- Verifique logs: \`$INSTALL_DIR/logs.sh\`
- Monitor Redis: \`redis-cli info\`

### Acessar métricas
\`\`\`bash
# Via API
curl http://$IP/api/status
curl http://$IP/health

# Via terminal
$INSTALL_DIR/status.sh | less
\`\`\`

## 🔄 ATUALIZAÇÃO

### Método recomendado
\`\`\`bash
# Execute o script de atualização
$INSTALL_DIR/update.sh
\`\`\`

## 📞 SUPORTE

### Recursos
- **Logs:** $INSTALL_DIR/logs/
- **Configurações:** $INSTALL_DIR/config/
- **Documentação:** $INSTALL_DIR/README.md

### Verificar status completo
\`\`\`bash
$INSTALL_DIR/status.sh
\`\`\`

---

## 🎉 INSTALAÇÃO CONCLUÍDA!

Seu sistema VOD Sync XUI está pronto para uso.

**Próximos passos:**
1. Configure suas fontes de VODs em \`$INSTALL_DIR/config/sync_config.json\`
2. Ajuste as configurações no arquivo \`.env\`
3. Acesse http://$IP para usar a interface web
4. Clique em "Iniciar Sincronização" para começar

**Dica:** Use \`$INSTALL_DIR/status.sh\` para monitorar o sistema.
EOF

# 18. Mostrar resumo final
print_header "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
print_divider
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            VOD SYNC XUI 4.0.0 INSTALADO!                     ║"
echo "║         Sistema corrigido e funcionando!                    ║"
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
echo "   📊 MySQL Pass: $DB_PASSWORD"
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
echo "   2. Configure suas fontes de VODs em:"
echo "      $INSTALL_DIR/config/sync_config.json"
echo "   3. Ajuste configurações em: $INSTALL_DIR/.env"
echo "   4. Clique em 'Iniciar Sincronização' na interface web"
echo ""
echo "📚 Documentação:"
echo "   📖 $INSTALL_DIR/README.md"
echo ""
echo "🔔 Funcionalidades:"
echo "   ⏰ Sincronização automática via Celery Beat"
echo "   🔄 Worker Celery para processamento paralelo"
echo "   💾 Backups automáticos semanais"
echo "   🧹 Limpeza automática diária"
echo ""
print_divider
echo ""
echo "🎬 O sistema VOD Sync XUI está pronto para sincronizar seus VODs!"
echo "   Para suporte, consulte a documentação ou verifique os logs."
echo ""
print_divider

# Finalizar
exit 0
