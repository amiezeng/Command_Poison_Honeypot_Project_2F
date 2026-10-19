#!/bin/bash
# runs once inside a new container, before the clean snapshot is taken.
# everything here is shared by all 5 configurations.

set -euo pipefail

apt update -y
apt install -y openssh-server

# the image sets password auth to no in this file, and ssh reads it first
printf '%s\n' 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# same ssh settings on every honeypot.
# bash reads banner.bashrc for non-interactive ssh, which is how bots run commands.
printf '%s\n' \
    'PasswordAuthentication yes' \
    'PubkeyAuthentication no' \
    'PermitRootLogin yes' \
    'SetEnv BASH_ENV=/etc/banner.bashrc' \
    >> /etc/ssh/sshd_config

# print /etc/banner-art after a non-interactive command
cat > /etc/banner.bashrc << 'EOF'
trap '__ec=$?; [ -s /etc/banner-art ] && cat /etc/banner-art; exit $__ec' EXIT
EOF

# print /etc/banner-art after each interactive command
cat > /etc/profile.d/banner.sh << 'EOF'
if [ -z "${BASH_VERSION:-}" ]
then
    return 0
fi

# startup commands run before the first prompt. ignore those.
__art_ready=0

__art_debug() {
    if [ "$__art_ready" != 1 ]
    then
        return
    fi
    case "$BASH_COMMAND" in
        __art_after)
            ;;
        *)
            __art_ran=1
            ;;
    esac
}
trap '__art_debug' DEBUG

__art_after() {
    trap - DEBUG
    if [ "$__art_ready" = 1 ] && [ "${__art_ran:-0}" = 1 ] && [ -s /etc/banner-art ]
    then
        cat /etc/banner-art
    fi
    __art_ran=0
    __art_ready=1
    trap '__art_debug' DEBUG
}
PROMPT_COMMAND=__art_after
EOF

: > /etc/banner-art

systemctl enable ssh
systemctl restart ssh
