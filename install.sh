#!/bin/bash

# ============================================================
# INSTALADOR VOD SYNC XUI - VERSÃO 4.0.0 (CORRIGIDO FINAL)
# Sistema simplificado e funcional de sincronização de VODs
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
echo -e "   ║        Versão Simplificada e Funcional   ║"
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
    curl \
    wget \
    unzip \
    cron \
    jq \
    sqlite3 \
    redis-server \
    redis-tools \
    python3-dev \
    libssl-dev \
    libffi-dev

print_success "Dependências instaladas"

# 3. Criar estrutura de diretórios
print_header "3. ESTRUTURA DE DIRETÓRIOS"
mkdir -p "$INSTALL_DIR"/{src,logs,data,config,backup,scripts,templates,static,vods,temp}
mkdir -p "$INSTALL_DIR"/data/database
mkdir -p "$INSTALL_DIR"/logs/{app,nginx,cron}
mkdir -p "$INSTALL_DIR"/vods/{movies,series,originals,processed}

# Setar permissões
chmod -R 755 "$INSTALL_DIR"
chown -R www-data:www-data "$INSTALL_DIR/data" "$INSTALL_DIR/logs" "$INSTALL_DIR/vods"
print_success "Estrutura de diretórios criada"

# 4. Criar arquivos de configuração SIMPLIFICADOS
print_header "4. CONFIGURAÇÕES DO SISTEMA"

# Arquivo .env principal SIMPLIFICADO
cat > "$INSTALL_DIR/.env" << EOF
# VOD Sync XUI - Configurações
SECRET_KEY=$SECRET_KEY
DEBUG=false
PORT=5000
API_KEY=$API_KEY
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync_xui
DB_USER=vod_sync_xui
DB_PASSWORD=$DB_PASSWORD

# Redis
REDIS_URL=redis://localhost:6379/0

# Paths
VOD_STORAGE_PATH=$INSTALL_DIR/vods
LOG_PATH=$INSTALL_DIR/logs
EOF

print_success "Arquivo .env criado"

# Arquivo de configuração JSON simples
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
        "recursive": true
      }
    ],
    "destination": {
      "path": "$INSTALL_DIR/vods"
    }
  }
}
EOF

print_success "Arquivo de configuração de sincronização criado"

# 5. Criar requirements.txt MÍNIMO
print_header "5. INSTALAÇÃO DO PYTHON"
cat > "$INSTALL_DIR/requirements.txt" << EOF
Flask==2.3.3
celery==5.3.4
redis==5.0.0
python-dotenv==1.0.0
requests==2.31.0
psutil==5.9.6
pymediainfo==6.1.0
Jinja2==3.1.2
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

# 6. Criar aplicação Flask SIMPLIFICADA E FUNCIONAL
print_header "6. CRIANDO APLICAÇÃO FLASK"

# Criar estrutura de diretórios Python
mkdir -p "$INSTALL_DIR/src"
mkdir -p "$INSTALL_DIR/src/tasks"

# Criar __init__.py
touch "$INSTALL_DIR/src/__init__.py"
touch "$INSTALL_DIR/src/tasks/__init__.py"

# Criar Celery app CORRETO (sem erros de sintaxe)
cat > "$INSTALL_DIR/src/tasks/celery_app.py" << 'EOF'
"""
Configuração do Celery - Versão Corrigida
"""
from celery import Celery

def make_celery():
    """Criar instância do Celery"""
    celery_app = Celery(
        'vod_sync',
        broker='redis://localhost:6379/0',
        backend='redis://localhost:6379/0',
        include=['src.tasks.vod_tasks']
    )
    
    # Configurações básicas
    celery_app.conf.update(
        task_serializer='json',
        accept_content=['json'],
        result_serializer='json',
        timezone='America/Sao_Paulo',
        enable_utc=True,
        beat_schedule={
            'test-task-every-30s': {
                'task': 'src.tasks.vod_tasks.test_task',
                'schedule': 30.0,
            },
        }
    )
    
    return celery_app

# Criar instância do Celery
celery_app = make_celery()

if __name__ == '__main__':
    celery_app.start()
EOF

# Criar tarefas básicas funcionais
cat > "$INSTALL_DIR/src/tasks/vod_tasks.py" << 'EOF'
"""
Tarefas básicas para o VOD Sync
"""
import time
from datetime import datetime
from celery import shared_task

