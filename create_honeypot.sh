#!/bin/bash

if [ "$#" -ne 2 ]
then
    echo "usage: $0 <name> <config>"
    exit 1
fi

CONTAINER="$1"
CONFIG="$2"

echo "Creating honeypot '$CONTAINER'"
echo "Configuration: $CONFIG"

# Create container
lxc launch ubuntu:24.04 "$CONTAINER"

sleep 5

# Update packages
lxc exec "$CONTAINER" -- apt update -y

# Install SSH
lxc exec "$CONTAINER" -- apt install -y openssh-server

sleep 3

# Basic SSH honeypot configuration
lxc exec "$CONTAINER" -- bash -c \
    "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

lxc exec "$CONTAINER" -- bash -c \
    "echo 'PubkeyAuthentication no' >> /etc/ssh/sshd_config"

lxc exec "$CONTAINER" -- bash -c \
    "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"

# Restart SSH
lxc exec "$CONTAINER" -- systemctl restart ssh

# Display container information
echo
echo "Honeypot '$CONTAINER' is running."
echo "Configuration: $CONFIG"

lxc list "$CONTAINER"