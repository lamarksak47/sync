#!/usr/bin/env bash
set -euo pipefail

#############################################
# Sincronizador VOD (Premium Core - Legal-Safe)
# Ubuntu 20.04 - One-file installer
#############################################

# ====== CONFIGURE AQUI (OBRIGATÓRIO) ======
APP_DIR="/opt/vodsync"
APP_USER="vodsync"
APP_GROUP="vodsync"

MYSQL_DB="vodsync"
MYSQL_USER="vodsync"
MYSQL_PASS="SENHA_FORTE_AQUI"          # <-- TROQUE
TMDB_API_KEY="SUA_CHAVE_TMDB"          # <-- TROQUE
JWT_SECRET="TROQUE_POR_UMA_CHAVE_FORTE" # <-- TROQUE

# Admin seed (troque depois)
ADMIN_EMAIL="admin@local"
ADMIN_PASS="Admin@123"

# Nginx
SERVER_NAME="_" # Pode colocar domínio: example.com  (ou "_" pra aceitar IP)

# Backend
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"

# ====== FUNÇÕES ======
log(){ echo -e "\033[1;32m[OK]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
die(){ echo -e "\033[1;31m[ERRO]\033[0m $*"; exit 1; }

need_root(){
  if [[ "${EUID}" -ne 0 ]]; then
    die "Rode como root: sudo bash install_vodsync.sh"
  fi
}

ensure_user(){
  if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    useradd -r -m -d "${APP_DIR}" -s /usr/sbin/nologin "${APP_USER}"
    log "Usuário ${APP_USER} criado"
  else
    log "Usuário ${APP_USER} já existe"
  fi
}

apt_install(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    python3 python3-venv python3-pip build-essential \
    mysql-server \
    nginx \
    php-fpm php-cli php-curl php-mbstring php-xml unzip curl
  log "Pacotes instalados"
}

mysql_setup(){
  systemctl enable --now mysql

  # Cria DB e usuário (idempotente)
  mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS ${MYSQL_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
  log "MySQL configurado (db: ${MYSQL_DB}, user: ${MYSQL_USER})"
}

write_file(){
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s" "$content" > "$path"
}

create_project_tree(){
  mkdir -p "${APP_DIR}"
  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}" || true

  # ===== schema.sql =====
  write_file "${APP_DIR}/schema.sql" "$(cat <<'EOF'
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  parent_id INT NULL,
  role ENUM('admin','reseller','user') NOT NULL DEFAULT 'user',
  name VARCHAR(120) NOT NULL,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  is_active TINYINT NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (parent_id) REFERENCES users(id)
);

CREATE TABLE licenses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  `key` VARCHAR(64) NOT NULL UNIQUE,
  plan VARCHAR(32) NOT NULL DEFAULT 'pro',
  max_connections INT NOT NULL DEFAULT 1,
  expires_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE external_connections (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  label VARCHAR(120) NOT NULL,
  host VARCHAR(120) NOT NULL,
  port INT NOT NULL DEFAULT 3306,
  db_user VARCHAR(120) NOT NULL,
  db_password VARCHAR(255) NOT NULL,
  db_name VARCHAR(120) NOT NULL,
  notes TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE m3u_lists (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  raw_text MEDIUMTEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE parsed_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  content_type VARCHAR(16) NOT NULL,
  category VARCHAR(120) NOT NULL,
  title VARCHAR(255) NOT NULL,
  source_url MEDIUMTEXT NOT NULL,
  tmdb_id INT NULL,
  year VARCHAR(8) NULL,
  overview MEDIUMTEXT NULL,
  poster_url MEDIUMTEXT NULL,
  backdrop_url MEDIUMTEXT NULL,
  genres MEDIUMTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX(owner_id),
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE schedules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  daily_time VARCHAR(5) NOT NULL DEFAULT '03:00',
  enabled TINYINT NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE sync_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  run_type VARCHAR(16) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'running',
  details MEDIUMTEXT NULL,
  added INT NOT NULL DEFAULT 0,
  updated INT NOT NULL DEFAULT 0,
  errors INT NOT NULL DEFAULT 0,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at DATETIME NULL,
  FOREIGN KEY (owner_id) REFERENCES users(id)
);
EOF
)"

  # ===== BACKEND =====
  write_file "${APP_DIR}/backend/requirements.txt" "$(cat <<'EOF'
fastapi==0.115.6
uvicorn[standard]==0.32.1
SQLAlchemy==2.0.36
pymysql==1.1.1
python-dotenv==1.0.1
requests==2.32.3
passlib[bcrypt]==1.7.4
python-jose==3.3.0
apscheduler==3.10.4
pydantic==2.10.3
EOF
)"

  write_file "${APP_DIR}/backend/.env" "$(cat <<EOF
