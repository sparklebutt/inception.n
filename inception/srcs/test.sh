#!/bin/sh


# isntalls required, curl and nmap

# Change to the directory where the script is located
cd "$(dirname "$0")"

# Source the .env file to load environment variables
if [ -f .env ]; then
	export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
else
	echo ".env file not found"
	exit 1
fi

NGINX=nginx #nginx continaer name
WORDPRESS=wordpress #wordpress continaer name
MARIADB=mariadb #mariadb container name
NETWORK=inceptionnet # name of internal network defined in yaml file
SECURE_PORT=${SECURE_PORT:-443} #secure port for nginx
WORDPRESS_PORT=${WORDPRESS_PORT:-9000} #wordpress port
DOMAIN_NAME=${DOMAIN_NAME:-localhost} # adjust this to domain name
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

echo "-----------Checking containers--------"
running_containers=$(docker ps --format '{{.Names}}')
count_running=$(echo "$running_containers" | wc -l)

if [ $count_running -eq 3 ]; then
    echo "Test Passed: Exactly 3 containers are running."
    echo "Container Names:"
    echo "$running_containers"
else
    echo "Test Failed: Expected 3 containers, but $count_running are running."
    echo "Container Names:"
    echo "$running_containers"
    exit 1
fi

echo "---------Testing internal docker network"

network_name="inceptionnet"

# Get list of containers in the network
connected_containers=$(docker network inspect $network_name | grep '"Name":' | awk -F '"' '{print $4}')

# Verify all expected containers are connected
expected_containers="nginx wordpress mariadb"
for container in $expected_containers; do
    if echo "$connected_containers" | grep  -w $container ; then
        echo "Test Passed: $container is connected to the $network_name network."
    else
        echo "Test Failed: $container is NOT connected to the $network_name network."
        exit 1
    fi
done

docker network inspect $network_name | grep -i "internal"
if [ $? -eq 0]; then
	echo "network is internal great job"
else
	echo "NETWORK NOT INTERNAL CHECK RESULTS BELOW"
fi


# Define the container names
containers="wordpress mariadb"
entrypoint_risk=false

# Function to get the container's IP
get_container_ip() {
    docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $1
}

# Function to scan ports using nmap
scan_ports() {
    local container=$1
    local ip=$2

    echo "Scanning ports for $container ($ip)..."
    nmap_result=$(nmap -p- --open -T4 $ip)
    echo "$nmap_result"

    # Check for open ports
    open_ports=$(echo "$nmap_result" | grep "open" | awk '{print $1}' | cut -d '/' -f 1)
    if [ -z "$open_ports" ]; then
	echo "✅ No open ports detected for $container."
	entrypoint_risk=false
    else
	echo "⚠️  Potential entrypoint risk: $container: $open_ports !"
        entrypoint_risk=true
    fi
    echo $open_ports
}

