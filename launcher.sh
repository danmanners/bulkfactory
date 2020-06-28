#!/bin/bash

if [ $# -eq 0 ]; then
    echo 'Usage: "./launcher.sh ethernetInterface" or "./launcher.sh cleanup"'
    exit
fi

if [[ $1 == "cleanup" ]]; then
    echo "Cleaning up the environment."

    # As long as there are existing containers, remove them.
    if [ $(docker ps -aq | wc -l) -ne 0 ]; then
        docker stop `docker ps -aq`
        docker rm `docker ps -aq`
    else
        echo "No containers to remove. Continuing to cleaning networks."
    fi

    # Prune existing unused networks
    docker network prune -f
    exit
fi

# Build the Docker Container
docker build -t localreverse reverseProxy

# Set the ethernet interface name
ethernetInterfaceName=$1

# Function to create the reverse proxy containers & networking
createFactory() {
    VLAN=$1
    VLNAME=$(printf "%02d" $1)
    VLRANGE=$(expr $VLAN \* 4)

    # Create the Network Interface
    docker network create \
        -d macvlan \
        --subnet=192.168.1.0/24 \
        --ip-range=192.168.1.$VLRANGE/30 \
        -o parent=$ethernetInterfaceName.$VLAN \
        macvlan$VLNAME

    # Create and Run the Container
    docker run -dp 100$VLNAME:443 \
        --name reverse$VLNAME \
        --restart unless-stopped \
        --network hostbridge \
        --ip 10.0.0.2$VLNAME \
        --add-host factory:192.168.1.20 \
        localreverse

    # Associate the previously created network
    docker network connect \
        macvlan$VLNAME reverse$VLNAME
}

# Create the host network bridge
docker network create -d macvlan \
    --subnet=10.0.0.0/24 \
    --ip-range=10.0.0.128/25 \
    -o parent=$ethernetInterfaceName \
    hostbridge

# Create the Reverse Containers from 3 to 8;
# This maps out for the available ports on a 8-Port Switch.
for i in $(seq 3 8); do
    echo "Creating Docker Container for VLAN $i."
    createFactory $i
    done
