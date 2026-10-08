#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh, covering #1759:
#
#   gpu_bind_vfio_pci bound only the card's display function. A workstation
#   card (RTX A2000 at 86:00.0) also has an HD-audio function at 86:00.1 in the
#   same IOMMU group, which stayed on snd_hda_intel, so qemu refused every pgpu
#   VM with "vfio 0000:86:00.0: group 26 is not viable".
#
# Pinned here:
#
#   gpu_vfio_card_functions -- the card is its own function plus the other
#                              functions of the same slot in its IOMMU group;
#                              bridges and other slots are not part of it.
#   gpu_bind_vfio_pci       -- binds all of them, all or nothing.
#   gpu_unbind_vfio_pci     -- releases all of them; only the display function
#                              has to reach a native driver.
#   gpu_device_list         -- a companion on vfio-pci carries NVIDIA's vendor
#                              id too and must not be listed as a card.
#
# Section 5 is a negative control: the device-list scan taken out of git before
# the fix lists the audio function, so these tests cannot pass for the wrong
# reason.
#
#   Run: bash test_gpu_vfio_card_functions.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# sysfs stand-in: every function under test reads /sys/bus/pci/..., so point
# that prefix at a fake tree.
SYS="$TMP/sys"
load() {
    local fn
    for fn in "$@"; do
        eval "$(extract "$fn" "$GPU_SRC" | sed "s#/sys/bus/pci/#$SYS/#g")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
    done
}
load gpu_pci_addr_normalize gpu_vfio_card_functions gpu_bind_vfio_pci gpu_unbind_vfio_pci

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# dev <addr> <class> <driver|-> <group>
dev() {
    mkdir -p "$SYS/devices/$1" "$SYS/drivers/vfio-pci" "$SYS/groups/$4/devices"
    echo "$2" > "$SYS/devices/$1/class"
    [ "$3" = "-" ] || { mkdir -p "$SYS/drivers/$3"; ln -sfn "$SYS/drivers/$3" "$SYS/devices/$1/driver"; }
    ln -sfn "$SYS/groups/$4" "$SYS/devices/$1/iommu_group"
    ln -sfn "$SYS/devices/$1" "$SYS/groups/$4/devices/$1"
}
reset_sys() { rm -rf "$SYS"; }

# The node from #1759: the A2000's display and audio functions in group 26,
# with the root port above it sharing the group.
a2000() {
    reset_sys
    dev 0000:85:00.0 0x060400 pcieport 26
    dev 0000:86:00.0 0x030000 nvidia 26
    dev 0000:86:00.1 0x040300 snd_hda_intel 26
}

# ---------------------------------------------------------------- 1. membership
a2000
ck "$(gpu_vfio_card_functions 0000:86:00.0 | tr '\n' ' ')" "0000:86:00.0 0000:86:00.1 " \
   "the card is its display and audio function, display first; the root port is not part of it"

reset_sys
dev 0000:3b:00.0 0x030200 nvidia 40
ck "$(gpu_vfio_card_functions 0000:3b:00.0 | tr '\n' ' ')" "0000:3b:00.0 " \
   "a datacenter card without companions is its one function"

reset_sys
mkdir -p "$SYS/devices/0000:3b:00.0"
ck "$(gpu_vfio_card_functions 0000:3b:00.0 | tr '\n' ' ')" "0000:3b:00.0 " \
   "with the IOMMU off there is no group, and the card is the given function"

# A neighbour behind a switch without ACS shares the group but is another card.
reset_sys
dev 0000:86:00.0 0x030000 nvidia 26
dev 0000:86:00.1 0x040300 snd_hda_intel 26
dev 0000:87:00.0 0x020000 ice 26
ck "$(gpu_vfio_card_functions 0000:86:00.0 | tr '\n' ' ')" "0000:86:00.0 0000:86:00.1 " \
   "another slot in the same group is never taken"

