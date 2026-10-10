#!/bin/bash
#
# Unit test for check_service_stats() in ../../main/proj_functions, covering
# #1779: the periodic round (telegraf -> hex_sdk check_service_stats every
# 10 min) never ran health_prometheus_check, health_lachesis_check or
# health_thanos_check, so their _health_*_auto_repair never fired and a stopped
# prometheus stayed down indefinitely.
#
# Self-contained: extracts check_service_stats and check_service, stubs
# is_control_node / is_edge_node, and points HEX_SDK at a function that records
# which health_<svc>_check the round calls, so it needs no cluster.
#
# Also asserts that every service the round names has a health_<svc>_check in
# ../modules/: an unresolved name makes hex_sdk print its whole Usage banner.
#
# The last section is a negative control against the round as it was at
# 5fcaa461, before the fix. It is skipped when that git object is unavailable.
#
#   Run: bash test_check_service_stats_services.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../../main/proj_functions"
MODS="$DIR/../modules"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

load() { # load <file> <function>...
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}
load "$SRC" check_service_stats check_service

HOSTNAME=cc1
EDGE=1
is_control_node() { return 0; }
is_edge_node() { [ "$EDGE" = "1" ]; }
CALLED=""
fake_sdk() {
    case "$1" in
        health_*_check) local s=${1#health_} ; CALLED+="${s%_check} " ;;
        health_errcode_lookup) echo "ok" ;;
    esac
}
HEX_SDK=fake_sdk

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
has() { case " $CALLED " in *" $1 "*) echo yes ;; *) echo no ;; esac; }

OUTF=$(mktemp)
BASE_SRC=$(mktemp)
trap 'rm -f "$OUTF" "$BASE_SRC"' EXIT
# run in this shell (not $( )) so the stub's CALLED survives
round() { CALLED="" ; check_service_stats > "$OUTF" ; OUT="$(cat "$OUTF")"; }

# ---- 1. the round checks prometheus, lachesis and thanos (#1779) ----
for EDGE in 1 0 ; do
    round
    for s in prometheus lachesis thanos ; do
        ck "$(has $s)" yes "edge=$EDGE: round runs health_${s}_check"
        ck "$(echo "$OUT" | grep -c "\"service\": \"$s\"")" 1 "edge=$EDGE: one $s row"
    done
done

# ---- 2. the existing monitoring services are still there ----
EDGE=1 round
for s in zookeeper kafka telegraf influxdb kapacitor grafana filebeat auditbeat logstash ; do
    ck "$(has $s)" yes "round still runs health_${s}_check"
done

# ---- 3. the round's document is still a JSON array ----
if command -v jq >/dev/null 2>&1 ; then
    ck "$(echo "$OUT" | jq -r 'map(select(.service == "prometheus")) | length')" 1 "round output parses as JSON"
fi

# ---- 4. every service the round names has a health_<svc>_check ----
EDGE=1 round
for s in $CALLED ; do
    grep -q "^health_${s}_check()" "$MODS"/*.sh || { fail=$((fail+1)); echo "FAIL: no health_${s}_check for round service $s"; }
done

# ---- 5. negative control: the round before the fix skips prometheus ----
BASE_REF=5fcaa461
if git -C "$DIR" show "$BASE_REF:core/main/proj_functions" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" check_service_stats
    EDGE=1 round
    ck "$(has prometheus)" no "negative control: unfixed round skips prometheus"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
