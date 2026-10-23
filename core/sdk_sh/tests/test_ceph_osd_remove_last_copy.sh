#!/bin/bash
#
# Unit test for the last-copy guards in ../modules/sdk_ceph.sh:
# 1. ceph_osd_pgs_waiting_on names down/incomplete PGs whose peering waits on an OSD,
# 2. force removal refuses an OSD that is not ok-to-stop, or that a PG waits on once
#    stopped (and restarts it), and purges otherwise,
# 3. the safe-mode "no reported stats" shortcut does not purge an OSD a PG waits on,
# 4. remove_disk does not wipe the disk when an OSD on it was not removed.
#
# Self-contained: extracts only the functions and stubs ceph / hex_sdk.
# Run:  bash test_ceph_osd_remove_last_copy.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

for f in ceph_osd_pgs_waiting_on ceph_osd_force_remove ceph_osd_host_of ceph_osd_safe_remove ceph_osd_remove_disk ; do
    fn="$(awk -v f="$f()" '$0 == f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
LOG=$T/log

# --- stubs ---------------------------------------------------------------
OK_TO_STOP=1     # 1 = ceph osd ok-to-stop passes
UP=1             # osd.7 up in osd dump
BLOCKED=""       # pg ls incomplete reports 5.1 blocked_by these OSDs
WAITING=""       # pg query reports these OSDs in down_osds_we_would_probe for 5.9
ceph_stub() {
    echo "ceph $*" >> $LOG
    case "$*" in
        "osd ok-to-stop"*) [ $OK_TO_STOP = 1 ] ;;
        "osd dump -f json") echo "{\"osds\":[{\"osd\":7,\"up\":$UP},{\"osd\":8,\"up\":1}]}" ;;
        "pg ls down -f json") [ -n "$WAITING" ] && echo '{"pg_stats":[{"pgid":"5.9","blocked_by":[]}]}' || echo '{"pg_ready":true}' ;;
        "pg ls incomplete -f json") [ -n "$BLOCKED" ] && echo "{\"pg_stats\":[{\"pgid\":\"5.1\",\"blocked_by\":[$BLOCKED]}]}" || echo '{"pg_ready":true}' ;;
        "pg ls peering -f json") echo '{"pg_ready":true}' ;;
        "pg 5.9 query -f json") echo "{\"recovery_state\":[{\"name\":\"Started/Primary/Peering/Down\",\"down_osds_we_would_probe\":[$WAITING]}]}" ;;
        "osd ls-tree "*) echo 4 ; echo 5 ;;
        "osd df osd.7 -f json") echo '{"nodes":[{"id":7,"pgs":0}]}' ;;
        "-s -f json") echo '{"health":{"status":"HEALTH_WARN"}}' ;;
    esac
}
CEPH=ceph_stub
HEX_SDK=:
HOSTNAME=cube47
Quiet() { [ "${1:-}" = -n ] && shift; "$@" >/dev/null 2>&1; }
log_info() { echo "INFO $*" >> $LOG; }
log_error() { echo "ERROR $*" >> $LOG; }
Error() { echo "ERROR $*" >> $LOG; exit 1; }   # hex_sdk Error exits
remote_run() { shift; echo "remote $*" >> $LOG; }
ceph_get_host_by_id() { echo cube47; }
ceph_osd_purge() { echo "PURGE $1" >> $LOG; }
sleep() { :; }
timeout() { shift; "$@"; }
PrepareDataDisk() { echo "PREPARE $1" >> $LOG; }
HEX_CFG=echo
ceph_adjust_cache_flush_bytes() { :; }
readlink() { echo "$2"; }
ceph_osd_list_disk() { echo /dev/sdc; }
ceph_osd_get_ids() { echo 7; }
ceph_osd_zap_disk() { echo "ZAP $1" >> $LOG; }
ceph_osd_create_map() { :; }

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }
has() { grep -q -- "$1" $LOG; }
reset() { : > $LOG; OK_TO_STOP=1; UP=1; WAITING=""; BLOCKED=""; }

