#!/bin/bash
max_restarts=5
restarts=0
container_name="your_container_name"

while true; do
    docker events --filter container=$container_name --filter event=die |
    while read event; do
        if [ $restarts -lt $max_restarts ]; then
            echo "Restarting container ($((restarts+1))/$max_restarts)"
            docker restart $container_name
            restarts=$((restarts+1))
        else
            echo "Max restarts reached. Stopping container."
            docker stop $container_name
            exit 0
        fi
    done
done

#!/bin/bash

# Check if NGINX is running
if ! curl -k -f https://localhost/ > /dev/null 2>&1; then
    echo "Error: NGINX is not responding or the site is inaccessible."
    exit 1
fi

# Check internet connectivity (e.g., ping Google's DNS)
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Error: No internet connection."
    exit 1
fi

echo "NGINX is healthy."
exit 0

#!/bin/bash

# Check if WordPress is responding
if ! curl -k -f https://nginx/wp-admin/install.php > /dev/null 2>&1; then
    echo "Error: WordPress is not responding at /wp-admin/install.php."
    exit 1
fi

# Check internet connectivity (e.g., ping Google's DNS)
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Error: No internet connection."
    exit 1
fi

echo "WordPress is healthy."
exit 0

#!/bin/bash

# Define credentials
DB_USER="your_db_user"
DB_PASS="your_db_password"

# Check if MariaDB is running
if ! mysqladmin -u$DB_USER -p$DB_PASS ping -h localhost > /dev/null 2>&1; then
    echo "Error: MariaDB is not responding or inaccessible."
    exit 1
fi

# Check internet connectivity (optional, only if required)
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Error: No internet connection."
    exit 1
fi

echo "MariaDB is healthy."
exit 0
