import os
import sys
import logging
from flask import Flask, render_template, jsonify, request, session, redirect, url_for
from flask_socketio import SocketIO, emit
from flask_login import LoginManager, login_user, logout_user, login_required, current_user
from flask_cors import CORS
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
import psutil
import datetime

# Adicionar diretório raiz ao path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.config import config
from src.database import init_db, get_db_session
from src.models.vod_models import User, VOD, SyncTask, Log
from src.services.sync_service import VODSyncService
from src.services.monitoring import SystemMonitor
from src.utils.logger import setup_logger
from src.api.routes import api_blueprint
from src.api.auth import auth_blueprint

# Configurar logging
logger = setup_logger('vod_sync')

# Inicializar Flask
app = Flask(__name__, 
            template_folder='dashboard/templates',
            static_folder='dashboard/static')

# Configurar Flask
app.config.update(config.flask_config)

# Configurar extensões
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'auth.login'

# Registrar blueprints
app.register_blueprint(api_blueprint, url_prefix='/api')
app.register_blueprint(auth_blueprint, url_prefix='/auth')

# Inicializar serviços
sync_service = VODSyncService(config)
system_monitor = SystemMonitor()

@login_manager.user_loader
def load_user(user_id):
    """Carregar usuário para Flask-Login"""
    session = get_db_session()
    return session.query(User).get(int(user_id))

@app.route('/')
@login_required
def index():
    """Página inicial do dashboard"""
    return render_template('index.html', 
                         user=current_user,
                         config=config)

@app.route('/dashboard')
@login_required
def dashboard():
    """Dashboard principal"""
    # Obter estatísticas do sistema
    stats = system_monitor.get_system_stats()
    
    # Obter estatísticas de VODs
    db_session = get_db_session()
    vod_count = db_session.query(VOD).count()
    pending_sync = db_session.query(SyncTask).filter_by(status='pending').count()
    completed_sync = db_session.query(SyncTask).filter_by(status='completed').count()
    
    # Obter logs recentes
    recent_logs = db_session.query(Log).order_by(Log.created_at.desc()).limit(10).all()
    
    db_session.close()
    
    return render_template('dashboard.html',
                         stats=stats,
                         vod_count=vod_count,
                         pending_sync=pending_sync,
                         completed_sync=completed_sync,
                         recent_logs=recent_logs,
                         user=current_user)

@app.route('/sync')
@login_required
def sync_page():
    """Página de sincronização"""
    db_session = get_db_session()
    sync_tasks = db_session.query(SyncTask).order_by(SyncTask.created_at.desc()).limit(50).all()
    vod_list = db_session.query(VOD).order_by(VOD.created_at.desc()).limit(50).all()
    db_session.close()
    
    return render_template('sync.html',
                         sync_tasks=sync_tasks,
                         vod_list=vod_list,
                         user=current_user)

@app.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    """Página de configurações"""
    if request.method == 'POST':
        # Atualizar configurações
        section = request.form.get('section')
        updates = {}
        
        if section == 'database':
            updates = {
                'host': request.form.get('db_host'),
                'port': int(request.form.get('db_port')),
                'user': request.form.get('db_user'),
                'password': request.form.get('db_password'),
                'database': request.form.get('db_name')
            }
        elif section == 'sync':
            updates = {
                'interval': int(request.form.get('sync_interval')),
                'max_concurrent': int(request.form.get('max_concurrent'))
            }
        elif section == 'storage':
            updates = {
                'local_path': request.form.get('local_path'),
                'max_size_gb': int(request.form.get('max_size_gb'))
            }
        
        config.update_config(section, updates)
        logger.info(f"Configurações atualizadas: {section}")
        
        return jsonify({'status': 'success', 'message': 'Configurações atualizadas!'})
    
    return render_template('settings.html',
                         config=config,
                         user=current_user)

