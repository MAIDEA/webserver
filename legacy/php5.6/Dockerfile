# PHP 5.6 (end of life) on Debian 12, from Ondřej Surý's packages (packages.sury.org), which carry backported
# security fixes. Targets: dev, prod (default).
#
# Behaves like the earlier images built from the official php:5.6-apache recipe: same extensions, settings and tools,
# config in /usr/local/etc/php (conf.d/*.ini, an optional php.ini), apache2-foreground, document root /src/app/webroot.
# apache2-foreground and docker-php-entrypoint are from the official recipe (docker-library/php).

# Images used by the build; scripts/build.sh pins each to its current digest (*_IMAGE build arguments)
ARG BASE_IMAGE=debian:bookworm-slim
ARG COMPOSER_IMAGE=composer:2.2

FROM ${COMPOSER_IMAGE} AS composer

FROM ${BASE_IMAGE} AS base

# Version of Sury's php5.6 packages; scripts/build.sh passes the current one (empty: latest)
ARG PHP_PACKAGE_VERSION=
# Oldest package version with the CVE-2026-109618 / CVE-2026-109619 fix
ARG PHP_PACKAGE_MIN=5.6.40-104
ARG SURY_KEYRING_SHA256=7511384559c9ddf1d5ce5f60be429ae9d4e7d01d9480d6f1b7a30c0810cf8b60
# wkhtmltopdf 0.12.4 as before (static Qt and OpenSSL; 0.12.6 blocks local files by default)
ARG WKHTMLTOPDF_SHA256=049b2cdec9a8254f0ef8ac273afaf54f7e25459a273e27189591edc7d7cf29db

ENV PHP_VERSION=5.6.40 \
    PHP_PATCHES=CVE-2026-109618-109619 \
    PHP_INI_DIR=/usr/local/etc/php \
    PHPRC=/usr/local/etc/php \
    PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d \
    APACHE_CONFDIR=/etc/apache2 \
    APACHE_ENVVARS=/etc/apache2/envvars \
    APACHE_DOCUMENT_ROOT=/src/app/webroot \
    PHP_MEMORY_LIMIT=1024M \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/sury-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb; \
    echo "$SURY_KEYRING_SHA256  /tmp/sury-keyring.deb" | sha256sum -c -; \
    dpkg -i /tmp/sury-keyring.deb; \
    rm /tmp/sury-keyring.deb; \
    echo 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ bookworm main' \
        > /etc/apt/sources.list.d/sury-php.list; \
    apt-get update; \
    v=${PHP_PACKAGE_VERSION:+=$PHP_PACKAGE_VERSION}; \
    apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php5.6$v php5.6-cli$v php5.6-common$v php5.6-json$v php5.6-opcache$v php5.6-readline$v \
        php5.6-bcmath$v php5.6-curl$v php5.6-gd$v php5.6-imap$v php5.6-intl$v php5.6-mbstring$v php5.6-mcrypt$v \
        php5.6-mysql$v php5.6-soap$v php5.6-sqlite3$v php5.6-xml$v php5.6-zip$v \
        git mariadb-client xz-utils \
        fontconfig libfontconfig1 libfreetype6 libjpeg62-turbo libpng16-16 libx11-6 libxext6 libxrender1 xfonts-75dpi xfonts-base zlib1g; \
    dpkg --compare-versions "$(dpkg-query -W -f '${Version}' php5.6-common)" ge "$PHP_PACKAGE_MIN"; \
    rm -rf /var/lib/apt/lists/*; \
    ln -s /usr/bin/php5.6 /usr/local/bin/php; \
# PHP reads /usr/local/etc/php (PHPRC, PHP_INI_SCAN_DIR), not Debian's /etc/php: no Debian php.ini, and Debian's
# per-SAPI conf.d directories are links to /usr/local/etc/php/conf.d, so phpenmod, phpdismod, phpquery and
# package installs act on the configuration PHP reads. Extensions start disabled; the next step enables ours.
    rm -f /etc/php/5.6/apache2/php.ini /etc/php/5.6/cli/php.ini; \
    phpdismod -v 5.6 -s ALL $(phpquery -v 5.6 -M); \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
    for sapi in apache2 cli; do \
        rmdir "/etc/php/5.6/$sapi/conf.d"; \
        ln -s "$PHP_INI_DIR/conf.d" "/etc/php/5.6/$sapi/conf.d"; \
    done

# Extensions: enabled with phpenmod (links in /usr/local/etc/php/conf.d to Debian's ini files, in their load order).
# php-modules-check fails the build if "php -m" differs from modules.txt or PHP prints startup warnings.
COPY extensions.txt modules.txt /usr/local/share/php/
COPY php-modules-check /usr/local/bin/
RUN set -eux; \
    phpenmod -v 5.6 -s ALL $(grep -v '^#' /usr/local/share/php/extensions.txt); \
