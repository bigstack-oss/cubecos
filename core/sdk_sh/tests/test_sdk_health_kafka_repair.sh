#!/bin/bash
#
# Unit test for the kafka / zookeeper health check and repairs in
# ../modules/sdk_health.sh, covering #1778: with the broker stopped,
# health_kafka_check's code 1 was overwritten by the queue check (code 6), the
# code-6 auto-repair ran `hex_config update_kafka_topics` against the dead
# broker and hung the round for ~16 min, and the manual repairs
# (health_kafka_repair / health_zookeeper_repair) only called
# _health_datapipe_deep_repair, which is a no-op on its first call after boot
# and within its cooldown and wipes the datapipe on every node otherwise.
# Nothing ever started the broker.
#
# Also covers the review of the first fix:
#   B1 a check_repair runs the zookeeper repair, then the kafka repair; the
#      second must not deep-repair a broker the first just started;
#   B2 kafka is Type=simple, so "running" right after a start is no proof: a
#      broker that dies seconds later must not count as repaired forever.
# and its second round:
#   R2-B1 a failed-start mark must not go stale while the brokers are up but the
#      kafka check stays non-zero, or a later stopped broker skips its start;
#   R2-S2 the wait is bounded in wall-clock time, and an unreachable peer does
#      not stretch the round past telegraf's 10-minute timeout.
#
# Self-contained: extracts the functions and stubs is_remote_running,
# remote_systemd_start/restart, nc (zookeeper's dump), sleep, journalctl,
# kafka_stats ($HEX_SDK), $HEX_CFG, _health_datapipe_deep_repair and
# _health_fail_log, so it needs no cluster and never touches a datapipe.
#
# The last sections are negative controls against 5fcaa461 (before the fix)
# f3cc90da (the first fix, before B1/B2) and 4ace38bc (before R2-B1/R2-S2).
# Skipped when unavailable.
#
#   Run: bash test_sdk_health_kafka_repair.sh   (exit 0 = pass)
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
load "$SRC" health_kafka_check _health_kafka_auto_repair health_kafka_repair health_zookeeper_repair \
            _health_datapipe_start_stopped _health_datapipe_up _health_datapipe_try_start _health_kafka_queues_ok

ERR_LOGSIZE=200
Quiet() { [ "$1" = "-n" ] && shift; "$@"; }
journalctl() { :; }

# STOPPED holds "<node>:<service>" entries that is_remote_running reports down.
# A start brings the unit up unless it is in NOSTART. A unit in CRASH comes up and
# dies again whenever time passes (sleep): a Type=simple broker that exits seconds
# after systemd called it started.
# A node in HANG drops packets: it is not sshable, and each bare ssh to it costs a
# 120 s connect timeout. SLOWUP adds seconds to every is_remote_running (a slow
# ssh). sleep and those costs advance SECONDS, so the wall-clock bounds can be
# asserted (only outside pipelines: a subshell's SECONDS does not come back).
STOPPED="" NOSTART="" CRASH="" STARTED="" SLEPT=0 NOREG=0 HANG="" SLOWUP=0
is_local_node() { [ "$1" = "cc1" ] ; }
is_sshable() { [ "$1" != "$HANG" ] ; }
is_remote_running() {
    SECONDS=$((SECONDS + SLOWUP))
    [ -n "$HANG" ] && [ "$1" = "$HANG" ] && { SECONDS=$((SECONDS + 120)) ; return 1 ; }
    case " $STOPPED " in *" $1:$2 "*) return 1 ;; esac; return 0
}
remote_systemd_start() {
    STARTED+="$1:$2 "
    case " $NOSTART " in *" $1:$2 "*) return 0 ;; esac
    STOPPED=" $STOPPED " ; STOPPED="${STOPPED// $1:$2 / }"
}
remote_systemd_restart() { remote_systemd_start "$@"; }
sleep() { SLEPT=$((SLEPT+1)) ; SECONDS=$((SECONDS + ${1:-0})) ; [ -z "$CRASH" ] || STOPPED+=" $CRASH" ; }
# zookeeper's dump: one /brokers/ids line per running broker (none with NOREG=1)
nc() {
    local node
    [ "$NOREG" = "1" ] && return 0
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        is_remote_running $node kafka && echo "/brokers/ids/$node"
    done
}

