#!/bin/bash
#
# Unit test for health_grafana_check and health_grafana_repair in ../modules/sdk_health.sh.
#
# grafana listens on loopback only, so probing http://<node>:3000 from the master always
# fails to connect. Both functions must probe 127.0.0.1:3000 on the node itself, treat
# only a connect failure (curl 7) as "doesn't respond", and skip the probe on a node that
# cannot be reached over ssh -- remote_run exits the whole sdk there -- while the
# is_remote_running line still reports that node and the next node is still checked.
#
# Self-contained: extracts only the two functions and stubs every helper they call, so it
# needs no cluster.  Run: bash test_health_grafana_probe.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_HEALTH_SRC:-$DIR/../modules/sdk_health.sh}"

src="$(cat "$SRC")"
for f in health_grafana_check health_grafana_repair ; do
    fn="$(echo "$src" | awk "/^$f\\(\\)/{f=1} f{print} f&&/^}/{exit}")"
    [ -n "$fn" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$fn"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# PROBE_<node> is the rc of the curl run on the node; DOWN holds the nodes that are
# neither sshable nor running grafana. Every probe and restart is logged to $LOG.
# Plain variables, not associative arrays, so this also runs under bash 3.
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

is_sshable() { case " $DOWN " in *" $1 "*) return 1 ;; esac ; return 0 ; }
is_remote_running() { is_sshable "$1" ; }
remote_run() {
    local node=$1 ; shift
    echo "remote_run $node $*" >> "$LOG"
    # the real one calls Error, which exits, on a node it cannot reach
    is_sshable "$node" || { echo "remote_run exited on $node" >> "$LOG" ; exit 1 ; }
    local rc="PROBE_$node"
    return "${!rc:-0}"
}
remote_systemd_restart() { echo "restart $*" >> "$LOG" ; }
_health_fail_log() { : ; }
# grafana is not reachable on the node's own address any more
curl_stub() { echo "CURL $*" >> "$LOG" ; return 7 ; }
# shellcheck disable=SC2034  # read by the eval'd functions
CURL=curl_stub ERR_LOGSIZE=50
# shellcheck disable=SC2034  # read by the eval'd functions
CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
# shellcheck disable=SC2034  # read indirectly by remote_run
probe() { PROBE_c1=$1 PROBE_c2=$2 PROBE_c3=$3 ; }

check() { ERR_CODE=0 ; ERR_MSG="" ; : > "$LOG" ; health_grafana_check ; }
repair() { : > "$LOG" ; health_grafana_repair ; }

# 1. healthy on loopback everywhere -> ok, nothing restarted
probe 0 0 0 ; DOWN=""
check
chk "1 code" "$ERR_CODE" 0
chk "1 msg" "$ERR_MSG" ""
repair
chk "1 restart" "$(grep -c '^restart ' "$LOG")" 0

# 2. c2 refuses on loopback -> code 2 for c2 only; repair restarts c2 once
probe 0 7 0
check
chk "2 code" "$ERR_CODE" 2
chk "2 msg" "$(echo -e "$ERR_MSG" | grep -c "doesn't respond")" 1
chk "2 c2" "$(echo -e "$ERR_MSG" | grep -c "grafana on c2 doesn't respond")" 1
repair
chk "2 restart" "$(grep '^restart ' "$LOG")" "restart c2 grafana-server"

# 3. an HTTP error is not "doesn't respond"
probe 22 0 0
check
chk "3 code" "$ERR_CODE" 0
repair
chk "3 restart" "$(grep -c '^restart ' "$LOG")" 0

# 4. c2 unreachable -> reported as not running, no probe on it, c3 still probed
probe 0 0 0 ; DOWN="c2"
( check ; echo "code=$ERR_CODE" ; echo -e "$ERR_MSG" ) > "$LOG.out" 2>&1
chk "4 no exit" "$(grep -c 'remote_run exited' "$LOG")" 0
chk "4 code" "$(grep '^code=' "$LOG.out")" "code=1"
chk "4 msg" "$(grep -c 'grafana on c2 is not running' "$LOG.out")" 1
chk "4 c3 probed" "$(grep -c '^remote_run c3 ' "$LOG")" 1
rm -f "$LOG.out"
DOWN=""

# 5. the probe targets loopback on the node, never <node>:3000 from here
check
chk "5 loopback" "$(grep -c '^remote_run c[123] .*http://127.0.0.1:3000/' "$LOG")" 3
chk "5 no direct" "$(grep -c '^CURL ' "$LOG")" 0
repair
chk "5 repair loopback" "$(grep -c '^remote_run c[123] .*http://127.0.0.1:3000/' "$LOG")" 3
chk "5 repair no direct" "$(grep -c '^CURL ' "$LOG")" 0

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
