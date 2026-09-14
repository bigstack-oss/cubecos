#!/bin/bash
T=$(mktemp -d)
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_move_preflight()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^_cinder_preflight_json()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_pf_block()/p' $SRC >> $T/fn.sh            # one-liner
source $T/fn.sh
chk(){ printf '%-46s -> %-26s (want %s)\n' "$1" "$2" "$3"; }
# every blocker code, comma-joined; the leading match is the top-level "code"
codes(){ grep -o '"code":"[^"]*"' $T/o | sed 's/.*:"//;s/"$//' | tail -n +2 | paste -sd, -; }

# stubs the function under test calls; each case overrides what it needs
_pf_volume()      { cat $T/vol.json; }
_pf_snapshots()   { cat $T/snaps; }
_pf_type_exists() { grep -qx "$1" $T/types; }
_pf_vm_state()    { cat $T/vmstate; }
_pf_qos_differs() { return 1; }
_pf_domain_probe(){ cat $T/domain; }
_pf_type_multiattach(){ grep -qx "$1" $T/ma_types; }
_pf_type_encrypted(){   grep -qx "$1" $T/enc_types; }
_pf_backend_fsid_pool() { cat $T/fsidpool_$1; }

printf 'ceph\ntier-nvme\n' > $T/types
echo 'ACTIVE' > $T/vmstate
: > $T/snaps
echo 'c6e64c49:cinder-volumes' > $T/fsidpool_ceph
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme
# layer-2 probe output: "<domstate>|<space-separated disk targets>"
echo 'running|sda sdb' > $T/domain
: > $T/ma_types      # tiers whose type is multiattach-capable
: > $T/enc_types     # tiers whose type is encrypted

mkvol() { # status attachments multiattach replication group type
  printf '{"status":"%s","attachments":%s,"multiattach":%s,"replication_status":"%s","group_id":%s,"volume_type":"%s","size":2}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" > $T/vol.json
}
one='[{"server_id":"vm-1"}]'; two='[{"server_id":"vm-1"},{"server_id":"vm-2"}]'

mkvol in-use "$one" false None null ceph
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "in-use, running VM, clean"        "$c" "OK"

mkvol in-use "$one" false None null ceph
cinder_move_preflight v1 ceph >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "destination == source type"       "$c" "E_SAME_TYPE"

mkvol in-use "$one" false None null ceph
echo 'SHUTOFF' > $T/vmstate
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "attached to a stopped VM"         "$c" "E_VM_NOT_RUNNING"
echo 'ACTIVE' > $T/vmstate

mkvol in-use "$two" true None null ceph
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "two read/write attachments"       "$c" "E_MULTIATTACH"

mkvol available "[]" false None null ceph
echo 'snap-1' > $T/snaps
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "volume has a snapshot"            "$c" "E_HAS_SNAPSHOTS"
: > $T/snaps

mkvol available "[]" false enabled null ceph
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "replicated volume"                "$c" "E_REPLICATED"

mkvol available "[]" false None '"g-1"' ceph
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "volume in a group"                "$c" "E_IN_GROUP"

# cubecos#1490 guard: same fsid AND same pool means the destination is not
# actually a different place, even though it is a different backend
mkvol available "[]" false None null ceph
echo 'c6e64c49:cinder-volumes' > $T/fsidpool_tier-nvme
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "same fsid + same pool"            "$c" "E_SAME_CLUSTER_SAME_POOL"

mkvol available "[]" false None null ceph
cinder_move_preflight v1 nope >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "unknown destination type"         "$c" "E_NO_SUCH_TYPE"

# --- source/target capability asymmetry ---
# the fsid guard case above dirtied this fixture; restore two distinct clusters
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme

# Cinder refuses any multiattach-capability change on a volume that is not
# 'available', whichever direction it goes.
mkvol in-use "$one" false None null ceph
echo 'tier-nvme' > $T/ma_types
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "attached, target multiattach only" "$c" "E_MULTIATTACH_MISMATCH"

mkvol in-use "$one" false None null ceph
echo 'ceph' > $T/ma_types
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "attached, source multiattach only" "$c" "E_MULTIATTACH_MISMATCH"

# detached volumes may cross it
mkvol available "[]" false None null ceph
echo 'tier-nvme' > $T/ma_types
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "detached crosses multiattach"      "$c" "OK"
: > $T/ma_types

# nova refuses the swap when EITHER side is natively LUKS-encrypted
mkvol in-use "$one" false None null ceph
echo 'tier-nvme' > $T/enc_types
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "attached, target encrypted"        "$c" "E_ENCRYPTED"

mkvol in-use "$one" false None null ceph
echo 'ceph' > $T/enc_types
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "attached, source encrypted"        "$c" "E_ENCRYPTED"
: > $T/enc_types

# --- layer 2: the running domain disagrees with nova's DB view ---
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme
_pf_attached_device() { echo "/dev/sdb"; }

mkvol in-use "$one" false None null ceph
echo '|' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "domain gone from its host"        "$c" "E_DOMAIN_MISSING"

mkvol in-use "$one" false None null ceph
echo 'shut off|sda sdb' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "nova says ACTIVE, domain is not"  "$c" "E_DOMAIN_NOT_LIVE"

mkvol in-use "$one" false None null ceph
echo 'running|sda sdc' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "bdm disk absent from the domain"  "$c" "E_DISK_NOT_IN_DOMAIN"

mkvol in-use "$one" false None null ceph
echo 'paused|sda sdb' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "paused domain is still swappable" "$c" "OK"

# probe could not run -> fail OPEN, never invent a refusal
mkvol in-use "$one" false None null ceph
_pf_domain_probe() { return 1; }
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "probe unreachable fails open"     "$c" "OK"
_pf_domain_probe() { cat $T/domain; }

# a detached volume has no domain to probe
mkvol available "[]" false None null ceph
echo '|' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "detached volume skips layer 2"    "$c" "OK"

# --- every blocker is reported, not just the first ---
mkvol in-use "$one" false None null ceph
echo SHUTOFF > $T/vmstate; echo snap-1 > $T/snaps; echo 'shut off|sda sdb' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1
chk "stopped VM + snapshot: all reasons" "$(codes)" "E_HAS_SNAPSHOTS,E_VM_NOT_RUNNING"

# the domain probe sees the same stopped guest; do not say it twice
mkvol in-use "$one" false None null ceph
echo SHUTOFF > $T/vmstate; : > $T/snaps; echo 'shut off|sda sdb' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1
chk "stopped VM reported once"          "$(codes)" "E_VM_NOT_RUNNING"

# unrelated layer-1 and layer-2 blockers both surface
mkvol in-use "$one" false None null ceph
echo ACTIVE > $T/vmstate; echo snap-1 > $T/snaps; echo 'running|sda sdc' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1
chk "snapshot + disk missing"           "$(codes)" "E_HAS_SNAPSHOTS,E_DISK_NOT_IN_DOMAIN"

# a clean volume reports no blockers at all
mkvol in-use "$one" false None null ceph
: > $T/snaps; echo 'running|sda sdb' > $T/domain
cinder_move_preflight v1 tier-nvme >$T/o 2>&1
chk "clean volume has no blockers"      "$(codes)" ""

rm -rf $T
