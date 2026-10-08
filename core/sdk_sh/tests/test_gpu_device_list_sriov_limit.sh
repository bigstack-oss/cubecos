#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh gpu_device_list: which cards report
# sriovVgpuProfileCountLimit (#1583 follow-up).
#
# The Web UI sizes its SR-IOV count control from this field, including on the
# preview of a switch *into* sriovVgpu. The limit used to be computed only for
# a card that was already sriovVgpu, so switching a pgpu, MIG-backed or unset
# card showed "Counts limit: N / -" with no ceiling at all (QA on cn13,
# 2026-10-07). Pinned here:
#
#   1. a visible card that supports sriovVgpu reports the limit whatever its
#      current type - unset, sriovVgpu or migBackedVgpu
#   2. a visible card that does not support sriovVgpu reports null
#   3. a vfio-bound pgpu reports the value gpu_resource_set recorded in
#      config.json, under the same key, and null when nothing was recorded
#
# The ceiling arithmetic itself is test_gpu_sriov_vgpu_count_limit.sh's; here it
# is stubbed so these cases test only which cards get it.
#
# Section 4 is a negative control against the pre-fix code out of git.
#
#   Run: bash test_gpu_device_list_sriov_limit.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

for fn in gpu_device_list gpu_probe_diagnosis gpu_pci_addr_hostdev_pattern gpu_pgpu_holding_domain; do
    eval "$(extract $fn "$GPU_SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GPU_CONFIG_FILE_PATH="$TMP/config.json"
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"

log_error() { :; }
log_debug() { :; }
gpu_support_types_from_xml() { echo '["pgpu","sriovVgpu","migBackedVgpu"]'; }
virsh() { :; }
lspci() { :; }
# Never null, so a null in the listing can only mean the card was not asked.
gpu_sriov_vgpu_count_limit() { echo 32; }

# nvidia-smi stub: the device query answers from $STUB_CSV, `vgpu -s -v` from
# $STUB_TYPES, everything else (vgpu -q) with nothing.
NVIDIA_SMI="$TMP/nvidia-smi"
cat > "$NVIDIA_SMI" <<'STUB'
#!/bin/bash
case "$1" in
    --query-gpu=*) cat "$STUB_CSV" ;;
    vgpu) [ "$2" = "-s" ] && cat "$STUB_TYPES" ;;
esac
exit 0
STUB
chmod +x "$NVIDIA_SMI"
export STUB_CSV="$TMP/csv" STUB_TYPES="$TMP/types"

BOTH_FAMILIES='vGPU Type ID                      : 0x5ee
    Name                          : NVIDIA RTX Pro 6000 Blackwell DC-2B
    Max Instances                 : 32
vGPU Type ID                      : 0x60e
    Name                          : NVIDIA RTX Pro 6000 Blackwell DC-1-2Q
    Max Instances                 : 48'
MIG_ONLY='vGPU Type ID                      : 0x60e
    Name                          : NVIDIA RTX Pro 6000 Blackwell DC-1-2Q
    Max Instances                 : 48'

ID=GPU-29f1b0ad-ada5-c5fb-ac9c-8d8832d6741b
ROW="$ID, NVIDIA RTX PRO 6000 Blackwell, 00000000:42:00.0, 97887"
PGPU_ID=GPU-171566b8-60f0-9c5e-7388-59b5583f7b97

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

visible() {  # <config.json> <vgpu -s -v output>
    echo "$1" > "$GPU_CONFIG_FILE_PATH"
    echo "$ROW" > "$STUB_CSV"
    printf '%s\n' "$2" > "$STUB_TYPES"
}
limit_of() { gpu_device_list | jq -c --arg id "$1" '.[] | select(.id == $id) | .sriovVgpuProfileCountLimit'; }

# --- 1. visible card that supports sriovVgpu: limit whatever its type ---------
visible '[]' "$BOTH_FAMILIES"
ck "$(limit_of $ID)" "32" "unset card -> limit reported"

visible "[{\"id\":\"$ID\",\"type\":\"migBackedVgpu\",\"pciAddress\":\"00000000:42:00.0\",\"profiles\":[{\"id\":1569,\"count\":5}]}]" "$BOTH_FAMILIES"
ck "$(limit_of $ID)" "32" "migBackedVgpu card -> limit reported"

visible "[{\"id\":\"$ID\",\"type\":\"sriovVgpu\",\"pciAddress\":\"00000000:42:00.0\",\"profiles\":[{\"id\":1518,\"count\":4}]}]" "$BOTH_FAMILIES"
ck "$(limit_of $ID)" "32" "sriovVgpu card -> limit reported (unchanged)"

# --- 2. visible card without SR-IOV types: null -------------------------------
visible "[{\"id\":\"$ID\",\"type\":\"migBackedVgpu\",\"pciAddress\":\"00000000:42:00.0\",\"profiles\":[]}]" "$MIG_ONLY"
ck "$(limit_of $ID)" "null" "card with no SR-IOV types -> null"
visible '[]' "$MIG_ONLY"
ck "$(limit_of $ID)" "null" "unset card with no SR-IOV types -> null"

# --- 3. vfio-bound pgpu: the recorded value, under the same key ---------------
: > "$STUB_CSV"
echo "[{\"id\":\"$PGPU_ID\",\"type\":\"pgpu\",\"pciAddress\":\"00000001:04:00.0\",\"totalVramMiB\":97887,\"sriovVgpuProfileCountLimit\":32}]" > "$GPU_CONFIG_FILE_PATH"
list=$(gpu_device_list)
ck "$(echo "$list" | jq -c '.[0].sriovVgpuProfileCountLimit')" "32" "pgpu -> recorded limit reported"
ck "$(echo "$list" | jq -c '.[0] | has("profileCountLimit")')" "false" "pgpu -> no stray profileCountLimit key"

echo "[{\"id\":\"$PGPU_ID\",\"type\":\"pgpu\",\"pciAddress\":\"00000001:04:00.0\",\"totalVramMiB\":97887}]" > "$GPU_CONFIG_FILE_PATH"
list=$(gpu_device_list)
ck "$(echo "$list" | jq -c '.[0].sriovVgpuProfileCountLimit')" "null" "pgpu recorded before the field -> null"
ck "$(echo "$list" | jq -c '.[0] | has("sriovVgpuProfileCountLimit")')" "true" "pgpu -> key present even when null"

# --- 4. negative control: the pre-fix code, straight out of git ----------------
BEFORE_REF="69c67285"
if git -C "$DIR" rev-parse --verify --quiet "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" >/dev/null 2>&1; then
    old_src="$TMP/sdk_gpu.before.sh"
    git -C "$DIR" show "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" > "$old_src"
    eval "$(extract gpu_device_list "$old_src" | sed 's/^gpu_device_list()/old_gpu_device_list()/')"

    visible "[{\"id\":\"$ID\",\"type\":\"migBackedVgpu\",\"pciAddress\":\"00000000:42:00.0\",\"profiles\":[{\"id\":1569,\"count\":5}]}]" "$BOTH_FAMILIES"
    ck "$(old_gpu_device_list | jq -c '.[0].sriovVgpuProfileCountLimit')" "null" \
       "control: pre-fix code gave a migBackedVgpu card no limit"
    ck "$(limit_of $ID)" "32" "control: same stubs, fixed code reports it"
else
    echo "SKIP: negative control needs git object $BEFORE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
