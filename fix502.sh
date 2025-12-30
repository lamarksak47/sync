#!/bin/bash

# ============================================
# CORRETOR 502 BAD GATEWAY - VOD SYNC SYSTEM
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# ==================== CORRIGIR 502 BAD GATEWAY ====================
fix_502_error() {
    log "🔧 CORRIGINDO ERRO 502 BAD GATEWAY..."
    echo ""
    
    # 1. Verificar se PHP-FPM está rodando
    log "1. Verificando PHP-FPM..."
    if systemctl is-active --quiet php7.4-fpm; then
        success "✅ PHP-FPM está rodando"
    else
        error "❌ PHP-FPM não está rodando"
        log "Tentando iniciar PHP-FPM..."
        systemctl start php7.4-fpm
        sleep 3
    fi
    
    # 2. Verificar socket do PHP-FPM
    log "2. Verificando socket PHP-FPM..."
    if [ -S /var/run/php/php7.4-fpm.sock ]; then
        success "✅ Socket PHP-FPM existe: /var/run/php/php7.4-fpm.sock"
        ls -la /var/run/php/php7.4-fpm.sock
    else
        error "❌ Socket PHP-FPM não existe"
        log "Procurando socket alternativo..."
        find /var/run -name "*.sock" 2>/dev/null | grep -i php
    fi
    
    # 3. Verificar configuração do pool PHP-FPM
    log "3. Verificando configuração PHP-FPM..."
    PHP_POOL_CONF="/etc/php/7.4/fpm/pool.d/www.conf"
    if [ -f "$PHP_POOL_CONF" ]; then
        log "Configuração encontrada: $PHP_POOL_CONF"
        
        # Verificar configuração do socket
        SOCKET_CONFIG=$(grep "^listen" "$PHP_POOL_CONF")
        log "Configuração listen: $SOCKET_CONFIG"
        
        # Se estiver usando porta em vez de socket, corrigir
        if echo "$SOCKET_CONFIG" | grep -q "127.0.0.1:9000"; then
            log "Configurando para usar socket em vez de porta..."
            sed -i 's/^listen = .*/listen = \/var\/run\/php\/php7.4-fpm.sock/' "$PHP_POOL_CONF"
            success "✅ Configuração do socket corrigida"
        fi
        
        # Verificar usuário/grupo
        USER_CONFIG=$(grep "^user\|^group" "$PHP_POOL_CONF")
        log "Usuário/Grupo: $USER_CONFIG"
        
        # Corrigir permissões se necessário
        sed -i 's/^user = .*/user = www-data/' "$PHP_POOL_CONF"
        sed -i 's/^group = .*/group = www-data/' "$PHP_POOL_CONF"
        
    else
        error "❌ Arquivo de configuração do pool não encontrado"
        # Criar configuração básica
        mkdir -p /etc/php/7.4/fpm/pool.d/
        cat > "$PHP_POOL_CONF" << 'EOF'
[www]
user = www-data
group = www-data
listen = /var/run/php/php7.4-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
EOF
        success "✅ Configuração do pool criada"
    fi
    
    # 4. Corrigir permissões do socket
    log "4. Corrigindo permissões do socket..."
    mkdir -p /var/run/php
    chown -R www-data:www-data /var/run/php
    chmod 755 /var/run/php
    
    # 5. Reiniciar PHP-FPM
    log "5. Reiniciando PHP-FPM..."
    systemctl restart php7.4-fpm
    sleep 3
    
    # 6. Verificar configuração do Nginx
    log "6. Verificando configuração do Nginx..."
    NGINX_CONF="/etc/nginx/sites-available/vod-sync"
    if [ -f "$NGINX_CONF" ]; then
        log "Configuração Nginx encontrada"
        
        # Verificar se está apontando para o socket correto
        if grep -q "fastcgi_pass.*9000" "$NGINX_CONF"; then
            log "Corrigindo Nginx para usar socket..."
            # Backup
            cp "$NGINX_CONF" "${NGINX_CONF}.backup"
            
            # Substituir porta por socket
            sed -i 's/fastcgi_pass.*9000/fastcgi_pass unix:\/var\/run\/php\/php7.4-fpm.sock/' "$NGINX_CONF"
            sed -i 's/fastcgi_pass.*127.0.0.1:9000/fastcgi_pass unix:\/var\/run\/php\/php7.4-fpm.sock/' "$NGINX_CONF"
            success "✅ Configuração Nginx corrigida"
        fi
        
        # Verificar se já está usando socket
        if grep -q "fastcgi_pass.*php7.4-fpm.sock" "$NGINX_CONF"; then
            success "✅ Nginx já configurado para usar socket"
        fi
    else
        error "❌ Configuração Nginx não encontrada"
        # Criar configuração correta
        cat > "$NGINX_CONF" << 'NGINX_FIXED'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /opt/vod-sync/frontend/public;
    index index.php index.html index.htm;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    client_max_body_size 100M;
}
NGINX_FIXED
        success "✅ Configuração Nginx criada"
    fi
    
    # 7. Testar configuração Nginx
    log "7. Testando configuração Nginx..."
    if nginx -t; then
        success "✅ Configuração Nginx válida"
    else
        error "❌ Erro na configuração Nginx"
        nginx -t 2>&1
        return 1
    fi
    
    # 8. Reiniciar Nginx
    log "8. Reiniciando Nginx..."
    systemctl restart nginx
    sleep 3
    
    # 9. Verificar se serviços estão rodando
    log "9. Verificando status dos serviços..."
    
    if systemctl is-active --quiet nginx; then
        success "✅ Nginx está rodando"
    else
        error "❌ Nginx não está rodando"
        journalctl -u nginx --no-pager -n 20
    fi
    
    if systemctl is-active --quiet php7.4-fpm; then
        success "✅ PHP-FPM está rodando"
    else
        error "❌ PHP-FPM não está rodando"
        journalctl -u php7.4-fpm --no-pager -n 20
    fi
    
    # 10. Testar conexão
    log "10. Testando conexão HTTP..."
    sleep 2
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200\|302\|301"; then
        success "✅ HTTP status OK"
    else
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
        error "❌ HTTP status: $HTTP_STATUS"
        
        # Verificar logs de erro
        log "📋 Últimos logs do Nginx:"
        tail -20 /var/log/nginx/error.log
        
        log "📋 Últimos logs do PHP-FPM:"
        tail -20 /var/log/php7.4-fpm.log 2>/dev/null || journalctl -u php7.4-fpm --no-pager -n 20
    fi
    
    # 11. Criar arquivo de teste PHP
    log "11. Criando arquivo de teste PHP..."
    cat > /opt/vod-sync/frontend/public/test-fix.php << 'PHP_TEST'
