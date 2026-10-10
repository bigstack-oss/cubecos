#!/bin/bash
#
# Unit test for health_late_start_sweep in ../modules/sdk_health.sh: the boot-end
# catch-up for start steps the master's lone cold-boot commit left failed.
#
# Asserted: a stopped etcd-watch is started + re-synced only with full etcd quorum; a
# dashboard that does not answer is bounced via ceph_mgr_dashboard_ensure; nfs-ganesha
# is only reported; cinder-backup down in both samples is restarted on its host only
# once swift answers, and never when it recovered or swift stays down; a healthy
# cluster gets no action.
#
# Self-contained: extracts the functions under test and stubs everything external.
# Run:  bash test_health_late_start_sweep.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

for f in health_late_start_sweep _health_late_log _health_late_backup_down \
         _health_etcd_watch_scan _health_etcd_watch_repair ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

pass=0 fail=0
ok()    { pass=$((pass+1)); }
bad()   { fail=$((fail+1)); echo "FAIL: $1"; }
has()   { case "$1" in *"$2"*) ok ;; *) bad "$3: '$1'" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3: '$1'" ;; *) ok ;; esac; }

# ---- stubs -----------------------------------------------------------------------
ACTIONS=""
timeout() { shift ; "$@" ; }
sleep()   { : ; }
logger()  { : ; }
shared_id() { echo vip ; }
is_sshable() { [ "$1" != "unreach" ] ; }
remote_systemd_restart() { ACTIONS+="restart $1 $2;" ; }
HEX_SDK=hex_sdk_stub
hex_sdk_stub() { ACTIONS+="sdk $*;" ; }
SETTINGS_TXT=/dev/null

ETCDCTL=etcdctl_stub
etcdctl_stub() {
    case "$*" in
        "member list") seq 3 ;;
        "endpoint health --cluster") for _ in $(seq "$ETCD_HEALTHY") ; do echo "x is healthy" ; done ;;
        "get cluster. --prefix --keys-only -w json") echo '{"kvs":[{"mod_revision":10}]}' ;;
    esac
}

CEPH=ceph_stub
ceph_stub() { echo '{"active_name":"c1"}' ; }
curl() {
    case "$*" in
        *7442/ceph/*) [ "$DASH_OK" = 1 ] && echo "HTTP/1.1 200 OK" ;;
        *8890/info*)  echo -n "$SWIFT_CODE" ;;
    esac
}

# backup down hosts per sample: BACKUP1 first call, BACKUP2 after (calls run in
# subshells, so the count lives in a file)
CALLS=$(mktemp)
OPENSTACK=os_stub
os_stub() {
    echo x >> "$CALLS"
    local hosts=$BACKUP1 h out=""
    [ $(wc -l < "$CALLS") -gt 1 ] && hosts=$BACKUP2
    for h in $hosts ; do
        out+="${out:+,}{\"Binary\":\"cinder-backup\",\"Host\":\"$h\",\"Status\":\"enabled\",\"State\":\"down\"}"
    done
    out+="${out:+,}{\"Binary\":\"cinder-backup\",\"Host\":\"c3\",\"Status\":\"enabled\",\"State\":\"up\"}"
    echo "[$out]"
}

# cmd -v answers the watcher and ganesha probes; cmd -n records the repair
cmd() {
    local v=0 nodes="" opt OPTIND=1
    while getopts "cvn:" opt ; do
        case $opt in v) v=1 ;; n) nodes=$OPTARG ;; esac
    done
    shift $((OPTIND-1))
    if [ $v = 1 ] ; then
        case "$*" in
            *etcd-watch*) for n in c1 c2 ; do echo "$n|0|${WATCH[$n]} 10" ; done ;;
            *nfs-ganesha*) for n in c1 c2 ; do echo "$n|0|SubState=${GAN[$n]}" ; done ;;
        esac
    else
        ACTIONS+="cmd[$nodes] $*;"
    fi
}

T=$(mktemp) ; trap 'rm -f "$T" "$CALLS"' EXIT
run() { ACTIONS="" ; : > "$CALLS" ; health_late_start_sweep "${1:-600}" >"$T" 2>&1 ; RC=$? ; OUT=$(cat "$T") ; }
declare -A WATCH GAN

# ---- A: everything the cold boot left down ----------------------------------------
ETCD_HEALTHY=3 DASH_OK=0 SWIFT_CODE=200 BACKUP1="c1" BACKUP2="c1"
WATCH=([c1]=inactive [c2]=active) ; GAN=([c1]=dead [c2]=running)
run
has   "$ACTIONS" "cmd[c1] systemctl start etcd-watch ; cubectl tuning apply;" "watcher not started on c1"
hasnt "$ACTIONS" "cmd[c1 c2]" "healthy watcher touched"
has   "$ACTIONS" "sdk ceph_mgr_dashboard_ensure;" "dashboard not bounced"
has   "$ACTIONS" "restart c1 openstack-cinder-backup;" "cinder-backup not restarted"
hasnt "$ACTIONS" "nfs-ganesha" "ganesha must only be reported"
has   "$OUT" "nfs-ganesha not running on [c1]" "ganesha not reported"
[ $RC = 0 ] && ok || bad "A rc=$RC"

# ---- B: no quorum, swift 503 -> no watcher repair, no backup restart ---------------
ETCD_HEALTHY=2 DASH_OK=1 SWIFT_CODE=503 BACKUP1="c1" BACKUP2="c1"
run 0
hasnt "$ACTIONS" "etcd-watch" "watcher repaired without quorum"
hasnt "$ACTIONS" "ceph_mgr_dashboard_ensure" "serving dashboard bounced"
hasnt "$ACTIONS" "restart" "backup restarted while swift is down"
has   "$OUT" "not answering" "swift wait not logged"
[ $RC = 1 ] && ok || bad "B rc=$RC"

# ---- C: backup recovered between samples -> no restart ---------------------------
ETCD_HEALTHY=3 SWIFT_CODE=200 BACKUP1="c1" BACKUP2=""
WATCH=([c1]=active [c2]=active) ; GAN=([c1]=running [c2]=running)
run
hasnt "$ACTIONS" "restart" "recovered backup restarted"
has   "$OUT" "recovered on its own" "recovery not logged"

# ---- D: healthy cluster -> no action ---------------------------------------------
BACKUP1="" BACKUP2=""
run
[ -z "$ACTIONS" ] && ok || bad "healthy cluster got actions: $ACTIONS"
has "$OUT" "cinder-backup ok" "healthy summary missing"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_late_start_sweep"; exit 0; } || exit 1
