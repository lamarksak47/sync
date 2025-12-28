#!/bin/bash
# configure-xui-mysql-remote.sh
# Script para configurar MySQL do XUI ONE para aceitar conexões remotas

print_header() {
    echo "=========================================="
    echo "   Configurar MySQL XUI ONE para Remoto"
    echo "=========================================="
    echo ""
}

print_info() {
    echo "[i] $1"
}

print_success() {
    echo "[✓] $1"
}

print_error() {
    echo "[✗] $1"
}

check_mysql() {
    if ! systemctl is-active --quiet mysql; then
        print_error "MySQL não está rodando"
        exit 1
    fi
}

get_mysql_credentials() {
    echo "Informe as credenciais do MySQL do XUI ONE:"
    echo ""
    
    read -p "Usuário MySQL [root]: " mysql_user
    mysql_user=${mysql_user:-root}
    
    read -sp "Senha MySQL: " mysql_pass
    echo ""
    
    if [ -z "$mysql_pass" ]; then
        print_error "Senha é obrigatória"
        exit 1
    fi
    
    # Testa conexão
    if ! mysql -u "$mysql_user" -p"$mysql_pass" -e "SELECT 1" &>/dev/null; then
        print_error "Credenciais inválidas"
        exit 1
    fi
}

allow_remote_access() {
    print_info "Configurando MySQL para aceitar conexões remotas..."
    
    # Backup do my.cnf
    cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup
    
    # Habilita bind-address para todas as interfaces
    sed -i 's/bind-address.*=.*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    
    # Configura usuário para acesso remoto
    mysql -u "$mysql_user" -p"$mysql_pass" << EOF
-- Cria usuário para acesso remoto
CREATE USER IF NOT EXISTS 'xui_remote'@'%' IDENTIFIED BY 'XuiRemotePass123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON xui.* TO 'xui_remote'@'%';
FLUSH PRIVILEGES;

-- Ou, se quiser usar o usuário existente
-- GRANT ALL PRIVILEGES ON xui.* TO 'seu_usuario'@'%' IDENTIFIED BY 'sua_senha';

-- Mostra usuários criados
SELECT user, host FROM mysql.user WHERE host = '%';
EOF
    
    print_success "Configuração do MySQL aplicada"
}

configure_firewall() {
    print_info "Configurando firewall para permitir MySQL..."
    
    if command -v ufw &>/dev/null; then
        ufw allow 3306/tcp
        ufw reload
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=3306/tcp
        firewall-cmd --reload
    else
        print_info "Firewall não detectado, configure manualmente a porta 3306"
    fi
    
    print_success "Firewall configurado"
}

restart_mysql() {
    print_info "Reiniciando MySQL..."
    systemctl restart mysql
    sleep 3
    
    if systemctl is-active --quiet mysql; then
        print_success "MySQL reiniciado com sucesso"
    else
        print_error "Erro ao reiniciar MySQL"
        exit 1
    fi
}

show_configuration() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "=========================================="
    echo "   CONFIGURAÇÃO COMPLETA!"
    echo "=========================================="
    echo ""
    echo "✅ MySQL configurado para aceitar conexões remotas"
    echo ""
    echo "📋 INFORMAÇÕES PARA O SINCRONIZADOR:"
    echo "   Host/IP: $IP_ADDRESS"
    echo "   Porta: 3306"
    echo "   Banco de dados: xui"
    echo "   Usuário: xui_remote"
    echo "   Senha: XuiRemotePass123!"
    echo ""
    echo "🔧 CONFIGURAÇÕES APLICADAS:"
    echo "   1. MySQL escuta em todas as interfaces (0.0.0.0)"
    echo "   2. Usuário 'xui_remote' criado com acesso remoto"
    echo "   3. Permissões concedidas para o banco 'xui'"
    echo "   4. Firewall configurado (porta 3306 aberta)"
    echo ""
    echo "⚠️  RECOMENDAÇÕES DE SEGURANÇA:"
    echo "   1. Altere a senha 'XuiRemotePass123!'"
    echo "   2. Restrinja o acesso por IP se possível"
    echo "   3. Mantenha o sistema atualizado"
    echo "   4. Monitore logs de acesso"
    echo ""
    echo "Para testar a conexão de outra máquina:"
    echo "  mysql -h $IP_ADDRESS -u xui_remote -pXuiRemotePass123! -e 'SHOW DATABASES;'"
    echo ""
}

main() {
    print_header
    check_mysql
    get_mysql_credentials
    allow_remote_access
    configure_firewall
    restart_mysql
    show_configuration
}

main
