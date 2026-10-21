#!/bin/bash
#
# Unit test for the MongoDB rule in _set_ipt_service_int (../modules/sdk_network.sh).
#
# Nothing outside the cluster uses 27017: mongod binds the management address, haproxy
# listens on <VIP>:27017, and their clients are cube-cos-api and mongosh on the nodes. So
# SERVICE-INT drops 27017 for every source but the allowlist (lo, controller.ip,
# control.vip, the `cubectl node list` addresses) and the operator's rules. Unlike etcd's,
# the drop has no management-subnet exception: that is where scanners sit.
#
# Self-contained: extracts only the function, records iptables calls instead of
# running them, and points its hex_tuning lookups at a fixture, so it needs no node.
#   Run: bash test_ipt_service_int_mongodb.sh   (exit 0 = pass)
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

DROP='-p tcp --dport 27017 -j DROP'
BASE=('cubesys.controller.ip=10.32.150.1' 'cubesys.control.vip=10.32.150.10')
echo '-p tcp --dport 22 -j ACCEPT' > "$T/ipt_rc"

# 1. 27017 is dropped, once
run "${BASE[@]}" 'cubesys.management=eth0' 'net.if.addr.eth0=10.32.150.1' 'net.if.mask.eth0=255.255.0.0'
chk "1 mongodb drop"                 "$(has "$DROP")" "1"

# 2. the allowlist comes first: loopback, the controller, the VIP (haproxy's 27017 listener
#    is reached at it), and every cluster node, so the replica set and cube-cos-api still reach it
for a in '-i lo -j ACCEPT' '-s 10.32.150.1 -j ACCEPT' '-s 10.32.150.10 -j ACCEPT' \
         '-s 10.32.150.2 -j ACCEPT' '-s 10.32.150.3 -j ACCEPT' ; do
    chk "2 $a before the drop"       "$(before "$a" "$DROP")" "y"
done

# 3. and the operator's iptables_service-int rules, so a site can still open the port
chk "3 operator rule before the drop" "$(before '-p tcp --dport 22 -j ACCEPT' "$DROP")" "y"

# 4. no source exception for 27017: not the management subnet etcd gets, not any other
chk "4 no 27017 accept"              "$(grep -cE -- '--dports? ([0-9]+[,:])*27017\b.*-j ACCEPT' "$T/rules")" "0"

# 5. it sits with the other port drops, after RabbitMQ's and before etcd's
chk "5 after the 25672 drop"         "$(before '-p tcp --dport 25672 -j DROP' "$DROP")" "y"
chk "5 before the etcd drop"         "$(before "$DROP" '-p tcp --match multiport --dports 12379,12380 -j DROP')" "y"

# 6. a node without management settings still gets the drop
run "${BASE[@]}"
chk "6 no mgmt: mongodb drop"        "$(has "$DROP")" "1"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