# kafka_stats runs in a pipeline (a subshell), so its calls are counted in a file
STATSF=$(mktemp)
BASE_SRC=$(mktemp)
_DP_START_MARK=$(mktemp -u)
trap 'rm -f "$STATSF" "$BASE_SRC" "$_DP_START_MARK"' EXIT
QUEUES=6 HEXCFG="" DEEP=0
fake_sdk() {
    case "$1" in
        kafka_stats) echo x >> "$STATSF" ; local i ; for ((i=0; i<QUEUES; i++)) ; do echo "Topic: t$i PartitionCount: 6" ; done ;;
        _health_datapipe_deep_repair) DEEP=$((DEEP+1)) ;;
    esac
}
HEX_SDK=fake_sdk
fake_cfg() { HEXCFG+="$* " ; }
HEX_CFG=fake_cfg
_health_datapipe_deep_repair() { DEEP=$((DEEP+1)) ; }
_health_fail_log() { SEEN_CODE=$ERR_CODE ; return $ERR_CODE ; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
mark() { [ -f "$_DP_START_MARK" ] && echo yes || echo no ; }
age_mark() { echo $(( $(date +%s) - $1 )) > "$_DP_START_MARK" ; }

reset() { # reset <stopped entries...>
    STOPPED="$*" NOSTART="" CRASH="" STARTED="" HEXCFG="" DEEP=0 SLEPT=0 NOREG=0 HANG="" SLOWUP=0
    rm -f "$_DP_START_MARK"
    : > "$STATSF"
    ERR_CODE=0 ERR_LOG="" ERR_MSG="" SEEN_CODE=""
}
check() { # check <stopped entries...>: the check, then the auto-repair it gates
    reset "$@"
    health_kafka_check 2>/dev/null
    RC=$?
    [ "$SEEN_CODE" = "0" ] || _health_kafka_auto_repair
}

# ---- 1cc ----
CUBE_NODE_CONTROL_HOSTNAMES=(cc1)

# 1. healthy
QUEUES=6 ; check
ck "$SEEN_CODE" 0 "healthy: ERR_CODE"
ck "$STARTED$HEXCFG$DEEP" "0" "healthy: nothing repaired"

# 2. broker stopped: code 1 survives, no queue check, auto-repair starts it (#1778)
QUEUES=0 ; check cc1:kafka
ck "$SEEN_CODE" 1 "broker stopped: ERR_CODE 1, not 6"
ck "$RC" 1 "broker stopped: check rc 1"
ck "$(echo -e "$ERR_MSG" | grep -c 'kafka on cc1 is not running')" 1 "broker stopped: ERR_MSG names the node"
ck "$(echo -e "$ERR_MSG" | grep -c 'built-in queues')" 0 "broker stopped: no queue message"
ck "$(wc -l < "$STATSF" | tr -d ' ')" 0 "broker stopped: kafka_stats not run against the dead broker"
ck "$STARTED" "cc1:kafka " "broker stopped: auto-repair starts kafka"
ck "$HEXCFG" "" "broker stopped: auto-repair never runs update_kafka_topics"
ck "$DEEP" 0 "broker stopped: auto-repair never runs the deep repair"

# 3. broker running, queues missing: code 6 and its repair are unchanged
QUEUES=3 ; check
ck "$SEEN_CODE" 6 "queues missing: ERR_CODE 6"
ck "$HEXCFG" "update_kafka_topics " "queues missing: update_kafka_topics"
ck "$STARTED$DEEP" "0" "queues missing: no start, no deep repair"
QUEUES=6

# 4. manual repair, broker stopped: started directly, no deep repair
reset cc1:kafka
health_kafka_repair
ck "$STARTED" "cc1:kafka " "kafka_repair stopped: starts kafka"
ck "$DEEP" 0 "kafka_repair stopped: no deep repair"
ck "$(mark)" no "kafka_repair stopped: no failed-start mark"

# 5. manual repair, broker stopped and will not start: no deep repair in this call
reset cc1:kafka ; NOSTART="cc1:kafka"
health_kafka_repair
ck "$STARTED" "cc1:kafka " "kafka_repair no start: tried to start kafka"
ck "$DEEP" 0 "kafka_repair no start: no deep repair in a call that started kafka"
ck "$SLEPT" 9 "kafka_repair no start: the wait is bounded (90 s: 9 x 10 s)"
ck "$(mark)" yes "kafka_repair no start: failed start marked"

# 6. manual repair, everything up but queues missing: deep repair as before
reset ; QUEUES=3
health_kafka_repair
ck "$STARTED" "" "kafka_repair queues missing: no start"
ck "$DEEP" 1 "kafka_repair queues missing: deep repair as before"
QUEUES=6

# 7. manual repair, everything up and healthy: nothing to do
reset
health_kafka_repair
ck "$STARTED$DEEP" "0" "kafka_repair healthy: no start, no deep repair"

# 8. zookeeper repair (code 2 "brokers online") with the broker stopped
reset cc1:kafka
health_zookeeper_repair
ck "$STARTED" "cc1:kafka " "zookeeper_repair, kafka stopped: starts kafka"
ck "$DEEP" 0 "zookeeper_repair, kafka stopped: no deep repair"

# 9. both stopped: zookeeper first, then kafka
reset cc1:kafka cc1:zookeeper
health_zookeeper_repair
ck "$STARTED" "cc1:zookeeper cc1:kafka " "both stopped: zookeeper then kafka"
ck "$DEEP" 0 "both stopped: no deep repair"

# 10. zookeeper repair, all running but brokers not registered: deep repair as before
reset ; NOREG=1
health_zookeeper_repair
ck "$DEEP" 1 "zookeeper_repair running, unregistered: deep repair as before"

# ---- B1: check_repair DataPipe = zookeeper repair, then kafka repair ----
# 11. the kafka repair must not wipe the broker the zookeeper repair just started
reset cc1:kafka
health_zookeeper_repair
health_kafka_repair
ck "$STARTED" "cc1:kafka " "B1: kafka started once, by the zookeeper repair"
ck "$DEEP" 0 "B1: no deep repair in the pass that started kafka"

# 12. same, with a broker that does not hold: still no deep repair in that pass
reset cc1:kafka ; CRASH="cc1:kafka"
health_zookeeper_repair
sleep 1
health_kafka_repair
ck "$DEEP" 0 "B1 crash: no deep repair in the pass that started kafka"

# ---- B2: a broker that dies seconds after its start ----
# 13. not counted as repaired; retried while the failure is recent
reset cc1:kafka ; CRASH="cc1:kafka"
health_kafka_repair
ck "$STARTED" "cc1:kafka " "B2: started"
ck "$(mark)" yes "B2: the start that did not hold is marked"
ck "$DEEP" 0 "B2: no deep repair in that call"
sleep 1
health_kafka_repair
ck "$DEEP" 0 "B2: retried, no deep repair while the failure is < 900 s old"
# 14. 900 s after the first failed start: not started again, deep repair allowed
age_mark 1000 ; STARTED=""
health_kafka_repair
ck "$STARTED" "" "B2 old: not started again"
ck "$DEEP" 1 "B2 old: escalates to the deep repair"
ck "$(mark)" no "B2 old: mark cleared"
# 15. a stale mark on a now-healthy datapipe is retired by the check
reset ; age_mark 1000
health_kafka_check 2>/dev/null
ck "$(mark)" no "healthy check clears a stale failed-start mark"

# ---- R2-B1: a mark must not outlive brokers that are up ----
# 15b. brokers up and registered, but the check ends non-zero (code 6 here): the
#      mark is retired anyway, so a later stopped broker is started, not wiped
reset ; age_mark 5000 ; QUEUES=3
health_kafka_check 2>/dev/null
ck "$SEEN_CODE" 6 "R2-B1: check stays non-zero (code 6)"
ck "$(mark)" no "R2-B1: brokers up retire the mark despite code 6"
QUEUES=6
STOPPED="cc1:kafka" STARTED="" DEEP=0
health_zookeeper_repair
ck "$STARTED" "cc1:kafka " "R2-B1: later stopped broker is started"
ck "$DEEP" 0 "R2-B1: later stopped broker is not deep-repaired"
# 15c. a broker still down at round time keeps the mark (B2 escalation intact)
reset cc1:kafka ; age_mark 5000
health_kafka_check 2>/dev/null
ck "$(mark)" yes "R2-B1: a down broker keeps the mark"

# ---- 3cc ----
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)

