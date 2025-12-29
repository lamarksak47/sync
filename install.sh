#!/bin/bash
# fix-all-problems.sh

echo "Corrigindo todos os problemas do Sincronizador VOD..."

# 1. Corrigir PHP-FPM
echo "1. Corrigindo PHP-FPM..."
systemctl stop php8.1-fpm
rm -f /run/php/php8.1-fpm-sincronizador.sock
systemctl start php8.1-fpm
sleep 2

# 2. Corrigir permissões
echo "2. Corrigindo permissões..."
chown -R www-data:www-data /var/www/sincronizador-vod
chmod 775 /var/www/sincronizador-vod/backend/logs
chmod 775 /var/www/sincronizador-vod/logs

# 3. Reiniciar serviços
echo "3. Reiniciando serviços..."
services=("sincronizador-vod" "nginx" "mysql" "php8.1-fpm")
for service in "${services[@]}"; do
    systemctl restart $service
    sleep 1
done

# 4. Testar
echo "4. Testando instalação..."
cd /var/www/sincronizador-vod/scripts
./status.sh

echo "✅ Correções aplicadas!"
