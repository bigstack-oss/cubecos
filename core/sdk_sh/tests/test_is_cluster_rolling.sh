#!/bin/bash
T=$(mktemp -d)
cmd() { echo ""; }              # no bootstrap log match
HEX_SDK=:; cube_cluster_ready() { return 0; }
SRC=$(dirname $0)/../modules.pre/sdk_is.sh
sed -n '/^is_cluster_rolling()/,/^}/p' $SRC > $T/fn.sh; source $T/fn.sh
ROLLING_RECOVER_MARKER=$T/marker
fail=0
chk(){ printf '%-42s -> %-8s (want %s)\n' "$1" "$2" "$3"; [ "$2" = "$3" ] || fail=1; }

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
rm -f $ROLLING_RECOVER_MARKER

# A hung cephfs mount (#2204): any access under it waits until killed. A stub
# test(1) blocks on $T/hung, and a FIFO with no writer blocks jq's open. Each
# call must answer within its bound; the guard reports a hang as "hung".
mkdir -p $T/bin
printf '#!/bin/bash\n[[ "$*" == *%s/hung/* ]] && exec sleep 600\nexec %s "$@"\n' "$T" "$(type -P test)" > $T/bin/test
chmod +x $T/bin/test
mkfifo $T/fifo.json
export -f cmd cube_cluster_ready is_cluster_rolling
export HEX_SDK ROLLING_RECOVER_MARKER
hung(){
    local s=$SECONDS r
    r=$(ROLLING_JOB=$1 PATH=$T/bin:$PATH timeout 30 bash -c 'is_cluster_rolling && echo rolling || echo no')
    [ $? -eq 124 ] && r=hung
    [ $((SECONDS - s)) -le 15 ] || r="$r($((SECONDS - s))s)"
    echo $r
}
chk "cephfs hung, no marker" "$(hung $T/hung/job.json)" "no"
touch $ROLLING_RECOVER_MARKER
chk "cephfs hung, marker set" "$(hung $T/hung/job.json)" "rolling"
rm -f $ROLLING_RECOVER_MARKER
chk "job read blocks" "$(hung $T/fifo.json)" "no"
rm -rf $T
exit $fail
