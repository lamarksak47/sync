#!/bin/bash
# Script de desinstalação do VOD Sync System

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/opt/vodsync"

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    DESINSTALAÇÃO DO VOD SYNC                 ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirmar
read -p "Tem certeza que deseja remover o VOD Sync System? (s/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

echo "Parando serviços..."
systemctl stop supervisor
supervisorctl stop all
systemctl disable vodsync-backend 2>/dev/null || true

echo "Removendo serviços..."
rm -f /etc/systemd/system/vodsync-backend.service
rm -f /etc/supervisor/conf.d/vodsync-*.conf
rm -f /etc/nginx/sites-available/vodsync
rm -f /etc/nginx/sites-enabled/vodsync
rm -f /etc/php/8.1/fpm/pool.d/vodsync.conf
rm -f /etc/cron.d/vodsync-*

echo "Removendo arquivos do sistema..."
rm -rf "$INSTALL_DIR"
rm -f /usr/local/bin/vodsync-admin
rm -f /usr/local/bin/vodsync-backup
rm -f /usr/local/bin/vodsync-restore
rm -f /usr/local/bin/vodsync-monitor
rm -f /etc/profile.d/vodsync.sh
rm -f /etc/logrotate.d/vodsync

echo "Removendo banco de dados..."
mysql -e "DROP DATABASE IF EXISTS vod_sync_system;"
mysql -e "DROP USER IF EXISTS 'vodsync_user'@'localhost';"

echo "Reiniciando serviços..."
systemctl restart nginx php8.1-fpm supervisor
nginx -t && systemctl reload nginx

echo -e "${GREEN}✅ VOD Sync System removido com sucesso!${NC}"
echo ""
echo -e "${YELLOW}⚠️  O seguinte foi mantido:${NC}"
echo "  - Configurações do MySQL (outros bancos)"
echo "  - Configurações do Redis"
echo "  - Arquivos de backup em /backup/vodsync/"
echo "  - Logs em /var/log/vodsync-*"
echo ""
echo -e "${YELLOW}Para remover completamente, execute:${NC}"
echo "  rm -rf /backup/vodsync"
echo "  rm -f /var/log/vodsync-*"
echo "  apt remove --purge python3.10 php8.1 nginx mariadb redis"
