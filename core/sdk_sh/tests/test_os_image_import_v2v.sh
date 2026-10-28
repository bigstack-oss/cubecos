#!/bin/bash
#
# os_image_import hands a Windows guest to virt-v2v, whose firstboot reboots the
# guest until every injected driver installs. Windows Server rejects smbus.inf, so
# a virtio-win that has smbus or an ISO again -- the shipped tree has neither, but
# support-fixpack-243 mounts virtio-win-0.1.266.iso over /usr/share/virtio-win --
# loops the guest forever (#560). virt-v2v must be handed a tree without them.
#
# The real os_image_import runs over stubs; the stub virt-v2v records the
# VIRTIO_WIN it was given and what that tree holds.
#
#   Run (Linux; needs GNU cp -s): bash test_os_image_import_v2v.sh
#   Negative control (must FAIL the smbus checks):
#     git show origin/develop:core/sdk_sh/modules/sdk_os.sh > /tmp/old.sh
#     SRC=/tmp/old.sh bash test_os_image_import_v2v.sh
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
cmd() { return 0; }
touch() { :; }
Error() { echo "Error: $*" >&2; exit 1; }     # as hex_sdk's: run() is a subshell
os_cinder_get_volume_backend_pool_by_volume_type() { echo '["cube@ceph#ceph"]'; }
os_cinder_get_volume_backend_host_by_volume_type() { echo '["cube@ceph"]'; }
BUILTIN_BACKPOOL=cinder-volumes
CEPHFS_GLANCE_DIR=$T/glance

cat > $T/bin/qemu-img <<'STUB'
#!/bin/bash
case $1 in
    info) echo "file format: qcow2"; echo "virtual size: 10 GiB (10737418240 bytes)" ;;
esac
STUB
cat > $T/bin/df <<'STUB'
#!/bin/bash
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
if [ "$1" = /tmp ] ; then echo "tmp 1 1 0 100% /tmp"; else echo "src 1 1 999999999 1% /src"; fi
STUB
printf '#!/bin/bash\n' > $T/bin/mount
# virt-v2v -i disk <img> -o local -of raw -os <dir> --parallel 4
cat > $T/bin/virt-v2v <<'STUB'
#!/bin/bash
vw=${VIRTIO_WIN-unset}
{
    echo "dir=$vw"
    if [ -d "$vw" ] ; then
        # the fixtures' smbus and ISO paths, by name: not the product's find
        bad=0
        for f in smbus smbus/2k25/amd64/smbus.inf drivers/by-os/amd64/2k25/smbus.inf virtio-win.iso ; do
            [ -e "$vw/$f" ] && bad=$((bad+1))
        done
        echo "bad=$bad"
        [ -f "$vw/viostor/2k25/amd64/viostor.inf" ] && echo viostor=yes || echo viostor=no
    fi
} > "$SEEN"
img=$3 dir=$9
base=$(basename "${img%.*}")
: > "$dir/$base-sda"
echo "<os firmware='bios'>" > "$dir/$base.xml"
STUB
cat > $T/bin/openstack <<'STUB'
#!/bin/bash
case "$1 $2" in
    "quota show") echo '[{"Resource":"gigabytes","Limit":-1,"In Use":0},{"Resource":"volumes","Limit":-1,"In Use":0}]' ;;
    "image show") echo '{"properties":{"direct_url":"cinder://x/src-vol"}}' ;;
    "volume create") echo vol-1 ;;
    "volume show") echo available ;;
