#!/bin/bash
#
# Unit test for the ceph side of cluster > remove_node (../modules/sdk_ceph.sh):
#   ceph_host_remove_precheck: names each pool that would keep fewer failure domains than
#     copies without the node (k+m for an erasure-coded pool), reads the root and the failure
#     domain from the pool's CRUSH rule, device class shadow roots included, counts only OSDs
#     that are in, and leaves alone a pool the node's OSDs cannot serve (cubecos#2423)
#   ceph_osd_host_remove: purges the node's OSDs only once safe-to-destroy passes, never waits
#     forever, purges nothing on a timeout, removes the host bucket, and reads a ceph it
#     cannot reach as a failure rather than as "nothing to remove" (cubecos#679)
#
# Self-contained: extracts the functions and answers their ceph calls from fixtures, so it
# needs no node.
#   Run: bash test_ceph_node_remove.sh   (exit 0 = pass)
#   SDK_CEPH_SH=<file> runs it against another copy of sdk_ceph.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_CEPH_SH:-$DIR/../modules/sdk_ceph.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for f in ceph_host_remove_precheck ceph_osd_host_remove ; do
    body="$(awk "/^$f\(\)/{p=1} p{print} p&&/^}/{exit}" "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# fixture <spec>: hosts as name:hdd,ssd OSD counts, e.g. "h1:2,1 h2:2,0"; OUT lists OSD ids
# that are out. Writes the crush tree (with device class shadow roots) and the osd dump.
fixture() {
    SPEC="$1" OUT="${OUT:-}" python3 - "$T" <<'PY'
import json, os, sys
t = sys.argv[1]; out = {int(x) for x in os.environ["OUT"].split()}
nodes = []; osds = []; nid = -100; oid = 0
roots = {"": {"id": -1, "name": "default", "type": "root", "children": []},
         "hdd": {"id": -2, "name": "default~hdd", "type": "root", "children": []},
         "ssd": {"id": -3, "name": "default~ssd", "type": "root", "children": []}}
for h in os.environ["SPEC"].split():
    name, counts = h.split(":")
    hdd, ssd = (int(c) for c in counts.split(","))
    host = {"id": nid, "name": name, "type": "host", "children": []}; nid -= 1
    roots[""]["children"].append(host["id"]); nodes.append(host)
    for cls, n in (("hdd", hdd), ("ssd", ssd)):
        shadow = {"id": nid, "name": name + "~" + cls, "type": "host", "children": []}; nid -= 1
        roots[cls]["children"].append(shadow["id"]); nodes.append(shadow)
        for _ in range(n):
            for b in (host, shadow): b["children"].append(oid)
            nodes.append({"id": oid, "name": "osd.%d" % oid, "type": "osd", "crush_weight": 0.02})
            osds.append({"osd": oid, "up": 1, "in": 0 if oid in out else 1}); oid += 1
nodes += roots.values()
json.dump({"nodes": nodes, "stray": []}, open(t + "/tree", "w"))
json.dump({"osds": osds}, open(t + "/osds", "w"))
PY
}
RULES='[{"rule_id":0,"steps":[{"op":"take","item":-1,"item_name":"default"},{"op":"chooseleaf_firstn","num":0,"type":"host"},{"op":"emit"}]},
        {"rule_id":1,"steps":[{"op":"take","item":-3,"item_name":"default~ssd"},{"op":"chooseleaf_firstn","num":0,"type":"host"},{"op":"emit"}]},
        {"rule_id":2,"steps":[{"op":"take","item":-1,"item_name":"default"},{"op":"chooseleaf_indep","num":0,"type":"host"},{"op":"emit"}]},
        {"rule_id":3,"steps":[{"op":"take","item":-1,"item_name":"default"},{"op":"choose_firstn","num":0,"type":"osd"},{"op":"emit"}]}]'
CEPH=ceph_stub
ceph_stub() {
    case "$*" in
        "osd crush tree --show-shadow -f json") cat "$T/tree" ;;
        "osd crush rule dump -f json") echo "$RULES" ;;
        "osd pool ls detail -f json") echo "$POOLS" ;;
        "osd dump -f json") cat "$T/osds" ;;
    esac
}
precheck() { OUT_LINES=$(ceph_host_remove_precheck "$1") ; rc=$? ; }