<?php
echo "<h1>✅ Teste PHP Funcionando!</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Server: " . $_SERVER['SERVER_SOFTWARE'] . "</p>";
echo "<p>Date: " . date('Y-m-d H:i:s') . "</p>";

// Testar funções básicas
echo "<h3>Testes:</h3>";
echo "<ul>";
echo "<li>Session: " . (function_exists('session_start') ? '✅' : '❌') . "</li>";
echo "<li>MySQLi: " . (function_exists('mysqli_connect') ? '✅' : '❌') . "</li>";
echo "<li>cURL: " . (function_exists('curl_init') ? '✅' : '❌') . "</li>";
echo "<li>GD: " . (function_exists('gd_info') ? '✅' : '❌') . "</li>";
echo "</ul>";

// Testar escrita
$test_file = '/tmp/php_test_' . time() . '.txt';
if (file_put_contents($test_file, 'Test OK')) {
    echo "<p>✅ Escrita em arquivo: OK</p>";
    unlink($test_file);
} else {
    echo "<p>❌ Escrita em arquivo: FALHOU</p>";
}
?>
PHP_TEST
    
    # 12. Verificar se podemos acessar o teste
    log "12. Testando acesso ao arquivo PHP..."
    sleep 2
    
    TEST_URL="http://localhost/test-fix.php"
    if curl -s "$TEST_URL" | grep -q "Teste PHP Funcionando"; then
        success "✅ Teste PHP funcionando!"
        echo ""
        echo "🌐 Acesse: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}')/test-fix.php"
    else
        error "❌ Teste PHP falhou"
        
        # Diagnóstico detalhado
        log "🔍 Diagnóstico detalhado:"
        
        # Verificar permissões
        log "Permissões do diretório:"
        ls -la /opt/vod-sync/frontend/public/
        
        # Verificar se o arquivo existe
        if [ -f "/opt/vod-sync/frontend/public/test-fix.php" ]; then
            log "Arquivo de teste existe"
        else
            error "Arquivo de teste não foi criado"
        fi
        
        # Testar socket diretamente
        log "Testando socket PHP-FPM..."
        if [ -S /var/run/php/php7.4-fpm.sock ]; then
            log "Socket existe, testando comunicação..."
            echo "<?php echo 'TEST'; ?>" | cgi-fcgi -bind -connect /var/run/php/php7.4-fpm.sock 2>&1 | head -5
        fi
    fi
    
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🔧 CORREÇÕES APLICADAS:"
    echo "   1. Configuração PHP-FPM verificada/corrigida"
    echo "   2. Socket PHP-FPM configurado"
    echo "   3. Permissões do socket corrigidas"
    echo "   4. Configuração Nginx atualizada"
    echo "   5. Serviços reiniciados"
    echo ""
    echo "⚡ COMANDOS PARA VERIFICAR:"
    echo "   sudo systemctl status php7.4-fpm"
    echo "   sudo systemctl status nginx"
    echo "   sudo tail -f /var/log/nginx/error.log"
    echo ""
    echo "🌐 TESTES:"
    echo "   http://seu-ip/test-fix.php"
    echo "   http://seu-ip/"
    echo ""
    echo "⚠️  Se ainda tiver 502:"
    echo "   1. sudo systemctl restart php7.4-fpm"
    echo "   2. sudo systemctl restart nginx"
    echo "   3. Verificar: ls -la /var/run/php/"
    echo ""
    echo "══════════════════════════════════════════════════════════"
    
    # Remover arquivo de teste após 1 minuto
    (sleep 60 && rm -f /opt/vod-sync/frontend/public/test-fix.php 2>/dev/null && echo "Arquivo de teste removido") &
}

