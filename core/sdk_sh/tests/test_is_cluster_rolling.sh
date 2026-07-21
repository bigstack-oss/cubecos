#!/bin/bash
T=$(mktemp -d)
cmd() { echo ""; }              # no bootstrap log match
HEX_SDK=:; cube_cluster_ready() { return 0; }
SRC=/root/cubecos/core/sdk_sh/modules.pre/sdk_is.sh
sed -n '/^is_cluster_rolling()/,/^}/p' $SRC > $T/fn.sh; source $T/fn.sh
ROLLING_RECOVER_MARKER=$T/marker
chk(){ printf '%-42s -> %-8s (want %s)\n' "$1" "$2" "$3"; }

ROLLING_JOB=$T/none
rm -f $ROLLING_RECOVER_MARKER
is_cluster_rolling && r=rolling || r=no; chk "no job, no marker" "$r" "no"
touch $ROLLING_RECOVER_MARKER
is_cluster_rolling && r=rolling || r=no; chk "no job (cephfs down), marker set" "$r" "rolling"
rm -f $ROLLING_RECOVER_MARKER

ROLLING_JOB=$T/job.json
echo '{"state":"running"}' > $ROLLING_JOB
is_cluster_rolling && r=rolling || r=no; chk "job running" "$r" "rolling"
echo '{"state":"done"}' > $ROLLING_JOB
is_cluster_rolling && r=rolling || r=no; chk "job done" "$r" "no"
echo '{"state":"paused"}' > $ROLLING_JOB
is_cluster_rolling && r=rolling || r=no; chk "job paused (repair allowed)" "$r" "no"
# job wins over a stale marker
echo '{"state":"done"}' > $ROLLING_JOB; touch $ROLLING_RECOVER_MARKER
is_cluster_rolling && r=rolling || r=no; chk "job done + stale marker" "$r" "no"
rm -rf $T