APP_NAME=Sincronizador VOD
JWT_SECRET=${JWT_SECRET}
JWT_ALG=HS256
JWT_EXPIRES_MIN=720

MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASS}
MYSQL_DB=${MYSQL_DB}

TMDB_API_KEY=${TMDB_API_KEY}
TMDB_LANG=pt-BR

SCHEDULER_ENABLED=true
EOF
)"

  write_file "${APP_DIR}/backend/app/main.py" "$(cat <<'EOF'
from fastapi import FastAPI
from app.routes import auth, users, licenses, connections, m3u, sync, dashboard
from app.services.scheduler import scheduler_startup

app = FastAPI(title="Sincronizador VOD (Legal-Safe Core)")

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(users.router, prefix="/api/users", tags=["users"])
app.include_router(licenses.router, prefix="/api/licenses", tags=["licenses"])
app.include_router(connections.router, prefix="/api/connections", tags=["connections"])
app.include_router(m3u.router, prefix="/api/m3u", tags=["m3u"])
app.include_router(sync.router, prefix="/api/sync", tags=["sync"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])

@app.on_event("startup")
def on_startup():
    scheduler_startup()
EOF
)"

  write_file "${APP_DIR}/backend/app/database/mysql.py" "$(cat <<'EOF'
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from dotenv import load_dotenv

load_dotenv()

MYSQL_HOST = os.getenv("MYSQL_HOST")
MYSQL_PORT = os.getenv("MYSQL_PORT", "3306")
MYSQL_USER = os.getenv("MYSQL_USER")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD")
MYSQL_DB = os.getenv("MYSQL_DB")

DATABASE_URL = f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}?charset=utf8mb4"

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_recycle=3600)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF
)"

  write_file "${APP_DIR}/backend/app/models/base.py" "from app.database.mysql import Base\n"

  write_file "${APP_DIR}/backend/app/models/user.py" "$(cat <<'EOF'
from sqlalchemy import String, Integer, DateTime, Enum, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
import enum
from app.models.base import Base

class Role(str, enum.Enum):
    ADMIN = "admin"
    RESELLER = "reseller"
    USER = "user"

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    parent_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)
    role: Mapped[str] = mapped_column(Enum(Role), nullable=False, default=Role.USER)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(190), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    parent = relationship("User", remote_side=[id])
EOF
)"

  write_file "${APP_DIR}/backend/app/models/license.py" "$(cat <<'EOF'
from sqlalchemy import String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from app.models.base import Base

class License(Base):
    __tablename__ = "licenses"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    plan: Mapped[str] = mapped_column(String(32), nullable=False, default="pro")
    max_connections: Mapped[int] = mapped_column(Integer, default=1)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    owner = relationship("User")
EOF
)"

  write_file "${APP_DIR}/backend/app/models/connection.py" "$(cat <<'EOF'
from sqlalchemy import String, Integer, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from app.models.base import Base

class ExternalConnection(Base):
    """
    Conexão externa genérica (alvo). NÃO é conector XUI.
    Você pode implementar depois um adapter legal para qualquer plataforma autorizada.
    """
    __tablename__ = "external_connections"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    label: Mapped[str] = mapped_column(String(120), nullable=False)

    host: Mapped[str] = mapped_column(String(120), nullable=False)
    port: Mapped[int] = mapped_column(Integer, nullable=False, default=3306)
    db_user: Mapped[str] = mapped_column(String(120), nullable=False)
    db_password: Mapped[str] = mapped_column(String(255), nullable=False)
    db_name: Mapped[str] = mapped_column(String(120), nullable=False)

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    owner = relationship("User")
EOF
)"

  write_file "${APP_DIR}/backend/app/models/m3u.py" "$(cat <<'EOF'
from sqlalchemy import Integer, DateTime, ForeignKey, Text, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from app.models.base import Base

class M3UList(Base):
    __tablename__ = "m3u_lists"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    raw_text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    owner = relationship("User")

class ParsedItem(Base):
    __tablename__ = "parsed_items"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)

    content_type: Mapped[str] = mapped_column(String(16), nullable=False)  # movie|series|unknown
    category: Mapped[str] = mapped_column(String(120), nullable=False, default="Sem categoria")

    title: Mapped[str] = mapped_column(String(255), nullable=False)
    source_url: Mapped[str] = mapped_column(Text, nullable=False)

    tmdb_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    year: Mapped[str | None] = mapped_column(String(8), nullable=True)
    overview: Mapped[str | None] = mapped_column(Text, nullable=True)
    poster_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    backdrop_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    genres: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    owner = relationship("User")
