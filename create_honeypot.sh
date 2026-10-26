#!/bin/bash
# one-time setup: launch a container, install the shared packages, save a snapshot.
# recycling restores that snapshot instead of building ubuntu again.

set -euo pipefail

cd "$(dirname "$0")"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]
then
    echo "usage: $0 <name> [profile]"
    exit 1
fi

CONTAINER="$1"
PROFILE="${2:-default}"
SNAPSHOT="clean"

echo "creating honeypot $CONTAINER"

lxc launch ubuntu:24.04 "$CONTAINER" -p "$PROFILE"

# apt cannot run until first-boot setup releases its lock
lxc exec "$CONTAINER" -- cloud-init status --wait

cat ./common_setup.sh | lxc exec "$CONTAINER" -- bash -s

# a stopped snapshot restores to a clean stopped container
lxc stop "$CONTAINER"
lxc snapshot "$CONTAINER" "$SNAPSHOT"

echo "snapshot $SNAPSHOT saved for $CONTAINER"
echo "start a cycle with ./recycling_script.sh $CONTAINER <process>"
