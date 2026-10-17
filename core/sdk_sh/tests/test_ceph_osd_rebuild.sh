#!/bin/bash
#
# Unit test for ceph_osd_rebuild in ../modules/sdk_ceph.sh: refusal cases and
# the raw/LVM in-place rebuild, with faked ceph and disk tools.
#   Run: bash test_ceph_osd_rebuild.sh
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
eval "$(awk '/^ceph_osd_rebuild\(\)/ {f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t ceph_osd_rebuild)" = function ] || { echo "FAIL: not extracted"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LOG=$TMP/log; CEPH_OSD_MAP=$TMP/map; CEPH_OSD_DIR=$TMP/osd; HOSTNAME=cube45; HEX_CFG=fake_hexcfg; CEPH=fake_ceph
echo "/dev/sdb1 0 756c6894-meta 8c9dd22f-data" > $CEPH_OSD_MAP
echo "/dev/sdb2 1 05dda8d9-meta 4b1c6ac4-data" >> $CEPH_OSD_MAP
Quiet() { "$@"; }; log_error() { echo "ERR $*" >> $LOG; }; log_info() { :; }
sleep() { SECONDS=$((SECONDS + $1)); }
timeout() { [ "$1" = -k ] && shift 2; shift; "$@"; }
systemctl() { echo "systemctl $*" >> $LOG; [ "$1" = start ] && touch $TMP/refreshed; return 0; }
umount() { echo "umount $*" >> $LOG; }; chown() { echo "chown $*" >> $LOG; }
ceph_osd_remount_one() { echo "remount_one $*" >> $LOG; mkdir -p $CEPH_OSD_DIR/ceph-$1; }
ceph-osd() { echo "ceph-osd $*" >> $LOG; }
dd() { echo "dd $*" >> $LOG; }; mkfs.xfs() { echo "mkfs.xfs $*" >> $LOG; }
ceph_bluestore_label_zero() { echo "labelzero $*" >> $LOG; }
ceph_osd_datapart_resolve() { [ "$1" = 8c9dd22f-data ] && echo /dev/sdb3; }
fake_hexcfg() { echo "hex_config $*" >> $LOG; }
ceph_osd_restart() { echo "ceph_osd_restart $*" >> $LOG; }
ceph-volume() {
    case "$1 $2" in
        "lvm list") echo '{"5":[{"type":"block","lv_path":"/dev/ceph-a/osd-block-a","tags":{"ceph.encrypted":"0","ceph.osd_fsid":"fsid-a"}}],"6":[{"type":"block","lv_path":"/dev/ceph-b/osd-block-b","tags":{"ceph.encrypted":"1","ceph.osd_fsid":"fsid-b"}}]}' ;;
        "lvm activate") echo "ceph-volume $*" >> $LOG; touch $TMP/refreshed ;;
        *) echo "ceph-volume $*" >> $LOG ;;
    esac
}
fake_ceph() {
    case "$1 $2" in
        "osd find") echo "{\"crush_location\":{\"host\":\"$OSDHOST\"}}" ;;
        "osd dump") local up=$UP; [ -f $TMP/refreshed ] && up=1; echo "{\"osds\":[{\"osd\":0,\"up\":$up},{\"osd\":1,\"up\":1},{\"osd\":5,\"up\":$up},{\"osd\":6,\"up\":$up},{\"osd\":7,\"up\":$up}]}" ;;
        "pg ls-by-osd") echo "Error EAGAIN: osd $3 is not up" >&2; return 11 ;;
        # stale PGs of a down OSD keep it in up/acting; 26.5 lives on another OSD
        "pg dump") [ -n "$PGFAIL" ] && return 1; echo "{\"pg_ready\":true,\"pg_stats\":[{\"pgid\":\"22.1\",\"state\":\"active+undersized\",\"up\":[1,2],\"acting\":[1,2]},{\"pgid\":\"$PGPOOL.3\",\"state\":\"stale+active+clean\",\"up\":[0],\"acting\":[0]},{\"pgid\":\"26.5\",\"state\":\"active+clean\",\"up\":[1],\"acting\":[1]}]}" ;;
        "osd pool") echo "[{\"pool_id\":22,\"pool_name\":\"cinder-volumes\",\"size\":3},{\"pool_id\":26,\"pool_name\":\"non-ec\",\"size\":$P26SIZE}]" ;;
        *) echo "ceph $*" >> $LOG ;;
    esac
}
FAILS=0
run() { : > $LOG; rm -f $TMP/refreshed; SECONDS=0; ceph_osd_rebuild "$@"; RC=$?; }
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got [$2] want [$3]" ; FAILS=$((FAILS+1)) ; fi ; }
has() { grep -qF -- "$1" $LOG && echo yes || echo no; }

