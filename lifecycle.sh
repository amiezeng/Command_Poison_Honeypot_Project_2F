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

# STY is set inside a screen session. a screen command then quits this loop
# instead of the mitm session, so every screen command drops STY first.
screen_do() {
    if [ "$(id -u)" -eq 0 ]
    then
        env -u STY screen "$@"
    else
        sudo env -u STY screen "$@"
    fi
}

slack() {
    local text="$1"
    if [ -z "${SLACK_WEBHOOK_URL:-}" ] && [ -f "$HOME/data/slack.env" ]
    then
        # shellcheck disable=SC1091
        . "$HOME/data/slack.env"
    fi
    if [ -z "${SLACK_WEBHOOK_URL:-}" ]
    then
        return 0
    fi
    text=${text//$'\n'/\\n}
    curl -sS -m 10 -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"${text}\"}" \
        "$SLACK_WEBHOOK_URL" >/dev/null || true
}

config_now() {
    local config=unknown
    if [ -f "$live/config" ]
    then
        config=$(tr -cd '0-9' < "$live/config")
    fi
    printf '%s\n' "$config"
}

# 1 is the empty control. 2 through 5 are the ascii drawings.
config_text() {
    case "$(config_now)" in
        1) printf '%s\n' "1 (control, no ascii)" ;;
        2) printf '%s\n' "2 (25% ascii)" ;;
        3) printf '%s\n' "3 (50% ascii)" ;;
        4) printf '%s\n' "4 (75% ascii)" ;;
        5) printf '%s\n' "5 (100% ascii)" ;;
        *) printf '%s\n' "unknown" ;;
    esac
}

# logout ends the attack. activity means a shell is open or the attacker typed.
classify_mitm_line() {
    case "$1" in
        *"[Connection] Attacker closed connection"*|*"Attacker ended the shell"*|*"Honeypot ended shell"*|*"OpenSSH server ended connection"*|*"Client error"*)
            printf '%s\n' logout
            ;;
        *"Container locked"*|*"Opened shell"*|*"Shell opened"*|*"shell opened"*|*"inside container"*|*"Noninteractive mode attacker command"*|*"Attacker Keystroke"*|*"line from reader"*)
            printf '%s\n' activity
            ;;
    esac
    return 0
}

# the attacker address is on the connect and auth lines, not the container address
note_attacker_ip() {
    local found
    found=$(printf '%s\n' "$1" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
    found=${found%%$'\n'*}
    if [ -z "$found" ] || [ "$found" = "0.0.0.0" ] || [ "$found" = "127.0.0.1" ] || [ "$found" = "172.20.0.1" ] || [ "$found" = "$PUBLIC_IP" ]
    then
        return 0
    fi
    case "$found" in
        172.20.*)
            return 0
            ;;
    esac
    ATTACKER_IP=$found
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
    lxc list "$1" -c 4 --format csv 2>/dev/null | awk 'NR == 1 { print $1 }' || true
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
    local label stamp dest d
    if ! session_saved
    then
        return 0
    fi
    case "$reason" in
        logout) label="attacker left" ;;
        idle) label="idle timeout" ;;
        timeout) label="session timeout" ;;
        *) label="$reason" ;;
    esac
    stamp=$(TZ=America/New_York date +%Y%m%dT%H%M%S)
    dest="$DATA/logs/${stamp}-${name}"
    mkdir -p "$dest"
    printf '%s\n' "$label" > "$dest/leave_reason"
    if [ -f "$live/config" ]
    then
        cp "$live/config" "$dest/config"
    fi
    if [ -f "$live/mitm.log" ]
    then
        cp "$live/mitm.log" "$dest/mitm.log"
    fi
    if [ -f "$live/session.stats" ]
    then
        cp "$live/session.stats" "$dest/session.stats"
    fi
    for d in logins login_attempts sessions
    do
        if [ -d "$live/$d" ] && [ -n "$(ls -A "$live/$d" 2>/dev/null)" ]
        then
            mkdir -p "$dest/$d"
            cp -a "$live/$d"/. "$dest/$d/"
        fi
    done
    echo "saved $dest ($label)"
}

