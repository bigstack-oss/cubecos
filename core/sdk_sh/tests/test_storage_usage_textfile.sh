#!/bin/bash
#
# Unit test for _storage_usage_textfile (../modules/sdk_storage.sh).
#
# Grafana reads Prometheus, so the collection has two outputs from one pass: this
# node_exporter textfile, and the influx line protocol the Kapacitor alarm needs
# because Kapacitor cannot read Prometheus.
#
# A null must be omitted, never emitted as 0 -- an absent series reads as "not
# measured" in Prometheus, while a 0 reads as "measured, empty", which is the
# same lie the confidence field exists to prevent everywhere else.
#
# The file is renamed into place: node_exporter reads the directory on its own
# schedule and would otherwise serve a half-written file as real samples.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

b="$(awk '/^_storage_usage_textfile\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: _storage_usage_textfile not extracted"; exit 1; }
eval "$b"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

D=$(mktemp -d); OUT=$D/cube_storage_usage.prom
cat <<'J' | _storage_usage_textfile "$D"
{"scope":"pool","backend":"CubeStorage","backend_type":"ceph","pool":"cinder-volumes","capacity_bytes":1000,"stored_bytes":100,"raw_used_bytes":300,"provisioned_bytes":500,"replication_factor":3,"reduction_ratio":null}
{"scope":"pool","backend":"NFSStorage","backend_type":"nfs","pool":"/var/lib/cinder/nfs/abc","capacity_bytes":2000,"stored_bytes":700,"raw_used_bytes":700,"provisioned_bytes":900,"replication_factor":1,"reduction_ratio":null}
{"scope":"disk","backend":"CubeStorage","pool":"ephemeral-vms","kind":"ephemeral","disk_id":"vm1_disk","instance_id":"vm-1","vm_name":"web-01","project_name":"appfw","provisioned_bytes":100,"allocated_bytes":25,"snapshot_bytes":0}
{"scope":"vm","instance_id":"vm-1","vm_name":"web-01","project_name":"appfw","guest_used_bytes":40,"guest_total_bytes":100}
{"scope":"fs","instance_id":"vm-1","vm_name":"web-01","project_name":"appfw","mountpoint":"/boot","device":"sda16","used_percent":94,"fs_used_bytes":8,"fs_total_bytes":10}
{"scope":"vm","instance_id":"vm-2","vm_name":"db-01","project_name":"admin","guest_used_bytes":null,"guest_total_bytes":null}
{"scope":"vol","instance_id":"vm-1","volume_id":"vol-a","vm_name":"web-01","project_id":"p1","project_name":"appfw","guest_used_bytes":30,"guest_total_bytes":90,"fs_count":2}
J

g(){ grep -c "$1" "$OUT"; }
# a ceph pool is already exported as ceph_pool_* by ceph-mgr; emitting it here
# too would give the same number two names. Backends with no exporter must
# still come through, or their pools go dark.
chk "ceph pool skipped"    "$(g '^cube_storage_pool_stored_bytes{.*pool="cinder-volumes".*}')"        "0"
chk "non-ceph pool kept"   "$(g '^cube_storage_pool_stored_bytes{.*backend_type="nfs".*} 700$')"      "1"
chk "non-ceph raw"         "$(g '^cube_storage_pool_raw_used_bytes{.*backend_type="nfs".*} 700$')"    "1"
chk "non-ceph replication" "$(g '^cube_storage_pool_replication_factor{.*backend_type="nfs".*} 1$')"  "1"
chk "disk allocated"       "$(g '^cube_storage_disk_allocated_bytes{.*name="web-01".*} 25$')"        "1"
chk "guest used"           "$(g '^cube_instance_guest_used_bytes{.*resource="vm-1".*} 40$')"          "1"
chk "volume guest used"    "$(g '^cube_volume_guest_used_bytes{.*volume="vol-a".*} 30$')"              "1"
chk "volume guest total"   "$(g '^cube_volume_guest_total_bytes{.*volume="vol-a".*} 90$')"             "1"
chk "volume keeps the vm"  "$(g '^cube_volume_guest_used_bytes{volume="vol-a",resource="vm-1".*')"     "1"
chk "volume HELP once"     "$(g '^# HELP cube_volume_guest_used_bytes ')"                              "1"
# the fleet-wide per-instance label convention: these must bind to the Instance
# dashboard's $UUID, which filters on resource=~
chk "uses resource label"  "$(g '^cube_storage_disk_allocated_bytes{resource="vm-1"')"                  "1"
chk "no instance_id label" "$(grep -c 'instance_id=' "$OUT")"                                            "0"
chk "no vm_name label"     "$(grep -c 'vm_name=' "$OUT")"                                                "0"
chk "fs percent"           "$(g '^cube_instance_fs_used_percent{.*mountpoint="/boot".*} 94$')"        "1"

# a null must be absent, not zero
chk "null reduction absent" "$(grep -c '^cube_storage_pool_reduction_ratio' "$OUT")"                  "0"
chk "null guest absent"     "$(grep -c 'db-01' "$OUT")"                                               "0"

# every emitted family must be typed, or Prometheus treats it as untyped
for f in cube_storage_pool_stored_bytes cube_storage_disk_allocated_bytes cube_instance_fs_used_percent ; do
  chk "TYPE for $f" "$(grep -c "^# TYPE $f gauge$" "$OUT")" "1"
done

# label values are quoted and the body is parseable exposition
chk "no unquoted labels" "$(grep -vc '^#' "$OUT" >/dev/null; grep -v '^#' "$OUT" | grep -cvE '^[a-z_]+\{[^}]*\} -?[0-9.]+$')" "0"
chk "no temp left behind" "$(ls "$D" | grep -c 'tmp')"                                                "0"
chk "single output file"  "$(ls "$D" | wc -l)"                                                        "1"

# an empty collection must still produce a valid (header-only) file, not a broken one
D2=$(mktemp -d); : | _storage_usage_textfile "$D2"
chk "empty run still valid" "$(grep -vc '^#' $D2/cube_storage_usage.prom)"                            "0"
rm -rf "$D" "$D2"
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
