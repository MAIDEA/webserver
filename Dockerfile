# Build stage for development
FROM --platform=${BUILDPLATFORM} php:8.4-apache-bookworm

# Optional image build arguments
ARG XDEBUG_REMOTE_PORT=9003
ARG XDEBUG_IDE_KEY=PHPSTORM
ARG XDEBUG_MODE=develop,debug
ARG XDEBUG_OUTPUT_DIR=/tmp
ARG XDEBUG_OUTPUT_PROFILE_NAME=cachegrind.out.%p

# Environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHP_MEMORY_LIMIT=1024M \
    APACHE_DOCUMENT_ROOT=/src/app/webroot \
    XDEBUG_MODE=${XDEBUG_MODE} \
    XDEBUG_IDE_KEY=${XDEBUG_IDE_KEY} \
    XDEBUG_OUTPUT_DIR=${XDEBUG_OUTPUT_DIR} \
    XDEBUG_OUTPUT_PROFILE_NAME=${XDEBUG_OUTPUT_PROFILE_NAME}


# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    curl \
    git \
    libxml2-dev \
    mariadb-client \
    libreadline-dev \
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
    && rm -rf /var/lib/apt/lists/*

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
    && pecl install apcu xdebug decimal imap \
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
        xdebug \
        apcu \
        decimal \
        imap

# PHP Configuration
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
    } > /usr/local/etc/php/conf.d/custom-php.ini \
    && echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini \
    && echo "apc.shm_size=512M" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini

# Configure XDebug
RUN echo "xdebug.mode=\${XDEBUG_MODE}" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.client_host=\${XDEBUG_REMOTE_HOST}" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.start_with_request=trigger" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.trigger_value=\${XDEBUG_IDE_KEY}" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.output_dir=\${XDEBUG_OUTPUT_DIR}" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.profiler_output_name=\${XDEBUG_OUTPUT_PROFILE_NAME}" >> /usr/local/etc/php/conf.d/xdebug.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install wkhtmltopdf
RUN curl -S -s -L -o /tmp/wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && dpkg -i /tmp/wkhtmltopdf.deb \
    && rm /tmp/wkhtmltopdf.deb

# Configure Apache
RUN a2enmod rewrite
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /src

EXPOSE 80

CMD ["apache2-foreground"]