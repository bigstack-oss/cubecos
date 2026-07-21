#!/bin/bash
#
# Unit test for the rolling-restart phase_ts delegate/buffer logic in
# ../modules/sdk_power.sh: _power_roll_write_phase_ts / _power_roll_flush_phase_ts_spool
# / _power_roll_set_phase_ts. job.json lives on cephfs (not mounted early in a node's
# boot), so a stamp must be written directly, delegated to an up peer, or spooled and
# replayed -- never dropped, never fatal.
#
# Self-contained: extracts just these functions (mocks the jq write, remote_run and
# the peer lookup), so it needs no cluster and no cephfs.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"

for fn in _power_roll_write_phase_ts _power_roll_flush_phase_ts_spool _power_roll_ts_peer _power_roll_set_phase_ts ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

WRITES=$(mktemp)                       # every jq-layer write records "h p ts" here
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# mock the jq write layer
_power_roll_write(){ local h p ts; while [ $# -gt 0 ]; do case "$1" in
    --arg) case "$2" in h) h=$3;; p) p=$3;; esac; shift 3;;
    --argjson) [ "$2" = ts ] && ts=$3; shift 3;;
    *) shift;; esac; done; echo "$h $p $ts" >> "$WRITES"; }

# 1. write_phase_ts: writes when job exists; no-op + rc1 when it doesn't
ROLLING_JOB=$(mktemp); : > "$WRITES"
_power_roll_write_phase_ts n1 bootstrapping 100
chk "write(job present)" "$(cat "$WRITES")" "n1 bootstrapping 100"
rm -f "$ROLLING_JOB"; : > "$WRITES"
_power_roll_write_phase_ts n1 bootstrapping 100; chk "write(job absent) rc1" "$?" "1"
chk "write(job absent) noop" "$(cat "$WRITES")" ""

# 2. flush spool: replays every buffered stamp in order, then removes the spool
ROLLING_JOB=$(mktemp); : > "$WRITES"; SPOOL=$(mktemp)
printf 'a bootstrapping 10\nb finalizing 20\n' > "$SPOOL"
_power_roll_flush_phase_ts_spool "$SPOOL"
chk "flush replays"  "$(tr '\n' ';' < "$WRITES")" "a bootstrapping 10;b finalizing 20;"
chk "flush clears"   "$([ -e "$SPOOL" ] && echo y || echo n)" "n"

# 3. set_phase_ts branch selection (spool path overridden for the test)
export _POWER_ROLL_TS_SPOOL=$(mktemp -u)
# 3a. cephfs up -> direct write, no delegation, no spool
ROLLING_JOB=$(mktemp); : > "$WRITES"; rm -f "$_POWER_ROLL_TS_SPOOL"
_power_roll_ts_peer(){ echo PEER; }; remote_run(){ echo "DELEGATED" >> "$WRITES"; return 0; }
_power_roll_set_phase_ts n1 bootstrapping
chk "3a direct write"    "$(awk '{print $1,$2}' "$WRITES")" "n1 bootstrapping"
chk "3a no delegation"   "$(grep -c DELEGATED "$WRITES")" "0"
chk "3a no spool"        "$([ -e "$_POWER_ROLL_TS_SPOOL" ] && echo y || echo n)" "n"
# 3b. cephfs down + peer reachable + delegate ok -> delegated, no local spool
rm -f "$ROLLING_JOB" "$_POWER_ROLL_TS_SPOOL"; : > "$WRITES"
_power_roll_set_phase_ts n1 bootstrapping
chk "3b delegated"       "$(grep -c DELEGATED "$WRITES")" "1"
chk "3b no spool"        "$([ -e "$_POWER_ROLL_TS_SPOOL" ] && echo y || echo n)" "n"
# 3c. cephfs down + no peer -> buffered to spool (not lost)
rm -f "$_POWER_ROLL_TS_SPOOL"; : > "$WRITES"; _power_roll_ts_peer(){ :; }
_power_roll_set_phase_ts n1 bootstrapping
chk "3c buffered"        "$(awk '{print $1,$2}' "$_POWER_ROLL_TS_SPOOL" 2>/dev/null)" "n1 bootstrapping"
# 3d. cephfs down + peer but delegate FAILS -> falls back to spool (never lost)
rm -f "$_POWER_ROLL_TS_SPOOL"; : > "$WRITES"; _power_roll_ts_peer(){ echo PEER; }; remote_run(){ return 1; }
_power_roll_set_phase_ts n1 finalizing
chk "3d delegate-fail buffers" "$(awk '{print $1,$2}' "$_POWER_ROLL_TS_SPOOL" 2>/dev/null)" "n1 finalizing"

rm -f "$WRITES" "$_POWER_ROLL_TS_SPOOL" 2>/dev/null
echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: phase_ts delegate/buffer"; exit 0; } || exit 1