check_service_access() {
    local container=$1
    local ip=$2
    local ports=$3

    echo "Testing access for $container on $ip for the following ports: $open_ports"

    for port in $ports; do
        echo "Testing port $port on $container..."

        if [ "$container" == "wordpress" ]; then
            # Test HTTP for WordPress
            result=$(curl -s --head http://$ip:$port)
            if [ -z "$result" ]; then
                echo "✅ No HTTP response detected on port $port for $container."
            else
                echo "⚠️  HTTP response detected on port $port! Potential entrypoint risk for $container."
                entrypoint_risk=true
            fi
        elif [ "$container" == "mariadb" ]; then
            # Test SQL for MariaDB (only check if port is 3306)
            if [ "$port" -eq 3306 ]; then
                result=$(mysql -h $ip -P $port -u root -p 2>/dev/null)
                if [ $? -ne 0 ]; then
                    echo "✅ No SQL access detected on port $port for $container."
                else
                    echo "⚠️  SQL access detected on port $port! Potential entrypoint risk for $container."
                    entrypoint_risk=true
                fi
            else
                echo "⚠️  Port $port on $container is open but not expected for SQL. Investigate further."
                entrypoint_risk=true
            fi
        else
            echo "⚠️  Unknown container type for $container. Skipping protocol-specific tests."
        fi
    done
    echo
}

# Main logic for testing each container
for container in $containers; do
    ip=$(get_container_ip $container)

    if [ -z "$ip" ]; then
        echo "❌ Failed to retrieve IP for $container. may not be providing seperate ips for containers, what type of network are the continaers using?"
        continue
    fi

    echo "Testing $container ($ip)..."
    # Scan all ports
    #scan_ports $container $ip
	open_ports=$(scan_ports $container $ip)
    # Test specific services
    #if [ "$container" == "wordpress" ]; then
    #    check_service_access $container $ip 9000 "HTTP"
    #elif [ "$container" == "mariadb" ]; then
    #    check_service_access $container $ip 3306 "SQL"
    if [ -n $open_prts ]; then
         check_service_access $continaer $ip "$open_ports"
    fi
done

# Summarize results
if [ "$entrypoint_risk" = true ]; then
    echo "⚠️  One or more containers may be acting as entrypoints. Investigate further!"
else
    echo "✅ All tests passed! No entrypoint risks detected for WordPress or MariaDB."
fi

echo "---------Testing server name configured--------"
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


for var in '${DOMAIN_NAME}' '${SECURE_PORT}' '${WORDPRESS_PORT}'; do
{
	if docker exec nginx cat /etc/nginx/nginx.conf | grep "$var" ; then
		echo "Test Failed: Environment variable $var was not substituted"
		echo "Contents of /etc/nginx/nginx.conf:"
		docker exec nginx cat /etc/nginx/nginx.conf
		exit 1
	else
		echo "Test Passed: Environment variable $var was substituted in nginx.conf"
	fi
}
done

docker exec nginx curl -k -s https://localhost:${SECURE_PORT}/wp-admin/setup-config.php >/dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "Test Passed: nginx and mariadb are communicating"
else
	echo "Test Failed: nginx can not access mariadb"
	exit 1
fi


echo "Testing NGINX for TLSv1.1 (this should be blocked)..."
docker exec nginx curl -k -v --tls-max 1.1 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is a failure for this test
    echo "Test Failed: NGINX allowed TLSv1.1 (this is not expected)"
    exit 1
else
    # Non-zero exit code indicates the connection failed, which is what we want
    echo "Test Passed: NGINX correctly blocked TLSv1.1"
fi
echo "Testing NGINX for TLSv1.4 (this should be blocked (version dosnt exist yet, if this establishes a connection something wild has happened))..."
docker exec nginx curl -k -v --tls-max 1.4 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is a failure for this test
    echo "Test Failed: NGINX allowed TLSv1.4 (this is not expected)"
    exit 1
else
    # Non-zero exit code indicates the connection failed, which is what we want
    echo "Test Passed: NGINX correctly blocked TLSv1.4"
fi

echo "Testing NGINX for TLSv1.2 (this should NOT be blocked)..."
docker exec nginx curl -k -v --tls-max 1.2 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is what we want 
    echo "Test Passed: NGINX allowed TLSv1.2 "
else
    # Non-zero exit code indicates the connection failed, unexpected
    echo "Test Failed: NGINX  blocked TLSv1.2"
    exit 1
fi

echo "Testing NGINX for TLSv1.3 (this should NOT be blocked)..."
docker exec nginx curl -k -v --tls-max 1.3 https://localhost >/dev/null 2>&1
if [ $? -eq 0 ]; then
    # If exit code is 0, the connection succeeded, which is what we want
    echo "Test Passed: NGINX allowed TLSv1.3 "
else
    # Non-zero exit code indicates the connection failed, unexpected
    echo "Test Failed: NGINX  blocked TLSv1.3"
    exit 1
fi

echo "All nginx tests passed successfully."

# Test if WordPress home page is up and running
echo "Testing if WordPress homapage is up and running"
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
echo "Testing WordPress login page is accesible"
docker exec nginx curl -k -s https://localhost:${SECURE_PORT}/wp-login.php | grep 'Log In'
if [ $? -ne 0 ]; then
	echo "Test Failed: WordPress login page not accessible"
	exit 1
else
	echo "Login accessible"
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
