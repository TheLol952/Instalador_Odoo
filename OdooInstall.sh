#!/usr/bin/env bash
set -euo pipefail

echo "==== Instalador de Odoo único por entorno Docker + Compose v2 ===="

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sudo_keep_alive() {
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

dbify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//'
}

random_password() {
  if need_cmd openssl; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
  else
    date +%s%N | sha256sum | head -c 24
  fi
}

port_in_use() {
  local port="$1"

  if need_cmd ss; then
    ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"
  else
    return 1
  fi
}

next_free_port() {
  local port="$1"

  while port_in_use "$port"; do
    port=$((port + 1))
  done

  echo "$port"
}

if ! need_cmd apt-get; then
  echo "Este instalador está pensado para Ubuntu/Debian con apt."
  exit 1
fi

sudo_keep_alive

# ------------------------
# Carpeta raíz del instalador
# ------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
read -rp "Nombre de la carpeta del entorno, ej: venecia-odoo-enterprise: " PROJECT_FOLDER_NAME

if [ -z "$PROJECT_FOLDER_NAME" ]; then
  echo "Debes ingresar un nombre de carpeta."
  exit 1
fi

PROJECT_FOLDER_NAME="$(slugify "$PROJECT_FOLDER_NAME")"
PROJECT_ROOT="${SCRIPT_DIR}/${PROJECT_FOLDER_NAME}"

echo ""
echo ">> El entorno se instalará en:"
echo "   ${PROJECT_ROOT}"
echo ""

mkdir -p "${PROJECT_ROOT}"
cd "${PROJECT_ROOT}"

# ------------------------
# Dependencias base
# ------------------------
echo ">> Instalando dependencias base..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release git openssl iproute2

# ------------------------
# Preguntas al usuario
# ------------------------
read -rp "¿Qué versión de Odoo querés instalar? [19.0]: " ODOO_VERSION
ODOO_VERSION="${ODOO_VERSION:-19.0}"

echo ""
echo "Selecciona edición:"
echo "  1) Community"
echo "  2) Enterprise"
read -rp "Opción [1/2] [1]: " EDITION
EDITION="${EDITION:-1}"

case "$EDITION" in
  1) EDITION_NAME="community" ;;
  2) EDITION_NAME="enterprise" ;;
  *) echo "Opción inválida: $EDITION"; exit 1 ;;
esac

echo ""
read -rp "Nombre único interno del entorno para Docker [${PROJECT_FOLDER_NAME}]: " PROJECT_SLUG
PROJECT_SLUG="${PROJECT_SLUG:-$PROJECT_FOLDER_NAME}"
PROJECT_SLUG="$(slugify "$PROJECT_SLUG")"

DEFAULT_DB_NAME="$(dbify "$PROJECT_SLUG")"
read -rp "Nombre de la base de datos inicial [${DEFAULT_DB_NAME}]: " ODOO_DB_NAME
ODOO_DB_NAME="${ODOO_DB_NAME:-$DEFAULT_DB_NAME}"
ODOO_DB_NAME="$(dbify "$ODOO_DB_NAME")"

DEFAULT_DB_USER="odoo_$(dbify "$PROJECT_SLUG")"
read -rp "Usuario PostgreSQL/Odoo DB [${DEFAULT_DB_USER}]: " ODOO_DB_USER
ODOO_DB_USER="${ODOO_DB_USER:-$DEFAULT_DB_USER}"
ODOO_DB_USER="$(dbify "$ODOO_DB_USER")"

echo ""
read -rsp "Contraseña PostgreSQL/Odoo DB [auto-generar]: " ODOO_DB_PASSWORD
echo ""
if [ -z "$ODOO_DB_PASSWORD" ]; then
  ODOO_DB_PASSWORD="$(random_password)"
fi

DEFAULT_ODOO_PORT="$(next_free_port 8069)"
read -rp "Puerto HTTP externo para Odoo [${DEFAULT_ODOO_PORT}]: " ODOO_HOST_PORT
ODOO_HOST_PORT="${ODOO_HOST_PORT:-$DEFAULT_ODOO_PORT}"

DEFAULT_POSTGRES_PORT="$(next_free_port 5432)"
read -rp "Puerto PostgreSQL externo [${DEFAULT_POSTGRES_PORT}]: " POSTGRES_HOST_PORT
POSTGRES_HOST_PORT="${POSTGRES_HOST_PORT:-$DEFAULT_POSTGRES_PORT}"

read -rp "Usuario administrador interno inicial de Odoo [admin]: " ODOO_ADMIN_LOGIN
ODOO_ADMIN_LOGIN="${ODOO_ADMIN_LOGIN:-admin}"

