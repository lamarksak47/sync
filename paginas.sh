#!/bin/bash

# ============================================
# COMPLETAR SISTEMA VOD SYNC - PÁGINAS FALTANTES
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretórios
BASE_DIR="/opt/vod-sync"
FRONTEND_DIR="$BASE_DIR/frontend"
BACKEND_DIR="$BASE_DIR/backend"

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

# ==================== CRIAR PÁGINAS FALTANTES ====================
create_missing_pages() {
    log "Criando páginas faltantes do sistema..."
    
    # ==================== CONEXÕES XUI ====================
    log "Criando página de conexões XUI..."
    
    cat > "$FRONTEND_DIR/public/xui.php" << 'XUI_PAGE'
<?php
session_start();
require_once 'auth_check.php';

$page_title = "Conexões XUI";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .connection-card {
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            transition: all 0.3s;
        }
        .connection-card:hover {
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transform: translateY(-2px);
        }
        .connection-active {
            border-left: 4px solid #28a745;
        }
        .connection-inactive {
            border-left: 4px solid #dc3545;
        }
        .status-badge {
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }
        .status-online {
            background-color: #d4edda;
            color: #155724;
        }
        .status-offline {
            background-color: #f8d7da;
            color: #721c24;
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Conexões XUI</li>
                    </ol>
                </nav>
                
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <h5 class="mb-0">
                            <i class="fas fa-server me-2"></i>Conexões XUI One
                        </h5>
                        <button class="btn btn-primary btn-sm" data-bs-toggle="modal" data-bs-target="#addXuiModal">
                            <i class="fas fa-plus me-1"></i>Nova Conexão
                        </button>
                    </div>
                    
                    <div class="card-body">
                        <?php if(isset($_GET['success'])): ?>
                        <div class="alert alert-success alert-dismissible fade show" role="alert">
                            Conexão adicionada com sucesso!
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <?php if(isset($_GET['error'])): ?>
                        <div class="alert alert-danger alert-dismissible fade show" role="alert">
                            Erro ao adicionar conexão!
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <!-- Lista de Conexões -->
                        <div class="row" id="connectionsList">
                            <!-- Conexões serão carregadas via AJAX -->
                            <div class="col-12 text-center py-5">
                                <div class="spinner-border text-primary" role="status">
                                    <span class="visually-hidden">Carregando...</span>
                                </div>
                                <p class="mt-2">Carregando conexões...</p>
                            </div>
                        </div>
                        
                        <!-- Tabela para Desktop -->
                        <div class="table-responsive d-none d-md-block">
                            <table class="table table-hover" id="xuiTable">
                                <thead>
                                    <tr>
                                        <th>Nome</th>
                                        <th>Host</th>
                                        <th>Porta</th>
                                        <th>Usuário</th>
                                        <th>Status</th>
                                        <th>Última Sinc.</th>
                                        <th>Ações</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <!-- Dados carregados via JavaScript -->
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
                
                <!-- Card de Status do XUI -->
                <div class="row mt-4">
                    <div class="col-md-4">
                        <div class="card">
                            <div class="card-body text-center">
                                <h1 class="display-4">0</h1>
                                <p class="text-muted">Conexões Ativas</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card">
                            <div class="card-body text-center">
                                <h1 class="display-4">0</h1>
                                <p class="text-muted">Usuários XUI</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card">
                            <div class="card-body text-center">
                                <h1 class="display-4">0</h1>
                                <p class="text-muted">Canais</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Modal Adicionar Conexão XUI -->
    <div class="modal fade" id="addXuiModal" tabindex="-1">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Nova Conexão XUI</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form id="addXuiForm" action="/api/xui/add.php" method="POST">
                    <div class="modal-body">
                        <div class="mb-3">
                            <label class="form-label">Nome da Conexão *</label>
                            <input type="text" class="form-control" name="alias" required 
                                   placeholder="Ex: XUI Principal">
                        </div>
                        
                        <div class="row">
                            <div class="col-md-8">
                                <div class="mb-3">
                                    <label class="form-label">Host/IP *</label>
                                    <input type="text" class="form-control" name="host" required 
                                           placeholder="Ex: 192.168.1.100 ou dominio.com">
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="mb-3">
                                    <label class="form-label">Porta *</label>
                                    <input type="number" class="form-control" name="port" required 
                                           value="3306" placeholder="3306">
                                </div>
                            </div>
                        </div>
                        
                        <div class="row">
                            <div class="col-md-6">
                                <div class="mb-3">
                                    <label class="form-label">Usuário *</label>
                                    <input type="text" class="form-control" name="username" required 
                                           placeholder="usuário_xui">
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="mb-3">
                                    <label class="form-label">Senha *</label>
                                    <div class="input-group">
                                        <input type="password" class="form-control" name="password" required 
                                               placeholder="••••••••">
                                        <button class="btn btn-outline-secondary" type="button" id="toggleXuiPassword">
                                            <i class="fas fa-eye"></i>
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Banco de Dados</label>
                            <input type="text" class="form-control" name="database" 
                                   value="xui" placeholder="xui">
                        </div>
                        
                        <div class="form-check mb-3">
                            <input class="form-check-input" type="checkbox" name="is_active" id="isActive" checked>
                            <label class="form-check-label" for="isActive">
                                Conexão ativa
                            </label>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-save me-1"></i>Salvar Conexão
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Mostrar/ocultar senha
        $('#toggleXuiPassword').click(function() {
            const input = $('input[name="password"]');
            const type = input.attr('type') === 'password' ? 'text' : 'password';
            input.attr('type', type);
            $(this).html(type === 'password' ? '<i class="fas fa-eye"></i>' : '<i class="fas fa-eye-slash"></i>');
        });
        
        // Carregar conexões
        loadXuiConnections();
        
        // Formulário de adicionar conexão
        $('#addXuiForm').submit(function(e) {
            e.preventDefault();
            
            const formData = $(this).serialize();
            
            $.ajax({
                url: '/api/xui/add.php',
                method: 'POST',
                data: formData,
                success: function(response) {
                    if(response.success) {
                        $('#addXuiModal').modal('hide');
                        loadXuiConnections();
                        window.location.href = '/xui.php?success=1';
                    } else {
                        alert('Erro: ' + response.message);
                    }
                },
                error: function() {
                    alert('Erro ao conectar com o servidor');
                }
            });
        });
    });
    
    function loadXuiConnections() {
        $.ajax({
            url: '/api/xui/list.php',
            method: 'GET',
            success: function(response) {
                if(response.success && response.data) {
                    updateConnectionsUI(response.data);
                } else {
                    $('#connectionsList').html('<div class="alert alert-warning">Nenhuma conexão configurada</div>');
                }
            },
            error: function() {
                $('#connectionsList').html('<div class="alert alert-danger">Erro ao carregar conexões</div>');
            }
        });
    }
    
    function updateConnectionsUI(connections) {
        let html = '';
        
        if(connections.length === 0) {
            html = '<div class="col-12"><div class="alert alert-info">Nenhuma conexão XUI configurada. Clique em "Nova Conexão" para começar.</div></div>';
        } else {
            connections.forEach(conn => {
                const statusClass = conn.is_active ? 'connection-active' : 'connection-inactive';
                const statusBadge = conn.is_active ? 
                    '<span class="status-badge status-online">Ativa</span>' : 
                    '<span class="status-badge status-offline">Inativa</span>';
                
                html += `
                <div class="col-md-6">
                    <div class="connection-card ${statusClass}">
                        <div class="d-flex justify-content-between align-items-start">
                            <div>
                                <h6 class="mb-1">${conn.alias}</h6>
                                <small class="text-muted">${conn.host}:${conn.port}</small>
                            </div>
                            ${statusBadge}
                        </div>
                        <div class="mt-3">
                            <small><i class="fas fa-user me-1"></i> ${conn.username}</small>
                            <div class="mt-2">
                                <button class="btn btn-sm btn-outline-primary" onclick="testConnection(${conn.id})">
                                    <i class="fas fa-plug me-1"></i>Testar
                                </button>
                                <button class="btn btn-sm btn-outline-success" onclick="syncXui(${conn.id})">
                                    <i class="fas fa-sync me-1"></i>Sincronizar
                                </button>
                                <button class="btn btn-sm btn-outline-danger" onclick="deleteConnection(${conn.id})">
                                    <i class="fas fa-trash me-1"></i>Remover
                                </button>
                            </div>
                        </div>
                    </div>
                </div>`;
            });
        }
        
        $('#connectionsList').html(html);
    }
    
    function testConnection(id) {
        $.ajax({
            url: '/api/xui/test.php?id=' + id,
            method: 'GET',
            success: function(response) {
                if(response.success) {
                    alert('✅ Conexão testada com sucesso!');
                } else {
                    alert('❌ Falha na conexão: ' + response.message);
                }
            }
        });
    }
    
    function syncXui(id) {
        if(confirm('Iniciar sincronização com esta conexão XUI?')) {
            window.location.href = '/sync.php?xui_id=' + id;
        }
    }
    
    function deleteConnection(id) {
        if(confirm('Tem certeza que deseja remover esta conexão?')) {
            $.ajax({
                url: '/api/xui/delete.php',
                method: 'POST',
                data: { id: id },
                success: function(response) {
                    if(response.success) {
                        loadXuiConnections();
                        alert('Conexão removida com sucesso!');
                    } else {
                        alert('Erro: ' + response.message);
                    }
                }
            });
        }
    }
    </script>
</body>
</html>
XUI_PAGE

    success "✅ Página XUI criada"
    
    # ==================== LISTAS M3U ====================
    log "Criando página de listas M3U..."
    
    cat > "$FRONTEND_DIR/public/m3u.php" << 'M3U_PAGE'
<?php
session_start();
require_once 'auth_check.php';

