#!/bin/bash
# uninstall-xui-vods-sync.sh
# Script para desinstalar completamente o XUI ONE VODs Sync

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${RED}"
    echo "============================================="
    echo "   XUI ONE VODs Sync - Desinstalador"
    echo "============================================="
    echo -e "${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script precisa ser executado como root"
        exit 1
    fi
}

confirm_uninstall() {
    print_header
    echo "⚠️  ATENÇÃO: Esta ação irá:"
    echo ""
    echo "1. Parar e remover todos os serviços"
    echo "2. Remover todos os arquivos de instalação"
    echo "3. Remover banco de dados (opcional)"
    echo "4. Remover configurações do sistema"
    echo ""
    echo -e "${RED}Esta ação é IRREVERSÍVEL!${NC}"
    echo ""
    
    read -p "Tem certeza que deseja continuar? (digite 'SIM' para confirmar): " confirm
    if [[ "$confirm" != "SIM" ]]; then
        echo "Desinstalação cancelada."
        exit 0
    fi
    
    echo ""
    read -p "Deseja remover o banco de dados também? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        REMOVE_DATABASE=true
    else
        REMOVE_DATABASE=false
    fi
    
    echo ""
    read -p "Deseja remover backups e dados do usuário? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        REMOVE_USER_DATA=true
    else
        REMOVE_USER_DATA=false
    fi
}

stop_services() {
    print_warning "Parando serviços..."
    
    # Para serviços
    systemctl stop xui-vods-api 2>/dev/null || true
    systemctl stop xui-vods-web 2>/dev/null || true
    
    # Remove serviços do systemd
    systemctl disable xui-vods-api 2>/dev/null || true
    systemctl disable xui-vods-web 2>/dev/null || true
    
    # Remove arquivos de serviço
    rm -f /etc/systemd/system/xui-vods-api.service
    rm -f /etc/systemd/system/xui-vods-web.service
    
    # Recarrega systemd
    systemctl daemon-reload
    
    print_success "Serviços parados e removidos"
}

remove_nginx_config() {
    print_warning "Removendo configuração do Nginx..."
    
    # Remove configuração do site
    rm -f /etc/nginx/sites-available/xui-vods-sync
    rm -f /etc/nginx/sites-enabled/xui-vods-sync
    
    # Recarrega Nginx
    nginx -t && systemctl reload nginx 2>/dev/null || true
    
    print_success "Configuração do Nginx removida"
}

remove_database() {
    if [[ "$REMOVE_DATABASE" != true ]]; then
        return 0
    fi
    
    print_warning "Removendo banco de dados..."
    
    # Tenta obter credenciais do arquivo de configuração
    if [[ -f "/etc/xui-one-vods-sync/api.env" ]]; then
        source <(grep -E "DB_NAME|DB_USER" /etc/xui-one-vods-sync/api.env | sed 's/^/export /')
    fi
    
    DB_NAME=${DB_NAME:-"xui_one_vods"}
    DB_USER=${DB_USER:-"xui_one_vods_user"}
    
    # Remove banco de dados
    mysql -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    print_success "Banco de dados removido"
}

remove_files() {
    print_warning "Removendo arquivos do sistema..."
    
    # Diretórios a serem removidos
    INSTALL_DIR="/opt/xui-one-vods-sync"
    CONFIG_DIR="/etc/xui-one-vods-sync"
    LOG_DIR="/var/log/xui-one-vods-sync"
    
    # Remove diretórios
    if [[ "$REMOVE_USER_DATA" == true ]]; then
        rm -rf "$INSTALL_DIR"
        rm -rf "$CONFIG_DIR"
        rm -rf "$LOG_DIR"
    else
        # Mantém backups e dados do usuário
        if [[ -d "$INSTALL_DIR/backups" ]]; then
            mv "$INSTALL_DIR/backups" /tmp/xui-vods-backups-$(date +%Y%m%d)
        fi
        rm -rf "$INSTALL_DIR"
        rm -rf "$CONFIG_DIR"
        rm -rf "$LOG_DIR"
        echo "Backups salvos em: /tmp/xui-vods-backups-$(date +%Y%m%d)"
    fi
    
    # Remove logs do Nginx
    rm -f /var/log/nginx/xui-vods-*.log 2>/dev/null || true
    
    # Remove cron jobs
    rm -f /etc/cron.d/xui-vods-backup 2>/dev/null || true
    rm -f /etc/cron.d/certbot-renew 2>/dev/null || true
    
    print_success "Arquivos removidos"
}

remove_user() {
    print_warning "Removendo usuário do sistema..."
    
    SERVICE_USER="xui-vods"
    
    # Remove usuário se não tiver arquivos
    if id "$SERVICE_USER" &>/dev/null; then
        userdel -r "$SERVICE_USER" 2>/dev/null || true
    fi
    
    print_success "Usuário removido"
}

remove_dependencies() {
    print_warning "Removendo dependências instaladas..."
    
    # Pergunta se deseja remover dependências
    read -p "Deseja remover as dependências instaladas? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_success "Dependências mantidas"
        return 0
    fi
    
    # Remove pacotes específicos
    apt-get remove --purge -y \
        python3.8-venv \
        python3-pip \
        mysql-server \
        nginx \
        redis-server \
        nodejs \
        certbot \
        python3-certbot-nginx
    
    # Limpa pacotes não utilizados
    apt-get autoremove -y
    apt-get clean
    
    print_success "Dependências removidas"
}

show_summary() {
    print_header
    echo -e "${GREEN}✅ DESINSTALAÇÃO CONCLUÍDA!${NC}"
    echo ""
    echo "O que foi removido:"
    echo "-------------------"
    echo "✓ Serviços do systemd"
    echo "✓ Arquivos de instalação"
    echo "✓ Configurações do Nginx"
    [[ "$REMOVE_DATABASE" == true ]] && echo "✓ Banco de dados"
    [[ "$REMOVE_USER_DATA" == true ]] && echo "✓ Backups e dados do usuário"
    [[ "$REMOVE_DEPENDENCIES" == true ]] && echo "✓ Dependências do sistema"
    echo ""
    
    if [[ "$REMOVE_USER_DATA" != true ]]; then
        echo "📁 Backups salvos em: /tmp/xui-vods-backups-$(date +%Y%m%d)"
        echo ""
    fi
    
    echo "O sistema foi completamente removido."
    echo ""
    
    # Verifica se há resíduos
    echo "Verificando resíduos..."
    echo ""
    
    if [[ -d "/opt/xui-one-vods-sync" ]]; then
        echo "⚠️  Diretório /opt/xui-one-vods-sync ainda existe"
    fi
    
    if systemctl list-units | grep -q "xui-vods"; then
        echo "⚠️  Serviços ainda estão registrados"
    fi
    
    echo ""
    echo "✅ Desinstalação concluída com sucesso!"
}

main() {
    check_root
    confirm_uninstall
    stop_services
    remove_nginx_config
    remove_database
    remove_files
    remove_user
    remove_dependencies
    show_summary
}

main

exit 0
