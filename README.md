# GNU Health HMIS 5.0 en Coolify

Despliegue del **Sistema de Información Hospitalaria GNU Health 5.0.6** en
[Coolify](https://coolify.io) mediante Docker Compose.

Incluye:

| Componente                | Versión                          |
|---------------------------|----------------------------------|
| GNU Health (HMIS)         | 5.0.6 (módulo `health` + dependencias activados; ~50 módulos adicionales instalados y activables desde el cliente) |
| Tryton (servidor)         | 7.0.x                            |
| SAO (cliente web)         | 7.0.56                           |
| PostgreSQL                | 16                               |

> **Sí, se puede desplegar en Coolify.** Coolify soporta recursos
> "Docker Compose" nativamente: levanta el stack, le pone dominio y HTTPS con
> Let's Encrypt, y gestiona backups y logs.
>
> La imagen oficial de GNU Health en Docker Hub (`gnuhealth/his`) está
> archivada, por eso este repo construye su propia imagen a partir de los
> paquetes oficiales de PyPI ([gnuhealth](https://pypi.org/project/gnuhealth/),
> [gnuhealth-all-modules](https://pypi.org/project/gnuhealth-all-modules/)) y
> del cliente web SAO empaquetado por Debian.

---

## 1. Preparar el repositorio

1. Crea un repositorio **privado** en GitHub / GitLab / Codeberg.
2. Sube estos archivos:

   ```
   Dockerfile
   docker-compose.yml
   entrypoint.sh
   .env.example
   .gitignore
   README.md
   ```

   > **No** subas `.env` ni contraseñas reales al repositorio.

---

## 2. Crear el recurso en Coolify

1. En Coolify: **Projects → + New → Resource**.
2. Elige **Docker Compose**.
3. Selecciona el repositorio y la rama que subiste.
4. Build Pack: **Docker Compose** (se detecta solo con `docker-compose.yml`).
5. Pestaña **Environment Variables** → agrega las siguientes variables
   (usa contraseñas fuertes, distintas entre sí):

   | Variable                | Valor                                   |
   |-------------------------|-----------------------------------------|
   | `DB_USER`               | `gnuhealth`                             |
   | `DB_PASSWORD`           | clave fuerte (PostgreSQL)               |
   | `DB_NAME`               | `gnuhealth`                             |
   | `TRYTON_ADMIN_PASSWORD` | clave fuerte (usuario `admin` del HIS)  |
   | `TRYTON_ADMIN_EMAIL`    | tu@correo.com                           |

6. **Domains**: agrega tu dominio (ej. `salud.midominio.com`) y, al elegir el
   servicio, selecciona `gnuhealth` con puerto `8000`. Asegúrate de que el
   registro DNS del dominio apunte a la IP del servidor Coolify.
7. Guarda y pulsa **Deploy**.

### ¿Sin dominio?

Si solo tienes una IP, quita el mapeo de dominios y expón el puerto:
en el recurso → **Ports Mappings** agrega `8000 → 8000` y abre ese puerto en el
firewall del servidor. Luego accede a `http://IP-DEL-SERVIDOR:8000`.
(No recomendado para datos clínicos: usa HTTPS.)

---

## 3. Primer arranque (importante)

- El **build** tarda entre 5 y 15 minutos (instala GNU Health, Tryton y ~50
  módulos desde PyPI).
- Después, el contenedor `gnuhealth` inicializa la base en 4 pasos
  (visible en los logs): [1/4] módulos base → [2/4] módulo `health` y
  dependencias → [3/4] países → [4/4] monedas. Son varios minutos más.
- En reinicios posteriores detecta que la base ya está inicializada y solo
  actualiza módulos (arranca en ~1 minuto).
- Sigue el progreso en **Logs** del recurso hasta ver
  `==> Arrancando trytond en 0.0.0.0:8000 ...`.

## 4. Acceder

- URL: `https://salud.midominio.com` (la que definiste).
- Usuario: **`admin`**
- Contraseña: la de `TRYTON_ADMIN_PASSWORD`.

> Los demás módulos de GNU Health (laboratorio, enfermería, UCI,
> pediatría, cirugía, imágenes, genética, etc.) ya están instalados en la
> imagen; actívalos desde el cliente web en
> **Administración → Modelos → Modelos** o vía
> `trytond-admin -d gnuhealth --update health_lab --activate-dependencies`
> (reemplazando `health_lab` por el módulo deseado).

---

## Prueba local (opcional)

```bash
cp .env.example .env   # editar contraseñas
docker compose up -d --build
# abrir http://localhost:8000  (usuario: admin)
```

---

## Notas de operación

- **Backups**: usa los backups automáticos de Coolify; incluyen los volúmenes
  `db-data` (PostgreSQL) y `gh-data` (adjuntos del HIS). También puedes
  automatizar `trytond-admin -d gnuhealth --all -c /etc/gnuhealth/trytond.conf`
  o `pg_dump` dentro del contenedor.
- **Actualizaciones**: cambiar las versiones pineadas en el `Dockerfile`
  (GNU Health publica patchsets periódicos) y re-desplegar. El entrypoint
  ejecuta `trytond-admin --all` para migrar el esquema automáticamente.
  **Haz backup antes de cada actualización.**
- **Seguridad**: son datos de salud. Usa siempre HTTPS, contraseñas fuertes,
  2FA de Coolify y restringe el acceso (firewall/Cloudflare). No expongas el
  puerto 5432 del contenedor `db`.
- **Extras opcionales**:
  - *Thalamus* (servidor de mensajería de la federación GNU Health): otro
    servicio/stack aparte.
  - *Orthanc* (PACS DICOM para el módulo de imágenes): contenedor adicional
    `osimis/orthanc` + módulo `gnuhealth-imaging`.
  - *Demo data*: consulta https://docs.gnuhealth.org/his/techguide/demodb.html
  - *Cliente de escritorio/móvil (MyGNUHealth / GNU Health Client)*: usa el
    protocolo WebDAV del módulo `gnuhealth-webdav3-server` (ya incluido) sobre
    el mismo puerto.
- **Soporte**: https://www.gnuhealth.org (listas de correo, Matrix) y
  documentación https://docs.gnuhealth.org

## Créditos

GNU Health es software libre (GPLv3+) de GNU Solidario:
https://www.gnuhealth.org — este repositorio solo empaqueta el despliegue.
