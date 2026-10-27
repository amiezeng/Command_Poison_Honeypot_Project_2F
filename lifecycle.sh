#!/bin/bash
# one loop per honeypot. screen name is the container (hp1).
# the mitm screen is hp1-mitm, so recycle does not kill this loop.
# start all four with: ./lifecycle.sh --all

set -euo pipefail

cd "$(dirname "$0")"

# monitor.sh and this loop share /home/aces/data, even when the screen is root
export HOME=/home/aces

DATA="$HOME/data"
MITM_CONFIG_DIR=/root/honeypots/MITM/config
MITM_INDEX=/root/honeypots/MITM/mitm/index.js
NAT=/root/honeypots/network/nat_mitm
IDLE_LIMIT="${IDLE_SECONDS:-60}"
MAX_SESSION="${MAX_SECONDS:-300}"

as_root() {
    if [ "$(id -u)" -eq 0 ]
    then
        "$@"
    else
        sudo "$@"
    fi
}

# logout ends the attack. activity means a shell is open or the attacker typed.
classify_mitm_line() {
    case "$1" in
        *"[Connection] Attacker closed connection"*|*"Attacker ended the shell"*|*"Honeypot ended shell"*|*"OpenSSH server ended connection"*|*"Client error"*)
            printf '%s\n' logout
            ;;
        *"Container locked"*|*"Shell opened"*|*"shell opened"*|*compromised*|*"Attacker Keystroke"*|*"line from reader"*)
            printf '%s\n' activity
            ;;
    esac
    return 0
}

lookup() {
    local name="$1"
    local line
    line=$(awk -F, -v n="$name" 'NR > 1 && $1 == n { print; exit }' ./honeypots.csv)
    if [ -z "$line" ]
    then
        echo "unknown honeypot: $name" >&2
        exit 1
    fi
    PUBLIC_IP=$(printf '%s\n' "$line" | cut -d, -f2)
    MITM_PORT=$(printf '%s\n' "$line" | cut -d, -f3)
}

container_ip() {
    lxc list "$1" -c 4 --format csv | awk 'NR == 1 { print $1 }'
}

session_saved() {
    [ -s "$live/mitm.log" ] && return 0
    local d
    for d in logins login_attempts sessions
    do
        if [ -d "$live/$d" ] && [ -n "$(ls -A "$live/$d" 2>/dev/null)" ]
        then
            return 0
        fi
    done
    return 1
}

archive_session() {
    local reason="$1"
    local stamp dest d
    if ! session_saved
    then
        return 0
    fi
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    dest="$DATA/logs/${stamp}-${name}"
    mkdir -p "$dest"
    printf '%s\n' "$reason" > "$dest/leave_reason"
    if [ -f "$live/config" ]
    then
        cp "$live/config" "$dest/config"
    fi
    if [ -f "$live/mitm.log" ]
    then
        cp "$live/mitm.log" "$dest/mitm.log"
    fi
    for d in logins login_attempts sessions
    do
        if [ -d "$live/$d" ] && [ -n "$(ls -A "$live/$d" 2>/dev/null)" ]
        then
            mkdir -p "$dest/$d"
            cp -a "$live/$d"/. "$dest/$d/"
        fi
    done
    echo "saved $dest ($reason)"
}

clear_session_files() {
    local d
    rm -f "$live/mitm.log"
    for d in logins login_attempts sessions
    do
        rm -rf "$live/$d"
        mkdir -p "$live/$d"
    done
}

sync_mitm_target() {
    local ip="$1"
    local cfg="$MITM_CONFIG_DIR/${name}.js"
    local current
    if [ ! -f "$cfg" ]
    then
        echo "missing $cfg" >&2
        return 1
    fi
    mkdir -p "$live/logins" "$live/login_attempts" "$live/sessions"
    current=$(as_root grep -oE "ipAddress[[:space:]]*:[[:space:]]*['\"][0-9.]+" "$cfg" | grep -oE '[0-9.]+$' || true)
    replace_js_string streamOutput "$live/sessions" "$cfg"
    replace_js_string loginAttempts "$live/login_attempts" "$cfg"
    replace_js_string logins "$live/logins" "$cfg"
    if [ "$current" != "$ip" ]
    then
        replace_js_string ipAddress "$ip" "$cfg"
        echo "container ip changed to $ip, updating nat"
        as_root "$NAT" "$PUBLIC_IP" "$ip" "$MITM_PORT"
    fi
}

# replace the quoted value of one js key and leave the rest of the line alone
replace_js_string() {
    local key="$1"
    local value="$2"
    local cfg="$3"
    local sq="'"
    local quoted="[${sq}\"][^${sq}\"]*[${sq}\"]"
    as_root sed -i -E "s|(${key}[[:space:]]*:[[:space:]]*)${quoted}|\\1${sq}${value}${sq}|" "$cfg"
}