OSDHOST=cube46 UP=0 PGPOOL=22 P26SIZE=3; run 0;     check "other host refused" $RC 1; check "other host: nothing destroyed" $(has "osd destroy") no
OSDHOST=cube45 UP=1;                      run 0;     check "up osd refused" $RC 1
UP=0;                                     run 7;     check "non-raw osd refused" $RC 1
PGPOOL=26 P26SIZE=1;                      run 0;     check "size-1 pool refused" $RC 1; check "size-1 names the pool" $(has "non-ec") yes; check "size-1: noout untouched" $(has "osd set noout") no
                                          run 0 force; check "size-1 with force rebuilds" $RC 0
PGPOOL=22 P26SIZE=1;                      run 0;     check "size-1 pg on another osd ignored" $RC 0
PGFAIL=1 P26SIZE=3;                       run 0;     check "unreadable pg map refused" $RC 1; check "unreadable: nothing destroyed" $(has "osd destroy") no
                                          run 0 force; check "unreadable with force rebuilds" $RC 0
PGFAIL= ;                                 run osd.0; check "happy path rc" $RC 0
check "noout set"               $(has "ceph osd set noout") yes
check "destroy keeps id"        $(has "ceph osd destroy 0 --yes-i-really-mean-it") yes
check "only its datapart wiped" $(has "dd if=/dev/zero of=/dev/sdb3") yes
check "neighbour untouched"     $(grep -cE "sdb2|sdb4|ceph-osd@1|remount_one 1" $LOG) 0
check "no all-osd refresh"      $(grep -cE "refresh_ceph_osd|ceph_osd_restart|activate --all" $LOG) 0
check "remount only this osd"   $(has "remount_one 0") yes
check "bluestore type written"  "$(cat $CEPH_OSD_DIR/ceph-0/type)" bluestore
check "mkfs osd keeps uuid"     $(has "ceph-osd -i 0 --mkfs --osd-uuid 756c6894-meta") yes
check "only this osd started"   $(has "systemctl start ceph-osd@0") yes
check "metapart keeps fs uuid"  $(has "mkfs.xfs -f -m uuid=756c6894-meta /dev/sdb1") yes
check "osd new reuses id"       $(has "ceph osd new 756c6894-meta 0") yes
check "noout unset"             $(has "ceph osd unset noout") yes
ORDER='osd destroy|mkfs.xfs|osd new|remount_one|ceph-osd -i|start ceph-osd'
check "order destroy<mkfs<new<remount<mkfs<start" "$(grep -oE "$ORDER" $LOG | tr '\n' ,)" "osd destroy,mkfs.xfs,osd new,remount_one,ceph-osd -i,start ceph-osd,"


# LVM: zap keeps the LV, prepare reuses the id on the same LV, activate starts only it
run 5;  check "lvm rebuild rc" $RC 0
check "lvm zap keeps lv"        $(has "ceph-volume lvm zap --osd-id 5") yes
check "lvm zap not --destroy"   $(has "--destroy") no
check "lvm prepare same id/lv"  $(has "ceph-volume lvm prepare --bluestore --osd-id 5 --data /dev/ceph-a/osd-block-a") yes
check "lvm activates only it"   $(has "ceph-volume lvm activate --bluestore 5 fsid-a") yes
check "lvm: no activate --all"  $(grep -cE "activate --all|ceph_osd_restart" $LOG) 0
check "lvm: no raw wipe"        $(grep -cE "mkfs.xfs|dd if=" $LOG) 0
# encrypted LVM: re-encrypted on prepare
run 6;  check "encrypted rebuild rc" $RC 0
check "encrypted keeps dmcrypt" $(has "ceph-volume lvm prepare --bluestore --dmcrypt --osd-id 6 --data /dev/ceph-b/osd-block-b") yes
# unknown id: neither raw nor lvm
run 7;  check "unknown osd refused" $RC 1; check "unknown: nothing destroyed" $(has "osd destroy") no

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
