# Build stage
# maidea: official 5.6 recipe rebuilt with the CVE-2026-109618/109619 patch (legacy/php5.6-base, built first by scripts/build.sh)
FROM maidea-local/php:5.6.40-cve-patched-apache-stretch AS builder

# Stretch's own archive keys have expired; the archive is also signed with newer Debian keys.
# The stretch/updates signature needs the Debian 10 security key, valid until 2027-04-12.
COPY --from=debian:bookworm-slim /usr/share/keyrings/debian-archive-keyring.gpg /etc/apt/trusted.gpg.d/debian-archive-keyring-bookworm.gpg
COPY --from=debian:bookworm-slim /usr/share/keyrings/debian-archive-removed-keys.gpg /etc/apt/trusted.gpg.d/debian-archive-removed-keys-bookworm.gpg

# Update sources to use archive
RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
    -e 's/security.debian.org/archive.debian.org/g' \
    -e '/stretch-updates/d' /etc/apt/sources.list

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    curl \
    git \
    libxml2-dev \
    libmcrypt-dev \
    libicu-dev \
    libc-client-dev \
    libkrb5-dev \
    libpng-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libzip-dev \
    make \
    gcc \
    g++ \
    libtool \
    zlib1g-dev \
    mysql-client \
    default-libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*

# Build and configure PHP extensions
RUN docker-php-ext-configure gd \
        --with-gd \
        --with-png-dir=/usr/include \
        --with-jpeg-dir=/usr/include \
        --with-freetype-dir=/usr/include \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-configure mysql --with-mysql=/usr/ \
    && docker-php-ext-configure mysqli --with-mysqli=/usr/bin/mysql_config \
    && docker-php-ext-install -j$(nproc) \
        mcrypt \
        pcntl \
        zip \
        bcmath \
        mbstring \
        iconv \
        soap \
        shmop \
        imap \
        sockets \
        mysql \
        mysqli \
        pdo_mysql \
        gd \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl

# Final stage
FROM maidea-local/php:5.6.40-cve-patched-apache-stretch

# Stretch's own archive keys have expired; the archive is also signed with newer Debian keys.
# The stretch/updates signature needs the Debian 10 security key, valid until 2027-04-12.
COPY --from=debian:bookworm-slim /usr/share/keyrings/debian-archive-keyring.gpg /etc/apt/trusted.gpg.d/debian-archive-keyring-bookworm.gpg
COPY --from=debian:bookworm-slim /usr/share/keyrings/debian-archive-removed-keys.gpg /etc/apt/trusted.gpg.d/debian-archive-removed-keys-bookworm.gpg

# Update sources to use archive
RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
    -e 's/security.debian.org/archive.debian.org/g' \
    -e '/stretch-updates/d' /etc/apt/sources.list

# Environment variables
ENV APACHE_DOCUMENT_ROOT=/src/app/webroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHP_MEMORY_LIMIT=1024M

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libmariadbclient18 \
    mysql-client \
    libxml2 \
    libmcrypt4 \
    libicu57 \
    libc-client2007e \
    libkrb5-3 \
    libpng16-16 \
    libfontconfig1 \
    zlib1g \
    libfreetype6 \
    libxrender1 \
    libxext6 \
    libx11-6 \
    fontconfig \
    xfonts-base \
    xfonts-75dpi \
    libfreetype6-dev \
    libjpeg62-turbo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Copy built extensions and configurations from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Enable PHP extensions
RUN docker-php-ext-enable \
    intl \
    mysql \
    mysqli \
    pdo_mysql \
    mcrypt \
    pcntl \
    zip \
    bcmath \
    mbstring \
    iconv \
    soap \
    shmop \
    imap \
    sockets \
    gd

# PHP Configuration
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
    } > /usr/local/etc/php/conf.d/custom-php.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

# Install wkhtmltopdf
WORKDIR /tmp
RUN curl -S -s -L -o wkhtmltopdf.tar.xz http://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz \
    && tar -xvf wkhtmltopdf.tar.xz \
    && mv wkhtmltox/bin/wkhtmltopdf /usr/local/bin/wkhtmltopdf \
    && chmod +x /usr/local/bin/wkhtmltopdf \
    && rm -rf /tmp/*

# Configure Apache
RUN a2enmod rewrite \
    && sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && printf 'ServerTokens Prod\nServerSignature Off\nTraceEnable Off\n' > /etc/apache2/conf-available/zz-prod-hardening.conf \
    && a2enconf zz-prod-hardening

WORKDIR /src

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost/ || exit 1

CMD ["apache2-foreground"]
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
    } > /usr/local/etc/php/conf.d/zz-cve-2026-mitigations.ini \
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
    && a2enconf zz-cve-2026-mitigations
