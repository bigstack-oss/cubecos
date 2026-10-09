#!/bin/bash
#
# Unit test for cinder_delete_storage (../modules/sdk_cinder.sh) unmounting the
# NFS shares of the backend it deletes (#2009).
#
# Cinder's NFS driver mounts each share of a backend at
# /store/cinder/mnt/<md5 of the share> and never unmounts it. Deleting the
# backend removed its conf and shares file but left the hard mount behind:
# once the NFS server went, df, node-exporter and `cluster health` hung on it,
# and re-adding the same share reused the stale mount (Stale file handle).
#
# The suite runs the real capture and json helpers; everything that touches the
# node (openstack, apply, umount, stat, ssh, /proc/mounts) is stubbed. Part C
# runs the same assertions against the function as it was before the fix, to
# prove they catch it.
#
#   Run: bash test_cinder_delete_storage_nfs_unmount.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

# The commit the function looked like before the fix. Pinned to an object, not
# to a branch, so the negative control cannot turn green against itself.
BASE_REF=5fcaa461

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

PROG=test_cinder_delete_storage_nfs_unmount
for f in cinder_delete_storage cinder_get_storage_nfs_mount_hashes cinder_unmount_nfs_mounts ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
for f in _hex_function _hex_function_ret ; do
    extract "$DIR/../../main/proj_functions" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
for f in json_get_value json_get_compact_value json_is_array ; do
    extract "$DIR/../modules.pre/sdk_json.sh" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_is.sh" is_valid_json || { echo "FAIL: is_valid_json not extracted"; exit 1; }
eval "$(grep -E '^ERROR_JSON_[A-Z_]+=' "$DIR/../modules.pre/sdk_json.sh")"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY="$WORK/backends"
CINDER_STORAGE_EXTRA_CONFIGS_DIRECTORY="$WORK/extra"
CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY="$WORK/ownership"
CINDER_NFS_MOUNT_POINT_BASE="$WORK/mnt"
HOSTNAME=cc1
HEX_SDK=/usr/sbin/hex_sdk

md5() { printf '%s' "$1" | md5sum | cut -d' ' -f1; }
S1="10.0.0.9:/export/a"
S2="10.0.0.9:/export/b"
H1="$(md5 "$S1")" H2="$(md5 "$S2")"
chk "hash is cinder's (md5 of the share, as on node1)" \
    "$(md5 "192.0.2.10:/rt694-g-772-53-nfs")" "c33bb61387ce69ffc0f97c73557f3923"

# --- stubs: everything that would touch the node ---------------------------
OPENSTACK=openstack_stub
openstack_stub() { return 0; }
cinder_is_volume_type_in_use() { return 1; }
cinder_apply_storage_deletion() { LOG+="apply;"; return 0; }
is_control_node() { return 0; }
log_warning() { LOG+="warn:$1;"; }
cinder_read_storage_extra_configs_ownership() {
    [ -f "$CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY/$1.yaml" ] && echo "{\"extraConfigFiles\":[{\"name\":\"${1}_nfs_shares\"}]}"
}
# MOUNTED holds the mount directories; DEAD the ones whose server is gone;
# BUSY the ones a plain umount refuses; STUCK the ones even umount -l cannot detach
cinder_is_nfs_mounted() { [[ " $MOUNTED " == *" $1 "* ]]; }
timeout() { while [[ "$1" == -* ]]; do shift 2; done; shift; "$@"; }
stat() { [[ " $DEAD " != *" ${!#} "* ]]; }
umount() {
    local d="${!#}"
    LOG+="umount $*;"
    if [ "$1" != "-l" ] && [[ " $BUSY " == *" $d "* ]]; then return 32; fi
    if [[ " $STUCK " == *" $d "* ]]; then return 124; fi
    MOUNTED="${MOUNTED//$d/}"
}
is_sshable() { [[ " $UNREACHABLE " != *" $1 "* ]]; }
ssh() { LOG+="ssh ${*: -2:1} ${!#};"; [[ " $SSH_FAIL " != *" ${*: -2:1} "* ]]; }

