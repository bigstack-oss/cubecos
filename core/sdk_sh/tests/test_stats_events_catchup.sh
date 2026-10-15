#!/bin/bash
#
# Unit test for stats_events_catchup (../modules/sdk_stats.sh): a rebooted node copies the
# events it missed while down (last local point before boot - 10 min .. first local point
# after boot + 10 min) from every kapacitor peer into its local InfluxDB, one explicit
# ::field/::tag query per measurement and slice, within a wall-clock budget, writing to
# localhost only (never kapacitor).
#   Run: bash test_stats_events_catchup.sh
#
set -u
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
for fn in _stats_influx_peer_urls _stats_influx_query _stats_influx_columns _stats_influx_select \
          _stats_influx_json_to_lp _stats_influx_local_edge stats_events_catchup ; do
    b="$(sed -n "/^$fn()/,/^}/p" $D/../modules/sdk_stats.sh)"
    [ -n "$b" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$b"
done
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got [$2] want [$3]" ; FAILS=$((FAILS+1)) ; fi ; }

STATS_KAPACITOR_CONF=$T/kapacitor.conf
STATS_PROC_STAT=$T/stat
STATS_EVENTS_CATCHUP_LOCK=$T/lock
STATS_LOCAL_INFLUX=http://localhost:8086
STATS_EVENTS_CATCHUP_SLICE=3600
STATS_EVENTS_CATCHUP_MARGIN=600
STATS_EVENTS_CATCHUP_MAX_GAP=7200
STATS_EVENTS_CATCHUP_BUDGET=900
KAPCONF='[[influxdb]]
  enabled = true
  default = true
  name = "localhost"
  urls = ["http://localhost:8086"]
[[httppost]]
  url = "http://localhost:9092/kapacitor/v1/write?db=events"
[[influxdb]]
  name = "n2"
  urls = ["http://10.0.0.2:8086"]
[[influxdb]]
  name = "n3"
  urls = ["http://10.0.0.3:8086"]'
echo "$KAPCONF" > $STATS_KAPACITOR_CONF
BTIME=1790000000
NOW=$((BTIME + 5 * 3600))
echo "btime $BTIME" > $STATS_PROC_STAT
# date +%s: $NOW, plus $TICK s per call (wall-clock budget test)
TICK=0
date() {
    if [ "$1" = +%s ] ; then
        local c=$(cat $T/clock 2>/dev/null || echo 0) ; echo $((c + TICK)) > $T/clock ; echo $((NOW + c))
    else
        command date "$@"
    fi
}
log_info() { echo "$*" >> $T/info; }
log_warning() { echo "$*" >> $T/warn; }
INFLUX_UP=1
systemctl() { [ "$INFLUX_UP" = 1 ]; }
# newest local point before boot: system at boot-2m, audit older
LOCAL_LAST="{\"results\":[{\"series\":[{\"name\":\"system\",\"columns\":[\"time\",\"message\"],\"values\":[[$(( (BTIME - 120) * 1000000000 + 123 )),\"x\"]]},{\"name\":\"audit\",\"columns\":[\"time\",\"cmd\"],\"values\":[[$(( (BTIME - 900) * 1000000000 )),\"y\"]]}]}]}"
# oldest local point after boot: audit at boot+5m, system later
LOCAL_FIRST="{\"results\":[{\"series\":[{\"name\":\"audit\",\"columns\":[\"time\",\"cmd\"],\"values\":[[$(( (BTIME + 300) * 1000000000 + 7 )),\"y\"]]},{\"name\":\"system\",\"columns\":[\"time\",\"message\"],\"values\":[[$(( (BTIME + 400) * 1000000000 )),\"x\"]]}]}]}"
TAGS='{"results":[{"statement_id":0,"series":[{"name":"system","columns":["tagKey"],"values":[["host"],["key"],["phase"],["project_id"],["sub"]]}]}]}'
# project_id is both a field and a tag; v has two types across shards
FIELDS='{"results":[{"statement_id":0,"series":[{"name":"system","columns":["fieldKey","fieldType"],"values":[["message","string"],["n","integer"],["f","float"],["ok","boolean"],["project_id","string"],["v","integer"],["v","float"]]}]}]}'
# columns follow the select order (fields then tags); influx renames the duplicate project_id_1
ROWS='{"results":[{"statement_id":0,"series":[{"name":"system","columns":["time","message","n","f","ok","project_id","v","host","key","phase","project_id_1","sub"],"values":[[1790000000123456789,"node \"n1\" a\\b, c=d",3,2,true,"pf",7,"n1","CLU00009I","rebooting","pt",""],[1790000001000000000,null,null,null,null,null,null,"n1","CLU00009I",null,null,null]]}]}]}'
EMPTY_AT=""
# n2 holds the events n1 missed; n3 is down
curl() {
    local url="" q="" a
    for a in "$@" ; do
        case "$a" in http://*) url=$a ;; q=*) q=${a#q=} ;; esac
    done
    echo "$url $q" >> $T/calls
    case "$url" in
    */write*) cat >> $T/write.$(echo "$url" | sed 's/.*rp=\([a-z]*\).*/\1/') ; return 0 ;;
    http://10.0.0.3:8086/*) return 7 ;;
    http://localhost:8086/query)
        case "$q" in
        *"ORDER BY time DESC"*) echo "$LOCAL_LAST" ;;
        *) echo "$LOCAL_FIRST" ;;
        esac ;;
    http://10.0.0.2:8086/query)
        case "$q" in
        "SHOW MEASUREMENTS") echo '{"results":[{"statement_id":0,"series":[{"name":"measurements","columns":["name"],"values":[["system"]]}]}]}' ;;
        'SHOW TAG KEYS FROM "system"') echo "$TAGS" ;;
        'SHOW FIELD KEYS FROM "system"') echo "$FIELDS" ;;
        *"FROM \"def\".\"system\" WHERE time >= ${EMPTY_AT:-none}s"*) return 0 ;;
        *'FROM "def"."system"'*) echo "$ROWS" ;;
        *) echo '{"results":[{"statement_id":0}]}' ;;
        esac ;;
    esac
}
SEL='"message"::field,"n"::field,"f"::field,"ok"::field,"project_id"::field,"v"::field,"host"::tag,"key"::tag,"phase"::tag,"project_id"::tag,"sub"::tag'
peer_selects() { grep -o '10.0.0.2:8086/query SELECT .*' $T/calls | sed 's/^10.0.0.2:8086\/query //'; }
reset() { rm -f $T/calls $T/write.* $T/warn $T/info $T/clock; }