EOF
)"

  write_file "${APP_DIR}/backend/app/models/schedule.py" "$(cat <<'EOF'
from sqlalchemy import Integer, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from app.models.base import Base

class Schedule(Base):
    __tablename__ = "schedules"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    daily_time: Mapped[str] = mapped_column(String(5), nullable=False, default="03:00")  # HH:MM
    enabled: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    owner = relationship("User")
EOF
)"

  write_file "${APP_DIR}/backend/app/models/sync_log.py" "$(cat <<'EOF'
from sqlalchemy import Integer, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from app.models.base import Base

class SyncLog(Base):
    __tablename__ = "sync_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)

    run_type: Mapped[str] = mapped_column(String(16), nullable=False)  # manual|auto
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="running")
    details: Mapped[str] = mapped_column(Text, nullable=True)

    added: Mapped[int] = mapped_column(Integer, default=0)
    updated: Mapped[int] = mapped_column(Integer, default=0)
    errors: Mapped[int] = mapped_column(Integer, default=0)

    started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    owner = relationship("User")
EOF
)"

  write_file "${APP_DIR}/backend/app/utils/security.py" "$(cat <<'EOF'
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(p: str) -> str:
    return pwd_context.hash(p)

def verify_password(p: str, h: str) -> bool:
    return pwd_context.verify(p, h)
EOF
)"

  write_file "${APP_DIR}/backend/app/utils/jwt.py" "$(cat <<'EOF'
import os
from datetime import datetime, timedelta
from jose import jwt, JWTError
from dotenv import load_dotenv

load_dotenv()

SECRET = os.getenv("JWT_SECRET", "change_me")
ALG = os.getenv("JWT_ALG", "HS256")
EXPIRES_MIN = int(os.getenv("JWT_EXPIRES_MIN", "720"))

def create_token(payload: dict) -> str:
    exp = datetime.utcnow() + timedelta(minutes=EXPIRES_MIN)
    to_encode = {**payload, "exp": exp}
    return jwt.encode(to_encode, SECRET, algorithm=ALG)

def decode_token(token: str) -> dict:
    return jwt.decode(token, SECRET, algorithms=[ALG])

def safe_decode(token: str) -> dict | None:
    try:
        return decode_token(token)
    except JWTError:
        return None
EOF
)"

  write_file "${APP_DIR}/backend/app/controllers/deps.py" "$(cat <<'EOF'
from fastapi import Depends, HTTPException, Header
from sqlalchemy.orm import Session
from app.database.mysql import get_db
from app.utils.jwt import safe_decode
from app.models.user import User, Role

def get_current_user(
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None)
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Token ausente")
    token = authorization.split(" ", 1)[1].strip()
    data = safe_decode(token)
    if not data or "user_id" not in data:
        raise HTTPException(status_code=401, detail="Token inválido")
    user = db.query(User).filter(User.id == int(data["user_id"]), User.is_active == 1).first()
    if not user:
        raise HTTPException(status_code=401, detail="Usuário não encontrado")
    return user

def require_role(*roles: Role):
    def _guard(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="Sem permissão")
        return user
    return _guard
EOF
)"

  write_file "${APP_DIR}/backend/app/services/m3u_parser.py" "$(cat <<'EOF'
import re
from typing import List, Dict

EXTINF_RE = re.compile(r"#EXTINF:-?\d+\s*(.*)", re.IGNORECASE)

def is_valid_m3u(text: str) -> bool:
    return text.strip().startswith("#EXTM3U")

def parse_m3u(text: str) -> List[Dict]:
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    items = []
    current = None

    for line in lines:
        if line.startswith("#EXTINF"):
            m = EXTINF_RE.match(line)
            meta = m.group(1) if m else ""
            group = "Sem categoria"
            ctype = "unknown"

            gt = re.search(r'group-title="([^"]+)"', meta)
            if gt:
                group = gt.group(1).strip()

            tt = re.search(r'tvg-type="([^"]+)"', meta)
            if tt:
                t = tt.group(1).lower()
                if "movie" in t:
                    ctype = "movie"
                elif "series" in t or "tv" in t:
                    ctype = "series"

            title = meta.split(",")[-1].strip() if "," in meta else "Sem título"
            current = {"title": title, "category": group, "content_type": ctype}
        elif line.startswith("#"):
            continue
        else:
            if current:
                current["source_url"] = line
                items.append(current)
                current = None

    return items
EOF
)"

  write_file "${APP_DIR}/backend/app/services/tmdb_service.py" "$(cat <<'EOF'
