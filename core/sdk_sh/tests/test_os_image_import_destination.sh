#!/bin/bash
#
# Unit test for ../modules/sdk_os.sh:
#   _os_image_import_rbd_pool -- Cinder backend pool -> RBD pool of this cluster
#   os_image_import           -- the "from another hypervisor" (cinder-volumes) path
#
# The regression that matters (#1447): the path went by the volume type's name.
# Only a type called exactly CubeStorage was written into Ceph; any other type --
# a node group, a device tier, or a second type on the built-in backend such as a
# customer's CubeStorage-smarthealth -- took the glance route with the backend
# host "cube" as its store. That is glance's built-in rbd store, not a cinder
# one, so no volume could be cloned from it: the import left an image in
# glance-images under admin, made no volume, and still reported success.
#
# Self-contained: extracts only the functions under test and stubs openstack,
# glance, cinder, rbd, qemu-img, virt-v2v and the hex helpers, so it needs no
# cluster. Every stub records its call.
#   Run: bash test_os_image_import_destination.sh   (exit 0 = pass)
#   SRC=<other sdk_os.sh> runs the same assertions against another version, e.g.
#   origin/develop before #1447, where the cases marked [#1447] must fail.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_os.sh}"

extract() {
    local name=$1 fn
    fn="$(awk -v n="^$name\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || return 1
    eval "$fn"
}

extract os_image_import || { echo "FAIL: os_image_import not found in $SRC"; exit 1; }
HAVE_RBD_POOL=1
extract _os_image_import_rbd_pool || HAVE_RBD_POOL=0
# the version under test may still call the host helper; it reads the same stub
extract _os_image_distro_ver || { echo "FAIL: _os_image_distro_ver not found in $SRC"; exit 1; }

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2', want '$3'"; fi; }
has()   { if grep -qF -- "$2" "$CALLS"; then ok; else bad "$1: no call matching '$2'"; fi; }
hasnt() { if grep -qF -- "$2" "$CALLS"; then bad "$1: unexpected call matching '$2'"; else ok; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS=$TMP/calls

# ---- stubs ---------------------------------------------------------------
BUILTIN_BACKPOOL=cinder-volumes
CEPHFS_GLANCE_DIR=$TMP/glance
OPENSTACK=fake_openstack

# BACKEND_POOL: what os_cinder_get_volume_backend_pool_by_volume_type resolves
# the volume type to; DIRECT_URL: the carrier image's direct_url; MANAGE_ID:
# what `cinder manage` prints as the new volume's id; RBD_FAIL=1 fails rbd import
os_cinder_get_volume_backend_pool_by_volume_type() {
    if [ -n "$BACKEND_POOL" ] ; then echo "[\"$BACKEND_POOL\"]" ; else echo "[]" ; fi
}
os_cinder_get_volume_backend_host_by_volume_type() {
    if [ -n "$BACKEND_POOL" ] ; then echo "[\"${BACKEND_POOL%%@*}\"]" ; else echo "[]" ; fi
}
fake_openstack() {
    echo "openstack $*" >> "$CALLS"
    case "$*" in
        *"quota show"*) echo '[{"Resource":"gigabytes","Limit":-1,"In Use":0},{"Resource":"volumes","Limit":-1,"In Use":0}]' ;;
        *"image show"*) echo "{\"properties\":{\"direct_url\":\"$DIRECT_URL\"}}" ;;
        *"volume create"*) echo "vol-from-clone" ;;
        *"volume show"*) echo "available" ;;
    esac
}
glance() { echo "glance $*" >> "$CALLS" ; }
cinder() {
    echo "cinder $*" >> "$CALLS"
    case "$*" in
        *manage*) [ -z "$MANAGE_ID" ] || printf '| id | %s |\n' "$MANAGE_ID" ;;
    esac
}
rbd() {
    echo "rbd $*" >> "$CALLS"
    case "$*" in *import*) [ "$RBD_FAIL" != 1 ] ;; esac
}
qemu-img() {
    case "$1" in
        info) printf 'file format: vmdk\nvirtual size: 1 GiB (1073741824 bytes)\n' ;;
        convert) for last; do :; done; : > "$last" ;;
    esac
}
virt-v2v() { return 1 ; }
uuidgen() { echo "img-uuid" ; }
cmd() {
    echo "cmd $*" >> "$CALLS"
    case "$1" in -v|find) return 0 ;; esac
}
touch() { : ; }
Error() { echo "Error: $*" >> "$CALLS" ; exit 1 ; }

FLAGS="--os-project-domain-name default --os-project-name CA903021"
mkdir -p "$TMP/src"
: > "$TMP/src/disk.vmdk"

# run_import <volume type>: one import from another hypervisor into CA903021
run_import() {
    : > "$CALLS"
    ( os_image_import "$TMP/src" disk.vmdk img1 "$FLAGS" cinder-volumes "$1" linux >/dev/null 2>&1 )
    RC=$?
}

