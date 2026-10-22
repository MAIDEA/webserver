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
| `latest`, `prod-apache-php`, `prod-apache-php8`, `prod-apache-php8.4` | 8.4 | prod |
| `prod-apache-php8.3` | 8.3 | prod |
| `dev-apache-php`, `dev-apache-php8`, `dev-apache-php8.4` | 8.4 | dev |
| `dev-apache-php8.3` | 8.3 | dev |

Which tag to use:

* **`prod-apache-php8.4`, `dev-apache-php8.3`, …** stay on that PHP version and only receive patch releases. Recommended.
* **`latest`, `prod-apache-php`, `prod-apache-php8`, `dev-apache-php`, `dev-apache-php8`** move to the newest PHP version when one is added
  (e.g. 8.5), which can break your app.
* **Immutable tags** `<tag>-<php version>-<build date>` (e.g. `prod-apache-php8.4.27-20261022`, `.2` etc. for further builds that day)
  are never overwritten: pin one for reproducible deploys or to roll back.

The images are rebuilt automatically when the official PHP image changes (PHP patch releases, Debian security updates), usually within a day.
Older PHP versions are listed under [Legacy tags](#legacy-tags).

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
* wkhtmltopdf 0.12.6.1 (patched qt) at `/usr/local/bin/wkhtmltopdf`.
  It is no longer maintained upstream and uses an old browser engine: do not render untrusted HTML or URLs with it.
* MariaDB client (`mysql`, `mysqldump`)
* Apache with `mod_rewrite` and `mod_headers`; `.htaccess` files are honoured, directory listing is off
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
* **HTTPS:** the container serves plain HTTP on port 80; terminate HTTPS at a reverse proxy.
  The prod images mark session cookies `secure`, so the app must be reached over HTTPS (or set `SESSION_COOKIE_SECURE=0`).
* **Other frameworks:** e.g. for Laravel or Symfony set `APACHE_DOCUMENT_ROOT=/src/public`.
* **Logs:** Apache and PHP log to the container output (`docker logs`).

## Configuration

All variables are read at container start.

| Variable | Default | Variant | Notes |
|---|---|---|---|
| `PHP_MEMORY_LIMIT` | `1024M` | both | PHP `memory_limit` |
| `SESSION_COOKIE_SECURE` | `1` | prod | set to `0` only if the app is served over plain HTTP |
| `APACHE_DOCUMENT_ROOT` | `/src/app/webroot` | both | |
| `XDEBUG_REMOTE_HOST` | `host.docker.internal` | dev | where the IDE listens; works on Docker Desktop, on Linux see `extra_hosts` above |
| `XDEBUG_IDE_KEY` | `PHPSTORM` | dev | trigger value: send `XDEBUG_SESSION=PHPSTORM` (browser extension, cookie or query parameter) |
| `XDEBUG_MODE` | `develop,debug` | dev | e.g. `debug,profile`, or `off` |
| `XDEBUG_REMOTE_PORT` | `9003` | dev | |
| `XDEBUG_OUTPUT_DIR` | `/tmp` | dev | profiler/trace output |
| `XDEBUG_OUTPUT_PROFILE_NAME` | `cachegrind.out.%p` | dev | |

## Legacy tags

Legacy tags run PHP versions that are no longer supported by the PHP project and have known vulnerabilities.
Use them only if you cannot upgrade yet, and never expose them to the internet.

### Security fixes only: PHP 7.4 and 5.6

| PHP | Tags |
|---|---|
| 7.4.33 | `prod-apache-php7.4`, `prod-apache-php7`, `dev-apache-php7.4`, `dev-apache-php7` |
| 5.6.40 | `prod-apache-php5.6`, `prod-apache-php5`, `dev-apache-php5.6`, `dev-apache-php5` |

These receive only backported fixes for critical vulnerabilities, no other updates.
They contain the fix for CVE-2026-109618 / CVE-2026-109619 ([PHP advisory](https://www.php.net/archive/2026.php#2026-10-21-5)):
7.4 with the PHP security team's [backport](https://github.com/php/php-src/commit/712e60f9edfd),
5.6 with Ondřej Surý's backport of the same fix. Many other known 5.6 vulnerabilities remain unfixed.

With this fix, a request that exceeds the PHP memory limit ends immediately: the client gets an empty response,
error handlers and shutdown functions do not run, and the error appears only in the container log.
Apps that lower `memory_limit` at runtime (e.g. in an error handler) can hit this on every such request.

The 5.6 prod image (added October 2026) is the dev image without Xdebug, with errors logged but not displayed and version headers hidden.

**Changed with the October 2026 rebuild** (mitigations recommended by the advisory):

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