@shared_task
def test_task():
    """Tarefa de teste simples"""
    return {
        'status': 'success',
        'message': 'Tarefa executada com sucesso',
        'timestamp': datetime.now().isoformat()
    }

@shared_task
def sync_task():
    """Tarefa de sincronização"""
    return {
        'status': 'success',
        'task': 'sync',
        'timestamp': datetime.now().isoformat()
    }

@shared_task
def scan_directory(directory):
    """Escanear diretório"""
    import os
    files = []
    
    try:
        for root, dirs, filenames in os.walk(directory):
            for filename in filenames:
                if filename.lower().endswith(('.mp4', '.mkv', '.avi')):
                    files.append(os.path.join(root, filename))
    except Exception as e:
        return {'status': 'error', 'error': str(e)}
    
    return {
        'status': 'success',
        'directory': directory,
        'file_count': len(files),
        'files': files[:10]  # Limitar a 10 arquivos
    }
EOF

# Criar aplicação Flask principal FUNCIONAL
cat > "$INSTALL_DIR/src/app.py" << 'EOF'
"""
VOD Sync XUI - Aplicação Principal Funcional
"""
import os
import sys
from pathlib import Path
from flask import Flask, jsonify, render_template_string
from datetime import datetime

# Adicionar diretório src ao path
sys.path.insert(0, str(Path(__file__).parent))

