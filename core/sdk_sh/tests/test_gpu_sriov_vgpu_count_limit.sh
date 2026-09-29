#!/bin/bash
#
# Unit test for gpu_sriov_vgpu_count_limit in ../modules/sdk_gpu.sh (#1583):
# the SR-IOV vGPU count limit gpu_device_list reports as
# sriovVgpuProfileCountLimit is min(sriov_totalvfs, the largest Max Instances
# among the card's SR-IOV types) - not sriov_totalvfs alone.
#
# Self-contained: extracts just that function, so it needs no GPU and no NVIDIA
# driver. The fixture is cut from `nvidia-smi vgpu -s -v` on cn13's RTX PRO
# 6000 Blackwell (driver 580.105.06, 2026-09-29).
#   Run: bash test_gpu_sriov_vgpu_count_limit.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_gpu.sh"
eval "$(awk '/^gpu_sriov_vgpu_count_limit\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t gpu_sriov_vgpu_count_limit)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

# constant the extracted function reads, copied from the top of sdk_gpu.sh
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"

FAILS=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  ok  $desc"
    else
        echo "FAIL: $desc -- expected '$expected', got '$actual'"
        FAILS=$((FAILS + 1))
    fi
}

# SR-IOV types reach 32 at most. The MIG-backed DC-1-2Q reports 48, which is
# also the PF's sriov_totalvfs - counting it would put the limit right back
# where the bug had it.
CN13='GPU 00000000:8C:00.0
    vGPU Type ID                          : 0x5ee
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-2B
        Class                             : NVS
        GPU Instance Profile ID           : N/A
        Max Instances                     : 32
        Max Instances Per VM              : 1
        Max Instances Per GI              : N/A
        FB Memory                         : 2048 MiB
    vGPU Type ID                          : 0x5f1
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-4Q
        Class                             : Quadro
        GPU Instance Profile ID           : N/A
        Max Instances                     : 24
        Max Instances Per VM              : 16
        Max Instances Per GI              : N/A
        FB Memory                         : 4096 MiB
    vGPU Type ID                          : 0x604
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-48Q
        Class                             : Quadro
        GPU Instance Profile ID           : N/A
        Max Instances                     : 2
        Max Instances Per VM              : 16
        Max Instances Per GI              : N/A
        FB Memory                         : 49152 MiB
    vGPU Type ID                          : 0x60a
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-1-2Q
        Class                             : Quadro
        GPU Instance Profile ID           : 19
        Max Instances                     : 48
        Max Instances Per VM              : 1
        Max Instances Per GI              : 1
        FB Memory                         : 2048 MiB'

check "cn13: 48 VFs, driver hosts 32        -> 32" \
    "32" "$(gpu_sriov_vgpu_count_limit "$CN13" 48)"

check "PF exposes fewer VFs than the driver  -> sriov_totalvfs" \
    "16" "$(gpu_sriov_vgpu_count_limit "$CN13" 16)"

NO_MAX=$(echo "$CN13" | grep -v -E '^[[:blank:]]*Max Instances[[:blank:]]*:')
check "no Max Instances printed             -> sriov_totalvfs (as before)" \
    "48" "$(gpu_sriov_vgpu_count_limit "$NO_MAX" 48)"

check "nvidia-smi answered nothing usable   -> sriov_totalvfs" \
    "48" "$(gpu_sriov_vgpu_count_limit "No devices were found" 48)"

check "sriov_totalvfs unreadable            -> null" \
    "null" "$(gpu_sriov_vgpu_count_limit "$CN13" "")"

# "Max Instances Per VM" larger than "Max Instances" must not be read as it
PER_VM='    vGPU Type ID                          : 0x5ef
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-3Q
        Max Instances                     : 32
        Max Instances Per VM              : 40'
check "Max Instances Per VM is not the limit -> 32" \
    "32" "$(gpu_sriov_vgpu_count_limit "$PER_VM" 48)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS case(s) failed"; exit 1; }
echo "all passed"
