#!/bin/bash
#
# Unit test for network_ipt_serviceint (../modules/sdk_network.sh) as the rebuild a node join or
# leave runs (#2415): cubesys's cluster_map_update trigger calls it on every node, so a joined
# node's management IP is accepted ahead of the drops without waiting for a cluster start.
#   - two rebuilds never interleave: the second waits for the first to finish
#   - /run/iptables, which health_k3s restores when the live rules drift, is refreshed when it
#     exists, and is not created when it does not (cluster start writes it)
#   - config_cubesys.cpp registers the trigger, and the trigger runs network_ipt_serviceint
#
# Self-contained: extracts the function with /run/ pointed at a temp dir and stubs the chain
# builders and iptables-save, so it needs no node.
#   Run: bash test_ipt_service_int_rebuild.sh   (exit 0 = pass)
#   SDK_NETWORK_SH=<file> / CONFIG_CUBESYS_CPP=<file> run it against other copies.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_NETWORK_SH:-$DIR/../modules/sdk_network.sh}"
CPP="${CONFIG_CUBESYS_CPP:-$DIR/../../modules/config_cubesys.cpp}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

body="$(awk '/^network_ipt_serviceint\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: network_ipt_serviceint not extracted"; exit 1; }
eval "$(sed "s#/run/#$T/#g" <<<"$body")"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# each rebuild logs its start and end, and takes long enough to overlap another one
_set_ipt_service_int() { echo "start $ID" >> "$T/log"; sleep 0.5; echo "end $ID" >> "$T/log"; }
_set_ip6t_service_int() { :; }
_set_ipt_service_out() { :; }
iptables-save() { echo "-A SERVICE-INT -s 10.1.0.21/32 -j ACCEPT ($ID)"; }

ID=a network_ipt_serviceint &
sleep 0.1
ID=b network_ipt_serviceint &
wait
chk "two rebuilds run one after the other" "$(tr '\n' ';' < "$T/log")" "start a;end a;start b;end b;"
chk "no /run/iptables before cluster start: none is written" "$(ls "$T/iptables" 2>/dev/null | wc -l)" "0"

echo "old snapshot" > "$T/iptables"
ID=c network_ipt_serviceint
chk "an existing /run/iptables is replaced by the rebuilt rules" "$(cat "$T/iptables")" \
    "-A SERVICE-INT -s 10.1.0.21/32 -j ACCEPT (c)"
chk "  through a temp file that does not linger" "$(ls "$T" | grep -c '^iptables.new$')" "0"

chk "cubesys registers the cluster_map_update trigger" \
    "$(grep -c '^CONFIG_TRIGGER(cubesys, "cluster_map_update", ClusterMapUpdateMain);$' "$CPP")" "1"
chk "  which rebuilds SERVICE-INT" \
    "$(awk '/^ClusterMapUpdateMain\(/{p=1} p{print} p&&/^}/{exit}' "$CPP" | grep -c 'HEX_SDK " network_ipt_serviceint"')" "1"

echo "test_ipt_service_int_rebuild: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