import os
import requests
from dotenv import load_dotenv

load_dotenv()

TMDB_KEY = os.getenv("TMDB_API_KEY", "")
TMDB_LANG = os.getenv("TMDB_LANG", "pt-BR")
BASE = "https://api.themoviedb.org/3"
IMG = "https://image.tmdb.org/t/p/original"

class TMDbService:
    def __init__(self):
        if not TMDB_KEY:
            raise RuntimeError("TMDB_API_KEY não configurada no .env")

    def search(self, query: str, kind: str):
        url = f"{BASE}/search/{kind}"
        r = requests.get(url, params={"api_key": TMDB_KEY, "language": TMDB_LANG, "query": query}, timeout=20)
        r.raise_for_status()
        data = r.json()
        return data.get("results", [])

    def enrich_movie(self, title: str):
        res = self.search(title, "movie")
        if not res:
            return None
        top = res[0]
        return {
            "tmdb_id": top.get("id"),
            "overview": top.get("overview"),
            "year": (top.get("release_date") or "")[:4],
            "poster_url": IMG + top["poster_path"] if top.get("poster_path") else None,
            "backdrop_url": IMG + top["backdrop_path"] if top.get("backdrop_path") else None,
        }

    def enrich_series(self, title: str):
        res = self.search(title, "tv")
        if not res:
            return None
        top = res[0]
        return {
            "tmdb_id": top.get("id"),
            "overview": top.get("overview"),
            "year": (top.get("first_air_date") or "")[:4],
            "poster_url": IMG + top["poster_path"] if top.get("poster_path") else None,
            "backdrop_url": IMG + top["backdrop_path"] if top.get("backdrop_path") else None,
        }
EOF
)"

  write_file "${APP_DIR}/backend/app/services/scheduler.py" "$(cat <<'EOF'
import os
from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv

load_dotenv()
SCHEDULER_ENABLED = os.getenv("SCHEDULER_ENABLED", "true").lower() == "true"

scheduler = BackgroundScheduler()

def scheduler_startup():
    if not SCHEDULER_ENABLED:
        return
    if not scheduler.running:
        scheduler.start()
EOF
)"

  write_file "${APP_DIR}/backend/app/services/sync_core.py" "$(cat <<'EOF'
from sqlalchemy.orm import Session
from datetime import datetime
from app.models.m3u import ParsedItem
from app.models.sync_log import SyncLog
from app.services.tmdb_service import TMDbService

def run_sync(db: Session, owner_id: int, run_type: str = "manual", only_new: bool = False) -> SyncLog:
    log = SyncLog(owner_id=owner_id, run_type=run_type, status="running", details="")
    db.add(log)
    db.commit()
    db.refresh(log)

    tmdb = TMDbService()
    added = updated = errors = 0
    notes = []

    try:
        items = db.query(ParsedItem).filter(ParsedItem.owner_id == owner_id).all()

        for item in items:
            if only_new and item.tmdb_id is not None:
                continue

            try:
                if item.content_type == "movie":
                    info = tmdb.enrich_movie(item.title)
                elif item.content_type == "series":
                    info = tmdb.enrich_series(item.title)
                else:
                    info = tmdb.enrich_movie(item.title) or tmdb.enrich_series(item.title)

                if info:
                    existed = item.tmdb_id is not None
                    item.tmdb_id = info.get("tmdb_id")
                    item.overview = info.get("overview")
                    item.year = info.get("year")
                    item.poster_url = info.get("poster_url")
                    item.backdrop_url = info.get("backdrop_url")
                    if existed:
                        updated += 1
                    else:
                        added += 1

                db.add(item)
                db.commit()

            except Exception as e:
                errors += 1
                notes.append(f"[ERRO] {item.title}: {str(e)}")
                db.rollback()

        log.status = "done"
        log.added = added
        log.updated = updated
        log.errors = errors
        log.details = "\n".join(notes)[:20000]
        log.finished_at = datetime.utcnow()
        db.add(log)
        db.commit()
        db.refresh(log)
        return log

    except Exception as e:
        log.status = "failed"
        log.details = f"Falha geral: {str(e)}"
        log.finished_at = datetime.utcnow()
        db.add(log)
        db.commit()
        db.refresh(log)
        return log
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/__init__.py" "# package\n"

  write_file "${APP_DIR}/backend/app/routes/auth.py" "$(cat <<'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from app.database.mysql import get_db
from app.models.user import User
from app.utils.security import verify_password
from app.utils.jwt import create_token

router = APIRouter()

class LoginIn(BaseModel):
    email: EmailStr
    password: str

