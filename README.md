# Maidea web server

Apache + PHP (mod_php) Docker images for running a PHP app mounted as a volume: mount the app, start the container, done.
Built for the CakePHP layout (document root `/src/app/webroot`), but works with any PHP app.

* Docker Hub: [`maidea/webserver`](https://hub.docker.com/r/maidea/webserver), source: [MAIDEA/webserver](https://github.com/MAIDEA/webserver)
* Based on the official [`php:<version>-apache-bookworm`](https://hub.docker.com/_/php) images (Debian 12)
* `linux/amd64` only (runs through emulation on Apple Silicon)
* Maintained for our own projects and offered to the public as-is, on a best-effort basis (see [Support and license](#support-and-license))

## Quick start

```sh
docker run --rm -p 8080:80 -v "$PWD/src:/src" maidea/webserver:prod-apache-php8.4
```

Serves `./src/app/webroot` on http://localhost:8080. For other layouts set `APACHE_DOCUMENT_ROOT` (see [Configuration](#configuration)).

## Tags

| Tags | PHP | Variant |
|---|---|---|
| `prod-apache-php8.5` | 8.5 | prod |
| `latest`, `prod-apache-php`, `prod-apache-php8`, `prod-apache-php8.4` | 8.4 | prod |
| `prod-apache-php8.3` | 8.3 | prod |
| `dev-apache-php8.5` | 8.5 | dev |
| `dev-apache-php`, `dev-apache-php8`, `dev-apache-php8.4` | 8.4 | dev |
| `dev-apache-php8.3` | 8.3 | dev |

Which tag to use:

* **`prod-apache-php8.4`, `dev-apache-php8.3`, …** stay on that PHP version and only receive patch releases. Recommended.
* **`latest`, `prod-apache-php`, `prod-apache-php8`, `dev-apache-php`, `dev-apache-php8`** move to a newer PHP version over time
  (currently 8.4), which can break your app.
* **Immutable tags** `<tag>-<php version>-<build date>` (e.g. `prod-apache-php8.4.27-20261022`, `.2` etc. for further builds that day)
  are never overwritten: pin one for reproducible deploys or to roll back.

The images are rebuilt automatically when the official PHP image changes (PHP patch releases, Debian security updates), usually within a day.
Older PHP versions are listed under [Legacy tags](#legacy-tags).

## Variants

| | prod | dev |
|---|---|---|
| Errors | logged to stderr (`docker logs`), not displayed | displayed and logged |
| OPcache | on (JIT off), **no file timestamp checks** (see below) | off |
| Xdebug | – | 3.x, trigger mode |
| Composer, git | – | yes |
| Upload / post size | 256M | 128M |
| `max_execution_time` | 60 s | 180 s |
| Session cookie | `secure` (configurable), `httponly`, `SameSite=Lax`, strict mode | not `secure` |
| Version headers | hidden (`Server: Apache`, no `X-Powered-By`) | shown |

**prod: restart after code changes.** OPcache does not check file timestamps, so code changed on the mounted volume is only picked up after a container restart
(or set `PHP_INI_OPCACHE__VALIDATE_TIMESTAMPS=1`).

**prod: `SameSite=Lax` session cookies** are not sent with cross-site POST requests: if e.g. a payment provider posts
back to your app, set `PHP_INI_SESSION__COOKIE_SAMESITE=None`.

**Session upload progress is off** (`session.upload_progress.enabled = 0`, both variants) as recommended by PHP for
CVE-2026-115560, which has no fix in PHP yet. Upload progress bars that rely on PHP sessions do not work.

## Included

* PHP extensions: apcu, bcmath, decimal, exif, ftp, gd (freetype, jpeg, webp), imap, intl, mysqli, opcache, pcntl, pdo_mysql, pdo_pgsql, pgsql, shmop, soap, sockets, zip,
  plus the extensions built into the official image (curl, mbstring, …); xdebug in dev
* wkhtmltopdf 0.12.6.1 (patched qt) at `/usr/local/bin/wkhtmltopdf`.
  It is no longer maintained upstream and uses an old browser engine: do not render untrusted HTML or URLs with it.
* MariaDB client (`mysql`, `mysqldump`); `install-php-extensions` to add PHP extensions (see [Building your own image](#building-your-own-image))
* Apache with `mod_rewrite` and `mod_headers`; `.htaccess` files are honoured, directory listing is off.
  Hidden files and folders (`.env`, `.git/`, …) are not served (`.well-known/` is), responses carry `X-Content-Type-Options: nosniff`,
  and request bodies larger than `post_max_size` + 10% are rejected
* Health check: Docker reports the container as `healthy` once Apache and PHP serve requests.
  It uses an internal listener on `127.0.0.1:8081` that is not reachable from outside the container and does not touch your app.

## Usage

Development, with Docker Compose:

```yaml
services:
  app:
    image: maidea/webserver:dev-apache-php8.4
    volumes:
      - "./src:/src"
    ports:
      - "8080:80"
    # on Linux, Xdebug's default host.docker.internal needs:
    #extra_hosts:
    #  - "host.docker.internal:host-gateway"
```

Production, behind a reverse proxy that terminates HTTPS:

```yaml
services:
  app:
    image: maidea/webserver:prod-apache-php8.4
    restart: unless-stopped
    volumes:
      - "./src:/src"
    environment:
      - PHP_MEMORY_LIMIT=512M
      # with jwilder/nginx-proxy:
      #- VIRTUAL_HOST=app.example.com
    # with Traefik:
    #labels:
    #  - "traefik.http.routers.app.rule=Host(`app.example.com`)"
    expose:
      - "80"
```

Good to know:

* **File permissions:** PHP runs as `www-data` (uid 33). Directories your app writes to (e.g. `app/tmp`) must be writable for that user.
  On a Linux host, `WWW_DATA_UID` / `WWW_DATA_GID` can give it your user's IDs instead.
* **HTTPS and reverse proxies:** the container serves plain HTTP on port 80; terminate HTTPS at a reverse proxy.
  Requests from proxies in `APACHE_TRUSTED_PROXIES` (default: private networks) get the client IP from `X-Forwarded-For`
  and `HTTPS=on` from `X-Forwarded-Proto: https`. If clients reach the container directly, set `APACHE_TRUSTED_PROXIES=none`.
  Clients on a trusted (private) network can set these headers themselves: do not use the client IP for access control
  unless `APACHE_TRUSTED_PROXIES` lists only your proxy.
  The prod images mark session cookies `secure`, so the app must be reached over HTTPS (or set `SESSION_COOKIE_SECURE=0`).
* **Startup scripts:** `/docker-entrypoint.d/*.sh` run as root before Apache starts, e.g. for database migrations.
* **Other frameworks:** e.g. for Laravel or Symfony set `APACHE_DOCUMENT_ROOT=/src/public`.
* **Logs:** Apache and PHP log to the container output (`docker logs`).

## Configuration

All variables are read at container start.

| Variable | Default | Variant | Notes |
|---|---|---|---|
| `PHP_INI_<NAME>` | | both | any PHP setting, e.g. `PHP_INI_UPLOAD_MAX_FILESIZE=64M`, `PHP_INI_DATE__TIMEZONE=Europe/Zagreb` (name lowercased, `__` becomes `.`) |
| `PHP_MEMORY_LIMIT` | `1024M` | both | PHP `memory_limit` |
| `SESSION_COOKIE_SECURE` | `1` | prod | set to `0` only if the app is served over plain HTTP |
| `APACHE_DOCUMENT_ROOT` | `/src/app/webroot` | both | |
| `APACHE_TRUSTED_PROXIES` | private networks | both | reverse proxies whose `X-Forwarded-*` headers are used (CIDRs, space-separated), or `none` |
| `WWW_DATA_UID`, `WWW_DATA_GID` | `33` | both | IDs of the user Apache and PHP run as |
| `APACHE_MAX_REQUEST_WORKERS` | `150` | both | Apache/PHP processes per container (each takes tens of MB); lower it for small apps |
| `XDEBUG_REMOTE_HOST` | `host.docker.internal` | dev | where the IDE listens; works on Docker Desktop, on Linux see `extra_hosts` above |
| `XDEBUG_IDE_KEY` | `PHPSTORM` | dev | trigger value: send `XDEBUG_SESSION=PHPSTORM` (browser extension, cookie or query parameter) |
| `XDEBUG_MODE` | `develop,debug` | dev | e.g. `debug,profile`, or `off` |
| `XDEBUG_REMOTE_PORT` | `9003` | dev | |
| `XDEBUG_OUTPUT_DIR` | `/tmp` | dev | profiler/trace output |
| `XDEBUG_OUTPUT_PROFILE_NAME` | `cachegrind.out.%p` | dev | |

## Building your own image

```dockerfile
FROM maidea/webserver:prod-apache-php8.4
# more PHP extensions: https://github.com/mlocati/docker-php-extension-installer
RUN install-php-extensions redis
# the prod images have no Composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY . /src
RUN composer install --no-dev --optimize-autoloader
# runs before Apache starts
COPY docker/migrate.sh /docker-entrypoint.d/10-migrate.sh
```

## Legacy tags

Legacy tags run PHP versions that are no longer supported by the PHP project and have known vulnerabilities.
Use them only if you cannot upgrade yet, and never expose them to the internet.

### Security updates: PHP 7.4 and 5.6

| PHP | Tags |
|---|---|
| 7.4.33 | `prod-apache-php7.4`, `prod-apache-php7`, `dev-apache-php7.4`, `dev-apache-php7` |
| 5.6.40 | `prod-apache-php5.6`, `prod-apache-php5`, `dev-apache-php5.6`, `dev-apache-php5` |

Since October 2026 these run on Debian 12 with PHP from [Ondřej Surý's packages](https://deb.sury.org/), which carry
backported fixes for many vulnerabilities found after the PHP project stopped supporting these versions, including
CVE-2026-109618 / CVE-2026-109619 ([PHP advisory](https://www.php.net/archive/2026.php#2026-10-21-5)).
They are rebuilt automatically when a new package or Debian update is released. Not every known vulnerability is fixed.

They keep the extensions, settings and tools of the earlier images (wkhtmltopdf 0.12.4 on 5.6, 0.12.6.1 on 7.4),
with these differences:

* PHP comes from Debian packages: `PHP_VERSION` has a package suffix (e.g. `5.6.40-105+0~...`), and there are no
  `docker-php-ext-*` scripts, `pecl` or compilers. Add extensions with apt, e.g. `apt-get install php7.4-redis`
  (enabled on install); `phpenmod`/`phpdismod` switch installed ones on and off (e.g. `phpenmod xsl`).
* Configuration stays in `/usr/local/etc/php` (`php.ini`, `conf.d/*.ini`); Debian's `/etc/php/<version>/{apache2,cli}/conf.d`
  are links to `/usr/local/etc/php/conf.d`.
* `exif` (and `mysqli` on 7.4) are loaded as well, as in the current images.
* `pcntl` is available on the command line only, not in Apache.
* `mod_headers` is enabled, so `Header` lines in `.htaccess` files now take effect.

Immutable tags, the health check, the Apache hardening, `PHP_INI_*`, `WWW_DATA_UID`/`GID`, `APACHE_*` variables and startup scripts
work as in the current images (the request body limit stays at 110M).

The 5.6 prod image (added October 2026) is the dev image without Xdebug, with errors logged but not displayed and version headers hidden.

With the CVE-2026-109618 fix, a request that exceeds the PHP memory limit ends immediately: the client gets an empty response,
error handlers and shutdown functions do not run, and the error appears only in the container log.
Apps that lower `memory_limit` at runtime (e.g. in an error handler) can hit this on every such request.

**Mitigations** recommended by the advisory (since October 2026):

* file uploads are limited to **100M** (`post_max_size` 110M; Apache rejects larger request bodies)
* Apache serves one request per process (`KeepAlive Off`, `MaxConnectionsPerChild 1`): safer, but slower under load
* session upload progress is disabled, and `max_input_nesting_level` is 16
* opt-in `PHP_MEMORY_LIMIT=-1` removes the PHP memory limit and prevents the app from setting one, which blocks the out-of-memory path of CVE-2026-109618.
  **Only use it together with a container memory limit** (e.g. `mem_limit` in Compose), otherwise one runaway request can use all memory of the server.

### Frozen: no updates

| PHP | Tags |
|---|---|
| 8.2.10 | `prod-apache-php8.2`, `dev-apache-php8.2` |
| 7.4 | `dev-apache-php7-x3`, `dev-apache-php7-x3-pgsql` |
| 7.0–7.3 | `dev_apache_php7`, `dev-apache-php7.0`, `dev-apache-php7.2`, `dev-apache-php7-wpdf0.12.5`, `prod-apache-php7.3` |
| 5.6 | `dev`, `dev1.4-apache-php5.6`, `dev1.6-apache-php5.6`, `dev1.7-apache-php5.6` |
| nginx + php-fpm (2017) | `1`, `2` |

**The 8.2 tags are vulnerable to the critical CVE-2026-109618 / CVE-2026-109619**: move to `prod-apache-php8.3` / `dev-apache-php8.3`.

## Building

See [MAINTAINING.md](MAINTAINING.md).

## Support and license

These images are maintained for MAIDEA's own projects and offered to the public as-is, on a best-effort basis:
there is no support, no guaranteed response to issues, and no warranty.

Copyright (c) 2026 MAIDEA. All rights reserved. The source is published for reference; see [LICENSE](LICENSE).
Third-party software in the images (Debian, PHP, Apache, wkhtmltopdf, …) is covered by its own licenses.
