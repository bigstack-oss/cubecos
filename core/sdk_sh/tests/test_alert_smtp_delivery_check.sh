#!/bin/bash
#
# Unit test for alert_smtp_delivery_check (../modules/sdk_alert.sh).
#
# kapacitor only logs a failed alert mail, so this check is the one place the
# failure becomes an event. It must fire once when mail starts failing, stay
# silent while it keeps failing (every failed alert logs another line, and an
# event per line would bury the table), and report recovery only after a quiet
# period. It reads kapacitor.log incrementally, and logrotate truncates that file
# in place (copytruncate), so a shrunken file must be re-read from the top.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_alert.sh"

b="$(awk '/^alert_smtp_delivery_check\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: alert_smtp_delivery_check not extracted"; exit 1; }
eval "$b"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d)
ALERT_SMTP_LOG=$T/kapacitor.log
ALERT_SMTP_STATE=$T/state/alert_smtp_delivery
ALERT_SMTP_QUIET=1800
HOSTNAME=cc1
EV=$T/events
hex_log_event(){ echo "$@" >> $EV; }
ALERT_SMTP_HEX_LOG_EVENT=hex_log_event

smtp_err(){ echo 'ts=2026-09-26T01:02:03.000Z lvl=error msg="error closing connection to SMTP server" service=smtp err="535 Authentication block"' >> $ALERT_SMTP_LOG; }
other_err(){ echo 'ts=2026-09-26T01:02:04.000Z lvl=error msg="failed to connect" service=influxdb cluster=localhost err="dial tcp: connection refused"' >> $ALERT_SMTP_LOG; }
# pretend the last smtp error was long enough ago
age(){ sed -i.bak "s/^last=.*/last=$(( $(date +%s) - $1 ))/" $ALERT_SMTP_STATE; }
run(){ : > $EV; alert_smtp_delivery_check; }

run
chk "no log: no-op"              "$(grep -c . $EV)"                 "0"
chk "no log: no state"           "$([ -f $ALERT_SMTP_STATE ] && echo y || echo n)" "n"

# errors already in the log at first run predate the check
smtp_err
run
chk "first run: baseline only"   "$(grep -c . $EV)"                 "0"

other_err
run
chk "non-smtp error ignored"     "$(grep -c . $EV)"                 "0"

smtp_err; smtp_err
run
chk "failure fires"              "$(grep -c SRV00004E $EV)"         "1"
chk "host carried"               "$(grep -c 'host=cc1' $EV)"        "1"
chk "count carried"              "$(grep -c 'errors=2' $EV)"        "1"
chk "error is tag-safe"          "$(grep -c 'error=535_Authentication_block' $EV)" "1"
chk "no category attr"           "$(grep -c 'category=' $EV)"       "0"

smtp_err
run
chk "no repeat while failing"    "$(grep -c . $EV)"                 "0"

run; age 600; run
chk "no recovery before quiet"   "$(grep -c . $EV)"                 "0"

age 1800; run
chk "recovery after quiet"       "$(grep -c SRV00005I $EV)"         "1"
run
chk "recovery once"              "$(grep -c . $EV)"                 "0"

smtp_err
run
chk "re-arms after recovery"     "$(grep -c SRV00004E $EV)"         "1"

# an error while failing restarts the quiet period
age 1700; smtp_err; run; age 600; run
chk "new error resets quiet"     "$(grep -c . $EV)"                 "0"
age 1800; run
chk "then recovers"              "$(grep -c SRV00005I $EV)"         "1"

# copytruncate: same inode, file shrinks; the new content must still be read
: > $ALERT_SMTP_LOG
smtp_err
run
chk "truncated log re-read"      "$(grep -c SRV00004E $EV)"         "1"
age 1800; run

# rotated to a new file (new inode) that is already longer than the old offset
mv $ALERT_SMTP_LOG $ALERT_SMTP_LOG.1
for i in 1 2 3 4 5 6 7 8; do other_err; done; smtp_err
run
chk "new inode re-read"          "$(grep -c SRV00004E $EV)"         "1"

# err= missing: fall back to msg=, and never emit a comma or = in a value
rm -f $ALERT_SMTP_STATE; run
echo 'ts=x lvl=error msg="smtp, failed=badly" service=smtp' >> $ALERT_SMTP_LOG
run
chk "msg fallback, sanitized"    "$(grep -c 'error=smtp_failed_badly$' $EV)" "1"

# a garbled state file must not break the check
printf 'offset=abc\nstate=failing\nlast=\n' > $ALERT_SMTP_STATE
run
chk "garbled state tolerated"    "$(grep -c . $EV)"                 "0"
chk "state rewritten"            "$(grep -c '^offset=[0-9][0-9]*$' $ALERT_SMTP_STATE)" "1"

rm -rf $T
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