@router.post("/login")
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email, User.is_active == 1).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Credenciais inválidas")

    token = create_token({"user_id": user.id, "role": user.role})
    return {"token": token, "role": user.role, "name": user.name}
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/m3u.py" "$(cat <<'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.database.mysql import get_db
from app.controllers.deps import get_current_user
from app.models.m3u import M3UList, ParsedItem
from app.services.m3u_parser import is_valid_m3u, parse_m3u

router = APIRouter()

class M3UIn(BaseModel):
    raw_text: str

@router.post("/save")
def save_m3u(payload: M3UIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    if not is_valid_m3u(payload.raw_text):
        raise HTTPException(status_code=400, detail="Formato M3U inválido (precisa iniciar com #EXTM3U)")
    m = M3UList(owner_id=user.id, raw_text=payload.raw_text)
    db.add(m)
    db.commit()
    return {"ok": True, "m3u_id": m.id}

@router.post("/scan")
def scan_m3u(db: Session = Depends(get_db), user=Depends(get_current_user)):
    last = db.query(M3UList).filter(M3UList.owner_id == user.id).order_by(M3UList.id.desc()).first()
    if not last:
        raise HTTPException(status_code=404, detail="Nenhuma lista M3U encontrada")

    items = parse_m3u(last.raw_text)
    db.query(ParsedItem).filter(ParsedItem.owner_id == user.id).delete()
    db.commit()

    for it in items:
        db.add(ParsedItem(
            owner_id=user.id,
            content_type=it.get("content_type", "unknown"),
            category=it.get("category", "Sem categoria"),
            title=it.get("title", "Sem título"),
            source_url=it.get("source_url", "")
        ))
    db.commit()

    cats = sorted(list({i["category"] for i in items}))
    return {"ok": True, "total": len(items), "categories": cats}
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/sync.py" "$(cat <<'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.database.mysql import get_db
from app.controllers.deps import get_current_user
from app.services.sync_core import run_sync

router = APIRouter()

@router.post("/manual")
def manual_sync(db: Session = Depends(get_db), user=Depends(get_current_user)):
    log = run_sync(db, owner_id=user.id, run_type="manual", only_new=False)
    return {"ok": True, "log": {"status": log.status, "added": log.added, "updated": log.updated, "errors": log.errors, "details": log.details}}

@router.post("/auto")
def auto_sync(db: Session = Depends(get_db), user=Depends(get_current_user)):
    log = run_sync(db, owner_id=user.id, run_type="auto", only_new=True)
    return {"ok": True, "log": {"status": log.status, "added": log.added, "updated": log.updated, "errors": log.errors}}
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/dashboard.py" "$(cat <<'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.database.mysql import get_db
from app.controllers.deps import get_current_user
from app.models.sync_log import SyncLog

router = APIRouter()

@router.get("/")
def dashboard(db: Session = Depends(get_db), user=Depends(get_current_user)):
    last = db.query(SyncLog).filter(SyncLog.owner_id == user.id).order_by(SyncLog.id.desc()).first()
    return {
        "ok": True,
        "last_sync": None if not last else {
            "status": last.status,
            "run_type": last.run_type,
            "added": last.added,
            "updated": last.updated,
            "errors": last.errors,
            "started_at": str(last.started_at),
            "finished_at": str(last.finished_at) if last.finished_at else None,
        }
    }
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/users.py" "$(cat <<'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from app.database.mysql import get_db
from app.controllers.deps import require_role
from app.models.user import User, Role
from app.utils.security import hash_password

router = APIRouter()

class CreateUserIn(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: Role
    parent_id: int | None = None

@router.post("/create")
def create_user(payload: CreateUserIn, db: Session = Depends(get_db), me=Depends(require_role(Role.ADMIN, Role.RESELLER))):
    if payload.role == Role.ADMIN and me.role != Role.ADMIN:
        raise HTTPException(status_code=403, detail="Apenas admin cria admin")
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=400, detail="Email já existe")

    parent_id = payload.parent_id
    if me.role == Role.RESELLER:
        parent_id = me.id
        if payload.role == Role.ADMIN:
            raise HTTPException(status_code=403, detail="Reseller não cria admin")

    u = User(
        name=payload.name,
        email=payload.email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        parent_id=parent_id
    )
    db.add(u)
    db.commit()
    return {"ok": True, "user_id": u.id}
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/licenses.py" "$(cat <<'EOF'
import secrets
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.database.mysql import get_db
from app.controllers.deps import require_role
from app.models.user import User, Role
from app.models.license import License

router = APIRouter()

class CreateLicenseIn(BaseModel):
    owner_id: int
    plan: str = "pro"
    max_connections: int = 1

@router.post("/create")
def create_license(payload: CreateLicenseIn, db: Session = Depends(get_db), me=Depends(require_role(Role.ADMIN))):
    owner = db.query(User).filter(User.id == payload.owner_id).first()
    if not owner:
        raise HTTPException(status_code=404, detail="Usuário não encontrado")
    key = secrets.token_hex(16)
    lic = License(owner_id=owner.id, key=key, plan=payload.plan, max_connections=payload.max_connections)
    db.add(lic)
    db.commit()
    return {"ok": True, "license_key": key}
EOF
)"

  write_file "${APP_DIR}/backend/app/routes/connections.py" "$(cat <<'EOF'
from fastapi import APIRouter
from pydantic import BaseModel
import pymysql

router = APIRouter()

class ConnIn(BaseModel):
    label: str
    host: str
    port: int = 3306
    db_user: str
    db_password: str
    db_name: str

@router.post("/test")
def test_conn(payload: ConnIn):
    conn = pymysql.connect(
        host=payload.host, port=payload.port,
        user=payload.db_user, password=payload.db_password,
        database=payload.db_name, connect_timeout=5
    )
    conn.close()
    return {"ok": True}
EOF
)"

  write_file "${APP_DIR}/backend/app/seed_admin.py" "$(cat <<EOF
from app.database.mysql import SessionLocal
from app.models.user import User, Role
from app.utils.security import hash_password

db = SessionLocal()
exists = db.query(User).filter(User.email == "${ADMIN_EMAIL}").first()
if not exists:
    admin = User(name="Admin", email="${ADMIN_EMAIL}", password_hash=hash_password("${ADMIN_PASS}"), role=Role.ADMIN)
    db.add(admin)
    db.commit()
    print("Admin criado: ${ADMIN_EMAIL} / ${ADMIN_PASS}")
else:
    print("Admin já existe: ${ADMIN_EMAIL}")
EOF
)"

  # ===== FRONTEND (PHP) =====
  write_file "${APP_DIR}/frontend/config/api.php" "$(cat <<'EOF'
<?php
// Chamamos o backend via localhost porque o PHP roda no mesmo servidor.
// Nginx faz proxy /api -> FastAPI.
return [
  "API_BASE" => "http://127.0.0.1/api"
];
EOF
)"

  write_file "${APP_DIR}/frontend/public/login.php" "$(cat <<'EOF'
<?php
session_start();
$cfg = require __DIR__ . "/../config/api.php";
$msg = "";

if ($_SERVER["REQUEST_METHOD"] === "POST") {
  $email = $_POST["email"] ?? "";
  $pass = $_POST["password"] ?? "";

  $payload = json_encode(["email"=>$email, "password"=>$pass]);
  $ch = curl_init($cfg["API_BASE"]."/auth/login");
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ["Content-Type: application/json"],
    CURLOPT_POSTFIELDS => $payload,
  ]);
  $res = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);

  if ($code === 200) {
    $data = json_decode($res, true);
    $_SESSION["token"] = $data["token"];
    $_SESSION["name"] = $data["name"];
    $_SESSION["role"] = $data["role"];
    header("Location: index.php");
    exit;
  } else {
    $msg = "Login inválido";
  }
}
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Login</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-5" style="max-width:420px;">
  <div class="card shadow-sm">
    <div class="card-body">
      <h4 class="mb-3">Entrar</h4>
      <?php if($msg): ?><div class="alert alert-danger"><?=$msg?></div><?php endif; ?>
      <form method="post">
        <div class="mb-3">
          <label class="form-label">Email</label>
          <input class="form-control" name="email" required>
        </div>
        <div class="mb-3">
          <label class="form-label">Senha</label>
          <input class="form-control" type="password" name="password" required>
        </div>
        <button class="btn btn-dark w-100">Entrar</button>
      </form>
    </div>
  </div>
