FROM debian:8.2

ENV DEBIAN_FRONTEND noninteractive

# Install php and nginx
RUN apt-get update && apt-get install -y \
    curl \
    git \
    php5-dev \
    php5-cli \
    php5-mysql \
    php5-intl \
    php5-curl \
    php5-fpm \
    php-pear \
    nginx





#install WKHTMLTOPDF with patched qt (download from website instead of install from source)
RUN curl -sS -o wkhtml.deb http://download.gna.org/wkhtmltopdf/0.12/0.12.2.1/wkhtmltox-0.12.2.1_linux-jessie-amd64.deb

#wkhtml rewuirements
RUN apt-get install -y fontconfig libxrender1 xfonts-base xfonts-75dpi
RUN dpkg -i wkhtml.deb
RUN rm wkhtml.deb    


# According to the Docker way, your container should run only one service.
# That�s the whole purpose of using containers after all.
# So, instead of backgrounding your service, you should leave it running in the foreground.
# You basically run one command, that�s the sole purpose of your container. A very simple-minded container :)
RUN echo "daemon off;" >> /etc/nginx/nginx.conf

# Find the line, cgi.fix_pathinfo=1, and change the 1 to 0.
RUN sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
RUN sed -i "s/;listen.allowed_clients = 127.0.0.1/listen.allowed_clients = 0.0.0.0/" /etc/php5/fpm/pool.d/www.conf
RUN sed -i "s/short_open_tag = Off/short_open_tag = On/" /etc/php5/fpm/php.ini

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer


# Install the server start script
COPY docker-config/start.sh /start.sh
RUN chmod u+x /start.sh

RUN rm /etc/nginx/sites-enabled/*
COPY docker-config/vhosts/* /etc/nginx/sites-enabled/

CMD /start.sh