reset ; stats_events_catchup
# v has types integer+float across shards: typed by the JSON value
want='system,host=n1,key=CLU00009I,phase=rebooting,project_id=pt message="node \"n1\" a\\b, c=d",n=3i,f=2.0,ok=true,project_id="pf",v=7i 1790000000123456789'
check "missed event copied (ns, peer field types, escapes, tag/field by position, empty tag and null row skipped)" \
    "$(cat $T/write.def 2>/dev/null)" "$want"
check "empty hc rp writes nothing" "$(ls $T/write.hc 2>/dev/null)" ""
check "per-measurement explicit ::field/::tag query, no GROUP BY, window = gap only" \
    "$(peer_selects | head -1)" \
    "SELECT $SEL FROM \"def\".\"system\" WHERE time >= $((BTIME - 720))s AND time < $((BTIME + 900))s"
check "one slice per rp for a short gap" "$(peer_selects | grep -c 'FROM "def"\|FROM "hc"')" "2"
check "local last point before boot, bounded" \
    "$(grep -c "localhost:8086/query SELECT \* FROM \"def\"\./\.\*/ WHERE time < ${BTIME}s AND time > $((BTIME - 7 * 86400))s ORDER BY time DESC LIMIT 1" $T/calls)" "1"
check "local first point after boot, bounded" \
    "$(grep -c "localhost:8086/query SELECT \* FROM \"def\"\./\.\*/ WHERE time >= ${BTIME}s AND time < $((BTIME + 7200))s LIMIT 1" $T/calls)" "1"
check "writes go to local influx only" "$(grep '/write' $T/calls | grep -vc '^http://localhost:8086/write?db=events&rp=[a-z]*&precision=ns ')" "0"
check "nothing posted to kapacitor" "$(grep -c ':9092' $T/calls)" "0"
check "down peer warned, not fatal" "$(grep -c '10.0.0.3:8086 unreachable' $T/warn)" "1"
check "summary logged" "$(tail -1 $T/info | grep -o '1 points copied, 0 slices skipped')" "1 points copied, 0 slices skipped"

# no local point after boot: gap ends 2 h after boot, never past now
reset ; LOCAL_FIRST='{"results":[{"statement_id":0}]}'
stats_events_catchup
check "no local point after boot: end at boot + 2 h" "$(peer_selects | tail -1 | grep -o 'time < [0-9]*s$')" "time < $((BTIME + 7200))s"
check "sliced by the hour" "$(peer_selects | grep -c 'FROM "def"')" "3"
reset ; NOW=$((BTIME + 1800))
stats_events_catchup
check "no local point after boot, booted 30 min ago: end at now" "$(peer_selects | tail -1 | grep -o 'time < [0-9]*s$')" "time < $((BTIME + 1800))s"

# a slice with an empty reply (influx query timeout) is skipped, the rest still copied
reset ; NOW=$((BTIME + 5 * 3600)) ; EMPTY_AT=$((BTIME - 720))
stats_events_catchup
check "empty reply skipped with a warning" "$(grep -c "def.system .* from http://10.0.0.2:8086: no answer, skipped" $T/warn)" "1"
check "later slices still copied" "$(grep -c 1790000000123456789 $T/write.def)" "2"
check "skip counted in summary" "$(tail -1 $T/info | grep -o '[0-9]* slices skipped')" "1 slices skipped"
EMPTY_AT=""

# wall-clock budget: stop querying once spent
reset ; TICK=200
stats_events_catchup
check "stops at the budget" "$(tail -1 $T/info | grep -o 'stopped at the 900s budget')" "stopped at the 900s budget"
check "no query after the budget" "$(peer_selects | wc -l)" "4"
TICK=0

# no local point before boot: the hour before boot
reset ; LOCAL_LAST='{"results":[{"statement_id":0}]}'
stats_events_catchup
check "no local history: start an hour before boot" "$(peer_selects | head -1 | grep -o 'time >= [0-9]*s')" "time >= $((BTIME - 3600))s"

# held lock: no second run
reset ; exec 8>"$STATS_EVENTS_CATCHUP_LOCK" ; flock -n 8
( stats_events_catchup ) ; check "concurrent run: no-op" "$(cat $T/calls 2>/dev/null)" ""
exec 8>&-

# not an influx node / no peers: no-op
reset ; INFLUX_UP=0 ; stats_events_catchup
check "no influxdb: no-op" "$(cat $T/calls 2>/dev/null)" ""
INFLUX_UP=1 ; echo '[[influxdb]]
  urls = ["http://localhost:8086"]' > $STATS_KAPACITOR_CONF
stats_events_catchup
check "no peers (1-node): no-op" "$(cat $T/calls 2>/dev/null)" ""

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
