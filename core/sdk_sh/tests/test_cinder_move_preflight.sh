#!/bin/bash
#
# cinder_move_preflight: which volume/instance states refuse a tier change,
# and that every reason is reported rather than only the first.
#
#   Run: bash test_cinder_move_preflight.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_move_preflight()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^_cinder_preflight_json()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_pf_block()/p' $SRC >> $T/fn.sh            # one-liner
source $T/fn.sh
pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}
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
_pf_type_backend_section() { local v; v=$(cat $T/section_$1 2>/dev/null); [ -n "$v" ] || return 1; echo "$v"; }
_pf_backend_fsid_pool()    { local v; v=$(cat $T/fsidpool_$1 2>/dev/null); [ -n "$v" ] || return 1; echo "$v"; }

printf 'ceph\ntier-nvme\nCubeStorage\n' > $T/types
echo 'ACTIVE' > $T/vmstate
: > $T/snaps
# volume type -> cinder.conf section. The built-in type is the one that is not
# named after its section.
echo 'ceph'        > $T/section_ceph
echo 'tier-nvme'   > $T/section_tier-nvme
echo 'ceph'        > $T/section_CubeStorage
echo 'c6e64c49:cinder-volumes' > $T/fsidpool_ceph
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme
# layer-2 probe output: "<domstate>|<space-separated disk targets>"
echo 'running|sda sdb' > $T/domain
: > $T/ma_types      # tiers whose type is multiattach-capable
: > $T/enc_types     # tiers whose type is encrypted

mkvol() { # status attachments multiattach replication group type
  printf '{"status":"%s","attachments":%s,"multiattach":%s,"replication_status":"%s","group_id":%s,"type":"%s","size":2}\n' \
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

# the built-in type is called CubeStorage while its section is called ceph;
# before the section lookup existed this pair resolved to nothing on both
# sides and the guard was inert for every move off the built-in tier
mkvol available "[]" false None null CubeStorage
echo 'c6e64c49:cinder-volumes' > $T/fsidpool_tier-nvme
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "built-in type resolves to ceph"   "$c" "E_SAME_CLUSTER_SAME_POOL"

# ...and it still crosses to a genuinely different pool
mkvol available "[]" false None null CubeStorage
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "built-in type to another cluster" "$c" "OK"

# an unresolvable side must be refused, never compared: two different strings
# (or one empty one) would otherwise read as "different place" and pass
mkvol available "[]" false None null ceph
: > $T/section_tier-nvme
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "destination type has no section"  "$c" "E_BACKEND_UNRESOLVED"
echo 'tier-nvme' > $T/section_tier-nvme

mkvol available "[]" false None null ceph
: > $T/fsidpool_tier-nvme
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "destination pool cannot be read"  "$c" "E_BACKEND_UNRESOLVED"
echo 'deadbeef:cinder-volumes' > $T/fsidpool_tier-nvme

mkvol available "[]" false None null ceph
: > $T/fsidpool_ceph
cinder_move_preflight v1 tier-nvme >$T/o 2>&1; c=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o)
chk "source pool cannot be read"       "$c" "E_BACKEND_UNRESOLVED"
echo 'c6e64c49:cinder-volumes' > $T/fsidpool_ceph

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

# --- _pf_qos_differs() direct testing ---
# Unset the stub and test the real function with mocked openstack
unset -f _pf_qos_differs
sed -n '/^_pf_qos_differs()/,/^}/p' $SRC > $T/qos_fn.sh
source $T/qos_fn.sh

# Mock openstack for QoS spec lookups
openstack() {
    if [ "$1" = "volume" ] && [ "$2" = "type" ] && [ "$3" = "show" ] ; then
        case "$4" in
            no-qos-src|no-qos-dst) echo '{"qos_specs_id":""}' ;;
            backend-src) echo '{"qos_specs_id":"qos-backend-1"}' ;;
            backend-dst) echo '{"qos_specs_id":"qos-backend-2"}' ;;
            backend-pair) echo '{"qos_specs_id":"qos-backend-1"}' ;;
            frontend-src) echo '{"qos_specs_id":"qos-frontend-1"}' ;;
            frontend-dst) echo '{"qos_specs_id":"qos-frontend-2"}' ;;
            both-src) echo '{"qos_specs_id":"qos-both-1"}' ;;
            both-dst) echo '{"qos_specs_id":"qos-both-2"}' ;;
        esac
    elif [ "$1" = "qos" ] && [ "$2" = "specs" ] && [ "$3" = "show" ] ; then
        case "$4" in
            qos-backend-1|qos-backend-2) echo '{"consumer":"back-end"}' ;;
            qos-frontend-1|qos-frontend-2) echo '{"consumer":"front-end"}' ;;
            qos-both-1|qos-both-2) echo '{"consumer":"both"}' ;;
        esac
    fi
}
export -f openstack
OPENSTACK=openstack