fixture "h1:2,1 h2:2,1 h3:2,0 h4:2,0"
POOLS='[{"pool_name":"rbd","size":3,"crush_rule":0},{"pool_name":"cache","size":2,"crush_rule":1}]'
precheck h4
chk "4 hosts, size 3, one removed: allowed" "$rc [$OUT_LINES]" "0 []"
precheck h1
chk "an ssd pool of size 2 on two ssd hosts: removing one of them is refused" "$rc [$OUT_LINES]" \
    "1 [pool cache needs 2 hosts, 1 would remain without h1]"
POOLS='[{"pool_name":"cache","size":3,"crush_rule":1}]'
precheck h4
chk "a pool already short, but the node has no OSD it can use: allowed" "$rc [$OUT_LINES]" "0 []"

fixture "h1:2,0 h2:2,0 h3:2,0 h4:2,0 h5:2,0"
POOLS='[{"pool_name":"default.rgw.buckets.data","size":5,"crush_rule":2},{"pool_name":"rbd","size":3,"crush_rule":0}]'
precheck h5
chk "erasure-coded k=3 m=2 on 5 hosts, one removed (cubecos#2423): refused, that pool only" "$rc [$OUT_LINES]" \
    "1 [pool default.rgw.buckets.data needs 5 hosts, 4 would remain without h5]"

OUT="6 7" fixture "h1:2,0 h2:2,0 h3:2,0 h4:2,0"
POOLS='[{"pool_name":"rbd","size":3,"crush_rule":0}]'
precheck h1
chk "a host whose OSDs are all out is not a failure domain" "$rc [$OUT_LINES]" "1 [pool rbd needs 3 hosts, 2 would remain without h1]"

fixture "h1:2,0 h2:1,0"
POOLS='[{"pool_name":"rbd","size":3,"crush_rule":3}]'
precheck h1
chk "an osd failure domain counts OSDs" "$rc [$OUT_LINES]" "1 [pool rbd needs 3 osds, 1 would remain without h1]"

CEPH=dead_ceph
dead_ceph() { return 1; }
precheck h1
chk "a ceph that cannot be read fails the check" "$rc" "1"

# ceph_osd_host_remove
sleep() { :; }
CEPH=osd_stub
osd_stub() {
    case "$*" in
        "osd tree -f json") [ "$TREE_OK" = y ] || return 1; echo "{\"nodes\":[{\"type\":\"host\",\"name\":\"$BUCKET\"}]}" ;;
        "osd ls-tree "*) echo "$IDS" | tr ' ' '\n' ;;
        "osd safe-to-destroy "*) SAFE_CALLS=$((SAFE_CALLS + 1)); echo "$SAFE_CALLS" > "$T/safe"; [ "$SAFE_CALLS" -gt "$SAFE_AFTER" ] ;;
        "pg stat") echo "100 pgs: 100 active+clean" ;;
        *) echo "ceph $*" >> "$T/calls" ;;
    esac
}
remove() {   # host bucket ids safe_after timeout tree_ok
    BUCKET=$2 IDS=$3 SAFE_AFTER=$4 TREE_OK=${6:-y} SAFE_CALLS=0
    : > "$T/calls"
    ceph_osd_host_remove "$1" "$5" > "$T/out" 2> "$T/err"
    rc=$?
}
calls() { grep '^ceph ' "$T/calls" | tr '\n' ';'; }

remove n1 n1 "24 25" 3 3600
chk "OSDs purged once safe-to-destroy passes, then the host bucket goes" "$rc $(calls)" \
    "0 ceph osd out 24 25;ceph osd purge 24 --yes-i-really-mean-it;ceph osd purge 25 --yes-i-really-mean-it;ceph osd crush rm n1;"
remove n1 n1 "24 25" 1000 60
chk "never safe within the bound: fails, OSDs stay out and nothing is purged" "$rc $(calls)" "1 ceph osd out 24 25;"
chk "  and says why" "$(grep -c 'stay out' "$T/err")" "1"
remove n1 other "" 0 60
chk "no host bucket: nothing to do" "$rc $(calls)" "0 "
remove n1 n1 "" 0 60 n
chk "a ceph that cannot be read is a failure, not an empty host" "$rc $(calls)" "1 "
remove n1 n1 "" 0 60
chk "a host bucket without OSDs is removed" "$rc $(calls)" "0 ceph osd crush rm n1;"

echo "test_ceph_node_remove: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