read -rsp "Contraseña administrador interno inicial de Odoo [auto-generar]: " ODOO_ADMIN_PASSWORD
echo ""
if [ -z "$ODOO_ADMIN_PASSWORD" ]; then
  ODOO_ADMIN_PASSWORD="$(random_password)"
fi

read -rsp "Master password de Odoo Database Manager [auto-generar]: " ODOO_MASTER_PASSWORD
echo ""
if [ -z "$ODOO_MASTER_PASSWORD" ]; then
  ODOO_MASTER_PASSWORD="$(random_password)"
fi

echo ""
read -rp "¿Este Odoo utilizará varias bases de datos? [s/N]: " MULTI_DB_OPTION
MULTI_DB_OPTION="${MULTI_DB_OPTION:-n}"

case "$MULTI_DB_OPTION" in
  s|S|si|SI|sí|SÍ|y|Y|yes|YES)
    ODOO_MULTI_DB="true"
    ODOO_LIST_DB="True"
    ODOO_DBFILTER=".*"
    ;;
  *)
    ODOO_MULTI_DB="false"
    ODOO_LIST_DB="False"
    ODOO_DBFILTER="^${ODOO_DB_NAME}$"
    ;;
esac

# ------------------------
# Instalar Docker + Compose v2
# ------------------------
echo ""
echo ">> Instalando/actualizando Docker repo oficial + Compose v2..."

sudo install -m 0755 -d /etc/apt/keyrings

. /etc/os-release

if [ "${ID}" != "ubuntu" ] && [ "${ID}" != "debian" ]; then
  echo "Sistema detectado: ${ID}. Este script solo soporta Ubuntu/Debian."
  exit 1
fi

DOCKER_GPG="/etc/apt/keyrings/docker.gpg"

if [ ! -f "$DOCKER_GPG" ]; then
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | sudo gpg --dearmor -o "$DOCKER_GPG"
  sudo chmod a+r "$DOCKER_GPG"
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="${VERSION_CODENAME:-$(lsb_release -cs)}"

echo "deb [arch=${ARCH} signed-by=${DOCKER_GPG}] https://download.docker.com/linux/${ID} ${CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ""
echo ">> Versiones instaladas:"
docker --version || true
docker compose version || true

echo ""
echo ">> Verificando que Docker esté iniciado..."

if ! sudo docker info >/dev/null 2>&1; then
  echo "   Docker no está activo. Intentando iniciar Docker..."

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl start docker || true
    sudo systemctl enable docker || true
  fi

  if ! sudo docker info >/dev/null 2>&1; then
    sudo service docker start || true
  fi
fi

if ! sudo docker info >/dev/null 2>&1; then
  echo ""
  echo "❌ Docker está instalado, pero el daemon no está corriendo."
  echo ""
  echo "Si estás en WSL, abre Docker Desktop en Windows y activa:"
  echo "Settings > Resources > WSL Integration > Ubuntu-24.04"
  echo ""
  echo "Luego vuelve a ejecutar:"
  echo "sudo docker compose up -d --build"
  exit 1
fi

echo "   Docker está activo."

# ------------------------
# Crear estructura del proyecto
# ------------------------
echo ""
echo ">> Creando estructura en:"
echo "   ${PROJECT_ROOT}"

mkdir -p config scripts enterprise

# ------------------------
# Clonar Odoo Core
# ------------------------
if [ ! -d "${PROJECT_ROOT}/odoo/.git" ]; then
  echo ">> Clonando Odoo Core rama ${ODOO_VERSION}..."
  git clone https://github.com/odoo/odoo.git -b "${ODOO_VERSION}" --depth=1 odoo
else
  echo "   - Ya existe ./odoo, omitiendo clone."
fi

# ------------------------
# Clonar Enterprise si aplica
# ------------------------
if [ "$EDITION" = "2" ]; then
  echo ""
  echo ">> Enterprise seleccionado."
  read -rp "GitHub user con acceso a odoo/enterprise: " GITHUB_USER
  read -rsp "GitHub token, no se mostrará: " GITHUB_TOKEN
  echo ""

  if [ -z "${GITHUB_USER}" ] || [ -z "${GITHUB_TOKEN}" ]; then
    echo "Faltan credenciales para clonar Enterprise."
    exit 1
  fi

  if [ ! -d "${PROJECT_ROOT}/enterprise/.git" ]; then
    echo ">> Clonando Odoo Enterprise rama ${ODOO_VERSION}..."
    rm -rf enterprise
    git clone -b "${ODOO_VERSION}" --depth=1 "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/odoo/enterprise.git" enterprise

    # Evita dejar el token guardado en el remote
    git -C enterprise remote set-url origin "https://github.com/odoo/enterprise.git"
  else
    echo "   - Ya existe ./enterprise, omitiendo clone."
  fi
