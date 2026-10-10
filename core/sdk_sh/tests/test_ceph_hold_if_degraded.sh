#!/bin/bash
#
# Unit test for ceph_hold_if_degraded and ceph_hold_data_movement
# (../modules/sdk_ceph.sh): the master's boot commit holds data movement only
# while storage is degraded, never sets pause/nodown, no ceph without quorum.
# Self-contained, mocks everything. Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
for f in ceph_storage_degraded ceph_hold_data_movement ceph_hold_if_degraded ; do
    eval "$(extract "$DIR/../modules/sdk_ceph.sh" $f)"
    type $f >/dev/null 2>&1 || { echo "FAIL: $f not extracted"; exit 1; }
done

LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- mocks
QUORUM=1 UP=12 IN=12 PGSTATE=active+clean
_cephmock(){
    echo "ceph $*" >> "$LOG"
    [ "$QUORUM" = 1 ] || return 1
    case "$1" in
        status) echo "{\"osdmap\":{\"num_up_osds\":$UP,\"num_in_osds\":$IN},\"pgmap\":{\"pgs_by_state\":[{\"state_name\":\"$PGSTATE\",\"count\":8}]}}" ;;
    esac
    return 0
}
CEPH=_cephmock
Quiet(){ "$@"; }
log_info(){ :; }
osdset(){ grep '^ceph osd set' "$LOG" | tr '\n' '|'; }

# --- healthy: nothing held
ceph_hold_if_degraded
chk "healthy: no flags" "$(osdset)" ""

# --- OSDs down: hold the 4 data-movement flags
: > "$LOG"; UP=8
ceph_hold_if_degraded
chk "osds down: holds data movement" "$(osdset)" \
    "ceph osd set noout|ceph osd set norecover|ceph osd set norebalance|ceph osd set nobackfill|"
chk "never sets pause" "$(grep -c 'osd set pause' "$LOG")" "0"
chk "never sets nodown" "$(grep -c 'osd set nodown' "$LOG")" "0"

# --- PGs inactive with all OSDs up: hold
: > "$LOG"; UP=12 PGSTATE=peering
ceph_hold_if_degraded
chk "pgs inactive: holds" "$(grep -c '^ceph osd set' "$LOG")" "4"

# --- no quorum: ceph status fails -> not degraded, no osd set, rc 0
: > "$LOG"; QUORUM=0 UP=8
ceph_hold_if_degraded; rc=$?
chk "no quorum: no osd set" "$(grep -c '^ceph osd set' "$LOG")" "0"
chk "no quorum: rc 0" "$rc" "0"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
