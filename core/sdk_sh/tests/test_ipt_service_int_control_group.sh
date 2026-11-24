#!/bin/bash
#
# Unit test for _set_ipt_service_int (../modules/sdk_network.sh): every control in the control
# group set at install (cubesys.control.addrs) is accepted, not only the nodes already in
# `cubectl node list`. cluster_map_update rebuilds SERVICE-INT on each add (#2415), and a control
# enters the node list only when its own join completes, so a rebuild between two control joins
# used to drop the control still joining -- and its rabbitmq join_cluster on 25672 with it.
#   - with c1-c3 in the group but only c1 and c2 in the node list, c3 is accepted
#   - each accept comes before the drops, and an address in both lists is accepted once
#   - a node outside the group (a compute) is accepted from the node list as before
#   - without cubesys.control.addrs the node list alone decides, as before
#
# Self-contained: extracts the function and stubs iptables, hex_tuning and cubectl, so it needs
# no node.
#   Run: bash test_ipt_service_int_control_group.sh   (exit 0 = pass)
#   SDK_NETWORK_SH=<file> runs it against another copy.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_NETWORK_SH:-$DIR/../modules/sdk_network.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

body="$(awk '/^_set_ipt_service_int\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: _set_ipt_service_int not extracted"; exit 1; }
eval "$(sed "s#/etc/appliance/state/#$T/#g" <<<"$body")"
: > "$T/iptables_service-int"

# `source hex_tuning <file> <key>` sets T_<key, dots and dashes as underscores> from "<key> = <value>"
mkdir -p "$T/bin"
cat > "$T/bin/hex_tuning" <<'EOF'
_v=$(awk -F' = ' -v k="$2" '$1 == k { print $2 }' "$1")
eval "T_${2//[.-]/_}=\"\$_v\""
EOF
PATH="$T/bin:$PATH"
SETTINGS_TXT="$T/settings.txt"

_init_network_chain() { :; }
iptables() { [ "$1" = -A ] && { shift; echo "$*" >> "$T/rules"; }; return 0; }
cubectl() { printf '%s\n' "$NODES"; }
node() { printf '{"hostname":"%s","ip":{"management":"%s"}}' "$1" "$2"; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
accepts() { grep -E '^SERVICE-INT -s 10\.' "$T/rules" | awk '{print $3}' | tr '\n' ' '; }
before_drop() { awk -v a="-s $1 " 'index($0, a) {s=NR} /--dport 25672 -j DROP/ {d=NR} END {print (s && d && s < d) ? "yes" : "no"}' "$T/rules"; }

# c3 still joining: the group has c1-c3, the node list has c1 and c2 (the rebuild for c2's add)
printf 'cubesys.control.vip = 10.1.0.100\ncubesys.control.addrs = 10.1.0.1,10.1.0.2,10.1.0.3\n' > "$SETTINGS_TXT"
NODES="[$(node c1 10.1.0.1),$(node c2 10.1.0.2)]"
: > "$T/rules"; _set_ipt_service_int
chk "a control still joining is accepted" "$(accepts)" "10.1.0.100 10.1.0.1 10.1.0.2 10.1.0.3 "
chk "  before rabbitmq's 25672 drop" "$(before_drop 10.1.0.3)" "yes"

# all joined, plus a compute outside the group: each address accepted once
NODES="[$(node c1 10.1.0.1),$(node c2 10.1.0.2),$(node c3 10.1.0.3),$(node p1 10.1.0.4)]"
: > "$T/rules"; _set_ipt_service_int
chk "group and node list together, each once" "$(accepts)" "10.1.0.100 10.1.0.1 10.1.0.2 10.1.0.3 10.1.0.4 "

# no control group in the settings: the node list alone, as before
printf 'cubesys.control.vip = 10.1.0.100\n' > "$SETTINGS_TXT"
NODES="[$(node cc1 10.1.0.1),$(node cn1 10.1.0.21)]"
: > "$T/rules"; _set_ipt_service_int
chk "without cubesys.control.addrs the node list decides" "$(accepts)" "10.1.0.100 10.1.0.1 10.1.0.21 "

echo "test_ipt_service_int_control_group: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
