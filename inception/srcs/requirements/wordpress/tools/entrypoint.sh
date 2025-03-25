#!/bin/sh

set -e

envsubst < /etc/php83/php-fpm.d/www.conf.template > /etc/php83/php-fpm.d/www.conf

echo "Testing database connection..."
#echo "WORDPRESS_DB_HOST=${WORDPRESS_DB_HOST}"

until mysql -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" -e "USE ${WORDPRESS_DB_NAME};"; do
  echo "waiting for database connection .....!"
  sleep 10
done

#echo "Database connection successful."

#echo "Listing databases:"
#mysql -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" "${WORDPRESS_DB_NAME}" <<EOF
#SHOW DATABASES;
#EOF

echo "ATTEMPTING TO INSTALL WORDPRESS"
# Install WordPress
if ! wp core is-installed --path="/var/www/html"; then
  echo "WordPress is being installed"

  if ! wp core download --path=/var/www/html; then
    echo "Error downloading WordPress"
    exit 1
  fi

  # Create wp-config.php
  if ! wp config create --dbname="${MYSQL_DATABASE}" --dbuser="${MYSQL_USER}" --dbpass="${MYSQL_PASSWORD}" --dbhost="${DB_HOST}" --path=/var/www/html --allow-root --force; then
    echo "Error creating wp-config.php"
    exit 1
  fi

  if ! wp core install --url="https://${DOMAIN_NAME}" --title="WordPress Site" --admin_user="${ADMIN_UNAME}" --admin_password="${BOSS_PASS}" --admin_email="admin@example.com" --allow-root --skip-email --path=/var/www/html; then
    echo "Error installing WordPress"
    exit 1
  fi

  if ! wp user create "${GUEST_UNAME}" user@example.com --user_pass="${GUEST_PASS}" --role=editor --allow-root --path=/var/www/html; then
    echo "Error creating additional user"
    exit 1
  fi

  wp theme install neve --activate --allow-root
  wp plugin update --all
else
  echo "WordPress is already installed."
fi

# Update WP address and site address to match our domain
wp option update siteurl "https://$DOMAIN_NAME" --allow-root
wp option update home "https://$DOMAIN_NAME" --allow-root

exec php-fpm83 -F
