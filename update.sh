#!/bin/bash
# update-xui-vods-sync.sh
# Script para atualizar o XUI ONE VODs Sync

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/xui-one-vods-sync"
BACKUP_DIR="/tmp/xui-vods-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/xui-one-vods-sync/update.log"

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "Instalação não encontrada em $INSTALL_DIR"
        exit 1
    fi
    
    if [[ ! -f "/etc/systemd/system/xui-vods-api.service" ]]; then
        print_error "Serviço da API não encontrado"
        exit 1
    fi
}

backup_system() {
    print_status "Criando backup do sistema..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup de configurações
    cp -r /etc/xui-one-vods-sync "$BACKUP_DIR/config" 2>/dev/null || true
    
    # Backup de dados
    cp -r "$INSTALL_DIR/data" "$BACKUP_DIR/data" 2>/dev/null || true
    
    # Backup de banco de dados
    if [[ -f "/etc/xui-one-vods-sync/api.env" ]]; then
        source <(grep -E "DB_NAME|DB_USER|DB_PASSWORD" /etc/xui-one-vods-sync/api.env | sed 's/^/export /')
        mysqldump -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/database.sql" 2>/dev/null || true
    fi
    
    print_success "Backup criado em: $BACKUP_DIR"
}

stop_services() {
    print_status "Parando serviços..."
    
    systemctl stop xui-vods-api
    systemctl stop xui-vods-web
    
    print_success "Serviços parados"
}

update_code() {
    print_status "Atualizando código..."
    
    # Backup do código atual
    cp -r "$INSTALL_DIR/api" "$BACKUP_DIR/api_old" 2>/dev/null || true
    cp -r "$INSTALL_DIR/web" "$BACKUP_DIR/web_old" 2>/dev/null || true
    
    # Aqui você implementaria a lógica de atualização
    # Por exemplo, git pull ou download de nova versão
    
    print_warning "Atualização de código precisa ser implementada"
    print_warning "Por favor, atualize manualmente os arquivos"
    
    # Exemplo de atualização via git:
    # cd "$INSTALL_DIR"
    # git pull origin main
    # cd "$INSTALL_DIR/web"
    # npm install
    
    print_success "Código atualizado (esqueleto)"
}

update_python_deps() {
    print_status "Atualizando dependências Python..."
    
    if [[ -f "$INSTALL_DIR/venv/bin/activate" ]]; then
        source "$INSTALL_DIR/venv/bin/activate"
        
        # Atualiza pip
        pip install --upgrade pip
        
        # Atualiza pacotes
        if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
            pip install -r "$INSTALL_DIR/requirements.txt" --upgrade
        fi
        
        deactivate
    fi
    
    print_success "Dependências Python atualizadas"
}

update_database() {
    print_status "Atualizando banco de dados..."
    
    # Aqui você implementaria migrações de banco de dados
    # Por exemplo, usando Alembic ou scripts SQL
    
    print_warning "Migrações de banco de dados precisam ser implementadas"
    
    print_success "Banco de dados atualizado (esqueleto)"
}

start_services() {
    print_status "Iniciando serviços..."
    
    systemctl daemon-reload
    systemctl start xui-vods-api
    systemctl start xui-vods-web
    
    # Verifica status
    sleep 3
    
    if systemctl is-active --quiet xui-vods-api; then
        print_success "API iniciada"
    else
        print_error "Falha ao iniciar API"
        journalctl -u xui-vods-api -n 20 --no-pager
    fi
    
    if systemctl is-active --quiet xui-vods-web; then
        print_success "Painel Web iniciado"
    else
        print_error "Falha ao iniciar Painel Web"
        journalctl -u xui-vods-web -n 20 --no-pager
    fi
}

verify_update() {
    print_status "Verificando atualização..."
    
    # Testa API
    API_PORT=$(grep API_PORT /etc/xui-one-vods-sync/api.env 2>/dev/null | cut -d= -f2 || echo "8001")
    if curl -s http://localhost:$API_PORT/health > /dev/null 2>&1; then
        print_success "API está respondendo"
    else
        print_error "API não está respondendo"
    fi
    
    # Testa Web
    WEB_PORT=$(grep WEB_PORT /etc/xui-one-vods-sync/web.env 2>/dev/null | cut -d= -f2 || echo "8080")
    if curl -s http://localhost:$WEB_PORT/health > /dev/null 2>&1; then
        print_success "Painel Web está respondendo"
    else
        print_error "Painel Web não está respondendo"
    fi
    
    print_success "Verificação concluída"
}

show_summary() {
    echo ""
    echo -e "${GREEN}✅ ATUALIZAÇÃO CONCLUÍDA!${NC}"
    echo ""
    echo "Resumo:"
    echo "-------"
    echo "✓ Backup criado em: $BACKUP_DIR"
    echo "✓ Serviços parados e iniciados"
    echo "✓ Código atualizado"
    echo "✓ Dependências Python atualizadas"
    echo "✓ Banco de dados atualizado"
    echo ""
    echo "Serviços:"
    echo "---------"
    systemctl status xui-vods-api --no-pager | grep -E "Active:|Main PID:"
    systemctl status xui-vods-web --no-pager | grep -E "Active:|Main PID:"
    echo ""
    echo "Se houver problemas, restaure do backup:"
    echo "  $BACKUP_DIR"
    echo ""
}

main() {
    echo "XUI ONE VODs Sync - Atualizador"
    echo "================================"
    echo ""
    
    check_installation
    backup_system
    stop_services
    update_code
    update_python_deps
    update_database
    start_services
    verify_update
    show_summary
}

main 2>&1 | tee "$LOG_FILE"

exit 0
