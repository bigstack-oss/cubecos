#!/bin/bash
#
# Unit test for power_bootup_mark in ../modules/sdk_power.sh: it records the phase,
# and marking done starts the one-time amphora VIP re-announce migration.
#   Run: bash test_power_bootup_mark.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
sed -n "/^power_bootup_mark()/,/^}/p" $D/../modules/sdk_power.sh > $T/fn.sh
source $T/fn.sh
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }
BOOTUP_STATUS_FILE=$T/status; HEX_SDK=hex_sdk; HOSTNAME=n1
log_info() { :; }
/usr/sbin/hex_log_event() { :; }
setsid() { echo "$*" >> $T/spawn; }

power_bootup_mark finalizing; wait
check "other phases start nothing" "$(cat $T/spawn 2>/dev/null)" ""
check "phase recorded" "$(awk '{print $1}' $T/status | tail -1)" "finalizing"
power_bootup_mark done; wait
check "done starts the amphora migration" "$(cat $T/spawn 2>/dev/null)" "hex_sdk migrate_octavia_amphora_vip_advertise"

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
