#!/bin/bash
#
# Unit test for _instance_metrics_ship in ../modules/sdk_instance.sh.
#
# The influx half of instance_metrics_collect failed on every run for five days on QA
# 10.32.36.10 without a trace: curl -sf into /dev/null (#1596). A failing ship must now be
# logged once when it starts and once when it recovers, and stay quiet in between, since
# the cron runs every minute; it still returns non-zero so the collection carries on.
#
# Self-contained: extracts only the function and stubs curl, shared_id and the log calls.
#   Run: bash test_instance_metrics_ship_failure_log.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_instance.sh"
T=$(mktemp -d)

body="$(awk '/^_instance_metrics_ship\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: _instance_metrics_ship not extracted"; exit 1; }
body="${body//\/run\/cube_instance_metrics.ship_failures/$T/ship_failures}"
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
CURL_RC=0
LOG=$T/log
curl_stub() { return $CURL_RC ; }
CURL=curl_stub
shared_id() { echo 10.32.36.10 ; }
log_error() { echo "ERROR $*" >> "$LOG" ; }
log_info()  { echo "INFO $*"  >> "$LOG" ; }
LP=$T/lp ; echo "vm.cpu.utilization_norm_perc,resource_id=x value=1 1" > "$LP"
logs() { grep -c "^$1 " "$LOG" ; }
ship() { _instance_metrics_ship "$LP" ; rc=$? ; }

# 1. three failing runs: rc passed through, one error, counted 3
: > "$LOG"; CURL_RC=7
ship; chk "1 rc"            "$rc" "7"
ship; ship
chk "1 one error"          "$(logs ERROR)" "1"
chk "1 counted"            "$(cat "$T/ship_failures")" "3"
chk "1 error names target" "$(grep -c 'http://10.32.36.10:9092' "$LOG")" "1"

# 2. recovery: rc 0, one info line with the count, counter cleared
CURL_RC=0
ship; chk "2 rc"            "$rc" "0"
chk "2 one recovery"       "$(logs INFO)" "1"
chk "2 recovery count"     "$(grep -c 'after 3 failed runs' "$LOG")" "1"
chk "2 cleared"            "$([ -e "$T/ship_failures" ] && echo y || echo n)" "n"

# 3. healthy runs stay quiet; nothing to ship is not a failure
: > "$LOG"
ship; ship
: > "$T/empty"; _instance_metrics_ship "$T/empty"; chk "3 empty rc" "$?" "0"
chk "3 quiet"              "$(wc -l < "$LOG" | tr -d ' ')" "0"

rm -rf "$T"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: instance metrics ship failure log" ; exit 0 ; } || exit 1
