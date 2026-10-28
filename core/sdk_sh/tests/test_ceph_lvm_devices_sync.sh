#!/bin/bash
#
# Unit test for ceph_lvm_devices_sync in ../modules/sdk_ceph.sh (cubecos#2165):
# LVM's devices file gets every PV on a DAS disk or partition, and nothing else
# is read, not even an mpath map holding a guest's VG; with no PV the file is
# still created, empty, and a pvs that hangs leaves the file as it was.
#
# Fakes lsblk, pvs, lvmdevices, timeout and hex_sdk; needs no cluster.
#   Run: bash test_ceph_lvm_devices_sync.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in _ceph_probe ceph_lvm_devices_sync ; do
    fn="$(awk -v f="$f" '$0 == f"()"{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_ceph.sh")"
    [ -n "$fn" ] || { echo "FAIL: $f not found"; exit 1; }
    eval "$fn"
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CALLS=$T/calls ; LVM_DEVICES_FILE=$T/system.devices
SRVTO=60 ; HEX_SDK=fake_sdk ; HUNG=0
log_error() { :; }
timeout() { [ "$1" = -k ] && shift 2; shift; "$@"; }
fake_sdk() { [ "$1" = storage_list_das_disks ] && printf '/dev/sda\n/dev/nvme0n1\n'; }
# sda: a whole-disk PV (an encrypted OSD); nvme0n1p2: an operator's VG. An mpath
# map with a guest's VG is on the node too, but no DAS disk.
lsblk() {
    case "$*" in
        "-pnlo NAME,TYPE /dev/sda") printf '/dev/sda disk\n' ;;
        "-pnlo NAME,TYPE /dev/nvme0n1") printf '/dev/nvme0n1 disk\n/dev/nvme0n1p1 part\n/dev/nvme0n1p2 part\n' ;;
        *) printf '/dev/mapper/36000c mpath LVM2_member\n' ;;
    esac
}
pvs() {
    echo "pvs $*" >> $CALLS
    [ $HUNG = 1 ] && return 124
    local seen=",${@: -1},"
    [[ $seen == *,/dev/sda,* ]] && echo "  /dev/sda"
    [[ $seen == *,/dev/nvme0n1p2,* ]] && echo "  /dev/nvme0n1p2"
    [[ $seen == *,/dev/mapper/36000c,* ]] && echo "  /dev/mapper/36000c"
    return 0
}
lvmdevices() { echo "lvmdevices $*" >> $CALLS; echo "${@: -1}" >> $LVM_DEVICES_FILE; }

pass=0 fail=0
check() { if [ "$2" = "$3" ] ; then pass=$((pass+1)) ; else fail=$((fail+1)) ; echo "FAIL $1: got [$2] want [$3]" ; fi ; }

: > $CALLS ; rm -f $LVM_DEVICES_FILE
ceph_lvm_devices_sync ; rc=$?
check "rc" $rc 0
check "read only the DAS disks and partitions" "$(grep '^pvs' $CALLS | sed 's/.*--devices //')" \
    "/dev/sda,/dev/nvme0n1,/dev/nvme0n1p1,/dev/nvme0n1p2"
check "added: the DAS PVs" "$(grep '^lvmdevices' $CALLS | awk '{print $NF}' | tr '\n' ' ')" "/dev/sda /dev/nvme0n1p2 "
check "the guest's mpath VG left out" "$(grep -c mapper $LVM_DEVICES_FILE)" 0

# no PV anywhere: the file still exists, empty
: > $CALLS ; rm -f $LVM_DEVICES_FILE
fake_sdk() { [ "$1" = storage_list_das_disks ] && echo /dev/sdz; }
lsblk() { case "$*" in "-pnlo NAME,TYPE /dev/sdz") echo "/dev/sdz disk" ;; esac; }
ceph_lvm_devices_sync
check "no PV: empty file" "$([ -e $LVM_DEVICES_FILE ] && wc -c < $LVM_DEVICES_FILE)" 0
check "no PV: nothing added" "$(grep -c '^lvmdevices' $CALLS)" 0

# a hung pvs: no file is created, so no PV it could not read is hidden
: > $CALLS ; rm -f $LVM_DEVICES_FILE ; HUNG=1
ceph_lvm_devices_sync ; rc=$?
check "hung: rc" $rc 1
check "hung: no file" "$([ -e $LVM_DEVICES_FILE ] && echo created || echo none)" none
# ...and an existing file is left as it was
echo "IDTYPE=sys_wwid DEVNAME=/dev/sda" > $LVM_DEVICES_FILE
ceph_lvm_devices_sync
check "hung: existing file kept" "$(cat $LVM_DEVICES_FILE)" "IDTYPE=sys_wwid DEVNAME=/dev/sda"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ceph_lvm_devices_sync"; exit 0; } || exit 1