else
  echo ">> Community seleccionado. La carpeta enterprise queda vacía."
fi

# ------------------------
# Archivo .env
# ------------------------
echo ""
echo ">> Creando .env..."

cat > .env <<EOF
COMPOSE_PROJECT_NAME=${PROJECT_SLUG}
PROJECT_SLUG=${PROJECT_SLUG}
ODOO_VERSION=${ODOO_VERSION}
ODOO_DB_NAME=${ODOO_DB_NAME}
ODOO_DB_USER=${ODOO_DB_USER}
ODOO_DB_PASSWORD=${ODOO_DB_PASSWORD}
ODOO_HOST_PORT=${ODOO_HOST_PORT}
POSTGRES_HOST_PORT=${POSTGRES_HOST_PORT}
ODOO_ADMIN_LOGIN=${ODOO_ADMIN_LOGIN}
ODOO_ADMIN_PASSWORD=${ODOO_ADMIN_PASSWORD}
ODOO_MASTER_PASSWORD=${ODOO_MASTER_PASSWORD}
ODOO_MULTI_DB=${ODOO_MULTI_DB}
EOF

chmod 600 .env

# ------------------------
# Dockerfile actualizado
# ------------------------
echo ">> Creando Dockerfile..."

cat > Dockerfile <<EOF
FROM odoo:${ODOO_VERSION}

USER root

RUN apt-get update && apt-get install -y \\
        python3-pip \\
        unrar-free \\
        libarchive-tools \\
        sed \\
    && pip install --break-system-packages \\
        PyJWT \\
        cryptography \\
        xmltodict \\
        rarfile \\
        py7zr \\
        psycopg2-binary \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*

# Parchear el DEFAULT_MAX_CONTENT_LENGTH de Odoo a 1 GB
RUN sed -i 's/DEFAULT_MAX_CONTENT_LENGTH = 128 \\* 1024 \\* 1024/DEFAULT_MAX_CONTENT_LENGTH = 1073741824/' /usr/lib/python3/dist-packages/odoo/http.py

USER odoo
EOF

# ------------------------
# Configuración de Odoo
# ------------------------
echo ">> Creando config/odoo.conf..."

cat > config/odoo.conf <<EOF
[options]
admin_passwd = ${ODOO_MASTER_PASSWORD}

db_host = db
db_port = 5432
db_user = ${ODOO_DB_USER}
db_password = ${ODOO_DB_PASSWORD}
EOF

if [ "$ODOO_MULTI_DB" = "false" ]; then
  cat >> config/odoo.conf <<EOF
db_name = ${ODOO_DB_NAME}
dbfilter = ${ODOO_DBFILTER}
EOF
else
  cat >> config/odoo.conf <<EOF
dbfilter = ${ODOO_DBFILTER}
EOF
fi

cat >> config/odoo.conf <<EOF

addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/enterprise-addons,/mnt/custom-addons
data_dir = /var/lib/odoo

http_interface = 0.0.0.0
http_port = 8069

proxy_mode = False
list_db = ${ODOO_LIST_DB}
without_demo = all

limit_time_cpu = 0
limit_time_real = 0
log_level = info
EOF

chmod 644 config/odoo.conf

# ------------------------
# Script inicializador de DB Odoo
# ------------------------
echo ">> Creando scripts/init-odoo-db.sh..."

cat > scripts/init-odoo-db.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo ">> Verificando si la base Odoo '${ODOO_DB_NAME}' ya está inicializada..."

if python3 <<'PY'
import os
import sys
import psycopg2

try:
    conn = psycopg2.connect(
        host=os.environ["HOST"],
        dbname=os.environ["ODOO_DB_NAME"],
        user=os.environ["USER"],
        password=os.environ["PASSWORD"],
    )
    cur = conn.cursor()
    cur.execute("SELECT to_regclass('public.ir_module_module')")
    initialized = cur.fetchone()[0] is not None
    cur.close()
    conn.close()
    sys.exit(0 if initialized else 1)
except Exception:
    sys.exit(1)
PY
then
  echo ">> La base '${ODOO_DB_NAME}' ya está inicializada. No se reinstala base."
  exit 0
fi

echo ">> Inicializando base Odoo '${ODOO_DB_NAME}' con módulo base..."

