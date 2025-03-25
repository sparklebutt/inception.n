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
