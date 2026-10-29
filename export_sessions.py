#!/usr/bin/env python3
# one row per saved session, for the standup notebook.
# writes /home/aces/data/sessions.csv

import csv
import os
import pwd
import re
from datetime import datetime
from pathlib import Path

DATA = Path(os.environ.get("HONEYPOT_DATA", "/home/aces/data"))
LOGS = DATA / "logs"
OUT = DATA / "sessions.csv"
FIELDS = [
    "timestamp",
    "honeypot",
    "config",
    "attacker_ip",
    "session_seconds",
    "reason",
    "commands",
    "keystrokes",
]


def folder_time(name):
    # 20261028T175632-hp1 is eastern. a trailing z on the stamp is utc.
    stamp, hp = name.rsplit("-", 1)
    utc = stamp.endswith("Z")
    stamp = stamp[:-1] if utc else stamp
    dt = datetime.strptime(stamp, "%Y%m%dT%H%M%S")
    if utc:
        epoch = (dt - datetime(1970, 1, 1)).total_seconds()
        dt = datetime.fromtimestamp(epoch)
    return dt, hp


def parse_stats(path):
    info = {}
    if not path.is_file():
        return info
    for raw in path.read_text(errors="replace").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        info[key.strip()] = value.strip()
    return info


def main():
    rows = []
    if not LOGS.is_dir():
        raise SystemExit(f"missing {LOGS}")
    for folder in sorted(LOGS.iterdir()):
        if not re.match(r"\d{8}T\d{6}Z?-", folder.name):
            continue
        try:
            when, hp = folder_time(folder.name)
        except ValueError:
            continue
        stats = parse_stats(folder / "session.stats")
        seconds = stats.get("session_seconds", "")
        if not seconds.isdigit():
            continue
        rows.append({
            "timestamp": when.strftime("%Y-%m-%d %H:%M:%S"),
            "honeypot": stats.get("honeypot", hp),
            "config": stats.get("config", ""),
            "attacker_ip": stats.get("attacker_ip", ""),
            "session_seconds": seconds,
            "reason": stats.get("reason", ""),
            "commands": stats.get("commands", ""),
            "keystrokes": stats.get("keystrokes", ""),
        })
    with OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        user = pwd.getpwnam("aces")
        os.chown(OUT, user.pw_uid, user.pw_gid)
    print(f"wrote {len(rows)} sessions to {OUT}")


if __name__ == "__main__":
    main()
