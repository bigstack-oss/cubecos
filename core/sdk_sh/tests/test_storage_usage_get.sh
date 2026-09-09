#!/bin/bash
#
# Unit test for storage_usage_get (../modules/sdk_storage.sh).
#
# This is what the hex_cli command and, later, cube-cos-api read. It queries
# the stored samples rather than collecting live, so the CLI and the GUI can
# never disagree -- and it reports the sample age, because a 15-minute sampler
# with no timestamp looks like a broken feature.
#
# With no argument it answers the per-pool question; with an instance id it
# answers that VM's, joining the disk rows with the guest row.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

for fn in _storage_usage_query storage_usage_get ; do
    b="$(awk "/^$fn\\(\\)/{p=1} p{print} p&&/^}/{exit}" "$M")"
    [ -n "$b" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$b"
done
TELEGRAF_DB=telegraf ; SRVTO=60 ; FORMAT=pretty
timeout(){ shift 3; "$@"; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
has(){ if echo "$2" | grep -qF "$3"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: [$2] lacks [$3]"; fi; }

Q=$(mktemp)
# the query text arrives in the q= argument, not in the URL
curl(){
    echo "$*" >> "$Q"
    case "$*" in
    *storage_pool_usage*)
      echo '{"results":[{"series":[{"name":"storage_pool_usage","tags":{"backend":"CubeStorage","pool":"cinder-volumes"},"columns":["time","last","stored_bytes","capacity_bytes","provisioned_bytes","replication_factor","reduction_ratio"],"values":[["2026-09-08T11:00:00Z",300,100,1000,500,3,null]]}]}]}' ;;
    *storage_usage_guest*)
      echo '{"results":[{"series":[{"name":"storage_usage_guest","tags":{"instance_id":"vm-1"},"columns":["time","last","guest_total_bytes","fs_count"],"values":[["2026-09-08T11:00:00Z",40,100,2]]}]}]}' ;;
    *storage_usage*)
      echo '{"results":[{"series":[{"name":"storage_usage","tags":{"instance_id":"vm-1","pool":"ephemeral-vms","kind":"ephemeral"},"columns":["time","last","provisioned_bytes","snapshot_bytes"],"values":[["2026-09-08T11:00:00Z",25,100,5]]}]}]}' ;;
    esac
}

out="$(storage_usage_get)"
chk "pool query issued"   "$(grep -c storage_pool_usage "$Q")"  "1"
has "reports the pool"    "$out" "cinder-volumes"
has "reports stored"      "$out" "100"
has "reports sample age"  "$out" "sampled"

: > "$Q"
out2="$(storage_usage_get vm-1)"
chk "disk query issued"   "$(grep -c 'from storage_usage where' "$Q")"   "1"
chk "guest query issued"  "$(grep -c storage_usage_guest "$Q")"  "1"
has "filters by instance" "$(cat "$Q")" "vm-1"
has "reports the pool row" "$out2" "ephemeral-vms"

FORMAT=json
out3="$(storage_usage_get)"
chk "json is valid"       "$(echo "$out3" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)" "ok"
has "json has backend"    "$out3" "CubeStorage"
has "json has sampledAt"  "$out3" "sampledAt"

rm -f "$Q"
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