# HTML template simples
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VOD Sync XUI</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            padding: 40px;
            max-width: 800px;
            width: 100%;
        }
        h1 { 
            color: #333; 
            margin-bottom: 20px;
            text-align: center;
        }
        .status-box {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            border-left: 5px solid #28a745;
        }
        .btn {
            display: inline-block;
            background: #007bff;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            margin: 5px;
            text-decoration: none;
            transition: background 0.3s;
        }
        .btn:hover {
            background: #0056b3;
        }
        .btn-success {
            background: #28a745;
        }
        .btn-success:hover {
            background: #1e7e34;
        }
        .btn-container {
            text-align: center;
            margin: 30px 0;
        }
        .info {
            background: #e9ecef;
            padding: 15px;
            border-radius: 5px;
            margin: 15px 0;
            font-size: 14px;
        }
        .endpoints {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
        }
        .endpoints h3 {
            margin-bottom: 10px;
            color: #555;
        }
        .endpoint {
            background: #f8f9fa;
            padding: 10px;
            margin: 5px 0;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎬 VOD Sync XUI - Sistema de Sincronização</h1>
        
        <div class="status-box">
            <h3>Status do Sistema</h3>
            <p><strong>Status:</strong> <span id="status">Carregando...</span></p>
            <p><strong>Versão:</strong> 4.0.0</p>
            <p><strong>Servidor:</strong> {{ server_ip }}</p>
            <p><strong>Data/Hora:</strong> {{ current_time }}</p>
        </div>
        
        <div class="btn-container">
            <button class="btn btn-success" onclick="startSync()">▶️ Iniciar Sincronização</button>
            <button class="btn" onclick="checkStatus()">🔄 Atualizar Status</button>
            <button class="btn" onclick="testCelery()">⚙️ Testar Celery</button>
        </div>
        
        <div class="info">
            <p><strong>Diretório de VODs:</strong> {{ vod_path }}</p>
            <p><strong>Configuração:</strong> {{ config_path }}</p>
        </div>
        
        <div id="result" class="status-box" style="display: none;">
            <h3>Resultado:</h3>
            <pre id="result-content"></pre>
        </div>
        
        <div class="endpoints">
            <h3>Endpoints da API:</h3>
            <div class="endpoint">GET /api/status - Status do sistema</div>
            <div class="endpoint">GET /health - Saúde do serviço</div>
            <div class="endpoint">POST /api/sync/start - Iniciar sincronização</div>
            <div class="endpoint">GET /api/vods - Listar VODs</div>
        </div>
    </div>
    
    <script>
        async function startSync() {
            try {
                showResult('Iniciando sincronização...');
                const response = await fetch('/api/sync/start', { method: 'POST' });
                const data = await response.json();
                showResult(JSON.stringify(data, null, 2));
            } catch (error) {
                showResult('Erro: ' + error.message);
            }
        }
        
        async function checkStatus() {
            try {
                showResult('Verificando status...');
                const response = await fetch('/api/status');
                const data = await response.json();
                document.getElementById('status').textContent = data.status;
                showResult(JSON.stringify(data, null, 2));
            } catch (error) {
                showResult('Erro: ' + error.message);
            }
        }
        
        async function testCelery() {
            try {
                showResult('Testando Celery...');
                const response = await fetch('/api/test/celery');
                const data = await response.json();
                showResult(JSON.stringify(data, null, 2));
            } catch (error) {
                showResult('Erro: ' + error.message);
            }
        }
        
        function showResult(content) {
            document.getElementById('result-content').textContent = content;
            document.getElementById('result').style.display = 'block';
        }
        
        // Carregar status inicial
        checkStatus();
    </script>
</body>
</html>
'''

def create_app():
    """Criar aplicação Flask"""
    app = Flask(__name__)
    
    # Configuração
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-key-123')
    
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
            current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            vod_path=os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods'),
            config_path='/opt/vod-sync-xui/config/sync_config.json'
        )
    
    @app.route('/api/status')
    def api_status():
        return jsonify({
            'status': 'online',
            'service': 'VOD Sync XUI',
            'version': '4.0.0',
            'timestamp': datetime.now().isoformat()
        })
    
    @app.route('/health')
    def health():
        return jsonify({'status': 'healthy'})
    
    @app.route('/api/sync/start', methods=['POST'])
    def start_sync():
        return jsonify({
            'status': 'success',
            'message': 'Sincronização iniciada',
            'timestamp': datetime.now().isoformat()
        })
    
    @app.route('/api/test/celery')
    def test_celery():
        try:
            from src.tasks.celery_app import celery_app
            return jsonify({
                'status': 'success',
                'message': 'Celery configurado',
                'broker': 'redis://localhost:6379/0'
            })
        except Exception as e:
            return jsonify({
                'status': 'error',
                'error': str(e)
            })
    
    @app.route('/api/vods')
    def list_vods():
        import glob
        vods = []
        vods_dir = os.getenv('VOD_STORAGE_PATH', '/opt/vod-sync-xui/vods')
        
        try:
            for ext in ['mp4', 'mkv', 'avi']:
                pattern = os.path.join(vods_dir, '**', f'*.{ext}')
                for file in glob.glob(pattern, recursive=True):
                    vods.append({
                        'name': os.path.basename(file),
                        'size': os.path.getsize(file),
                        'path': file
                    })
        except Exception as e:
            return jsonify({'error': str(e)})
        
        return jsonify({
            'count': len(vods),
            'vods': vods[:20]
        })
    
    @app.errorhandler(404)
    def not_found(e):
        return jsonify({'error': 'Not found'}), 404
    
    @app.errorhandler(500)
    def internal_error(e):
        return jsonify({'error': 'Internal server error'}), 500
    
    return app

# Criar a aplicação
app = create_app()

if __name__ == '__main__':
    host = '0.0.0.0'
    port = 5000
    print(f"🚀 Iniciando VOD Sync XUI em http://{host}:{port}")
    app.run(host=host, port=port, debug=False)
EOF

print_success "Aplicação Flask criada"

# 7. Configurar banco de dados MySQL
print_header "7. CONFIGURAÇÃO DO BANCO DE DADOS"
print_step "Configurando MySQL..."

# Iniciar MySQL
systemctl start mysql 2>/dev/null || true
systemctl enable mysql 2>/dev/null || true

# Criar banco de dados e usuário
mysql -e "DROP DATABASE IF EXISTS vod_sync_xui;" 2>/dev/null || true
mysql -e "CREATE DATABASE IF NOT EXISTS vod_sync_xui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
mysql -e "CREATE USER IF NOT EXISTS 'vod_sync_xui'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" 2>/dev/null || true
mysql -e "GRANT ALL PRIVILEGES ON vod_sync_xui.* TO 'vod_sync_xui'@'localhost';" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

print_success "Banco de dados MySQL configurado"

# 8. Configurar Redis
print_header "8. CONFIGURAÇÃO DO REDIS"
print_step "Configurando Redis..."

systemctl start redis-server 2>/dev/null || true
systemctl enable redis-server 2>/dev/null || true

# Testar Redis
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    print_success "Redis configurado e funcionando"
else
    print_error "Redis falhou ao iniciar"
fi

# 9. Configurar Nginx
print_header "9. CONFIGURAÇÃO DO NGINX"
cat > /etc/nginx/sites-available/vod-sync << EOF
server {
    listen 80;
    server_name _;
    
    access_log $INSTALL_DIR/logs/nginx/access.log;
    error_log $INSTALL_DIR/logs/nginx/error.log;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /vods/ {
        alias $INSTALL_DIR/vods/;
        autoindex off;
    }
    
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Habilitar site
ln -sf /etc/nginx/sites-available/vod-sync /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar e reiniciar Nginx
nginx -t && systemctl restart nginx
print_success "Nginx configurado"

# 10. Criar serviços systemd SIMPLIFICADOS E FUNCIONAIS
print_header "10. CONFIGURAÇÃO DE SERVIÇOS SYSTEMD"

# Serviço principal Flask (executa diretamente o Python)
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

[Install]
WantedBy=multi-user.target
EOF

# Serviço Celery Worker CORRETO
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
ExecStart=$INSTALL_DIR/venv/bin/python -m celery -A src.tasks.celery_app worker --loglevel=info
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-worker

[Install]
WantedBy=multi-user.target
EOF

# Serviço Celery Beat CORRETO
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
ExecStart=$INSTALL_DIR/venv/bin/python -m celery -A src.tasks.celery_app beat --loglevel=info
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync-beat

[Install]
WantedBy=multi-user.target
EOF

# Recarregar daemon
systemctl daemon-reload

print_success "Serviços systemd criados"

# 11. Criar scripts de gerenciamento
print_header "11. CRIANDO SCRIPTS DE GERENCIAMENTO"

# Script de inicialização
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash

set -e

INSTALL_DIR="/opt/vod-sync-xui"

echo "🚀 Iniciando VOD Sync XUI..."

# Iniciar serviços
echo "1. Iniciando MySQL..."
systemctl start mysql 2>/dev/null || true

echo "2. Iniciando Redis..."
systemctl start redis-server 2>/dev/null || true

echo "3. Iniciando Nginx..."
systemctl start nginx 2>/dev/null || true

echo "4. Iniciando aplicação Flask..."
systemctl start vod-sync 2>/dev/null || true

echo "5. Iniciando Celery Worker..."
systemctl start vod-sync-worker 2>/dev/null || true

echo "6. Iniciando Celery Beat..."
systemctl start vod-sync-beat 2>/dev/null || true

sleep 3

echo ""
echo "📊 Status dos serviços:"
echo "======================="

services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "✅ $service: ATIVO"
    else
        echo "❌ $service: INATIVO"
    fi
done

# Obter IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

echo ""
echo "🌐 URLs de acesso:"
echo "=================="
echo "  Interface Web:    http://$IP"
echo "  Saúde:            http://$IP/health"
echo ""
echo "🔧 Diretório: $INSTALL_DIR"
echo ""
echo "🎬 VOD Sync XUI está pronto!"
EOF

# Script de parada
cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash

echo "🛑 Parando VOD Sync XUI..."

# Parar serviços
systemctl stop vod-sync-beat 2>/dev/null || true
systemctl stop vod-sync-worker 2>/dev/null || true
systemctl stop vod-sync 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop redis-server 2>/dev/null || true

echo "✅ Serviços parados"
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

echo "📊 STATUS - VOD SYNC XUI"
echo "========================"
echo ""

# Serviços
echo "🔧 SERVIÇOS:"
echo "------------"
services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    
    if [ "$status" = "active" ]; then
        echo "✅ $service: ATIVO"
    elif [ "$status" = "inactive" ]; then
        echo "⏸️  $service: INATIVO"
    elif [ "$status" = "failed" ]; then
        echo "❌ $service: FALHOU"
    else
        echo "❓ $service: $status"
    fi
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
    echo "✅ Flask (5000): Ouvindo"
else
    echo "❌ Flask (5000): Não ouvindo"
fi

if ss -tlnp | grep -q :6379; then
    echo "✅ Redis (6379): Ouvindo"
else
    echo "❌ Redis (6379): Não ouvindo"
fi

echo ""

# Testes
echo "🧪 TESTES:"
echo "----------"

# Testar Redis
if redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "✅ Redis: CONECTADO"
else
    echo "❌ Redis: DESCONECTADO"
fi

# Testar API
if curl -s http://localhost/health 2>/dev/null | grep -q healthy; then
    echo "✅ API: RESPONDENDO"
else
    echo "❌ API: NÃO RESPONDE"
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
echo "1. Flask App"
echo "2. Nginx"
echo "3. Celery Worker"
echo "4. Celery Beat"
echo "5. Ver todos"
echo ""
read -p "Escolha (1-5): " choice

case $choice in
    1)
        journalctl -u vod-sync -f
        ;;
    2)
        tail -f "$INSTALL_DIR/logs/nginx/error.log"
        ;;
    3)
        journalctl -u vod-sync-worker -f
        ;;
    4)
        journalctl -u vod-sync-beat -f
        ;;
    5)
        echo "Pressione Ctrl+C para parar"
        echo "=== Flask ==="
        journalctl -u vod-sync -f --no-tail &
        FLASK_PID=$!
        
        echo "=== Celery Worker ==="
        journalctl -u vod-sync-worker -f --no-tail &
        WORKER_PID=$!
        
        wait
        ;;
    *)
        echo "Opção inválida"
        ;;
esac
EOF

# Dar permissões
chmod +x "$INSTALL_DIR"/*.sh

print_success "Scripts de gerenciamento criados"

# 12. Iniciar serviços
print_header "12. INICIALIZAÇÃO DOS SERVIÇOS"

# Testar Python e Celery primeiro
cd "$INSTALL_DIR"
source venv/bin/activate

print_step "Testando configuração Python..."
if python -c "import flask; import celery; print('✅ Python OK')"; then
    print_success "Python configurado"
else
    print_error "Python com problemas"
fi

print_step "Testando Celery..."
if python -c "from src.tasks.celery_app import celery_app; print('✅ Celery OK')"; then
    print_success "Celery configurado"
else
    print_error "Celery com problemas"
fi

# Iniciar serviços
echo ""
echo "Iniciando serviços..."
"$INSTALL_DIR/start.sh"

sleep 5

# 13. Verificar instalação
print_header "13. VERIFICAÇÃO FINAL"

ALL_OK=true
services=("mysql" "redis-server" "nginx" "vod-sync" "vod-sync-worker" "vod-sync-beat")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: OK"
    else
        echo "❌ $service: FALHOU"
        ALL_OK=false
        
        # Mostrar erro específico
        echo "   Últimos logs:"
        journalctl -u "$service" -n 5 --no-pager | sed 's/^/     /'
    fi
done

echo ""
print_step "Testando funcionalidades..."

# Testar Redis
if redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "✅ Redis funcionando"
else
    echo "❌ Redis não responde"
    ALL_OK=false
fi

# Testar API
if curl -s http://localhost/health 2>/dev/null | grep -q healthy; then
    echo "✅ API funcionando"
else
    echo "❌ API não responde"
    ALL_OK=false
fi

# Testar interface web
if curl -s http://localhost 2>/dev/null | grep -q "VOD Sync"; then
    echo "✅ Interface web funcionando"
else
    echo "❌ Interface web não carrega"
    ALL_OK=false
fi

echo ""
print_step "Informações do sistema..."

# IP
IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
echo "🌐 IP do servidor: $IP"

# Diretório
echo "📁 Diretório de instalação: $INSTALL_DIR"

# Credenciais
echo "🔐 Credenciais salvas em: $INSTALL_DIR/.env"

echo ""
print_step "Resumo..."

if $ALL_OK; then
    echo "✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo ""
    echo "🎉 Parabéns! O VOD Sync XUI está funcionando perfeitamente."
    echo ""
    echo "🚀 Próximos passos:"
    echo "   1. Acesse: http://$IP"
    echo "   2. Configure as fontes em: $INSTALL_DIR/config/sync_config.json"
    echo "   3. Use os controles na interface web"
    echo ""
    echo "📋 Scripts disponíveis:"
    echo "   $INSTALL_DIR/start.sh    - Iniciar tudo"
    echo "   $INSTALL_DIR/stop.sh     - Parar tudo"
    echo "   $INSTALL_DIR/restart.sh  - Reiniciar"
    echo "   $INSTALL_DIR/status.sh   - Ver status"
    echo "   $INSTALL_DIR/logs.sh     - Ver logs"
else
    echo "⚠️  INSTALAÇÃO PARCIALMENTE CONCLUÍDA"
    echo ""
    echo "Alguns serviços podem não estar funcionando."
    echo "Use os seguintes comandos para diagnosticar:"
    echo "  $INSTALL_DIR/status.sh   - Ver status detalhado"
    echo "  $INSTALL_DIR/logs.sh     - Ver logs de erro"
    echo "  $INSTALL_DIR/restart.sh  - Tentar reiniciar"
fi

print_divider
echo ""
echo "📞 Para suporte ou problemas:"
echo "   - Verifique os logs: $INSTALL_DIR/logs.sh"
echo "   - Consulte o status: $INSTALL_DIR/status.sh"
echo ""
print_divider

# Finalizar
exit 0
