
    # Criar arquivo de atualização
    cat > $INSTALL_DIR/scripts/update.sh <<'EOF'
#!/bin/bash

# Update script for VOD Sync System

echo "Updating VOD Sync System..."

# Backup current version
BACKUP_DIR="/opt/vod_sync_system/backups/update_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup database
mysqldump vod_sync_db > $BACKUP_DIR/database_backup.sql

# Backup configuration
cp -r /opt/vod_sync_system/config $BACKUP_DIR/
cp -r /opt/vod_sync_system/.env $BACKUP_DIR/

echo "Backup created in: $BACKUP_DIR"

# Update code (if using Git)
if [ -d "/opt/vod_sync_system/.git" ]; then
    cd /opt/vod_sync_system
    git pull origin main
fi

# Update Python dependencies
cd /opt/vod_sync_system/backend
source venv/bin/activate
pip install -r requirements.txt --upgrade

# Run database migrations
python -m alembic upgrade head

# Restart services
systemctl restart vod-scheduler
systemctl restart apache2

echo "Update completed successfully!"
EOF

    chmod +x $INSTALL_DIR/scripts/update.sh
    
    # Criar script de backup
    cat > $INSTALL_DIR/scripts/backup_database.sh <<'EOF'
#!/bin/bash

# Database backup script

BACKUP_DIR="/opt/vod_sync_system/backups/database"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/vod_sync_db_$DATE.sql"

mkdir -p $BACKUP_DIR

# Backup database
mysqldump --defaults-file=/opt/vod_sync_system/config/db_credentials.cnf \
          --single-transaction \
          --quick \
          --lock-tables=false \
          vod_sync_db > $BACKUP_FILE

# Compress backup
gzip $BACKUP_FILE

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "Backup created: $BACKUP_FILE.gz"
EOF

    chmod +x $INSTALL_DIR/scripts/backup_database.sh
    
    # Adicionar backup diário ao cron
    (crontab -l 2>/dev/null; echo "0 3 * * * /opt/vod_sync_system/scripts/backup_database.sh") | crontab -
    
    print_success "Scripts de manutenção criados"
}

show_final_message() {
    print_success "=================================================="
    print_success "     INSTALAÇÃO CONCLUÍDA COM SUCESSO!           "
    print_success "=================================================="
    echo ""
    echo "📋 RESUMO DA INSTALAÇÃO:"
    echo "   Diretório: $INSTALL_DIR"
    echo "   Backend: $INSTALL_DIR/$BACKEND_DIR"
    echo "   Frontend: $INSTALL_DIR/$FRONTEND_DIR"
    echo ""
    echo "🌐 URLS DE ACESSO:"
    echo "   Painel Web: http://$(hostname -I | awk '{print $1}')/"
    echo "   API Backend: http://$(hostname -I | awk '{print $1}'):8000"
    echo "   Documentação API: http://$(hostname -I | awk '{print $1}'):8000/api/docs"
    echo ""
    echo "🔐 CREDENCIAIS PADRÃO:"
    echo "   Usuário: admin"
    echo "   Senha: Admin@123"
    echo ""
    echo "🚀 INICIAR SISTEMA:"
    echo "   $INSTALL_DIR/start_system.sh start"
    echo ""
    echo "📄 RESUMO COMPLETO:"
    echo "   $INSTALL_DIR/INSTALL_SUMMARY.txt"
    echo ""
    print_success "=================================================="
    print_success "        SISTEMA PRONTO PARA USO!                 "
    print_success "=================================================="
}

main() {
    clear
    print_header
    
    # Registrar início
    echo "Iniciando instalação do VOD Sync System" > $LOG_FILE
    echo "Data: $(date)" >> $LOG_FILE
    echo "========================================" >> $LOG_FILE
    
    # Executar todos os passos
    check_requirements
    install_dependencies
    create_directories
    setup_database
    create_database_schema
    setup_backend
    setup_frontend
    setup_crontab
    create_license_script
    setup_permissions
    create_install_summary
    finalize_installation
    show_final_message
    
    # Registrar conclusão
    echo "Instalação concluída com sucesso!" >> $LOG_FILE
    echo "Data: $(date)" >> $LOG_FILE
}

# Executar instalação
main "$@"
