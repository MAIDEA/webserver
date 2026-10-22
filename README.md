# Maidea web server: legacy PHP 7.4 and 5.6 images

Apache + PHP (mod_php) Docker images for older apps that cannot be upgraded yet.
**This branch is no longer used to build images.** They are built from
[`legacy/` on `master`](https://github.com/MAIDEA/webserver/tree/master/legacy); see the
[main README](https://github.com/MAIDEA/webserver#readme) for the current PHP 8 images.

* Docker Hub: [`maidea/webserver`](https://hub.docker.com/r/maidea/webserver)
* `linux/amd64` only; the app is mounted at `/src`, document root `/src/app/webroot`

Legacy tags run PHP versions that are no longer supported by the PHP project and have known vulnerabilities.
Use them only if you cannot upgrade yet, and never expose them to the internet.

### Security fixes only: PHP 7.4 and 5.6

| PHP | Tags |
|---|---|
| 7.4.33 | `prod-apache-php7.4`, `prod-apache-php7`, `dev-apache-php7.4`, `dev-apache-php7` |
| 5.6.40 | `dev-apache-php5.6`, `dev-apache-php5` |

These receive only backported fixes for critical vulnerabilities, no other updates.
They contain the fix for CVE-2026-109618 / CVE-2026-109619 ([PHP advisory](https://www.php.net/archive/2026.php#2026-10-21-5)):
7.4 with the PHP security team's [backport](https://github.com/php/php-src/commit/712e60f9edfd),
5.6 with Ondřej Surý's backport of the same fix. Many other known 5.6 vulnerabilities remain unfixed.

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


## Configuration specific to these images

| Variable | Default | Notes |
|---|---|---|
| `PHP_MEMORY_LIMIT` | not set (`memory_limit` from `php.ini`, 1024M) | `-1` removes the PHP memory limit and prevents the app from changing it; **only with a container memory limit** |

## Support and license

These images are maintained for MAIDEA's own projects and offered to the public as-is, on a best-effort basis:
there is no support, no guaranteed response to issues, and no warranty.

Copyright (c) 2026 MAIDEA. All rights reserved. The source is published for reference; see [LICENSE](LICENSE).
Third-party software in the images (Debian, PHP, Apache, wkhtmltopdf, …) is covered by its own licenses.