# Defaults that Debian's build changed, back to those of the official php image
    { \
        echo 'session.save_path = ""'; \
        echo 'mysql.default_socket = /var/run/mysqld/mysqld.sock'; \
        echo 'pdo_mysql.default_socket = /tmp/mysql.sock'; \
    } > "$PHP_INI_DIR/conf.d/00-defaults.ini"; \
    php-modules-check

# Apache as in the official recipe: envvars overridable at runtime, logs to stdout/stderr, prefork + mod_php
RUN set -eux; \
    sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
    . "$APACHE_ENVVARS"; \
    for dir in "$APACHE_LOCK_DIR" "$APACHE_RUN_DIR" "$APACHE_LOG_DIR"; do \
        rm -rf "$dir"; mkdir -p "$dir"; chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; chmod 777 "$dir"; \
    done; \
    rm -rf /var/www/html; mkdir -p /var/www/html; chown www-data:www-data /var/www/html; chmod 777 /var/www/html; \
    ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
    ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
    ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
    chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"; \
    a2dismod -q mpm_event; \
    a2enmod -q mpm_prefork php5.6 rewrite; \
# PHP handler from docker-php.conf below (only .php files), not Debian's php5.6.conf
    rm /etc/apache2/mods-enabled/php5.6.conf; \
    { \
        echo '<FilesMatch \.php$>'; \
        echo '\tSetHandler application/x-httpd-php'; \
        echo '</FilesMatch>'; \
        echo; \
        echo 'DirectoryIndex disabled'; \
        echo 'DirectoryIndex index.php index.html'; \
        echo; \
        echo '<Directory /var/www/>'; \
        echo '\tOptions -Indexes'; \
        echo '\tAllowOverride All'; \
        echo '</Directory>'; \
    } > "$APACHE_CONFDIR/conf-available/docker-php.conf"; \
    a2enconf -q docker-php; \
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

RUN set -eux; \
    curl -fsSL -o /tmp/wkhtmltopdf.tar.xz https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz; \
    echo "$WKHTMLTOPDF_SHA256  /tmp/wkhtmltopdf.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/wkhtmltopdf.tar.xz -C /tmp wkhtmltox/bin/wkhtmltopdf; \
    mv /tmp/wkhtmltox/bin/wkhtmltopdf /usr/local/bin/wkhtmltopdf; \
    rm -rf /tmp/wkhtmltopdf.tar.xz /tmp/wkhtmltox

# Composer 2.2 LTS, the last version that runs on PHP 5.6
COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# maidea: mitigations for CVE-2026-109618 / CVE-2026-109619 (PHP security advisory 2026-10-21, see README)
# - no session upload progress: the confirmed path for the stale-state bug
# - upload limit 100M (post 110M, Apache body limit 110M): bounds the out-of-memory trigger, also without Content-Length
# - one request per Apache process: stale state from one request cannot reach a later one
# - PHP_MEMORY_LIMIT=-1 (opt-in): removes the PHP memory limit and locks it; needs a container memory limit
RUN { \
        echo 'session.upload_progress.enabled = 0'; \
        echo 'upload_max_filesize = 100M'; \
        echo 'post_max_size = 110M'; \
        echo 'max_input_nesting_level = 16'; \
    } > "$PHP_INI_DIR/conf.d/zz-cve-2026-mitigations.ini" \
    && { \
        echo 'KeepAlive Off'; \
        echo '<IfModule mpm_prefork_module>'; \
        echo '    MaxConnectionsPerChild 1'; \
        echo '</IfModule>'; \
        echo 'LimitRequestBody 115343360'; \
        echo 'Include /etc/apache2/php-memory/${PHP_MEMORY_MODE}.conf'; \
    } > /etc/apache2/conf-available/zz-cve-2026-mitigations.conf \
    && mkdir -p /etc/apache2/php-memory \
    && echo '# PHP memory limit from php.ini' > /etc/apache2/php-memory/default.conf \
    && echo 'php_admin_value memory_limit -1' > /etc/apache2/php-memory/unlimited.conf \
    && echo 'if [ "${PHP_MEMORY_LIMIT:-}" = "-1" ]; then export PHP_MEMORY_MODE=unlimited; else export PHP_MEMORY_MODE=default; fi' >> /etc/apache2/envvars \
    && a2enconf -q zz-cve-2026-mitigations