esac
STUB
printf '#!/bin/bash\necho "| id | vol-1 |"\n' > $T/bin/cinder
printf '#!/bin/bash\n' > $T/bin/glance
printf '#!/bin/bash\n' > $T/bin/rbd
printf '#!/bin/bash\necho 00000000-0000-0000-0000-000000000001\n' > $T/bin/uuidgen
chmod +x $T/bin/*
export PATH="$T/bin:$PATH"
OPENSTACK=$T/bin/openstack
export SEEN=$T/seen

# a virtio-win tree laid out like virtio-win-0.1.266.iso, smbus and all
mkdir -p $T/vw-iso/viostor/2k25/amd64 $T/vw-iso/smbus/2k25/amd64 $T/vw-iso/guest-agent
echo inf > $T/vw-iso/viostor/2k25/amd64/viostor.inf
echo inf > $T/vw-iso/smbus/2k25/amd64/smbus.inf
: > $T/vw-iso/guest-agent/qemu-ga-x86_64.msi
# the rpm layout, smbus under by-os, plus the ISO the rpm ships
mkdir -p $T/vw-rpm/drivers/by-os/amd64/2k25 $T/vw-rpm/viostor/2k25/amd64
echo inf > $T/vw-rpm/viostor/2k25/amd64/viostor.inf
echo inf > $T/vw-rpm/drivers/by-os/amd64/2k25/smbus.inf
: > $T/vw-rpm/virtio-win.iso
# the tree the build ships: no smbus, no ISO
mkdir -p $T/vw-clean/viostor/2k25/amd64
echo inf > $T/vw-clean/viostor/2k25/amd64/viostor.inf

run(){ # VIRTIO_WIN (or "unset")
    rm -f $SEEN
    : > "$T/src/windows_2025.vhdx"
    if [ "$1" = unset ] ; then
        ( unset VIRTIO_WIN; os_image_import $T/src windows_2025.vhdx img "" cinder-volumes CubeStorage windows ) >$T/out 2>&1
    else
        ( export VIRTIO_WIN=$1; os_image_import $T/src windows_2025.vhdx img "" cinder-volumes CubeStorage windows ) >$T/out 2>&1
    fi
}
seen(){ grep "^$1=" $SEEN 2>/dev/null | cut -d= -f2-; }
leftover(){ ls -d /tmp/virtio-win_* 2>/dev/null | wc -l; }

before=$(leftover)

# ==== 1. ISO layout with smbus (fixpack-243 mounted over virtio-win) =========
run $T/vw-iso
chk "iso + smbus: virt-v2v not given the smbus tree" "$([ "$(seen dir)" != $T/vw-iso ] && echo yes)" "yes"
chk "iso + smbus: no smbus or ISO in what virt-v2v got" "$(seen bad)" "0"
chk "iso + smbus: viostor 2k25 still there" "$(seen viostor)" "yes"
chk "iso + smbus: says what it left out" "$(grep -c 'Leaving smbus and ISOs' $T/out)" "1"
chk "iso + smbus: source tree untouched" "$(find $T/vw-iso -iname '*smbus*' | wc -l)" "2"
chk "iso + smbus: temp tree removed" "$(leftover)" "$before"

# ==== 2. rpm layout, smbus under by-os, and virtio-win.iso ===================
run $T/vw-rpm
chk "rpm + smbus + iso: no smbus or ISO in what virt-v2v got" "$(seen bad)" "0"
chk "rpm + smbus + iso: viostor 2k25 still there" "$(seen viostor)" "yes"

# ==== 3. the shipped tree is handed over as it is ============================
run $T/vw-clean
chk "clean tree: VIRTIO_WIN passed through" "$(seen dir)" "$T/vw-clean"
chk "clean tree: nothing printed" "$(grep -c 'Leaving smbus' $T/out)" "0"

# ==== 4. no VIRTIO_WIN and no /usr/share/virtio-win: environment untouched ===
if [ ! -d /usr/share/virtio-win ] ; then
    run unset
    chk "unset: VIRTIO_WIN left unset" "$(seen dir)" "unset"
else
    echo "SKIP unset: /usr/share/virtio-win exists on this host"
fi

# ==== 5. the copy cannot be made: stop, never run virt-v2v on the smbus tree =
mkdir -p $T/nomktemp $T/cwd
printf '#!/bin/bash\n[ "$1" = -d ] && exit 1\nexec /usr/bin/mktemp "$@"\n' > $T/nomktemp/mktemp
chmod +x $T/nomktemp/mktemp
: > $T/cwd/keep.iso
( cd $T/cwd || exit 1; PATH="$T/nomktemp:$PATH" run $T/vw-iso )
chk "mktemp -d fails: says so" "$(grep -c 'Failed to prepare' $T/out)" "1"
chk "mktemp -d fails: virt-v2v not run" "$([ -e $SEEN ] && echo ran || echo no)" "no"
chk "mktemp -d fails: nothing removed from cwd" "$(ls $T/cwd)" "keep.iso"

mkdir -p $T/nocp
printf '#!/bin/bash\n[ "$1" = -rs ] && exit 1\nexec /usr/bin/cp "$@"\n' > $T/nocp/cp
chmod +x $T/nocp/cp
before=$(leftover)
PATH="$T/nocp:$PATH" run $T/vw-iso
chk "cp -rs fails: says so" "$(grep -c 'Failed to prepare' $T/out)" "1"
chk "cp -rs fails: virt-v2v not run" "$([ -e $SEEN ] && echo ran || echo no)" "no"
chk "cp -rs fails: temp tree removed" "$(leftover)" "$before"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: os_image_import virtio-win without smbus"
exit 0
