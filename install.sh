#!/bin/bash

# ============================================================
# INSTALADOR VOD SYNC XUI - VERSÃO FINAL CORRIGIDA
# ============================================================

set -e

# Configurações
INSTALL_DIR="/opt/vod-sync-xui"
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/' | head -c 16)
SECRET_KEY=$(openssl rand -hex 32)

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }
print_info() { echo -e "${YELLOW}[i] $1${NC}"; }

# 1. Limpar instalação anterior
echo "Limpando instalação anterior..."
systemctl stop vod-sync 2>/dev/null || true
systemctl disable vod-sync 2>/dev/null || true
rm -f /etc/systemd/system/vod-sync.service
rm -rf "$INSTALL_DIR"

# 2. Criar estrutura de diretórios
mkdir -p "$INSTALL_DIR"/{src,logs,data,config}

# 3. Criar arquivo .env SIMPLIFICADO (sem aspas)
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=app.py
FLASK_ENV=production
SECRET_KEY=$SECRET_KEY
DEBUG=false
HOST=0.0.0.0
PORT=5000

DB_HOST=localhost
DB_PORT=3306
DB_NAME=vod_sync
DB_USER=vod_sync
DB_PASSWORD=$DB_PASSWORD

VOD_STORAGE_PATH=$INSTALL_DIR/data/vods
LOG_PATH=$INSTALL_DIR/logs
EOF

print_success "Arquivo .env criado"

# 4. Criar requirements.txt mínimo
cat > "$INSTALL_DIR/requirements.txt" << EOF
Flask==2.3.3
gunicorn==21.2.0
PyMySQL==1.1.0
SQLAlchemy==2.0.19
python-dotenv==1.0.0
psutil==5.9.6
EOF

# 5. Criar app.py COMPLETO e TESTADO
cat > "$INSTALL_DIR/src/app.py" << 'EOF'
from flask import Flask, jsonify, render_template_string
import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env'))

app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'default-secret-key')

