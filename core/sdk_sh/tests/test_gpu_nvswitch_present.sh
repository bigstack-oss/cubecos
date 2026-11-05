#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh, covering #2255:
#
#   nvlink_enable must refuse to start nvidia-fabricmanager without an NVSwitch
#   fabric. A bridge-other class alone also matches the 1cc Intel ACPI bridge;
#   require NVIDIA's vendor too. NVL5+ is a Mellanox device whose PCI VPD
#   carries SW_MNG, which is there before the InfiniBand driver is.
#
# Section 4 is a negative control: removing the vendor comparison makes the
# 1cc tree look like an NVSwitch fabric, proving that fixture catches the bug.
#
#   Run: bash test_gpu_nvswitch_present.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# sysfs stand-in: point the PCI prefix at a fake tree.
SYS="$TMP/sys"
load() {
    local fn
    for fn in "$@"; do
        eval "$(extract "$fn" "$GPU_SRC" | sed "s#/sys/bus/pci/#$SYS/pci/#g")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
    done
}
load gpu_nvswitch_present

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# dev <addr> <vendor> <class>
dev() {
    mkdir -p "$SYS/pci/devices/$1"
    echo "$2" > "$SYS/pci/devices/$1/vendor"
    echo "$3" > "$SYS/pci/devices/$1/class"
}
reset_sys() { rm -rf "$SYS"; mkdir -p "$SYS/pci/devices"; }
one_cc() {
    reset_sys
    dev 0000:00:01.3 0x8086 0x068000
    dev 0000:00:02.0 0x1234 0x030000
}

# --------------------------------------------------------------- 1. PCI fabric
reset_sys
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "empty PCI devices and missing InfiniBand class have no fabric"

one_cc
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "the 1cc Intel ACPI bridge is not an NVSwitch"

reset_sys
dev 0000:3b:00.0 0x10de 0x030200
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "an NVIDIA GPU alone has no NVSwitch fabric"

dev 0000:3c:00.0 0x10de 0x068000
gpu_nvswitch_present; rc=$?
ck "$rc" 0 "an NVIDIA bridge-other device identifies an NVSwitch fabric"

# -------------------------------------------------------------- 2. NVL5 fabric
# No /sys/class/infiniband at all: the VPD is read from the PCI device.
reset_sys
dev 0000:1a:00.0 0x15b3 0x020700
printf '\000\001prefixSW_MNGsuffix\000\377' > "$SYS/pci/devices/0000:1a:00.0/vpd"
gpu_nvswitch_present; rc=$?
ck "$rc" 0 "a Mellanox device with SW_MNG in its VPD identifies NVL5 without an NVSwitch on PCI"

printf '\000\001ordinary ConnectX\000\377' > "$SYS/pci/devices/0000:1a:00.0/vpd"
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "an ordinary ConnectX VPD does not identify an NVSwitch fabric"

reset_sys
dev 0000:1a:00.0 0x8086 0x020000
printf 'SW_MNG' > "$SYS/pci/devices/0000:1a:00.0/vpd"
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "SW_MNG only counts on a Mellanox device"

reset_sys
dev 0000:1a:00.0 0x15b3 0x020700
gpu_nvswitch_present; rc=$?
ck "$rc" 1 "a Mellanox device without a readable VPD has no fabric"

# ----------------------------------------------------------------- 3. silence
dev 0000:3c:00.0 0x10de 0x068000
out=$(gpu_nvswitch_present); rc=$?
ck "$rc:$out" "0:" "a true result prints nothing on stdout"

# -------------------------------------------------------- 4. negative control
# Make the NVIDIA vendor comparison always true; the class comparison stays.
one_cc
eval "$(extract gpu_nvswitch_present "$GPU_SRC" |
    sed "s#/sys/bus/pci/#$SYS/pci/#g" |
    sed 's/\[ "\$vendor" = "0x10de" \]/true/')"
gpu_nvswitch_present; rc=$?
ck "$rc" 0 "control: without the vendor comparison the 1cc bridge wrongly counts as an NVSwitch"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
