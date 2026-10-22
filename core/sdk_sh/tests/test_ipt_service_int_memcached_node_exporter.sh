#!/bin/bash
#
# Unit test for the memcached (11211) and node_exporter (9101) rules in _set_ipt_service_int
# (../modules/sdk_network.sh).
#
# Both listen on the management address and are used only from the cluster's own nodes:
# memcached by the OpenStack services, with no authentication, and node_exporter by
# prometheus on the controls, which also serves /debug/pprof there. So SERVICE-INT drops
# each for every source but the allowlist (lo, controller.ip, control.vip, the
# `cubectl node list` addresses) and the operator's rules, with no management-subnet
# exception like etcd's.
#
# Self-contained: extracts only the function, records iptables calls instead of
# running them, and points its hex_tuning lookups at a fixture, so it needs no node.
#   Run: bash test_ipt_service_int_memcached_node_exporter.sh   (exit 0 = pass)
#   SDK_NETWORK_SH=<file> runs it against another copy of sdk_network.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_NETWORK_SH:-$DIR/../modules/sdk_network.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

body="$(awk '/^_set_ipt_service_int\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: _set_ipt_service_int not extracted"; exit 1; }
body="${body//\/etc\/appliance\/state\/iptables_service-int/$T/ipt_rc}"
body="${body//source hex_tuning \$SETTINGS_TXT/_tuning}"
eval "$body"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture: $T/settings is /etc/settings.txt; _tuning sets T_<key> for every key
# under the prefix, '.' and '-' turned into '_', like hex_tuning
_tuning() {
    local k v
    while IFS='=' read -r k v ; do
        case "$k" in "$1"*) k="T_${k//./_}" ; printf -v "${k//-/_}" '%s' "$v" ;; esac
    done < "$T/settings"
}
_init_network_chain() { :; }
iptables() { echo "$*" >> "$T/calls"; }
cubectl() { echo '[{"ip":{"management":"10.32.150.2"}},{"ip":{"management":"10.32.150.3"}}]'; }

# run <settings lines...>: rebuild the chain, leave its rules in $T/rules
run() {
    # shellcheck disable=SC2046 # one name per word
    unset $(compgen -v T_)
    printf '%s\n' "$@" > "$T/settings"
    : > "$T/calls"
    _set_ipt_service_int
    grep '^-A SERVICE-INT ' "$T/calls" | sed 's/^-A SERVICE-INT //' > "$T/rules"
}
has() { grep -cxF -- "$1" "$T/rules"; }
at() { grep -nxF -- "$1" "$T/rules" | head -1 | cut -d: -f1; }
before() { local a b; a=$(at "$1"); b=$(at "$2"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && echo y || echo n; }

BASE=('cubesys.controller.ip=10.32.150.1' 'cubesys.control.vip=10.32.150.10')
echo '-p tcp --dport 22 -j ACCEPT' > "$T/ipt_rc"
ETCD='-p tcp --match multiport --dports 12379,12380 -j DROP'

run "${BASE[@]}" 'cubesys.management=eth0' 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0'
for port in 11211 9101 ; do
    DROP="-p tcp --dport $port -j DROP"
    # 1. the port is dropped, once
    chk "1 $port drop"                       "$(has "$DROP")" "1"
    # 2. after the allowlist: loopback, the controller, the VIP and every cluster node
    for a in '-i lo -j ACCEPT' '-s 10.32.150.1 -j ACCEPT' '-s 10.32.150.10 -j ACCEPT' \
             '-s 10.32.150.2 -j ACCEPT' '-s 10.32.150.3 -j ACCEPT' ; do
        chk "2 $port: $a before the drop"    "$(before "$a" "$DROP")" "y"
    done
    # 3. and after the operator's iptables_service-int rules
    chk "3 $port: operator rule first"       "$(before '-p tcp --dport 22 -j ACCEPT' "$DROP")" "y"
    # 4. no source exception for the port
    chk "4 $port: no accept"                 "$(grep -cE -- "--dports? ([0-9]+[,:])*$port\b.*-j ACCEPT" "$T/rules")" "0"
    # 5. with the other port drops, after MongoDB's and before etcd's
    chk "5 $port: after the 27017 drop"      "$(before '-p tcp --dport 27017 -j DROP' "$DROP")" "y"
    chk "5 $port: before the etcd drop"      "$(before "$DROP" "$ETCD")" "y"
done

# 6. a node without management settings still gets both drops
run "${BASE[@]}"
chk "6 no mgmt: 11211 drop"                  "$(has '-p tcp --dport 11211 -j DROP')" "1"
chk "6 no mgmt: 9101 drop"                   "$(has '-p tcp --dport 9101 -j DROP')" "1"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
