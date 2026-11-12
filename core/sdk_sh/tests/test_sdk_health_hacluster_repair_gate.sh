#!/bin/bash
#
# Unit test for the hacluster auto-repair gate in ../modules/sdk_health.sh, covering
# #2325: the repair restarts the node's own Pacemaker, and it ran on the first NG,
# while a compute was still booting, and when an ssh probe failed. masakari then
# put the healthy control node into maintenance with instance-HA off.
#
# Self-contained: extracts _health_fail_log, _health_remote_stopped,
# health_hacluster_check and _health_hacluster_auto_repair, points their files at
# a temp dir, stubs pcs / cubectl / the probes, and puts a fake ssh on PATH (run
# through the real timeout) for the boot check. health_hacluster_repair is a stub
# that only records the call.
#
# The last section is a negative control against 02cf633a, before the fix. It is
# skipped when that git object is not available.
#
#   Run: bash test_sdk_health_hacluster_repair_gate.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/log" "$T/tmp" "$T/run" "$T/state" "$T/etc"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

load() { # load <file> <function>...: the files these functions use are moved under $T
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src" | sed -e "s#/var/log/health_#$T/log/health_#g" \
            -e "s#/tmp/health_#$T/tmp/health_#g" -e "s#/run/health_#$T/run/health_#g" \
            -e "s#/etc/alert.level#$T/etc/alert.level#g" \
            -e "s#/etc/appliance/state/cube_repair_optout#$T/optout#g" \
            -e "s#/run/ec2.key#$T/run/ec2.key#g" -e "s#/tmp/\\\$#$T/tmp/\\\$#g")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}
load "$SRC" _health_repair_due _health_fail_log _health_remote_stopped health_hacluster_check _health_hacluster_auto_repair

