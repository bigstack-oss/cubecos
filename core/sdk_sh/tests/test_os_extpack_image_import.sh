#!/bin/bash
#
# Unit test for import failures in ../modules/sdk_os.sh (#2401).
# os_extpack_image_import must name each image whose helper fails, import the
# rest, and return non-zero; os_image_import, the octavia and ironic helpers
# must return non-zero when conversion, upload, tagging or image create fails.
# Self-contained: extract the functions under test and stub every command.
#   Run: bash test_os_extpack_image_import.sh (exit 0 = pass)
#   Negative control (must FAIL):
#     git show origin/develop:core/sdk_sh/modules/sdk_os.sh > /tmp/old.sh
#     SRC=/tmp/old.sh bash test_os_extpack_image_import.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_os.sh}"

extract() {
    local name=$1 fn
    fn="$(awk -v n="$name" '$0 == n "()" {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $name not found in $SRC"; exit 1; }
    eval "$fn"
}

pass=0 fail=0
check() {
    if [ "$2" = "$3" ]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        echo "FAIL: $1: got '$2', want '$3'"
    fi
}
nonzero() {
    if [ "$2" != 0 ]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        echo "FAIL: $1: expected failure"
    fi
}
contains() { check "$1" "$(grep -cF -- "$2" "$3")" 1; }
absent() { check "$1" "$(grep -cF -- "$2" "$3")" 0; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/pack"
export CALLS=$TMP/calls TEST_TMP=$TMP
export TAR_RC=0 CONVERT_RC=0 GLANCE_RC=0 CREATE_RC=0
cat > "$TMP/bin/tar" <<'STUB'
#!/bin/bash
echo "tar $*" >> "$CALLS"
exit "$TAR_RC"
STUB
cat > "$TMP/bin/qemu-img" <<'STUB'
#!/bin/bash
case $1 in
    info)
        echo 'file format: qcow2'
        echo 'virtual size: 10 GiB (10737418240 bytes)'
        ;;
    convert)
        echo "convert $*" >> "$CALLS"
        : > "${@: -1}"
        # qemu-img 10.1.0 exits non-zero (2) on a qcow2 whose backing file is missing
        exit "$CONVERT_RC"
        ;;
esac
STUB
cat > "$TMP/bin/df" <<'STUB'
#!/bin/bash
echo 'Filesystem 1K-blocks Used Available Use% Mounted on'
echo 'test 999999999 0 999999999 0% /'
STUB
cat > "$TMP/bin/glance" <<'STUB'
#!/bin/bash
echo "glance $*" >> "$CALLS"
# glanceclient 4.8.0 exits non-zero when the upload is rejected, leaving a queued image
exit "$GLANCE_RC"
STUB
cat > "$TMP/bin/openstack" <<'STUB'
#!/bin/bash
echo "openstack $*" >> "$CALLS"
# openstackclient 7.5.1: image create exits 1 when it cannot read the file
exit "$CREATE_RC"
STUB
cat > "$TMP/bin/mktemp" <<'STUB'
#!/bin/bash
echo "$TEST_TMP/converted.raw"
STUB
cat > "$TMP/bin/uuidgen" <<'STUB'
#!/bin/bash
echo image-id
STUB
cat > "$TMP/bin/jq" <<'STUB'
#!/bin/bash
cat >/dev/null
echo cube
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
OPENSTACK=fake_openstack
cmd() { echo "cmd $*" >> "$CALLS"; return "${CMD_RC:-0}"; }
touch() { :; }
cubectl() { echo "cubectl $*" >> "$CALLS"; }
os_extpack_image_umount() { echo "umount $*" >> "$CALLS"; }
fake_openstack() { echo "image-cli $*" >> "$CALLS"; }

for img in amphora-x_1.qcow2 manila-x_1.qcow2 rancher-cluster-x_1.qcow2 appfw-x_1.tgz ; do
    : > "$TMP/pack/$img"
done
extract os_extpack_image_import
run_pack() {
    : > "$CALLS"
    (
        os_octavia_image_import() { echo octavia >> "$CALLS"; }
        os_manila_image_import() { echo manila >> "$CALLS"; }
        os_ironic_deploy_kernel_import() { echo kernel >> "$CALLS"; }
        os_ironic_deploy_initramfs_import() { echo initramfs >> "$CALLS"; }
        os_image_import_with_attrs() { echo rancher >> "$CALLS"; return "$RANCHER_RC"; }
        os_extpack_image_import "$TMP" pack
    ) > "$TMP/output" 2>&1
    RC=$?
}
RANCHER_RC=0
run_pack
check 'pack success rc' "$RC" 0
absent 'pack success output' Failed "$TMP/output"
RANCHER_RC=1
run_pack
check 'pack helper failure rc' "$RC" 1
contains 'pack helper diagnostic' 'Failed to import rancher-cluster-x_1.qcow2' "$TMP/output"
contains 'pack continues: octavia' octavia "$CALLS"
contains 'pack continues: manila' manila "$CALLS"
contains 'pack continues: appfw' 'cubectl node rsync' "$CALLS"
contains 'pack failure unmounts' umount "$CALLS"
RANCHER_RC=0 TAR_RC=1
run_pack
check 'pack tar failure rc' "$RC" 1
contains 'pack tar diagnostic' 'Failed to import appfw-x_1.tgz' "$TMP/output"
absent 'failed tar skips rsync' cubectl "$CALLS"
TAR_RC=0

