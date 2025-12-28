import os
import yaml
from dataclasses import dataclass
from typing import Optional, Dict, Any
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

@dataclass
class DatabaseConfig:
    """Configuração do banco de dados XUI"""
    host: str
    port: int
    user: str
    password: str
    database: str
    use_ssh: bool = False
    ssh_host: Optional[str] = None
    ssh_port: int = 22
    ssh_user: Optional[str] = None
    ssh_password: Optional[str] = None
    ssh_key_path: Optional[str] = None

@dataclass
class SyncConfig:
    """Configuração de sincronização"""
    interval: int = 3600
    max_concurrent: int = 3
    retry_attempts: int = 3
    retry_delay: int = 300
    vod_extensions: list = None
    
    def __post_init__(self):
        if self.vod_extensions is None:
            self.vod_extensions = ['.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv']

@dataclass
class StorageConfig:
    """Configuração de armazenamento"""
    local_path: str
    remote_path: Optional[str] = None
    max_size_gb: int = 1000
    cleanup_threshold: int = 80  # porcentagem
    backup_enabled: bool = True
    backup_path: str = "/opt/vod-sync-xui/backups"

@dataclass
class SecurityConfig:
    """Configuração de segurança"""
    secret_key: str
    admin_user: str = "admin"
    admin_password: Optional[str] = None
    session_timeout: int = 3600
    api_rate_limit: int = 100
    ssl_enabled: bool = False
    ssl_cert: Optional[str] = None
    ssl_key: Optional[str] = None

@dataclass
class MonitoringConfig:
    """Configuração de monitoramento"""
    enabled: bool = True
    metrics_port: int = 9090
    alert_email: Optional[str] = None
    cpu_threshold: float = 80.0
    memory_threshold: float = 85.0
    disk_threshold: float = 90.0

@dataclass
class NotificationConfig:
    """Configuração de notificações"""
    email_enabled: bool = False
    email_server: Optional[str] = None
    email_port: int = 587
    email_user: Optional[str] = None
    email_password: Optional[str] = None
    email_from: Optional[str] = None
    email_to: Optional[str] = None
    
    telegram_enabled: bool = False
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None

class Config:
    """Classe principal de configuração"""
    
    def __init__(self, config_path: str = None):
        self.config_path = config_path or "/opt/vod-sync-xui/config/config.yaml"
        self._config_data = self._load_config()
        self._setup_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """Carregar configuração do arquivo YAML"""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f) or {}
        except FileNotFoundError:
            return self._create_default_config()
    
    def _create_default_config(self) -> Dict[str, Any]:
        """Criar configuração padrão"""
        default_config = {
            'database': {
                'host': os.getenv('XUI_DB_HOST', 'localhost'),
                'port': int(os.getenv('XUI_DB_PORT', 3306)),
                'user': os.getenv('XUI_DB_USER', 'root'),
                'password': os.getenv('XUI_DB_PASSWORD', ''),
                'database': os.getenv('XUI_DB_NAME', 'xui'),
                'use_ssh': False
            },
            'sync': {
                'interval': 3600,
                'max_concurrent': 3,
                'retry_attempts': 3
            },
            'storage': {
                'local_path': '/opt/vod-sync-xui/data/vods',
                'max_size_gb': 1000
            },
            'security': {
                'secret_key': os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production'),
                'admin_user': 'admin'
            },
            'monitoring': {
                'enabled': True,
                'metrics_port': 9090
            }
        }
        
        # Salvar configuração padrão
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
        with open(self.config_path, 'w') as f:
            yaml.dump(default_config, f, default_flow_style=False)
        
        return default_config
    
    def _setup_config(self):
        """Configurar objetos de configuração"""
        db_config = self._config_data.get('database', {})
        sync_config = self._config_data.get('sync', {})
        storage_config = self._config_data.get('storage', {})
        security_config = self._config_data.get('security', {})
        monitoring_config = self._config_data.get('monitoring', {})
        notification_config = self._config_data.get('notification', {})
        
        self.database = DatabaseConfig(**db_config)
        self.sync = SyncConfig(**sync_config)
        self.storage = StorageConfig(**storage_config)
        self.security = SecurityConfig(**security_config)
        self.monitoring = MonitoringConfig(**monitoring_config)
        self.notification = NotificationConfig(**notification_config)
    
    def update_config(self, section: str, values: Dict[str, Any]):
        """Atualizar configuração"""
        if section in self._config_data:
            self._config_data[section].update(values)
        else:
            self._config_data[section] = values
        
        # Salvar no arquivo
        with open(self.config_path, 'w') as f:
            yaml.dump(self._config_data, f, default_flow_style=False)
        
        # Recarregar configuração
        self._setup_config()
    
    @property
    def flask_config(self) -> Dict[str, Any]:
        """Configuração para Flask"""
        return {
            'SECRET_KEY': self.security.secret_key,
            'SESSION_TYPE': 'filesystem',
            'SESSION_FILE_DIR': '/opt/vod-sync-xui/data/sessions',
            'SESSION_PERMANENT': False,
            'SESSION_USE_SIGNER': True,
            'SESSION_COOKIE_SECURE': self.security.ssl_enabled,
            'SESSION_COOKIE_HTTPONLY': True,
            'SESSION_COOKIE_SAMESITE': 'Lax',
            'PERMANENT_SESSION_LIFETIME': self.security.session_timeout,
            'MAX_CONTENT_LENGTH': 100 * 1024 * 1024,  # 100MB
            'SQLALCHEMY_DATABASE_URI': f"sqlite:////opt/vod-sync-xui/data/vod_sync.db",
            'SQLALCHEMY_TRACK_MODIFICATIONS': False,
            'CELERY_BROKER_URL': 'redis://localhost:6379/0',
            'CELERY_RESULT_BACKEND': 'redis://localhost:6379/0'
        }

# Instância global de configuração
config = Config()
