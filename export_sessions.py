#!/usr/bin/env python3
# one row per saved session, for the standup notebook.
# writes /home/aces/data/sessions1.csv

import csv
import os
import pwd
import re
from datetime import datetime
from pathlib import Path

DATA = Path(os.environ.get("HONEYPOT_DATA", "/home/aces/data"))
LOGS = DATA / "logs"
OUT = DATA / "sessions1.csv"
MAX_SESSION = int(os.environ.get("MAX_SECONDS", "300"))
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


def row_key(row):
    return tuple(row.get(field, "") or "" for field in FIELDS)


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
        if int(seconds) > MAX_SESSION and not (
            stats.get("reason") == "session timeout" and int(seconds) <= MAX_SESSION + 30
        ):
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

    existing = set()
    if OUT.is_file() and OUT.stat().st_size:
        with OUT.open(newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != FIELDS:
                raise SystemExit(f"{OUT} has an unexpected CSV header")
            existing.update(row_key(row) for row in reader)

    new_rows = []
    for row in rows:
        key = row_key(row)
        if key not in existing:
            new_rows.append(row)
            existing.add(key)

    needs_header = not OUT.is_file() or OUT.stat().st_size == 0
    with OUT.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        if needs_header:
            writer.writeheader()
        writer.writerows(new_rows)
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        user = pwd.getpwnam("aces")
        os.chown(OUT, user.pw_uid, user.pw_gid)
    print(f"appended {len(new_rows)} sessions to {OUT}")


if __name__ == "__main__":
    main()
