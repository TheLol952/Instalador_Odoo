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

El instalador solicitará la versión y edición de Odoo, los nombres del entorno y de la base de datos, el puerto local y las credenciales. También pedirá el nombre, usuario/correo y contraseña del administrador inicial. La contraseña del administrador es obligatoria porque no se imprime ni se conserva después de inicializar Odoo.

El instalador no crea usuarios adicionales. El nombre, el usuario/correo y la contraseña del administrador se pueden personalizar; estos valores se usan en `odoo-init` y después se eliminan de `.env`. El resumen final muestra únicamente el nombre y el usuario, nunca la contraseña.

Cada instalación se crea en una nueva carpeta dentro del directorio del instalador. La contraseña de PostgreSQL y la master password interna se guardan en `.env` o `config/odoo.conf`; estos archivos no deben subirse a Git. `.env` usa permisos `600` y `config/odoo.conf`, `640`.

PostgreSQL sólo se expone dentro de la red de Docker. Odoo se publica exclusivamente en `127.0.0.1`, de modo que debe colocarse detrás de Nginx u otro proxy inverso. Para Nginx, configura también:

```nginx
client_max_body_size 100m;
```

El gestor web de bases de datos y el listado de bases están deshabilitados. En modo de base única, `db_name` y `dbfilter` se limitan a la base configurada. En modo múltiple, el instalador solicita una lista explícita de nombres, genera un `dbfilter` restrictivo e inicializa cada base mediante `odoo-init`.

## Qué realiza

- Instala o actualiza Docker Engine y Docker Compose v2 desde el repositorio oficial de Docker.
- Clona la rama seleccionada de Odoo Community.
- Clona los módulos Enterprise cuando se selecciona esa edición.
- Genera la configuración de PostgreSQL, Odoo y Docker Compose.
- Inicializa las bases permitidas una sola vez, configura el administrador y levanta los contenedores.
- Limita CPU, memoria, procesos y duración de las solicitudes de Odoo mediante valores editables en `.env`.
- Rota los logs de Docker y comprueba la salud de PostgreSQL y Odoo.

El servicio `odoo-init` es una tarea auxiliar de una sola ejecución. Crea las tablas
iniciales de Odoo y configura el primer usuario administrador, pero no es necesario
para operar el entorno después de instalarlo. El instalador lo coloca en el perfil
`init`, lo ejecuta explícitamente y elimina su contenedor al terminar. Por eso los
comandos normales de Compose no lo vuelven a iniciar. El código de Community y
Enterprise se monta como solo lectura tanto en `odoo-init` como en `web`.

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

Las credenciales del administrador se eliminan de `.env` al finalizar, por lo que
`odoo-init` está diseñado para ejecutarse durante la instalación. Si se requiere una
reinicialización administrativa, hay que proporcionar explícitamente esas variables
de entorno durante esa ejecución.
