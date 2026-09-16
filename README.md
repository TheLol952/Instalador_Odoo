# Instalador de Odoo con Docker

Este repositorio contiene un instalador interactivo para crear entornos de Odoo Community o Enterprise usando Docker y Docker Compose v2.

## Requisitos

- Ubuntu o Debian con `apt`
- Acceso a `sudo`
- Conexión a Internet
- Para Odoo Enterprise, una cuenta y un token de GitHub con acceso al repositorio privado `odoo/enterprise`

## Uso rápido

```bash
git clone <URL-DEL-REPOSITORIO>
cd Instalador_Odoo
chmod +x OdooInstall.sh
./OdooInstall.sh
```

El instalador solicitará la versión y edición de Odoo, los nombres del entorno y de la base de datos, los puertos y las credenciales. Si se dejan vacías las contraseñas, se generan automáticamente.

Cada instalación se crea en una nueva carpeta dentro del directorio del instalador. Sus secretos se guardan en `.env` y `config/odoo.conf`; estos archivos no deben subirse a Git.

## Qué realiza

- Instala o actualiza Docker Engine y Docker Compose v2 desde el repositorio oficial de Docker.
- Clona la rama seleccionada de Odoo Community.
- Clona los módulos Enterprise cuando se selecciona esa edición.
- Genera la configuración de PostgreSQL, Odoo y Docker Compose.
- Inicializa la base de datos una sola vez y levanta los contenedores.

El servicio `odoo-init` es una tarea auxiliar de una sola ejecución. Crea las tablas
iniciales de Odoo y configura el primer usuario administrador, pero no es necesario
para operar el entorno después de instalarlo. El instalador lo coloca en el perfil
`init`, lo ejecuta explícitamente y elimina su contenedor al terminar. Por eso los
comandos normales de Compose no lo vuelven a iniciar.

> El script instala paquetes del sistema y configura Docker, por lo que solicitará permisos de administrador. Se recomienda revisarlo antes de ejecutarlo en un servidor de producción.

## Después de instalar

Dentro de la carpeta del entorno generado se pueden usar estos comandos:

```bash
sudo docker compose ps
sudo docker compose logs -f web
sudo docker compose restart web
```

`docker compose restart web` reinicia únicamente Odoo. `docker compose restart`
reinicia Odoo y PostgreSQL, pero no `odoo-init`, porque su perfil permanece inactivo.

La base PostgreSQL y el filestore de Odoo se conservan en los volúmenes nombrados
`<entorno>-db-data` y `<entorno>-web-data`. Un reinicio o una recreación normal de
los contenedores no elimina esos volúmenes. No uses `docker compose down -v` salvo
que realmente quieras borrar todos los datos del entorno. Mantén también el mismo
`COMPOSE_PROJECT_NAME` de `.env`; cambiarlo puede hacer que Compose conecte volúmenes
nuevos y el entorno parezca vacío.

Si excepcionalmente necesitas ejecutar de nuevo la comprobación de inicialización:

```bash
sudo docker compose run --rm odoo-init
```

El script verifica primero si la tabla principal de módulos ya existe y, si la base
está inicializada, termina sin reinstalarla.
