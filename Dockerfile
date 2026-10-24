# Apache + mod_php images for apps mounted at /src. Two targets: prod (default) and dev.
# Build arguments per image are listed in matrix.json; build with scripts/build.sh.

# PHP minor version of the official php image, e.g. 8.4 (patch releases are picked up on rebuild)
ARG PHP_VERSION=8.4

# libmpdec for the decimal extension: not packaged in Debian 12, built from a checksum-verified tarball
FROM php:${PHP_VERSION}-apache-bookworm AS mpdecimal
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev make \
    && rm -rf /var/lib/apt/lists/*
RUN cd /tmp \
    && curl -fsSLO https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-2.5.1.tar.gz \
    && echo "9f9cd4c041f99b5c49ffb7b59d9f12d95b683d88585608aa56a6307667b2b21f  mpdecimal-2.5.1.tar.gz" | sha256sum --check --status - \
    && tar xf mpdecimal-2.5.1.tar.gz \
    && cd mpdecimal-2.5.1 \
    && ./configure --disable-cxx \
    && make \
    && make install


FROM php:${PHP_VERSION}-apache-bookworm AS base

LABEL org.opencontainers.image.source="https://github.com/MAIDEA/webserver"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHP_MEMORY_LIMIT=1024M \
    APACHE_DOCUMENT_ROOT=/src/app/webroot

COPY --from=mlocati/php-extension-installer:2.12.3 /usr/bin/install-php-extensions /usr/local/bin/
# COPY would turn the library symlinks into plain files, which the extension installer does not recognise
COPY --from=mpdecimal /usr/local/lib/libmpdec.so.2.5.1 /usr/local/lib/
COPY --from=mpdecimal /usr/local/include/mpdecimal.h /usr/local/include/

# PECL versions are pinned on purpose: unpinned builds pull new majors (e.g. decimal 2.x changed its API)
ARG APCU_VERSION=5.1.24
ARG DECIMAL_VERSION=1.5.0
ARG IMAP_VERSION=1.0.3
RUN ln -s libmpdec.so.2.5.1 /usr/local/lib/libmpdec.so.3 \
    && ln -s libmpdec.so.2.5.1 /usr/local/lib/libmpdec.so \
    && ldconfig \
    && install-php-extensions \
        apcu-${APCU_VERSION} \
        bcmath \
        decimal-${DECIMAL_VERSION} \
        imap-${IMAP_VERSION} \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        shmop \
        soap \
        sockets \
        zip \
    && ldd "$(php-config --extension-dir)/decimal.so" | grep -q 'libmpdec.so.3 => /usr/local/lib/libmpdec.so.3'

# gd with FreeType, JPEG, PNG and WebP only: on Debian 12 install-php-extensions always adds AVIF and XPM,
# whose extra image decoders the apps do not need
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfreetype6 libjpeg62-turbo libpng16-16 libwebp7 \
    && apt-get install -y --no-install-recommends libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" gd \
    && apt-get purge -y --auto-remove libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

# wkhtmltopdf: last upstream release (project archived), checksum-verified; its dependencies come via apt
RUN curl -fsSL -o /tmp/wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && echo "98ba0d157b50d36f23bd0dedf4c0aa28c7b0c50fcdcdc54aa5b6bbba81a3941d  /tmp/wkhtmltopdf.deb" | sha256sum --check --status - \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/wkhtmltopdf.deb mariadb-client unzip \
    && rm -rf /var/lib/apt/lists/* /tmp/wkhtmltopdf.deb

# Document root comes from APACHE_DOCUMENT_ROOT at container start (single quotes keep it unexpanded here)
RUN a2enmod rewrite headers \
    && sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# shared/: also used by the legacy images
# Health check, copied after the document-root rewrite above, which would otherwise rewrite its /var/www/ path
COPY shared/apache/healthcheck.conf /etc/apache2/conf-available/healthcheck.conf
RUN mkdir -p /var/www/healthcheck \
    && echo '<?php echo "ok";' > /var/www/healthcheck/index.php \
    && a2enconf healthcheck \
    && chown -R www-data:www-data /var/www \
    && chmod -R 755 /var/www

# Reverse proxies: client IP and HTTPS from X-Forwarded-* headers (APACHE_TRUSTED_PROXIES)
COPY shared/apache/remoteip.conf /etc/apache2/conf-available/remoteip-proxy.conf
COPY shared/apache/remoteip/ /etc/apache2/remoteip/
COPY shared/apache/envvars-remoteip /tmp/
RUN cat /tmp/envvars-remoteip >> /etc/apache2/envvars \
    && rm /tmp/envvars-remoteip \
    && a2enmod remoteip \
    && a2enconf remoteip-proxy

COPY config/php/common.ini /usr/local/etc/php/conf.d/zz-common.ini

# WWW_DATA_UID/GID, PHP_INI_* settings and /docker-entrypoint.d/ hooks, then the official entrypoint
COPY shared/docker-webserver-entrypoint /usr/local/bin/

WORKDIR /src

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS --max-time 4 http://127.0.0.1:8081/ || exit 1

ENTRYPOINT ["docker-webserver-entrypoint"]
CMD ["apache2-foreground"]


FROM base AS dev

ARG XDEBUG_VERSION=3.4.4
RUN install-php-extensions xdebug-${XDEBUG_VERSION} \
    && apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

ENV XDEBUG_MODE=develop,debug \
    XDEBUG_REMOTE_HOST=host.docker.internal \
    XDEBUG_REMOTE_PORT=9003 \
    XDEBUG_IDE_KEY=PHPSTORM \
    XDEBUG_OUTPUT_DIR=/tmp \
    XDEBUG_OUTPUT_PROFILE_NAME=cachegrind.out.%p

COPY config/php/dev.ini /usr/local/etc/php/conf.d/zz-dev.ini
COPY config/php/apcu-dev.ini /usr/local/etc/php/conf.d/zz-apcu.ini
COPY config/php/xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini


# Last stage = default target
FROM base AS prod

ENV SESSION_COOKIE_SECURE=1

COPY config/php/prod.ini /usr/local/etc/php/conf.d/zz-prod.ini
COPY config/php/opcache-prod.ini /usr/local/etc/php/conf.d/zz-opcache.ini
COPY config/php/apcu-prod.ini /usr/local/etc/php/conf.d/zz-apcu.ini
COPY config/apache/prod-hardening.conf /etc/apache2/conf-available/zz-prod-hardening.conf
RUN a2enconf zz-prod-hardening