clear_session_files() {
    local d
    rm -f "$live/mitm.log" "$live/session.stats"
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
    local _
    : > "$live/mitm.log"
    screen_do -S "${name}-mitm" -X quit 2>/dev/null || true
    # wait for the old node process to release the port before starting a new one
    for _ in $(seq 1 20)
    do
        if ! ss -ltn "sport = :$MITM_PORT" | grep -q LISTEN
        then
            break
        fi
        sleep 0.5
    done
    screen_do -dmS "${name}-mitm" bash -c "cd '$MITM_CONFIG_DIR' && node '$MITM_INDEX' '${name}.js' 2>&1 | tee -a '$live/mitm.log'"
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

# sets SESSION_REASON, SESSION_START, SESSION_CONNECTED_AT, SESSION_COMMANDS, SESSION_KEYSTROKES, SESSION_FIRST_COMMAND, ATTACKER_IP
watch_session() {
    local logfile="$live/mitm.log"
    local seen=0 total now line event
    local in_session=0 start_ts=0 last_ts=0
    SESSION_REASON=
    SESSION_START=0
    SESSION_CONNECTED_AT=
    SESSION_COMMANDS=0
    SESSION_KEYSTROKES=0
    SESSION_FIRST_COMMAND=-1
    ATTACKER_IP=unknown
    : >> "$logfile"
    while true
    do
        total=$(wc -l < "$logfile" | tr -d '[:space:]')
        if [ "$total" -gt "$seen" ]
        then
            while IFS= read -r line
            do
                case "$line" in
                    *"Attacker connected:"*)
                        note_attacker_ip "$line"
                        if [ -z "$SESSION_CONNECTED_AT" ]
                        then
                            SESSION_CONNECTED_AT=$(TZ=America/New_York date '+%Y-%m-%d %I:%M:%S %p %Z')
                            SESSION_START=$(date +%s)
                        fi
                        ;;
                    *"Container locked to "*|*"trying to authenticate"*|*"[Auth] Attacker:"*|*"Auto Access] Attacker:"*)
                        note_attacker_ip "$line"
                        ;;
                    *"line from reader:"*|*"Noninteractive mode attacker command:"*)
                        SESSION_COMMANDS=$((SESSION_COMMANDS + 1))
                        ;;
                    *"Attacker Keystroke:"*)
                        SESSION_KEYSTROKES=$((SESSION_KEYSTROKES + 1))
                        ;;
                esac
                event=$(classify_mitm_line "$line")
                if [ "$event" = "logout" ]
                then
                    if [ "$in_session" -eq 1 ]
                    then
                        SESSION_REASON=logout
                        return 0
                    fi
                    # closed before any lock or shell: nothing is dirty, keep listening
                    SESSION_CONNECTED_AT=
                    SESSION_START=0
                    SESSION_COMMANDS=0
                    SESSION_KEYSTROKES=0
                    SESSION_FIRST_COMMAND=-1
                    ATTACKER_IP=unknown
                fi
                if [ "$event" = "activity" ]
                then
                    now=$(date +%s)
                    if [ "$in_session" -eq 0 ]
                    then
                        in_session=1
                        start_ts=$now
                        if [ -z "$SESSION_CONNECTED_AT" ]
                        then
                            SESSION_CONNECTED_AT=$(TZ=America/New_York date '+%Y-%m-%d %I:%M:%S %p %Z')
                            SESSION_START=$now
                        fi
                        echo "session started" >&2
                    fi
                    if [ "$SESSION_COMMANDS" -gt 0 ] && [ "$SESSION_FIRST_COMMAND" -lt 0 ]
                    then
                        SESSION_FIRST_COMMAND=$((now - start_ts))
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
                SESSION_REASON=timeout
                return 0
            fi
            if [ $((now - last_ts)) -ge "$IDLE_LIMIT" ]
            then
                SESSION_REASON=idle
                return 0
            fi
        fi
        sleep 2
    done
}

# one record per attack, copied into the saved session folder
write_session_stats() {
    local length="$1"
    local why="$2"
    local first=none
    if [ "$SESSION_FIRST_COMMAND" -ge 0 ]
    then
        first="${SESSION_FIRST_COMMAND}s"
    fi
    cat > "$live/session.stats" << EOF
honeypot=$name
public_ip=$PUBLIC_IP
config=$(config_now)
ascii=$(config_text)
reason=$why
attacker_ip=$ATTACKER_IP
session_seconds=$length
commands=$SESSION_COMMANDS
keystrokes=$SESSION_KEYSTROKES
seconds_to_first_command=$first
EOF
}

kick_attacker() {
    lxc exec "$name" -- pkill sshd || true
}

run_one() {
    local name="$1"
    local live reason ip left_at
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
        watch_session
        reason=$SESSION_REASON
        left_at=$(TZ=America/New_York date '+%Y-%m-%d %I:%M:%S %p %Z')
        echo "session ended: $reason"
        length=0
        if [ "$SESSION_START" -gt 0 ]
        then
            length=$(( $(date +%s) - SESSION_START ))
        fi
        case "$reason" in
            logout) why="attacker left" ;;
            idle) why="idle timeout" ;;
            timeout) why="session timeout" ;;
            *) why=$reason ;;
        esac
        first=none
        if [ "$SESSION_FIRST_COMMAND" -ge 0 ]
        then
            first="${SESSION_FIRST_COMMAND}s"
        fi
        left=$(TZ=America/New_York date '+%Y-%m-%d %I:%M:%S %p %Z')
        case "$reason" in
            logout|idle|timeout)
                write_session_stats "$length" "$why"
                slack "------------------------------
$name $PUBLIC_IP: attacker session
------------------------------
configuration: $(config_text)
from: $ATTACKER_IP
connected: $SESSION_CONNECTED_AT
left: $left_at
reason: $why
duration: ${length}s
commands: $SESSION_COMMANDS
keystrokes: $SESSION_KEYSTROKES
first command: $first
------------------------------"
                ;;
        esac
        case "$reason" in
            idle|timeout)
                kick_attacker
                sleep 1
                ;;
            logout)
                ;;
            *)
                echo "watcher stopped, recycling"
                reason=error
                ;;
        esac
        screen_do -S "${name}-mitm" -X quit 2>/dev/null || true
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
        env -u STY screen -S "$name" -X quit 2>/dev/null || true
        screen_do -S "$name" -X quit 2>/dev/null || true
        screen_do -S "${name}-mitm" -X quit 2>/dev/null || true
    done < ./honeypots.csv
    while IFS=, read -r name _ _
    do
        [ -z "$name" ] && continue
        [ "$name" = "name" ] && continue
        screen_do -dmS "$name" bash -c "cd '$root' && exec ./run-one.sh '$name'"
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
    # a failed command must not end the screen. start the honeypot again.
    while true
    do
        (
            run_one "$1"
        ) || echo "lifecycle $1 stopped, starting again"
        sleep 5
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]
then
    main "$@"
fi
