#!/bin/bash
cd /home/aces/Command_Poison_Honeypot_Project_2F
for _ in $(seq 1 60)
do
    lxc list >/dev/null 2>&1 && break
    sleep 2
done
exec ./lifecycle.sh --all
