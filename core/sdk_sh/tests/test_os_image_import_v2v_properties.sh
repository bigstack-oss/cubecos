#!/bin/bash
#
# os_image_import tags what it imports with image properties. Two of them are
# decided by how the image was converted (#560):
#
#   hw_disk_bus  RHEL's virt-v2v makes only viostor (virtio-blk) boot-critical in
#                a Windows guest, so a Windows guest virt-v2v converted has to boot
#                on virtio; every other path -- Linux, the qemu-img fallback when
#                virt-v2v refuses the guest, the glance-images pool -- stays on scsi.
#   os_version   the property glance documents for the guest OS version; the
#                function used to write os_vers, which nothing reads.
#
# The real os_image_import and _os_image_distro_ver run over stubs of the
# commands they call; the properties are read back from what reaches
# `openstack volume set` (cinder-volumes) or `glance image-create` (glance-images).
#
#   Run: bash test_os_image_import_v2v_properties.sh
#   Negative control (must FAIL the virtio and os_version checks):
#     git show origin/develop~N:core/sdk_sh/modules/sdk_os.sh > /tmp/old.sh
#     SRC=/tmp/old.sh bash test_os_image_import_v2v_properties.sh
#
set -u
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=${SRC:-$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_os.sh}
sed -n '/^_os_image_distro_ver()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^os_image_import()/,/^}/p' $SRC >> $T/fn.sh
source $T/fn.sh
[ "$(type -t os_image_import)" = function ] || { echo "FAIL: os_image_import not extracted"; exit 1; }
type -P jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-52s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-52s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# ==== stubs ================================================================
mkdir -p $T/bin $T/src
cmd() { return 0; }                     # import marker: never "being imported"
touch() { :; }                          # the marker lives in /run
Error() { echo "Error: $*" >&2; return 1; }
os_cinder_get_volume_backend_pool_by_volume_type() { echo '["cube@ceph#ceph"]'; }
os_cinder_get_volume_backend_host_by_volume_type() { echo '["cube@ceph"]'; }
BUILTIN_BACKPOOL=cinder-volumes
CEPHFS_GLANCE_DIR=$T/glance

cat > $T/bin/qemu-img <<'STUB'
#!/bin/bash
case $1 in
    info) echo "file format: qcow2"; echo "virtual size: 10 GiB (10737418240 bytes)" ;;
    convert) echo qemu-img-convert >> "$CALLS" ;;
esac
STUB
# /tmp reports no room, so the raw file lands next to the source in $T
cat > $T/bin/df <<'STUB'
#!/bin/bash
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
if [ "$1" = /tmp ] ; then echo "tmp 1 1 0 100% /tmp"; else echo "src 1 1 999999999 1% /src"; fi
STUB
printf '#!/bin/bash\n' > $T/bin/mount
# virt-v2v -i disk <img> -o local -of raw -os <dir> --parallel 4
cat > $T/bin/virt-v2v <<'STUB'
#!/bin/bash
echo virt-v2v >> "$CALLS"
[ "$V2V_OK" = 1 ] || exit 1
img=$3 dir=$9
base=$(basename "${img%.*}")
: > "$dir/$base-sda"
echo "<os firmware='bios'>" > "$dir/$base.xml"
STUB
cat > $T/bin/openstack <<'STUB'
#!/bin/bash
case "$1 $2" in
    "quota show") echo '[{"Resource":"gigabytes","Limit":-1,"In Use":0},{"Resource":"volumes","Limit":-1,"In Use":0}]' ;;
    "volume set") shift 2; echo "$*" > "$VOLUME_SET" ;;
    "image show") echo '{"properties":{"direct_url":"cinder://x/src-vol"}}' ;;
    "volume create") echo vol-1 ;;
    "volume show") echo available ;;
esac
STUB
cat > $T/bin/glance <<'STUB'
#!/bin/bash
echo "$*" > "$GLANCE_CREATE"
STUB
cat > $T/bin/cinder <<'STUB'
#!/bin/bash
echo "| id | vol-1 |"
STUB
printf '#!/bin/bash\n' > $T/bin/rbd
printf '#!/bin/bash\necho 00000000-0000-0000-0000-000000000001\n' > $T/bin/uuidgen
chmod +x $T/bin/*
export PATH="$T/bin:$PATH"
OPENSTACK=$T/bin/openstack
export CALLS=$T/calls VOLUME_SET=$T/volume_set GLANCE_CREATE=$T/glance_create

# run one import; prints the properties that reached the import command
run(){ # file distro pool v2v_ok
    rm -f $CALLS $VOLUME_SET $GLANCE_CREATE
    : > "$T/src/$1"
    ( V2V_OK=$4 os_image_import $T/src "$1" img-under-test "" "$3" CubeStorage "$2" ) >$T/out 2>&1
    if [ "$3" = glance-images ] ; then cat $GLANCE_CREATE 2>/dev/null; else cat $VOLUME_SET 2>/dev/null; fi
}
bus(){ grep -o -e '-property hw_disk_bus=[a-z-]*' | sed 's/.*=//' | tr '\n' ' ' | sed 's/ $//'; }

# ==== 1. Windows, virt-v2v converted it =====================================
P=$(run windows_2025.vhdx Windows cinder-volumes 1)
chk "windows + virt-v2v: hw_disk_bus" "$(echo "$P" | bus)" "virtio"
chk "windows + virt-v2v: ran virt-v2v, not qemu-img" "$(tr '\n' ' ' < $CALLS)" "virt-v2v "
chk "windows + virt-v2v: os_type" "$(echo "$P" | grep -o 'os_type=[a-z]*')" "os_type=windows"
chk "windows + virt-v2v: hw_scsi_model untouched" "$(echo "$P" | grep -o 'hw_scsi_model=[a-z-]*')" "hw_scsi_model=virtio-scsi"
chk "windows + virt-v2v: os_version" "$(echo "$P" | grep -o 'os_version=[^ ]*')" "os_version=2025"
chk "windows + virt-v2v: no os_vers" "$(echo "$P" | grep -c 'os_vers=')" "0"

# ==== 2. Linux, virt-v2v converted it =======================================
P=$(run ubuntu_22.04.qcow2 linux cinder-volumes 1)
chk "linux + virt-v2v: hw_disk_bus" "$(echo "$P" | bus)" "scsi"
chk "linux + virt-v2v: os_version" "$(echo "$P" | grep -o 'os_version=[^ ]*')" "os_version=22.04"

# ==== 3. Windows, virt-v2v refused it (qemu-img fallback, no drivers) =======
P=$(run windows_2025.vhdx windows cinder-volumes 0)
chk "windows + qemu-img fallback: hw_disk_bus" "$(echo "$P" | bus)" "scsi"
chk "windows + qemu-img fallback: fell back" "$(tr '\n' ' ' < $CALLS)" "virt-v2v qemu-img-convert "

# ==== 4. Windows into glance-images (qemu-img only, never virt-v2v) =========
P=$(run windows_2025.vhdx windows glance-images 1)
chk "windows + glance-images: hw_disk_bus" "$(echo "$P" | bus)" "scsi"
chk "windows + glance-images: os_version" "$(echo "$P" | grep -o 'os_version=[^ ]*')" "os_version=2025"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: os_image_import v2v properties"
exit 0
