#!/bin/bash
#
# Unit test for #2325: after a rolling upgrade a compute did not come back into
# Pacemaker, and the hacluster repair then restarted Pacemaker on a healthy
# control node.
#
#   A. pacemaker_remote_add (../modules.pre/sdk_pacemaker.sh): pcs refuses
#      "cluster node add-remote" unless every remote node already in the CIB is in
#      the local pcs known-hosts. The function authenticated only the new node,
#      dropped the error and started pacemaker_remote anyway.
#   B. health_hacluster_repair (../modules/sdk_health.sh): with every control node
#      online it re-adds the compute and leaves this node's Pacemaker alone.
#
# Self-contained: extracts the functions and stubs pcs / cibadmin / remote_run.
# The pcs stub keeps a known-hosts list and a list of remote resources and fails
# add-remote the way pcs 0.11 does.
#
# Negative controls use 04f1aa91 (before the fix). They are skipped when the git
# object is not available.
#
#   Run: bash test_sdk_pacemaker_remote_add_auth.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCMK="$DIR/../modules.pre/sdk_pacemaker.sh"
HEALTH="$DIR/../modules/sdk_health.sh"
OLD=04f1aa91

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }
load() { # load <file> <function>...
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src" | sed -e "s#/usr/sbin/pcs#pcs#g" -e "s#/etc/appliance/state/#$T/state/#g")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}
old_file() { git -C "$DIR" show "$OLD:core/sdk_sh/$1" > "$T/old.sh" 2>/dev/null && [ -s "$T/old.sh" ]; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
has() { grep -c -- "$1" "$T/calls" 2>/dev/null; }

SRVSTO=1 SRVTO=1 HOSTNAME=cc1 HEX_SDK=hex_sdk
DEAD="" CTRL=""
Quiet() { [ "$1" = "-n" ] && shift; "$@" >/dev/null 2>&1; }
timeout() { shift; "$@"; }
log_error() { echo "$*" >> "$T/errors"; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
# the stub keeps its state in files: add-remote runs in a command substitution
cib() { cat "$T/cib" 2>/dev/null; }
known() { cat "$T/known" 2>/dev/null; }
cibadmin() { local n; for n in $(cib); do echo "<primitive id=\"$n\" class=\"ocf\" type=\"remote\" provider=\"pacemaker\">"; done; }
remote_run() { echo "remote_run $*" >> "$T/calls"; return 0; }
hex_sdk() {
    echo "hex_sdk $*" >> "$T/calls"
    case "$*" in
        "remote_run "*" hex_sdk is_control_node") in_list "$2" "$CTRL" ;;
        "pacemaker_remote_remove "*) echo " $(cib) " | sed "s/ $2 / /" > "$T/cib.new"; mv "$T/cib.new" "$T/cib" ;;
    esac
}
pcs() {
    local n
    echo "pcs $*" >> "$T/calls"
    case "$1 ${2:-}" in
        "host auth")
            in_list "$3" "$DEAD" && return 1
            in_list "$3" "$(known)" || echo "$(known) $3" > "$T/known" ;;
        "cluster node")
            in_list "$4" "$(cib)" && { echo "Error: '$4' already exists"; return 1; }
            for n in $(cib) $4; do
                in_list "$n" "$(known)" && continue
                echo "Error: Host '$n' is not known to pcs, try to authenticate the host using 'pcs host auth $n' command"
                return 1
            done
            echo "$(cib) $4" > "$T/cib" ;;
        "status "*) cat "$T/status" 2>/dev/null ;;
    esac
    return 0
}
reset() { rm -f "$T/calls" "$T/errors" "$T/status" "$T/cib" "$T/known"; DEAD="" CTRL=""; }

# ================= A. pacemaker_remote_add =================
load "$PCMK" pacemaker_remote_nodes pacemaker_remote_add

# ---- A1. the upgrade: p5 is in the CIB, known-hosts is empty ----
reset; echo p5 > "$T/cib"
pacemaker_remote_add p4 2>/dev/null; ck $? 0 "A1 add p4 while p5 is not known: rc"
ck "$(in_list p4 "$(cib)"; echo $?)" 0 "A1 p4 has a resource"
ck "$(has 'pcs host auth p5 ')" 1 "A1 the existing remote node is authenticated"
ck "$(has 'remote_run p4 systemctl enable --now pacemaker_remote')" 1 "A1 pacemaker_remote is started on p4"

# ---- A2. no other remote node (the last compute of a roll) ----
reset
pacemaker_remote_add p4 2>/dev/null; ck $? 0 "A2 add p4 with no other remote: rc"
ck "$(in_list p4 "$(cib)"; echo $?)" 0 "A2 p4 has a resource"
ck "$(has 'pcs host auth')" 1 "A2 only the new node is authenticated"

# ---- A3. the existing remote node cannot be authenticated: fail loudly ----
reset; echo p5 > "$T/cib"; DEAD="p5"
pacemaker_remote_add p4 2>"$T/stderr"; ck $? 1 "A3 add fails: rc"
ck "$(in_list p4 "$(cib)"; echo $?)" 1 "A3 p4 has no resource"
ck "$(grep -c "p4 not added: Error: Host 'p5' is not known to pcs" "$T/errors")" 1 "A3 the pcs error is logged"
ck "$(grep -c "p4 not added" "$T/stderr")" 1 "A3 the pcs error is on stderr"
ck "$(has 'enable --now pacemaker_remote')" 0 "A3 pacemaker_remote is not started"

