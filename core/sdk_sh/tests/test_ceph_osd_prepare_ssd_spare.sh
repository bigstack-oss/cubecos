#!/bin/bash
#
# ceph_osd_prepare_bluestore: a trimmed SSD keeps CEPH_OSD_SSD_SPARE_PCT of its free
# space unpartitioned; HDDs, SSDs that cannot discard and failed trims use it all.
#
#   Run: bash test_ceph_osd_prepare_ssd_spare.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh
grep -E "^(CEPH_OSD_SSD_SPARE_PCT|BLOCK_SYSFS)=" $SRC > $T/fn.sh
sed -n "/^ceph_osd_trim_ssd()/,/^}/p; /^ceph_osd_prepare_bluestore()/,/^}/p" $SRC >> $T/fn.sh
BLOCK_SYSFS=$T/block
source $T/fn.sh

LOG=$T/log
Quiet() { [ "$1" = -n ] && shift; "$@"; }
ceph_osd_zap_disk() { :; }
ceph_bluestore_label_zero() { :; }
GetFreeSectorsByDisk() { echo 1000000000; }   # 512-byte sectors
lsblk() { echo '{"blockdevices":[{"log-sec":512}]}'; }
jq() { echo 512; }
uuidgen() { echo uuid; }
partprobe() { :; }; dd() { :; }; mkfs.xfs() { :; }
sgdisk() { echo "sgdisk $*" >> $LOG; }
blkdiscard() { echo "blkdiscard $*" >> $LOG; [ -z "$TRIM_FAILS" ]; }

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-40s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-40s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}
disk(){ # name rotational discard_max_bytes
    mkdir -p $BLOCK_SYSFS/$1/queue
    echo $2 > $BLOCK_SYSFS/$1/queue/rotational
    echo $3 > $BLOCK_SYSFS/$1/queue/discard_max_bytes
}
run(){ : > $LOG; ceph_osd_prepare_bluestore /dev/$1 2 409600 scsi; }
datasizes(){ grep cube_data $LOG | grep -o '+[0-9]*M' | tr '\n' ' ' | sed 's/ $//'; }
trimmed(){ grep -q "^blkdiscard -f /dev/$1$" $LOG && echo yes || echo no; }

# 1e9 sectors over 2 data partitions: 244140M each in full, 195312M with 20% spare
disk sda 0 134217216
run sda
chk "ssd: whole disk trimmed"            "$(trimmed sda)" "yes"
chk "ssd: 20% left unpartitioned"        "$(datasizes)" "+195312M +195312M"

disk sdb 1 0
run sdb
chk "hdd: no trim"                       "$(trimmed sdb)" "no"
chk "hdd: all free space used"           "$(datasizes)" "+244140M +244140M"

disk sdc 0 0
run sdc
chk "ssd without discard: no trim"       "$(trimmed sdc)" "no"
chk "ssd without discard: no spare"      "$(datasizes)" "+244140M +244140M"

TRIM_FAILS=1 run sda
chk "failed trim: no spare"              "$(datasizes)" "+244140M +244140M"

CEPH_OSD_SSD_SPARE_PCT=0 run sda
chk "spare 0%: still trimmed"            "$(trimmed sda)" "yes"
chk "spare 0%: all free space used"      "$(datasizes)" "+244140M +244140M"

chk "meta partitions unchanged"          "$(grep -c '+200M.*cube_meta_' $LOG)" "2"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