</div>
</body>
</html>
EOF
)"

  write_file "${APP_DIR}/frontend/public/index.php" "$(cat <<'EOF'
<?php
session_start();
if (!isset($_SESSION["token"])) { header("Location: login.php"); exit; }
$cfg = require __DIR__ . "/../config/api.php";

function api_get($url, $token) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ["Authorization: Bearer ".$token],
  ]);
  $res = curl_exec($ch);
  curl_close($ch);
  return json_decode($res, true);
}

$data = api_get($cfg["API_BASE"]."/dashboard/", $_SESSION["token"]);
$last = $data["last_sync"] ?? null;
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Painel</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<nav class="navbar navbar-dark bg-dark">
  <div class="container">
    <span class="navbar-brand">Sincronizador VOD</span>
    <span class="text-white">Olá, <?=$_SESSION["name"]?> (<?=$_SESSION["role"]?>)</span>
  </div>
</nav>

<div class="container py-4">
  <div class="row g-3">
    <div class="col-md-6">
      <div class="card shadow-sm">
        <div class="card-body">
          <h5>Última sincronização</h5>
          <?php if(!$last): ?>
            <p class="text-muted">Nenhuma ainda.</p>
          <?php else: ?>
            <ul class="mb-0">
              <li>Status: <?=$last["status"]?></li>
              <li>Tipo: <?=$last["run_type"]?></li>
              <li>Adicionados: <?=$last["added"]?></li>
              <li>Atualizados: <?=$last["updated"]?></li>
              <li>Erros: <?=$last["errors"]?></li>
            </ul>
          <?php endif; ?>
          <hr>
          <a class="btn btn-outline-dark me-2" href="m3u.php">Lista M3U</a>
          <a class="btn btn-dark" href="sync.php">Sincronizar</a>
        </div>
      </div>
    </div>
  </div>
