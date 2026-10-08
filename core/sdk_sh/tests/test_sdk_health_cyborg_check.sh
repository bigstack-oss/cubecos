#!/bin/bash
#
# Unit test for health_cyborg_check() in ../modules/sdk_health.sh, covering
# #1708: a stopped cyborg-agent on a compute node set a lowercase err_code=5,
# which the health framework never reads, so the check passed, no ERR_LOG was
# attached and _health_cyborg_auto_repair (gated on ERR_CODE) never restarted
# the agent.
#
# Self-contained: extracts health_cyborg_check and _health_cyborg_auto_repair,
# and stubs is_remote_running, remote_systemd_restart and _health_fail_log, so
# it needs no cluster.
#
# The last section is a negative control: the check as it was at 69c67285,
# before the fix, must miss the stopped agent, so these tests cannot pass for
# the wrong reason. It is skipped when that git object is not available.
#
#   Run: bash test_sdk_health_cyborg_check.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

load() { # load <file> <function>...
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}
load "$SRC" health_cyborg_check _health_cyborg_auto_repair

ERR_LOGSIZE=200
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
CUBE_NODE_COMPUTE_HOSTNAMES=(cc1 cc2 cc3 cn1)

# STOPPED holds "<node>:<service>" entries that is_remote_running reports down.
STOPPED=""
is_remote_running() { case " $STOPPED " in *" $1:$2 "*) return 1 ;; esac; return 0; }
RESTARTED=""
remote_systemd_restart() { RESTARTED+="$1:$2 "; }
# The framework reads ERR_CODE / ERR_LOG after the check; record what it saw.
_health_fail_log() { SEEN_CODE=$ERR_CODE; SEEN_LOG=$ERR_LOG; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

check() { # check <stopped entries...>: runs the check, then the repair it gates
    STOPPED="$*" ERR_CODE=0 ERR_LOG="" ERR_MSG="" SEEN_CODE="" SEEN_LOG="" RESTARTED=""
    health_cyborg_check
    _health_cyborg_auto_repair
}

# ---- 1. everything running: healthy, nothing restarted ----
check
ck "$SEEN_CODE" 0 "all running: ERR_CODE"
ck "$SEEN_LOG" "" "all running: no ERR_LOG"
ck "$RESTARTED" "" "all running: no restart"

# ---- 2. cyborg-agent down on a compute-only node (#1708) ----
check cn1:cyborg-agent
ck "$SEEN_CODE" 5 "agent down: ERR_CODE 5"
ck "$SEEN_LOG" "journalctl -n 200 -u cyborg-agent" "agent down: ERR_LOG is the agent's journal"
ck "$(echo -e "$ERR_MSG" | grep -c 'cyborg-agent on cn1 is not running')" 1 "agent down: ERR_MSG names the node"
ck "$RESTARTED" "cn1:cyborg-agent " "agent down: auto-repair restarts it"

# ---- 3. the api/conductor branches are unchanged ----
check cc2:cyborg-api
ck "$SEEN_CODE" 3 "api down: ERR_CODE 3"
ck "$RESTARTED" "cc2:cyborg-api " "api down: auto-repair restarts it"
check cc1:cyborg-conductor
ck "$SEEN_CODE" 4 "conductor down: ERR_CODE 4"

# ---- 4. negative control: the check before the fix misses the agent ----
BASE_SRC=$(mktemp)
trap 'rm -f "$BASE_SRC"' EXIT
BASE_REF=69c67285
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_cyborg_check
    check cn1:cyborg-agent
    ck "$SEEN_CODE" 0 "negative control: unfixed check reports healthy"
    ck "$RESTARTED" "" "negative control: unfixed check repairs nothing"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
