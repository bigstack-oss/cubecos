#!/bin/bash
#
# Unit test for storage_usage_ceph_pools in ../modules/sdk_storage.sh: a replicated
# pool's replication_factor is its configured size, also on a near-empty pool
# whose raw/stored ratio is far off, on both the prometheus and the ceph df path.
# Fakes ceph and prometheus; needs jq, no cluster.
#   Run: bash test_storage_usage_pool_repl.sh
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_storage.sh"
eval "$(awk '/^storage_usage_ceph_pools\(\)/ {f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t storage_usage_ceph_pools)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

FAILS=0
CEPH=fake_ceph
STORAGE_USAGE_CEPH_POOLS="cinder-volumes glance-images"
Debug() { :; }
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }
# cinder-volumes: 133 B stored, 12 KiB raw (metadata only); glance-images: plain 3x
fake_ceph() {
    case "$*" in
        "osd pool ls detail --format json")
            echo '[{"pool_name":"cinder-volumes","type":1,"size":3},{"pool_name":"glance-images","type":1,"size":3}]' ;;
        "df detail --format json")
            echo '{"pools":[{"name":"cinder-volumes","stats":{"stored":133,"bytes_used":12288,"max_avail":100}},
                            {"name":"glance-images","stats":{"stored":1000,"bytes_used":3000,"max_avail":100}}]}' ;;
    esac
}
repl() { echo "$1" | jq -r "select(.pool == \"$2\") | .replication_factor"; }

# 1: prometheus path
_storage_usage_promql() {
    case "$1" in
        ceph_pool_metadata) echo '[{"metric":{"pool_id":"1","name":"cinder-volumes"}},{"metric":{"pool_id":"2","name":"glance-images"}}]' ;;
        *) echo '[{"metric":{"__name__":"ceph_pool_stored","pool_id":"1"},"value":[0,"133"]},
                  {"metric":{"__name__":"ceph_pool_bytes_used","pool_id":"1"},"value":[0,"12288"]},
                  {"metric":{"__name__":"ceph_pool_stored","pool_id":"2"},"value":[0,"1000"]},
                  {"metric":{"__name__":"ceph_pool_bytes_used","pool_id":"2"},"value":[0,"3000"]}]' ;;
    esac
}
OUT=$(storage_usage_ceph_pools)
check "prometheus: near-empty pool reports its size" "$(repl "$OUT" cinder-volumes)" 3
check "prometheus: full pool reports its size" "$(repl "$OUT" glance-images)" 3

# 2: ceph df fallback
_storage_usage_promql() { :; }
OUT=$(storage_usage_ceph_pools)
check "ceph df: near-empty pool reports its size" "$(repl "$OUT" cinder-volumes)" 3

# 3: pool sizes unavailable -> previous derived ratio
fake_ceph() { [ "$1" = df ] && echo '{"pools":[{"name":"glance-images","stats":{"stored":1000,"bytes_used":2000,"max_avail":1}}]}'; }
OUT=$(storage_usage_ceph_pools)
check "no pool sizes: falls back to raw/stored" "$(repl "$OUT" glance-images)" 2

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