setup() {  # <name> <shares file content> -- an NFS backend as cinder_put_storage leaves it
    mkdir -p "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY" "$CINDER_STORAGE_EXTRA_CONFIGS_DIRECTORY" \
             "$CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY"
    printf '[%s]\nvolume_driver = cinder.volume.drivers.nfs.NfsDriver\nnfs_shares_config = %s\n' \
        "$1" "$CINDER_STORAGE_EXTRA_CONFIGS_DIRECTORY/${1}_nfs_shares" \
        > "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY/ext_storage_$1.conf"
    printf '%b' "$2" > "$CINDER_STORAGE_EXTRA_CONFIGS_DIRECTORY/${1}_nfs_shares"
    echo "extraConfigFiles: []" > "$CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY/$1.yaml"
}
mnt() { mkdir -p "$CINDER_NFS_MOUNT_POINT_BASE/$1"; MOUNTED+=" $CINDER_NFS_MOUNT_POINT_BASE/$1"; }
reset() {
    rm -rf "${WORK:?}"/* "$WORK/.out"
    LOG="" MOUNTED="" DEAD="" BUSY="" STUCK="" UNREACHABLE="" SSH_FAIL=""
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1)
}
run() {  # <function> <name> -> RC, OUT; in this shell, so the stubs' state survives
    "$1" "{\"name\":\"$2\"}" >"$WORK/.out" 2>/dev/null; RC=$?
    OUT="$(cat "$WORK/.out")"
}
gone() { [ ! -d "$CINDER_NFS_MOUNT_POINT_BASE/$1" ] && ! cinder_is_nfs_mounted "$CINDER_NFS_MOUNT_POINT_BASE/$1" && echo yes || echo no; }

suite() {  # <label> <function>
    local L="$1" fn="$2"

    # 1. two share lines (plus a comment, a blank and mount options): both unmounted, dirs gone
    reset; setup nfs1 "# comment\n\n$S1\n$S2 -o vers=4.1\n"; mnt "$H1"; mnt "$H2"
    run "$fn" nfs1
    chk "$L 1 return code" "$RC" "0"
    chk "$L 1 stdout contract" "$OUT" '{"message":"storage nfs1 deleted"}'
    chk "$L 1 share 1 unmounted, dir removed" "$(gone "$H1")" "yes"
    chk "$L 1 share 2 unmounted, dir removed" "$(gone "$H2")" "yes"
    chk "$L 1 plain umount, not lazy" "$(grep -c 'umount -l' <<< "${LOG//;/$'\n'}")" "0"
    chk "$L 1 unmounted after the backend left cinder" "${LOG%%umount*}" "apply;"

    # 2. a non-NFS backend: no umount
    reset; mkdir -p "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY"
    printf '[rbd1]\nvolume_driver = cinder.volume.drivers.rbd.RBDDriver\n' \
        > "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY/ext_storage_rbd1.conf"
    mkdir -p "$CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY"; echo x > "$CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY/rbd1.yaml"
    mnt "$H1"
    run "$fn" rbd1
    chk "$L 2 non-NFS return code" "$RC" "0"
    chk "$L 2 non-NFS: nothing unmounted" "$(cinder_is_nfs_mounted "$CINDER_NFS_MOUNT_POINT_BASE/$H1" && echo kept)" "kept"

    # 3. already unmounted: no error, no umount, empty dir removed
    reset; setup nfs1 "$S1\n"; mkdir -p "$CINDER_NFS_MOUNT_POINT_BASE/$H1"
    run "$fn" nfs1
    chk "$L 3 not mounted: return code" "$RC" "0"
    chk "$L 3 not mounted: empty dir removed" "$(gone "$H1")" "yes"

    # 4. a share another backend still lists stays mounted
    reset; setup nfs1 "$S1\n$S2\n"; setup nfs2 "$S2\n"; mnt "$H1"; mnt "$H2"
    run "$fn" nfs1
    chk "$L 4 own share unmounted" "$(gone "$H1")" "yes"
    chk "$L 4 shared share kept" "$(cinder_is_nfs_mounted "$CINDER_NFS_MOUNT_POINT_BASE/$H2" && echo kept)" "kept"

    # 5. stale handle / server gone: detached lazily
    reset; setup nfs1 "$S1\n"; mnt "$H1"; DEAD="$CINDER_NFS_MOUNT_POINT_BASE/$H1"
    run "$fn" nfs1
    chk "$L 5 stale: return code" "$RC" "0"
    chk "$L 5 stale: lazily detached" "$(gone "$H1")" "yes"

    # 5b. stale and the lazy detach fails too: reported, dir kept
    reset; setup nfs1 "$S1\n"; mnt "$H1"; DEAD="$CINDER_NFS_MOUNT_POINT_BASE/$H1"; STUCK="$DEAD"
    run "$fn" nfs1
    chk "$L 5b stuck: delete still succeeds" "$RC" "0"
    chk "$L 5b stuck: dir kept" "$([ -d "$CINDER_NFS_MOUNT_POINT_BASE/$H1" ] && echo kept)" "kept"
    chk "$L 5b stuck: logged on the deleting node" "$(grep -c "could not be detached" <<< "${LOG//;/$'\n'}")" "1"

    # 6. busy while the server answers: left mounted, never lazily
    reset; setup nfs1 "$S1\n"; mnt "$H1"; BUSY="$CINDER_NFS_MOUNT_POINT_BASE/$H1"
    run "$fn" nfs1
    chk "$L 6 busy: delete still succeeds" "$RC" "0"
    chk "$L 6 busy: left mounted" "$(cinder_is_nfs_mounted "$CINDER_NFS_MOUNT_POINT_BASE/$H1" && echo kept)" "kept"
    chk "$L 6 busy: no lazy umount" "$(grep -c 'umount -l' <<< "${LOG//;/$'\n'}")" "0"

    # 7. 3 control nodes, one unreachable: the others are told, by hash only
    reset; setup nfs1 "$S1\n"; mnt "$H1"
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3); UNREACHABLE="cc3"
    run "$fn" nfs1
    chk "$L 7 local unmounted" "$(gone "$H1")" "yes"
    chk "$L 7 cc2 told by hash" "$(grep -o "ssh root@cc2 $HEX_SDK cinder_unmount_nfs_mounts $H1" <<< "${LOG//;/$'\n'}")" \
        "ssh root@cc2 $HEX_SDK cinder_unmount_nfs_mounts $H1"
    chk "$L 7 cc3 skipped, not waited on" "$(grep -c 'root@cc3' <<< "${LOG//;/$'\n'}")" "0"

    # 8. a peer whose unmount fails is logged on the deleting node
    reset; setup nfs1 "$S1\n"; mnt "$H1"
    CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2); SSH_FAIL="root@cc2"
    run "$fn" nfs1
    chk "$L 8 peer failure: return code" "$RC" "0"
    chk "$L 8 peer failure logged" "$(grep -c "cc2: NFS unmount for storage nfs1 incomplete" <<< "${LOG//;/$'\n'}")" "1"
}

# --- the helper refuses anything but a hash --------------------------------
reset; mkdir -p "$WORK/mnt/x"
cinder_unmount_nfs_mounts "../x" "x" "$WORK/mnt/x"
chk "non-hash arguments ignored" "$([ -d "$WORK/mnt/x" ] && echo kept)" "kept"

# --- Part A: the function as it is now -------------------------------------
suite "A" cinder_delete_storage

# --- Part C: negative control, the pre-fix function must fail Part A -------
if old="$(git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_cinder.sh" 2>/dev/null)"; then
    tmp="$(mktemp)"; printf '%s\n' "$old" > "$tmp"
    extract "$tmp" cinder_delete_storage cinder_delete_storage_prefix || { echo "FAIL: pre-fix function not extracted"; exit 1; }
    rm -f "$tmp"
    p0=$pass f0=$fail
    suite "C" cinder_delete_storage_prefix >/dev/null
    if [ $((fail - f0)) -gt 0 ]; then
        pass=$((p0 + 1)); fail=$f0
    else
        pass=$p0; fail=$((f0 + 1)); echo "FAIL: C: the pre-fix function passed; the suite does not catch the bug"
    fi
else
    echo "SKIP: C: $BASE_REF not reachable (no git repo here)"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
