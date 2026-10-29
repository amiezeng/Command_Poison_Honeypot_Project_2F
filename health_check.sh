#!/bin/bash
# slack only when a honeypot or the lifecycle service changes state.
# a problem must show up on two checks in a row, so a recycle does not alert.

set -euo pipefail
export HOME=/home/aces
export TZ=America/New_York
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

if [ "$(id -u)" -ne 0 ]
then
    exec sudo -E "$0" "$@"
fi

cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./slack_lib.sh

state="$HOME/data/health"
mkdir -p "$state"
changes=()

consider() {
    local key="$1"
    local status="$2"
    local label="$3"
    local reported="" pending=""
    if [ -f "$state/$key.reported" ]
    then
        reported=$(cat "$state/$key.reported")
    fi
    if [ -f "$state/$key.pending" ]
    then
        pending=$(cat "$state/$key.pending")
    fi
    printf '%s\n' "$status" > "$state/$key.pending"
    if [ -z "$reported" ]
    then
        if [ "$status" = "up" ]
        then
            printf '%s\n' up > "$state/$key.reported"
        else
            printf '%s\n' unseen > "$state/$key.reported"
        fi
        return 0
    fi
    if [ "$status" = "$reported" ]
    then
        return 0
    fi
    if [ "$status" != "$pending" ]
    then
        return 0
    fi
    printf '%s\n' "$status" > "$state/$key.reported"
    if [ "$status" = "up" ]
    then
        changes+=("$label is back up")
    else
        changes+=("$label: $status")
    fi
}

service_status=up
if ! systemctl is-active --quiet honeypot-lifecycle.service
then
    service_status="lifecycle service is not running"
fi
consider service "$service_status" "honeypot-lifecycle"

while IFS=, read -r name public_ip port
do
    [ -z "$name" ] && continue
    [ "$name" = "name" ] && continue
    problems=()

    if ! command -v lxc >/dev/null 2>&1
    then
        problems+=("lxc command not found")
    else
        info=$(lxc info "$name" 2>/dev/null || true)
        running=$(printf '%s\n' "$info" | sed -n 's/^Status: //p' | head -n 1 | tr '[:upper:]' '[:lower:]')
        if [ "$running" != "running" ]
        then
            problems+=("container is ${running:-missing}")
        fi
    fi

    if ! ss -H -ltn | awk -v p=":${port}$" '$4 ~ p { found = 1 } END { exit !found }'
    then
        problems+=("mitm port ${port} is not listening")
    fi

    if ! screen -ls 2>/dev/null | grep -E "[0-9]+\\.${name}[[:space:]]" >/dev/null
    then
        problems+=("lifecycle screen is not running")
    fi

    log=""
    for candidate in \
        "$HOME/data/logs/${name}.lifecycle.log" \
        "$HOME/data/${name}.lifecycle.log" \
        "$HOME/data/${name}.lifecycle.csv" \
        "$HOME/data/logs/${name}.lifecycle.csv"
    do
        if [ -f "$candidate" ]
        then
            log=$candidate
            break
        fi
    done
    if [ -z "$log" ]
    then
        problems+=("lifecycle log is missing")
    else
        last=$(grep -E 'waiting for attacker|session started|session ended|recycle failed|did not start|no ip for' "$log" | tail -n 1 || true)
        case "$last" in
            *"recycle failed"*|*"did not start"*|*"no ip for"*)
                problems+=("recycle is failing")
                ;;
        esac
    fi

    if [ "${#problems[@]}" -eq 0 ]
    then
        status=up
    else
        status=$(printf '%s; ' "${problems[@]}")
        status=${status%; }
    fi
    consider "$name" "$status" "$name ($public_ip)"
done < ./honeypots.csv

if [ "${#changes[@]}" -gt 0 ]
then
    message=$(printf '%s\n' "${changes[@]}")
    printf '%s\n' "$message"
    slack_send "$message"
fi
