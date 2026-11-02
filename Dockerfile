# GNU Health HMIS 5.0.6 (Hospital Information System) sobre Tryton 7.0
# Imagen lista para desplegar en Coolify (o cualquier host con Docker).
#
# Componentes:
#   - GNU Health core 5.0.6 + los ~50 módulos (gnuhealth-all-modules)
#   - Tryton server 7.0.x
#   - Cliente web SAO 7.0.56 (precompilado, desde el paquete Debian)
#   - PostgreSQL se ejecuta como contenedor hermano (ver docker-compose.yml)

FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Herramientas mínimas: curl (descargas + healthcheck), cliente PostgreSQL
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------
# GNU Health 5.0: core + todos los módulos + Tryton 7.0
# gnuhealth-all-modules arrastra trytond, proteus, psycopg2 y
# todos los módulos gnuhealth-* (~50).
# psycopg2 se compila desde fuentes (libpq-dev + gcc) porque no
# publica wheels de Linux para Python 3.12; se purgan después.
# ---------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && pip install --no-cache-dir \
        "gnuhealth==5.0.6" \
        "gnuhealth-all-modules==5.0.4" \
    && apt-get purge -y --auto-remove build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------
# Cliente web SAO (Tryton SAO) 7.0.56 precompilado.
# Lo tomamos del paquete Debian (sid): ya trae dist/, index.html,
# bower_components y locales en /usr/share/tryton-sao/www, así no
# hace falta nodejs/npm en la imagen.
# ---------------------------------------------------------------
ARG SAO_DEB_URL=http://deb.debian.org/debian/pool/main/t/tryton-sao/tryton-sao_7.0.56+ds1-1_all.deb
RUN curl -fsSL -o /tmp/tryton-sao.deb "${SAO_DEB_URL}" \
    && dpkg-deb -x /tmp/tryton-sao.deb / \
    && rm -f /tmp/tryton-sao.deb

# Directorio de datos de trytond (adjuntos/archivos de la DB)
RUN mkdir -p /var/lib/gnuhealth

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=20 \
    CMD curl -fsS http://127.0.0.1:8000/ >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