$page_title = "Listas M3U";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .m3u-card {
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            background: #f8f9fa;
        }
        .m3u-stats {
            background: white;
            border-radius: 8px;
            padding: 10px;
            margin-bottom: 15px;
            border: 1px solid #e9ecef;
        }
        .progress {
            height: 8px;
        }
        .upload-area {
            border: 2px dashed #6c757d;
            border-radius: 8px;
            padding: 40px 20px;
            text-align: center;
            background: #f8f9fa;
            cursor: pointer;
            transition: all 0.3s;
        }
        .upload-area:hover {
            border-color: #0d6efd;
            background: #e7f1ff;
        }
        .upload-area.dragover {
            border-color: #0d6efd;
            background: #cfe2ff;
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Listas M3U</li>
                    </ol>
                </nav>
                
                <!-- Cards de Estatísticas -->
                <div class="row mb-4">
                    <div class="col-md-3">
                        <div class="m3u-stats">
                            <h6 class="text-muted">Listas M3U</h6>
                            <h3 id="totalLists">0</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="m3u-stats">
                            <h6 class="text-muted">Canais</h6>
                            <h3 id="totalChannels">0</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="m3u-stats">
                            <h6 class="text-muted">Filmes</h6>
                            <h3 id="totalMovies">0</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="m3u-stats">
                            <h6 class="text-muted">Séries</h6>
                            <h3 id="totalSeries">0</h3>
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <h5 class="mb-0">
                            <i class="fas fa-list me-2"></i>Listas M3U
                        </h5>
                        <div>
                            <button class="btn btn-primary btn-sm" data-bs-toggle="modal" data-bs-target="#uploadM3uModal">
                                <i class="fas fa-upload me-1"></i>Upload M3U
                            </button>
                            <button class="btn btn-success btn-sm" data-bs-toggle="modal" data-bs-target="#addUrlM3uModal">
                                <i class="fas fa-link me-1"></i>URL M3U
                            </button>
                        </div>
                    </div>
                    
                    <div class="card-body">
                        <?php if(isset($_GET['success'])): ?>
                        <div class="alert alert-success alert-dismissible fade show" role="alert">
                            Lista M3U processada com sucesso!
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <!-- Lista de M3Us -->
                        <div class="table-responsive">
                            <table class="table table-hover" id="m3uTable">
                                <thead>
                                    <tr>
                                        <th>Nome</th>
                                        <th>Tipo</th>
                                        <th>Canais</th>
                                        <th>Filmes</th>
                                        <th>Séries</th>
                                        <th>Última Atualização</th>
                                        <th>Status</th>
                                        <th>Ações</th>
                                    </tr>
                                </thead>
                                <tbody id="m3uTableBody">
                                    <!-- Carregado via JavaScript -->
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Modal Upload M3U -->
    <div class="modal fade" id="uploadM3uModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Upload de Lista M3U</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form id="uploadM3uForm" enctype="multipart/form-data">
                    <div class="modal-body">
                        <div class="mb-3">
                            <label class="form-label">Nome da Lista *</label>
                            <input type="text" class="form-control" name="name" required 
                                   placeholder="Ex: Lista Premium">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Arquivo M3U *</label>
                            <div class="upload-area" id="dropArea">
                                <i class="fas fa-cloud-upload-alt fa-3x text-muted mb-3"></i>
                                <h5>Arraste e solte seu arquivo M3U aqui</h5>
                                <p class="text-muted">ou clique para selecionar</p>
                                <input type="file" class="d-none" id="m3uFile" name="m3u_file" accept=".m3u,.m3u8,.txt">
                                <div class="mt-3" id="fileInfo"></div>
                            </div>
                            <small class="text-muted">Tamanho máximo: 50MB. Formatos: .m3u, .m3u8, .txt</small>
                        </div>
                        
                        <div class="row">
                            <div class="col-md-6">
                                <div class="mb-3">
                                    <label class="form-label">Categoria</label>
                                    <select class="form-select" name="category">
                                        <option value="tv">TV</option>
                                        <option value="movies">Filmes</option>
                                        <option value="series">Séries</option>
                                        <option value="mixed">Misto</option>
                                    </select>
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="mb-3">
                                    <label class="form-label">Atualização Automática</label>
                                    <select class="form-select" name="auto_update">
                                        <option value="none">Nenhuma</option>
                                        <option value="daily">Diária</option>
                                        <option value="weekly">Semanal</option>
                                        <option value="monthly">Mensal</option>
                                    </select>
                                </div>
                            </div>
                        </div>
                        
                        <div class="form-check mb-3">
                            <input class="form-check-input" type="checkbox" name="is_active" id="m3uActive" checked>
                            <label class="form-check-label" for="m3uActive">
                                Lista ativa
                            </label>
                        </div>
                        
                        <div class="progress d-none" id="uploadProgress">
                            <div class="progress-bar" role="progressbar" style="width: 0%"></div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-primary" id="uploadBtn">
                            <i class="fas fa-upload me-1"></i>Upload e Processar
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <!-- Modal URL M3U -->
    <div class="modal fade" id="addUrlM3uModal" tabindex="-1">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Adicionar Lista M3U por URL</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form id="urlM3uForm">
                    <div class="modal-body">
                        <div class="mb-3">
                            <label class="form-label">Nome da Lista *</label>
                            <input type="text" class="form-control" name="name" required 
                                   placeholder="Ex: Lista Premium">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">URL M3U *</label>
                            <input type="url" class="form-control" name="url" required 
                                   placeholder="https://exemplo.com/lista.m3u">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Usuário (se necessário)</label>
                            <input type="text" class="form-control" name="username" 
                                   placeholder="usuário">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Senha (se necessário)</label>
                            <input type="password" class="form-control" name="password" 
                                   placeholder="••••••••">
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-link me-1"></i>Adicionar URL
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Inicializar DataTable
        $('#m3uTable').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.11.5/i18n/pt-BR.json'
            }
        });
        
        // Carregar listas M3U
        loadM3ULists();
        
        // Drag and drop para upload
        const dropArea = document.getElementById('dropArea');
        const fileInput = document.getElementById('m3uFile');
        
        dropArea.addEventListener('click', () => fileInput.click());
        
        fileInput.addEventListener('change', function(e) {
            handleFiles(this.files);
        });
        
        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
            dropArea.addEventListener(eventName, preventDefaults, false);
        });
        
        function preventDefaults(e) {
            e.preventDefault();
            e.stopPropagation();
        }
        
        ['dragenter', 'dragover'].forEach(eventName => {
            dropArea.addEventListener(eventName, highlight, false);
        });
        
        ['dragleave', 'drop'].forEach(eventName => {
            dropArea.addEventListener(eventName, unhighlight, false);
        });
        
        function highlight() {
            dropArea.classList.add('dragover');
        }
        
        function unhighlight() {
            dropArea.classList.remove('dragover');
        }
        
        dropArea.addEventListener('drop', handleDrop, false);
        
        function handleDrop(e) {
            const dt = e.dataTransfer;
            const files = dt.files;
            handleFiles(files);
        }
        
        function handleFiles(files) {
            if (files.length > 0) {
                const file = files[0];
                if (file.type === 'application/octet-stream' || 
                    file.name.endsWith('.m3u') || 
                    file.name.endsWith('.m3u8') || 
                    file.name.endsWith('.txt')) {
                    
                    $('#fileInfo').html(`
                        <div class="alert alert-success">
                            <i class="fas fa-file me-2"></i>
                            <strong>${file.name}</strong> (${formatBytes(file.size)})
                        </div>
                    `);
                    fileInput.files = files;
                } else {
                    $('#fileInfo').html(`
                        <div class="alert alert-danger">
                            <i class="fas fa-exclamation-circle me-2"></i>
                            Formato inválido. Use .m3u, .m3u8 ou .txt
                        </div>
                    `);
                }
            }
        }
        
        function formatBytes(bytes, decimals = 2) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const dm = decimals < 0 ? 0 : decimals;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
        }
        
        // Formulário de upload
        $('#uploadM3uForm').submit(function(e) {
            e.preventDefault();
            
            const formData = new FormData(this);
            
            $('#uploadProgress').removeClass('d-none');
            $('#uploadBtn').prop('disabled', true);
            
            $.ajax({
                url: '/api/m3u/upload.php',
                method: 'POST',
                data: formData,
                contentType: false,
                processData: false,
                xhr: function() {
                    const xhr = new XMLHttpRequest();
                    xhr.upload.addEventListener('progress', function(e) {
                        if (e.lengthComputable) {
                            const percentComplete = (e.loaded / e.total) * 100;
                            $('#uploadProgress .progress-bar').css('width', percentComplete + '%');
                        }
                    }, false);
                    return xhr;
                },
                success: function(response) {
                    if(response.success) {
                        $('#uploadM3uModal').modal('hide');
                        $('#uploadM3uForm')[0].reset();
                        $('#fileInfo').empty();
                        loadM3ULists();
                        window.location.href = '/m3u.php?success=1';
                    } else {
                        alert('Erro: ' + response.message);
                    }
                },
                error: function() {
                    alert('Erro ao conectar com o servidor');
                },
                complete: function() {
                    $('#uploadProgress').addClass('d-none');
                    $('#uploadBtn').prop('disabled', false);
                }
            });
        });
        
        // Formulário URL
        $('#urlM3uForm').submit(function(e) {
            e.preventDefault();
            
            const formData = $(this).serialize();
            
            $.ajax({
                url: '/api/m3u/url.php',
                method: 'POST',
                data: formData,
                success: function(response) {
                    if(response.success) {
                        $('#addUrlM3uModal').modal('hide');
                        loadM3ULists();
                        window.location.href = '/m3u.php?success=1';
                    } else {
                        alert('Erro: ' + response.message);
                    }
                }
            });
        });
    });
    
    function loadM3ULists() {
        $.ajax({
            url: '/api/m3u/list.php',
            method: 'GET',
            success: function(response) {
                if(response.success && response.data) {
                    updateM3UTable(response.data);
                    updateStats(response.stats || {});
                }
            }
        });
    }
    
    function updateM3UTable(lists) {
        const tbody = $('#m3uTableBody');
        tbody.empty();
        
        if(lists.length === 0) {
            tbody.html(`
                <tr>
                    <td colspan="8" class="text-center">
                        <div class="alert alert-info">
                            Nenhuma lista M3U encontrada. Adicione sua primeira lista!
                        </div>
                    </td>
                </tr>
            `);
            return;
        }
        
        lists.forEach(list => {
            const statusBadge = list.is_active ? 
                '<span class="badge bg-success">Ativa</span>' : 
                '<span class="badge bg-secondary">Inativa</span>';
            
            const row = `
                <tr>
                    <td>
                        <strong>${list.name}</strong><br>
                        <small class="text-muted">${list.source_type === 'file' ? 'Arquivo' : 'URL'}</small>
                    </td>
                    <td>${list.category || 'TV'}</td>
                    <td><span class="badge bg-info">${list.channel_count || 0}</span></td>
                    <td><span class="badge bg-primary">${list.movie_count || 0}</span></td>
                    <td><span class="badge bg-warning">${list.series_count || 0}</span></td>
                    <td>${list.last_updated || 'Nunca'}</td>
                    <td>${statusBadge}</td>
                    <td>
                        <button class="btn btn-sm btn-outline-primary" onclick="viewM3U(${list.id})" title="Visualizar">
                            <i class="fas fa-eye"></i>
                        </button>
                        <button class="btn btn-sm btn-outline-success" onclick="processM3U(${list.id})" title="Processar">
                            <i class="fas fa-cogs"></i>
                        </button>
                        <button class="btn btn-sm btn-outline-danger" onclick="deleteM3U(${list.id})" title="Excluir">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>
                </tr>
            `;
            
            tbody.append(row);
        });
    }
    
    function updateStats(stats) {
        $('#totalLists').text(stats.total_lists || 0);
        $('#totalChannels').text(stats.total_channels || 0);
        $('#totalMovies').text(stats.total_movies || 0);
        $('#totalSeries').text(stats.total_series || 0);
    }
    
    function viewM3U(id) {
        window.open(`/api/m3u/view.php?id=${id}`, '_blank');
    }
    
    function processM3U(id) {
        if(confirm('Processar esta lista M3U agora?')) {
            $.ajax({
                url: '/api/m3u/process.php',
                method: 'POST',
                data: { id: id },
                success: function(response) {
                    if(response.success) {
                        alert('✅ Lista processada com sucesso!');
                        loadM3ULists();
                    } else {
                        alert('❌ Erro: ' + response.message);
                    }
                }
            });
        }
    }
    
    function deleteM3U(id) {
        if(confirm('Tem certeza que deseja excluir esta lista M3U?')) {
            $.ajax({
                url: '/api/m3u/delete.php',
                method: 'POST',
                data: { id: id },
                success: function(response) {
                    if(response.success) {
                        alert('Lista excluída com sucesso!');
                        loadM3ULists();
                    } else {
                        alert('Erro: ' + response.message);
                    }
                }
            });
        }
    }
    </script>
</body>
</html>
M3U_PAGE

    success "✅ Página M3U criada"
    
    # ==================== SINCRONIZAÇÃO ====================
    log "Criando página de sincronização..."
    
    cat > "$FRONTEND_DIR/public/sync.php" << 'SYNC_PAGE'
<?php
session_start();
require_once 'auth_check.php';

// Verificar se tem conexões XUI configuradas
$xui_id = isset($_GET['xui_id']) ? intval($_GET['xui_id']) : 0;
$m3u_id = isset($_GET['m3u_id']) ? intval($_GET['m3u_id']) : 0;

