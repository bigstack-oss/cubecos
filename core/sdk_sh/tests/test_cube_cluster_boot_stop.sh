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
for f in cube_cluster_stop _cube_stop_vms _cube_stop_keep ; do eval "$(extract "$DIR/../../main/proj_functions" $f)" ; done
type cube_cluster_boot_stop >/dev/null 2>&1 || { echo "FAIL: cube_cluster_boot_stop not extracted"; exit 1; }
type ceph_hold_data_movement >/dev/null 2>&1 || { echo "FAIL: ceph_hold_data_movement not extracted"; exit 1; }

LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- mocks
QUORUM=1
cubectl(){ echo '[{"hostname":"c1","ip":{"management":"10.0.0.1"}},{"hostname":"c2","ip":{"management":"10.0.0.2"}},{"hostname":"c3","ip":{"management":"10.0.0.3"}}]'; }
UNREACHABLE=""
is_sshable(){ [ "$1" != "$UNREACHABLE" ]; }
ssh(){ echo "ssh $*" >> "$LOG"; }
Quiet(){ echo "quiet $*" >> "$LOG"; "$@"; }
_cephmock(){ echo "ceph $*" >> "$LOG"; [ "$1" = "-s" ] && return $((1-QUORUM)); return 0; }
CEPH=_cephmock
HEX_SDK=_sdkmock
_sdkmock(){ echo "hex_sdk $*" >> "$LOG"; case "$1" in ceph_hold_data_movement) ceph_hold_data_movement ;; esac; }

cube_cluster_boot_stop
chk "stops every control node, last first" \
    "$(grep '^ssh' "$LOG" | tr '\n' '|')" \
    "ssh root@10.0.0.3 _sdkmock cube_cluster_stop boot|ssh root@10.0.0.2 _sdkmock cube_cluster_stop boot|ssh root@10.0.0.1 _sdkmock cube_cluster_stop boot|"
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
chk "sweep still runs without quorum" "$(grep -c '^ssh' "$LOG")" "3"
chk "no osd set without quorum" "$(grep -c '^ceph osd set' "$LOG")" "0"

# --- an unreachable peer (is_sshable fails) is skipped; the sweep and the hold go on
: > "$LOG"; QUORUM=1; UNREACHABLE=10.0.0.2
(cube_cluster_boot_stop); rc=$?
chk "unreachable peer: others swept" "$(grep '^ssh' "$LOG" | cut -d' ' -f2 | tr '\n' '|')" "root@10.0.0.3|root@10.0.0.1|"
chk "unreachable peer: still holds flags" "$(grep -c '^ceph osd set' "$LOG")" "4"
chk "unreachable peer: returns 0" "$rc" "0"

# --- a peer whose remote stop fails does not abort either
: > "$LOG"; UNREACHABLE=""
ssh(){ echo "ssh $*" >> "$LOG"; [ "$1" = "root@10.0.0.2" ] && return 255; return 0; }
(cube_cluster_boot_stop); rc=$?
chk "failing remote stop: sweep continues" "$(grep -c '^ssh' "$LOG")" "3"
chk "failing remote stop: returns 0" "$rc" "0"

# --- cube_cluster_stop: boot mode stops only this host's VMs, keeps live state
HOSTNAME=c3
_osmock(){ echo "openstack $*" >> "$LOG"; case "$1 $2" in "server list") [ -n "$VMS_DONE" ] || echo vm-local ;; esac; }
OPENSTACK=_osmock
_sdkmock(){ [ "$1" = os_nova_list ] && [ -z "$VMS_DONE" ] && printf 'vm-a ACTIVE Running\nvm-b ACTIVE Running\n'; return 0; }
HEX_SDK=_sdkmock
VMS_DONE=""
sleep(){ VMS_DONE=1; }
ACTIVE_SVCS=""
systemctl(){ [[ " $ACTIVE_SVCS " == *" $3 "* ]]; }
logger(){ echo "logger $*" >> "$LOG"; }
rm(){ echo "rm $*" >> "$LOG"; }
touch(){ echo "touch $*" >> "$LOG"; }
os_nova_instance_reset(){ :; }

: > "$LOG"; VMS_DONE=""
cube_cluster_stop
chk "operator stop: every VM cluster-wide" "$(grep -c 'openstack server stop' "$LOG")" "2"
chk "operator stop: arms galera rebuild" "$(grep -c 'touch /etc/appliance/state/mysql_new_cluster' "$LOG")" "1"

# cube4510: healthy peer swept at boot, its services running
: > "$LOG"; VMS_DONE=""; ACTIVE_SVCS="corosync rabbitmq-server mariadb"
cube_cluster_stop boot
chk "boot stop: every list is host-filtered" "$(grep "server list" "$LOG" | grep -vc -- "--host c3")" "0"
chk "boot stop: stops local VMs only" "$(grep 'openstack server stop' "$LOG" | tr '\n' '|')" "openstack server stop vm-local|"
chk "boot stop, live: galera not armed" "$(grep -c 'mysql_new_cluster' "$LOG")" "0"
chk "boot stop, live: mnesia kept" "$(grep -c 'mnesia' "$LOG")" "0"
chk "boot stop, live: corosync kept" "$(grep -c "^rm .*corosync" "$LOG")" "0"
chk "boot stop, live: no rm" "$(grep -c '^rm ' "$LOG")" "0"

# real cold boot: services down, state reset as before
: > "$LOG"; VMS_DONE=1; ACTIVE_SVCS=""
cube_cluster_stop boot
chk "boot stop, cold: resets state" "$(grep -c -e '^rm ' -e '^touch ' "$LOG")" "4"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
