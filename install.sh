#!/bin/bash
# install_vod_sync_minimal.sh - Instalador minimalista

set -e

echo "Instalador Minimalista VOD Sync XUI One"
echo "========================================"

# Verificar root
if [[ $EUID -ne 0 ]]; then
    echo "Execute como root: sudo $0"
    exit 1
fi

# Detectar sistema
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Sistema não suportado"
    exit 1
fi

echo "Sistema: $OS $VER"

# Atualizar
apt-get update

# Instalar dependências ABSOLUTAMENTE ESSENCIAIS
echo "Instalando dependências essenciais..."
apt-get install -y \
    curl wget git \
    python3 python3-pip python3-venv \
    mysql-server mysql-client \
    php php-cli php-mysql \
    nginx supervisor

# Criar estrutura básica
mkdir -p /opt/vod-sync-xui/{backend,frontend,logs,backups}

echo "✅ Dependências básicas instaladas"
echo ""
echo "Para continuar:"
echo "1. Configure o MySQL: sudo mysql_secure_installation"
echo "2. Instale manualmente:"
echo "   pip3 install fastapi uvicorn sqlalchemy pymysql"
echo "3. Configure o arquivo .env"
echo ""
echo "Script básico concluído!"
