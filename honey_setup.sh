#!/bin/bash
# run inside the container:  cat ./honey_setup.sh | lxc exec <container> -- bash -s
# to test somewhere else:    HONEY_ROOT=/tmp/x HONEY_LOGDIR=/tmp/y bash honey_setup.sh

set -euo pipefail

ROOT="${HONEY_ROOT:-/opt/banana-ledger}"
LOGDIR="${HONEY_LOGDIR:-/var/log/banana-ledger}"
SEED="${HONEY_SEED:-7}"

rm -rf "$ROOT" "$LOGDIR"
mkdir -p "$ROOT"/{accounts,transfers,reports,config,scripts,backups,vault} "$LOGDIR"

# one awk program makes all of the text. the first argument picks the file.
gen() {
    awk -v seed="$SEED" -v mode="$1" '
    function rnd() { state = (state * 16807) % 2147483647; return state / 2147483647 }
    function pick(a, n) { return a[int(rnd() * n) + 1] }
    function word(    s, k, n) {
        if (rnd() < 0.55) return pick(mw, nmw)
        n = 2 + int(rnd() * 2); s = ""
        for (k = 0; k < n; k++) s = s pick(cons, nc) pick(vow, nv)
        return s
    }
    function cap(w) { return toupper(substr(w, 1, 1)) substr(w, 2) }
    function name() { return cap(word()) " " cap(word()) }
    function letters(n,    s, k) {
        s = ""
        for (k = 0; k < n; k++) s = s substr("ABCDEFGHJKLMNPQRSTUVWXYZ", int(rnd() * 24) + 1, 1)
        return s
    }
    function digits(n,    s, k) {
        s = ""
        for (k = 0; k < n; k++) s = s int(rnd() * 10)
        return s
    }
    function acct() { return "BN-" letters(3) "-" digits(5) }
    function money(max) { return sprintf("%.2f", rnd() * max) }
    function day(    m, d) {
        m = 1 + int(rnd() * 10); d = 1 + int(rnd() * 28)
        return sprintf("2026-%02d-%02d", m, d)
    }
    function sentence(    s, k, n) {
        n = 6 + int(rnd() * 8); s = ""
        for (k = 0; k < n; k++) s = s (k ? " " : "") word()
        return cap(s) "."
    }
    BEGIN {
        state = (seed + 0) % 2147483646 + 1
        nc = split("b d f g k l m n p r s t v z x q", cons, " ")
        nv = split("a e i o u ai ou ee", vow, " ")
        nr = split("green yellow spotted brown", ripe, " ")
        nmw = split("banana bello poopaye tulaliloo bapple gelato papoy kampai tatata baboi wubba bananaaa belloo potatoo", mw, " ")

        if (mode == "customers") {
            print "acct_id,holder,branch,opened,balance,status"
            for (i = 0; i < 60; i++)
                printf "%s,%s,%s-%s,%s,%s,%s\n", acct(), name(), toupper(word()), digits(2), day(), money(90000), (rnd() < 0.9 ? "open" : "hold")
        }
        if (mode == "balances") {
            print "acct_id,period,opening,closing,fees"
            for (i = 0; i < 60; i++) {
                o = rnd() * 90000
                printf "%s,2026-10,%.2f,%.2f,%.2f\n", acct(), o, o + (rnd() - 0.5) * 4000, rnd() * 40
            }
        }
        if (mode == "transfers") {
            print "ref,from_acct,to_acct,amount,release_date,state"
            for (i = 0; i < 40; i++)
                printf "TR%s,%s,%s,%s,%s,%s\n", digits(8), acct(), acct(), money(25000), day(), (rnd() < 0.5 ? "queued" : "peeling")
        }
        if (mode == "recon") {
            print "BANANA LEDGER & TRUST - DAILY RECONCILIATION (NONSENSE DATA)"
            print "batch " letters(4) "-" digits(6)
            print ""
            for (i = 0; i < 25; i++)
                printf "%-12s %-18s %12s  %s\n", acct(), word() "_" word(), money(60000), (rnd() < 0.85 ? "matched" : "MISMATCH")
            print ""
            print sentence()
            print sentence()
        }
        if (mode == "readme") {
            print "banana-ledger"
            print "============="
            print ""
            for (i = 0; i < 4; i++) { print sentence() " " sentence(); print "" }
            print "contacts: " word() "@" word() ".internal"
        }
        if (mode == "conf") {
            print "# banana-ledger service settings"
            print "service_name = " word() "-ledger"
            print "db_host      = " word() "-db.internal"
            print "db_name      = " word() "_prod"
            print "db_user      = svc_" word()
            print "db_pass      = " letters(5) "-" digits(4) "-" letters(5) "-nonsense"
            print "export_dir   = /opt/banana-ledger/backups"
            print "batch_size   = " (100 + int(rnd() * 400))
        }
        if (mode == "vault") {
            print "BANANA RESERVE LEDGER (NONSENSE DATA)"
            print ""
            for (i = 0; i < 12; i++)
                printf "crate %s  bananas %d  ripeness %s  note: %s\n", letters(2) digits(3), 100 + int(rnd() * 9000), pick(ripe, nr), sentence()
        }
        if (mode == "backupnotes") {
            print "backup notes (nonsense)"
            print ""
            for (i = 0; i < 6; i++) print "- " day() ": " sentence()
        }
        if (mode == "ledgerlog") {
            for (i = 0; i < 120; i++) {
                printf "2026-10-%02d %02d:%02d:%02d %s %s %s\n", 1 + int(rnd() * 25), int(rnd() * 24), int(rnd() * 60), int(rnd() * 60), \
                    (rnd() < 0.8 ? "INFO " : "WARN "), word(), sentence()
            }
        }
        if (mode == "accesslog") {
            for (i = 0; i < 80; i++) {
                printf "2026-10-%02d %02d:%02d:%02d node-%s %s /%s/%s %d\n", 1 + int(rnd() * 25), int(rnd() * 24), int(rnd() * 60), int(rnd() * 60), \
                    letters(2), (rnd() < 0.7 ? "GET " : "POST"), word(), word(), (rnd() < 0.9 ? 200 : 403)
            }
        }
    }'
}

gen readme      > "$ROOT/README.txt"
gen customers   > "$ROOT/accounts/customers.csv"
gen balances    > "$ROOT/accounts/balances_2026-10.csv"
gen transfers   > "$ROOT/transfers/pending_transfers.csv"
gen recon       > "$ROOT/reports/daily_recon_2026-10-25.txt"
gen conf        > "$ROOT/config/ledger.conf"
gen backupnotes > "$ROOT/backups/backup_notes.txt"
gen vault       > "$ROOT/vault/banana_reserve.txt"

# a script that only prints text, so nothing in here can touch anything
cat > "$ROOT/scripts/nightly_export.sh" << 'EOF'
#!/bin/bash
# nightly export (nonsense placeholder, does nothing real)
echo "export started"
echo "export finished"
EOF

gen ledgerlog   > "$LOGDIR/ledger.log"
gen accesslog   > "$LOGDIR/access.log"

# readable by any account the attacker ends up with
chown -R root:root "$ROOT" "$LOGDIR" 2>/dev/null || true
find "$ROOT" "$LOGDIR" -type d -exec chmod 755 {} +
find "$ROOT" "$LOGDIR" -type f -exec chmod 644 {} +
chmod 755 "$ROOT/scripts/nightly_export.sh"

echo "honey files written to $ROOT and $LOGDIR"