#!/bin/bash
# runs once inside a new container, before the clean snapshot is taken.
# everything here is shared by all 5 configurations.

set -euo pipefail

apt update -y
apt install -y openssh-server

# same ssh settings on every honeypot
printf '%s\n' \
    'PasswordAuthentication yes' \
    'PubkeyAuthentication no' \
    'PermitRootLogin yes' \
    >> /etc/ssh/sshd_config

systemctl enable ssh
systemctl restart ssh