# ==================== DIAGNÓSTICO COMPLETO ====================
full_diagnostic() {
    log "🔍 DIAGNÓSTICO COMPLETO DO SISTEMA"
    echo ""
    
    # 1. Serviços
    log "1. STATUS DOS SERVIÇOS:"
    echo "----------------------------------------"
    systemctl status nginx --no-pager | head -10
    echo ""
    systemctl status php7.4-fpm --no-pager | head -10
    echo ""
    systemctl status vod-sync-backend --no-pager | head -10
    echo ""
    
    # 2. Portas
    log "2. PORTAS ABERTAS:"
    echo "----------------------------------------"
    ss -tuln | grep -E ":80|:8000|:9000"
    echo ""
    
    # 3. Socket PHP-FPM
    log "3. SOCKET PHP-FPM:"
    echo "----------------------------------------"
    ls -la /var/run/php/ 2>/dev/null || echo "Diretório /var/run/php/ não existe"
    echo ""
    
    # 4. Configuração PHP-FPM
    log "4. CONFIGURAÇÃO PHP-FPM:"
    echo "----------------------------------------"
    if [ -f /etc/php/7.4/fpm/pool.d/www.conf ]; then
        grep -E "^(listen|user|group|listen.owner|listen.group)" /etc/php/7.4/fpm/pool.d/www.conf
    else
        echo "Arquivo de configuração não encontrado"
    fi
    echo ""
    
    # 5. Configuração Nginx
    log "5. CONFIGURAÇÃO NGINX:"
    echo "----------------------------------------"
    if [ -f /etc/nginx/sites-available/vod-sync ]; then
        grep -A5 -B5 "fastcgi_pass\|location.*\.php" /etc/nginx/sites-available/vod-sync
    else
        echo "Arquivo de configuração não encontrado"
    fi
    echo ""
    
    # 6. Logs de erro recentes
    log "6. LOGS DE ERRO (últimas 10 linhas):"
    echo "----------------------------------------"
    log "Nginx error.log:"
    tail -10 /var/log/nginx/error.log 2>/dev/null || echo "Arquivo de log não encontrado"
    echo ""
    
    log "PHP-FPM log:"
    tail -10 /var/log/php7.4-fpm.log 2>/dev/null || journalctl -u php7.4-fpm --no-pager -n 10
    echo ""
    
    # 7. Teste de conexão
    log "7. TESTE DE CONEXÃO:"
    echo "----------------------------------------"
    echo "Testando Nginx na porta 80:"
    curl -I http://localhost 2>&1 | head -1
    echo ""
    
    echo "Testando Backend na porta 8000:"
    curl -I http://localhost:8000 2>&1 | head -1
    echo ""
    
    # 8. Permissões
    log "8. PERMISSÕES:"
    echo "----------------------------------------"
    echo "Diretório frontend:"
    ls -la /opt/vod-sync/frontend/public/ | head -5
    echo ""
    
    # 9. Versões
    log "9. VERSÕES:"
    echo "----------------------------------------"
    echo "Nginx: $(nginx -v 2>&1)"
    echo "PHP: $(php -v 2>&1 | head -1)"
    echo ""
}

