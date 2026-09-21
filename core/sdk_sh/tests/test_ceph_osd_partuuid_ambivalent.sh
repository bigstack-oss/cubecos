#!/bin/bash
#
# Unit test for ceph_osd_partuuid_of(), ceph_osd_datapart_scan() and
# ceph_osd_datapart_resolve() in ../modules/sdk_ceph.sh -- resolving a raw
# OSD's data partition when libblkid calls it "ambivalent" (object data that
# looks like a second filesystem), so plain blkid and udev report nothing for
# it while the GPT entry is still readable with a type-filtered probe
# (cubecos#1284).
#
# Self-contained: extracts only the three functions and stubs blkid / lsblk /
# lvs. Run:  bash test_ceph_osd_partuuid_ambivalent.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"

for f in ceph_osd_partuuid_of ceph_osd_datapart_scan ceph_osd_datapart_resolve ; do
    fn="$(awk -v f="$f" '$0 == f"()"{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
GOOD=$T/sda3     # healthy partition: plain blkid knows it
BAD=$T/sda4      # ambivalent partition: only the filtered probe works
DEAD=$T/sdz9     # partition that resolves nowhere
touch $GOOD $BAD $DEAD
GOOD_UUID=6dbdfce0-19af-4b1d-9837-e80c8d23824f
BAD_UUID=46c51906-b3a5-4fe3-9003-847f8eac59cd
LV_UUID=abcdef01-2345-6789-abcd-ef0123456789
CALLS=$T/calls

# blkid stub: models the real behaviour on the sky142 incident node; a plain
# `blkid -o value -s PARTUUID` is unexpected (it is what fails there)
blkid() {
    echo "blkid $*" >> $CALLS
    case "$*" in
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID $GOOD") echo $GOOD_UUID ;;
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID $BAD")  echo $BAD_UUID ;;
        "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID $DEAD") return 2 ;;
        "-o device --match-token PARTUUID=$GOOD_UUID") echo $GOOD ;;
        "-o device --match-token PARTUUID="*)          return 2 ;;      # cache never sees the bad one
        *) echo "unexpected blkid $*" >&2; return 99 ;;
    esac
}
# udev view: the ambivalent partition and the dead one have no PARTUUID
lsblk() {
    echo "lsblk $*" >> $CALLS
    printf '%s part %s\n%s part \n%s part \n%s disk \n' $GOOD $GOOD_UUID $BAD $DEAD $T/sda
}
lvs() {
    echo "lvs $*" >> $CALLS
    case "$*" in *"lv_uuid=$LV_UUID"*) echo "  /dev/vg/osd-lv" ;; esac
}

pass=0 fail=0
# assert <name> <want-rc> <want-out> <cmd...>
assert() {
    local name=$1 wrc=$2 wout=$3; shift 3
    local out rc
    out=$("$@" 2>/dev/null); rc=$?
    if [ "$rc" = "$wrc" ] && [ "$out" = "$wout" ]; then pass=$((pass+1))
    else fail=$((fail+1)); echo "FAIL: $name -> rc=$rc out='$out' (want rc=$wrc out='$wout')"; fi
}
called() { grep -qF -- "$1" $CALLS; }

# ceph_osd_partuuid_of
: > $CALLS
assert "partuuid_of healthy"     0 "$GOOD_UUID" ceph_osd_partuuid_of $GOOD
assert "partuuid_of ambivalent"  0 "$BAD_UUID"  ceph_osd_partuuid_of $BAD
if called "-p -n ceph_bluestore -o value -s PART_ENTRY_UUID $BAD"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: ambivalent partition must use the filtered probe"; fi
assert "partuuid_of unreadable"  1 ""           ceph_osd_partuuid_of $DEAD
assert "partuuid_of missing dev" 1 ""           ceph_osd_partuuid_of $T/nope
assert "partuuid_of empty arg"   1 ""           ceph_osd_partuuid_of ""

# ceph_osd_datapart_scan: probes only partitions udev has no PARTUUID for
: > $CALLS
assert "scan finds ambivalent"   0 "$BAD"       ceph_osd_datapart_scan $BAD_UUID
if called "PARTUUID $GOOD"; then fail=$((fail+1)); echo "FAIL: scan must skip partitions udev already identifies"; else pass=$((pass+1)); fi
assert "scan no match"           1 ""           ceph_osd_datapart_scan 00000000-0000-0000-0000-000000000000

# ceph_osd_datapart_resolve: blkid cache, then disk scan, then LVM, then give up
: > $CALLS
assert "resolve healthy"         0 "$GOOD"      ceph_osd_datapart_resolve $GOOD_UUID
if called "lsblk"; then fail=$((fail+1)); echo "FAIL: healthy uuid should resolve from the cache without a scan"; else pass=$((pass+1)); fi
assert "resolve ambivalent"      0 "$BAD"       ceph_osd_datapart_resolve $BAD_UUID
assert "resolve lvm"             0 "/dev/vg/osd-lv" ceph_osd_datapart_resolve $LV_UUID
assert "resolve gone"            1 ""           ceph_osd_datapart_resolve 00000000-0000-0000-0000-000000000000
assert "resolve empty"           1 ""           ceph_osd_datapart_resolve ""

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ceph_osd_partuuid_of / datapart_scan / datapart_resolve"; exit 0; } || exit 1
