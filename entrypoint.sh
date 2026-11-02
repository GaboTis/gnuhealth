#!/usr/bin/env bash
# Entrypoint de GNU Health / Tryton
# 1) Escribe trytond.conf con los valores del entorno
# 2) Espera a PostgreSQL
# 3) Crea/inicializa la base de datos (primera vez: todos los módulos)
# 4) Arranca trytond en primer plano
set -euo pipefail

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-gnuhealth}"
DB_PASSWORD="${DB_PASSWORD:?Falta DB_PASSWORD}"
DB_NAME="${DB_NAME:-gnuhealth}"
TRYTON_ADMIN_PASSWORD="${TRYTON_ADMIN_PASSWORD:?Falta TRYTON_ADMIN_PASSWORD}"
TRYTON_ADMIN_EMAIL="${TRYTON_ADMIN_EMAIL:-admin@example.com}"

CONF=/etc/gnuhealth/trytond.conf

mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<EOF
[database]
uri = postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/
path = /var/lib/gnuhealth

[web]
listen = 0.0.0.0:8000
root = /usr/share/tryton-sao/www
num_proxies = 1

[session]
timeout = 7200
EOF

echo "==> Esperando a PostgreSQL en ${DB_HOST}:${DB_PORT} ..."
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
    sleep 2
done
echo "==> PostgreSQL listo."

# 1) Crear la base si no existe (el usuario POSTGRES_USER es superusuario).
PGURI_ADMIN="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/postgres"
if [ "$(psql "$PGURI_ADMIN" -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'")" != "1" ]; then
    echo "==> Creando la base de datos '${DB_NAME}'..."
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
fi

# 2) Inicializar (primera vez) o actualizar (reinicios posteriores).
#    Flujo oficial de GNU Health (gnuhealth-control):
#    init base -> módulo 'health' + dependencias -> países -> monedas
PGURI_DB="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

HAS_TABLES="$(psql "$PGURI_DB" -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' LIMIT 1" 2>/dev/null || true)"

if [ "$HAS_TABLES" != "1" ]; then
    echo "==> [1/4] Inicializando la base '${DB_NAME}' (módulos base)..."
    # trytond-admin (Tryton 7.0) lee la contraseña del admin desde TRYTONPASSFILE
    # durante la inicialización; sin esta variable pediría la clave por teclado.
    printf '%s\n' "$TRYTON_ADMIN_PASSWORD" > /tmp/gh-admin-pass
    export TRYTONPASSFILE=/tmp/gh-admin-pass
    trytond-admin -c "$CONF" -d "$DB_NAME" --all --email "$TRYTON_ADMIN_EMAIL" -vv
    unset TRYTONPASSFILE
    rm -f /tmp/gh-admin-pass
    echo "==> [1/4] Base inicializada. Usuario administrador: 'admin'."
fi

HEALTH_STATE="$(psql "$PGURI_DB" -tAc "SELECT state FROM ir_module WHERE name = 'health';" 2>/dev/null || true)"
if [ "$HEALTH_STATE" != "activated" ]; then
    echo "==> [2/4] Instalando módulo 'health' (núcleo GNU Health) y dependencias (tarda varios minutos)..."
    trytond-admin -c "$CONF" -d "$DB_NAME" --update health --activate-dependencies -vv
    echo "==> [3/4] Importando países..."
    trytond_import_countries -c "$CONF" -d "$DB_NAME"
    echo "==> [4/4] Importando monedas..."
    trytond_import_currencies -c "$CONF" -d "$DB_NAME"
    echo "==> GNU Health instalado en la base '${DB_NAME}'."
else
    echo "==> La base '${DB_NAME}' ya está inicializada; actualizando módulos..."
    trytond-admin -c "$CONF" -d "$DB_NAME" --all -vv || true
fi

echo "==> Arrancando trytond en 0.0.0.0:8000 ..."
exec trytond -c "$CONF"
