#!/bin/bash
# Verify power_roll_kind_active across cephfs-available / unavailable states.
T=$(mktemp -d); HOSTNAME=skyA
_power_roll_kind() { jq -r '.kind // "restart"' $ROLLING_JOB 2>/dev/null || echo restart; }
SRC=/root/cubecos/core/sdk_sh/modules/sdk_power.sh
sed -n '/^power_roll_kind_active()/,/^}/p' $SRC > $T/fn.sh; source $T/fn.sh

ROLLING_RECOVER_MARKER=$T/marker
MARK=$ROLLING_RECOVER_MARKER
chk() { printf '%-46s -> %-8s (want %s)\n' "$1" "${2:-<empty>}" "$3"; }

ROLLING_JOB=$T/nofile
rm -f $MARK 2>/dev/null
chk "cephfs down, no marker" "$(power_roll_kind_active)" "<empty>"

mkdir -p $(dirname $MARK) 2>/dev/null; touch $MARK 2>/dev/null
chk "cephfs down, marker present" "$(power_roll_kind_active)" "restart"
rm -f $MARK 2>/dev/null

ROLLING_JOB=$T/job.json
echo '{"kind":"upgrade","state":"running","nodes":[{"hostname":"skyA"}]}' > $ROLLING_JOB
chk "job running, this node in it (upgrade)" "$(power_roll_kind_active)" "upgrade"

echo '{"kind":"restart","state":"running","nodes":[{"hostname":"skyB"}]}' > $ROLLING_JOB
chk "job running, this node NOT in it" "$(power_roll_kind_active)" "<empty>"

echo '{"kind":"upgrade","state":"done","nodes":[{"hostname":"skyA"}]}' > $ROLLING_JOB
chk "job done" "$(power_roll_kind_active)" "<empty>"
rm -rf $T
