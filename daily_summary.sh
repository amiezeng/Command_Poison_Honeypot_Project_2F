#!/bin/bash
# slack summary of the last 24 hours. cron runs this at 7:15pm eastern.

set -euo pipefail
export HOME=/home/aces
export TZ=America/New_York
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" -ne 0 ]
then
    exec sudo -E "$0" "$@"
fi

cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./slack_lib.sh

report=$(python3 ./daily_summary.py)
printf '%s\n' "$report"
slack_send "$report"
