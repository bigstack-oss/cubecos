#!/bin/bash
#
# Unit test for the cluster-internal service rules in _set_ipt_service_int
# (../modules/sdk_network.sh): the OVS/OVN databases, RabbitMQ's epmd and prometheus endpoint,
# the exporters prometheus scrapes, haproxy's stats page, pcsd, zookeeper and kafka, the
# OpenSearch and ceph dashboards (which users reach through haproxy), lachesis's metrics, and
# named's rndc and designate-mdns, which only the controls use.
#
# Each is used only from the cluster's own nodes, so SERVICE-INT drops it for every source but
# the allowlist (lo, controller.ip, control.vip, the `cubectl node list` addresses) and the
# operator's rules. k3s is left alone: its pods reach 6443 and 10250 from the pod network, which
# the allowlist does not cover. DNS (53) stays open: tenant VMs use the cluster's named.
#
# Self-contained: extracts only the function, records iptables calls instead of
# running them, and points its hex_tuning lookups at a fixture, so it needs no node.
#   Run: bash test_ipt_service_int_internal_services.sh   (exit 0 = pass)
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
RULES=('-p tcp --match multiport --dports 6640,6641,6642 -j DROP'
       '-p tcp --match multiport --dports 4369,15692 -j DROP'
       '-p tcp --match multiport --dports 9117,9150,9283,9290,9587 -j DROP'
       '-p tcp --dport 9100 -j DROP'
       '-p tcp --dport 2224 -j DROP'
       '-p tcp --match multiport --dports 2181,9095 -j DROP'
       '-p tcp --match multiport --dports 5601,7443 -j DROP'
       '-p tcp --dport 9090 -j DROP'
       '-p tcp --match multiport --dports 953,5354 -j DROP')

run "${BASE[@]}" 'cubesys.management=eth0' 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0'
for DROP in "${RULES[@]}" ; do
    # 1. the rule is there, once
    chk "1 [$DROP]"                          "$(has "$DROP")" "1"
    # 2. after the allowlist: loopback (haproxy reaches the dashboards over it), the
    #    controller, the VIP and every cluster node
    for a in '-i lo -j ACCEPT' '-s 10.32.150.1 -j ACCEPT' '-s 10.32.150.10 -j ACCEPT' \
             '-s 10.32.150.2 -j ACCEPT' '-s 10.32.150.3 -j ACCEPT' ; do
        chk "2 [$DROP] after $a"             "$(before "$a" "$DROP")" "y"
    done
    # 3. after the operator's rules, and with the other port drops, before etcd's
    chk "3 [$DROP] after operator rules"     "$(before '-p tcp --dport 22 -j ACCEPT' "$DROP")" "y"
    chk "3 [$DROP] after the 9101 drop"      "$(before '-p tcp --dport 9101 -j DROP' "$DROP")" "y"
    chk "3 [$DROP] before the etcd drop"     "$(before "$DROP" "$ETCD")" "y"
done

# 4. nothing opens these ports, and k3s (6443, 10250, its etcd on 2379/2380) and DNS (53) are
#    not dropped
for p in 6640 6641 6642 4369 15692 9117 9150 9283 9290 9587 9100 2224 2181 9095 5601 7443 9090 953 5354 ; do
    chk "4 no accept for $p"                 "$(grep -cE -- "--dports? ([0-9]+[,:])*$p\b.*-j ACCEPT" "$T/rules")" "0"
done
for p in 6443 10250 2379 2380 53 ; do
    chk "4 $p not dropped"                   "$(grep -cE -- "--dports? ([0-9]+[,:])*$p\b.*-j DROP" "$T/rules")" "0"
done

# 5. a node without management settings still gets every rule
run "${BASE[@]}"
for DROP in "${RULES[@]}" ; do
    chk "5 no mgmt: [$DROP]"                 "$(has "$DROP")" "1"
done

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