# 1. waiting PGs are named for the OSD they wait on only
reset; WAITING=7
[ "$(ceph_osd_pgs_waiting_on 7)" = 5.9 ] && ok || bad "5.9 not reported as waiting on osd.7"
[ -z "$(ceph_osd_pgs_waiting_on osd.8)" ] && ok || bad "5.9 reported as waiting on osd.8"
WAITING=""
[ -z "$(ceph_osd_pgs_waiting_on 7)" ] && ok || bad "a PG reported waiting with none down"
BLOCKED=7
[ "$(ceph_osd_pgs_waiting_on 7)" = 5.1 ] && ok || bad "incomplete PG blocked_by osd.7 not reported"

# 2. force: not ok-to-stop -> refuse before stopping anything
reset; OK_TO_STOP=0
ceph_osd_force_remove 7 && bad "force removal passed while not ok-to-stop" || ok
has "PURGE" && bad "purged while not ok-to-stop" || ok
has "systemctl stop" && bad "stopped while not ok-to-stop" || ok

# 3. force: a PG waits on the stopped OSD -> restart it, mark in, no purge
reset; WAITING=7
ceph_osd_force_remove 7 && bad "force removal passed with a PG waiting" || ok
has "PURGE" && bad "purged the last up-to-date copy" || ok
has "systemctl start ceph-osd@7" && ok || bad "stopped OSD not restarted"
has "ceph osd in 7" && ok || bad "OSD not marked in again"
has "5.9" && ok || bad "refusal does not name the PG"

# 4. force: healthy -> purge
reset
ceph_osd_force_remove 7 && ok || bad "force removal failed on a healthy cluster"
has "PURGE 7" && ok || bad "not purged on a healthy cluster"

# 5. force: dead OSD a PG waits on -> no purge, nothing to restart
reset; UP=0; WAITING=7
ceph_osd_force_remove 7 && bad "dead OSD purged while a PG waits on it" || ok
has "systemctl" && bad "touched the service of a dead OSD" || ok

# 5b. force: a disk's OSDs go as one unit; ids no longer in the osdmap are skipped
reset
ceph_osd_force_remove 7 8 9 && ok || bad "multi-OSD force removal failed on a healthy cluster"
has "ceph osd ok-to-stop 7 8" && ok || bad "ok-to-stop not checked for the disk's OSDs together"
has "PURGE 7" && has "PURGE 8" && ok || bad "not every OSD on the disk purged"
has "PURGE 9" && bad "purged an id that is not in the osdmap" || ok
reset; OK_TO_STOP=0
ceph_osd_force_remove 7 8 && bad "multi-OSD force removal passed while not ok-to-stop" || ok
has "systemctl stop" && bad "stopped an OSD before the joint ok-to-stop" || ok
reset; WAITING=7
ceph_osd_force_remove 7 8 && bad "multi-OSD force removal passed with a PG waiting" || ok
has "PURGE" && bad "purged part of a disk while a PG waits on it" || ok
has "systemctl start ceph-osd@7" && has "systemctl start ceph-osd@8" && ok || bad "not every stopped OSD restarted"

# 6. safe shortcut: no stats, down, 0 pgs, but a PG waits on it -> no purge
reset; UP=0; WAITING=7
_hex_function() { local -n _o=$1 _e=$2; _o=""; _e="Error EAGAIN: OSD(s) 7 have no reported stats"; return 1; }
ceph_osd_safe_remove 7 0.17 1 "" >/dev/null 2>&1
has "PURGE" && bad "safe shortcut purged an OSD a PG waits on" || ok
reset; UP=0
ceph_osd_safe_remove 7 0.17 1 "" >/dev/null 2>&1
has "PURGE 7" && ok || bad "safe shortcut no longer purges a dead empty OSD"

# 8. remove_disk force: OSD refused -> disk not wiped
reset; OK_TO_STOP=0
( ceph_osd_remove_disk /dev/sdc force )
has "ZAP" && bad "disk wiped although its OSD was not removed" || ok

echo "----"
echo "PASS=$pass FAIL=$fail"
[ $fail = 0 ] && echo "OK: ceph OSD last-copy guards" && exit 0
exit 1
