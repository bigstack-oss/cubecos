#!/bin/bash
#
# Unit test for ceph_mount_cephfs --defer and ceph_cephfs_deferred_bringup
# (../modules/sdk_ceph.sh): a boot-pass mount gives up early while OSDs are down
# or PGs inactive, and the deferred bringup finishes it later. Self-contained,
# mocks everything. Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
for f in ceph_storage_degraded ceph_mount_cephfs ceph_cephfs_deferred_bringup ; do
    eval "$(extract "$DIR/../modules/sdk_ceph.sh" $f)"
    type $f >/dev/null 2>&1 || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LOG=$TMP/log
CEPHFS_STORE_DIR=$TMP/cephfs
CEPHFS_DEFERRED_MARKER=$TMP/deferred
CEPHFS_DEFER_GRACE=60
SRVSTO=10
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- mocks
UP=12 IN=12 PGSTATE=active+clean MDS=up:active MOUNT_OK=1 MOUNTED=0 GRACE_OK=1
_cephmock(){
    case "$1" in
        -s) return 0 ;;
        status) echo "{\"osdmap\":{\"num_up_osds\":$UP,\"num_in_osds\":$IN},\"pgmap\":{\"pgs_by_state\":[{\"state_name\":\"$PGSTATE\",\"count\":8}]}}" ;;
        mds) echo "cephfs:1 {0=c1=$MDS}" ;;
    esac
}
CEPH=_cephmock
sleep(){ SECONDS=$((SECONDS + $1)); }
mountpoint(){ [ "$MOUNTED" = 1 ]; }
timeout(){ shift; echo "$*" >> "$LOG"; [ "$1" = mount ] && [ "$MOUNT_OK" = 1 ] && MOUNTED=1; return 0; }
ceph-authtool(){ :; }
hostname(){ echo c1; }
log_info(){ :; }
log_warning(){ echo "warning $*" >> "$LOG"; }
log_error(){ echo "error $*" >> "$LOG"; }
Quiet(){ [ "$1" = -n ] && shift; echo "$*" >> "$LOG"; }
ceph_ganesha_grace_join(){ echo "grace_join" >> "$LOG"; [ "$GRACE_OK" = 1 ]; }

reset(){ : > "$LOG"; rm -f "$CEPHFS_DEFERRED_MARKER"; MOUNTED=0; SECONDS=0; }

# --- cold boot: peer OSDs down, mds not active -> defer after the grace
reset; UP=4 MDS=up:replay
ceph_mount_cephfs --defer; rc=$?
chk "degraded: defers (rc 2)" "$rc" "2"
chk "degraded: marker set" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" "y"
chk "degraded: no mount attempted" "$(grep -c '^mount' "$LOG")" "0"
chk "degraded: gives up after the grace, not 300s" "$([ $SECONDS -le 70 ] && echo y)" "y"

# --- inactive PGs alone also defer
reset; UP=12 PGSTATE=peering MDS=up:replay
ceph_mount_cephfs --defer; chk "inactive PGs: defers" "$?" "2"

# --- active-but-degraded PGs are serviceable: no deferral
reset; PGSTATE=active+undersized+degraded MDS=up:active
ceph_mount_cephfs --defer; chk "active+degraded PGs: mounts" "$?" "0"
chk "active+degraded PGs: no marker" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" ""

# --- healthy storage, mds slow: keep the full wait (no deferral)
reset; PGSTATE=active+clean MDS=up:replay MOUNT_OK=0
ceph_mount_cephfs --defer; rc=$?
chk "healthy, mds slow: not deferred" "$rc" "1"
chk "healthy, mds slow: full wait + 6 mounts" "$(grep -c '^mount' "$LOG")" "6"
chk "healthy, mds slow: no marker" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" ""

# --- without --defer (first-time setup, check_repair): unchanged
reset; UP=4 MDS=up:replay MOUNT_OK=0
ceph_mount_cephfs; rc=$?
chk "no --defer: old failure path" "$rc" "1"
chk "no --defer: 6 mounts" "$(grep -c '^mount' "$LOG")" "6"
chk "no --defer: waited 300s" "$([ $SECONDS -ge 300 ] && echo y)" "y"
chk "no --defer: no marker" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" ""

# --- bringup without marker: no-op
reset; UP=12 MDS=up:active MOUNT_OK=1
ceph_cephfs_deferred_bringup; rc=$?
chk "bringup no marker: rc 0" "$rc" "0"
chk "bringup no marker: touches nothing" "$(wc -l < "$LOG")" "0"

# --- bringup with marker: mount, then dependents, marker cleared
reset; touch "$CEPHFS_DEFERRED_MARKER"
ceph_cephfs_deferred_bringup; rc=$?
chk "bringup: rc 0" "$rc" "0"
chk "bringup: marker cleared" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" ""
chk "bringup: mount, umountfs, grace, ganesha in order" \
    "$(grep -E '^mount|ceph-umountfs|grace_join|nfs-ganesha' "$LOG" | awk '{print $1, $NF}' | tr '\n' '|')" \
    "mount name=admin,secretfile=/etc/ceph/admin.key,recover_session=clean|systemctl ceph-umountfs|grace_join grace_join|systemctl nfs-ganesha|"

# --- bringup when the mount still fails: keep the marker, no ganesha
reset; touch "$CEPHFS_DEFERRED_MARKER"; MOUNT_OK=0
ceph_cephfs_deferred_bringup; rc=$?
chk "bringup mount fails: rc 1" "$rc" "1"
chk "bringup mount fails: marker kept" "$([ -e "$CEPHFS_DEFERRED_MARKER" ] && echo y)" "y"
chk "bringup mount fails: no ganesha" "$(grep -c nfs-ganesha "$LOG")" "0"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
