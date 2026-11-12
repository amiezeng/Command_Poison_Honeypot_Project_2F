#!/bin/bash
# post one message. webhook is $HOME/data/slack.env

slack_send() {
    local text="$1"
    if [ -z "${SLACK_WEBHOOK_URL:-}" ] && [ -f "${HOME}/data/slack.env" ]
    then
        # shellcheck disable=SC1091
        . "${HOME}/data/slack.env"
    fi
    if [ -z "${SLACK_WEBHOOK_URL:-}" ]
    then
        echo "no slack webhook" >&2
        return 0
    fi
    local payload
    payload=$(printf '%s' "$text" | python3 -c 'import json,sys; print(json.dumps({"text": sys.stdin.read()}))')
    curl -sS -m 15 -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" >/dev/null || echo "slack post failed" >&2
}
