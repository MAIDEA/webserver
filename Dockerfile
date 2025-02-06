ARG BUILDPLATFORM=linux/amd64

# Build stage
FROM --platform=${BUILDPLATFORM} php:5.6-apache-stretch AS builder

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
    && rm -rf /var/lib/apt/lists/*

# Build and configure PHP extensions
RUN docker-php-ext-configure gd \
        --with-gd \
        --with-png-dir=/usr/include \
        --with-jpeg-dir=/usr/include \
        --with-freetype-dir=/usr/include \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
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
        pdo_mysql \
        gd \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && pecl update-channels \
    && pecl install xdebug-2.5.5

# Final stage
FROM --platform=${BUILDPLATFORM} php:5.6-apache-stretch

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

# Enable PHP extensions and configure PHP
RUN docker-php-ext-install sockets \
    && docker-php-ext-install json \
    && docker-php-ext-enable \
    xdebug \
    intl \
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
    } > /usr/local/etc/php/conf.d/custom-php.ini

# Configure XDebug
RUN { \
    echo "xdebug.remote_enable=on"; \
    echo "xdebug.remote_host=\${XDEBUG_REMOTE_HOST}"; \
    echo "xdebug.idekey=\${XDEBUG_IDE_KEY}"; \
    } > /usr/local/etc/php/conf.d/xdebug.ini

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
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /src

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost/ || exit 1

CMD ["apache2-foreground"]