start_mitm() {
    : > "$live/mitm.log"
    as_root screen -S "${name}-mitm" -X quit 2>/dev/null || true
    as_root screen -dmS "${name}-mitm" bash -c "cd '$MITM_CONFIG_DIR' && node '$MITM_INDEX' '${name}.js' 2>&1 | tee -a '$live/mitm.log'"
}

mitm_listening() {
    local _
    for _ in $(seq 1 30)
    do
        if [ -f "$live/mitm.log" ] && grep -q "listening on" "$live/mitm.log"
        then
            return 0
        fi
        sleep 1
    done
    return 1
}

# returns logout, idle, or timeout on stdout
watch_session() {
    local logfile="$live/mitm.log"
    local seen=0 total now line event
    local in_session=0 start_ts=0 last_ts=0
    : >> "$logfile"
    while true
    do
        total=$(wc -l < "$logfile" | tr -d '[:space:]')
        if [ "$total" -gt "$seen" ]
        then
            while IFS= read -r line
            do
                event=$(classify_mitm_line "$line")
                if [ "$event" = "logout" ]
                then
                    printf '%s\n' logout
                    return 0
                fi
                if [ "$event" = "activity" ]
                then
                    now=$(date +%s)
                    if [ "$in_session" -eq 0 ]
                    then
                        in_session=1
                        start_ts=$now
                        echo "session started" >&2
                    fi
                    last_ts=$now
                fi
            done < <(awk -v start=$((seen + 1)) -v end="$total" 'NR >= start && NR <= end' "$logfile")
            seen=$total
        fi
        if [ "$in_session" -eq 1 ]
        then
            now=$(date +%s)
            if [ $((now - start_ts)) -ge "$MAX_SESSION" ]
            then
                printf '%s\n' timeout
                return 0
            fi
            if [ $((now - last_ts)) -ge "$IDLE_LIMIT" ]
            then
                printf '%s\n' idle
                return 0
            fi
        fi
        sleep 2
    done
}

kick_attacker() {
    lxc exec "$name" -- pkill sshd || true
}

run_one() {
    local name="$1"
    local live reason ip
    lookup "$name"
    live="$DATA/live/$name"
    mkdir -p "$live"
    if [ "$(id -u)" -eq 0 ]
    then
        chown aces:aces "$live" || true
    fi
    echo "lifecycle $name"
    # save the finished session before the next restore wipes the container
    reason=previous
    while true
    do
        if [ -n "$reason" ]
        then
            archive_session "$reason"
        fi
        clear_session_files
        if ! ./recycling_script.sh "$name" "${name}-mitm"
        then
            echo "recycle failed for $name, retrying"
            reason=
            sleep 5
            continue
        fi
        ip=$(container_ip "$name")
        if [ -z "$ip" ]
        then
            echo "no ip for $name, retrying"
            reason=
            sleep 5
            continue
        fi
        if ! sync_mitm_target "$ip"
        then
            reason=
            sleep 5
            continue
        fi
        start_mitm
        if ! mitm_listening
        then
            echo "mitm for $name did not start, retrying"
            if [ -f "$live/mitm.log" ]
            then
                tail -n 20 "$live/mitm.log" >&2
            fi
            reason=
            sleep 5
            continue
        fi
        echo "waiting for attacker on $name"
        reason=$(watch_session)
        echo "session ended: $reason"
        case "$reason" in
            logout)
                ;;
            idle|timeout)
                kick_attacker
                sleep 1
                ;;
            *)
                echo "watcher stopped, recycling"
                reason=error
                ;;
        esac
        as_root screen -S "${name}-mitm" -X quit 2>/dev/null || true
        sleep 1
    done
}

start_all() {
    local root name
    root=$(pwd)
    while IFS=, read -r name _ _
    do
        [ -z "$name" ] && continue
        [ "$name" = "name" ] && continue
        screen -S "$name" -X quit 2>/dev/null || true
        as_root screen -S "$name" -X quit 2>/dev/null || true
        as_root screen -S "${name}-mitm" -X quit 2>/dev/null || true
    done < ./honeypots.csv
    while IFS=, read -r name _ _
    do
        [ -z "$name" ] && continue
        [ "$name" = "name" ] && continue
        as_root screen -dmS "$name" bash -c "cd '$root' && exec ./lifecycle.sh '$name'"
        echo "started $name"
    done < ./honeypots.csv
}

main() {
    if [ "${1:-}" = "--all" ]
    then
        start_all
        exit 0
    fi
    if [ "$#" -ne 1 ]
    then
        echo "usage: $0 <container name> | $0 --all" >&2
        exit 1
    fi
    run_one "$1"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]
then
    main "$@"
fi
