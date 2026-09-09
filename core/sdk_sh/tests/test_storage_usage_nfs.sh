#!/bin/bash
#
# Unit test for storage_usage_nfs_disks (../modules/sdk_storage.sh).
#
# NFS Cinder volumes are files on the share, so qemu-img reports the exact
# physical footprint (actual-size) against the logical size (virtual-size) with
# no array involved. CubeCOS's builtin NFS model sets nfs_qcow2_volumes=false
# and nfs_sparsed_volumes=true, so they are sparse raw rather than qcow2 --
# qemu-img reports the sparse allocation either way.
#
# dedup_compress must stay null, not 1.0: a 1.0 reads as "compression on,
# saving nothing", which is a different and wrong statement. A file it cannot
# read is "unavailable", never 0 -- a 0 renders as an empty volume.
#
# Cross-module reads go through $HEX_SDK: a bare cinder_get_storages call is a
# silent no-op, because hex_sdk sources only sdk_<first-token>*.sh.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

SRVTO=60
HEX_SDK=hex_sdk
b="$(awk '/^storage_usage_nfs_disks\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: storage_usage_nfs_disks not extracted"; exit 1; }
eval "$b"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
timeout(){ shift 3; "$@"; }

MNT=$(mktemp -d)
: > $MNT/volume-nnn ; : > $MNT/volume-mmm ; : > $MNT/not-a-volume

# two backends configured; only the nfs one is ours
hex_sdk(){
    case "$1" in
    cinder_get_storages) echo '[{"name":"NFSStorage","driver":"cinder.volume.drivers.nfs.NfsDriver"},
                                {"name":"sc01","driver":"cinder.volume.drivers.dell_emc.sc.storagecenter_fc.SCFCDriver"}]' ;;
    cinder_get_storage)  echo "{\"storage\":{\"service\":{\"driverSection\":[{\"key\":\"nfs_shares_config\",\"value\":\"$MNT/shares\"}]}}}" ;;
    esac
}
echo "10.32.2.25:/export/cinder-nfs" > $MNT/shares
findmnt(){ echo "$MNT"; }   # the share is mounted here

qemu-img(){
    case "$3" in
    *volume-nnn) echo '{"virtual-size":10737418240,"actual-size":1073741824}' ;;
    *volume-mmm) return 1 ;;
    esac
}

out="$(storage_usage_nfs_disks)"
g(){ echo "$out" | jq -r --arg d "$1" 'select(.disk_id==$d) | '"$2"; }

chk "row count"          "$(echo "$out" | grep -c .)"           "2"
chk "provisioned"        "$(g volume-nnn .provisioned_bytes)"   "10737418240"
chk "allocated"          "$(g volume-nnn .allocated_bytes)"     "1073741824"
chk "backend name"       "$(g volume-nnn .backend)"             "NFSStorage"
chk "backend_type"       "$(g volume-nnn .backend_type)"        "nfs"
chk "kind"               "$(g volume-nnn .kind)"                "volume"
chk "scope"              "$(g volume-nnn .scope)"               "disk"
chk "no compression"     "$(g volume-nnn .dedup_compress)"      "null"
chk "confidence"         "$(g volume-nnn .confidence)"          "exact"
chk "unreadable conf"    "$(g volume-mmm .confidence)"          "unavailable"
chk "unreadable alloc"   "$(g volume-mmm .allocated_bytes)"     "null"
chk "non-volume skipped" "$(echo "$out" | jq -r 'select(.disk_id=="not-a-volume")' | grep -c .)" "0"

# no nfs backend configured at all must be silent, not an error
hex_sdk(){ [ "$1" = "cinder_get_storages" ] && echo '[{"name":"sc01","driver":"x.SCFCDriver"}]'; }
chk "no nfs backend silent" "$(storage_usage_nfs_disks | grep -c .)" "0"

rm -rf $MNT
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
