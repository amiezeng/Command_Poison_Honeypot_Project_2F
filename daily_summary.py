#!/usr/bin/env python3
# slack summary for the past 24 hours and every saved session.
# called by daily_summary.sh.

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


def lifecycle_log(name):
    for candidate in (
        DATA / "logs" / f"{name}.lifecycle.log",
        DATA / f"{name}.lifecycle.log",
        DATA / f"{name}.lifecycle.csv",
        DATA / "logs" / f"{name}.lifecycle.csv",
    ):
        if candidate.is_file():
            return candidate
    return None


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def config_rows(reached):
    rows = [(LABELS[key], str(reached.get(key, 0))) for key in ("1", "2", "3", "4", "5")]
    for key in sorted(reached):
        if key not in LABELS:
            rows.append((key, str(reached[key])))
    return rows


def render_section(attacks, names, public):
    by_ip = Counter(item["ip"] for item in attacks)
    by_hp = Counter(item["hp"] for item in attacks)
    by_reason = Counter(item["reason"] for item in attacks)
    reached = Counter(item["config"] for item in attacks)
    commands = sum(as_int(item["commands"]) for item in attacks)
    keystrokes = sum(as_int(item["keystrokes"]) for item in attacks)
    lengths = [as_int(item["seconds"]) for item in attacks if item["seconds"] != ""]
    average = int(round(sum(lengths) / len(lengths))) if lengths else 0
    unique = len([ip for ip in by_ip if ip != "unknown"])
    open_now = [item for item in attacks if item["open"]]

    ip_rows = [(ip, str(count)) for ip, count in by_ip.most_common()]
    if not ip_rows:
        ip_rows = [("none", "0")]
    reason_rows = [(reason, str(count)) for reason, count in by_reason.most_common()]
    if not reason_rows:
        reason_rows = [("none", "0")]
    hp_rows = [(name, public.get(name, ""), str(by_hp.get(name, 0))) for name in names]

    lines = [
        "```",
        f"number of attackers total: {len(attacks)}",
        f"unique attacker ips: {unique}",
        "",
        "attackers by ip",
        table(("ip address", "attackers"), ip_rows),
        "",
        "configurations attackers reached",
        table(("configuration", "attackers"), config_rows(reached)),
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
    for item in open_now:
        lines.append(f"{item['hp']} ({public.get(item['hp'], '')}) from {item['ip']}")
    lines.append("```")
    return lines


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
            stats = parse_stats(folder / "session.stats")
            if not stats and not (folder / "mitm.log").is_file():
                continue
            ip = stats.get("attacker_ip") or "unknown"
            if ip == "unknown" and (folder / "mitm.log").is_file():
                ip = attacker_ip((folder / "mitm.log").read_text(errors="replace"))
            attacks.append({
                "when": when,
                "hp": stats.get("honeypot", hp),
                "ip": ip,
                "config": stats.get("config", "unknown"),
                "reason": stats.get("reason", "unknown"),
                "seconds": stats.get("session_seconds", ""),
                "commands": stats.get("commands", "0"),
                "keystrokes": stats.get("keystrokes", "0"),
                "open": False,
            })

    for name, _ip_pub, _port in honeypots:
        log_path = lifecycle_log(name)
        if log_path is None:
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
        attacks.append({
            "when": started or end,
            "hp": name,
            "ip": ip,
            "config": config,
            "reason": "still open",
            "seconds": "",
            "commands": "0",
            "keystrokes": "0",
            "open": True,
        })

    recent = [item for item in attacks if start <= item["when"] < end]
    oldest = min((item["when"] for item in attacks), default=None)
    if oldest is None:
        all_label = "no saved sessions on disk"
    else:
        all_label = f"oldest saved session {clock(oldest)} et"

    lines = [
        "*honeypot summary*",
        "",
        "*past 24 hours*",
        f"{clock(start)} through {clock(end)} et",
        *render_section(recent, names, public),
        "",
        "*all saved sessions*",
        all_label,
        *render_section(attacks, names, public),
    ]
    print("\n".join(lines))


if __name__ == "__main__":
    main()
