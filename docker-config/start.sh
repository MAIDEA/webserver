#!/bin/bash

#novi dir potreban da se nginx ne buni za logove
mkdir -p /var/log/nginx

#php fpm daemon start
php5-fpm -R

#crontab daemon start (uncomment if needed)
#crontab

#main nginx process to run in foreground
nginx -c /etc/nginx/nginx.conf

