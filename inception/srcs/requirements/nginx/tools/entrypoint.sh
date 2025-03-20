#!/bin/sh

# Substitute environment variables in the template and create final config
#envsubst '${DOMAIN_NAME} ${SECURE_PORT}' <  etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf 
#etc/nginx/nginx.conf.template >/etc/nginx/nginx.conf
#sed 's/__DOLLAR__/$/g' /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
#&& \
#	sed 's/__DOLLAR__/$/g' /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Start Nginx
nginx -g "daemon off;" -c /etc/nginx/nginx.conf
# exec this command

# remove comments  
#!/bin/sh
# something to look into below
# Validate environment variables
#if [ -z "$DOMAIN_NAME" ]; then
#    echo "Error: DOMAIN_NAME is not set."
#    exit 1
#fi

# Create necessary directories and set permissions
#mkdir -p /var/www/html
#chown -R nginx:nginx /var/www/html

# Wait for database connection (example health check)
#until nc -z -v -w30 database 3306
#do
#  echo "Waiting for database connection..."
#  sleep 1
#done

# Start Nginx
#nginx -g "daemon off;"
