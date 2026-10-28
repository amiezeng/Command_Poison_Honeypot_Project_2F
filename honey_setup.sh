#!/bin/bash
# run inside the container:  cat ./honey_setup.sh | lxc exec <container> -- bash -s
# to test somewhere else:    HONEY_ROOT=/tmp/x HONEY_LOGDIR=/tmp/y bash honey_setup.sh

set -euo pipefail

ROOT="${HONEY_ROOT:-/opt/banana-ledger}"
LOGDIR="${HONEY_LOGDIR:-/var/log/banana-ledger}"
SEED="${HONEY_SEED:-7}"

rm -rf "$ROOT" "$LOGDIR"
mkdir -p "$ROOT"/{accounts,transfers,reports,config,scripts,backups,vault,branches,loans,statements,compliance,audit,treasury,database,exports,archives} "$LOGDIR"

# Every generated record uses only the fictional banana/minion word list below.
gen() {
    awk -v seed="$SEED" -v mode="$1" '
    function rnd() { state = (state * 16807) % 2147483647; return state / 2147483647 }
    function word() { return words[int(rnd() * count) + 1] }
    BEGIN {
        state = (seed + 0) % 2147483646 + 1
        count = split("banana bello poopaye tulaliloo bapple gelato papoy kampai tatata baboi wubba bananaaa belloo potatoo", words, " ")
        lines = 12
        fields = 7
        separator = " "
        if (mode == "customers" || mode == "balances" || mode == "branches" || mode == "loans" || mode == "compliance" || mode == "transfers") {
            lines = 40
            separator = ","
        }
        if (mode == "branches" || mode == "vault" || mode == "treasury") lines = 18
        if (mode == "loans" || mode == "compliance") lines = 24
        if (mode == "transfers") lines = 32
        if (mode == "ledgerlog") lines = 120
        if (mode == "accesslog") lines = 80
        if (mode == "backupnotes") lines = 6
        if (mode == "readme") lines = 8
        if (mode == "audit") lines = 50

        for (row = 0; row < lines; row++) {
            fields = 4 + int(rnd() * 5)
            for (column = 0; column < fields; column++)
                printf "%s%s", (column ? separator : ""), word()
            print ""
        }
    }'
}

gen readme      > "$ROOT/README.txt"
gen customers   > "$ROOT/accounts/customers.csv"
gen balances    > "$ROOT/accounts/balances_2026-10.csv"
gen branches    > "$ROOT/branches/branch_directory.csv"
gen loans       > "$ROOT/loans/loan_book.csv"
gen statements  > "$ROOT/statements/sample_2026-10.txt"
gen compliance  > "$ROOT/compliance/review_queue.csv"
gen audit       > "$ROOT/audit/operations.audit"
gen treasury    > "$ROOT/treasury/daily_position.txt"
gen schema      > "$ROOT/database/schema_notes.txt"
gen manifest    > "$ROOT/archives/archive_manifest.txt"
gen transfers   > "$ROOT/transfers/pending_transfers.csv"
gen recon       > "$ROOT/reports/daily_recon_2026-10-25.txt"
gen conf        > "$ROOT/config/ledger.conf"
gen backupnotes > "$ROOT/backups/backup_notes.txt"
gen vault       > "$ROOT/vault/banana_reserve.txt"
gen backupnotes > "$ROOT/exports/export_notes.txt"

gen script      > "$ROOT/scripts/nightly_export.txt"

gen ledgerlog   > "$LOGDIR/ledger.log"
gen accesslog   > "$LOGDIR/access.log"

# readable by any account the attacker ends up with
chown -R root:root "$ROOT" "$LOGDIR" 2>/dev/null || true
find "$ROOT" "$LOGDIR" -type d -exec chmod 755 {} +
find "$ROOT" "$LOGDIR" -type f -exec chmod 644 {} +

echo "honey files written to $ROOT and $LOGDIR"