# ---- 1. backend pool -> RBD pool ------------------------------------------
if [ "$HAVE_RBD_POOL" = 1 ] ; then
    check "built-in backend lives in cinder-volumes" "$(_os_image_import_rbd_pool 'cube@ceph#ceph')" "cinder-volumes"
    check "node group pool"   "$(_os_image_import_rbd_pool 'cube@grp1-pool#grp1-pool')" "grp1-pool"
    check "device tier pool"  "$(_os_image_import_rbd_pool 'cube@cinder-volumes-ssd#cinder-volumes-ssd')" "cinder-volumes-ssd"
    check "external backend"  "$(_os_image_import_rbd_pool 'netapp1@netapp1#pool_a')" ""
    check "no backend"        "$(_os_image_import_rbd_pool '')" ""
else
    echo "SKIP: _os_image_import_rbd_pool not in $SRC (version before #1447)"
fi

# ---- 2. [#1447] the customer's case: a second type on the built-in backend --
BACKEND_POOL='cube@ceph#ceph' DIRECT_URL=null MANAGE_ID=vol-managed RBD_FAIL=0
run_import CubeStorage-smarthealth
check "2 [#1447] rc" "$RC" 0
has   "2 [#1447] written into cinder-volumes" "rbd --id cinder import"
has   "2 [#1447] managed in the chosen project with the chosen type" \
      "cinder --os-project-domain-name default --os-project-name CA903021 manage --bootable --name img1 --volume-type CubeStorage-smarthealth cube@ceph#ceph"
hasnt "2 [#1447] no glance image in between" "glance "
if grep -q "rbd --id cinder import .* cinder-volumes/volume-img1-" "$CALLS" ; then ok ; else bad "2 [#1447] rbd target is cinder-volumes/volume-img1-*" ; fi

# ---- 3. [#1447] a node group pool -----------------------------------------
BACKEND_POOL='cube@grp1-pool#grp1-pool'
run_import grp1
check "3 [#1447] rc" "$RC" 0
if grep -q "rbd --id cinder import .* grp1-pool/volume-img1-" "$CALLS" ; then ok ; else bad "3 [#1447] rbd target is grp1-pool/volume-img1-*" ; fi
has   "3 [#1447] managed on the node group pool" "--volume-type grp1 cube@grp1-pool#grp1-pool"
hasnt "3 [#1447] no glance image in between" "glance "

# ---- 4. regression: the type actually called CubeStorage ------------------
BACKEND_POOL='cube@ceph#ceph'
run_import CubeStorage
check "4 rc" "$RC" 0
has   "4 managed as before" "manage --bootable --name img1 --volume-type CubeStorage cube@ceph#ceph"
has   "4 image properties copied to the volume" "volume set --image-property hw_disk_bus=scsi"

# ---- 5. [#1447] an external backend: volume made in the chosen project ------
BACKEND_POOL='netapp1@netapp1#pool_a' DIRECT_URL='cinder://netapp1/src-vol'
run_import netapp1
check "5 rc" "$RC" 0
has   "5 carrier image goes to the backend's glance store" "--store netapp1"
has   "5 [#1447] volume made in the chosen project" \
      "openstack --os-project-domain-name default --os-project-name CA903021 volume create --type netapp1 --source src-vol"
hasnt "5 nothing written into Ceph" "rbd "

# ---- 6. [#1447] the old failure shape now fails, and cleans up -------------
BACKEND_POOL='netapp1@netapp1#pool_a' DIRECT_URL='rbd://fsid/glance-images/img-uuid/snap'
run_import netapp1
if [ "$RC" != 0 ] ; then ok ; else bad "6 [#1447] import with no cinder direct_url must fail, got rc=0" ; fi
hasnt "6 no clone from a non-cinder url" "volume create"
has   "6 [#1447] carrier image removed" "image delete img-uuid"

# ---- 7. rbd import fails -> no volume is managed --------------------------
BACKEND_POOL='cube@ceph#ceph' RBD_FAIL=1
run_import CubeStorage-smarthealth
RBD_FAIL=0
if [ "$RC" != 0 ] ; then ok ; else bad "7 failed rbd import must fail the import" ; fi
hasnt "7 nothing managed" "manage --bootable"

# ---- 8. manage gives no id -> the orphan RBD image is removed ---------------
BACKEND_POOL='cube@ceph#ceph' MANAGE_ID=
run_import CubeStorage-smarthealth
MANAGE_ID=vol-managed
if [ "$RC" != 0 ] ; then ok ; else bad "8 failed manage must fail the import" ; fi
if grep -q "rbd --id cinder rm cinder-volumes/volume-img1-" "$CALLS" ; then ok ; else bad "8 orphan rbd image removed" ; fi

# ---- 9. a type with no backend pool up ------------------------------------
BACKEND_POOL=''
run_import nosuch
if [ "$RC" != 0 ] ; then ok ; else bad "9 type without a backend pool must fail" ; fi
hasnt "9 nothing written into Ceph" "rbd "
hasnt "9 no glance image" "glance "

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
