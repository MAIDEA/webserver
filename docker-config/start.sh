#!/bin/bash


#novi dir potreban da se nginx ne buni
mkdir -p /var/log/nginx

php5-fpm -R
nginx -c /etc/nginx/nginx.conf