$page_title = "Sincronização";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        .sync-step {
            border: 2px solid #dee2e6;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            background: white;
            transition: all 0.3s;
        }
        .sync-step.active {
            border-color: #0d6efd;
            background: #f0f8ff;
        }
        .sync-step.completed {
            border-color: #198754;
            background: #f0fff4;
        }
        .sync-step.failed {
            border-color: #dc3545;
            background: #fff0f0;
        }
        .step-icon {
            width: 50px;
            height: 50px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
            margin-right: 15px;
        }
        .step-1 { background: #e7f1ff; color: #0d6efd; }
        .step-2 { background: #fff3cd; color: #ffc107; }
        .step-3 { background: #d1ecf1; color: #17a2b8; }
        .step-4 { background: #d4edda; color: #198754; }
        .log-container {
            max-height: 400px;
            overflow-y: auto;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            background: #f8f9fa;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
        .log-entry {
            padding: 5px 0;
            border-bottom: 1px solid #eee;
        }
        .log-success { color: #198754; }
        .log-error { color: #dc3545; }
        .log-warning { color: #ffc107; }
        .log-info { color: #0d6efd; }
        .progress-bar-animated {
            animation: progress-bar-stripes 1s linear infinite;
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Sincronização</li>
                    </ol>
                </nav>
                
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0">
                            <i class="fas fa-sync me-2"></i>Sincronização XUI + M3U
                        </h5>
                    </div>
                    
                    <div class="card-body">
                        <?php if(isset($_GET['success'])): ?>
                        <div class="alert alert-success alert-dismissible fade show" role="alert">
                            Sincronização concluída com sucesso!
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                        <?php endif; ?>
                        
                        <!-- Configuração da Sincronização -->
                        <div class="row mb-4">
                            <div class="col-md-6">
                                <div class="card">
                                    <div class="card-header">
                                        <h6 class="mb-0">Configuração</h6>
                                    </div>
                                    <div class="card-body">
                                        <form id="syncConfigForm">
                                            <div class="mb-3">
                                                <label class="form-label">Conexão XUI *</label>
                                                <select class="form-select" name="xui_id" id="xuiSelect" required>
                                                    <option value="">Selecione uma conexão...</option>
                                                    <!-- Carregado via JavaScript -->
                                                </select>
                                            </div>
                                            
                                            <div class="mb-3">
                                                <label class="form-label">Lista M3U *</label>
                                                <select class="form-select" name="m3u_id" id="m3uSelect" required>
                                                    <option value="">Selecione uma lista...</option>
                                                    <!-- Carregado via JavaScript -->
                                                </select>
                                            </div>
                                            
                                            <div class="mb-3">
                                                <label class="form-label">Tipo de Conteúdo</label>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="sync_movies" id="syncMovies" checked>
                                                    <label class="form-check-label" for="syncMovies">
                                                        Filmes
                                                    </label>
                                                </div>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="sync_series" id="syncSeries" checked>
                                                    <label class="form-check-label" for="syncSeries">
                                                        Séries
                                                    </label>
                                                </div>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="sync_live" id="syncLive" checked>
                                                    <label class="form-check-label" for="syncLive">
                                                        Canais ao Vivo
                                                    </label>
                                                </div>
                                            </div>
                                            
                                            <div class="mb-3">
                                                <label class="form-label">Opções</label>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="enrich_tmdb" id="enrichTmdb" checked>
                                                    <label class="form-check-label" for="enrichTmdb">
                                                        Enriquecer com TMDb
                                                    </label>
                                                </div>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="replace_images" id="replaceImages" checked>
                                                    <label class="form-check-label" for="replaceImages">
                                                        Substituir imagens
                                                    </label>
                                                </div>
                                                <div class="form-check">
                                                    <input class="form-check-input" type="checkbox" name="force_sync" id="forceSync">
                                                    <label class="form-check-label" for="forceSync">
                                                        Sincronização forçada
                                                    </label>
                                                </div>
                                            </div>
                                            
                                            <div class="d-grid">
                                                <button type="submit" class="btn btn-primary btn-lg" id="startSyncBtn">
                                                    <i class="fas fa-play me-1"></i>Iniciar Sincronização
                                                </button>
                                            </div>
                                        </form>
                                    </div>
                                </div>
                            </div>
                            
                            <div class="col-md-6">
                                <div class="card">
                                    <div class="card-header">
                                        <h6 class="mb-0">Status da Sincronização</h6>
                                    </div>
                                    <div class="card-body">
                                        <!-- Progresso -->
                                        <div class="mb-3">
                                            <div class="d-flex justify-content-between mb-1">
                                                <span>Progresso</span>
                                                <span id="progressPercent">0%</span>
                                            </div>
                                            <div class="progress" style="height: 20px;">
                                                <div class="progress-bar" id="syncProgressBar" role="progressbar" 
                                                     style="width: 0%"></div>
                                            </div>
                                        </div>
                                        
                                        <!-- Passos da Sincronização -->
                                        <div id="syncSteps">
                                            <div class="sync-step" id="step1">
                                                <div class="d-flex align-items-center">
                                                    <div class="step-icon step-1">
                                                        <i class="fas fa-database"></i>
                                                    </div>
                                                    <div>
                                                        <h6 class="mb-1">1. Conexão com XUI</h6>
                                                        <small class="text-muted" id="step1Status">Aguardando...</small>
                                                    </div>
                                                </div>
                                            </div>
                                            
                                            <div class="sync-step" id="step2">
                                                <div class="d-flex align-items-center">
                                                    <div class="step-icon step-2">
                                                        <i class="fas fa-list"></i>
                                                    </div>
                                                    <div>
                                                        <h6 class="mb-1">2. Processar M3U</h6>
                                                        <small class="text-muted" id="step2Status">Aguardando...</small>
                                                    </div>
                                                </div>
                                            </div>
                                            
                                            <div class="sync-step" id="step3">
                                                <div class="d-flex align-items-center">
                                                    <div class="step-icon step-3">
                                                        <i class="fas fa-film"></i>
                                                    </div>
                                                    <div>
                                                        <h6 class="mb-1">3. Enriquecer com TMDb</h6>
                                                        <small class="text-muted" id="step3Status">Aguardando...</small>
                                                    </div>
                                                </div>
                                            </div>
                                            
                                            <div class="sync-step" id="step4">
                                                <div class="d-flex align-items-center">
                                                    <div class="step-icon step-4">
                                                        <i class="fas fa-check-circle"></i>
                                                    </div>
                                                    <div>
                                                        <h6 class="mb-1">4. Finalizar</h6>
                                                        <small class="text-muted" id="step4Status">Aguardando...</small>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Logs em Tempo Real -->
                        <div class="card">
                            <div class="card-header d-flex justify-content-between align-items-center">
                                <h6 class="mb-0">Logs da Sincronização</h6>
                                <button class="btn btn-sm btn-outline-secondary" onclick="clearLogs()">
                                    <i class="fas fa-trash me-1"></i>Limpar Logs
                                </button>
                            </div>
                            <div class="card-body">
                                <div class="log-container" id="logContainer">
                                    <div class="log-entry log-info">
                                        <i class="fas fa-info-circle me-1"></i>
                                        Sistema de sincronização pronto. Selecione as configurações e clique em "Iniciar Sincronização".
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Resumo da Sincronização -->
                        <div class="row mt-4 d-none" id="syncSummary">
                            <div class="col-md-12">
                                <div class="card">
                                    <div class="card-header">
                                        <h6 class="mb-0">Resumo da Sincronização</h6>
                                    </div>
                                    <div class="card-body">
                                        <div class="row" id="summaryStats">
                                            <!-- Preenchido via JavaScript -->
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Carregar conexões XUI e listas M3U
        loadXuiConnections();
        loadM3ULists();
        
        // Preencher seletores se IDs foram passados via URL
        const urlParams = new URLSearchParams(window.location.search);
        const xuiId = urlParams.get('xui_id');
        const m3uId = urlParams.get('m3u_id');
        
        if(xuiId) {
            setTimeout(() => $('#xuiSelect').val(xuiId), 500);
        }
        
        if(m3uId) {
            setTimeout(() => $('#m3uSelect').val(m3uId), 500);
        }
        
        // Formulário de sincronização
        $('#syncConfigForm').submit(function(e) {
            e.preventDefault();
            
            const xuiId = $('#xuiSelect').val();
            const m3uId = $('#m3uSelect').val();
            
            if(!xuiId || !m3uId) {
                alert('Selecione uma conexão XUI e uma lista M3U');
                return;
            }
            
            if(confirm('Iniciar sincronização? Isso pode levar alguns minutos.')) {
                startSync($(this).serialize());
            }
        });
    });
    
    function loadXuiConnections() {
        $.ajax({
            url: '/api/xui/list.php',
            method: 'GET',
            success: function(response) {
                if(response.success && response.data) {
                    const select = $('#xuiSelect');
                    select.empty();
                    select.append('<option value="">Selecione uma conexão...</option>');
                    
                    response.data.forEach(conn => {
                        if(conn.is_active) {
                            select.append(`<option value="${conn.id}">${conn.alias} (${conn.host})</option>`);
                        }
                    });
                }
            }
        });
    }
    
    function loadM3ULists() {
        $.ajax({
            url: '/api/m3u/list.php',
            method: 'GET',
            success: function(response) {
                if(response.success && response.data) {
                    const select = $('#m3uSelect');
                    select.empty();
                    select.append('<option value="">Selecione uma lista...</option>');
                    
                    response.data.forEach(list => {
                        if(list.is_active) {
                            select.append(`<option value="${list.id}">${list.name} (${list.channel_count || 0} itens)</option>`);
                        }
                    });
                }
            }
        });
    }
    
    function startSync(formData) {
        // Desabilitar botão
        $('#startSyncBtn').prop('disabled', true).html('<i class="fas fa-spinner fa-spin me-1"></i>Sincronizando...');
        
        // Resetar interface
        resetSyncUI();
        
        // Iniciar sincronização via AJAX
        $.ajax({
            url: '/api/sync/start.php',
            method: 'POST',
            data: formData,
            success: function(response) {
                if(response.success) {
                    addLog('✅ Sincronização iniciada com sucesso!', 'success');
                    monitorSync(response.sync_id);
                } else {
                    addLog('❌ Erro ao iniciar sincronização: ' + response.message, 'error');
                    $('#startSyncBtn').prop('disabled', false).html('<i class="fas fa-play me-1"></i>Iniciar Sincronização');
                }
            },
            error: function() {
                addLog('❌ Erro de conexão com o servidor', 'error');
                $('#startSyncBtn').prop('disabled', false).html('<i class="fas fa-play me-1"></i>Iniciar Sincronização');
            }
        });
    }
    
    function resetSyncUI() {
        // Resetar steps
        $('#step1, #step2, #step3, #step4').removeClass('active completed failed');
        $('#step1Status').text('Aguardando...');
        $('#step2Status').text('Aguardando...');
        $('#step3Status').text('Aguardando...');
        $('#step4Status').text('Aguardando...');
        
        // Resetar progresso
        $('#syncProgressBar').css('width', '0%').removeClass('progress-bar-animated');
        $('#progressPercent').text('0%');
        
        // Limpar logs
        $('#logContainer').html('');
        
        // Esconder resumo
        $('#syncSummary').addClass('d-none');
    }
    
    function monitorSync(syncId) {
        // Atualizar progresso periodicamente
        const checkInterval = setInterval(() => {
            $.ajax({
                url: '/api/sync/status.php?id=' + syncId,
                method: 'GET',
                success: function(response) {
                    if(response.success) {
                        updateSyncUI(response.data);
                        
                        // Verificar se terminou
                        if(response.data.status === 'completed' || response.data.status === 'failed') {
                            clearInterval(checkInterval);
                            $('#startSyncBtn').prop('disabled', false).html('<i class="fas fa-play me-1"></i>Iniciar Sincronização');
                            
                            // Mostrar resumo
                            if(response.data.status === 'completed') {
                                showSyncSummary(response.data.stats);
                            }
                        }
                    }
                }
            });
        }, 2000); // Verificar a cada 2 segundos
    }
    
    function updateSyncUI(syncData) {
        // Atualizar progresso
        const progress = syncData.progress || 0;
        $('#syncProgressBar').css('width', progress + '%');
        $('#progressPercent').text(progress + '%');
        
        if(progress < 100) {
            $('#syncProgressBar').addClass('progress-bar-animated');
        } else {
            $('#syncProgressBar').removeClass('progress-bar-animated');
        }
        
        // Atualizar steps
        updateStep(1, syncData.step_1);
        updateStep(2, syncData.step_2);
        updateStep(3, syncData.step_3);
        updateStep(4, syncData.step_4);
        
        // Atualizar logs
        if(syncData.logs && syncData.logs.length > 0) {
            syncData.logs.forEach(log => {
                addLog(log.message, log.type);
            });
        }
    }
    
    function updateStep(stepNumber, stepData) {
        const step = $('#step' + stepNumber);
        const status = $('#step' + stepNumber + 'Status');
        
        if(stepData) {
            step.removeClass('active completed failed');
            
            if(stepData.status === 'in_progress') {
                step.addClass('active');
                status.text(stepData.message || 'Em andamento...');
            } else if(stepData.status === 'completed') {
                step.addClass('completed');
                status.text(stepData.message || 'Concluído');
            } else if(stepData.status === 'failed') {
                step.addClass('failed');
                status.text(stepData.message || 'Falhou');
            }
        }
    }
    
    function addLog(message, type = 'info') {
        const logContainer = $('#logContainer');
        const timestamp = new Date().toLocaleTimeString();
        
        let icon = 'fa-info-circle';
        let className = 'log-info';
        
        switch(type) {
            case 'success':
                icon = 'fa-check-circle';
                className = 'log-success';
                break;
            case 'error':
                icon = 'fa-times-circle';
                className = 'log-error';
                break;
            case 'warning':
                icon = 'fa-exclamation-triangle';
                className = 'log-warning';
                break;
        }
        
        const logEntry = `
            <div class="log-entry ${className}">
                <i class="fas ${icon} me-1"></i>
                [${timestamp}] ${message}
            </div>
        `;
        
        logContainer.append(logEntry);
        logContainer.scrollTop(logContainer[0].scrollHeight);
    }
    
    function clearLogs() {
        $('#logContainer').html('');
        addLog('Logs limpos', 'info');
    }
    
    function showSyncSummary(stats) {
        const summaryHtml = `
            <div class="col-md-3">
                <div class="text-center">
                    <h3 class="text-success">${stats.total_items || 0}</h3>
                    <p class="text-muted">Itens Processados</p>
                </div>
            </div>
            <div class="col-md-3">
                <div class="text-center">
                    <h3 class="text-primary">${stats.movies_added || 0}</h3>
                    <p class="text-muted">Filmes Adicionados</p>
                </div>
            </div>
            <div class="col-md-3">
                <div class="text-center">
                    <h3 class="text-warning">${stats.series_added || 0}</h3>
                    <p class="text-muted">Séries Adicionadas</p>
                </div>
            </div>
            <div class="col-md-3">
                <div class="text-center">
                    <h3 class="text-info">${stats.channels_added || 0}</h3>
                    <p class="text-muted">Canais Adicionados</p>
                </div>
            </div>
        `;
        
        $('#summaryStats').html(summaryHtml);
        $('#syncSummary').removeClass('d-none');
    }
    </script>
</body>
</html>
SYNC_PAGE

    success "✅ Página de sincronização criada"
    
    # ==================== FILMES ====================
    log "Criando página de filmes..."
    
    cat > "$FRONTEND_DIR/public/movies.php" << 'MOVIES_PAGE'
<?php
session_start();
require_once 'auth_check.php';

$page_title = "Filmes";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .movie-card {
            border: 1px solid #dee2e6;
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 20px;
            transition: transform 0.3s;
            background: white;
        }
        .movie-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
        }
        .movie-poster {
            width: 100%;
            height: 300px;
            object-fit: cover;
        }
        .movie-info {
            padding: 15px;
        }
        .movie-title {
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 5px;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }
        .movie-year {
            color: #6c757d;
            font-size: 14px;
        }
        .movie-rating {
            color: #ffc107;
            font-size: 14px;
        }
        .badge-genre {
            background: #e9ecef;
            color: #495057;
            font-size: 12px;
            margin-right: 5px;
            margin-bottom: 5px;
        }
        .filter-sidebar {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .view-toggle {
            cursor: pointer;
            padding: 8px 15px;
            border: 1px solid #dee2e6;
            border-radius: 5px;
            display: inline-flex;
            align-items: center;
            margin-right: 10px;
        }
        .view-toggle.active {
            background: #0d6efd;
            color: white;
            border-color: #0d6efd;
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Filmes</li>
                    </ol>
                </nav>
                
                <!-- Filtros e Controles -->
                <div class="card mb-4">
                    <div class="card-body">
                        <div class="row">
                            <div class="col-md-6">
                                <div class="input-group">
                                    <span class="input-group-text">
                                        <i class="fas fa-search"></i>
                                    </span>
                                    <input type="text" class="form-control" id="searchMovies" 
                                           placeholder="Buscar filmes...">
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="d-flex justify-content-end">
                                    <div class="me-3">
                                        <span class="me-2">Visualização:</span>
                                        <span class="view-toggle active" id="viewGrid">
                                            <i class="fas fa-th-large me-1"></i>Grid
                                        </span>
                                        <span class="view-toggle" id="viewList">
                                            <i class="fas fa-list me-1"></i>Lista
                                        </span>
                                    </div>
                                    <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#filterModal">
                                        <i class="fas fa-filter me-1"></i>Filtros
                                    </button>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Filtros Rápidos -->
                        <div class="row mt-3">
                            <div class="col-md-12">
                                <div class="d-flex flex-wrap" id="quickFilters">
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2 active" data-filter="all">
                                        Todos
                                    </button>
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2" data-filter="recent">
                                        Recentes
                                    </button>
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2" data-filter="popular">
                                        Populares
                                    </button>
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2" data-filter="action">
                                        Ação
                                    </button>
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2" data-filter="comedy">
                                        Comédia
                                    </button>
                                    <button class="btn btn-sm btn-outline-primary me-2 mb-2" data-filter="drama">
                                        Drama
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Estatísticas -->
                <div class="row mb-4">
                    <div class="col-md-3">
                        <div class="card bg-primary text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="totalMovies">0</h1>
                                <p class="mb-0">Total de Filmes</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-success text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="recentMovies">0</h1>
                                <p class="mb-0">Adicionados (30 dias)</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-info text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="tmdbMovies">0</h1>
                                <p class="mb-0">Com TMDb</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-warning text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="missingInfo">0</h1>
                                <p class="mb-0">Faltam Informações</p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Lista de Filmes -->
                <div class="row" id="moviesGrid">
                    <!-- Carregado via JavaScript -->
                    <div class="col-12 text-center py-5">
                        <div class="spinner-border text-primary" role="status">
                            <span class="visually-hidden">Carregando...</span>
                        </div>
                        <p class="mt-2">Carregando filmes...</p>
                    </div>
                </div>
                
                <!-- Tabela de Filmes (List View) -->
                <div class="table-responsive d-none" id="moviesTable">
                    <table class="table table-hover">
                        <thead>
                            <tr>
                                <th>Poster</th>
                                <th>Título</th>
                                <th>Ano</th>
                                <th>Gênero</th>
                                <th>Classificação</th>
                                <th>Status</th>
                                <th>Ações</th>
                            </tr>
                        </thead>
                        <tbody id="moviesTableBody">
                            <!-- Carregado via JavaScript -->
                        </tbody>
                    </table>
                </div>
                
                <!-- Paginação -->
                <nav aria-label="Paginação de filmes" class="mt-4">
                    <ul class="pagination justify-content-center" id="moviesPagination">
                        <!-- Gerada via JavaScript -->
                    </ul>
                </nav>
            </div>
        </div>
    </div>
    
    <!-- Modal Filtros -->
    <div class="modal fade" id="filterModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Filtros Avançados</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <div class="row">
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label class="form-label">Gênero</label>
                                <select class="form-select" id="filterGenre" multiple>
                                    <option value="action">Ação</option>
                                    <option value="comedy">Comédia</option>
                                    <option value="drama">Drama</option>
                                    <option value="horror">Terror</option>
                                    <option value="sci-fi">Ficção Científica</option>
                                    <option value="romance">Romance</option>
                                    <option value="fantasy">Fantasia</option>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label class="form-label">Ano</label>
                                <div class="row">
                                    <div class="col-md-6">
                                        <input type="number" class="form-control" id="filterYearFrom" 
                                               placeholder="De" min="1900" max="2024">
                                    </div>
                                    <div class="col-md-6">
                                        <input type="number" class="form-control" id="filterYearTo" 
                                               placeholder="Até" min="1900" max="2024">
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="row">
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label class="form-label">Classificação Mínima</label>
                                <input type="range" class="form-range" id="filterRating" min="0" max="10" step="0.5">
                                <div class="d-flex justify-content-between">
                                    <small>0</small>
                                    <small id="ratingValue">5.0</small>
                                    <small>10</small>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label class="form-label">Ordem</label>
                                <select class="form-select" id="filterOrder">
                                    <option value="recent">Mais Recentes</option>
                                    <option value="oldest">Mais Antigos</option>
                                    <option value="rating">Melhor Avaliados</option>
                                    <option value="title">Título (A-Z)</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Status</label>
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" id="filterWithTmdb" checked>
                            <label class="form-check-label" for="filterWithTmdb">
                                Com informações TMDb
                            </label>
                        </div>
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" id="filterMissingInfo">
                            <label class="form-check-label" for="filterMissingInfo">
                                Faltam informações
                            </label>
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancelar</button>
                    <button type="button" class="btn btn-primary" onclick="applyFilters()">
                        <i class="fas fa-check me-1"></i>Aplicar Filtros
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Carregar filmes
        loadMovies();
        
        // Alternar visualização
        $('#viewGrid').click(function() {
            $(this).addClass('active');
            $('#viewList').removeClass('active');
            $('#moviesGrid').removeClass('d-none');
            $('#moviesTable').addClass('d-none');
        });
        
        $('#viewList').click(function() {
            $(this).addClass('active');
            $('#viewGrid').removeClass('active');
            $('#moviesTable').removeClass('d-none');
            $('#moviesGrid').addClass('d-none');
        });
        
        // Busca em tempo real
        $('#searchMovies').on('input', function() {
            searchMovies($(this).val());
        });
        
        // Filtros rápidos
        $('#quickFilters button').click(function() {
            $('#quickFilters button').removeClass('active');
            $(this).addClass('active');
            
            const filter = $(this).data('filter');
            applyQuickFilter(filter);
        });
        
        // Slider de classificação
        $('#filterRating').on('input', function() {
            $('#ratingValue').text($(this).val());
        });
    });
    
    function loadMovies(page = 1, filters = {}) {
        $.ajax({
            url: '/api/movies/list.php',
            method: 'GET',
            data: { page: page, ...filters },
            success: function(response) {
                if(response.success) {
                    updateMoviesGrid(response.data.movies);
                    updateMoviesTable(response.data.movies);
                    updatePagination(response.data.total_pages, page);
                    updateStats(response.data.stats);
                }
            }
        });
    }
    
    function updateMoviesGrid(movies) {
        const grid = $('#moviesGrid');
        
        if(movies.length === 0) {
            grid.html(`
                <div class="col-12">
                    <div class="alert alert-info">
                        <i class="fas fa-info-circle me-2"></i>
                        Nenhum filme encontrado. Execute uma sincronização primeiro.
                    </div>
                </div>
            `);
            return;
        }
        
        let html = '';
        
        movies.forEach(movie => {
            const posterUrl = movie.poster_path || '/assets/images/default-poster.jpg';
            const rating = movie.vote_average ? movie.vote_average.toFixed(1) : 'N/A';
            const year = movie.release_date ? movie.release_date.substring(0,4) : 'N/A';
            
            // Gêneros
            let genresHtml = '';
            if(movie.genres && movie.genres.length > 0) {
                movie.genres.slice(0, 3).forEach(genre => {
                    genresHtml += `<span class="badge badge-genre">${genre}</span>`;
                });
            }
            
            html += `
            <div class="col-xl-2 col-lg-3 col-md-4 col-sm-6">
                <div class="movie-card">
                    <img src="${posterUrl}" class="movie-poster" alt="${movie.title}" 
                         onerror="this.src='/assets/images/default-poster.jpg'">
                    <div class="movie-info">
                        <div class="movie-title" title="${movie.title}">${movie.title}</div>
                        <div class="d-flex justify-content-between align-items-center mb-2">
                            <span class="movie-year">${year}</span>
                            <span class="movie-rating">
                                <i class="fas fa-star"></i> ${rating}
                            </span>
                        </div>
                        <div class="mb-2">${genresHtml}</div>
                        <div class="d-grid">
                            <button class="btn btn-sm btn-outline-primary" onclick="viewMovie(${movie.id})">
                                <i class="fas fa-eye me-1"></i>Detalhes
                            </button>
                        </div>
                    </div>
                </div>
            </div>`;
        });
        
        grid.html(html);
    }
    
    function updateMoviesTable(movies) {
        const tbody = $('#moviesTableBody');
        tbody.empty();
        
        movies.forEach(movie => {
            const posterUrl = movie.poster_path || '/assets/images/default-poster.jpg';
            const rating = movie.vote_average ? movie.vote_average.toFixed(1) : 'N/A';
            const year = movie.release_date ? movie.release_date.substring(0,4) : 'N/A';
            
            // Status
            let statusBadge = '<span class="badge bg-secondary">Incompleto</span>';
            if(movie.tmdb_id) {
                statusBadge = '<span class="badge bg-success">Completo</span>';
            }
            
            // Gêneros
            let genresText = 'N/A';
            if(movie.genres && movie.genres.length > 0) {
                genresText = movie.genres.slice(0, 2).join(', ');
            }
            
            const row = `
                <tr>
                    <td>
                        <img src="${posterUrl}" width="50" height="75" 
                             style="object-fit: cover; border-radius: 4px;"
                             onerror="this.src='/assets/images/default-poster.jpg'">
                    </td>
                    <td>
                        <strong>${movie.title}</strong><br>
                        <small class="text-muted">${movie.original_title || ''}</small>
                    </td>
                    <td>${year}</td>
                    <td>${genresText}</td>
                    <td>
                        <span class="badge bg-warning">
                            <i class="fas fa-star"></i> ${rating}
                        </span>
                    </td>
                    <td>${statusBadge}</td>
                    <td>
                        <button class="btn btn-sm btn-outline-primary" onclick="viewMovie(${movie.id})">
                            <i class="fas fa-eye"></i>
                        </button>
                        <button class="btn btn-sm btn-outline-success" onclick="updateMovieInfo(${movie.id})">
                            <i class="fas fa-sync"></i>
                        </button>
                        <button class="btn btn-sm btn-outline-danger" onclick="deleteMovie(${movie.id})">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>
                </tr>
            `;
            
            tbody.append(row);
        });
    }
    
    function updatePagination(totalPages, currentPage) {
        const pagination = $('#moviesPagination');
        pagination.empty();
        
        if(totalPages <= 1) return;
        
        // Previous
        const prevDisabled = currentPage <= 1 ? 'disabled' : '';
        pagination.append(`
            <li class="page-item ${prevDisabled}">
                <a class="page-link" href="#" onclick="changePage(${currentPage - 1})">
                    <i class="fas fa-chevron-left"></i>
                </a>
            </li>
        `);
        
        // Page numbers
        const startPage = Math.max(1, currentPage - 2);
        const endPage = Math.min(totalPages, currentPage + 2);
        
        for(let i = startPage; i <= endPage; i++) {
            const active = i === currentPage ? 'active' : '';
            pagination.append(`
                <li class="page-item ${active}">
                    <a class="page-link" href="#" onclick="changePage(${i})">${i}</a>
                </li>
            `);
        }
        
        // Next
        const nextDisabled = currentPage >= totalPages ? 'disabled' : '';
        pagination.append(`
            <li class="page-item ${nextDisabled}">
                <a class="page-link" href="#" onclick="changePage(${currentPage + 1})">
                    <i class="fas fa-chevron-right"></i>
                </a>
            </li>
        `);
    }
    
    function updateStats(stats) {
        $('#totalMovies').text(stats.total || 0);
        $('#recentMovies').text(stats.recent_30_days || 0);
        $('#tmdbMovies').text(stats.with_tmdb || 0);
        $('#missingInfo').text(stats.without_tmdb || 0);
    }
    
    function changePage(page) {
        loadMovies(page, getCurrentFilters());
        $('html, body').animate({ scrollTop: 0 }, 'fast');
    }
    
    function searchMovies(query) {
        const filters = getCurrentFilters();
        filters.query = query;
        loadMovies(1, filters);
    }
    
    function applyQuickFilter(filter) {
        const filters = {};
        
        switch(filter) {
            case 'recent':
                filters.order = 'recent';
                break;
            case 'popular':
                filters.order = 'rating';
                break;
            case 'action':
                filters.genre = 'action';
                break;
            case 'comedy':
                filters.genre = 'comedy';
                break;
            case 'drama':
                filters.genre = 'drama';
                break;
        }
        
        loadMovies(1, filters);
    }
    
    function applyFilters() {
        const filters = {
            genre: $('#filterGenre').val(),
            year_from: $('#filterYearFrom').val(),
            year_to: $('#filterYearTo').val(),
            rating_min: $('#filterRating').val(),
            order: $('#filterOrder').val(),
            with_tmdb: $('#filterWithTmdb').is(':checked'),
            missing_info: $('#filterMissingInfo').is(':checked')
        };
        
        $('#filterModal').modal('hide');
        loadMovies(1, filters);
    }
    
    function getCurrentFilters() {
        return {
            // Implementar conforme necessário
        };
    }
    
    function viewMovie(id) {
        window.open(`/movie.php?id=${id}`, '_blank');
    }
    
    function updateMovieInfo(id) {
        if(confirm('Atualizar informações deste filme do TMDb?')) {
            $.ajax({
                url: '/api/movies/update.php',
                method: 'POST',
                data: { id: id },
                success: function(response) {
                    if(response.success) {
                        alert('✅ Informações atualizadas com sucesso!');
                        loadMovies();
                    } else {
                        alert('❌ Erro: ' + response.message);
                    }
                }
            });
        }
    }
    
    function deleteMovie(id) {
        if(confirm('Tem certeza que deseja excluir este filme?')) {
            $.ajax({
                url: '/api/movies/delete.php',
                method: 'POST',
                data: { id: id },
                success: function(response) {
                    if(response.success) {
                        alert('Filme excluído com sucesso!');
                        loadMovies();
                    } else {
                        alert('Erro: ' + response.message);
                    }
                }
            });
        }
    }
    </script>
</body>
</html>
MOVIES_PAGE

    success "✅ Página de filmes criada"
    
    # ==================== SÉRIES ====================
    log "Criando página de séries..."
    
    cat > "$FRONTEND_DIR/public/series.php" << 'SERIES_PAGE'
<?php
session_start();
require_once 'auth_check.php';

$page_title = "Séries";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .series-card {
            border: 1px solid #dee2e6;
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 20px;
            transition: transform 0.3s;
            background: white;
        }
        .series-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
        }
        .series-poster {
            width: 100%;
            height: 300px;
            object-fit: cover;
        }
        .series-info {
            padding: 15px;
        }
        .series-title {
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 5px;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }
        .series-meta {
            font-size: 13px;
            color: #6c757d;
        }
        .season-badge {
            background: #e9ecef;
            color: #495057;
            border-radius: 4px;
            padding: 2px 8px;
            font-size: 12px;
            margin-right: 5px;
            margin-bottom: 5px;
            display: inline-block;
        }
        .episode-count {
            background: #d1ecf1;
            color: #0c5460;
            border-radius: 4px;
            padding: 2px 8px;
            font-size: 12px;
            margin-right: 5px;
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Séries</li>
                    </ol>
                </nav>
                
                <!-- Filtros e Controles -->
                <div class="card mb-4">
                    <div class="card-body">
                        <div class="row">
                            <div class="col-md-6">
                                <div class="input-group">
                                    <span class="input-group-text">
                                        <i class="fas fa-search"></i>
                                    </span>
                                    <input type="text" class="form-control" id="searchSeries" 
                                           placeholder="Buscar séries...">
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="d-flex justify-content-end">
                                    <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#filterSeriesModal">
                                        <i class="fas fa-filter me-1"></i>Filtros
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Estatísticas -->
                <div class="row mb-4">
                    <div class="col-md-3">
                        <div class="card bg-primary text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="totalSeries">0</h1>
                                <p class="mb-0">Total de Séries</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-success text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="totalSeasons">0</h1>
                                <p class="mb-0">Temporadas</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-info text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="totalEpisodes">0</h1>
                                <p class="mb-0">Episódios</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-warning text-white">
                            <div class="card-body">
                                <h1 class="display-6" id="recentSeries">0</h1>
                                <p class="mb-0">Adicionadas (30 dias)</p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Lista de Séries -->
                <div class="row" id="seriesGrid">
                    <!-- Carregado via JavaScript -->
                    <div class="col-12 text-center py-5">
                        <div class="spinner-border text-primary" role="status">
                            <span class="visually-hidden">Carregando...</span>
                        </div>
                        <p class="mt-2">Carregando séries...</p>
                    </div>
                </div>
                
                <!-- Paginação -->
                <nav aria-label="Paginação de séries" class="mt-4">
                    <ul class="pagination justify-content-center" id="seriesPagination">
                        <!-- Gerada via JavaScript -->
                    </ul>
                </nav>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Carregar séries
        loadSeries();
        
        // Busca em tempo real
        $('#searchSeries').on('input', function() {
            searchSeries($(this).val());
        });
    });
    
    function loadSeries(page = 1, filters = {}) {
        $.ajax({
            url: '/api/series/list.php',
            method: 'GET',
            data: { page: page, ...filters },
            success: function(response) {
                if(response.success) {
                    updateSeriesGrid(response.data.series);
                    updatePagination(response.data.total_pages, page);
                    updateStats(response.data.stats);
                }
            }
        });
    }
    
    function updateSeriesGrid(series) {
        const grid = $('#seriesGrid');
        
        if(series.length === 0) {
            grid.html(`
                <div class="col-12">
                    <div class="alert alert-info">
                        <i class="fas fa-info-circle me-2"></i>
                        Nenhuma série encontrada. Execute uma sincronização primeiro.
                    </div>
                </div>
            `);
            return;
        }
        
        let html = '';
        
        series.forEach(serie => {
            const posterUrl = serie.poster_path || '/assets/images/default-poster.jpg';
            const rating = serie.vote_average ? serie.vote_average.toFixed(1) : 'N/A';
            const year = serie.first_air_date ? serie.first_air_date.substring(0,4) : 'N/A';
            
            // Temporadas
            let seasonsHtml = '';
            if(serie.seasons && serie.seasons.length > 0) {
                serie.seasons.slice(0, 3).forEach(season => {
                    seasonsHtml += `<span class="season-badge">T${season.season_number}</span>`;
                });
                
                if(serie.seasons.length > 3) {
                    seasonsHtml += `<span class="season-badge">+${serie.seasons.length - 3}</span>`;
                }
            }
            
            // Contagem de episódios
            const episodeCount = serie.episode_count || 0;
            
            html += `
            <div class="col-xl-2 col-lg-3 col-md-4 col-sm-6">
                <div class="series-card">
                    <img src="${posterUrl}" class="series-poster" alt="${serie.name}" 
                         onerror="this.src='/assets/images/default-poster.jpg'">
                    <div class="series-info">
                        <div class="series-title" title="${serie.name}">${serie.name}</div>
                        <div class="series-meta mb-2">
                            <span class="me-2">${year}</span>
                            <span><i class="fas fa-star text-warning"></i> ${rating}</span>
                        </div>
                        <div class="mb-2">
                            ${seasonsHtml}
                            <span class="episode-count">
                                <i class="fas fa-play-circle"></i> ${episodeCount}
                            </span>
                        </div>
                        <div class="d-grid">
                            <button class="btn btn-sm btn-outline-primary" onclick="viewSeries(${serie.id})">
                                <i class="fas fa-eye me-1"></i>Ver Detalhes
                            </button>
                        </div>
                    </div>
                </div>
            </div>`;
        });
        
        grid.html(html);
    }
    
    function updatePagination(totalPages, currentPage) {
        const pagination = $('#seriesPagination');
        pagination.empty();
        
        if(totalPages <= 1) return;
        
        // Previous
        const prevDisabled = currentPage <= 1 ? 'disabled' : '';
        pagination.append(`
            <li class="page-item ${prevDisabled}">
                <a class="page-link" href="#" onclick="changePage(${currentPage - 1})">
                    <i class="fas fa-chevron-left"></i>
                </a>
            </li>
        `);
        
        // Page numbers
        const startPage = Math.max(1, currentPage - 2);
        const endPage = Math.min(totalPages, currentPage + 2);
        
        for(let i = startPage; i <= endPage; i++) {
            const active = i === currentPage ? 'active' : '';
            pagination.append(`
                <li class="page-item ${active}">
                    <a class="page-link" href="#" onclick="changePage(${i})">${i}</a>
                </li>
            `);
        }
        
        // Next
        const nextDisabled = currentPage >= totalPages ? 'disabled' : '';
        pagination.append(`
            <li class="page-item ${nextDisabled}">
                <a class="page-link" href="#" onclick="changePage(${currentPage + 1})">
                    <i class="fas fa-chevron-right"></i>
                </a>
            </li>
        `);
    }
    
    function updateStats(stats) {
        $('#totalSeries').text(stats.total_series || 0);
        $('#totalSeasons').text(stats.total_seasons || 0);
        $('#totalEpisodes').text(stats.total_episodes || 0);
        $('#recentSeries').text(stats.recent_30_days || 0);
    }
    
    function changePage(page) {
        loadSeries(page, getCurrentFilters());
        $('html, body').animate({ scrollTop: 0 }, 'fast');
    }
    
    function searchSeries(query) {
        const filters = getCurrentFilters();
        filters.query = query;
        loadSeries(1, filters);
    }
    
    function getCurrentFilters() {
        return {};
    }
    
    function viewSeries(id) {
        window.open(`/serie.php?id=${id}`, '_blank');
    }
    </script>
</body>
</html>
SERIES_PAGE

    success "✅ Página de séries criada"
    
    # ==================== LOGS ====================
    log "Criando página de logs..."
    
    cat > "$FRONTEND_DIR/public/logs.php" << 'LOGS_PAGE'
<?php
session_start();
require_once 'auth_check.php';

$page_title = "Logs do Sistema";
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - VOD Sync</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .log-container {
            max-height: 600px;
            overflow-y: auto;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            background: #f8f9fa;
        }
        .log-entry {
            padding: 10px 15px;
            border-bottom: 1px solid #eee;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
        .log-entry:last-child {
            border-bottom: none;
        }
        .log-level-info {
            border-left: 4px solid #0d6efd;
            background: #e7f1ff;
        }
        .log-level-success {
            border-left: 4px solid #198754;
            background: #d4edda;
        }
        .log-level-warning {
            border-left: 4px solid #ffc107;
            background: #fff3cd;
        }
        .log-level-error {
            border-left: 4px solid #dc3545;
            background: #f8d7da;
        }
        .log-time {
            color: #6c757d;
            font-size: 12px;
            min-width: 120px;
        }
        .log-message {
            word-break: break-all;
        }
        .log-badge {
            font-size: 11px;
            padding: 2px 8px;
            border-radius: 10px;
            margin-right: 5px;
        }
        .filter-tag {
            cursor: pointer;
            transition: all 0.2s;
        }
        .filter-tag:hover {
            transform: scale(1.05);
        }
    </style>
</head>
<body>
    <?php include 'navbar.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col-md-12">
                <nav aria-label="breadcrumb">
                    <ol class="breadcrumb">
                        <li class="breadcrumb-item"><a href="/dashboard.php">Dashboard</a></li>
                        <li class="breadcrumb-item active">Logs</li>
                    </ol>
                </nav>
                
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <h5 class="mb-0">
                            <i class="fas fa-clipboard-list me-2"></i>Logs do Sistema
                        </h5>
                        <div>
                            <button class="btn btn-sm btn-outline-danger" onclick="clearLogs()">
                                <i class="fas fa-trash me-1"></i>Limpar Logs
                            </button>
                            <button class="btn btn-sm btn-outline-primary" onclick="refreshLogs()">
                                <i class="fas fa-sync me-1"></i>Atualizar
                            </button>
                        </div>
                    </div>
                    
                    <div class="card-body">
                        <!-- Filtros -->
                        <div class="row mb-4">
                            <div class="col-md-12">
                                <div class="card">
                                    <div class="card-body">
                                        <h6 class="card-title">Filtros</h6>
                                        
                                        <div class="row">
                                            <div class="col-md-3">
                                                <div class="mb-3">
                                                    <label class="form-label">Nível</label>
                                                    <select class="form-select" id="filterLevel">
                                                        <option value="all">Todos</option>
                                                        <option value="info">Info</option>
                                                        <option value="success">Sucesso</option>
                                                        <option value="warning">Aviso</option>
                                                        <option value="error">Erro</option>
                                                    </select>
                                                </div>
                                            </div>
                                            <div class="col-md-3">
                                                <div class="mb-3">
                                                    <label class="form-label">Tipo</label>
                                                    <select class="form-select" id="filterType">
                                                        <option value="all">Todos</option>
                                                        <option value="sync">Sincronização</option>
                                                        <option value="xui">XUI</option>
                                                        <option value="m3u">M3U</option>
                                                        <option value="tmdb">TMDb</option>
                                                        <option value="system">Sistema</option>
                                                    </select>
                                                </div>
                                            </div>
                                            <div class="col-md-3">
                                                <div class="mb-3">
                                                    <label class="form-label">Período</label>
                                                    <select class="form-select" id="filterPeriod">
                                                        <option value="today">Hoje</option>
                                                        <option value="yesterday">Ontem</option>
                                                        <option value="week">Esta semana</option>
                                                        <option value="month">Este mês</option>
                                                        <option value="all">Todos</option>
                                                    </select>
                                                </div>
                                            </div>
                                            <div class="col-md-3">
                                                <div class="mb-3">
                                                    <label class="form-label">Busca</label>
                                                    <div class="input-group">
                                                        <input type="text" class="form-control" id="filterSearch" 
                                                               placeholder="Buscar em logs...">
                                                        <button class="btn btn-outline-secondary" onclick="applyFilters()">
                                                            <i class="fas fa-search"></i>
                                                        </button>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                        
                                        <!-- Tags de filtro rápido -->
                                        <div class="mt-3">
                                            <small class="text-muted me-2">Filtros rápidos:</small>
                                            <span class="badge bg-primary filter-tag me-2" data-level="error">
                                                <i class="fas fa-exclamation-circle me-1"></i>Erros
                                            </span>
                                            <span class="badge bg-success filter-tag me-2" data-type="sync">
                                                <i class="fas fa-sync me-1"></i>Sincronização
                                            </span>
                                            <span class="badge bg-warning filter-tag me-2" data-type="m3u">
                                                <i class="fas fa-list me-1"></i>M3U
                                            </span>
                                            <span class="badge bg-info filter-tag" data-type="tmdb">
                                                <i class="fas fa-database me-1"></i>TMDb
                                            </span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Estatísticas -->
                        <div class="row mb-4">
                            <div class="col-md-3">
                                <div class="card bg-primary text-white">
                                    <div class="card-body">
                                        <h1 class="display-6" id="totalLogs">0</h1>
                                        <p class="mb-0">Total de Logs</p>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="card bg-success text-white">
                                    <div class="card-body">
                                        <h1 class="display-6" id="successLogs">0</h1>
                                        <p class="mb-0">Sucesso</p>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="card bg-warning text-white">
                                    <div class="card-body">
                                        <h1 class="display-6" id="warningLogs">0</h1>
                                        <p class="mb-0">Avisos</p>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="card bg-danger text-white">
                                    <div class="card-body">
                                        <h1 class="display-6" id="errorLogs">0</h1>
                                        <p class="mb-0">Erros</p>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Logs em Tempo Real -->
                        <div class="card">
                            <div class="card-header d-flex justify-content-between align-items-center">
                                <h6 class="mb-0">Logs em Tempo Real</h6>
                                <div class="form-check form-switch">
                                    <input class="form-check-input" type="checkbox" id="autoRefresh" checked>
                                    <label class="form-check-label" for="autoRefresh">
                                        Auto-atualizar
                                    </label>
                                </div>
                            </div>
                            <div class="card-body p-0">
                                <div class="log-container" id="logContainer">
                                    <!-- Logs serão carregados aqui -->
                                    <div class="log-entry log-level-info">
                                        <div class="d-flex">
                                            <div class="log-time"><?php echo date('H:i:s'); ?></div>
                                            <div class="log-message">
                                                Sistema de logs inicializado. Aguardando dados...
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <div class="card-footer">
                                <div class="d-flex justify-content-between align-items-center">
                                    <small class="text-muted" id="logCount">0 logs</small>
                                    <div>
                                        <button class="btn btn-sm btn-outline-secondary" onclick="scrollToTop()">
                                            <i class="fas fa-arrow-up"></i>
                                        </button>
                                        <button class="btn btn-sm btn-outline-secondary" onclick="scrollToBottom()">
                                            <i class="fas fa-arrow-down"></i>
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Exportação -->
                        <div class="row mt-4">
                            <div class="col-md-12">
                                <div class="card">
                                    <div class="card-body">
                                        <h6 class="card-title">Exportação</h6>
                                        <div class="btn-group">
                                            <button class="btn btn-outline-primary" onclick="exportLogs('txt')">
                                                <i class="fas fa-file-alt me-1"></i>TXT
                                            </button>
                                            <button class="btn btn-outline-success" onclick="exportLogs('csv')">
                                                <i class="fas fa-file-csv me-1"></i>CSV
                                            </button>
                                            <button class="btn btn-outline-info" onclick="exportLogs('json')">
                                                <i class="fas fa-file-code me-1"></i>JSON
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    
    <script>
    $(document).ready(function() {
        // Carregar logs iniciais
        loadLogs();
        
        // Configurar auto-refresh
        let refreshInterval;
        setupAutoRefresh();
        
        $('#autoRefresh').change(function() {
            setupAutoRefresh();
        });
        
        // Filtros rápidos
        $('.filter-tag').click(function() {
            const level = $(this).data('level');
            const type = $(this).data('type');
            
            if(level) {
                $('#filterLevel').val(level);
            }
            if(type) {
                $('#filterType').val(type);
            }
            
            applyFilters();
        });
    });
    
    function setupAutoRefresh() {
        if(refreshInterval) {
            clearInterval(refreshInterval);
        }
        
        if($('#autoRefresh').is(':checked')) {
            refreshInterval = setInterval(loadLogs, 5000); // Atualizar a cada 5 segundos
        }
    }
    
    function loadLogs() {
        const filters = getCurrentFilters();
        
        $.ajax({
            url: '/api/logs/list.php',
            method: 'GET',
            data: filters,
            success: function(response) {
                if(response.success) {
                    updateLogsUI(response.data.logs);
                    updateStats(response.data.stats);
                }
            }
        });
    }
    
    function updateLogsUI(logs) {
        const container = $('#logContainer');
        
        if(logs.length === 0) {
            container.html(`
                <div class="log-entry log-level-info">
                    <div class="d-flex">
                        <div class="log-time"><?php echo date('H:i:s'); ?></div>
                        <div class="log-message">
                            Nenhum log encontrado com os filtros atuais.
                        </div>
                    </div>
                </div>
            `);
            $('#logCount').text('0 logs');
            return;
        }
        
        let html = '';
        
        logs.forEach(log => {
            const time = new Date(log.timestamp).toLocaleTimeString();
            const date = new Date(log.timestamp).toLocaleDateString();
            
            // Determinar classe CSS baseada no nível
            let levelClass = 'log-level-info';
            let levelBadge = '<span class="badge bg-primary log-badge">INFO</span>';
            
            switch(log.level) {
                case 'success':
                    levelClass = 'log-level-success';
                    levelBadge = '<span class="badge bg-success log-badge">SUCESSO</span>';
                    break;
                case 'warning':
                    levelClass = 'log-level-warning';
                    levelBadge = '<span class="badge bg-warning log-badge">AVISO</span>';
                    break;
                case 'error':
                    levelClass = 'log-level-error';
                    levelBadge = '<span class="badge bg-danger log-badge">ERRO</span>';
                    break;
            }
            
            // Badge de tipo
            let typeBadge = '';
            if(log.type) {
                let typeClass = 'bg-secondary';
                switch(log.type) {
                    case 'sync': typeClass = 'bg-success'; break;
                    case 'xui': typeClass = 'bg-info'; break;
                    case 'm3u': typeClass = 'bg-warning'; break;
                    case 'tmdb': typeClass = 'bg-primary'; break;
                }
                typeBadge = `<span class="badge ${typeClass} log-badge">${log.type.toUpperCase()}</span>`;
            }
            
            html += `
            <div class="log-entry ${levelClass}">
                <div class="d-flex">
                    <div class="log-time" title="${date}">${time}</div>
                    <div class="log-message flex-grow-1">
                        <div class="mb-1">
                            ${levelBadge}
                            ${typeBadge}
                            <strong>${log.source || 'Sistema'}:</strong>
                        </div>
                        <div>${log.message}</div>
                        ${log.details ? `<small class="text-muted">${log.details}</small>` : ''}
                    </div>
                </div>
            </div>`;
        });
        
        // Manter scroll position se já estiver no final
        const isScrolledToBottom = container[0].scrollHeight - container.scrollTop() === container.outerHeight();
        
        container.html(html);
        $('#logCount').text(logs.length + ' logs');
        
        // Se estava no final, manter no final
        if(isScrolledToBottom) {
            scrollToBottom();
        }
    }
    
    function updateStats(stats) {
        $('#totalLogs').text(stats.total || 0);
        $('#successLogs').text(stats.success || 0);
        $('#warningLogs').text(stats.warning || 0);
        $('#errorLogs').text(stats.error || 0);
    }
    
    function getCurrentFilters() {
        return {
            level: $('#filterLevel').val(),
            type: $('#filterType').val(),
            period: $('#filterPeriod').val(),
            search: $('#filterSearch').val()
        };
    }
    
    function applyFilters() {
        loadLogs();
    }
    
    function clearLogs() {
        if(confirm('Tem certeza que deseja limpar todos os logs?')) {
            $.ajax({
                url: '/api/logs/clear.php',
                method: 'POST',
                success: function(response) {
                    if(response.success) {
                        alert('Logs limpos com sucesso!');
                        loadLogs();
                    }
                }
            });
        }
    }
    
    function refreshLogs() {
        loadLogs();
    }
    
    function scrollToTop() {
        $('#logContainer').scrollTop(0);
    }
    
    function scrollToBottom() {
        const container = $('#logContainer');
        container.scrollTop(container[0].scrollHeight);
    }
    
    function exportLogs(format) {
        const filters = getCurrentFilters();
        filters.format = format;
        
        const params = new URLSearchParams(filters).toString();
        window.open('/api/logs/export.php?' + params, '_blank');
    }
    </script>
</body>
</html>
LOGS_PAGE

    success "✅ Página de logs criada"
    
    # ==================== ARQUIVOS DE AUTENTICAÇÃO ====================
    log "Criando arquivos de autenticação..."
    
    cat > "$FRONTEND_DIR/public/auth_check.php" << 'AUTH_CHECK'
<?php
/**
 * Verificação de autenticação
 */
session_start();

// Redirecionar para login se não estiver autenticado
if (!isset($_SESSION['user_id'])) {
    header('Location: /');
    exit();
}

// Verificar tempo de sessão (8 horas)
$session_timeout = 8 * 60 * 60; // 8 horas em segundos
if (isset($_SESSION['login_time']) && (time() - $_SESSION['login_time'] > $session_timeout)) {
    session_destroy();
    header('Location: /?session=expired');
    exit();
}

// Atualizar tempo da sessão a cada requisição
$_SESSION['login_time'] = time();

// Verificar permissões
function checkPermission($required_type) {
    if (!isset($_SESSION['user_type'])) {
        return false;
    }
    
    // Hierarquia de permissões
    $hierarchy = [
        'user' => 1,
        'reseller' => 2,
        'admin' => 3
    ];
    
    $user_level = isset($hierarchy[$_SESSION['user_type']]) ? $hierarchy[$_SESSION['user_type']] : 0;
    $required_level = isset($hierarchy[$required_type]) ? $hierarchy[$required_type] : 0;
    
    return $user_level >= $required_level;
}

// Função para verificar se é admin
function isAdmin() {
    return isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'admin';
}

// Função para verificar se é reseller
function isReseller() {
    return isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'reseller';
}

// Função para verificar se é usuário normal
function isUser() {
    return isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'user';
}
?>
AUTH_CHECK

    cat > "$FRONTEND_DIR/public/navbar.php" << 'NAVBAR'
<?php
// Determinar página ativa
$current_page = basename($_SERVER['PHP_SELF']);
?>
<nav class="navbar navbar-expand-lg navbar-dark bg-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="/dashboard.php">
            <i class="fas fa-sync-alt me-2"></i>VOD Sync
        </a>
        
        <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
            <span class="navbar-toggler-icon"></span>
        </button>
        
        <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav me-auto">
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'dashboard.php' ? 'active' : ''; ?>" 
                       href="/dashboard.php">
                        <i class="fas fa-tachometer-alt me-1"></i>Dashboard
                    </a>
                </li>
                
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'xui.php' ? 'active' : ''; ?>" 
                       href="/xui.php">
                        <i class="fas fa-server me-1"></i>Conexões XUI
                    </a>
                </li>
                
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'm3u.php' ? 'active' : ''; ?>" 
                       href="/m3u.php">
                        <i class="fas fa-list me-1"></i>Listas M3U
                    </a>
                </li>
                
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'movies.php' ? 'active' : ''; ?>" 
                       href="/movies.php">
                        <i class="fas fa-film me-1"></i>Filmes
                    </a>
                </li>
                
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'series.php' ? 'active' : ''; ?>" 
                       href="/series.php">
                        <i class="fas fa-tv me-1"></i>Séries
                    </a>
                </li>
                
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'sync.php' ? 'active' : ''; ?>" 
                       href="/sync.php">
                        <i class="fas fa-sync me-1"></i>Sincronização
                    </a>
                </li>
                
                <?php if(isAdmin()): ?>
                <li class="nav-item">
                    <a class="nav-link <?php echo $current_page == 'logs.php' ? 'active' : ''; ?>" 
                       href="/logs.php">
                        <i class="fas fa-clipboard-list me-1"></i>Logs
                    </a>
                </li>
                <?php endif; ?>
            </ul>
            
            <ul class="navbar-nav">
                <li class="nav-item dropdown">
                    <a class="nav-link dropdown-toggle" href="#" id="userDropdown" 
                       data-bs-toggle="dropdown">
                        <i class="fas fa-user me-1"></i>
                        <?php echo htmlspecialchars($_SESSION['username']); ?>
                        <span class="badge bg-<?php 
                            echo $_SESSION['user_type'] == 'admin' ? 'danger' : 
                                 ($_SESSION['user_type'] == 'reseller' ? 'warning' : 'info'); 
                        ?> ms-1">
                            <?php echo ucfirst($_SESSION['user_type']); ?>
                        </span>
                    </a>
                    <ul class="dropdown-menu dropdown-menu-end">
                        <li>
                            <a class="dropdown-item" href="#">
                                <i class="fas fa-user-circle me-2"></i>Meu Perfil
                            </a>
                        </li>
                        <li>
                            <a class="dropdown-item" href="#">
                                <i class="fas fa-cog me-2"></i>Configurações
                            </a>
                        </li>
                        <li><hr class="dropdown-divider"></li>
                        <li>
                            <a class="dropdown-item text-danger" href="/logout.php">
                                <i class="fas fa-sign-out-alt me-2"></i>Sair
                            </a>
                        </li>
                    </ul>
                </li>
            </ul>
        </div>
    </div>
</nav>

<!-- Notificações -->
<div class="position-fixed top-0 end-0 p-3" style="z-index: 11">
    <div id="notificationToast" class="toast" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="toast-header">
            <strong class="me-auto">Notificação</strong>
            <small>Agora</small>
            <button type="button" class="btn-close" data-bs-dismiss="toast"></button>
        </div>
        <div class="toast-body" id="notificationMessage">
            Olá, <?php echo htmlspecialchars($_SESSION['username']); ?>!
        </div>
    </div>
</div>

<script>
// Mostrar notificação de boas-vindas
document.addEventListener('DOMContentLoaded', function() {
    const toast = new bootstrap.Toast(document.getElementById('notificationToast'));
    setTimeout(() => toast.show(), 1000);
});
</script>
NAVBAR

    success "✅ Arquivos de autenticação criados"
    
    # ==================== API ENDPOINTS ====================
    log "Criando endpoints da API..."
    
    # Criar diretórios da API
    mkdir -p "$FRONTEND_DIR/public/api/xui"
    mkdir -p "$FRONTEND_DIR/public/api/m3u"
    mkdir -p "$FRONTEND_DIR/public/api/sync"
    mkdir -p "$FRONTEND_DIR/public/api/movies"
    mkdir -p "$FRONTEND_DIR/public/api/series"
    mkdir -p "$FRONTEND_DIR/public/api/logs"
    
    # API para listar conexões XUI
    cat > "$FRONTEND_DIR/public/api/xui/list.php" << 'XUI_LIST_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de dados (em produção, buscar do banco de dados)
$connections = [
    [
        'id' => 1,
        'alias' => 'XUI Principal',
        'host' => 'localhost',
        'port' => 3306,
        'username' => 'xui_user',
        'is_active' => true,
        'created_at' => '2024-01-15 10:30:00'
    ],
    [
        'id' => 2,
        'alias' => 'XUI Backup',
        'host' => '192.168.1.100',
        'port' => 3306,
        'username' => 'admin',
        'is_active' => false,
        'created_at' => '2024-01-20 14:45:00'
    ]
];

echo json_encode([
    'success' => true,
    'data' => $connections
]);
?>
XUI_LIST_API

    # API para adicionar conexão XUI
    cat > "$FRONTEND_DIR/public/api/xui/add.php" << 'XUI_ADD_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de adição (em produção, salvar no banco)
$data = $_POST;

echo json_encode([
    'success' => true,
    'message' => 'Conexão XUI adicionada com sucesso',
    'data' => $data
]);
?>
XUI_ADD_API

    # API para listar M3U
    cat > "$FRONTEND_DIR/public/api/m3u/list.php" << 'M3U_LIST_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de dados
$lists = [
    [
        'id' => 1,
        'name' => 'Lista Premium',
        'source_type' => 'file',
        'category' => 'mixed',
        'channel_count' => 1500,
        'movie_count' => 500,
        'series_count' => 200,
        'is_active' => true,
        'last_updated' => '2024-01-25 09:15:00'
    ],
    [
        'id' => 2,
        'name' => 'Canais Live',
        'source_type' => 'url',
        'category' => 'tv',
        'channel_count' => 800,
        'movie_count' => 0,
        'series_count' => 0,
        'is_active' => true,
        'last_updated' => '2024-01-24 16:30:00'
    ]
];

$stats = [
    'total_lists' => 2,
    'total_channels' => 2300,
    'total_movies' => 500,
    'total_series' => 200
];

echo json_encode([
    'success' => true,
    'data' => $lists,
    'stats' => $stats
]);
?>
M3U_LIST_API

    # API para upload M3U
    cat > "$FRONTEND_DIR/public/api/m3u/upload.php" << 'M3U_UPLOAD_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de upload
$filename = $_FILES['m3u_file']['name'] ?? 'arquivo.m3u';

echo json_encode([
    'success' => true,
    'message' => 'Arquivo M3U processado com sucesso',
    'filename' => $filename,
    'items_processed' => 1250
]);
?>
M3U_UPLOAD_API

    # API para iniciar sincronização
    cat > "$FRONTEND_DIR/public/api/sync/start.php" << 'SYNC_START_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de início de sincronização
$sync_id = uniqid('sync_', true);

echo json_encode([
    'success' => true,
    'message' => 'Sincronização iniciada',
    'sync_id' => $sync_id,
    'estimated_time' => '5 minutos'
]);
?>
SYNC_START_API

    # API para status da sincronização
    cat > "$FRONTEND_DIR/public/api/sync/status.php" << 'SYNC_STATUS_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de status
$status = [
    'id' => $_GET['id'] ?? 'sync_123',
    'status' => 'in_progress',
    'progress' => 65,
    'step_1' => ['status' => 'completed', 'message' => 'Conexão XUI estabelecida'],
    'step_2' => ['status' => 'completed', 'message' => 'M3U processada: 1250 itens'],
    'step_3' => ['status' => 'in_progress', 'message' => 'Enriquecendo com TMDb...'],
    'step_4' => ['status' => 'pending', 'message' => 'Aguardando...'],
    'logs' => [
        ['message' => '✅ Conexão com XUI estabelecida', 'type' => 'success'],
        ['message' => '📋 Processando lista M3U...', 'type' => 'info'],
        ['message' => '🎬 Buscando informações do TMDb...', 'type' => 'info']
    ]
];

echo json_encode([
    'success' => true,
    'data' => $status
]);
?>
SYNC_STATUS_API

    # API para listar filmes
    cat > "$FRONTEND_DIR/public/api/movies/list.php" << 'MOVIES_LIST_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de filmes
$movies = [];

// Gerar alguns filmes de exemplo
for ($i = 1; $i <= 12; $i++) {
    $genres = ['Ação', 'Comédia', 'Drama', 'Ficção Científica'];
    shuffle($genres);
    
    $movies[] = [
        'id' => $i,
        'title' => "Filme Exemplo $i",
        'original_title' => "Example Movie $i",
        'release_date' => (2020 + $i) . '-01-15',
        'vote_average' => rand(50, 95) / 10,
        'poster_path' => 'https://image.tmdb.org/t/p/w500/example.jpg',
        'genres' => array_slice($genres, 0, rand(1, 3)),
        'tmdb_id' => rand(1000, 9999),
        'created_at' => date('Y-m-d H:i:s', strtotime("-{$i} days"))
    ];
}

$stats = [
    'total' => 250,
    'recent_30_days' => 45,
    'with_tmdb' => 180,
    'without_tmdb' => 70
];

echo json_encode([
    'success' => true,
    'data' => [
        'movies' => $movies,
        'total_pages' => 5,
        'current_page' => 1,
        'stats' => $stats
    ]
]);
?>
MOVIES_LIST_API

    # API para listar séries
    cat > "$FRONTEND_DIR/public/api/series/list.php" << 'SERIES_LIST_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de séries
$series = [];

for ($i = 1; $i <= 12; $i++) {
    $seasons = [];
    $season_count = rand(1, 5);
    
    for ($s = 1; $s <= $season_count; $s++) {
        $seasons[] = [
            'season_number' => $s,
            'episode_count' => rand(6, 22)
        ];
    }
    
    $series[] = [
        'id' => $i,
        'name' => "Série Exemplo $i",
        'first_air_date' => (2015 + $i) . '-09-15',
        'vote_average' => rand(60, 95) / 10,
        'poster_path' => 'https://image.tmdb.org/t/p/w500/example.jpg',
        'seasons' => $seasons,
        'episode_count' => array_sum(array_column($seasons, 'episode_count')),
        'tmdb_id' => rand(2000, 9999),
        'created_at' => date('Y-m-d H:i:s', strtotime("-{$i} days"))
    ];
}

$stats = [
    'total_series' => 120,
    'total_seasons' => 450,
    'total_episodes' => 5200,
    'recent_30_days' => 25
];

echo json_encode([
    'success' => true,
    'data' => [
        'series' => $series,
        'total_pages' => 4,
        'current_page' => 1,
        'stats' => $stats
    ]
]);
?>
SERIES_LIST_API

    # API para listar logs
    cat > "$FRONTEND_DIR/public/api/logs/list.php" << 'LOGS_LIST_API'
<?php
header('Content-Type: application/json');
session_start();

// Simulação de logs
$logs = [];

$log_types = ['sync', 'xui', 'm3u', 'tmdb', 'system'];
$log_levels = ['info', 'success', 'warning', 'error'];
$log_sources = ['Sincronização', 'XUI Connection', 'M3U Processor', 'TMDb API', 'Sistema'];

for ($i = 0; $i < 50; $i++) {
    $type = $log_types[array_rand($log_types)];
    $level = $log_levels[array_rand($log_levels)];
    $source = $log_sources[array_rand($log_sources)];
    
    $messages = [
        'info' => ['Processo iniciado', 'Conexão estabelecida', 'Arquivo carregado'],
        'success' => ['Sincronização concluída', 'Conexão testada com sucesso', 'Arquivo processado'],
        'warning' => ['Aviso: limite próximo', 'Conexão lenta', 'Formato não padrão'],
        'error' => ['Erro de conexão', 'Arquivo corrompido', 'Timeout na API']
    ];
    
    $logs[] = [
        'id' => $i + 1,
        'timestamp' => date('Y-m-d H:i:s', strtotime("-{$i} minutes")),
        'level' => $level,
        'type' => $type,
        'source' => $source,
        'message' => $messages[$level][array_rand($messages[$level])],
        'details' => $i % 5 == 0 ? 'Detalhes adicionais para diagnóstico' : null
    ];
}

// Ordenar por timestamp (mais recente primeiro)
usort($logs, function($a, $b) {
    return strtotime($b['timestamp']) - strtotime($a['timestamp']);
});

// Limitar para os 20 mais recentes
$logs = array_slice($logs, 0, 20);

$stats = [
    'total' => 1250,
    'success' => 980,
    'warning' => 150,
    'error' => 120
];

echo json_encode([
    'success' => true,
    'data' => [
        'logs' => $logs,
        'stats' => $stats
    ]
]);
?>
LOGS_LIST_API

    success "✅ Endpoints da API criados"
    
    # ==================== ATUALIZAR PERMISSÕES ====================
    log "Atualizando permissões..."
    
    chown -R www-data:www-data "$FRONTEND_DIR"
    chmod -R 755 "$FRONTEND_DIR/public"
    
    # ==================== CRIAR ARQUIVOS DE CONFIGURAÇÃO ====================
    log "Criando arquivos de configuração..."
    
    cat > "$FRONTEND_DIR/config/config.php" << 'CONFIG_FILE'
<?php
return [
    'app' => [
        'name' => 'VOD Sync System',
        'version' => '2.0.0',
        'env' => 'production',
        'url' => 'http://localhost',
        'timezone' => 'America/Sao_Paulo'
    ],
    
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'database' => 'vod_system',
        'username' => 'vodsync_user',
        'password' => 'VodSync123',
        'charset' => 'utf8mb4',
        'collation' => 'utf8mb4_unicode_ci'
    ],
    
    'api' => [
        'tmdb_key' => '',
        'tmdb_language' => 'pt-BR',
        'backend_url' => 'http://localhost:8000',
        'timeout' => 30
    ],
    
    'xui' => [
        'default_port' => 3306,
        'timeout' => 10,
        'max_connections' => 5
    ],
    
    'm3u' => [
        'max_file_size' => 50 * 1024 * 1024, // 50MB
        'allowed_extensions' => ['m3u', 'm3u8', 'txt'],
        'default_category' => 'tv'
    ],
    
    'sync' => [
        'batch_size' => 100,
        'max_retries' => 3,
        'enrich_tmdb' => true,
        'replace_images' => true
    ],
    
    'security' => [
        'session_timeout' => 8 * 60 * 60, // 8 horas
        'csrf_protection' => true,
        'password_min_length' => 8
    ]
];
?>
CONFIG_FILE

    # ==================== RESUMO ====================
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎉 SISTEMA COMPLETADO COM SUCESSO!"
    echo ""
    echo "📁 Páginas criadas:"
    echo "   ✅ /xui.php - Conexões XUI"
    echo "   ✅ /m3u.php - Listas M3U"
    echo "   ✅ /sync.php - Sincronização"
    echo "   ✅ /movies.php - Filmes"
    echo "   ✅ /series.php - Séries"
    echo "   ✅ /logs.php - Logs do sistema"
    echo ""
    echo "🔧 Componentes adicionais:"
    echo "   ✅ Sistema de autenticação"
    echo "   ✅ Navbar dinâmica"
    echo "   ✅ API endpoints simulados"
    echo "   ✅ Arquivo de configuração"
    echo ""
    echo "🌐 Acesse o sistema em: http://seu-ip/"
    echo ""
    echo "⚠️  Observações:"
    echo "   1. Os endpoints da API são simulados (retornam dados de exemplo)"
    echo "   2. Para produção, implemente a lógica real no backend Python"
    echo "   3. Configure as chaves TMDb em /opt/vod-sync/backend/.env"
    echo ""
    echo "⚡ Próximos passos:"
    echo "   1. Configure uma conexão XUI real"
    echo "   2. Faça upload de uma lista M3U"
    echo "   3. Execute a primeira sincronização"
    echo ""
    echo "══════════════════════════════════════════════════════════"
}

# Executar
create_missing_pages