# ==================== MENU DE CORREÇÃO ====================
show_fix_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     CORRETOR 502 BAD GATEWAY - VOD SYNC SYSTEM         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "Problema detectado: 502 Bad Gateway"
    echo "Isso significa que o Nginx não está se comunicando com o PHP-FPM"
    echo ""
    
    echo "Opções:"
    echo "1) 🔧 Correção Automática Completa"
    echo "2) 🔍 Diagnóstico Completo do Sistema"
    echo "3) 🔄 Apenas Reiniciar Serviços"
    echo "4) ⚙️  Ver Configurações Atuais"
    echo "5) 🚪 Voltar/Sair"
    echo ""
    
    read -p "Escolha uma opção: " choice
    
    case $choice in
        1)
            fix_502_error
            ;;
        2)
            full_diagnostic
            ;;
        3)
            log "Reiniciando serviços..."
            systemctl restart php7.4-fpm
            systemctl restart nginx
            systemctl restart vod-sync-backend
            sleep 3
            success "Serviços reiniciados"
            echo ""
            echo "Teste agora: curl -I http://localhost"
            ;;
        4)
            log "Configurações atuais:"
            echo "========================================"
            echo "PHP-FPM socket:"
            ls -la /var/run/php/*.sock 2>/dev/null || echo "Nenhum socket encontrado"
            echo ""
            echo "Nginx config (fastcgi_pass):"
            grep "fastcgi_pass" /etc/nginx/sites-available/vod-sync 2>/dev/null || echo "Configuração não encontrada"
            echo ""
            echo "PHP-FPM config (listen):"
            grep "^listen" /etc/php/7.4/fpm/pool.d/www.conf 2>/dev/null || echo "Configuração não encontrada"
            ;;
        5)
            exit 0
            ;;
        *)
            echo "Opção inválida"
            ;;
    esac
    
    echo ""
    read -p "Pressione Enter para continuar..." </dev/tty
}

# ==================== SOLUÇÃO RÁPIDA ====================
quick_fix() {
    # Solução mais simples e direta
    echo "🔄 Aplicando solução rápida..."
    
    # 1. Garantir que o diretório do socket existe
    mkdir -p /var/run/php
    chown www-data:www-data /var/run/php
    
    # 2. Configurar PHP-FPM para usar socket
    cat > /etc/php/7.4/fpm/pool.d/www.conf << 'PHP_FPM_FIX'
[www]
user = www-data
group = www-data
listen = /var/run/php/php7.4-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 10
php_admin_value[error_log] = /var/log/php7.4-fpm.log
php_admin_flag[log_errors] = on
PHP_FPM_FIX
    
    # 3. Configurar Nginx para usar socket
    cat > /etc/nginx/sites-available/vod-sync << 'NGINX_FIX'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /opt/vod-sync/frontend/public;
    index index.php index.html index.htm;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    client_max_body_size 100M;
}
NGINX_FIX
    
    # 4. Reiniciar serviços
    systemctl restart php7.4-fpm
    systemctl restart nginx
    
    echo "✅ Solução aplicada. Testando..."
    sleep 3
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200\|302\|301"; then
        echo "🎉 PROBLEMA RESOLVIDO! O site agora está acessível."
        echo "🌐 Acesse: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    else
        echo "⚠️  Ainda com problemas. Execute o diagnóstico completo."
    fi
}

# ==================== EXECUÇÃO PRINCIPAL ====================
main() {
    if [ "$1" = "--quick" ]; then
        quick_fix
    elif [ "$1" = "--diagnose" ]; then
        full_diagnostic
    else
        while true; do
            show_fix_menu
        done
    fi
}

# Executar
main "$@"