odoo -c /etc/odoo/odoo.conf \
  -d "${ODOO_DB_NAME}" \
  -i base \
  --without-demo=all \
  --stop-after-init

echo ">> Configurando usuario administrador interno de Odoo..."

odoo shell -c /etc/odoo/odoo.conf -d "${ODOO_DB_NAME}" <<'PY'
import os

admin = env.ref('base.user_admin', raise_if_not_found=False)

if admin:
    admin.write({
        'login': os.environ.get('ODOO_ADMIN_LOGIN', 'admin'),
        'password': os.environ['ODOO_ADMIN_PASSWORD'],
    })
    env.cr.commit()
PY

echo ">> Base inicializada correctamente."
EOF

chmod +x scripts/init-odoo-db.sh

# ------------------------
# docker-compose.yml
# ------------------------
echo ">> Creando docker-compose.yml..."

cat > docker-compose.yml <<'EOF'
services:
  db:
    image: postgres:15
    container_name: "${PROJECT_SLUG}-db"
    restart: unless-stopped
    environment:
      POSTGRES_DB: "${ODOO_DB_NAME}"
      POSTGRES_USER: "${ODOO_DB_USER}"
      POSTGRES_PASSWORD: "${ODOO_DB_PASSWORD}"
    volumes:
      - db-data:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_HOST_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER}\" -d \"$${POSTGRES_DB}\""]
      interval: 10s
      timeout: 5s
      retries: 10

  odoo-init:
    build: .
    container_name: "${PROJECT_SLUG}-init"
    restart: "no"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - web-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf:ro
      - ./enterprise:/mnt/enterprise-addons
      - ./odoo/addons:/mnt/custom-addons
      - ./scripts/init-odoo-db.sh:/usr/local/bin/init-odoo-db.sh:ro
    environment:
      HOST: db
      USER: "${ODOO_DB_USER}"
      PASSWORD: "${ODOO_DB_PASSWORD}"
      ODOO_DB_NAME: "${ODOO_DB_NAME}"
      ODOO_ADMIN_LOGIN: "${ODOO_ADMIN_LOGIN}"
      ODOO_ADMIN_PASSWORD: "${ODOO_ADMIN_PASSWORD}"
    command: ["bash", "/usr/local/bin/init-odoo-db.sh"]

  web:
    build: .
    container_name: "${PROJECT_SLUG}-web"
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      odoo-init:
        condition: service_completed_successfully
    ports:
      - "${ODOO_HOST_PORT}:8069"
    volumes:
      - web-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf:ro
      - ./enterprise:/mnt/enterprise-addons
      - ./odoo/addons:/mnt/custom-addons
    environment:
      HOST: db
      USER: "${ODOO_DB_USER}"
      PASSWORD: "${ODOO_DB_PASSWORD}"
      ODOO_DB_NAME: "${ODOO_DB_NAME}"
    command:
      - odoo
      - -c
      - /etc/odoo/odoo.conf
EOF

if [ "$ODOO_MULTI_DB" = "false" ]; then
  cat >> docker-compose.yml <<'EOF'
      - -d
      - "${ODOO_DB_NAME}"
EOF
fi

cat >> docker-compose.yml <<'EOF'

volumes:
  db-data:
    name: "${PROJECT_SLUG}-db-data"
  web-data:
    name: "${PROJECT_SLUG}-web-data"
EOF

# ------------------------
# Levantar entorno
# ------------------------
echo ""
echo ">> Levantando servicios..."

sudo docker compose -f docker-compose.yml up -d --build

echo ""
echo "✅ Listo."
echo "   Entorno: ${PROJECT_SLUG}"
echo "   Carpeta: ${PROJECT_ROOT}"
echo "   Odoo:    http://localhost:${ODOO_HOST_PORT}"
echo "   DB inicial: ${ODOO_DB_NAME}"
echo "   Multi DB:   ${ODOO_MULTI_DB}"
echo "   Usuario interno Odoo inicial: ${ODOO_ADMIN_LOGIN}"

if [ "$ODOO_MULTI_DB" = "true" ]; then
  echo "   Database Manager: http://localhost:${ODOO_HOST_PORT}/web/database/manager"
fi

echo ""
echo "Las contraseñas quedaron guardadas en:"
echo "   ${PROJECT_ROOT}/.env"
echo "   ${PROJECT_ROOT}/config/odoo.conf"
echo ""
echo "Comandos útiles:"
echo "   cd ${PROJECT_ROOT}"
echo "   sudo docker compose ps"
echo "   sudo docker compose logs -f web"
echo "   sudo docker compose logs -f odoo-init"