extract _os_image_distro_ver
extract os_image_import
os_cinder_get_volume_backend_host_by_volume_type() { echo '["cube"]'; }
run_image() {
    : > "$CALLS"
    ( os_image_import "$TMP" image.qcow2 test-image ) > "$TMP/output" 2>&1
    RC=$?
}
run_image
check 'image success rc' "$RC" 0
contains 'image success output' 'Finished creating image' "$TMP/output"
check 'image success removes raw' "$([ -e "$TMP/converted.raw" ] && echo yes || echo no)" no
CMD_RC=1
run_image
check 'image success with a node unreachable rc' "$RC" 0
CMD_RC=0
CONVERT_RC=1
run_image
check 'conversion failure rc' "$RC" 1
absent 'conversion failure skips glance' 'glance --' "$CALLS"
contains 'conversion failure diagnostic' 'Failed to convert image.qcow2' "$TMP/output"
check 'conversion failure removes raw' "$([ -e "$TMP/converted.raw" ] && echo yes || echo no)" no
contains 'conversion failure removes marker' 'cmd rm -f /run/os_image_import_' "$CALLS"
CONVERT_RC=0 GLANCE_RC=1
run_image
check 'glance failure rc' "$RC" 1
contains 'glance failure deletes queued image' 'image-cli image delete image-id' "$CALLS"
absent 'glance failure skips project set' 'image set --project' "$CALLS"
absent 'glance failure skips completion' 'Finished creating image' "$TMP/output"
check 'glance failure removes raw' "$([ -e "$TMP/converted.raw" ] && echo yes || echo no)" no
contains 'glance failure removes marker' 'cmd rm -f /run/os_image_import_' "$CALLS"
GLANCE_RC=0

extract os_octavia_image_import
run_octavia() {
    : > "$CALLS"
    (
        os_image_import() { : > "$TMP/imported"; }
        fake_openstack() {
            echo "$*" >> "$CALLS"
            case "$1 $2" in
                'image list')
                    [ "$OLD_IMAGE" = 0 ] || echo old-id
                    [ ! -e "$TMP/imported" ] || echo new-id
                    ;;
                'image delete')
                    # openstackclient 7.5.1: exits 1 if any listed image is not deleted (seen with a protected one)
                    return 1
                    ;;
                'image set')
                    # openstackclient 7.5.1: exits 1 for a missing image ID
                    return "$TAG_RC"
                    ;;
                'image unset')
                    # openstackclient 7.5.1: exits 1 for a missing image ID
                    return "$UNTAG_RC"
                    ;;
            esac
        }
        os_octavia_image_import "$TMP" image.qcow2
    ) > "$TMP/output" 2>&1
    RC=$?
    rm -f "$TMP/imported"
}
OLD_IMAGE=0 TAG_RC=1 UNTAG_RC=0
run_octavia
nonzero 'octavia tag failure rc' "$RC"
contains 'octavia tag diagnostic' 'Failed to tag amphora-x64-haproxy image new-id' "$TMP/output"
TAG_RC=0
run_octavia
check 'octavia success rc' "$RC" 0
OLD_IMAGE=1 UNTAG_RC=1
run_octavia
nonzero 'octavia untag failure rc' "$RC"
contains 'octavia untag diagnostic' 'Failed to untag amphora-x64-haproxy image old-id' "$TMP/output"

extract os_ironic_deploy_kernel_import
extract os_ironic_deploy_initramfs_import
cp() { echo "cp $*" >> "$CALLS"; }
CREATE_RC=1
for helper in os_ironic_deploy_kernel_import os_ironic_deploy_initramfs_import ; do
    : > "$CALLS"
    "$helper" "$TMP" deploy-image > "$TMP/output" 2>&1
    RC=$?
    check "$helper create failure rc" "$RC" 1
    absent "$helper create failure skips cp" 'cp -f' "$CALLS"
done

if [ "$fail" = 0 ]; then
    echo "PASS ($pass checks)"
    exit 0
fi
echo "FAIL ($fail failures, $pass checks passed)"
exit 1
