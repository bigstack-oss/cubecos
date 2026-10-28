#!/bin/bash
#
# Unit test for ceph_get_ids_by_dev in ../modules/sdk_ceph.sh and the virtual-
# device rule in storage_is_das (../modules/sdk_storage.sh): ceph-volume raw
# list runs only on the asked device and its partitions -- never every disk --
# and never on nbd/loop devices, an FC path or an mpath device. Fakes ceph-volume,
# lsblk and hex_sdk; needs no cluster.
#   Run: bash test_ceph_get_ids_by_dev.sh
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(awk '/^ceph_get_ids_by_dev\(\)/ {f=1} f{print} f&&/^}/{exit}' "$DIR/../modules/sdk_ceph.sh")"
eval "$(awk '/^storage_is_das\(\)/ {f=1} f{print} f&&/^}/{exit}' "$DIR/../modules/sdk_storage.sh")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; LOG=$TMP/log
HEX_SDK=fake_sdk; CEPH=fake_ceph
storage_is_mpath() { [[ $1 == /dev/mapper/* ]]; }
fake_sdk() {
    case "$1" in
        storage_is_das) storage_is_das "$2" ;;
        storage_is_mpath) storage_is_mpath "$2" ;;
    esac
}
lsblk() {
    case "$*" in
        *"-o TRAN /dev/sdbn"*) echo fc ;;
        *"-o TRAN"*) echo sas ;;
        *"-pnlo NAME /dev/sdb"*) printf "/dev/sdb\n/dev/sdb3\n/dev/sdb4\n" ;;
        *"-pnlo NAME"*) echo "${@: -1}" ;;
    esac
}
ceph-volume() {
    echo "ceph-volume $*" >> $LOG
    case "$*" in
        "raw list /dev/sdb3 --format json") echo '{"a":{"device":"/dev/sdb3","osd_id":0}}' ;;
        "raw list /dev/sdb4 --format json") echo '{"b":{"device":"/dev/sdb4","osd_id":1}}' ;;
        "raw list"*) echo '{}' ;;
        "lvm list"*) echo '{}' ;;
    esac
}
fake_ceph() { printf "0\n1\n2\n"; }
# storage_is_das calls lsblk by absolute path
function /usr/bin/lsblk { lsblk "$@"; }
FAILS=0; check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got [$2] want [$3]" ; FAILS=$((FAILS+1)) ; fi ; }
raws() { grep -c "raw list" $LOG; }

: > $LOG; out=$(ceph_get_ids_by_dev /dev/sdb); check "das disk ids" "$out" "0 1"
check "das: only its partitions scanned" "$(grep 'raw list' $LOG | awk '{print $4}' | tr '\n' ' ')" "/dev/sdb /dev/sdb3 /dev/sdb4 "
: > $LOG; out=$(ceph_get_ids_by_dev /dev/nbd1); check "nbd: no ids" "$out" ""; check "nbd: no raw list" $(raws) 0
: > $LOG; out=$(ceph_get_ids_by_dev /dev/loop0); check "loop: no raw list" $(raws) 0
: > $LOG; out=$(ceph_get_ids_by_dev /dev/sdbn); check "fc path: no raw list" $(raws) 0
: > $LOG; out=$(ceph_get_ids_by_dev /dev/mapper/36000d31); check "mpath: no ids" "$out" ""; check "mpath: no raw list" $(raws) 0
check "storage_is_das nbd" "$(storage_is_das /dev/nbd3 && echo das || echo not)" not
check "storage_is_das sas disk" "$(storage_is_das /dev/sda && echo das || echo not)" das

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
