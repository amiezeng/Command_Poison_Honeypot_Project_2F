#!/usr/bin/env python3
# one slack summary for the last 24 hours. called by daily_summary.sh.

import os
import re
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

DATA = Path(os.environ.get("HONEYPOT_DATA", "/home/aces/data"))
ROOT = Path(__file__).resolve().parent
LABELS = {
    "1": "1 control, no ascii",
    "2": "2 25% ascii",
    "3": "3 50% ascii",
    "4": "4 75% ascii",
    "5": "5 100% ascii",
}


def clock(dt):
    hour = dt.strftime("%I").lstrip("0") or "12"
    return dt.strftime(f"%Y-%m-%d {hour}:%M%p").lower()


def table(headers, rows):
    cols = list(zip(*([headers] + rows)))
    widths = [max(len(str(cell)) for cell in col) for col in cols]

    def line(row, fill=" "):
        parts = []
        for cell, width in zip(row, widths):
            text = str(cell)
            if fill != " ":
                text = fill * width
            parts.append(text.ljust(width))
        return " │ ".join(parts)

    out = [line(headers), line(headers, "─")]
    for row in rows:
        out.append(line(row))
    return "\n".join(out)


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


def load_honeypots():
    rows = []
    csv_path = ROOT / "honeypots.csv"
    for raw in csv_path.read_text().splitlines()[1:]:
        parts = raw.split(",")
        if len(parts) < 3 or not parts[0]:
            continue
        rows.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return rows


def log_time(line):
    match = re.match(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
    if not match:
        return None
    return datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")


def attacker_ip(text):
    found = "unknown"
    for match in re.findall(r"Attacker connected:\s*([0-9.]+)", text):
        if match.startswith("172.20.") or match in ("0.0.0.0", "127.0.0.1"):
            continue
        found = match
    return found


def main():
    end = datetime.now()
    start = end - timedelta(hours=24)
    honeypots = load_honeypots()
    names = [row[0] for row in honeypots]
    public = {row[0]: row[1] for row in honeypots}

    attacks = []
    logs = DATA / "logs"
    if logs.is_dir():
        for folder in logs.iterdir():
            if not re.match(r"\d{8}T\d{6}Z?-", folder.name):
                continue
            try:
                when, hp = folder_time(folder.name)
            except ValueError:
                continue
            if when < start or when >= end:
                continue
            stats = parse_stats(folder / "session.stats")
            if not stats and not (folder / "mitm.log").is_file():
                continue
            ip = stats.get("attacker_ip") or "unknown"
            if ip == "unknown" and (folder / "mitm.log").is_file():
                ip = attacker_ip((folder / "mitm.log").read_text(errors="replace"))
            attacks.append({
                "hp": stats.get("honeypot", hp),
                "ip": ip,
                "config": stats.get("config", "unknown"),
                "reason": stats.get("reason", "unknown"),
                "seconds": stats.get("session_seconds", ""),
                "commands": stats.get("commands", "0"),
                "keystrokes": stats.get("keystrokes", "0"),
                "open": False,
            })

    open_now = []
    for name, ip_pub, _port in honeypots:
        log_path = logs / f"{name}.lifecycle.log"
        if not log_path.is_file():
            continue
        last = None
        started = None
        for raw in log_path.read_text(errors="replace").splitlines():
            if re.search(r"session ended|waiting for attacker|recycle failed|did not start|no ip for", raw):
                last = "closed"
            elif "session started" in raw:
                last = "open"
                started = log_time(raw)
        if last != "open":
            continue
        if started is not None and (started < start or started >= end):
            continue
        live = DATA / "live" / name
        ip = "unknown"
        mitm = live / "mitm.log"
        if mitm.is_file():
            ip = attacker_ip(mitm.read_text(errors="replace"))
        config = "unknown"
        if (live / "config").is_file():
            digits = re.sub(r"\D", "", (live / "config").read_text(errors="replace"))
            if digits:
                config = digits
        item = {
            "hp": name,
            "ip": ip,
            "config": config,
            "reason": "still open",
            "seconds": "",
            "commands": "0",
            "keystrokes": "0",
            "open": True,
        }
        attacks.append(item)
        open_now.append(f"{name} ({ip_pub}) from {ip}")

    by_ip = Counter(item["ip"] for item in attacks)
    by_hp = Counter(item["hp"] for item in attacks)
    by_reason = Counter(item["reason"] for item in attacks)
    reached = Counter(item["config"] for item in attacks)

    deployed = Counter()
    for name in names:
        log_path = logs / f"{name}.lifecycle.log"
        if not log_path.is_file():
            continue
        for raw in log_path.read_text(errors="replace").splitlines():
            match = re.search(r"selected configuration:\s*(\d+)", raw)
            if not match:
                continue
            when = log_time(raw)
            if when is None or when < start or when >= end:
                continue
            deployed[match.group(1)] += 1

    def num(value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0

    commands = sum(num(item["commands"]) for item in attacks)
    keystrokes = sum(num(item["keystrokes"]) for item in attacks)
    lengths = [num(item["seconds"]) for item in attacks if item["seconds"] != ""]
    average = int(round(sum(lengths) / len(lengths))) if lengths else 0

    ip_rows = [(ip, str(count)) for ip, count in by_ip.most_common()]
    if not ip_rows:
        ip_rows = [("none", "0")]

    deploy_rows = [(LABELS[key], str(deployed.get(key, 0))) for key in ("1", "2", "3", "4", "5")]
    reached_rows = [(LABELS.get(key, key), str(count)) for key, count in sorted(reached.items(), key=lambda pair: pair[0])]
    if not reached_rows:
        reached_rows = [("none", "0")]

    hp_rows = [(name, public.get(name, ""), str(by_hp.get(name, 0))) for name in names]
    reason_rows = [(reason, str(count)) for reason, count in by_reason.most_common()]
    if not reason_rows:
        reason_rows = [("none", "0")]

    lines = [
        "*honeypot daily summary*",
        f"{clock(start)} through {clock(end)} et",
        "",
        "```",
        f"number of attackers total: {len(attacks)}",
        f"unique attacker ips: {len(by_ip)}",
        "",
        "attackers by ip",
        table(("ip address", "attackers"), ip_rows),
        "",
        "configurations deployed",
        table(("configuration", "times"), deploy_rows),
        "",
        "configurations attackers reached",
        table(("configuration", "attackers"), reached_rows),
        "",
        "attackers by honeypot",
        table(("honeypot", "public ip", "attackers"), hp_rows),
        "",
        "how sessions ended",
        table(("reason", "times"), reason_rows),
        "",
        f"commands: {commands}",
        f"keystrokes: {keystrokes}",
        f"average session: {average}s",
        f"still open: {len(open_now)}",
    ]
    if open_now:
        lines.extend(open_now)
    lines.append("```")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
