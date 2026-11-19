#!/bin/bash
#
# Unit test for ceph_osd_remount() in ../modules/sdk_ceph.sh. With
# --stopped-only (refresh_ceph_osd, i.e. add_disk) a running OSD is never
# compacted, stopped, unmounted or remounted; a stopped one is remounted and,
# with --no-start, left for the caller to start. Without it (restart_ceph_osd,
# boot) every OSD is stopped and remounted as before.
#
# Self-contained: extracts only the function and stubs systemctl / mount / ceph.
# Run:  bash test_ceph_osd_remount_stopped_only.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"

fn="$(awk '$0 == "ceph_osd_remount()"{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: ceph_osd_remount not found in $SRC"; exit 1; }
eval "$fn"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
OPS=$T/ops
CEPH_OSD_MAP=$T/dev_osd.map
printf '%s\n' "/dev/sdb1 1 m1 d1" "/dev/sdc1 2 m2 d2" > $CEPH_OSD_MAP

# --- stubs ---------------------------------------------------------------
RUNNING=" 1 "               # ids whose ceph-osd@ unit is active
find() { echo /var/lib/ceph/osd/ceph-1 /var/lib/ceph/osd/ceph-2; }
systemctl() {
    case "$1" in
        is-active) local id=${2#ceph-osd@}; [[ "$RUNNING" == *" $id "* ]] ;;
        *) echo "systemctl $*" >> $OPS ;;
    esac
}
CEPH=ceph_stub
ceph_stub() { echo "ceph $*" >> $OPS; }
ceph-volume() { echo '{}'; }
umount() { echo "umount $*" >> $OPS; }
mount() { echo "mount $*" >> $OPS; }
mkdir() { :; }; chmod() { :; }; chown() { :; }; udevadm() { :; }; unlink() { :; }; ln() { :; }
readlink() { local p=${!#}; p=${p%/block}; echo "/dev/disk/by-partuuid/d${p##*ceph-}"; }
Quiet() { [ "$1" != "-n" ] || shift; "$@" >/dev/null 2>&1; }
command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $*"; }

# 1. --no-start --stopped-only: osd.1 runs, osd.2 is stopped
: > $OPS
ceph_osd_remount --no-start --stopped-only
grep -q "ceph-osd@1\|ceph-1\|osd.1 " $OPS && bad "running osd.1 was touched: $(cat $OPS)" || ok
grep -q "umount /var/lib/ceph/osd/ceph-2" $OPS && ok || bad "stopped osd.2 not unmounted"
grep -q "mount /dev/sdc1 /var/lib/ceph/osd/ceph-2" $OPS && ok || bad "stopped osd.2 not remounted"
grep -q "systemctl start" $OPS && bad "--no-start still started an OSD" || ok

# 2. no flags: every OSD stopped, remounted and started (restart_ceph_osd)
: > $OPS
ceph_osd_remount
grep -q "systemctl stop ceph-osd@1" $OPS && ok || bad "running osd.1 not stopped without --stopped-only"
grep -q "mount /dev/sdb1 /var/lib/ceph/osd/ceph-1" $OPS && ok || bad "osd.1 not remounted without --stopped-only"
grep -q "start ceph-osd@1" $OPS && grep -q "start ceph-osd@2" $OPS && ok || bad "OSDs not started without --no-start"

# 3. --no-start alone (boot commit): every OSD remounted, none started
: > $OPS
ceph_osd_remount --no-start
grep -q "systemctl stop ceph-osd@1" $OPS && ok || bad "boot remount did not stop osd.1"
grep -q "systemctl start" $OPS && bad "--no-start started an OSD" || ok

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ceph_osd_remount --stopped-only"; exit 0; } || exit 1
