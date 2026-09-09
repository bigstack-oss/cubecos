#!/bin/bash
#
# Unit test for storage_usage_thresholds (../modules/sdk_storage.sh).
#
# The tier is only useful if it fires on a crossing. A 15-minute timer that
# emits while a pool merely sits above the mark produces ~96 events a day and
# trains everyone to ignore the event table, so state persists between runs and
# re-arming needs a fall of 5 points below soft.
#
# Over-subscription is a separate alarm from fullness: a pool 60% full with 4x
# provisioned is the one that ends in an outage, and no used_percent threshold
# catches it.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

b="$(awk '/^storage_usage_thresholds\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: storage_usage_thresholds not extracted"; exit 1; }
eval "$b"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

STORAGE_USAGE_STATE=$(mktemp); : > $STORAGE_USAGE_STATE
# the tunables are read through hex_tuning -- a script the caller *sources*,
# which leaves the variable unset for anything still at its default
SETTINGS_TXT=$(mktemp); : > $SETTINGS_TXT
TUNEBIN=$(mktemp -d); PATH="$TUNEBIN:$PATH"
tune_defaults(){ : > $TUNEBIN/hex_tuning ; chmod +x $TUNEBIN/hex_tuning ; }
tune_defaults
HOSTNAME=sky141
EV=$(mktemp)
hex_log_event(){ echo "$@" >> $EV; }
STORAGE_USAGE_HEX_LOG_EVENT=hex_log_event

mkpool(){ echo "{\"backend\":\"CubeStorage\",\"pool\":\"cinder-volumes\",\"capacity_bytes\":1000,\"raw_used_bytes\":$1,\"provisioned_bytes\":$2}"; }
run(){ mkpool "$1" "$2" | storage_usage_thresholds; }

: > $EV; run 700 1000
chk "below soft: silent"      "$(grep -c . $EV)"            "0"

: > $EV; run 780 1000
chk "soft crossing fires"     "$(grep -c STO00001W $EV)"    "1"
chk "used_percent carried"    "$(grep -c 'used_percent=78' $EV)" "1"
chk "pool carried"            "$(grep -c 'pool=cinder-volumes' $EV)" "1"

: > $EV; run 780 1000
chk "no repeat while above"   "$(grep -c . $EV)"            "0"

: > $EV; run 880 1000
chk "hard crossing fires"     "$(grep -c STO00002E $EV)"    "1"

: > $EV; run 720 1000
chk "hysteresis holds"        "$(grep -c . $EV)"            "0"

: > $EV; run 650 1000
chk "clear fires"             "$(grep -c STO00003I $EV)"    "1"

: > $EV; run 780 1000
chk "re-arms after clear"     "$(grep -c STO00001W $EV)"    "1"

# over-subscription is independent of fullness
: > $STORAGE_USAGE_STATE; : > $EV; run 600 4000
chk "oversub fires"           "$(grep -c STO00004W $EV)"    "1"
chk "no fullness alarm"       "$(grep -c STO00001W $EV)"    "0"
: > $EV; run 600 4000
chk "oversub does not repeat" "$(grep -c STO00004W $EV)"    "0"

# a pool whose capacity is unknown must not divide by zero or alarm
: > $STORAGE_USAGE_STATE; : > $EV
echo '{"backend":"x","pool":"p","capacity_bytes":null,"raw_used_bytes":null,"provisioned_bytes":null}' | storage_usage_thresholds
chk "null capacity skipped"   "$(grep -c . $EV)"            "0"

# a tuned value must override the built-in default
cat > $TUNEBIN/hex_tuning <<'TUNE'
case "$2" in
storage.usage.threshold.soft)        T_storage_usage_threshold_soft=50 ;;
storage.usage.threshold.hard)        T_storage_usage_threshold_hard=60 ;;
storage.usage.oversubscription.warn) T_storage_usage_oversubscription_warn=9.0 ;;
esac
TUNE
chmod +x $TUNEBIN/hex_tuning
: > $STORAGE_USAGE_STATE; : > $EV; run 550 1000
chk "tuned soft honoured (55% > 50)" "$(grep -c STO00001W $EV)" "1"
: > $STORAGE_USAGE_STATE; : > $EV; run 400 1000
chk "below tuned soft is silent"     "$(grep -c . $EV)"         "0"
: > $STORAGE_USAGE_STATE; : > $EV; run 400 4000
chk "tuned oversub 9.0 not tripped by 4x" "$(grep -c STO00004W $EV)" "0"
tune_defaults

rm -rf $EV $STORAGE_USAGE_STATE $SETTINGS_TXT $TUNEBIN
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
