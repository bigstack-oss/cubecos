#!/bin/bash
T=$(mktemp -d)
SRC=$(dirname $0)/../modules.pre/sdk_is.sh
sed -n '/^is_rolling_restart_boot()/,/^}/p' $SRC > $T/fn.sh; source $T/fn.sh
HOSTNAME=cube45
fail=0
chk(){ printf '%-44s -> %-4s (want %s)\n' "$1" "$2" "$3"; [ "$2" = "$3" ] || fail=1; }
run(){ is_rolling_restart_boot && echo yes || echo no; }

ROLLING_JOB=$T/none
chk "no job (cephfs down)" "$(run)" "no"
ROLLING_JOB=$T/job.json
echo '{"kind":"restart","state":"running","inflight":"cube45"}' > $ROLLING_JOB
chk "restart, running, this node in flight" "$(run)" "yes"
echo '{"kind":"restart","state":"running","inflight":"cube46"}' > $ROLLING_JOB
chk "restart, running, other node in flight" "$(run)" "no"
echo '{"kind":"restart","state":"running","inflight":""}' > $ROLLING_JOB
chk "restart, running, nothing in flight" "$(run)" "no"
echo '{"kind":"upgrade","state":"running","inflight":"cube45"}' > $ROLLING_JOB
chk "upgrade, running, this node in flight" "$(run)" "no"
echo '{"state":"running","inflight":"cube45"}' > $ROLLING_JOB
chk "no kind (older job)" "$(run)" "no"
echo '{"kind":"restart","state":"paused","inflight":"cube45"}' > $ROLLING_JOB
chk "restart, paused" "$(run)" "no"
echo '{"kind":"restart","state":"done","inflight":"cube45"}' > $ROLLING_JOB
chk "restart, done" "$(run)" "no"
echo 'garbage' > $ROLLING_JOB
chk "unparsable job" "$(run)" "no"
rm -rf $T
exit $fail
