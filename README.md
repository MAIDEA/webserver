# Maidea web server

Apache + PHP (mod_php) Docker images for running a PHP app mounted as a volume: mount the app, start the container, done.
Built for the CakePHP layout (document root `/src/app/webroot`), but works with any PHP app.

* Docker Hub: [`maidea/webserver`](https://hub.docker.com/r/maidea/webserver)
* Based on the official [`php:<version>-apache-bookworm`](https://hub.docker.com/_/php) images (Debian 12), `linux/amd64`

## Tags

| Tags | PHP | Variant |
|---|---|---|
| `latest`, `prod-apache-php`, `prod-apache-php8`, `prod-apache-php8.4` | 8.4 | prod |
| `prod-apache-php8.3` | 8.3 | prod |
| `dev-apache-php`, `dev-apache-php8`, `dev-apache-php8.4` | 8.4 | dev |
| `dev-apache-php8.3` | 8.3 | dev |

These tags are updated with PHP patch releases.
Each build is also pushed under an immutable tag, `<tag>-<php version>-<build date>`
(e.g. `prod-apache-php8.4.27-20261022`), which is never overwritten: pin it for reproducible deploys or to roll back.

**Legacy tags** are frozen, receive no updates, and run end-of-life PHP versions with known vulnerabilities.
Use them only for internal projects that have not been migrated yet, and never expose them to the internet:

| PHP | Tags |
|---|---|
| 8.2.10 | `dev-apache-php8.2`, `prod-apache-php8.2` |
| 7.4 | `dev-apache-php7`, `dev-apache-php7.4`, `prod-apache-php7`, `prod-apache-php7.4`, `dev-apache-php7-x3`, `dev-apache-php7-x3-pgsql` |
| 7.0–7.3 | `dev_apache_php7`, `dev-apache-php7.0`, `dev-apache-php7.2`, `dev-apache-php7-wpdf0.12.5`, `prod-apache-php7.3` |
| 5.6 | `dev-apache-php5`, `dev-apache-php5.6`, `dev`, `dev1.4-apache-php5.6`, `dev1.6-apache-php5.6`, `dev1.7-apache-php5.6` |
| nginx + php-fpm (2017) | `1`, `2` |

## Variants

| | prod | dev |
|---|---|---|
| Errors | logged to stderr (`docker logs`), not displayed | displayed and logged |
| OPcache | on, JIT on, **no file timestamp checks** (see below) | off |
| Xdebug | – | 3.x, trigger mode |
| Composer, git | – | yes |
| Upload / post size | 256M | 128M |
| `max_execution_time` | 60 s | 180 s |
| Session cookie | `secure` (configurable), `httponly`, strict mode | not `secure` |
| Version headers | hidden (`Server: Apache`, no `X-Powered-By`) | shown |

**prod: restart after code changes.** OPcache does not check file timestamps, so code changed on the mounted volume is only picked up after a container restart.

## Included

* PHP extensions: apcu, bcmath, decimal, gd (freetype, jpeg, webp), imap, intl, opcache, pcntl, pdo_mysql, pdo_pgsql, pgsql, shmop, soap, sockets, zip,
  plus the extensions built into the official image (curl, mbstring, …); xdebug in dev
* wkhtmltopdf 0.12.6.1 (patched qt) at `/usr/local/bin/wkhtmltopdf`
* MariaDB client (`mysql`, `mysqldump`)
* Apache with `mod_rewrite` and `mod_headers`; `.htaccess` files are honoured, directory listing is off
* Health check: Docker reports the container as `healthy` once Apache and PHP serve requests.
  It uses an internal listener on `127.0.0.1:8081` that is not reachable from outside the container and does not touch your app.

## Usage

```yaml
services:
  my_webapp:
    image: maidea/webserver:dev-apache-php8.4
    volumes:
      - "./src:/src"          # app code; document root is /src/app/webroot
    environment:
      - XDEBUG_REMOTE_HOST=host.docker.internal
      # with jwilder/nginx-proxy:
      #- VIRTUAL_HOST=host.example.com
      #- VIRTUAL_PORT=80
    # with Traefik:
    #labels:
    #  - "traefik.http.routers.my_webapp.rule=Host(`host.example.com`)"
    # on Linux, host.docker.internal needs:
    #extra_hosts:
    #  - "host.docker.internal:host-gateway"
    expose:
      - "80"
```

## Configuration

All variables are read at container start.

| Variable | Default | Variant | Notes |
|---|---|---|---|
| `PHP_MEMORY_LIMIT` | `1024M` | both | PHP `memory_limit` |
| `SESSION_COOKIE_SECURE` | `1` | prod | set to `0` only if the app is served over plain HTTP |
| `APACHE_DOCUMENT_ROOT` | `/src/app/webroot` | prod | in dev the document root is fixed to `/src/app/webroot` |
| `XDEBUG_REMOTE_HOST` | – | dev | **required for step debugging**; `host.docker.internal` on Docker Desktop |
| `XDEBUG_IDE_KEY` | `PHPSTORM` | dev | trigger value: send `XDEBUG_SESSION=PHPSTORM` (browser extension, cookie or query parameter) |
| `XDEBUG_MODE` | `develop,debug` | dev | e.g. `debug,profile`, or `off` |
| `XDEBUG_REMOTE_PORT` | `9003` | dev | |
| `XDEBUG_OUTPUT_DIR` | `/tmp` | dev | profiler/trace output |
| `XDEBUG_OUTPUT_PROFILE_NAME` | `cachegrind.out.%p` | dev | |

## Building

Each image is built from its own branch:

| Branch | Tags |
|---|---|
| `prod-apache-php` (same commit: `prod-apache-php8`) | `latest`, `prod-apache-php`, `prod-apache-php8`, `prod-apache-php8.4` |
| `prod-apache-php8.3` | `prod-apache-php8.3` |
| `master` (same commit: `dev-apache-php`, `dev-apache-php8`) | `dev-apache-php`, `dev-apache-php8`, `dev-apache-php8.4` |
| `dev-apache-php8.3` | `dev-apache-php8.3` |

```sh
docker buildx build --platform linux/amd64 -t maidea/webserver:<tag> .
```

The PHP version and the PECL extension versions are pinned in the `Dockerfile`.
Do not unpin them: e.g. an unpinned `pecl install decimal` installs decimal 2.x, which breaks the API used by existing apps.
