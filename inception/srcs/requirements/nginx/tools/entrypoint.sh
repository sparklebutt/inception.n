#!/bin/sh

sed -i "s|\${CRT_PATH}|${CRT_PATH}|g" /etc/nginx/nginx.conf.template
sed -i "s|\${KEY_PATH}|${KEY_PATH}|g" /etc/nginx/nginx.conf.template

nginx -g "daemon off;" -c /etc/nginx/nginx.conf