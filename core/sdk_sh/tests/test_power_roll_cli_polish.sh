#!/bin/bash
#
# Unit test for ../modules/sdk_power.sh roll CLI polish:
#  - power_roll_check_hosts rejects a non-node arg (e.g. "help") before any prompt
#  - power_roll_status stops a node's phase clock once an abort resets it to pending
#  - power_roll_start logs CLU00001I as soon as the job exists, before the first drain
# Extracts the functions and stubs cubectl, hex_log_event and the roll driver.
# Run: bash test_power_roll_cli_polish.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"

for fn in power_roll_check_hosts power_roll_status power_roll_start ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

T=$(mktemp -d); trap 'rm -rf $T' EXIT
ROLLING_DIR=$T/rolling; mkdir -p $ROLLING_DIR
ROLLING_JOB=$ROLLING_DIR/job.json
CALLS=$T/calls; : > $CALLS; HOSTNAME=n1
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

NODES='[{"hostname":"n1","role":"control-converged","ip":{"management":"10.0.0.1"}},{"hostname":"n2","role":"compute","ip":{"management":"10.0.0.2"}}]'
cubectl(){ echo "$NODES"; }
timeout(){ shift; "$@"; }

# --- 1. host validation ---
power_roll_check_hosts n1 n2 2>/dev/null; chk "valid hosts" "$?" "0"
power_roll_check_hosts 2>/dev/null; chk "no hosts = all" "$?" "0"
out=$(power_roll_check_hosts help 2>&1); rc=$?
chk "help rejected" "$rc" "1"
chk "names bad arg" "$(echo "$out" | head -1)" "unknown node(s): help"
chk "lists nodes" "$(echo "$out" | tail -1)" "cluster nodes: n1 n2"
power_roll_check_hosts n1 bogus 2>/dev/null; chk "one bad of two" "$?" "1"
power_roll_check_hosts n 2>/dev/null; chk "no substring match" "$?" "1"
power_roll_check_hosts -x 2>/dev/null; chk "dash arg rejected" "$?" "1"
( cubectl(){ :; }; power_roll_check_hosts n1 2>/dev/null ); chk "no node list fails closed" "$?" "1"

# --- 2. status phase clock ---
_power_roll_booted_since(){ return 1; }
now=$(date +%s)
phase_row(){ power_roll_status | awk -v h="$1" '$1==h' | tail -1; }
# aborted while draining: draining 60s, then reset to pending -> frozen 1m00s, no '*'
jq -n --argjson d $((now-600)) --argjson p $((now-540)) '{kind:"restart",state:"aborted",inflight:"",
    nodes:[{hostname:"n1",role:"control-converged",status:"pending",started:0,finished:0,
            phase_ts:{draining:$d,pending:$p}}]}' > $ROLLING_JOB
chk "aborted pending frozen" "$(phase_row n1 | awk '{print $2, $NF}')" "1m00s 1m00s"
# still draining: clock runs ('*')
jq -n --argjson d $((now-60)) '{kind:"restart",state:"running",inflight:"n1",
    nodes:[{hostname:"n1",role:"control-converged",status:"draining",started:$d,finished:0,
            phase_ts:{draining:$d}}]}' > $ROLLING_JOB
chk "live draining ticks" "$(phase_row n1 | awk '{print $2}' | grep -c '\*$')" "1"
# continue re-kick: pending stamp older than the new draining stamp is ignored
jq -n --argjson p $((now-300)) --argjson d $((now-60)) '{kind:"restart",state:"running",inflight:"n1",
    nodes:[{hostname:"n1",role:"control-converged",status:"draining",started:$d,finished:0,
            phase_ts:{pending:$p,draining:$d}}]}' > $ROLLING_JOB
chk "re-kicked draining ticks" "$(phase_row n1 | awk '{print $2}' | grep -c '\*$')" "1"
# untouched pending node: nothing shown
jq -n '{kind:"restart",state:"aborted",inflight:"",
    nodes:[{hostname:"n1",role:"control-converged",status:"pending",started:0,finished:0}]}' > $ROLLING_JOB
chk "never-started pending" "$(phase_row n1 | awk '{print $2, $NF}')" "- -"

# --- 3. start event before the first drain ---
rm -f $ROLLING_JOB
log_info(){ :; }; Quiet(){ [ "$1" = -n ] && shift; "$@" >/dev/null 2>&1; }
cluster_rolling_marker_set(){ :; }
HEX_SDK=hexsdk; hexsdk(){ return 0; }
_power_roll_master(){ echo n1; }; _power_roll_cli_verb(){ [ "${1:-}" = upgrade ] && echo update || echo restart; }
_power_roll_watchdog_arm(){ :; }
/usr/sbin/hex_log_event(){ echo "event $*" >> $CALLS; }
power_roll_advance(){ echo "advance" >> $CALLS; }
ROLL_EVENT_ATTRS="interface=cli,host=n1,user=root" power_roll_start restart n2 >/dev/null
chk "event logged" "$(grep -c '^event -e CLU00001I' $CALLS)" "1"
chk "event before first drain" "$(head -1 $CALLS | cut -d' ' -f1)" "event"
chk "event attrs" "$(grep CLU00001I $CALLS | cut -d' ' -f4-)" \
    "interface=cli,host=n1,user=root,category=cluster,sub=rolling_restart,action=start,scope=n2"
# no CLI attrs (direct hex_sdk call): system attrs, whole cluster
: > $CALLS; rm -f $ROLLING_JOB
power_roll_start restart >/dev/null
chk "default attrs" "$(grep CLU00001I $CALLS | cut -d' ' -f4-)" \
    "interface=system,host=n1,category=cluster,sub=rolling_restart,action=start,scope=all"
# refused start (roll already running): no event
: > $CALLS; jq -n '{state:"running",kind:"restart",nodes:[]}' > $ROLLING_JOB
power_roll_start restart >/dev/null 2>&1; chk "refused start rc" "$?" "1"
chk "refused start no event" "$(grep -c CLU00001I $CALLS)" "0"
# unknown node at start: no event
: > $CALLS; rm -f $ROLLING_JOB
power_roll_start restart nope >/dev/null 2>&1; chk "unknown node no event" "$(grep -c CLU00001I $CALLS)" "0"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: roll CLI polish"; exit 0; } || exit 1
