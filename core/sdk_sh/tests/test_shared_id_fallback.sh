#!/bin/bash
#
# Unit test for shared_id in ../../main/proj_functions.
#
# shared_id is the control plane's address as the shell sees it: 43 call sites use it for
# influx reads, kapacitor writes and remote_run to a control. It read only
# cubesys.control.vip and fell back to the hostname, but compute and storage nodes carry no
# control.vip -- theirs is cubesys.controller.ip, which is also what hex_config's SHARED_ID
# resolves to there. On QA 10.32.36.10 both computes answered their own hostname, so
# instance_metrics_collect POSTed to <compute>:9092, where nothing listens, and no VM series
# reached InfluxDB (#1596).
#
# Self-contained: extracts only the function, and points its cache file and its hex_tuning
# lookups at a fixture, so it needs no node.
#   Run: bash test_shared_id_fallback.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../../main/proj_functions"
T=$(mktemp -d)

body="$(awk '/^shared_id\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: shared_id not extracted"; exit 1; }
body="${body//\/run\/shared_id/$T/shared_id}"
body="${body//source hex_tuning \/etc\/settings.txt/_tuning}"
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture: SETTINGS[key]=value is /etc/settings.txt; _tuning sets T_<key> like hex_tuning
declare -A SETTINGS
_tuning() { local v="T_${1//./_}"; printf -v "$v" '%s' "${SETTINGS[$1]:-}"; }
Quiet() { [ "$1" = -n ] && shift; eval "$@" >/dev/null 2>&1; }
hostname() { echo testhost; }
reset() { SETTINGS=() ; rm -f "$T/shared_id" ; unset T_cubesys_control_vip T_cubesys_controller_ip ; }

# 1. HA control: the VIP
reset; SETTINGS=([cubesys.control.vip]=10.32.36.10)
chk "1 control"       "$(shared_id)" "10.32.36.10"

# 2. compute: no control.vip, the VIP is cubesys.controller.ip (cube36's p4/p5)
reset; SETTINGS=([cubesys.controller.ip]=10.32.36.10)
chk "2 compute"       "$(shared_id)" "10.32.36.10"
chk "2 cached"        "$(cat "$T/shared_id")" "10.32.36.10"

# 3. storage node, same shape
reset; SETTINGS=([cubesys.controller.ip]=10.1.0.10)
chk "3 storage"       "$(shared_id)" "10.1.0.10"

# 4. single non-HA control: neither key, still the hostname
reset
chk "4 non-HA ctrl"   "$(shared_id)" "testhost"

# 5. a cached value is returned as is, and "unconfigured" is recomputed
reset; echo -n cached > "$T/shared_id"; SETTINGS=([cubesys.controller.ip]=10.32.36.10)
chk "5 cache"         "$(shared_id)" "cached"
echo -n unconfigured > "$T/shared_id"
chk "5 unconfigured"  "$(shared_id)" "10.32.36.10"

rm -rf "$T"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: shared_id fallback" ; exit 0 ; } || exit 1
