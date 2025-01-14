# Production image
FROM --platform=${BUILDPLATFORM} php:8.4-apache-bookworm

# Environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHP_MEMORY_LIMIT=1024M \
    APACHE_DOCUMENT_ROOT=/src/app/webroot

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    curl \
    libxml2-dev \
    mariadb-client \
    libicu-dev \
    libc-client-dev \
    libkrb5-dev \
    libpng-dev \
    libfontconfig \
    zlib1g \
    libfreetype6 \
    libxrender1 \
    libxext6 \
    libx11-6 \
    fontconfig \
    xfonts-base \
    xfonts-75dpi \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    libwebp-dev \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Install mpdecimal from source (required for decimal extension)
RUN cd /tmp \
    && curl -LO https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-2.5.1.tar.gz \
    && echo "9f9cd4c041f99b5c49ffb7b59d9f12d95b683d88585608aa56a6307667b2b21f mpdecimal-2.5.1.tar.gz" | sha256sum --check --status - \
    && tar xf mpdecimal-2.5.1.tar.gz \
    && cd mpdecimal-2.5.1 \
    && ./configure \
    && make \
    && make install \
    && cd .. \
    && rm -rf mpdecimal-2.5.1*

# Configure and install PHP extensions
RUN pecl update-channels \
    && pecl install apcu decimal imap \
    && docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        pdo_mysql \
        pcntl \
        zip \
        bcmath \
        shmop \
        sockets \
        soap \
        opcache \
        pdo \
        pdo_pgsql \
        pgsql \
    && docker-php-ext-enable \
        apcu \
        decimal \
        imap

# Production PHP Configuration
RUN { \
    echo 'short_open_tag = On'; \
    echo 'output_buffering = 4096'; \
    echo 'max_execution_time = 60'; \
    echo 'max_input_time = 60'; \
    echo 'memory_limit = ${PHP_MEMORY_LIMIT}'; \
    echo 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_STRICT'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'html_errors = Off'; \
    echo 'default_charset = "UTF-8"'; \
    echo 'post_max_size = 256M'; \
    echo 'upload_max_filesize = 256M'; \
    echo 'max_file_uploads = 20'; \
    echo 'date.timezone = UTC'; \
    echo 'variables_order = "EGPCS"'; \
    echo 'realpath_cache_size = 4096k'; \
    echo 'realpath_cache_ttl = 600'; \
    echo 'session.use_strict_mode = 1'; \
    echo 'session.use_cookies = 1'; \
    echo 'session.use_only_cookies = 1'; \
    echo 'session.cookie_secure = 1'; \
    echo 'session.cookie_httponly = 1'; \
    echo 'session.use_trans_sid = 0'; \
    echo 'session.cache_limiter = nocache'; \
    echo 'session.sid_length = 48'; \
    echo 'session.sid_bits_per_character = 6'; \
    } > /usr/local/etc/php/conf.d/custom-php.ini

# Configure OpCache for production
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.enable_cli=0'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.validate_timestamps=0'; \
    echo 'opcache.revalidate_freq=0'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.optimization_level=0x7FFEBFFF'; \
    echo 'opcache.jit_buffer_size=50M'; \
    echo 'opcache.jit=1235'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# APCu settings
RUN { \
    echo 'apc.enable_cli=0'; \
    echo 'apc.shm_size=512M'; \
    echo 'apc.ttl=7200'; \
    } > /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install wkhtmltopdf
RUN curl -S -s -L -o /tmp/wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && dpkg -i /tmp/wkhtmltopdf.deb \
    && rm /tmp/wkhtmltopdf.deb

# Configure Apache
RUN a2enmod rewrite headers
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Apache security configuration
RUN { \
    echo 'ServerTokens Prod'; \
    echo 'ServerSignature Off'; \
    echo 'TraceEnable Off'; \
    } >> /etc/apache2/apache2.conf

# Set proper permissions
RUN chown -R www-data:www-data /var/www \
    && chmod -R 755 /var/www

WORKDIR /src

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80

CMD ["apache2-foreground"]