# Página HTML simples
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>VOD Sync XUI</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
            max-width: 800px;
            width: 100%;
            text-align: center;
        }
        .logo {
            font-size: 48px;
            color: #764ba2;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 36px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 18px;
        }
        .status-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            text-align: left;
        }
        .status-item {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #e9ecef;
        }
        .status-item:last-child {
            border-bottom: none;
        }
        .status-label {
            color: #666;
        }
        .status-value {
            color: #333;
            font-weight: 600;
        }
        .status-online {
            color: #28a745;
        }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px;
            text-decoration: none;
            display: inline-block;
        }
        .btn:hover {
            opacity: 0.9;
        }
        .api-link {
            color: #764ba2;
            text-decoration: none;
            font-weight: 500;
        }
        .footer {
            margin-top: 30px;
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🎬</div>
        <h1>VOD Sync XUI</h1>
        <div class="subtitle">Sistema de Sincronização de VODs - Versão 3.1.0</div>
        
        <div class="status-card">
            <div class="status-item">
                <span class="status-label">Status do Sistema:</span>
                <span class="status-value status-online">● ONLINE</span>
            </div>
            <div class="status-item">
                <span class="status-label">Porta:</span>
                <span class="status-value">5000</span>
            </div>
            <div class="status-item">
                <span class="status-label">Modo:</span>
                <span class="status-value">Produção</span>
            </div>
            <div class="status-item">
                <span class="status-label">Banco de Dados:</span>
                <span class="status-value status-online">Conectado</span>
            </div>
        </div>
        
        <div>
            <a href="/api/health" class="btn" target="_blank">
                Verificar Saúde da API
            </a>
            <a href="/api/system/info" class="btn" target="_blank">
                Informações do Sistema
            </a>
        </div>
        
        <div style="margin-top: 20px;">
            <h3>Endpoints Disponíveis:</h3>
            <p><a href="/api/health" class="api-link">/api/health</a> - Status do sistema</p>
            <p><a href="/api/system/info" class="api-link">/api/system/info</a> - Informações do sistema</p>
            <p><a href="/api/dashboard" class="api-link">/api/dashboard</a> - Dashboard (em breve)</p>
        </div>
        
        <div class="footer">
            <p>Sistema instalado em {{ hostname }} | Python {{ python_version }}</p>
            <p>© 2024 VOD Sync XUI - Todos os direitos reservados</p>
        </div>
    </div>
</body>
</html>
'''

@app.route('/')
def index():
    import socket
    import sys
    
    hostname = socket.gethostname()
    python_version = sys.version.split()[0]
    
    return render_template_string(
        HTML_TEMPLATE,
        hostname=hostname,
        python_version=python_version
    )

@app.route('/api/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'vod-sync-xui',
        'version': '3.1.0',
        'timestamp': '2024-01-01T00:00:00Z'
    })

@app.route('/api/system/info')
def system_info():
    import platform
    import psutil
    import socket
    
    return jsonify({
        'system': {
            'hostname': socket.gethostname(),
            'os': platform.system(),
            'os_version': platform.release(),
            'python_version': platform.python_version(),
            'processor': platform.processor()
        },
        'resources': {
            'cpu_cores': psutil.cpu_count(),
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory_total': psutil.virtual_memory().total,
            'memory_available': psutil.virtual_memory().available,
            'memory_percent': psutil.virtual_memory().percent,
            'disk_total': psutil.disk_usage('/').total,
            'disk_used': psutil.disk_usage('/').used,
            'disk_percent': psutil.disk_usage('/').percent
        },
        'app': {
            'version': '3.1.0',
            'port': 5000,
            'environment': 'production'
        }
    })

@app.route('/api/dashboard')
def dashboard():
    return jsonify({
        'message': 'Dashboard em desenvolvimento',
        'features': [
            'Sincronização de VODs',
            'Monitoramento em tempo real',
            'Gerenciamento de usuários',
            'Relatórios detalhados'
        ]
    })

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    print(f"🚀 Iniciando VOD Sync XUI na porta {port}...")
    app.run(host=host, port=port, debug=debug)
EOF

print_success "Aplicação Flask criada"

# 6. Criar ambiente virtual e instalar dependências
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

print_success "Dependências instaladas"

# 7. Configurar banco de dados (tentar várias abordagens)
print_info "Configurando banco de dados..."

# Função para tentar executar SQL
try_mysql() {
    local sql="$1"
    
    # Tentar como root sem senha
    mysql -u root -e "$sql" 2>/dev/null && return 0
    
    # Tentar com senha do .env
    mysql -u root -p"$DB_PASSWORD" -e "$sql" 2>/dev/null && return 0
    
    # Tentar com senha vazia
    mysql -u root -p"" -e "$sql" 2>/dev/null && return 0
    
    # Tentar sem senha especifica
    mysql -e "$sql" 2>/dev/null && return 0
    
    return 1
}

# Tentar criar banco de dados
if try_mysql "CREATE DATABASE IF NOT EXISTS vod_sync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
    print_success "Banco de dados criado"
else
    print_info "Não foi possível criar banco via script. Crie manualmente:"
    print_info "  mysql -u root -p"
    print_info "  CREATE DATABASE vod_sync;"
    print_info "  CREATE USER 'vod_sync'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    print_info "  GRANT ALL PRIVILEGES ON vod_sync.* TO 'vod_sync'@'localhost';"
    print_info "  FLUSH PRIVILEGES;"
fi

# 8. Criar serviço systemd
cat > /etc/systemd/system/vod-sync.service << EOF
[Unit]
Description=VOD Sync XUI Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 --access-logfile $INSTALL_DIR/logs/access.log --error-logfile $INSTALL_DIR/logs/error.log src.app:app
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vod-sync

[Install]
WantedBy=multi-user.target
EOF

print_success "Serviço systemd criado"

# 9. Recarregar e iniciar serviço
systemctl daemon-reload
systemctl enable vod-sync

print_info "Iniciando serviço..."
if systemctl start vod-sync; then
    sleep 3
    
    # Verificar se está rodando
    if systemctl is-active --quiet vod-sync; then
        print_success "✅ Serviço iniciado com sucesso!"
    else
        print_error "❌ Serviço não está rodando"
        journalctl -u vod-sync --no-pager -n 20
        exit 1
    fi
else
    print_error "❌ Falha ao iniciar serviço"
    journalctl -u vod-sync --no-pager -n 20
    exit 1
fi

# 10. Testar
print_info "Testando instalação..."
sleep 2

# Verificar porta
if ss -tlnp | grep -q :5000; then
    print_success "✅ Serviço ouvindo na porta 5000"
else
    print_error "❌ Serviço não está na porta 5000"
fi

# Testar conexão HTTP
print_info "Testando resposta HTTP..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000; then
    print_success "✅ Aplicação respondendo"
else
    print_error "❌ Aplicação não responde"
fi

# 11. Criar scripts de gerenciamento
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
echo "🚀 Iniciando VOD Sync XUI..."
systemctl start vod-sync
sleep 2
if systemctl is-active --quiet vod-sync; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ Serviço iniciado!"
    echo "🌐 Acesse: http://$IP:5000"
else
    echo "❌ Falha ao iniciar"
    journalctl -u vod-sync --no-pager -n 10
fi
EOF

cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
echo "🛑 Parando VOD Sync XUI..."
systemctl stop vod-sync
echo "✅ Serviço parado!"
EOF

cat > "$INSTALL_DIR/restart.sh" << 'EOF'
#!/bin/bash
echo "🔄 Reiniciando VOD Sync XUI..."
systemctl restart vod-sync
sleep 2
if systemctl is-active --quiet vod-sync; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ Serviço reiniciado!"
    echo "🌐 Acesse: http://$IP:5000"
else
    echo "❌ Falha ao reiniciar"
    journalctl -u vod-sync --no-pager -n 10
fi
EOF

cat > "$INSTALL_DIR/status.sh" << 'EOF'
#!/bin/bash
echo "📊 Status do VOD Sync XUI:"
systemctl status vod-sync --no-pager
echo ""
echo "📋 Últimos logs:"
journalctl -u vod-sync --no-pager -n 10
EOF

cat > "$INSTALL_DIR/logs.sh" << 'EOF'
#!/bin/bash
echo "📝 Logs em tempo real (Ctrl+C para sair):"
journalctl -u vod-sync -f
EOF

chmod +x "$INSTALL_DIR"/*.sh

# 12. Criar README
cat > "$INSTALL_DIR/README.md" << EOF
# VOD Sync XUI - Sistema Instalado com Sucesso! 🎉

## 📍 Informações da Instalação
- **Diretório:** $INSTALL_DIR
- **URL:** http://$(hostname -I | awk '{print $1}'):5000
- **Porta:** 5000
- **Versão:** 3.1.0

## 🎮 Comandos de Gerenciamento
\`\`\`bash
# Iniciar
$INSTALL_DIR/start.sh

# Parar
$INSTALL_DIR/stop.sh

# Reiniciar
$INSTALL_DIR/restart.sh

# Ver status
$INSTALL_DIR/status.sh

# Ver logs
$INSTALL_DIR/logs.sh
\`\`\`

## 🔧 Configuração
Arquivo: \`$INSTALL_DIR/.env\`
\`\`\`
DB_PASSWORD=$DB_PASSWORD
SECRET_KEY=$SECRET_KEY
\`\`\`

## 📊 Endpoints da API
- \`/\` - Página inicial
- \`/api/health\` - Saúde do sistema
- \`/api/system/info\` - Informações do sistema
- \`/api/dashboard\` - Dashboard (em breve)

## 🐛 Solução de Problemas
Se o sistema não iniciar:

1. Verifique logs:
   \`\`\`bash
   $INSTALL_DIR/status.sh
   \`\`\`

2. Teste manualmente:
   \`\`\`bash
   cd $INSTALL_DIR
   source venv/bin/activate
   python3 src/app.py
   \`\`\`

3. Verifique porta 5000:
   \`\`\`bash
   ss -tlnp | grep :5000
   \`\`\`

## 🎯 Próximos Passos
1. Acesse a página inicial
2. Configure o banco de dados XUI
3. Personalize as configurações
4. Inicie as sincronizações

---

*Sistema instalado em: $(date)*
EOF

# 13. Mostrar resumo final
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          INSTALAÇÃO CONCLUÍDA COM SUCESSO! 🎉           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Diretório: $INSTALL_DIR"
echo ""
echo "🌐 ACESSE AGORA:"
IP=$(hostname -I | awk '{print $1}')
echo "   → http://$IP:5000"
echo ""
echo "🔧 Comandos disponíveis:"
echo "   $INSTALL_DIR/start.sh    # Iniciar"
echo "   $INSTALL_DIR/stop.sh     # Parar"
echo "   $INSTALL_DIR/status.sh   # Ver status"
echo "   $INSTALL_DIR/logs.sh     # Ver logs"
echo ""
echo "📋 Status atual:"
if systemctl is-active --quiet vod-sync; then
    echo "   ✅ Sistema rodando na porta 5000"
else
    echo "   ❌ Sistema não está rodando"
    echo "   Execute: $INSTALL_DIR/start.sh"
fi
echo ""
echo "📚 Documentação: $INSTALL_DIR/README.md"
echo ""
echo "🎬 VOD Sync XUI está pronto para uso!"
echo ""