# ---- R2-S2: wall-clock bounds ----
# 15d. cc2's broker stopped, cc3 dropping packets: the round (check + auto-repair) does
#      not wait for cc3 and stays well inside telegraf's 600 s
reset cc2:kafka ; HANG=cc3
T0=$SECONDS
health_kafka_check 2>/dev/null
_health_kafka_auto_repair
ck "$SEEN_CODE" 1 "R2-S2 hang: ERR_CODE 1"
ck "$SLEPT" 0 "R2-S2 hang: no registration wait for an unreachable peer"
ck "$([ $((SECONDS - T0)) -lt 600 ] && echo ok || echo $((SECONDS - T0)))" ok "R2-S2 hang: round under 600 s"
ck "$(echo " $STARTED " | grep -c ' cc2:kafka ')" 1 "R2-S2 hang: cc2's broker still started"
# 15e. every ssh slow (30 s) and the broker never registering: the wait stops at its
#      90 s deadline (plus one pass), not after 9 passes of 70 s
reset cc2:kafka ; NOREG=1 ; SLOWUP=30
T0=$SECONDS
_health_datapipe_start_stopped
RC=$?
ck "$RC" 2 "R2-S2 slow: not up in time"
ck "$([ $((SECONDS - T0)) -le 400 ] && echo ok || echo $((SECONDS - T0)))" ok "R2-S2 slow: wait bounded by wall clock"

