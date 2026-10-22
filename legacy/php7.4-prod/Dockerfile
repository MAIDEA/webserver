# maidea: official 7.4 recipe rebuilt with the CVE-2026-109618/109619 patch (legacy/php7.4-base, built first by scripts/build.sh)
FROM maidea-local/php:7.4.33-cve-patched-apache-bullseye

COPY _docker-config/php.ini /usr/local/etc/php/

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# Debian 11 left long-term support; its packages now live on archive.debian.org
RUN printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list

RUN apt-get update && apt-get remove composer && apt-get install -y \
    pkg-config \
    curl \
    git \
    libxml2-dev \
    mariadb-client \
    libmcrypt-dev \
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
    libmpdec-dev \
    libzip-dev \
    libwebp-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pecl update-channels
RUN pecl install apcu-5.1.22 \
    && pecl install xdebug-3.1.5 \
    && echo "date.timezone = \"UTC\"" >> /usr/local/etc/php/conf.d/timezone.ini

RUN pecl install mcrypt-1.0.3 \
    && pecl install decimal-1.4.0

RUN docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install intl \
    && docker-php-ext-install -j$(nproc) pdo_mysql \
    && docker-php-ext-enable mcrypt \
    && docker-php-ext-install pcntl \
    && docker-php-ext-install zip \
    && docker-php-ext-install bcmath \
    && docker-php-ext-install shmop \
    && PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install imap \
    && docker-php-ext-install sockets \
    && docker-php-ext-install soap \
    && docker-php-ext-install -j$(nproc) opcache \
    && docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
    && docker-php-ext-install pdo pdo_pgsql pgsql \
    && echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini \
    && echo "apc.shm_size=512M" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini

RUN a2enmod rewrite

RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

# Download, extract and move wkhtml in place
WORKDIR /tmp
RUN curl -S -s -L -o wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_amd64.deb \
    && dpkg -i wkhtmltopdf.deb

WORKDIR /src

#change webroot
ENV APACHE_DOCUMENT_ROOT /src/app/webroot
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf



#  ALL POSSIBLE PHP EXTENSIONS and requirements
#
#RUN apt update
#RUN apt upgrade -y
#RUN apt install -y apt-utils
#RUN a2enmod rewrite
#RUN apt install -y libmcrypt-dev
#RUN docker-php-ext-install mcrypt
#RUN apt install -y libicu-dev
#RUN docker-php-ext-install -j$(nproc) intl
#RUN apt-get install -y libfreetype6-dev libjpeg62-turbo-dev libpng12-dev
#RUN docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/
#RUN docker-php-ext-install -j$(nproc) gd
#RUN apt install -y php-apc
#RUN apt install -y libxml2-dev
#RUN apt install -y libldb-dev
#RUN apt install -y libldap2-dev
#RUN apt install -y libxml2-dev
#RUN apt install -y libssl-dev
#RUN apt install -y libxslt-dev
#RUN apt install -y libpq-dev
#RUN apt install -y postgresql-client
#RUN apt install -y mysql-client
#RUN apt install -y libsqlite3-dev
#RUN apt install -y libsqlite3-0
#RUN apt install -y libc-client-dev
#RUN apt install -y libkrb5-dev
#RUN apt install -y curl
#RUN apt install -y libcurl3
#RUN apt install -y libcurl3-dev
#RUN apt install -y firebird-dev
#RUN apt-get install -y libpspell-dev
#RUN apt-get install -y aspell-en
#RUN apt-get install -y aspell-de
#RUN apt install -y libtidy-dev
#RUN apt install -y libsnmp-dev
#RUN apt install -y librecode0
#RUN apt install -y librecode-dev
#RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer
##RUN pecl install apc
#RUN docker-php-ext-install opcache
#RUN yes | pecl install xdebug \
#    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
#    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/xdebug.ini \
#    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/xdebug.ini
#RUN docker-php-ext-install soap
#RUN docker-php-ext-install ftp
#RUN docker-php-ext-install xsl
#RUN docker-php-ext-install bcmath
#RUN docker-php-ext-install calendar
#RUN docker-php-ext-install ctype
#RUN docker-php-ext-install dba
#RUN docker-php-ext-install dom
#RUN docker-php-ext-install zip
#RUN docker-php-ext-install session
#RUN docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu
#RUN docker-php-ext-install ldap
#RUN docker-php-ext-install json
#RUN docker-php-ext-install hash
#RUN docker-php-ext-install sockets
#RUN docker-php-ext-install pdo
#RUN docker-php-ext-install mbstring
#RUN docker-php-ext-install tokenizer
#RUN docker-php-ext-install pgsql
#RUN docker-php-ext-install pdo_pgsql
#RUN docker-php-ext-install pdo_mysql
#RUN docker-php-ext-install pdo_sqlite
#RUN docker-php-ext-install intl
#RUN docker-php-ext-install mcrypt
#RUN docker-php-ext-install mysqli
#RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl
#RUN docker-php-ext-install imap
#RUN docker-php-ext-install gd
#RUN docker-php-ext-install curl
#RUN docker-php-ext-install exif
#RUN docker-php-ext-install fileinfo
#RUN docker-php-ext-install gettext
##RUN apt install -y libgmp-dev # idk
##RUN docker-php-ext-install gmp # idk
#RUN docker-php-ext-install iconv
#RUN docker-php-ext-install interbase
#RUN docker-php-ext-install pdo_firebird
#RUN docker-php-ext-install opcache
##RUN docker-php-ext-install oci8 # idk
##RUN docker-php-ext-install odbc # idk
#RUN docker-php-ext-install pcntl
##RUN apt install -y freetds-dev # idk
##RUN docker-php-ext-install pdo_dblib  # idk
##RUN docker-php-ext-install pdo_oci # idk
##RUN docker-php-ext-install pdo_odbc # idk
#RUN docker-php-ext-install phar
#RUN docker-php-ext-install posix
#RUN docker-php-ext-install pspell
##RUN apt install -y libreadline-dev # idk
##RUN docker-php-ext-install readline # idk
#RUN docker-php-ext-install recode
#RUN docker-php-ext-install shmop
#RUN docker-php-ext-install simplexml
#RUN docker-php-ext-install snmp
#RUN docker-php-ext-install sysvmsg
#RUN docker-php-ext-install sysvsem
#RUN docker-php-ext-install sysvshm
#RUN docker-php-ext-install tidy
#RUN docker-php-ext-install wddx
#RUN docker-php-ext-install xml
##RUN apt install -y libxml2-dev # idk
##RUN docker-php-ext-install xmlreader # idk
#RUN docker-php-ext-install xmlrpc
#RUN docker-php-ext-install xmlwriter
## idk bz2 enchant

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
