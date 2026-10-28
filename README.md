# HACS200 Fallacy Honeypot Project

This project deploys and operates SSH honeypots to observe and study attacker
behavior in a controlled environment. Each honeypot runs in an Ubuntu LXD
container and is presented as a fictional bank environment. SSH activity is
handled by a separate MITM service, while the lifecycle scripts track sessions
and preserve their logs for later analysis.

## What it does

- Runs four honeypot containers (`hp1`–`hp4`), with public addresses and MITM
  ports listed in [`honeypots.csv`](./honeypots.csv).
- Creates a clean container snapshot with SSH enabled and generated fictional
  bank files. Each session starts from this snapshot so one visitor's changes
  do not persist into the next session.
- Randomly selects one of five configurations for each cycle: a no-art control
  or a terminal-art banner shown at 25%, 50%, 75%, or 100% coverage.
- Monitors MITM output to detect when a visitor enters or leaves, count commands
  and keystrokes, record the visitor IP when available, and end idle or
  overlong sessions.
- Records SSH login and connection events and archives session data with a
  human-readable leave reason (`attacker left`, `idle timeout`, or
  `session timeout`).

## Components

- [`create_honeypot.sh`](./create_honeypot.sh) provisions a container, runs
  shared and honeypot setup, and saves the clean snapshot.
- [`common_setup.sh`](./common_setup.sh) installs and configures SSH and the
  fictional hostname.
- [`honey_setup.sh`](./honey_setup.sh) generates the fictional bank files and
  logs placed inside each container.
- [`recycling_script.sh`](./recycling_script.sh) restores a clean snapshot,
  applies a configuration, checks SSH readiness, and starts the MITM service.
- [`lifecycle.sh`](./lifecycle.sh) runs the session loop, monitors MITM output,
  and archives session records.
- [`monitor.sh`](./monitor.sh) records SSH authentication, disconnect, and
  container health events.

## Requirements

- Linux host with LXD (`lxc`) configured and permission to manage containers.
- `screen`, `sudo`, and the usual shell utilities used by the scripts.
- The MITM Node.js service and its per-container configurations, expected by
  default under `/root/honeypots/MITM/`.
- The host NAT helper, expected by default at
  `/root/honeypots/network/nat_mitm`.
- Network and firewall rules appropriate for an authorized, isolated research
  deployment.

The MITM service and NAT helper are external dependencies; they are not included
in this repository. `recycling_script.sh` supports overriding the MITM paths
with `MITM_INDEX`, `MITM_CONFIG_DIR`, and `MITM_CONFIG`.

## Setup and operation

From the project directory, create each container once:

```bash
./create_honeypot.sh hp1
./create_honeypot.sh hp2
./create_honeypot.sh hp3
./create_honeypot.sh hp4
```

Then start lifecycle loops for all honeypots:

```bash
./lifecycle.sh --all
```

Each loop requires the matching MITM config (for example, `hp1.js`) and the
external host networking/NAT setup to be ready. To run one honeypot instead,
use `./lifecycle.sh hp1`.

## Collected data

Live per-container data is written under `~/data/live/<container>/`. Archived
sessions are saved under `~/data/logs/`, including the MITM log, session
statistics, leave reason, configuration, and any available login/session
records. The lifecycle loop can also send session-start and session-end
<<<<<<< HEAD
notifications if `SLACK_WEBHOOK_URL` is configured.
=======
notifications if `SLACK_WEBHOOK_URL` is configured.
>>>>>>> 5afe3aa08c0a9f8bbef32c29a9d41a932ba886da
