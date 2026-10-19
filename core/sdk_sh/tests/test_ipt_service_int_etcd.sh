#!/bin/bash
#
# Unit test for the etcd rules in _set_ipt_service_int (../modules/sdk_network.sh).
#
# SERVICE-INT keeps etcd's client (12379) and peer (12380) ports to cluster sources.
# Besides the allowlist every other port gets (lo, controller.ip, control.vip, the
# `cubectl node list` addresses), etcd also accepts the management subnet: a node
# joining the cluster dials 12379 -- and a control 12380 -- before it is in the node
# list, and a member only rebuilds this chain at its own cluster start. The subnet
# comes from net.if.addr/mask.<cubesys.management>; without it the DROP still lands.
#
# Self-contained: extracts only the function, records iptables calls instead of
# running them, and points its hex_tuning lookups at a fixture, so it needs no node.
#   Run: bash test_ipt_service_int_etcd.sh   (exit 0 = pass)
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

DROP='-p tcp --match multiport --dports 12379,12380 -j DROP'
accept() { echo "-p tcp --match multiport --dports 12379,12380 -s $1 -j ACCEPT"; }
BASE=('cubesys.controller.ip=10.32.150.1' 'cubesys.control.vip=10.32.150.10')
echo '-p tcp --dport 22 -j ACCEPT' > "$T/ipt_rc"

# 1. the management subnet is accepted for etcd, everything else dropped
run "${BASE[@]}" 'cubesys.management=eth0' 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0' \
    'net.if.addr.eth1=192.168.1.1' 'net.if.mask.eth1=255.255.255.0'
chk "1 subnet accept"             "$(has "$(accept 10.32.150.1/255.255.0.0)")" "1"
chk "1 etcd drop"                 "$(has "$DROP")" "1"
chk "1 accept before drop"        "$(before "$(accept 10.32.150.1/255.255.0.0)" "$DROP")" "y"
chk "1 other interface unused"    "$(grep -c 192.168.1.1 "$T/rules")" "0"

# 2. both sit with the other port drops: after the allowlist and the operator rules
chk "2 after node list"           "$(before '-s 10.32.150.3 -j ACCEPT' "$(accept 10.32.150.1/255.255.0.0)")" "y"
chk "2 after operator rules"      "$(before '-p tcp --dport 22 -j ACCEPT' "$(accept 10.32.150.1/255.255.0.0)")" "y"
chk "2 after the 25672 drop"      "$(before '-p tcp --dport 25672 -j DROP' "$(accept 10.32.150.1/255.255.0.0)")" "y"

# 3. the rest of the chain is unchanged, in the same order
KEPT=('-i lo -j ACCEPT' '-s 10.32.150.1 -j ACCEPT' '-s 10.32.150.10 -j ACCEPT'
      '-s 10.32.150.2 -j ACCEPT' '-s 10.32.150.3 -j ACCEPT' '-p tcp --dport 22 -j ACCEPT'
      '-p tcp --match multiport --dports 5900:5999 -j DROP' '-p tcp --dport 3306 -j DROP'
      '-p tcp --dport 13306 -j DROP' '-p tcp --dport 5672 -j DROP' '-p tcp --dport 5671 -j DROP'
      '-p tcp --dport 15672 -j DROP' '-p tcp --dport 25672 -j DROP'
      '-p icmp --icmp-type timestamp-request -j DROP')
for r in "${KEPT[@]}" ; do
    chk "3 kept: $r" "$(has "$r")" "1"
done
printf '%s\n' "${KEPT[@]}" > "$T/kept"   # rules other changes add to the chain don't count
chk "3 order kept"                "$(grep -xF -f "$T/kept" "$T/rules" | tr '\n' '|')" "$(printf '%s|' "${KEPT[@]}")"
chk "3 no other subnet accept"    "$(grep -c -- '-s 10.32.150.1/' "$T/rules")" "1"

# 4. no mask: fail closed -- no subnet accept, the drop stays
run "${BASE[@]}" 'cubesys.management=eth0' 'net.if.addr.eth0=10.32.150.1'
chk "4 no mask: no accept"        "$(grep -c -- '--dports 12379,12380 -s' "$T/rules")" "0"
chk "4 no mask: drop"             "$(has "$DROP")" "1"

# 5. no cubesys.management: same
run "${BASE[@]}" 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0'
chk "5 no mgmt: no accept"        "$(grep -c -- '--dports 12379,12380 -s' "$T/rules")" "0"
chk "5 no mgmt: drop"             "$(has "$DROP")" "1"

# 6. interface names with '.' (vlan) and '-' map to hex_tuning's variable names
run "${BASE[@]}" 'cubesys.management=eth0.100' 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0' \
    'net.if.addr.eth0.100=172.16.5.1' 'net.if.mask.eth0.100=255.255.255.0'
chk "6 vlan subnet"               "$(has "$(accept 172.16.5.1/255.255.255.0)")" "1"
chk "6 vlan: parent unused"       "$(grep -c -- '-s 10.32.150.1/' "$T/rules")" "0"
run "${BASE[@]}" 'cubesys.management=br-mgmt' 'net.if.addr.br-mgmt=10.20.0.5' 'net.if.mask.br-mgmt=255.255.252.0'
chk "6 dash subnet"               "$(has "$(accept 10.20.0.5/255.255.252.0)")" "1"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
