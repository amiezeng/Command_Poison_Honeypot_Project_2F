# HACS200 Fallacy Honeypot Project

This project investigates attacker behavior in response to command-output poisoning within a controlled honeypot environment. Each honeypot operates inside an Ubuntu LXD container configured to simulate a fictional banking system. When an attacker executes a command, the resulting output is modified using one of five predefined ASCII-based poisoning configurations. SSH interactions are managed through the ACES man-in-the-middle (MITM) service, while automated lifecycle scripts monitor and track individual sessions, preserving detailed activity logs for subsequent analysis.

## Null Hypothesis (H₀)
Command-output poisoning has no statistically significant effect on attacker behavior within the honeypot environment.

## Alternative Hypothesis (Hₐ)
Command-output poisoning has a statistically significant effect on attacker behavior within the honeypot environment.

## Data Collection
- A Slack bot is used to provide automated notifications and updates on completed honeypot sessions.
- Real-time data for each honeypot container is stored in ~/data/live/<container>/.
- Completed sessions are archived in ~/data/logs/ for future analysis.
### Archived records include:
- SSH man-in-the-middle (MITM) logs
- Session statistics
- Attacker disconnect or leave reasons
- Command-output poisoning configuration
- Available login and session activity records

## How it works

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
  archives session records, and appends each completed session as one row to
  `~/data/<honeypot>.lifecycle.csv`. Repeat sessions from the same attacker IP
  are recorded as separate rows.
- [`monitor.sh`](./monitor.sh) records SSH authentication, disconnect, and
  container health events.
