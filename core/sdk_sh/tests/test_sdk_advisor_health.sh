#!/bin/bash
#
# Unit test for health_advisor_check/report/repair/_auto_repair in
# ../modules/sdk_health.sh -- the cluster-check entry that gives "cluster
# check" visibility into the Cube AI Advisor agent, which it did not have
# before.
#
# The agent runs on every node in the cluster (not only control nodes, which
# is where "cluster check" itself runs), so the check must fan out over
# CUBE_NODE_LIST_HOSTNAMES rather than look only at the local node -- a
# node-local check would be blind to every compute/storage node, which is
# most of the fleet.
#
# No node enrolled must stay healthy: a cluster that never rolled into the
# Advisor is the normal case, not a fault. A node holding an identity whose
# agent is not running is the fault this exists to catch, naming the node so
# an operator does not have to go hunting. A node holding an identity whose
# binary is missing is a distinct code, also naming the node: only
# re-enrolment fixes that, so the auto path must never spend its retry budget
# on it.
#
# Self-contained: extracts only the functions under test (plus the two small
# framework helpers they call: _health_report and health_errcode_lookup), and
# stubs _health_fail_log, remote_run and is_remote_running so this needs no
# cluster and no SSH.
# Run:  bash test_sdk_advisor_health.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

PROG=test
source "$DIR/../modules/errcodes"

for f in health_advisor_check health_advisor_report health_advisor_repair \
         _health_advisor_auto_repair _health_report health_errcode_lookup ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

# _health_fail_log normally logs to /var/log, drives auto_repair and posts to
# influx -- none of that is this test's concern, only the one contract
# _health_report relies on: it hands ERR_CODE back as the return status.
_health_fail_log() { return "$ERR_CODE"; }

ADVISOR_AGENT_UNIT_NAME=cube-advisor-agent.service
ADVISOR_HEALTH_CERT=/etc/cube/advisor-agent/agent.crt
ADVISOR_HEALTH_BIN=/usr/local/bin/cube-advisor-agent
HEX_SDK=hex_sdk_marker

# Per-node fixtures, keyed by hostname. Unset/absent means "not present".
declare -A CERT_PRESENT BIN_PRESENT UNIT_ACTIVE
REPAIR_LOG=""

# remote_run <node> <cmd...> -- the three shapes the code under test uses:
# "stat <cert>" and "test -x <bin>" answer from the fixtures; anything else
# (the $HEX_SDK advisor_agent_service_start call) is just recorded.
remote_run() {
    local node=$1 ; shift
    case "$1" in
        stat) [ "${CERT_PRESENT[$node]:-0}" = "1" ] ;;
        test) [ "${BIN_PRESENT[$node]:-0}" = "1" ] ;;
        *) REPAIR_LOG+="$node:$* " ;;
    esac
}

is_remote_running() {
    local node=$1
    [ "${UNIT_ACTIVE[$node]:-0}" = "1" ]
}

reset() {
    CERT_PRESENT=() ; BIN_PRESENT=() ; UNIT_ACTIVE=()
    REPAIR_LOG=""
    ERR_CODE=0 ; ERR_MSG= ; ERR_LOG= ; DESCRIPTION= ; FORMAT=
}

enrol() {  # enrol <node> [active|inactive|nobin]
    local node=$1 state=${2:-active}
    CERT_PRESENT[$node]=1
    case "$state" in
        active)   BIN_PRESENT[$node]=1 ; UNIT_ACTIVE[$node]=1 ;;
        inactive) BIN_PRESENT[$node]=1 ; UNIT_ACTIVE[$node]=0 ;;
        nobin)    BIN_PRESENT[$node]=0 ; UNIT_ACTIVE[$node]=0 ;;
    esac
}

# ---- no node enrolled: healthy, with an advisory note, never a fault ------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
health_advisor_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "no node enrolled returned $rc, want 0"
[ "$DESCRIPTION" = "not enrolled" ] && ok || bad "no node enrolled description: '$DESCRIPTION'"

# ---- two nodes enrolled, both running: healthy -----------------------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 active
health_advisor_check ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "two enrolled+active returned $rc, want 0"

# ---- two enrolled, one stopped: code 1, naming that node -------------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 inactive
health_advisor_check ; rc=$?
[ "$rc" -eq 1 ] && ok || bad "one of two stopped returned $rc, want 1"
case "$ERR_MSG" in
    *c2*) ok ;;
    *) bad "message does not name the stopped node: $ERR_MSG" ;;
esac
case "$ERR_MSG" in
    *c1*) bad "message named a healthy node too: $ERR_MSG" ;;
    *) ok ;;
esac

# ---- one enrolled with a missing binary: code 2, naming it -----------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 nobin
health_advisor_check ; rc=$?
[ "$rc" -eq 2 ] && ok || bad "missing-binary node returned $rc, want 2"
case "$ERR_MSG" in
    *c2*) ok ;;
    *) bad "message does not name the node missing its binary: $ERR_MSG" ;;
esac

# ---- health_advisor_report round-trips a code through health_errcode_lookup
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2)
enrol c1 active ; enrol c2 inactive
FORMAT=line
out="$(health_advisor_report)"
want="$(health_errcode_lookup advisor 1)"
case "$out" in
    *"error_code=1"*"description=$want"*) ok ;;
    *) bad "report did not round-trip code 1 through health_errcode_lookup: $out (want desc '$want')" ;;
esac

# ---- repair: restarts only the affected node, remotely --------------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 inactive
health_advisor_repair
[ "$REPAIR_LOG" = "c2:hex_sdk_marker advisor_agent_service_start " ] && ok \
    || bad "repair did not restart exactly the affected node: '$REPAIR_LOG'"

# ---- auto-repair on code 1: same restart, gated ----------------------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 inactive
ERR_CODE=1
_health_advisor_auto_repair
[ "$REPAIR_LOG" = "c2:hex_sdk_marker advisor_agent_service_start " ] && ok \
    || bad "auto-repair on code 1 did not restart the affected node: '$REPAIR_LOG'"

# ---- auto-repair on code 2: calls nothing ----------------------------------
reset
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
enrol c1 active ; enrol c2 nobin
ERR_CODE=2
_health_advisor_auto_repair
[ -z "$REPAIR_LOG" ] && ok || bad "auto-repair on code 2 called something: '$REPAIR_LOG'"

# ---- auto-repair dispatch is by name: _health_fail_log builds
# "_health_<srv>_auto_repair" from the checked component's name and looks it
# up by that exact string -- a typo here would silently mean "no auto-repair",
# with no error anywhere.
if declare -F _health_advisor_auto_repair >/dev/null 2>&1 ; then
    ok
else
    bad "_health_advisor_auto_repair is not defined by that exact name"
fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_advisor_check/report/repair"; exit 0; } || exit 1
