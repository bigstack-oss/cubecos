#!/bin/bash
#
# Unit test for power_roll_precheck (../modules/sdk_power.sh), #2164: a rolling upgrade
# refuses while any control node's broker has a feature flag disabled or cannot be asked,
# names each node and flag, and power_roll_start refuses before it marks, stages or
# claims anything. Extracts the functions and stubs cubectl and remote_run.
# Run: bash test_power_roll_precheck.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_power.sh"
for fn in power_roll_precheck power_roll_start ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

T=$(mktemp -d); trap 'rm -rf $T' EXIT
CALLS=$T/calls; : > $CALLS
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has(){ grep -qF -- "$1" $CALLS && echo y || echo n; }

cubectl(){ echo '[{"hostname":"cc1"},{"hostname":"cc2"},{"hostname":"cc3"}]'; }
HEX_SDK=hexsdk
log_error(){ echo "error $1" >> $CALLS; }
# per-node answer in $T/off/<node>; a node listed in DEAD fails like an unreachable one
DEAD=""
remote_run(){ echo "rr $1 $2" >> $CALLS; [[ " $DEAD " == *" $1 "* ]] && return 1; cat $T/off/$1 2>/dev/null; return 0; }
reset(){ rm -rf $T/off; mkdir $T/off; DEAD=""; : > $CALLS; }

reset
out=$(power_roll_precheck 2>&1); rc=$?
chk "all on: passes" "$rc" 0
chk "all on: silent" "$out" ""
chk "asks every control" "$(grep -c '^rr cc[123] hexsdk os_rabbitmq_flags_disabled$' $CALLS)" 3

reset; for h in cc1 cc2 cc3 ; do echo "feature_flags_v2 stream_single_active_consumer" > $T/off/$h ; done
out=$(power_roll_precheck 2>&1); rc=$?
chk "flags off: refuses" "$rc" 1
chk "flags off: names each node" "$(echo "$out" | grep -c '^precheck FAILED: rabbitmq feature flags disabled on cc[123]: feature_flags_v2 stream_single_active_consumer$')" 3
chk "flags off: says how to fix" "$(echo "$out" | grep -c 'hex_config rabbitmq_feature_flags')" 1
chk "flags off: nothing touched" "$(echo "$out" | tail -1)" "Upgrade aborted; no node was touched."
chk "flags off: logged" "$(has 'error rolling_upgrade: precheck failed')" y

reset; DEAD="cc2"
out=$(power_roll_precheck 2>&1); rc=$?
chk "unreadable broker: refuses" "$rc" 1
chk "unreadable broker: named" "$(echo "$out" | head -1)" "precheck FAILED: cannot read the rabbitmq feature flags on cc2"
chk "unreadable broker: others still asked" "$(has 'rr cc3 ')" y

# power_roll_start upgrade: refused before the marker, ceph, the lock or the stage
reset; echo "feature_flags_v2" > $T/off/cc1
ROLLING_DIR=$T/rolling ROLLING_JOB=$T/rolling/job.json
_power_roll_resolve_pkg(){ echo /var/update/x.pkg; }
cluster_rolling_marker_set(){ echo "marker" >> $CALLS; }
Quiet(){ echo "quiet $*" >> $CALLS; }
_power_roll_stage_all(){ echo "stage" >> $CALLS; }
power_roll_start upgrade x.pkg >/dev/null 2>&1; rc=$?
chk "start: refused" "$rc" 1
chk "start: no marker" "$(has marker)" n
chk "start: no ceph_enter_rolling" "$(has quiet)" n
chk "start: no stage" "$(has stage)" n
chk "start: no job dir" "$([ -e $T/rolling ] && echo y || echo n)" n

# a restart roll changes no version: not prechecked
reset; echo "feature_flags_v2" > $T/off/cc1
power_roll_start restart >/dev/null 2>&1
chk "restart: no precheck" "$(has 'os_rabbitmq_flags_disabled')" n

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
