#!/bin/bash
#
# Unit test for ceph_volume_raw_list_das in ../modules/sdk_ceph.sh (cubecos#2165):
# the DAS disks come from one storage_list_das_disks call, not a hex_sdk call per
# disk (seconds each on an FC-heavy node), and ceph-volume raw list runs on each
# DAS disk and its partitions only, its results merged.
#
# Fakes lsblk, ceph-volume and hex_sdk; needs no cluster.
#   Run: bash test_ceph_volume_raw_list_das.sh   (exit 0 = pass)
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(awk '/^ceph_volume_raw_list_das\(\)/ {f=1} f{print} f&&/^}/{exit}' "$DIR/../modules/sdk_ceph.sh")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; LOG=$TMP/log
HEX_SDK=fake_sdk
fake_sdk() { echo "hex_sdk $*" >> $LOG; [ "$1" = storage_list_das_disks ] && printf '/dev/sda\n/dev/sdb\n'; }
lsblk() {
    case "$*" in
        *"-pnlo NAME /dev/sda") printf '/dev/sda\n/dev/sda1\n' ;;
        *"-pnlo NAME /dev/sdb") printf '/dev/sdb\n/dev/sdb1\n/dev/sdb2\n/dev/sdb3\n' ;;
    esac
}
ceph-volume() {
    echo "ceph-volume $*" >> $LOG
    case "$*" in
        "raw list /dev/sdb3 --format json") echo '{"u3":{"device":"/dev/sdb3","osd_id":0}}' ;;
        "raw list /dev/sdb1 --format json") echo '{"u1":{"device":"/dev/sdb1","osd_id":1}}' ;;
        "raw list"*) echo '{}' ;;
    esac
}
FAILS=0; check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got [$2] want [$3]" ; FAILS=$((FAILS+1)) ; fi ; }

out=$(ceph_volume_raw_list_das)
check "merged" "$(echo "$out" | jq -c -S .)" '{"u1":{"device":"/dev/sdb1","osd_id":1},"u3":{"device":"/dev/sdb3","osd_id":0}}'
check "one hex_sdk call" "$(grep '^hex_sdk' $LOG)" "hex_sdk storage_list_das_disks"
check "raw list on DAS disks and partitions only" "$(grep 'raw list' $LOG | awk '{print $4}' | tr '\n' ' ')" \
    "/dev/sda /dev/sda1 /dev/sdb /dev/sdb1 /dev/sdb2 /dev/sdb3 "
fake_sdk() { echo "hex_sdk $*" >> $LOG; }
check "no DAS disk: empty map" "$(ceph_volume_raw_list_das | jq -c .)" '{}'

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
