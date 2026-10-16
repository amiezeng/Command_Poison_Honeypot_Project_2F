#!/bin/bash
# restore the clean snapshot, then apply one random configuration.
# the container must already exist. run create_honeypot.sh once before this.

set -euo pipefail

cd "$(dirname "$0")"

if [ "$#" -ne 2 ]
then
    echo "usage: $0 <container name> <process>"
    exit 1
fi

CONTAINER="$1"
PROCESS="$2"
SNAPSHOT="clean"

# 1 control, 2 is 25% ascii, 3 is 50%, 4 is 75%, 5 is 100%
CONFIG=$(( RANDOM % 5 + 1 ))

echo "recycling $CONTAINER"
echo "selected configuration: $CONFIG"

started=$(date +%s)

sudo screen -S "$PROCESS" -X quit 2>/dev/null || true

# lxc info prints "Running", not "RUNNING".
# restore fails if that check does not match.
status=$(lxc info "$CONTAINER" | sed -n 's/^Status: //p' | head -n 1 | tr '[:upper:]' '[:lower:]')
if [ "$status" = "running" ]
then
    lxc stop "$CONTAINER" --force
fi

# wait until stop has finished
stopped=0
for _ in $(seq 1 30)
do
    status=$(lxc info "$CONTAINER" | sed -n 's/^Status: //p' | head -n 1 | tr '[:upper:]' '[:lower:]')
    if [ "$status" = "stopped" ]
    then
        stopped=1
        break
    fi
    sleep 0.5
done

if [ "$stopped" -ne 1 ]
then
    echo "container $CONTAINER did not stop"
    exit 1
fi

lxc restore "$CONTAINER" "$SNAPSHOT"
lxc start "$CONTAINER"

# start returns before the container accepts commands
ready=0
for _ in $(seq 1 30)
do
    if lxc exec "$CONTAINER" -- true >/dev/null 2>&1
    then
        ready=1
        break
    fi
    sleep 0.5
done

if [ "$ready" -ne 1 ]
then
    echo "container $CONTAINER did not become ready"
    exit 1
fi

# config 1 is empty. 2 through 5 are the four drawings.
banner=$(mktemp)
case "$CONFIG" in
    1)
        : > "$banner"
        ;;
    2)
        cp ./ascii/25.txt "$banner"
        ;;
    3)
        cp ./ascii/50.txt "$banner"
        ;;
    4)
        cp ./ascii/75.txt "$banner"
        ;;
    5)
        cp ./ascii/100.txt "$banner"
        ;;
esac
lxc file push --mode 0644 "$banner" "$CONTAINER/etc/banner-art"
rm -f "$banner"

cat ./configuration_setup.sh | lxc exec "$CONTAINER" -- bash -s "$CONFIG"

# configuration setup must finish with ssh listening
ssh_up=0
for _ in $(seq 1 30)
do
    if lxc exec "$CONTAINER" -- bash -c 'echo >/dev/tcp/127.0.0.1/22' >/dev/null 2>&1
    then
        ssh_up=1
        break
    fi
    sleep 0.5
done

if [ "$ssh_up" -ne 1 ]
then
    echo "ssh did not start listening in $CONTAINER"
    exit 1
fi

echo "honeypot $CONTAINER is running"
echo "configuration: $CONFIG"
echo "recycle took $(( $(date +%s) - started )) seconds"
