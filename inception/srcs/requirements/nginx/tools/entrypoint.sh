#!/bin/sh

sed -i "s|\${CRT_PATH}|${CRT_PATH}|g" /etc/nginx/nginx.conf
sed -i "s|\${KEY_PATH}|${KEY_PATH}|g" /etc/nginx/nginx.conf
sed -i "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" /etc/nginx/nginx.conf
sed -i "s|\${WORDPRESS_PORT}|${WORDPRESS_PORT}|g" /etc/nginx/nginx.conf

nginx -g "daemon off;" -c /etc/nginx/nginx.conf