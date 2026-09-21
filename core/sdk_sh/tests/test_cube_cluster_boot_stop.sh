#!/bin/bash
#
# Unit test for cube_cluster_boot_stop (../../main/proj_functions) and
# ceph_hold_data_movement (../modules/sdk_ceph.sh): sweep every control node
# last-first, hold data movement, never set pause/nodown, no ceph without
# quorum. Self-contained, mocks everything. Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
eval "$(extract "$DIR/../../main/proj_functions" cube_cluster_boot_stop)"
eval "$(extract "$DIR/../modules/sdk_ceph.sh" ceph_hold_data_movement)"
type cube_cluster_boot_stop >/dev/null 2>&1 || { echo "FAIL: cube_cluster_boot_stop not extracted"; exit 1; }
type ceph_hold_data_movement >/dev/null 2>&1 || { echo "FAIL: ceph_hold_data_movement not extracted"; exit 1; }

LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- mocks
QUORUM=1
cubectl(){ echo '[{"hostname":"c1","ip":{"management":"10.0.0.1"}},{"hostname":"c2","ip":{"management":"10.0.0.2"}},{"hostname":"c3","ip":{"management":"10.0.0.3"}}]'; }
remote_run(){ echo "remote_run $*" >> "$LOG"; }
Quiet(){ echo "quiet $*" >> "$LOG"; "$@"; }
_cephmock(){ echo "ceph $*" >> "$LOG"; [ "$1" = "-s" ] && return $((1-QUORUM)); return 0; }
CEPH=_cephmock
HEX_SDK=_sdkmock
_sdkmock(){ echo "hex_sdk $*" >> "$LOG"; case "$1" in ceph_hold_data_movement) ceph_hold_data_movement ;; esac; }

cube_cluster_boot_stop
chk "stops every control node, last first" \
    "$(grep '^remote_run' "$LOG" | tr '\n' '|')" \
    "remote_run 10.0.0.3 _sdkmock cube_cluster_stop|remote_run 10.0.0.2 _sdkmock cube_cluster_stop|remote_run 10.0.0.1 _sdkmock cube_cluster_stop|"
chk "holds data movement (4 flags)" \
    "$(grep '^ceph osd set' "$LOG" | tr '\n' '|')" \
    "ceph osd set noout|ceph osd set norecover|ceph osd set norebalance|ceph osd set nobackfill|"
chk "never sets pause" "$(grep -c 'osd set pause' "$LOG")" "0"
chk "never sets nodown" "$(grep -c 'osd set nodown' "$LOG")" "0"
chk "no osd compact at boot" "$(grep -c 'compact' "$LOG")" "0"
chk "flags go through hex_sdk (cross-module)" "$(grep -c '^hex_sdk ceph_hold_data_movement' "$LOG")" "1"

# --- no quorum (master booting first, mons down): nodes still swept, ceph untouched
: > "$LOG"; QUORUM=0
cube_cluster_boot_stop
chk "sweep still runs without quorum" "$(grep -c '^remote_run' "$LOG")" "3"
chk "no osd set without quorum" "$(grep -c '^ceph osd set' "$LOG")" "0"

# --- an unreachable peer must not abort the sweep
: > "$LOG"; QUORUM=1
remote_run(){ echo "remote_run $*" >> "$LOG"; [ "$1" = "10.0.0.2" ] && return 255; return 0; }
cube_cluster_boot_stop; rc=$?
chk "unreachable peer: sweep continues" "$(grep -c '^remote_run' "$LOG")" "3"
chk "unreachable peer: still holds flags" "$(grep -c '^ceph osd set' "$LOG")" "4"
chk "unreachable peer: returns 0" "$rc" "0"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