</div>
</body>
</html>
EOF
)"

  write_file "${APP_DIR}/frontend/public/m3u.php" "$(cat <<'EOF'
<?php
session_start();
if (!isset($_SESSION["token"])) { header("Location: login.php"); exit; }
$cfg = require __DIR__ . "/../config/api.php";
$msg = "";

function api_post($url, $token, $body) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ["Authorization: Bearer ".$token, "Content-Type: application/json"],
    CURLOPT_POSTFIELDS => json_encode($body),
  ]);
  $res = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  return [$code, json_decode($res, true)];
}

if ($_SERVER["REQUEST_METHOD"] === "POST") {
  $raw = $_POST["raw"] ?? "";
  [$code, $res] = api_post($cfg["API_BASE"]."/m3u/save", $_SESSION["token"], ["raw_text"=>$raw]);
  $msg = ($code===200) ? "Lista salva com sucesso." : ("Erro: ".($res["detail"] ?? "falha"));
}
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>M3U</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
  <a href="index.php" class="btn btn-link">&larr; Voltar</a>
  <div class="card shadow-sm">
    <div class="card-body">
      <h5>Inserir lista M3U</h5>
      <?php if($msg): ?><div class="alert alert-info"><?=$msg?></div><?php endif; ?>
      <form method="post">
        <textarea class="form-control" rows="12" name="raw" placeholder="#EXTM3U ..." required></textarea>
        <button class="btn btn-dark mt-3">Salvar</button>
      </form>
      <hr>
      <form method="post" action="scan.php">
        <button class="btn btn-outline-dark">Escanear Lista</button>
      </form>
    </div>
  </div>
</div>
</body>
</html>
EOF
)"

  write_file "${APP_DIR}/frontend/public/scan.php" "$(cat <<'EOF'
<?php
session_start();
if (!isset($_SESSION["token"])) { header("Location: login.php"); exit; }
$cfg = require __DIR__ . "/../config/api.php";

$ch = curl_init($cfg["API_BASE"]."/m3u/scan");
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_POST => true,
  CURLOPT_HTTPHEADER => ["Authorization: Bearer ".$_SESSION["token"]],
]);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$data = json_decode($res, true);
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Scan</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
  <a href="m3u.php" class="btn btn-link">&larr; Voltar</a>
  <div class="card shadow-sm">
    <div class="card-body">
      <h5>Resultado do Scanner</h5>
      <?php if($code!==200): ?>
        <div class="alert alert-danger">Erro: <?=$data["detail"] ?? "falha"?></div>
      <?php else: ?>
        <div class="alert alert-success">Itens: <?=$data["total"]?></div>
        <p class="mb-1"><b>Categorias encontradas:</b></p>
        <ul>
          <?php foreach($data["categories"] as $c): ?>
            <li><?=htmlspecialchars($c)?></li>
          <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </div>
  </div>
</div>
</body>
</html>
EOF
)"

  write_file "${APP_DIR}/frontend/public/sync.php" "$(cat <<'EOF'
<?php
session_start();
if (!isset($_SESSION["token"])) { header("Location: login.php"); exit; }
$cfg = require __DIR__ . "/../config/api.php";
$msg = "";
$log = null;

function api_post($url, $token) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ["Authorization: Bearer ".$token],
  ]);
  $res = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  return [$code, json_decode($res, true)];
}

