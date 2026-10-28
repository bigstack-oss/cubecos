#!/bin/bash
#
# Unit test for the OSD partition probes in ../modules/sdk_ceph.sh on a node
# with FC multipath LUNs (cubecos#2165): ceph_osd_list_meta_partitions and
# ceph_osd_datapart_resolve probe only DAS partitions, never an FC path, an
# mpath member or an nbd device, and a probe that hangs is reported as such --
# list fails, resolve and has_osd return 2 -- never as an absent device.
#
# Fakes lsblk, blkid, lvs, ceph-bluestore-tool, timeout and hex_sdk; needs no
# cluster.   Run: bash test_ceph_osd_probe_das_only.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in _ceph_das_partitions _ceph_probe ceph_osd_list_meta_partitions ceph_osd_datapart_has_osd \
         ceph_osd_datapart_resolve ceph_osd_partuuid_of ceph_osd_datapart_scan ; do
    fn="$(awk -v f="$f" '$0 == f"()"{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_ceph.sh")"
    [ -n "$fn" ] || { echo "FAIL: $f not found"; exit 1; }
    eval "$fn"
done
for f in storage_is_das storage_list_das_disks ; do
    eval "$(awk -v f="$f" '$0 == f"()"{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_storage.sh")"
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CALLS=$T/calls ; ERRS=$T/errs
SRVTO=60 ; HEX_SDK=fake_sdk
HUNG=""            # a probe whose arguments contain this word "times out"
log_error() { echo "$1" >> $ERRS; }
timeout() { [ "$1" = -k ] && shift 2; shift; "$@"; }
fake_sdk() {
    case "$1" in
        storage_list_das_disks) echo "hex_sdk $1" >> $CALLS ; storage_list_das_disks ;;
    esac
}
# sdj and sdu are the two FC paths of one Compellent LUN (dm-6), nbd0 a virtual disk
storage_is_mpath() { [ "$1" = /dev/sdu ] || [ "$1" = /dev/sdj ]; }
function /usr/bin/lsblk { lsblk "$@"; }
lsblk() {
    echo "lsblk $*" >> $CALLS
    case "$*" in
        "-dpno NAME,TYPE") printf '/dev/sda disk\n/dev/nvme0n1 disk\n/dev/sdj disk\n/dev/sdu disk\n/dev/sdk disk\n/dev/nbd0 disk\n/dev/mapper/36000d31 mpath\n' ;;
        "-dn -o TRAN /dev/sdk") echo fc ;;
        "-dn -o TRAN "*) echo sas ;;
        "-pnlo NAME,TYPE /dev/sda") printf '/dev/sda disk\n/dev/sda1 part\n/dev/sda2 part\n/dev/sda3 part\n/dev/sda4 part\n' ;;
        "-pnlo NAME,TYPE /dev/nvme0n1") printf '/dev/nvme0n1 disk\n/dev/nvme0n1p1 part\n/dev/nvme0n1p3 part\n' ;;
        "-pnlo NAME,TYPE "*) echo "unexpected lsblk $*" >&2 ;;
        # udev lost the PARTUUID of the FC partitions too: they would be scan candidates
        "-lnpo NAME,TYPE,PARTUUID") printf '/dev/sda3 part\n/dev/sdj1 part\n/dev/sdk1 part\n/dev/nvme0n1p3 part\n' ;;
    esac
}
blkid() {
    echo "blkid $*" >> $CALLS
    [ -n "$HUNG" ] && [[ " $* " == *" $HUNG "* ]] && return 124
    case "$*" in
        "/dev/sda1 /dev/sda2 /dev/sda3 /dev/sda4 /dev/nvme0n1p1 /dev/nvme0n1p3")
            echo '/dev/sda1: UUID="m1" TYPE="xfs" PARTLABEL="cube_meta_a_1" PARTUUID="p1"'
            echo '/dev/sda2: UUID="m2" TYPE="xfs" PARTLABEL="cube_meta_a_2" PARTUUID="p2"'
            echo '/dev/sda3: PARTLABEL="cube_data_a_3" PARTUUID="d3"'
            echo '/dev/nvme0n1p1: UUID="m3" TYPE="xfs" PARTLABEL="cube_meta_0n1_1" PARTUUID="p3"' ;;
        "-o device --match-token PARTUUID=d3 "*) echo /dev/sda3 ;;
        "-o device --match-token PARTUUID="*) return 2 ;;
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID /dev/nvme0n1p3") echo n3 ;;
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID /dev/sda3") echo d3 ;;
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID "*) return 2 ;;
        *) echo "unexpected blkid $*" >&2; return 99 ;;
    esac
}
lvs() {
    echo "lvs $*" >> $CALLS
    [ -n "$HUNG" ] && [[ " $* " == *" $HUNG "* ]] && return 124
    case "$*" in *"lv_uuid=lv1"*) echo "  /dev/vg/osd-lv" ;; esac
}
ceph-bluestore-tool() {
    echo "ceph-bluestore-tool $*" >> $CALLS
    [ -n "$HUNG" ] && [[ " $* " == *" $HUNG "* ]] && return 124
    case "$*" in
        "show-label --dev /dev/sda3") echo '{"/dev/sda3":{"osd_uuid":"o3"}}' ;;
        *) return 1 ;;
    esac
}
# udev's /dev/disk/by-partuuid links: "uuid=device" pairs, none by default
LINKS=""
readlink() {
    local l
    for l in $LINKS ; do [ "$2" = "/dev/disk/by-partuuid/${l%%=*}" ] && { echo ${l#*=} ; return 0 ; } ; done
    return 1
}
# the partitions the scan's on-disk probe needs to exist
mkdir -p $T/dev ; for p in sda3 sda4 sdj1 sdk1 nvme0n1p3 ; do touch $T/dev/$p ; done
_e() { [ -e "$T$1" ]; }
eval "$(declare -f ceph_osd_partuuid_of | sed 's/\[ -e "\$dev" \]/_e "$dev"/')"

pass=0 fail=0
check() { if [ "$2" = "$3" ] ; then pass=$((pass+1)) ; else fail=$((fail+1)) ; echo "FAIL $1: got [$2] want [$3]" ; fi ; }
probed() { grep -E "^(blkid|lvs|ceph-bluestore-tool) " $CALLS | grep -cE "$1"; }
run() { : > $CALLS ; : > $ERRS ; out=$("$@") ; rc=$? ; }

# the DAS partitions: no FC path, mpath member, nbd or mpath device
run _ceph_das_partitions
check "das partitions" "$(echo $out)" "/dev/sda1 /dev/sda2 /dev/sda3 /dev/sda4 /dev/nvme0n1p1 /dev/nvme0n1p3"
check "das partitions: one hex_sdk call" "$(grep -c '^hex_sdk' $CALLS)" 1

# meta partitions: one blkid, over DAS partitions only
run ceph_osd_list_meta_partitions
check "meta: rc" $rc 0
check "meta: partitions" "$out" "/dev/nvme0n1p1 /dev/sda1 /dev/sda2"
check "meta: one blkid, never bare" "$(grep '^blkid' $CALLS)" "blkid /dev/sda1 /dev/sda2 /dev/sda3 /dev/sda4 /dev/nvme0n1p1 /dev/nvme0n1p3"
check "meta: no FC/nbd probed" $(probed 'sdj|sdu|sdk|nbd|mapper') 0
HUNG=/dev/sda4 ; run ceph_osd_list_meta_partitions ; HUNG=""
check "meta hung: rc" $rc 1
check "meta hung: no partial list" "$out" ""
check "meta hung: logged" "$(grep -c 'did not return in 60s' $ERRS)" 1

# resolve: blkid over DAS partitions, then the scan over DAS candidates only
run ceph_osd_datapart_resolve d3
check "resolve raw: dev" "$rc $out" "0 /dev/sda3"
check "resolve raw: no FC probed" $(probed 'sdj|sdu|sdk|nbd|mapper') 0
run ceph_osd_datapart_resolve n3
check "resolve via scan: dev" "$rc $out" "0 /dev/nvme0n1p3"
check "resolve via scan: FC partitions skipped" $(probed 'sdj1|sdk1') 0
run ceph_osd_datapart_resolve lv1
check "resolve lvm" "$rc $out" "0 /dev/vg/osd-lv"
run ceph_osd_datapart_resolve gone
check "resolve gone" "$rc $out" "1 "

# a present udev link, confirmed on disk, needs no DAS listing and no other probe
LINKS="d3=/dev/sda3" ; run ceph_osd_datapart_resolve d3 ; LINKS=""
check "resolve via link" "$rc $out" "0 /dev/sda3"
check "resolve via link: no DAS listing" "$(grep -c 'lsblk -dpno' $CALLS)" 0
check "resolve via link: one probe" "$(grep -E '^(blkid|lvs) ' $CALLS)" "blkid -p -n ceph_bluestore -o value -s PART_ENTRY_UUID /dev/sda3"
# a stale link (the GPT there says otherwise) falls back to the DAS probe
LINKS="n3=/dev/sda4" ; run ceph_osd_datapart_resolve n3 ; LINKS=""
check "resolve stale link" "$rc $out" "0 /dev/nvme0n1p3"
LINKS="d3=/dev/sda3" ; HUNG=/dev/sda3 ; run ceph_osd_datapart_resolve d3 ; HUNG="" ; LINKS=""
check "resolve link hung" "$rc $out" "2 "
check "resolve link hung: not waited on again" "$(grep -cE '^(blkid|lvs) ' $CALLS)" 1

# a hung probe is "cannot tell" (2), never "gone" (1)
HUNG=PARTUUID=gone ; run ceph_osd_datapart_resolve gone ; HUNG=""
check "resolve blkid hung" "$rc $out" "2 "
HUNG=/dev/nvme0n1p3 ; run ceph_osd_datapart_resolve gone ; HUNG=""
check "resolve scan hung" "$rc $out" "2 "
HUNG=lv_uuid=gone ; run ceph_osd_datapart_resolve gone ; HUNG=""
check "resolve lvs hung" "$rc $out" "2 "
HUNG=PARTUUID=lv1 ; run ceph_osd_datapart_resolve lv1 ; HUNG=""
check "resolve hung but found elsewhere" "$rc $out" "0 /dev/vg/osd-lv"

# has_osd passes "cannot tell" through, so bootstrap does not mkfs over it
run ceph_osd_datapart_has_osd d3 o3
check "has_osd match" $rc 0
run ceph_osd_datapart_has_osd d3 other
check "has_osd other osd" $rc 1
run ceph_osd_datapart_has_osd gone o3
check "has_osd gone" $rc 1
HUNG=PARTUUID=gone ; run ceph_osd_datapart_has_osd gone o3 ; HUNG=""
check "has_osd resolve hung" $rc 2
HUNG=show-label ; run ceph_osd_datapart_has_osd d3 o3 ; HUNG=""
check "has_osd label hung" $rc 2
check "has_osd label hung: resolved first" $(probed 'show-label --dev /dev/sda3') 1

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: OSD partition probes stay on DAS and report hangs"; exit 0; } || exit 1
