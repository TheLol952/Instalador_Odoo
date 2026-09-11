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
- Inicializa la base de datos y levanta los contenedores.

> El script instala paquetes del sistema y configura Docker, por lo que solicitará permisos de administrador. Se recomienda revisarlo antes de ejecutarlo en un servidor de producción.

## Después de instalar

Dentro de la carpeta del entorno generado se pueden usar estos comandos:

```bash
sudo docker compose ps
sudo docker compose logs -f web
sudo docker compose logs -f odoo-init
```