if ($_SERVER["REQUEST_METHOD"] === "POST") {
  [$code, $res] = api_post($cfg["API_BASE"]."/sync/manual", $_SESSION["token"]);
  if ($code===200) {
    $msg = "Sincronização concluída.";
    $log = $res["log"];
  } else {
    $msg = "Falha ao sincronizar.";
  }
}
?>
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Sincronizar</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
  <a href="index.php" class="btn btn-link">&larr; Voltar</a>
  <div class="card shadow-sm">
    <div class="card-body">
      <h5>Sincronização Manual</h5>
      <?php if($msg): ?><div class="alert alert-info"><?=$msg?></div><?php endif; ?>
      <form method="post">
        <button class="btn btn-dark">Executar</button>
      </form>

      <?php if($log): ?>
        <hr>
        <h6>Resumo</h6>
        <ul>
          <li>Status: <?=$log["status"]?></li>
          <li>Adicionados: <?=$log["added"]?></li>
          <li>Atualizados: <?=$log["updated"]?></li>
          <li>Erros: <?=$log["errors"]?></li>
        </ul>
        <?php if(!empty($log["details"])): ?>
          <pre style="white-space:pre-wrap;"><?=$log["details"]?></pre>
        <?php endif; ?>
      <?php endif; ?>
    </div>
  </div>
</div>
</body>
</html>
EOF
)"

  log "Arquivos do projeto criados em ${APP_DIR}"
}

import_schema(){
  mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" "${MYSQL_DB}" < "${APP_DIR}/schema.sql" || true
  log "schema.sql importado (se já existia, não quebrou)"
}

backend_setup(){
  cd "${APP_DIR}/backend"

  python3 -m venv venv
  source venv/bin/activate
  pip3 install --upgrade pip
  pip3 install -r requirements.txt

  # Seed admin
  python -m app.seed_admin || true

  deactivate
  log "Backend preparado (venv + deps + seed admin)"
}

systemd_setup(){
  cat > /etc/systemd/system/vodsync-backend.service <<EOF
[Unit]
Description=VODSync Backend (FastAPI)
After=network.target mysql.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}/backend
Environment=PYTHONUNBUFFERED=1
ExecStart=${APP_DIR}/backend/venv/bin/uvicorn app.main:app --host ${BACKEND_HOST} --port ${BACKEND_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now vodsync-backend.service
  log "systemd: vodsync-backend.service ativo"
}

nginx_setup(){
  # PHP-FPM socket (Ubuntu 20 geralmente é php7.4-fpm)
  PHP_SOCK="/run/php/php7.4-fpm.sock"
  if [[ ! -S "${PHP_SOCK}" ]]; then
    warn "Socket php7.4-fpm não encontrado em ${PHP_SOCK}. Tentando detectar..."
    PHP_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1 || true)"
    [[ -n "${PHP_SOCK}" ]] || die "Não encontrei socket do php-fpm em /run/php/"
  fi

  mkdir -p /var/www/vodsync
  rsync -a --delete "${APP_DIR}/frontend/public/" /var/www/vodsync/
  chown -R www-data:www-data /var/www/vodsync

  # Nginx server block
  cat > /etc/nginx/sites-available/vodsync <<EOF
server {
  listen 80;
  server_name ${SERVER_NAME};

  root /var/www/vodsync;
  index index.php index.html;

  # Painel
  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  # PHP
  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:${PHP_SOCK};
  }

  # API -> FastAPI
  location /api/ {
    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT}/api/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

  ln -sf /etc/nginx/sites-available/vodsync /etc/nginx/sites-enabled/vodsync
  rm -f /etc/nginx/sites-enabled/default || true

  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  log "Nginx configurado: / (painel PHP) e /api (backend)"
}

final_info(){
  local ip
  ip="$(curl -s ifconfig.me || true)"
  echo
  echo "==============================================="
  echo "INSTALAÇÃO CONCLUÍDA"
  echo "==============================================="
  echo "Painel:   http://${ip:-SEU_IP}/"
  echo "API:      http://${ip:-SEU_IP}/api/"
  echo
  echo "Admin:    ${ADMIN_EMAIL} / ${ADMIN_PASS}"
  echo
  echo "Serviço:  systemctl status vodsync-backend.service"
  echo "Logs:     journalctl -u vodsync-backend.service -f"
  echo
  echo "Nginx:    systemctl status nginx"
  echo "==============================================="
  echo
  warn "Troque ADMIN_PASS e JWT_SECRET depois. Em produto premium isso é obrigatório."
}

#############################################
# MAIN
#############################################
need_root
apt_install
ensure_user
mysql_setup
create_project_tree

# Permissões
chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"

import_schema
backend_setup
systemd_setup
nginx_setup
final_info
