#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh, covering one defect family (#1486):
#
#   nvidia-smi reports "No devices were found" on *stdout*, with an EMPTY stderr
#   and a non-zero exit. So `cmd 2>/dev/null` plus a test for an empty result
#   never sees the failure -- the error sentence is returned as if it were data.
#
# That is the normal state of a node whose cards are all pgpu: a card bound to
# vfio-pci (or an SR-IOV PF held by pci-pf-stub with no VFs enabled) is invisible
# to nvidia-smi, which is precisely the case the affected code was written for.
#
# Two readers are pinned here:
#
#   gpu_sysfs_pci_addr -- returned the sentence as a PCI address, so callers
#                         built paths like /sys/bus/pci/devices/no devices were
#                         found/ and reported "cannot read X" against nonsense.
#   gpu_device_list    -- read the sentence as a one-field CSV row and enumerated
#                         it as a card with that sentence as its id.
#
# Section 5 is a negative control: the same stubs against the pre-fix code taken
# out of git, so a future refactor that quietly reintroduces the emptiness test
# cannot leave these tests passing for the wrong reason.
#
#   Run: bash test_gpu_nvidia_smi_no_devices.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

eval "$(extract gpu_pci_addr_normalize "$GPU_SRC")"
eval "$(extract gpu_sysfs_pci_addr "$GPU_SRC")"
eval "$(extract gpu_device_list "$GPU_SRC")"
eval "$(extract gpu_probe_diagnosis "$GPU_SRC")"
for fn in gpu_pci_addr_normalize gpu_sysfs_pci_addr gpu_device_list gpu_probe_diagnosis ; do
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GPU_CONFIG_FILE_PATH="$TMP/config.json"
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"

log_error() { :; }
log_debug() { :; }
# The node has no vGPU XML, no running domains and nothing else on the PCI bus:
# every card in these fixtures reaches the list through config.json alone.
gpu_support_types_from_xml() { echo '["pgpu"]'; }
virsh() { :; }
lspci() { :; }

# nvidia-smi stub. Driven through files rather than exported variables so the
# same stub answers from inside a command substitution.
NVIDIA_SMI="$TMP/nvidia-smi"
cat > "$NVIDIA_SMI" <<'STUB'
#!/bin/bash
cat "$STUB_OUT"
cat "$STUB_ERR" >&2
exit "$(cat "$STUB_RC")"
STUB
chmod +x "$NVIDIA_SMI"
export STUB_OUT="$TMP/out" STUB_ERR="$TMP/err" STUB_RC="$TMP/rc"
smi() { printf '%s' "$1" > "$STUB_OUT"; printf '%s' "${2:-}" > "$STUB_ERR"; printf '%s' "${3:-0}" > "$STUB_RC"; }