# 16. one broker stopped: only that one is started
check cc2:kafka
ck "$SEEN_CODE" 1 "3cc one broker stopped: ERR_CODE 1"
ck "$STARTED" "cc2:kafka " "3cc one broker stopped: starts only cc2"
ck "$DEEP" 0 "3cc one broker stopped: no deep repair"

# 17. B1 on 3cc
reset cc2:kafka
health_zookeeper_repair
health_kafka_repair
ck "$STARTED$DEEP" "cc2:kafka 0" "3cc B1: cc2 started once, no deep repair"

# ---- 18. no auto-repair path can reach the deep repair ----
for fn in _health_kafka_auto_repair _health_datapipe_start_stopped _health_datapipe_up ; do
    ck "$(extract $fn "$SRC" | grep -c datapipe_deep_repair)" 0 "$fn does not call the deep repair"
done

# ---- 19. negative controls ----
CUBE_NODE_CONTROL_HOSTNAMES=(cc1)
BASE_REF=5fcaa461
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_kafka_check _health_kafka_auto_repair health_kafka_repair
    QUEUES=0 ; check cc1:kafka
    ck "$SEEN_CODE" 6 "negative control: unfixed check reports code 6"
    ck "$HEXCFG" "update_kafka_topics " "negative control: unfixed auto-repair runs update_kafka_topics"
    ck "$STARTED" "" "negative control: unfixed auto-repair starts nothing"
    QUEUES=6
    reset cc1:kafka
    health_kafka_repair
    ck "$STARTED$DEEP" "1" "negative control: unfixed manual repair goes straight to the deep repair"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

FIRST_REF=f3cc90da
if git -C "$DIR" show "$FIRST_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_kafka_repair health_zookeeper_repair _health_datapipe_start_stopped
    reset cc1:kafka
    health_zookeeper_repair
    health_kafka_repair
    ck "$DEEP" 1 "negative control B1: first fix deep-repairs the broker it just started"
    reset cc1:kafka ; CRASH="cc1:kafka"
    health_kafka_repair ; sleep 1
    health_kafka_repair ; sleep 1
    health_kafka_repair
    ck "$DEEP" 0 "negative control B2: first fix counts a dying broker as repaired, never escalates"
else
    echo "SKIP: negative control needs git object $FIRST_REF"
fi

SECOND_REF=4ace38bc
if git -C "$DIR" show "$SECOND_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_kafka_check health_zookeeper_repair _health_datapipe_try_start \
                     _health_datapipe_start_stopped _health_datapipe_up
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1)
    reset ; age_mark 5000 ; QUEUES=3
    health_kafka_check 2>/dev/null
    QUEUES=6 STOPPED="cc1:kafka" STARTED="" DEEP=0
    health_zookeeper_repair
    ck "$STARTED$DEEP" "1" "negative control R2-B1: stale mark skips the start and deep-repairs"
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
    reset cc2:kafka ; NOREG=1 ; SLOWUP=30
    T0=$SECONDS
    _health_datapipe_start_stopped
    ck "$([ $((SECONDS - T0)) -gt 400 ] && echo long || echo short)" long "negative control R2-S2: iteration-counted wait runs long"
else
    echo "SKIP: negative control needs git object $SECOND_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
