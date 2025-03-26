#!/bin/sh

set -e  # Exit immediately if a command exits with a non-zero status

# Substitute environment variables in mariadb.cnf.template
envsubst < etc/mysql/mariadb.cnf.template > /etc/my.cnf


chmod 644 /etc/my.cnf

if [ ! -d "/var/lib/mysql/mysql" ]; then
  mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

chown -R mysql:mysql /var/lib/mysql /run/mysqld /var/log/mysql

#temp start of mariadb for init of database and users
mysqld_safe & 

#--skip-networking &
pid="$!"
# Wait for MariaDB to be ready
until mysqladmin ping --silent; do
  echo "Waiting for MariaDB to be ready..."
  sleep 2
done

# Create the database and user, and grant privileges this goes into a init-db.sh
mysql -u root <<-EOSQL
  CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
  CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
  GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
  FLUSH PRIVILEGES;
EOSQL

mysqladmin -u root shutdown

exec mysqld_safe
#wait $pid
