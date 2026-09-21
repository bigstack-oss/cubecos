#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh:
#   gpu_resource_summary -- the `hex_cli gpu resource_list` / `gpu status`
#                           listing must carry each pgpu card's Cyborg device
#                           profile, so the string a flavor needs is reachable
#                           from the CLI and not only from `openstack
#                           accelerator device profile list`.
#
# Self-contained: extracts the function under test and stubs its two callees,
# so it needs no GPU, no config.json and no Openstack.
#   Run: bash test_gpu_resource_summary_device_profile.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"
eval "$(awk '/^gpu_resource_summary\(\)/{f=1} f{print} f&&/^}/{exit}' "$GPU_SRC")"
[ "$(type -t gpu_resource_summary)" = function ] || { echo "FAIL: not extracted"; exit 1; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# gpu_device_list stub: three cards, one of each shape the field has to cover.
DEVICES='[
 {"id":"GPU-a","name":"NVIDIA RTX A2000","type":"pgpu","pciAddress":"00000000:86:00.0",
  "status":"idle","allocation":{"current":0,"total":1}},
 {"id":"GPU-b","name":"NVIDIA RTX A2000","type":"sriovVgpu","pciAddress":"00000000:42:00.0",
  "status":"inUse","allocation":{"current":2,"total":4}},
 {"id":"GPU-c","name":"NVIDIA RTX A2000","type":"unset","pciAddress":"00000000:43:00.0",
  "status":"unassigned","allocation":null}
]'
DEV_RC=0
gpu_device_list() { [ "$DEV_RC" = 0 ] || return "$DEV_RC"; printf '%s' "$DEVICES"; }

MAP='{}' MAP_RC=0
gpu_device_profile_map() { [ "$MAP_RC" = 0 ] || return "$MAP_RC"; printf '%s' "$MAP"; }

# The field of one card's line, by card id's position in DEVICES (1-based).
dp() { gpu_resource_summary | sed -n "${1}p" | sed 's/.*device profile: \([^,]*\),.*/\1/'; }

# --- 1. a pgpu card whose profile exists shows it -----------------------------
MAP='{"GPU-a":"rtx_a2000_1"}'
ck "$(dp 1)" "rtx_a2000_1" "pgpu with a profile"

# --- 2. types that need no profile are "-", not "none" ------------------------
ck "$(dp 2)" "-" "sriovVgpu needs no device profile"
ck "$(dp 3)" "-" "an uncarved card needs no device profile"

# --- 3. a pgpu card with no profile yet is "none" -----------------------------
MAP='{"GPU-a":null}'
ck "$(dp 1)" "none" "pgpu whose profile was never created"
MAP='{}'
ck "$(dp 1)" "none" "pgpu absent from the map entirely"

# --- 4. an unreachable Cyborg is "?", and must not blank the rest of the line -
# The resource types come from config.json alone; losing Openstack must not
# cost the operator the listing they already had before this field existed.
MAP_RC=1
ck "$(dp 1)" "?" "openstack unreachable -> ? for pgpu"
ck "$(dp 2)" "-" "openstack unreachable -> still - for sriovVgpu"
ck "$(gpu_resource_summary | sed -n 1p | sed 's/.*type: \([^,]*\),.*/\1/')" "pgpu" \
   "openstack unreachable -> type still reported"
ck "$(gpu_resource_summary | wc -l | tr -d ' ')" "3" "openstack unreachable -> all cards still listed"
MAP_RC=0

# --- 5. the pre-existing early returns still win ------------------------------
DEV_RC=1
ck "$(gpu_resource_summary)" "GPU resource configuration unavailable" "gpu_device_list failure"
DEV_RC=0
DEVICES='[]'
ck "$(gpu_resource_summary)" "No GPU cards reported" "no cards"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
