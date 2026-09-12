#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh:
#   gpu_device_profile_ensure -- creates a pgpu card's Cyborg device profile
#                                without asking Cyborg about the card (#818).
#
# The point of the design is the timing: gpu_resource_set calls this the instant
# a carve succeeds, but cyborg's nvidia driver only rescans hex's config.json on
# its agent period (periodic_interval, default 60s), so the card is not in the
# accelerator inventory yet. Everything needed must come from config.json and
# sysfs. These tests pin that -- there is no accelerator-device stub here at all,
# so any code path that grew a dependency on one would fail.
#
#   Run: bash test_gpu_device_profile_ensure.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"
OS_SRC="$DIR/../modules/sdk_os.sh"
eval "$(awk '/^_gpu_load_os_module\(\)/{f=1} f{print} f&&/^}/{exit}' "$GPU_SRC")"
eval "$(awk '/^gpu_device_profile_ensure\(\)/{f=1} f{print} f&&/^}/{exit}' "$GPU_SRC")"
eval "$(awk '/^os_device_profile_name_for\(\)/{f=1} f{print} f&&/^}/{exit}' "$OS_SRC")"
eval "$(awk '/^os_device_profile_groups_for\(\)/{f=1} f{print} f&&/^}/{exit}' "$OS_SRC")"
for fn in _gpu_load_os_module gpu_device_profile_ensure os_device_profile_name_for os_device_profile_groups_for ; do
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GPU_CONFIG_FILE_PATH="$TMP/config.json"

LOGFILE="$TMP/log"; : > "$LOGFILE"
log_error() { printf '%s\n' "$1" >> "$LOGFILE"; }
log_debug() { :; }

# sysfs stand-in. The function derives the address from config.json and reads
# /sys/bus/pci/devices/<addr>/device, so point that prefix at a fake tree.
SYSFS="$TMP/sys"; mkdir -p "$SYSFS/0000:86:00.0"
echo "0x2531" > "$SYSFS/0000:86:00.0/device"
eval "$(declare -f gpu_device_profile_ensure | sed "s#/sys/bus/pci/devices/#$SYSFS/#")"

# Deliberately poisoned: a pgpu card is bound to vfio-pci, and nvidia-smi prints
# "No devices were found" on stdout for it (rc 6, empty stderr), so this helper
# hands back that sentence as if it were an address. The function must not be
# using it. A real node reproduced exactly this.
gpu_sysfs_pci_addr() { printf '%s' "no devices were found"; }

MOCK_NAMES="" MOCK_NAMES_RC=0
os_device_profile_names() { [ "$MOCK_NAMES_RC" = 0 ] || return "$MOCK_NAMES_RC"; printf '%s' "$MOCK_NAMES"; }

CREATED="$TMP/created"; : > "$CREATED"
MOCK_CREATE_RC=0
os_device_profile_create_with() {
    printf '%s|%s|%s\n' "$1" "$2" "${3:-1}" >> "$CREATED"
    [ "$MOCK_CREATE_RC" = 0 ] || return "$MOCK_CREATE_RC"
    echo "$1"
}

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# config.json stores an 8-digit PCI domain; sysfs uses 4 (0000:86:00.0).
PGPU='{"id":"GPU-a","name":"NVIDIA RTX A2000","type":"pgpu","pciAddress":"00000000:86:00.0"}'
NOADDR='{"id":"GPU-d","name":"NVIDIA RTX A2000","type":"pgpu"}'
VGPU='{"id":"GPU-c","name":"NVIDIA RTX A2000","type":"sriovVgpu","pciAddress":"00000000:42:00.0"}'

# --- 1. profile missing -> created from config.json + sysfs, no Cyborg lookup --
: > "$CREATED"; echo "[$PGPU]" > "$GPU_CONFIG_FILE_PATH"; MOCK_NAMES="tesla_t4_1"
ck "$(gpu_device_profile_ensure GPU-a)" "rtx_a2000_1" "missing profile -> created"
ck "$(cat "$CREATED")" "rtx_a2000_1|2531|1" "created with the sysfs product id"

# --- 2. idempotent: already there -> no second create -------------------------
: > "$CREATED"; MOCK_NAMES="rtx_a2000_1"
ck "$(gpu_device_profile_ensure GPU-a)" "rtx_a2000_1" "existing profile -> reported"
ck "$(wc -l < "$CREATED" | tr -d ' ')" "0" "existing profile -> no create call"

# --- 3. a non-pgpu card is a no-op, not an error ------------------------------
: > "$CREATED"; echo "[$VGPU]" > "$GPU_CONFIG_FILE_PATH"; MOCK_NAMES=""
out=$(gpu_device_profile_ensure GPU-c); rc=$?
ck "$rc" "0" "sriovVgpu card -> success"
ck "$out" "" "sriovVgpu card -> no name"
ck "$(wc -l < "$CREATED" | tr -d ' ')" "0" "sriovVgpu card -> no create call"

# --- 4. failure paths ----------------------------------------------------------
echo "[$PGPU]" > "$GPU_CONFIG_FILE_PATH"
gpu_device_profile_ensure "" >/dev/null 2>&1;      ck "$?" "1" "empty id -> non-zero"
gpu_device_profile_ensure GPU-nope >/dev/null 2>&1; ck "$?" "1" "unknown card -> non-zero"

MOCK_NAMES_RC=1
gpu_device_profile_ensure GPU-a >/dev/null 2>&1;   ck "$?" "1" "Cyborg unreachable -> non-zero"
MOCK_NAMES_RC=0

MOCK_NAMES=""
echo "[$NOADDR]" > "$GPU_CONFIG_FILE_PATH"
gpu_device_profile_ensure GPU-d >/dev/null 2>&1;   ck "$?" "1" "no recorded pciAddress -> non-zero"
echo "[$PGPU]" > "$GPU_CONFIG_FILE_PATH"

rm -f "$SYSFS/0000:86:00.0/device"
gpu_device_profile_ensure GPU-a >/dev/null 2>&1;   ck "$?" "1" "unreadable product id -> non-zero"
echo "0x2531" > "$SYSFS/0000:86:00.0/device"

MOCK_CREATE_RC=1
gpu_device_profile_ensure GPU-a >/dev/null 2>&1;   ck "$?" "1" "create failure propagates"
MOCK_CREATE_RC=0

# --- 5. the groups document the profile is created with -----------------------
ck "$(os_device_profile_groups_for 2531 1)" \
   '[{"resources:PGPU": 1, "trait:CUSTOM_GPU_PRODUCT_ID_2531": "required", "trait:CUSTOM_GPU_NVIDIA": "required"}]' \
   "groups: one unit"
ck "$(os_device_profile_groups_for 2bb5 2 | jq 'length')" "2" "groups: units=2 gives two groups"
ck "$(os_device_profile_groups_for 2bb5 1 | jq -r '.[0]["trait:CUSTOM_GPU_PRODUCT_ID_2BB5"]')" \
   "required" "groups: product id is upper-cased"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
