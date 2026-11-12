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

# one config file per container, with that container's listening port in it.
MITM_INDEX="${MITM_INDEX:-/root/honeypots/MITM/mitm/index.js}"
MITM_CONFIG_DIR="${MITM_CONFIG_DIR:-/root/honeypots/MITM/config}"
MITM_CONFIG="${MITM_CONFIG:-$MITM_CONFIG_DIR/$CONTAINER.js}"
MITM_LOG="$HOME/data/live/$CONTAINER/mitm.log"
 
# fail before touching the container if the MITM cannot be started
if ! sudo test -f "$MITM_INDEX"
then
    echo "MITM program not found: $MITM_INDEX"
    exit 1
fi
 
if ! sudo test -f "$MITM_CONFIG"
then
    echo "MITM config not found: $MITM_CONFIG"
    echo "set MITM_CONFIG=/path/to/config or edit MITM_CONFIG_DIR in this script"
    exit 1
fi
 
# 1 control, 2 is 25% ascii, 3 is 50%, 4 is 75%, 5 is 100%
CONFIG=$(( RANDOM % 5 + 1 ))
 
echo "recycling $CONTAINER"
echo "selected configuration: $CONFIG"
 
started=$(date +%s)
 
# stop the old MITM first. this also clears its one-attacker lock.
sudo screen -S "$PROCESS" -X quit 2>/dev/null || true
 
# wait until the old screen session is gone
for _ in $(seq 1 20)
do
    if ! sudo screen -ls 2>/dev/null | grep -q "[0-9]\.${PROCESS}[[:space:]]"
    then
        break
    fi
    sleep 0.5
done
 
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

lxc exec "$CONTAINER" -- /bin/bash --noprofile --norc -s "$CONFIG" < ./configuration_setup.sh || echo "configuration setup skipped"
 
# configuration setup must finish with ssh listening
ssh_up=0
for _ in $(seq 1 30)
do
    if lxc exec "$CONTAINER" -- python3 -c 'import socket; socket.create_connection(("127.0.0.1", 22), 2).close()' >/dev/null 2>&1
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
 
# monitor.sh reads this so each ssh event is labeled with the configuration
mkdir -p "$HOME/data/live/$CONTAINER"
printf '%s\n' "$CONFIG" > "$HOME/data/live/$CONTAINER/config"
 
# start a fresh MITM for this container in its own screen session.
# this is last, so no attacker can arrive before the container is ready.
# sudo, because the kill at the top uses sudo and screen sessions belong to one user.
# the config path and log path are passed as arguments so quoting cannot break.
sudo screen -dmS "$PROCESS" bash -c \
    'node "$1" "$2" 2>&1 | tee -a "$3"' _ "$MITM_INDEX" "$(basename "$MITM_CONFIG")" "$MITM_LOG"
 
# confirm the screen session came up
mitm_up=0
for _ in $(seq 1 10)
do
    if sudo screen -ls 2>/dev/null | grep -q "[0-9]\.${PROCESS}[[:space:]]"
    then
        mitm_up=1
        break
    fi
    sleep 0.5
done
 
if [ "$mitm_up" -ne 1 ]
then
    echo "MITM screen session $PROCESS did not start"
    echo "last lines of $MITM_LOG:"
    tail -n 10 "$MITM_LOG" 2>/dev/null || true
    exit 1
fi
 
echo "honeypot $CONTAINER is running"
echo "configuration: $CONFIG"
echo "mitm: screen session $PROCESS, config $MITM_CONFIG"
echo "recycle took $(( $(date +%s) - started )) seconds"
