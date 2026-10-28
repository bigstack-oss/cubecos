#!/bin/bash
#
# Unit test for the feature-flag part of health_rabbitmq_check (../modules/sdk_health.sh),
# #2164: a broker that still has a stable flag disabled is NG (code 4) naming the flags, and
# any other rabbitmq fault's code wins over it. Reported only: nothing enables them.
# Self-contained: stubs $HEX_SDK, $HEX_CFG and is_remote_running.
# Run: bash test_sdk_health_rabbitmq_flags.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"
extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }
for fn in health_rabbitmq_check ; do
    eval "$(extract $fn "$SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done
PROG=test; declare -A ERR_CODE; source "$DIR/../modules/errcodes"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
ERR_LOGSIZE=200
OFF="" RUNNING="c1 c2 c3" PARTS=""
HEX_SDK=hexsdk; hexsdk(){ echo "sdk $*" >> $T/calls
    case "$1" in os_rabbitmq_flags_disabled) [ "$OFF" = DOWN ] && return 1 ; echo "$OFF" ;; esac; }
HEX_CFG=hexcfg; hexcfg(){ echo "cfg $*" >> $T/calls
    case "$1" in status_rabbitmq)
        jq -nc --arg r "$RUNNING" --arg p "$PARTS" '{running_nodes: ($r | split(" ") | map(select(length>0)) | map("rabbit@" + .)),
                                                    partitions: ($p | split(" ") | map(select(length>0)))}' ;; esac; }
is_remote_running(){ [[ " $RUNNING " == *" $1 "* ]]; }
Quiet(){ [ "$1" = -n ] && shift; "$@"; }
_health_fail_log(){ echo "$ERR_CODE|$ERR_MSG" > $T/result; }
run(){ ERR_CODE=0 ERR_MSG="" ERR_LOG=""; : > $T/calls; health_rabbitmq_check; cat $T/result; }

chk "all on: ok" "$(run)" "0|"
OFF="direct_exchange_routing_v2 feature_flags_v2"
chk "six off: NG 4 names them" "$(run)" "4|feature flags disabled: direct_exchange_routing_v2 feature_flags_v2\n"
chk "six off: nothing enables them" "$(grep -c rabbitmq_feature_flags $T/calls)" 0
chk "code 4 reads" "${ERR_CODE[rabbitmq,4]}" "feature flags disabled"
RUNNING="c1 c2"
chk "a node down too: its code wins" "$(run | cut -d'|' -f1)" "2"
RUNNING="c1 c2 c3" OFF=DOWN
chk "broker not answering: not a flag NG" "$(run)" "0|"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
