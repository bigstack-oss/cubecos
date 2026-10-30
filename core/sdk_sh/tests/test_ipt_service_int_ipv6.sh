#!/bin/bash
#
# Unit test for _set_ip6t_service_int (../modules/sdk_network.sh): the ports SERVICE-INT drops
# that also listen on IPv6 -- pcsd, zookeeper, lachesis's metrics and haproxy's galera check --
# are dropped there too, for every source, by a chain that goes first in ip6tables' INPUT and is
# hooked in once. Every port it drops is one the IPv4 chain drops, and network_ipt_serviceint
# builds both.
#
# Self-contained: extracts only the functions and records ip6tables calls instead of running
# them, so it needs no node.
#   Run: bash test_ipt_service_int_ipv6.sh   (exit 0 = pass)
#   SDK_NETWORK_SH=<file> runs it against another copy of sdk_network.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_NETWORK_SH:-$DIR/../modules/sdk_network.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

body="$(awk '/^_set_ip6t_service_int\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: _set_ip6t_service_int not extracted"; exit 1; }
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ip6tables stand-in: records each call; -C INPUT answers from $HOOKED, --list from $EXISTS
ip6tables() {
    echo "$*" >> "$T/calls"
    case "$*" in
        "-C INPUT -j SERVICE-INT") [ "$HOOKED" = y ] ;;
        "-n --list SERVICE-INT") [ "$EXISTS" = y ] ;;
        *) return 0 ;;
    esac
}
run() { HOOKED=$1 EXISTS=$2; : > "$T/calls"; _set_ip6t_service_int; }
rules() { grep '^-A SERVICE-INT ' "$T/calls" | sed 's/^-A SERVICE-INT //'; }

run n n
chk "a new chain is created" "$(grep -c '^-N SERVICE-INT$' "$T/calls")" "1"
chk "  and flushed" "$(grep -c '^-F SERVICE-INT$' "$T/calls")" "1"
chk "  drops pcsd, zookeeper, lachesis and the galera check" "$(rules | tr '\n' ';')" \
    "-p tcp --dport 2224 -j DROP;-p tcp --dport 2181 -j DROP;-p tcp --dport 9090 -j DROP;-p tcp --dport 13306 -j DROP;"
chk "  and accepts nothing" "$(rules | grep -c -v -- '-j DROP$')" "0"
chk "  hooked first in INPUT" "$(grep -c '^-I INPUT 1 -j SERVICE-INT$' "$T/calls")" "1"
chk "  and only through -I" "$(grep -c '^-A INPUT' "$T/calls")" "0"

run y y
chk "a rebuild flushes the existing chain without creating it" "$(grep -c '^-N SERVICE-INT$' "$T/calls") $(grep -c '^-F SERVICE-INT$' "$T/calls")" "0 1"
chk "  keeps the same four drops" "$(rules | wc -l)" "4"
chk "  and does not hook it twice" "$(grep -c '^-I INPUT' "$T/calls")" "0"

# Every IPv6 drop is a port the IPv4 chain drops for all but the cluster's own nodes
v4="$(awk '/^_set_ipt_service_int\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
for p in $(rules | sed -E 's/.*--dport ([0-9]+).*/\1/'); do
    chk "port $p is dropped by the IPv4 chain too" \
        "$(grep -E -- "--dport $p -j DROP|--dports ([0-9,:]*,)?$p(,[0-9,:]*)? -j DROP" <<<"$v4" | wc -l | tr -d ' ')" "1"
done

chk "network_ipt_serviceint builds both chains" \
    "$(awk '/^network_ipt_serviceint\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC" | grep -c -E '^\s+_set_ip6?t_service_int$')" "2"

echo "test_ipt_service_int_ipv6: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
