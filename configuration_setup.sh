#!/bin/bash
# runs inside the container after every snapshot restore.
# only differences between configurations belong here.

set -euo pipefail

if [ "$#" -ne 1 ]
then
    echo "usage: configuration_setup.sh <config>"
    exit 1
fi

CONFIG="$1"

case "$CONFIG" in
    1|2|3|4|5)
        ;;
    *)
        echo "invalid configuration: $CONFIG"
        exit 1
        ;;
esac

# config-specific changes go here.
echo "applied configuration $CONFIG"