# fake ssh for the boot check: exits with the code in $T/boot.<host> (0 = booted)
cat > "$T/bin/ssh" <<'EOF'
#!/bin/bash
for a ; do case $a in root@*) h=${a#root@} ;; esac ; done
exit "$(cat "$GATE_T/boot.$h" 2>/dev/null || echo 0)"
EOF
chmod +x "$T/bin/ssh"
export GATE_T=$T PATH="$T/bin:$PATH"

VERBOSE=0 ERR_LOGSIZE=200 SRVSTO=1 HEX_STATE_DIR=$T/state OPENSTACK=false HEX_SDK=false
cmd() { :; }
runtime=$T/runtime CLUSTER_REPAIRING=$T/repairing
_HEALTH_PROBE_RETRY_WAIT=0
CUBE_BOOT_DONE_TEST=true
Quiet() { [ "$1" = "-n" ] && shift; "$@" >/dev/null 2>&1; }
health_errcode_lookup() { echo "desc $2"; }
influx_event() { :; }
cube_cluster_ready() { return 0; }
is_cluster_rolling() { return 1; }
remote_run() { return 0; }
health_hacluster_repair() { echo x >> "$T/repairs"; }

CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
CUBE_NODE_COMPUTE_HOSTNAMES=(cc1 cc2 cc3 p4 p5)
pcs() { printf '  * Online: [ cc1 cc2 cc3 ]\n  * RemoteOnline: [ p4 p5 ]\n'; }
cubectl() { printf 'p4,10.0.0.4,compute\np5,10.0.0.5,compute\n'; }

# probe answers: $T/probe.<node>.<service> holds exit codes, one per call (last one
# repeats); no file = running
PROBES=0
is_remote_running() {
    local f=$T/probe.$1.$2 r=0
    PROBES=$((PROBES+1))
    [ -f "$f" ] || return 0
    r=$(head -1 "$f")
    [ "$(wc -l < "$f")" -le 1 ] || sed -i.bak 1d "$f"
    return "$r"
}

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

reset() { rm -f "$T"/probe.* "$T"/boot.* "$T"/repairs "$T"/tmp/* "$T"/log/* "$T"/etc/* ; unset _OVERRIDE_MAX_ERR; }
probe() { local k=$1 ; shift ; printf '%s\n' "$@" > "$T/probe.$k"; } # probe <node>.<service> <code>...
repairs() { [ -f "$T/repairs" ] && wc -l < "$T/repairs" | tr -d ' ' || echo 0; }
round() { ERR_CODE=0 ERR_MSG="" ERR_LOG="" ; health_hacluster_check >/dev/null 2>&1; }

# ---- 1. a stopped corosync: no repair on the first NG, repair on the second ----
reset
probe cc3.corosync 1
round; ck "$ERR_CODE" 1 "stopped corosync is an NG"
ck "$(repairs)" 0 "first NG: no repair"
ck "$(grep -c 'waits for 2 failed checks in a row' "$T/log/health_hacluster_error.log")" 1 "first NG: the wait is logged"
round; ck "$(repairs)" 1 "second NG in a row: repair"
round; ck "$(repairs)" 2 "third NG in a row: repair (below maxerr)"

# ---- 2. a pass in between resets the confirmation ----
reset
probe cc3.corosync 1
round; rm -f "$T/probe.cc3.corosync"; round; ck "$ERR_CODE" 0 "probe recovered: pass"
probe cc3.corosync 1
round; ck "$(repairs)" 0 "NG, pass, NG: no repair"

# ---- 3. a failed ssh probe is not a stopped service ----
reset
probe cc3.corosync 255
round; ck "$ERR_CODE" 0 "ssh 255 on every try: no NG"
round; ck "$(repairs)" 0 "ssh 255 twice in a row: no repair"
reset
probe cc3.corosync 124
round; ck "$ERR_CODE" 0 "ssh timeout on every try: no NG"
reset
probe cc3.corosync 255 1
round; ck "$ERR_CODE" 1 "ssh fails, then the retry says stopped: NG"
reset
probe p5.pcsd 255
round; ck "$ERR_CODE" 0 "compute probe ssh 255: no NG"

# ---- 4. _health_remote_stopped return values and retries ----
reset; PROBES=0
_health_remote_stopped cc3 corosync; ck "$?" 1 "running -> 1"
ck "$PROBES" 1 "running: one probe"
probe cc3.corosync 1; PROBES=0
_health_remote_stopped cc3 corosync; ck "$?" 0 "stopped -> 0"
ck "$PROBES" 1 "stopped: one probe, no retry"
probe cc3.corosync 255 0; PROBES=0
_health_remote_stopped cc3 corosync; ck "$?" 1 "ssh fails, retry says running -> 1"
ck "$PROBES" 2 "ssh fails: one retry"
probe cc3.corosync 255 255; PROBES=0
_health_remote_stopped cc3 corosync; ck "$?" 2 "ssh fails twice -> 2 (unknown)"
ck "$PROBES" 2 "ssh fails twice: two probes, no more"

# ---- 5. a compute still booting holds the repair; a down one does not ----
reset
probe cc3.corosync 1
echo 1 > "$T/boot.p5"
round; round; ck "$(repairs)" 0 "p5 booting: no repair on the second NG"
ck "$(grep -c 'p5 is still booting' "$T/log/health_hacluster_error.log")" 1 "p5 booting: the skip is logged"
echo 255 > "$T/boot.p5"
round; ck "$(repairs)" 1 "p5 down (ssh 255): repair"
echo 0 > "$T/boot.p5"
round; ck "$(repairs)" 2 "p5 booted: repair"

# ---- 6. maxerr 1 (cluster check, or cubesys.alert.level 1): repair on the second NG ----
reset
probe cc3.corosync 1
export _OVERRIDE_MAX_ERR=1
round; ck "$(repairs)" 0 "maxerr 1, first NG: no repair"
round; ck "$(repairs)" 1 "maxerr 1, second NG: repair"
round; ck "$(repairs)" 1 "maxerr 1, third NG: backoff"
unset _OVERRIDE_MAX_ERR

# ---- 7. other services keep repairing on the first NG ----
reset
health_foo_check() { ERR_CODE=1 ERR_MSG="" ERR_LOG="" ; _health_fail_log ; }
_health_foo_auto_repair() { echo x >> "$T/repairs"; }
health_foo_check >/dev/null 2>&1
ck "$(repairs)" 1 "other service: repair on the first NG"

# ---- 8. negative control: before the fix, the first NG and a failed probe repaired ----
BASE_SRC=$T/base.sh
BASE_REF=02cf633a
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" _health_repair_due _health_fail_log health_hacluster_check _health_hacluster_auto_repair
    reset
    probe cc3.corosync 1
    round; ck "$(repairs)" 1 "negative control: unfixed code repairs on the first NG"
    reset
    probe cc3.corosync 255
    round; ck "$ERR_CODE" 1 "negative control: unfixed check reads ssh 255 as stopped"
    reset
    probe cc3.corosync 1
    echo 1 > "$T/boot.p5"
    round; ck "$(repairs)" 1 "negative control: unfixed code repairs while p5 boots"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
