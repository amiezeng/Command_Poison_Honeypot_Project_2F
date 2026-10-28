#!/bin/bash
# watch one honeypot from the host.
# writes ssh events to ~/data/live/<container>/monitor.log
# slack is sent by lifecycle.sh when an attacker enters or leaves.
# usage: monitor.sh <container>

set -euo pipefail

if [ "$#" -ne 1 ]
then
    echo "usage: $0 <container>"
    exit 1
fi

CONTAINER="$1"
live_dir="$HOME/data/live/$CONTAINER"
mkdir -p "$live_dir"

config=unknown
if [ -f "$live_dir/config" ]
then
    config=$(tr -cd '0-9' < "$live_dir/config")
fi

clean() {
    printf '%s' "$1" | tr -cd 'A-Za-z0-9.:_-'
}

log_event() {
    local event="$1"
    local extra="$2"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s container=%s config=%s event=%s %s\n' \
        "$now" "$CONTAINER" "$config" "$event" "$extra" >> "$live_dir/monitor.log"
}

# event, user, ip, and port are set for the caller
classify_line() {
    local line="$1"
    event=""
    user=""
    ip=""
    port=""

    case "$line" in
        *"Accepted password for "*|*"Accepted publickey for "*)
            event=login_success
            user=$(printf '%s\n' "$line" | sed -n 's/.*Accepted [^ ]* for \([^ ]*\) from.*/\1/p')
            ;;
        *"Failed password for invalid user "*)
            event=login_failure
            user=$(printf '%s\n' "$line" | sed -n 's/.*invalid user \([^ ]*\) from.*/\1/p')
            ;;
        *"Failed password for "*)
            event=login_failure
            user=$(printf '%s\n' "$line" | sed -n 's/.*Failed password for \([^ ]*\) from.*/\1/p')
            ;;
        *"Disconnected from user "*)
            event=disconnect
            user=$(printf '%s\n' "$line" | sed -n 's/.*Disconnected from user \([^ ]*\) .*/\1/p')
            ip=$(printf '%s\n' "$line" | sed -n 's/.*Disconnected from user [^ ]* \([0-9a-fA-F.:]*\) port.*/\1/p')
            port=$(printf '%s\n' "$line" | sed -n 's/.* port \([0-9]*\).*/\1/p')
            ;;
        *"Disconnected from "*)
            event=disconnect
            ip=$(printf '%s\n' "$line" | sed -n 's/.*Disconnected from \([0-9a-fA-F.:]*\) port.*/\1/p')
            port=$(printf '%s\n' "$line" | sed -n 's/.* port \([0-9]*\).*/\1/p')
            ;;
        *)
            return 1
            ;;
    esac

    if [ -z "$ip" ]
    then
        ip=$(printf '%s\n' "$line" | sed -n 's/.* from \([0-9a-fA-F.:]*\) port.*/\1/p')
        port=$(printf '%s\n' "$line" | sed -n 's/.* port \([0-9]*\).*/\1/p')
    fi
    user=$(clean "$user")
    ip=$(clean "$ip")
    port=$(clean "$port")
}

record_ssh() {
    local extra
    extra="user=$user ip=$ip port=$port"
    log_event "$event" "$extra"
}

# record health changes in the local log
set_health() {
    local now="$1"
    local prev=""
    if [ -f "$live_dir/health" ]
    then
        prev=$(head -n 1 "$live_dir/health")
    fi
    printf '%s\n' "$now" > "$live_dir/health"
    if [ "$now" = "$prev" ]
    then
        return 0
    fi
    case "$now" in
        up)
            if [ -n "$prev" ]
            then
                log_event health_up ""
            fi
            ;;
        down)
            log_event container_down ""
            ;;
        ssh_down)
            log_event ssh_down ""
            ;;
        journal_down)
            log_event journal_down ""
            ;;
    esac
}

container_status() {
    local info
    info=$(lxc info "$CONTAINER")
    printf '%s\n' "$info" | sed -n 's/^Status: //p' | head -n 1 | tr '[:upper:]' '[:lower:]'
}

ssh_listening() {
    lxc exec "$CONTAINER" -- bash -c 'echo >/dev/tcp/127.0.0.1/22' >/dev/null 2>&1
}

# read new ssh journal lines. a restore wipes the container journal, so an old cursor is dropped.
collect_ssh() {
    local cursor="" output="" line="" new_cursor="" baseline=0
    if [ -f "$live_dir/ssh.cursor" ]
    then
        cursor=$(head -n 1 "$live_dir/ssh.cursor")
    else
        baseline=1
    fi

    if [ "$baseline" -eq 1 ]
    then
        if ! output=$(lxc exec "$CONTAINER" -- journalctl -u ssh -n 1 --show-cursor --no-pager -o short-iso 2>&1)
        then
            set_health journal_down
            return 0
        fi
    elif ! output=$(lxc exec "$CONTAINER" -- journalctl -u ssh --after-cursor="$cursor" --show-cursor --no-pager -o short-iso 2>&1)
    then
        if printf '%s\n' "$output" | grep -q -i cursor
        then
            rm -f "$live_dir/ssh.cursor"
            baseline=0
            if ! output=$(lxc exec "$CONTAINER" -- journalctl -u ssh --no-pager -o short-iso --show-cursor 2>&1)
            then
                set_health journal_down
                return 0
            fi
        else
            set_health journal_down
            return 0
        fi
    fi

    while IFS= read -r line
    do
        line=${line%$'\r'}
        case "$line" in
            "-- cursor: "*)
                new_cursor=${line#"-- cursor: "}
                ;;
            "")
                ;;
            *)
                if [ "$baseline" -eq 0 ] && classify_line "$line"
                then
                    record_ssh
                fi
                ;;
        esac
    done <<< "$output"

    if [ -n "$new_cursor" ]
    then
        printf '%s\n' "$new_cursor" > "$live_dir/ssh.cursor"
    fi
}

status=$(container_status)
if [ "$status" != "running" ]
then
    set_health down
    exit 0
fi

if ! ssh_listening
then
    set_health ssh_down
    exit 0
fi

set_health up
collect_ssh