# What a vfio-bound card actually produces. Measured on cn13, 2026-09-14:
# rc 6, the sentence on stdout, stderr empty.
no_devices() { smi "No devices were found" "" 6; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

PGPU='{"id":"GPU-171566b8-60f0-9c5e-7388-59b5583f7b97","name":"NVIDIA RTX PRO 6000","type":"pgpu","pciAddress":"00000001:04:00.0","totalVramMiB":97887}'
VGPU='{"id":"GPU-c0ffee00-0000-0000-0000-000000000001","name":"NVIDIA RTX A2000","type":"sriovVgpu","pciAddress":"00000000:86:00.0"}'
PGPU_ID="GPU-171566b8-60f0-9c5e-7388-59b5583f7b97"

# --- 1. gpu_pci_addr_normalize: shape is checked, not assumed ------------------
ck "$(gpu_pci_addr_normalize '00000001:04:00.0')" "0001:04:00.0" "normalize: 8-digit domain trimmed"
ck "$(gpu_pci_addr_normalize '0000:86:00.0')"     "0000:86:00.0" "normalize: 4-digit domain kept"
ck "$(gpu_pci_addr_normalize '00000000:BB:1A.0')" "0000:bb:1a.0" "normalize: lower-cased"
ck "$(gpu_pci_addr_normalize '  0001:04:00.0 ')"  "0001:04:00.0" "normalize: surrounding space"

# The exact regression. Note what the old code actually did: its
# `sed 's/^[0-9a-fA-F]\{4\}//'` domain trim does not match "No d" -- 'N' is not a
# hex digit -- so the sentence was not even truncated, it was lower-cased and
# passed straight through as an address. Trimming is not a validity test.
gpu_pci_addr_normalize 'No devices were found' >/dev/null 2>&1
ck "$?" "1" "normalize: error sentence rejected"
ck "$(gpu_pci_addr_normalize 'No devices were found' 2>/dev/null)" "" "normalize: rejected means no output"
gpu_pci_addr_normalize '' >/dev/null 2>&1;              ck "$?" "1" "normalize: empty rejected"
gpu_pci_addr_normalize '0001:04:00' >/dev/null 2>&1;    ck "$?" "1" "normalize: truncated address rejected"
gpu_pci_addr_normalize '000:04:00.0' >/dev/null 2>&1;   ck "$?" "1" "normalize: short domain rejected"
gpu_pci_addr_normalize 'zzzz:04:00.0' >/dev/null 2>&1;  ck "$?" "1" "normalize: non-hex rejected"

# --- 2. gpu_sysfs_pci_addr ----------------------------------------------------
echo "[$PGPU,$VGPU]" > "$GPU_CONFIG_FILE_PATH"

# 2a. The card is visible: the answer comes from nvidia-smi.
smi "00000000:86:00.0"
ck "$(gpu_sysfs_pci_addr GPU-c0ffee00-0000-0000-0000-000000000001)" "0000:86:00.0" \
   "visible card -> address from nvidia-smi"

# 2b. #1486 itself: vfio-bound card, nvidia-smi fails on stdout, the fallback
# that was written for exactly this case must now actually run.
no_devices
out=$(gpu_sysfs_pci_addr "$PGPU_ID"); rc=$?
ck "$out" "0001:04:00.0" "vfio-bound card -> address from config.json"
ck "$rc" "0" "vfio-bound card -> exit 0"

# 2c. No answer anywhere: empty output and non-zero, never a sentence.
no_devices
out=$(gpu_sysfs_pci_addr GPU-does-not-exist); rc=$?
ck "$out" "" "unknown card -> no output"
ck "$rc" "1" "unknown card -> non-zero"

# 2d. The shape check is not redundant with the exit status: a message that
# exits 0 must not get through either.
smi "Unable to determine the device handle for GPU" "" 0
ck "$(gpu_sysfs_pci_addr "$PGPU_ID")" "0001:04:00.0" "garbage at exit 0 -> still falls back"

smi "Unable to determine the device handle for GPU" "" 0
out=$(gpu_sysfs_pci_addr GPU-does-not-exist); rc=$?
ck "$out" "" "garbage at exit 0, nothing recorded -> no output"
ck "$rc" "1" "garbage at exit 0, nothing recorded -> non-zero"

# 2e. config.json unreadable is a failure, not an empty-string success.
mv "$GPU_CONFIG_FILE_PATH" "$TMP/config.json.away"
no_devices
out=$(gpu_sysfs_pci_addr "$PGPU_ID"); rc=$?
ck "$out" "" "no config.json -> no output"
ck "$rc" "1" "no config.json -> non-zero"
mv "$TMP/config.json.away" "$GPU_CONFIG_FILE_PATH"

# --- 3. gpu_device_list: the sentence must not become a card ------------------
# A node whose only card is pgpu. nvidia-smi sees nothing, so the whole list is
# built from config.json -- one card, and no phantom.
echo "[$PGPU]" > "$GPU_CONFIG_FILE_PATH"
no_devices
list=$(gpu_device_list); rc=$?
ck "$rc" "0" "all-pgpu node -> gpu_device_list succeeds"
ck "$(echo "$list" | jq 'length')" "1" "all-pgpu node -> exactly one card"
ck "$(echo "$list" | jq -r '.[0].id')" "$PGPU_ID" "all-pgpu node -> the real card"
ck "$(echo "$list" | jq '[.[] | select(.id | test("devices were found"; "i"))] | length')" "0" \
   "all-pgpu node -> no phantom card from the error sentence"

# An empty config.json on such a node is an empty list, not a one-card list.
echo "[]" > "$GPU_CONFIG_FILE_PATH"
no_devices
ck "$(gpu_device_list | jq 'length')" "0" "no cards at all -> empty list"

# --- 4. a visible card still enumerates ---------------------------------------
echo "[$VGPU]" > "$GPU_CONFIG_FILE_PATH"
smi "GPU-c0ffee00-0000-0000-0000-000000000001, NVIDIA RTX A2000, 00000000:86:00.0, 6144"
list=$(gpu_device_list)
ck "$(echo "$list" | jq 'length')" "1" "visible card -> enumerated once"
ck "$(echo "$list" | jq -r '.[0].id')" "GPU-c0ffee00-0000-0000-0000-000000000001" \
   "visible card -> id from nvidia-smi"
ck "$(echo "$list" | jq -r '.[0].totalVramMiB')" "6144" "visible card -> framebuffer measured"

# --- 5. negative control: the pre-fix code, straight out of git ----------------
# Pinned to the commit these fixtures were written against rather than a moving
# branch, so the control keeps testing the code that actually had the defect.
# Soft-skipped where git or the object is unavailable (exported trees, shallow
# clones) -- a missing control must not fail the suite.
BEFORE_REF="0d815005"
if git -C "$DIR" rev-parse --verify --quiet "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" >/dev/null 2>&1; then
    old_src="$TMP/sdk_gpu.before.sh"
    git -C "$DIR" show "$BEFORE_REF:core/sdk_sh/modules/sdk_gpu.sh" > "$old_src"

    old_fn=$(extract gpu_sysfs_pci_addr "$old_src")
    if [ -n "$old_fn" ]; then
        eval "${old_fn/gpu_sysfs_pci_addr()/old_gpu_sysfs_pci_addr()}"

        echo "[$PGPU]" > "$GPU_CONFIG_FILE_PATH"
        no_devices
        ck "$(old_gpu_sysfs_pci_addr "$PGPU_ID")" "no devices were found" \
           "control: pre-fix code returned the error sentence as an address"
        ck "$(gpu_sysfs_pci_addr "$PGPU_ID")" "0001:04:00.0" \
           "control: same stubs, fixed code returns the address"
    else
        echo "SKIP: gpu_sysfs_pci_addr not found at $BEFORE_REF"
    fi
else
    echo "SKIP: negative control needs git object $BEFORE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
