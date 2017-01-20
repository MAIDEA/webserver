FROM debian:8

ENV DEBIAN_FRONTEND noninteractive

# Install php and nginx
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y \
    cron \
    curl \
    git \
    php5-dev \
    php5-cli \
    php5-mysql \
    php5-intl \
    php5-curl \
    php5-fpm \
    php-pear \
    php5-sqlite \
    nginx \
    supervisor




ENV NGINX_DIR=/opt/nginx \
    PHP_DIR=/opt/php \
    PHP_CONFIG_TEMPLATE=/opt/php-configs \
    PHP56_DIR=/opt/php56 \
    PHP70_DIR=/opt/php70 \
    PHP71_DIR=/opt/php71 \
    LOG_DIR=/var/log/app_engine \
    APP_DIR=/app \
    NGINX_USER_CONF_DIR=/etc/nginx/conf.d \
    UPLOAD_DIR=/upload \
    SESSION_SAVE_PATH=/tmp/sessions \
    NGINX_VERSION=1.10.2 \
    PHP56_VERSION=5.6.29 \
    PHP70_VERSION=7.0.14 \
    PHP71_VERSION=7.1.0 \
    PATH=/opt/php/bin:$PATH \
    WWW_HOME=/app/webroot






#install WKHTMLTOPDF with patched qt (download from website instead of install from source)
RUN curl -sS -o wkhtml.deb http://download.gna.org/wkhtmltopdf/0.12/0.12.2.1/wkhtmltox-0.12.2.1_linux-jessie-amd64.deb

#wkhtml rewuirements
RUN apt-get install -y fontconfig libxrender1 xfonts-base xfonts-75dpi
RUN dpkg -i wkhtml.deb
#RUN rm wkhtml.deb



#symlink nginx logs to stdout for docker loging - based on official nginx image
#RUN ln -sf /dev/stdout /var/log/nginx/access.log \
#	&& ln -sf /dev/stderr /var/log/nginx/error.log


# Put other config and shell files into place.
COPY nginx.conf gzip_params fastcgi_params /etc/nginx/
#COPY nginx-app.conf $NGINX_USER_CONF_DIR
COPY supervisord.conf /etc/supervisor/supervisord.conf
#COPY logrotate.app_engine /etc/logrotate.d/app_engine
#COPY entrypoint.sh composer.sh whitelist_functions.php /
COPY php-fpm.conf php.ini php-cli.ini /etc/php5/fpm/




# Lock down the web directories
RUN mkdir -p $APP_DIR $LOG_DIR $UPLOAD_DIR $SESSION_SAVE_PATH \
        $NGINX_USER_CONF_DIR $WWW_HOME \
    && chown -R www-data.www-data \
        $APP_DIR $UPLOAD_DIR $SESSION_SAVE_PATH $LOG_DIR \
        $NGINX_USER_CONF_DIR $WWW_HOME \
    && chmod 755 $UPLOAD_DIR $SESSION_SAVE_PATH \
    # For easy access to php with `su www-data -c $CMD`
    && ln -sf ${PHP_DIR}/bin/php /usr/bin/php





#ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
