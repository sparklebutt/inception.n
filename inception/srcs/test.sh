#!/bin/sh

# Change to the directory where the script is located
cd "$(dirname "$0")"

# Source the .env file to load environment variables
if [ -f .env ]; then
	export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
else
	echo ".env file not found"
	exit 1
fi


# Function to wait for a service to be healthy
wait_for_service() {
	local service=$1
	local port=$2
	local retries=30
	local count=0

	# Test connectivity based on the service type
	# php is tested through nginx, because curling wordpress directly does not work, 
	# this is because curl comminictaes with html, whereas wordpress relies on php-fpm which 
	# can not translate html. This test sends and then recieves , if the reciveing value is an OK 200
	# it shows that nginx is communicating with wordpress
if [ "$port" = "9000" ]; then
    echo "Testing PHP-FPM connection through Nginx on port $port..."
    while [ $count -lt $retries ]; do
        echo "Checking if $service is ready to handle PHP requests (attempt $((count + 1))/$retries)..."
        if docker exec nginx curl -k -s -o /dev/null -w "%{http_code}" https://localhost >/dev/null; then
        #if [ $? -eq 0 ]; then
            echo "$service PHP-FPM is successfully responding on port $port through Nginx."
            return 0
        fi
        echo "Waiting for $service PHP-FPM to be ready on port $port..."
        count=$((count + 1))
        sleep 5
    done
else
    while [ $count -lt $retries ]; do
        echo "Checking if $service is up on port $port (attempt $((count + 1))/$retries)..."
        docker exec $service curl -k -s http://localhost:$port >/dev/null
        if [ $? -eq 0 ]; then
            echo "$service is up and running on port $port"
            return 0
        fi
        echo "Waiting for $service to be ready on port $port..."
        count=$((count + 1))
        sleep 5
    done
fi

echo "Error: $service did not become ready in time on port $port"
return 1
}
# Wait for Nginx and WordPress to be ready
wait_for_service nginx 443
if [ $? -ne 0 ]; then
	echo "Nginx did not become ready in time"
	exit 1
fi

wait_for_service wordpress 9000
if [ $? -ne 0 ]; then
	echo "WordPress did not become ready in time"
	exit 1
fi

# Test if the Nginx configuration contains the server_name directive
docker exec nginx cat /etc/nginx/nginx.conf | grep 'server_name'
if [ $? -ne 0 ]; then
	echo "Test Failed: Nginx configuration is incorrect or not being used"
	echo "Contents of /etc/nginx/nginx.conf:"
	docker exec nginx cat /etc/nginx/nginx.conf
	exit 1
else
	echo "Test Passed: Nginx configuration contains the server_name directive"
fi

# Additional checks to ensure environment variables are correctly substituted
docker exec nginx cat /etc/nginx/nginx.conf | grep '${DOMAIN_NAME}'
if [ $? -eq 0 ]; then
	echo "Test Failed: Environment variable DOMAIN_NAME was not substituted"
	echo "Contents of /etc/nginx/nginx.conf:"
	docker exec nginx cat /etc/nginx/nginx.conf
	exit 1
fi

docker exec nginx cat /etc/nginx/nginx.conf | grep '${SECURE_PORT}'
if [ $? -eq 0 ]; then
	echo "Test Failed: Environment variable SECURE_PORT was not substituted"
	echo "Contents of /etc/nginx/nginx.conf:"
	docker exec nginx cat /etc/nginx/nginx.conf
	exit 1
fi

docker exec nginx cat /etc/nginx/nginx.conf | grep '${WORDPRESS_PORT}'
if [ $? -eq 0 ]; then
	echo "Test Failed: Environment variable WORDPRESS_PORT was not substituted"
	echo "Contents of /etc/nginx/nginx.conf:"
	docker exec nginx cat /etc/nginx/nginx.conf
	exit 1
fi

echo "Testing NGINX for TLSv1.1 (this should be blocked)..."
docker exec nginx curl -v --tls-max 1.1 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is a failure for this test
    echo "Test Failed: NGINX allowed TLSv1.1 (this is not expected)"
    exit 1
else
    # Non-zero exit code indicates the connection failed, which is what we want
    echo "Test Passed: NGINX correctly blocked TLSv1.1"
fi
echo "Testing NGINX for TLSv1.4 (this should be blocked (version dosnt exist yet, if this establishes a connection something wild has happened))..."
docker exec nginx curl -v --tls-max 1.4 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is a failure for this test
    echo "Test Failed: NGINX allowed TLSv1.4 (this is not expected)"
    exit 1
else
    # Non-zero exit code indicates the connection failed, which is what we want
    echo "Test Passed: NGINX correctly blocked TLSv1.4"
fi

#echo "Testing NGINX for TLSv1.2 (this should be blocked)..."
#docker exec nginx curl -v --tls-max 1.2 https://localhost >/dev/null 2>&1
#if [ $? -eq 0 ]; then
#    # If exit code is 0, the connection succeeded, which is what we want 
#    echo "Test Passed: NGINX allowed TLSv1.2 "
#else
#    # Non-zero exit code indicates the connection failed, unexpected
#    echo "Test Failed: NGINX  blocked TLSv1.2"
#    exit 1
#fi

#echo "Testing NGINX for TLSv1.3 (this should be blocked)..."
#docker exec nginx curl -v --tls-max 1.2 https://localhost >/dev/null 2>&1
#if [ $? -eq 0 ]; then
#    # If exit code is 0, the connection succeeded, which is what we want
#    echo "Test Passed: NGINX allowed TLSv1.3 "
#else
#    # Non-zero exit code indicates the connection failed, unexpected
#    echo "Test Failed: NGINX  blocked TLSv1.3"
#    exit 1
#fi

echo "All nginx tests passed successfully."

# Test if WordPress home page is up and running
docker exec nginx curl -k -s https://localhost:${SECURE_PORT} | grep 'WordPress Site'
if [ $? -ne 0 ]; then
	echo "Test Failed: WordPress home page not served correctly"
	echo "Nginx logs:"
	docker exec nginx cat /var/log/nginx/error.log
	docker exec nginx cat /var/log/nginx/access.log
	echo "WordPress logs:"
	docker exec wordpress cat /var/log/nginx/error.log
	docker exec wordpress cat /var/log/nginx/access.log
	exit 1
else
	echo "Test Passed: WordPress home page served correctly"
fi

# Test if WordPress login page is accessible
docker exec nginx curl -k -s https://localhost:${SECURE_PORT}/wp-login.php | grep 'Log In'
if [ $? -ne 0 ]; then
	echo "Test Failed: WordPress login page not accessible"
	exit 1
fi

# Test database connection via WordPress
docker exec wordpress wp db check --path=/var/www/html
if [ $? -ne 0 ]; then
	echo "Test Failed: WordPress cannot connect to the database"
	exit 1
fi

# Test if PHP-FPM is running
docker exec wordpress ps aux | grep php-fpm | grep -v grep
if [ $? -ne 0 ]; then
	echo "Test Failed: PHP-FPM is not running"
	exit 1
fi

# Test if WordPress directory has correct permissions
docker exec wordpress ls -ld /var/www/html | grep 'nginx'
if [ $? -ne 0 ]; then
	echo "Test Failed: WordPress directory permissions are incorrect"
	exit 1
fi

# Test if SSL/TLS certificate is being served correctly
docker exec nginx curl -k -s --head https://localhost:${SECURE_PORT} | grep '200 OK'
if [ $? -ne 0 ]; then
	echo "Test Failed: SSL/TLS certificate not served correctly"
	exit 1
fi
