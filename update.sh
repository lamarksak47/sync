#!/bin/bash
# Script de atualização do VOD Sync System

INSTALL_DIR="/opt/vodsync"
BACKUP_DIR="/backup/vodsync"
LOG_FILE="/var/log/vodsync-update.log"

echo "🔄 Iniciando atualização do VOD Sync System..."
echo "Data: $(date)" > "$LOG_FILE"

# Criar backup antes de atualizar
echo "💾 Criando backup..."
/usr/local/bin/vodsync-backup >> "$LOG_FILE" 2>&1

# Parar serviços
echo "⏸️ Parando serviços..."
vodsync-admin stop >> "$LOG_FILE" 2>&1

# Atualizar código
echo "📥 Atualizando código fonte..."
cd "$INSTALL_DIR"
git pull origin main >> "$LOG_FILE" 2>&1

# Atualizar dependências do backend
echo "🐍 Atualizando Python dependencies..."
cd "$INSTALL_DIR/backend"
source venv/bin/activate
pip install -r requirements.txt --upgrade >> "$LOG_FILE" 2>&1
deactivate

# Executar migrações do banco
echo "🗄️ Atualizando banco de dados..."
cd "$INSTALL_DIR/backend"
source venv/bin/activate
alembic upgrade head >> "$LOG_FILE" 2>&1
deactivate

# Atualizar permissões
echo "🔧 Atualizando permissões..."
chown -R www-data:www-data "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# Reiniciar serviços
echo "▶️ Reiniciando serviços..."
vodsync-admin start >> "$LOG_FILE" 2>&1

echo "✅ Atualização concluída!"
echo "📋 Logs disponíveis em: $LOG_FILE"
