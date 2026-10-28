#!/bin/bash
#
# Unit test for the pause reason power_roll_watchdog in ../modules/sdk_power.sh
# writes when the in-flight node misses its deadline (cubecos#2165): it names the
# budget the kick gave the node (deadline - started, scaled by its VMs), not the
# ROLLING_NODE_TIMEOUT floor, and the phase the node last stamped in phase_ts,
# not a .status the boot never advances past "rebooting".
#
# Self-contained: extracts only power_roll_watchdog and fakes the VIP check and
# the pause; job.json is a temp file read by the real jq.
#   Run: bash test_power_roll_watchdog_reason.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
body="$(awk '/^power_roll_watchdog\(\)/{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_power.sh")"
[ -n "$body" ] || { echo "FAIL: power_roll_watchdog not extracted"; exit 1; }
eval "$body"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ROLLING_JOB=$T/job.json ; SETTINGS_TXT=$T/settings ; HEX_SDK=: ; CEPH=:
# `source hex_tuning` finds it on PATH
printf 'T_cubesys_control_vip=10.32.42.10\n' > $T/hex_tuning ; PATH=$T:$PATH
is_control_node() { return 0; }
ip() { echo "2: eth0 inet 10.32.42.10/24"; }
Quiet() { :; }; log_warning() { :; }; systemctl() { :; }
_power_roll_pause() { echo "$1" > $T/reason; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ] ; then pass=$((pass+1)) ; else fail=$((fail+1)) ; echo "FAIL: $1: got [$2] want [$3]" ; fi ; }
NOW=$(date +%s)
# job <started> <deadline> <status> <phase_ts json>
job() {
    printf '{"state":"running","inflight":"cc1","deadline":%s,"nodes":[{"hostname":"cc1","status":"%s","started":%s,"phase_ts":%s}]}\n' \
        "$2" "$3" "$1" "$4" > $ROLLING_JOB
    rm -f $T/reason
}

# the cube42 incident: 13 VMs scaled the budget to 3060s; the node stamped
# bootstrapping 650s after rebooting, and .status still says rebooting
S=$(( NOW - 4000 ))
job $S $(( S + 3060 )) rebooting "{\"draining\":$(( S + 2 )),\"rebooting\":$(( S + 262 )),\"bootstrapping\":$(( S + 912 ))}"
power_roll_watchdog
chk "scaled budget, stamped phase" "$(cat $T/reason)" "watchdog: cc1 exceeded its 3060s node deadline (phase: bootstrapping)"

# no VMs: the budget is the floor
job $S $(( S + 2700 )) rebooting "{\"draining\":$(( S + 2 )),\"rebooting\":$(( S + 30 ))}"
power_roll_watchdog
chk "floor budget" "$(cat $T/reason)" "watchdog: cc1 exceeded its 2700s node deadline (phase: rebooting)"

# a job without phase_ts falls back to .status
job $S $(( S + 2700 )) draining "{}"
power_roll_watchdog
chk "no phase_ts" "$(cat $T/reason)" "watchdog: cc1 exceeded its 2700s node deadline (phase: draining)"

# within the deadline: no pause
job $NOW $(( NOW + 3060 )) rebooting "{\"rebooting\":$NOW}"
power_roll_watchdog
chk "within deadline" "$(cat $T/reason 2>/dev/null)" ""

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: power_roll_watchdog pause reason"; exit 0; } || exit 1
