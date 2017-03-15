#!/bin/bash

#novi dir potreban da se nginx ne buni za logove
mkdir -p /var/log/nginx

#xdebug iz varijable u konfig
sed -i "s/xdebug\.remote_host\=.*/xdebug\.remote_host\=$XDEBUG_HOST/g" /etc/php5/fpm/conf.d/xdebug.ini
#i u env da radi CLI
export XDEBUG_CONFIG="remote_host=$XDEBUG_HOST"
cp /etc/php5/fpm/conf.d/xdebug.ini /etc/php5/cli/conf.d/xdebug.ini


php5-fpm -R
nginx -c /etc/nginx/nginx.conf

