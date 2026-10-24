# PHP 7.4 (end of life) on Debian 12, from Ondřej Surý's packages (packages.sury.org), which carry backported
# security fixes. Targets: dev, prod (default).
#
# Behaves like the earlier images built from the official php:7.4-apache recipe: same extensions, settings and tools,
# config in /usr/local/etc/php (php.ini, conf.d/*.ini), apache2-foreground, document root /src/app/webroot.
# apache2-foreground and docker-php-entrypoint are from the official recipe (docker-library/php).

FROM debian:bookworm-slim AS base

# Version of Sury's php7.4 packages; scripts/build.sh passes the current one (empty: latest)
ARG PHP_PACKAGE_VERSION=
# Oldest package version with the CVE-2026-109618 / CVE-2026-109619 fix
ARG PHP_PACKAGE_MIN=1:7.4.33-31
ARG SURY_KEYRING_SHA256=7511384559c9ddf1d5ce5f60be429ae9d4e7d01d9480d6f1b7a30c0810cf8b60
ARG WKHTMLTOPDF_SHA256=98ba0d157b50d36f23bd0dedf4c0aa28c7b0c50fcdcdc54aa5b6bbba81a3941d

ENV PHP_VERSION=7.4.33 \
    PHP_PATCHES=CVE-2026-109618-109619 \
    PHP_INI_DIR=/usr/local/etc/php \
    PHPRC=/usr/local/etc/php \
    PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d \
    APACHE_CONFDIR=/etc/apache2 \
    APACHE_ENVVARS=/etc/apache2/envvars \
    APACHE_DOCUMENT_ROOT=/src/app/webroot \
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
    curl -fsSL -o /tmp/wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb; \
    echo "$WKHTMLTOPDF_SHA256  /tmp/wkhtmltopdf.deb" | sha256sum -c -; \
    apt-get update; \
    v=${PHP_PACKAGE_VERSION:+=$PHP_PACKAGE_VERSION}; \
    apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php7.4$v php7.4-cli$v php7.4-common$v php7.4-json$v php7.4-opcache$v php7.4-readline$v \
        php7.4-bcmath$v php7.4-curl$v php7.4-gd$v php7.4-imap$v php7.4-intl$v php7.4-mbstring$v \
        php7.4-mysql$v php7.4-pgsql$v php7.4-soap$v php7.4-sqlite3$v php7.4-xml$v php7.4-zip$v \
        php7.4-apcu php7.4-mcrypt \
        git mariadb-client /tmp/wkhtmltopdf.deb; \
    dpkg --compare-versions "$(dpkg-query -W -f '${Version}' php7.4-common)" ge "$PHP_PACKAGE_MIN"; \
    rm -rf /var/lib/apt/lists/* /tmp/wkhtmltopdf.deb; \
    ln -s /usr/bin/php7.4 /usr/local/bin/php; \
# PHP reads /usr/local/etc/php (PHPRC, PHP_INI_SCAN_DIR), not Debian's /etc/php: no Debian php.ini
    rm -f /etc/php/7.4/apache2/php.ini /etc/php/7.4/cli/php.ini; \
    mkdir -p "$PHP_INI_DIR/conf.d"

# Extensions, loaded from /usr/local/etc/php/conf.d (Debian's ini files, keeping their load order).
# php-modules-check fails the build if "php -m" differs from modules.txt or PHP prints startup warnings.
COPY extensions.txt modules.txt /usr/local/share/php/
COPY php-modules-check /usr/local/bin/
RUN set -eux; \
    for ext in $(grep -v '^#' /usr/local/share/php/extensions.txt); do \
        prio=$(sed -n 's/^; priority=//p' "/etc/php/7.4/mods-available/$ext.ini"); \
        cp "/etc/php/7.4/mods-available/$ext.ini" "$PHP_INI_DIR/conf.d/$prio-$ext.ini"; \
    done; \
    printf 'apc.enable_cli=1\napc.shm_size=512M\n' >> "$PHP_INI_DIR/conf.d/20-apcu.ini"; \
    echo 'date.timezone = "UTC"' > "$PHP_INI_DIR/conf.d/timezone.ini"; \
# Defaults that Debian's build changed, back to those of the official php image
    { \
        echo 'session.save_path = ""'; \
        echo 'pdo_mysql.default_socket ='; \
    } > "$PHP_INI_DIR/conf.d/00-defaults.ini"; \
    php-modules-check; \
    php -r 'exit(version_compare(phpversion("apcu"), "5.1.0", ">=") && version_compare(phpversion("apcu"), "5.2.0", "<") ? 0 : 1);'; \
    php -r 'exit(version_compare(phpversion("mcrypt"), "1.0.0", ">=") && version_compare(phpversion("mcrypt"), "1.1.0", "<") ? 0 : 1);'

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
    a2enmod -q mpm_prefork php7.4 rewrite; \
# PHP handler from docker-php.conf below (only .php files), not Debian's php7.4.conf
    rm /etc/apache2/mods-enabled/php7.4.conf; \
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

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

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

COPY apache2-foreground docker-php-entrypoint /usr/local/bin/
WORKDIR /src
EXPOSE 80
# https://httpd.apache.org/docs/2.4/stopping.html#gracefulstop
STOPSIGNAL SIGWINCH
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["apache2-foreground"]


FROM base AS dev

ENV XDEBUG_MODE=develop,debug \
    XDEBUG_IDE_KEY=PHPSTORM

COPY php.ini-dev /usr/local/etc/php/php.ini
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends php7.4-xdebug; \
    rm -rf /var/lib/apt/lists/*; \
    cp /etc/php/7.4/mods-available/xdebug.ini "$PHP_INI_DIR/conf.d/20-xdebug.ini"; \
    { \
        echo 'xdebug.client_host=${XDEBUG_REMOTE_HOST}'; \
        echo 'xdebug.start_with_request=trigger'; \
        echo 'xdebug.trigger_value=${XDEBUG_IDE_KEY}'; \
    } > "$PHP_INI_DIR/conf.d/xdebug.ini"; \
    php-modules-check xdebug; \
    php -r 'exit(version_compare(phpversion("xdebug"), "3.1.0", ">=") && version_compare(phpversion("xdebug"), "3.2.0", "<") ? 0 : 1);'


FROM base AS prod

COPY php.ini-prod /usr/local/etc/php/php.ini
RUN php-modules-check