# ---- A4. p4 already has a resource: unchanged, the service is started ----
reset; echo "p4 p5" > "$T/cib"; echo p5 > "$T/known"
pacemaker_remote_add p4 2>/dev/null; ck $? 0 "A4 p4 already added: rc"
ck "$(has 'remote_run p4 systemctl enable --now pacemaker_remote')" 1 "A4 pacemaker_remote is started"
ck "$(test -e "$T/errors"; echo $?)" 1 "A4 nothing logged as an error"

# ---- A5. a control node: a failed add does not end the function early ----
reset; echo p5 > "$T/cib"; DEAD="p5" CTRL="cc2"
is_remote_running() { return 0; }
pacemaker_remote_add cc2 2>/dev/null; ck $? 0 "A5 control node: rc"
ck "$(has 'remote_run cc2 systemctl enable --now pacemaker_remote')" 1 "A5 control node: unchanged path"

# ---- A6. negative control: the old function leaves p4 out and starts the service ----
if old_file modules.pre/sdk_pacemaker.sh ; then
    load "$T/old.sh" pacemaker_remote_add
    reset; echo p5 > "$T/cib"
    pacemaker_remote_add p4 2>/dev/null
    ck "$(in_list p4 "$(cib)"; echo $?)" 1 "A6 old code: p4 has no resource"
    ck "$(has 'remote_run p4 systemctl enable --now pacemaker_remote')" 1 "A6 old code: pacemaker_remote started anyway"
    load "$PCMK" pacemaker_remote_add
else
    echo "SKIP: A6 negative control needs git object $OLD"
fi

# ================= B. health_hacluster_repair =================
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
CUBE_NODE_COMPUTE_HOSTNAMES=(cc1 cc2 cc3 p4 p5)
CTRL_ALL="cc1 cc2 cc3"
cmd() { :; }
cubectl() { :; }
jq() { :; }
is_cluster_rolling() { return 1; }
is_sshable() { return 0; }
remote_run() {
    echo "remote_run $*" >> "$T/calls"
    case "$*" in *"hex_sdk is_control_node") in_list "$1" "$CTRL_ALL" ; return ;; esac
    return 0
}
touch "$T/state/configured"
status() { # status <control line> <remote line> [extra line]
    printf '  * Online: [ %s ]\n%s  * RemoteOnline: [ %s ]\n%s\n' "$1" "${4:+  * OFFLINE: [ $4 ]$'\n'}" "$2" "${3:-}" > "$T/status"
}
HA=' * vip (ocf:heartbeat:IPaddr2): Started cc1
 * cinder-volume (systemd:openstack-cinder-volume): Started cc2'
load "$HEALTH" _health_hacluster_controls_ok health_hacluster_repair

# ---- B1. controls online, p4 not RemoteOnline: re-add p4, no Pacemaker restart ----
reset; status "cc1 cc2 cc3" "p5" "$HA"
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop')" 0 "B1 this node's Pacemaker is not stopped"
ck "$(has 'hex_sdk pacemaker_node_start cc1')" 1 "B1 services are still made sure to run"
ck "$(has 'hex_sdk pacemaker_remote_remove p4')" 1 "B1 p4 is removed"
ck "$(has 'hex_sdk pacemaker_remote_add p4')" 1 "B1 p4 is re-added"
ck "$(has 'pacemaker_remote_remove p5')" 0 "B1 p5 is left alone"

# ---- B2. a control node is offline: restart as before ----
reset; status "cc1 cc2" "p4 p5" "$HA" "cc3"
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop cc1')" 1 "B2 control offline: Pacemaker is restarted"

# ---- B3. HA and cinder-volume is not started: restart as before ----
reset; status "cc1 cc2 cc3" "p4 p5" ' * vip (ocf:heartbeat:IPaddr2): Started cc1
 * cinder-volume (systemd:openstack-cinder-volume): Stopped'
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop cc1')" 1 "B3 cinder-volume stopped: Pacemaker is restarted"

# ---- B4. ovndb_servers failed: restart as before ----
reset; status "cc1 cc2 cc3" "p4 p5" "$HA
 * ovndb_servers (ocf:ovn:ovndb-servers): FAILED cc2"
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop cc1')" 1 "B4 ovndb_servers failed: Pacemaker is restarted"

# ---- B5. pcs status gives nothing: restart as before ----
reset
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop cc1')" 1 "B5 no pcs status: Pacemaker is restarted"

# ---- B6. nothing wrong: no restart, no remote node touched ----
reset; status "cc1 cc2 cc3" "p4 p5" "$HA"
health_hacluster_repair >/dev/null 2>&1
ck "$(has 'hex_sdk pacemaker_node_stop')" 0 "B6 healthy: Pacemaker is not stopped"
ck "$(has 'pacemaker_remote_remove')" 0 "B6 healthy: no remote node removed"

# ---- B7. negative control: the old repair restarts Pacemaker for a missing compute ----
if old_file modules/sdk_health.sh ; then
    load "$T/old.sh" health_hacluster_repair
    reset; status "cc1 cc2 cc3" "p5" "$HA"
    health_hacluster_repair >/dev/null 2>&1
    ck "$(has 'hex_sdk pacemaker_node_stop cc1')" 1 "B7 old code: Pacemaker restarted for a missing compute"
else
    echo "SKIP: B7 negative control needs git object $OLD"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