# ----------------------------------------- 2. bind: every function, all or nothing
# The single-function primitives touch the kernel; record the calls instead.
# Driven through files so the record survives command substitutions.
CALLS="$TMP/calls"; FAIL_ON="$TMP/fail_on"
gpu_bind_vfio_pci_function() {
    echo "bind $1" >> "$CALLS"
    grep -qx "bind $1" "$FAIL_ON" 2>/dev/null && return 1
    return 0
}
gpu_unbind_vfio_pci_function() {
    echo "unbind $1 ${2:-native}" >> "$CALLS"
    grep -qx "unbind $1" "$FAIL_ON" 2>/dev/null && return 1
    return 0
}
calls() { tr '\n' ';' < "$CALLS"; }
run() { : > "$CALLS"; : > "$FAIL_ON"; [ $# -gt 0 ] && printf '%s\n' "$@" > "$FAIL_ON"; }

a2000; run
gpu_bind_vfio_pci 00000000:86:00.0 2>/dev/null; rc=$?
ck "$rc" 0 "bind of the A2000 succeeds"
ck "$(calls)" "bind 0000:86:00.0;bind 0000:86:00.1;" \
   "bind takes the audio function along (config.json's 8-char domain is accepted)"

a2000; run "bind 0000:86:00.1"
gpu_bind_vfio_pci 00000000:86:00.0 2>/dev/null; rc=$?
ck "$rc" 1 "a companion that will not bind fails the bind"
ck "$(calls)" "bind 0000:86:00.0;bind 0000:86:00.1;unbind 0000:86:00.0 any;" \
   "and the display function this call moved is handed back"

# Commit() re-apply on a card whose display function is already on vfio-pci:
# a failed companion must not tear down the passthrough that was already there.
a2000; ln -sfn "$SYS/drivers/vfio-pci" "$SYS/devices/0000:86:00.0/driver"; run "bind 0000:86:00.1"
gpu_bind_vfio_pci 00000000:86:00.0 2>/dev/null
ck "$(calls)" "bind 0000:86:00.0;bind 0000:86:00.1;" \
   "a function that was already on vfio-pci is not rolled back"

a2000; run
gpu_bind_vfio_pci "No devices were found" 2>/dev/null; rc=$?
ck "$rc:$(calls)" "1:" "a non-address is refused before anything is touched"

# A foreign endpoint held by a host driver is reported, not taken.
reset_sys
dev 0000:86:00.0 0x030000 nvidia 26
dev 0000:87:00.0 0x020000 ice 26
run
err=$(gpu_bind_vfio_pci 00000000:86:00.0 2>&1 >/dev/null); rc=$?
ck "$rc:$(calls)" "0:bind 0000:86:00.0;" "a foreign endpoint does not fail the bind and is not bound"
case "$err" in *"0000:87:00.0 shares the IOMMU group"*"held by ice"*) r=warned ;; *) r="$err" ;; esac
ck "$r" warned "the foreign endpoint that will block passthrough is named"

a2000; run
err=$(gpu_bind_vfio_pci 00000000:86:00.0 2>&1 >/dev/null)
ck "$err" "" "a bridge sharing the group is not warned about"

# ------------------------------------------------------------------- 3. unbind
a2000; run
gpu_unbind_vfio_pci 00000000:86:00.0 2>/dev/null; rc=$?
ck "$rc" 0 "release of the A2000 succeeds"
ck "$(calls)" "unbind 0000:86:00.0 native;unbind 0000:86:00.1 any;" \
   "release hands back the audio function too; only the display function must reach a native driver"

a2000; run "unbind 0000:86:00.0"
gpu_unbind_vfio_pci 00000000:86:00.0 2>/dev/null; rc=$?
ck "$rc:$(calls)" "1:unbind 0000:86:00.0 native;" \
   "a display function that will not come back fails the release and stops there"