_test_qos() {
    local src="$1" dst="$2" want="$3" desc="$4"
    _pf_qos_differs "$src" "$dst"
    chk "$desc" "$?" "$want"
}

_test_qos "no-qos-src" "no-qos-dst" 1 "QoS: neither type has QoS"
_test_qos "backend-src" "backend-dst" 1 "QoS: both back-end-only different specs"
_test_qos "frontend-src" "backend-src" 0 "QoS: front-end on one side only"
_test_qos "backend-pair" "backend-pair" 1 "QoS: identical spec id"
_test_qos "frontend-src" "frontend-dst" 0 "QoS: both front-end with different specs"
_test_qos "both-src" "both-dst" 0 "QoS: both consumer=both with different specs"

# --- the real _pf_type_backend_section() ---------------------------------
# The guard above is only as good as this lookup; a stub of it cannot show
# that a volume type name is not a cinder.conf section name.
unset -f _pf_type_backend_section
sed -n '/^_pf_type_backend_section()/,/^}/p' $SRC > $T/sec_fn.sh
source $T/sec_fn.sh

openstack() {
    if [ "$1 $2 $3" = "volume type show" ] ; then
        case "$4" in
            CubeStorage) echo '{"properties":{"volume_backend_name":"ceph"}}' ;;
            tier-nvme)   echo '{"properties":{"volume_backend_name":"tier-nvme"}}' ;;
            legacy)      echo '{"properties":{}}' ;;            # no extra spec
            *)           return 1 ;;                            # no such type
        esac
    fi
}
export -f openstack
OPENSTACK=openstack

chk "section: built-in type -> ceph"   "$(_pf_type_backend_section CubeStorage)" "ceph"
chk "section: tier named after it"     "$(_pf_type_backend_section tier-nvme)"   "tier-nvme"
_pf_type_backend_section ghost >/dev/null 2>&1
chk "section: unknown type fails"      "$?" "1"
chk "section: unknown type is silent"  "$(_pf_type_backend_section ghost 2>/dev/null)" ""
_pf_type_backend_section legacy >/dev/null 2>&1
chk "section: no spec, not built-in"   "$?" "1"

# a CubeStorage whose extra spec never got written still resolves
openstack() { echo '{"properties":{}}' ; }
export -f openstack
chk "section: built-in without a spec" "$(_pf_type_backend_section CubeStorage)" "ceph"

# --- the real _pf_backend_fsid_pool() ------------------------------------
unset -f _pf_backend_fsid_pool
sed -n '/^_pf_backend_fsid_pool()/,/^}/p' $SRC > $T/fp_fn.sh
source $T/fp_fn.sh

_pf_ini_get() {
    # $1 file, $2 section, $3 key — stands in for the awk reader
    case "$2:$3" in
        ceph:rbd_ceph_conf) echo /etc/ceph/ceph.conf ;;
        ceph:rbd_pool)      echo cinder-volumes ;;
        *) return 1 ;;
    esac
}
export -f _pf_ini_get
ceph() { echo c6e64c49 ; }
export -f ceph
timeout() { shift; "$@" ; }
export -f timeout

chk "fsid/pool: a real section"        "$(_pf_backend_fsid_pool ceph)" "c6e64c49:cinder-volumes"
_pf_backend_fsid_pool nosuch >/dev/null 2>&1
chk "fsid/pool: unknown section fails" "$?" "1"
chk "fsid/pool: unknown is silent"     "$(_pf_backend_fsid_pool nosuch 2>/dev/null)" ""
_pf_backend_fsid_pool "" >/dev/null 2>&1
chk "fsid/pool: empty section fails"   "$?" "1"
ceph() { return 1 ; }
export -f ceph
_pf_backend_fsid_pool ceph >/dev/null 2>&1
chk "fsid/pool: silent cluster fails"  "$?" "1"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: cinder_move_preflight"
exit 0
