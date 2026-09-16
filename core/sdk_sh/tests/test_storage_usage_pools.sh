#!/bin/bash
#
# Unit test for storage_usage_cinder_pools (../modules/sdk_storage.sh).
#
# This is the universal tier: every Cinder driver publishes pool capacity via
# get_volume_stats, so a backend with no adapter of its own still reports
# honest totals instead of a blank. Nothing in CubeCOS read it before.
#
# The CLI does NOT expose the raw capabilities dict -- `volume backend pool
# list --long` returns a flattened summary (Name, Protocol, Thin/Thick,
# Capacity, Allocated, Max Over Ratio) with no free_capacity_gb or
# provisioned_capacity_gb, so the adapter reads those columns. Cinder's
# "Allocated" is allocated_capacity_gb: the sum of volume sizes it placed
# there, i.e. provisioned, not physical.
#
# Backend name comes from Name (cube@ceph#ceph -> ceph); a pool whose capacity
# the driver could not report must be null, never 0.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

SRVTO=60
b="$(awk '/^storage_usage_cinder_pools\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: storage_usage_cinder_pools not extracted"; exit 1; }
eval "$b"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
timeout(){ shift 3; "$@"; }

openstack(){
    cat <<'JSON'
[{"Name":"cube@ceph#ceph","Protocol":"ceph","Thick":"","Thin":true,
  "Volumes":"","Capacity":1471.18,"Allocated":809,"Max Over Ratio":"20.0"},
 {"Name":"cube@NFSStorage#NFSStorage","Protocol":"nfs","Thick":"","Thin":true,
  "Volumes":"","Capacity":100.0,"Allocated":40,"Max Over Ratio":"20.0"},
 {"Name":"cube@brokendrv#brokendrv","Protocol":"iscsi","Thick":"","Thin":"",
  "Volumes":"","Capacity":"","Allocated":"","Max Over Ratio":""}]
JSON
}

out="$(storage_usage_cinder_pools)"
g(){ echo "$out" | jq -r --arg b "$1" 'select(.backend==$b) | '"$2"; }

chk "row count"        "$(echo "$out" | grep -c .)"                    "3"
chk "ceph backend name" "$(g ceph .backend)"                           "ceph"
chk "nfs backend name" "$(g NFSStorage .backend)"                      "NFSStorage"
chk "backend_type"     "$(g ceph .backend_type)"                       "cinder"
chk "scope"            "$(g ceph .scope)"                              "pool"
chk "pool full name"   "$(g ceph .pool)"                               "cube@ceph#ceph"
chk "capacity bytes"   "$(g NFSStorage .capacity_bytes)"               "107374182400"
chk "provisioned bytes" "$(g NFSStorage .provisioned_bytes)"           "42949672960"
chk "oversub ratio"    "$(g NFSStorage .max_over_subscription_ratio)"  "20.0"
chk "thin flag"        "$(g NFSStorage .thin)"                         "true"
chk "confidence exact" "$(g NFSStorage .confidence)"                   "exact"
# a driver that reported nothing must not read as an empty 0-byte pool
chk "broken capacity null" "$(g brokendrv .capacity_bytes)"            "null"
chk "broken confidence" "$(g brokendrv .confidence)"                   "unavailable"
chk "ceph capacity"    "$(g ceph .capacity_bytes)"                     "1579667496632"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