@app.route('/logs')
@login_required
def logs_page():
    """Página de logs"""
    db_session = get_db_session()
    log_levels = ['INFO', 'WARNING', 'ERROR', 'DEBUG']
    selected_level = request.args.get('level', 'INFO')
    
    logs_query = db_session.query(Log)
    if selected_level != 'ALL':
        logs_query = logs_query.filter_by(level=selected_level)
    
    logs = logs_query.order_by(Log.created_at.desc()).limit(100).all()
    db_session.close()
    
    return render_template('logs.html',
                         logs=logs,
                         log_levels=log_levels,
                         selected_level=selected_level,
                         user=current_user)

@app.route('/metrics')
def metrics():
    """Endpoint para Prometheus metrics"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/system/stats')
@login_required
def system_stats():
    """API para estatísticas do sistema"""
    stats = system_monitor.get_system_stats()
    return jsonify(stats)

@app.route('/api/sync/start', methods=['POST'])
@login_required
def start_sync():
    """Iniciar sincronização manual"""
    try:
        task_id = sync_service.start_sync()
        logger.info(f"Sincronização iniciada manualmente: {task_id}")
        
        # Emitir evento via SocketIO
        socketio.emit('sync_started', {
            'task_id': task_id,
            'timestamp': datetime.datetime.now().isoformat(),
            'user': current_user.username
        })
        
        return jsonify({'status': 'success', 'task_id': task_id})
    except Exception as e:
        logger.error(f"Erro ao iniciar sincronização: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/sync/stop/<task_id>', methods=['POST'])
@login_required
def stop_sync(task_id):
    """Parar sincronização"""
    try:
        sync_service.stop_sync(task_id)
        logger.info(f"Sincronização parada: {task_id}")
        
        socketio.emit('sync_stopped', {
            'task_id': task_id,
            'timestamp': datetime.datetime.now().isoformat()
        })
        
        return jsonify({'status': 'success'})
    except Exception as e:
        logger.error(f"Erro ao parar sincronização: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/vods')
@login_required
def get_vods():
    """Obter lista de VODs"""
    db_session = get_db_session()
    
    # Parâmetros de paginação
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    
    # Filtros
    search = request.args.get('search', '')
    category = request.args.get('category', '')
    
    query = db_session.query(VOD)
    
    if search:
        query = query.filter(
            (VOD.title.contains(search)) | 
            (VOD.description.contains(search))
        )
    
    if category:
        query = query.filter_by(category=category)
    
    total = query.count()
    vods = query.order_by(VOD.created_at.desc())\
               .offset((page - 1) * per_page)\
               .limit(per_page)\
               .all()
    
    db_session.close()
    
    return jsonify({
        'vods': [vod.to_dict() for vod in vods],
        'total': total,
        'page': page,
        'per_page': per_page
    })

@socketio.on('connect')
def handle_connect():
    """Manipular conexão do cliente"""
    if current_user.is_authenticated:
        logger.info(f"Cliente conectado: {current_user.username}")
        emit('connected', {'message': 'Connected to VOD Sync Server'})

@socketio.on('request_stats')
def handle_stats_request():
    """Enviar estatísticas em tempo real"""
    stats = system_monitor.get_system_stats()
    emit('system_stats', stats)

def main():
    """Função principal"""
    # Inicializar banco de dados
    init_db()
    
    # Criar usuário admin se não existir
    db_session = get_db_session()
    if not db_session.query(User).filter_by(username='admin').first():
        admin_user = User(
            username='admin',
            email='admin@vodsync.com',
            is_admin=True
        )
        admin_user.set_password('admin123')
        db_session.add(admin_user)
        db_session.commit()
        logger.info("Usuário admin criado com senha: admin123")
    
    db_session.close()
    
    # Iniciar serviço de sincronização
    sync_service.start_background_sync()
    
    # Iniciar aplicação
    logger.info("Iniciando VOD Sync Server...")
    
    # Configurar SSL se habilitado
    ssl_context = None
    if config.security.ssl_enabled and config.security.ssl_cert and config.security.ssl_key:
        ssl_context = (config.security.ssl_cert, config.security.ssl_key)
    
    # Iniciar SocketIO
    socketio.run(app, 
                host='0.0.0.0', 
                port=5000, 
                debug=False,
                use_reloader=False,
                ssl_context=ssl_context)

if __name__ == '__main__':
    main()
