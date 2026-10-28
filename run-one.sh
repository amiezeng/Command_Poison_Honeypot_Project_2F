#!/bin/bash
export TZ=America/New_York
name="$1"
cd "$(dirname "$0")"
mkdir -p /home/aces/data/logs
log="/home/aces/data/logs/${name}.lifecycle.log"
stdbuf -oL -eL ./lifecycle.sh "$name" 2>&1 \
    | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush() }' \
    | tee -a "$log"
