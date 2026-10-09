#!/bin/bash
#
# Unit test for health_heat_check() and _health_heat_auto_repair() in
# ../modules/sdk_health.sh, covering #2008: with every openstack-heat-engine
# stopped, `openstack orchestration service list` (answered by the engines over
# RPC) came back empty, so the check reported code 2 "api timeout" instead of
# code 3 "engine down", and the auto-repair, which restarts engines only from
# "down" lines in ERR_MSG, restarted nothing.
#
# Self-contained: extracts the two functions and stubs stale_api_check_repair,
# the openstack CLI, _health_api_reachable, is_remote_running,
# remote_systemd_restart and _health_fail_log, so it needs no cluster.
#
# The last section is a negative control against the check at 5fcaa461, before
# the fix. It is skipped when that git object is not available.
#
#   Run: bash test_sdk_health_heat_check.sh   (exit 0 = pass)
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
load "$SRC" health_heat_check _health_heat_auto_repair

ERR_LOGSIZE=200
stale_api_check_repair() { :; }

# SVC_LIST is what `openstack orchestration service list -f value` prints.
SVC_LIST=""
fake_openstack() { [ -n "$SVC_LIST" ] && printf '%b' "$SVC_LIST"; return 0; }
OPENSTACK=fake_openstack
API_OK=1
_health_api_reachable() { [ "$API_OK" = "1" ]; }

# STOPPED holds "<node>:<service>" entries that is_remote_running reports down.
STOPPED=""
is_remote_running() { case " $STOPPED " in *" $1:$2 "*) return 1 ;; esac; return 0; }
RESTARTED=""
remote_systemd_restart() { RESTARTED+="$1:$2 "; }
_health_fail_log() { SEEN_CODE=$ERR_CODE; SEEN_LOG=$ERR_LOG; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

check() { # check <stopped entries...>: runs the check, then the repair it gates
    STOPPED="$*" ERR_CODE=0 ERR_LOG="" ERR_MSG="" DESCRIPTION="" SEEN_CODE="" SEEN_LOG="" RESTARTED=""
    health_heat_check
    [ "$SEEN_CODE" = "0" ] || _health_heat_auto_repair
}

up_list() { local n s="" ; for n in "$@" ; do s+="$n heat-engine up\n" ; done ; echo "$s" ; }

# ---- 1cc ----
CUBE_NODE_CONTROL_HOSTNAMES=(cc1)

# 1. healthy
API_OK=1 SVC_LIST="$(up_list cc1)"
check
ck "$SEEN_CODE" 0 "1cc healthy: ERR_CODE"
ck "$RESTARTED" "" "1cc healthy: no restart"

# 2. the engine stopped: the list comes back empty (#2008)
API_OK=1 SVC_LIST=""
check cc1:openstack-heat-engine
ck "$SEEN_CODE" 3 "1cc engine stopped: ERR_CODE 3 (engine down), not 2"
ck "$SEEN_LOG" "journalctl -n 200 -u openstack-heat-engine" "1cc engine stopped: ERR_LOG is the engine's journal"
ck "$(echo -e "$ERR_MSG" | grep -c '^cc1 heat-engine down$')" 1 "1cc engine stopped: ERR_MSG names the node"
ck "$RESTARTED" "cc1:openstack-heat-engine " "1cc engine stopped: auto-repair starts the engine"

# 3. heat-api not answering while the engine runs: still code 2
API_OK=1 SVC_LIST=""
check
ck "$SEEN_CODE" 2 "1cc empty list, engine running: ERR_CODE 2"
ck "$SEEN_LOG" "journalctl -n 200 -u openstack-heat-api" "1cc empty list: ERR_LOG is heat-api's journal"
ck "$RESTARTED" "" "1cc empty list, engine running: no engine restart"

# 4. heat-api stopped (endpoint unreachable): code 1, repair restarts heat-api only
API_OK=0 SVC_LIST=""
check cc1:openstack-heat-api
ck "$SEEN_CODE" 1 "1cc heat-api stopped: ERR_CODE 1"
ck "$RESTARTED" "cc1:openstack-heat-api " "1cc heat-api stopped: restarts heat-api, not the engine"

# ---- 3cc ----
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)

# 5. every engine stopped
API_OK=1 SVC_LIST=""
check cc1:openstack-heat-engine cc2:openstack-heat-engine cc3:openstack-heat-engine
ck "$SEEN_CODE" 3 "3cc all engines stopped: ERR_CODE 3"
ck "$RESTARTED" "cc1:openstack-heat-engine cc2:openstack-heat-engine cc3:openstack-heat-engine " \
   "3cc all engines stopped: restarts each engine"

# 6. one engine stopped, heat already lists it down: restarted once, only there
API_OK=1 SVC_LIST="$(up_list cc1 cc3)cc2 heat-engine down\n"
check cc2:openstack-heat-engine
ck "$SEEN_CODE" 3 "3cc one engine stopped: ERR_CODE 3"
ck "$RESTARTED" "cc2:openstack-heat-engine " "3cc one engine stopped: restarts that engine once"

# 7. all running, healthy
API_OK=1 SVC_LIST="$(up_list cc1 cc2 cc3)"
check
ck "$SEEN_CODE" 0 "3cc healthy: ERR_CODE"

# ---- 8. negative control: the check before the fix reports code 2 and repairs nothing ----
BASE_SRC=$(mktemp)
trap 'rm -f "$BASE_SRC"' EXIT
BASE_REF=5fcaa461
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_heat_check _health_heat_auto_repair
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1)
    API_OK=1 SVC_LIST=""
    check cc1:openstack-heat-engine
    ck "$SEEN_CODE" 2 "negative control: unfixed check reports api timeout"
    ck "$RESTARTED" "" "negative control: unfixed repair restarts nothing"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