a2000; run "unbind 0000:86:00.1"
gpu_unbind_vfio_pci 00000000:86:00.0 2>/dev/null; rc=$?
ck "$rc" 1 "a companion still on vfio-pci fails the release"

# ------------------------------------- 4. unbind primitive: "any" accepts driverless
# The real primitive, against the fake tree: nothing re-probes, so after the
# unbind write the device has whatever driver link the test leaves in place.
unset -f gpu_unbind_vfio_pci_function
load gpu_unbind_vfio_pci_function
reset_sys
dev 0000:86:00.1 0x040300 - 26
: > "$SYS/drivers_probe"; : > "$SYS/devices/0000:86:00.1/driver_override"
gpu_unbind_vfio_pci_function 0000:86:00.1 any 2>/dev/null; rc=$?
ck "$rc" 0 "with 'any', a companion left driverless counts as released"
gpu_unbind_vfio_pci_function 0000:86:00.1 2>/dev/null; rc=$?
ck "$rc" 1 "without it, driverless is still a failure (the display function's rule is unchanged)"
ln -sfn "$SYS/drivers/vfio-pci" "$SYS/devices/0000:86:00.1/driver"
: > "$SYS/drivers/vfio-pci/unbind"
gpu_unbind_vfio_pci_function 0000:86:00.1 any 2>/dev/null; rc=$?
ck "$rc" 1 "with 'any', still being on vfio-pci is a failure"

# ---------------------------------------------- 5. device list: companions are not cards
GPU_CONFIG_FILE_PATH="$TMP/config.json"; echo '[]' > "$GPU_CONFIG_FILE_PATH"
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"
log_error() { :; }
log_debug() { :; }
gpu_support_types_from_xml() { echo '["pgpu"]'; }
gpu_pgpu_holding_domain() { :; }
virsh() { :; }
lspci() {
    case "$*" in
        *-s*) echo "86:00.0 VGA compatible controller: NVIDIA Corporation GA106 [RTX A2000 12GB]" ;;
        *) printf '%s\n' "0000:86:00.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:2571]" \
                         "0000:86:00.1 Audio device [0403]: NVIDIA Corporation [10de:228e]" ;;
    esac
}
NVIDIA_SMI="$TMP/nvidia-smi"
printf '#!/bin/bash\necho "No devices were found"\nexit 6\n' > "$NVIDIA_SMI"; chmod +x "$NVIDIA_SMI"
gpu_is_installed() { return 0; }

a2000
ln -sfn "$SYS/drivers/vfio-pci" "$SYS/devices/0000:86:00.0/driver"
ln -sfn "$SYS/drivers/vfio-pci" "$SYS/devices/0000:86:00.1/driver"

load gpu_sysfs_pci_addr gpu_probe_diagnosis gpu_device_list
listed=$(gpu_device_list 2>/dev/null | jq -r '[.[].pciAddress] | join(" ")' 2>/dev/null)
ck "$listed" "00000000:86:00.0" "only the display function of a vfio-bound card is listed"

# Negative control: the same fixture against the pre-fix scan, pinned to the
# commit this fix was written against. Soft-skipped where git or the object is
# unavailable (exported trees, shallow clones).
BEFORE_REF="4dde3b12"
if git -C "$DIR" rev-parse --verify --quiet "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" >/dev/null 2>&1; then
    old_src="$TMP/sdk_gpu.before.sh"
    git -C "$DIR" show "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" > "$old_src"
    eval "$(extract gpu_device_list "$old_src" | sed "s#/sys/bus/pci/#$SYS/#g")"
    listed=$(gpu_device_list 2>/dev/null | jq -r '[.[].pciAddress] | join(" ")' 2>/dev/null)
    ck "$listed" "00000000:86:00.0 00000000:86:00.1" \
       "control: pre-fix scan lists the vfio-bound audio function as a card of its own"
else
    echo "SKIP: negative control needs git object $BEFORE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