# shared/ (passed by scripts/build.sh as the "shared" build context): health check on a loopback-only listener,
# reverse proxies (APACHE_TRUSTED_PROXIES), request limits (APACHE_MAX_REQUEST_WORKERS; the body limit above stays),
# hardening (no hidden files, shorter Timeout, nosniff), the entrypoint (WWW_DATA_UID/GID, PHP_INI_*, /docker-entrypoint.d/);
# no server-status page or /cgi-bin/ alias
COPY --from=shared apache/healthcheck.conf /etc/apache2/conf-available/healthcheck.conf
COPY --from=shared apache/remoteip.conf /etc/apache2/conf-available/remoteip-proxy.conf
COPY --from=shared apache/remoteip/ /etc/apache2/remoteip/
COPY --from=shared apache/limits.conf /etc/apache2/conf-available/request-limits.conf
COPY --from=shared apache/hardening.conf /etc/apache2/conf-available/hardening.conf
COPY --from=shared apache/envvars-defaults /tmp/
COPY --from=shared docker-webserver-entrypoint /usr/local/bin/
RUN mkdir -p /var/www/healthcheck \
    && echo '<?php echo "ok";' > /var/www/healthcheck/index.php \
    && chown -R www-data:www-data /var/www/healthcheck \
    && a2enconf -q healthcheck \
    && cat /tmp/envvars-defaults >> /etc/apache2/envvars \
    && rm /tmp/envvars-defaults \
    && a2enmod -q remoteip headers \
    && a2dismod -q -f status \
    && a2disconf -q serve-cgi-bin \
    && a2enconf -q remoteip-proxy request-limits hardening

COPY apache2-foreground docker-php-entrypoint /usr/local/bin/
WORKDIR /src
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --start-interval=2s --retries=3 \
    CMD curl -fsS --max-time 4 http://127.0.0.1:8081/ || exit 1
ENTRYPOINT ["docker-webserver-entrypoint"]
CMD ["apache2-foreground"]


FROM base AS dev

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends php5.6-xdebug; \
    rm -rf /var/lib/apt/lists/*; \
    phpenmod -v 5.6 -s ALL xdebug; \
    php-modules-check xdebug; \
    php -r 'exit(version_compare(phpversion("xdebug"), "2.5.0", ">=") && version_compare(phpversion("xdebug"), "2.6.0", "<") ? 0 : 1);'

RUN { \
        echo 'short_open_tag = On'; \
        echo 'output_buffering = 4096'; \
        echo 'max_execution_time = 180'; \
        echo 'max_input_time = 120'; \
        echo 'memory_limit = ${PHP_MEMORY_LIMIT}'; \
        echo 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'; \
        echo 'display_errors = On'; \
        echo 'display_startup_errors = On'; \
        echo 'log_errors = On'; \
        echo 'log_errors_max_len = 1024'; \
        echo 'html_errors = On'; \
        echo 'default_charset = "UTF-8"'; \
        echo 'post_max_size = 128M'; \
        echo 'upload_max_filesize = 128M'; \
        echo 'max_file_uploads = 20'; \
        echo 'date.timezone = UTC'; \
        echo 'session.use_strict_mode = 0'; \
        echo 'session.use_cookies = 1'; \
        echo 'session.use_only_cookies = 1'; \
        echo 'session.cookie_secure = 0'; \
        echo 'session.use_trans_sid = 0'; \
        echo 'session.cache_limiter = nocache'; \
        echo 'session.gc_probability = 0'; \
        echo 'error_log = /proc/self/fd/2'; \
    } > "$PHP_INI_DIR/conf.d/custom-php.ini" \
    && { \
        echo 'xdebug.remote_enable=on'; \
        echo 'xdebug.remote_host=${XDEBUG_REMOTE_HOST}'; \
        echo 'xdebug.idekey=${XDEBUG_IDE_KEY}'; \
    } > "$PHP_INI_DIR/conf.d/xdebug.ini"


FROM base AS prod

RUN { \
        echo 'short_open_tag = On'; \
        echo 'output_buffering = 4096'; \
        echo 'max_execution_time = 180'; \
        echo 'max_input_time = 120'; \
        echo 'memory_limit = ${PHP_MEMORY_LIMIT}'; \
        echo 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'; \
        echo 'display_errors = Off'; \
        echo 'display_startup_errors = Off'; \
        echo 'log_errors = On'; \
        echo 'log_errors_max_len = 1024'; \
        echo 'html_errors = Off'; \
        echo 'expose_php = Off'; \
        echo 'register_argc_argv = Off'; \
        echo 'default_charset = "UTF-8"'; \
        echo 'post_max_size = 128M'; \
        echo 'upload_max_filesize = 128M'; \
        echo 'max_file_uploads = 20'; \
        echo 'date.timezone = UTC'; \
        echo 'session.use_strict_mode = 0'; \
        echo 'session.use_cookies = 1'; \
        echo 'session.use_only_cookies = 1'; \
        echo 'session.cookie_secure = 0'; \
        echo 'session.use_trans_sid = 0'; \
        echo 'session.cache_limiter = nocache'; \
        echo 'session.gc_probability = 0'; \
        echo 'error_log = /proc/self/fd/2'; \
    } > "$PHP_INI_DIR/conf.d/custom-php.ini" \
    && printf 'ServerTokens Prod\nServerSignature Off\nTraceEnable Off\n' > /etc/apache2/conf-available/zz-prod-hardening.conf \
    && a2enconf -q zz-prod-hardening
