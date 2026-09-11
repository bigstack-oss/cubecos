#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh:
#   gpu_device_profile_map -- reports the Cyborg device profile of every pgpu
#                             card on the node (#818), and must not turn an
#                             unreachable Cyborg into "no profiles".
#
# Self-contained: extracts the two functions under test plus the real name
# derivation from sdk_os.sh (so a drift between the two modules fails here),
# stubs the one Openstack call, and needs no GPU and no Openstack.
#   Run: bash test_gpu_device_profile_map.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"
OS_SRC="$DIR/../modules/sdk_os.sh"
eval "$(awk '/^gpu_device_profile_map\(\)/{f=1} f{print} f&&/^}/{exit}' "$GPU_SRC")"
eval "$(awk '/^gpu_device_profile_get\(\)/{f=1} f{print} f&&/^}/{exit}' "$GPU_SRC")"
eval "$(awk '/^os_device_profile_name_for\(\)/{f=1} f{print} f&&/^}/{exit}' "$OS_SRC")"
for fn in gpu_device_profile_map gpu_device_profile_get os_device_profile_name_for ; do
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GPU_CONFIG_FILE_PATH="$TMP/config.json"

LOGFILE="$TMP/log"; : > "$LOGFILE"
log_error() { printf '%s\n' "$1" >> "$LOGFILE"; }

# os_device_profile_names stub. CALLS counts round trips, so a test can assert
# that a node with no pgpu card makes none.
CALLS="$TMP/calls"; : > "$CALLS"
MOCK_NAMES="" MOCK_RC=0
os_device_profile_names() {
    echo x >> "$CALLS"
    [ "$MOCK_RC" = 0 ] || return "$MOCK_RC"
    printf '%s' "$MOCK_NAMES"
}
calls() { wc -l < "$CALLS" | tr -d ' '; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

A2000='{"id":"GPU-a","name":"NVIDIA RTX A2000","type":"pgpu","pciAddress":"00000000:86:00.0"}'
BLACK='{"id":"GPU-b","name":"NVIDIA RTX PRO 6000 Blackwell Server Edition","type":"pgpu","pciAddress":"00000001:04:00.0"}'
VGPU='{"id":"GPU-c","name":"NVIDIA RTX A2000","type":"sriovVgpu","pciAddress":"00000000:42:00.0"}'

# --- 1. no pgpu card: empty object, and NO Openstack round trip ---------------
: > "$CALLS"; echo "[$VGPU]" > "$GPU_CONFIG_FILE_PATH"
ck "$(gpu_device_profile_map)" "{}" "no pgpu card -> {}"
ck "$(calls)" "0" "no pgpu card -> no Openstack call"

# --- 2. profile exists -> reported --------------------------------------------
: > "$CALLS"; echo "[$A2000]" > "$GPU_CONFIG_FILE_PATH"
MOCK_NAMES="rtx_a2000_1
tesla_t4_1"
ck "$(gpu_device_profile_map | jq -r '."GPU-a"')" "rtx_a2000_1" "existing profile is reported"
ck "$(calls)" "1" "one card -> one Openstack call"

# --- 3. profile not created yet -> null, not the name it would get ------------
MOCK_NAMES="tesla_t4_1"
ck "$(gpu_device_profile_map | jq -r '."GPU-a"')" "null" "missing profile -> null"

# --- 4. several pgpu cards still cost exactly one round trip ------------------
: > "$CALLS"; echo "[$A2000,$BLACK,$VGPU]" > "$GPU_CONFIG_FILE_PATH"
MOCK_NAMES="rtx_a2000_1
rtx_pro_6000_blackwell_server_edition_1"
out=$(gpu_device_profile_map)
ck "$(echo "$out" | jq -r '."GPU-a"')" "rtx_a2000_1" "card 1 of 2"
ck "$(echo "$out" | jq -r '."GPU-b"')" "rtx_pro_6000_blackwell_server_edition_1" "card 2 of 2"
ck "$(echo "$out" | jq 'has("GPU-c")')" "false" "sriovVgpu card is not listed"
ck "$(calls)" "1" "two pgpu cards -> still one Openstack call"

# --- 5. Cyborg unreachable must fail, not report "no profiles" ----------------
MOCK_RC=1
gpu_device_profile_map >/dev/null 2>&1
ck "$?" "1" "openstack failure -> non-zero"
MOCK_RC=0

# --- 6. missing/garbage config.json -------------------------------------------
rm -f "$GPU_CONFIG_FILE_PATH"
gpu_device_profile_map >/dev/null 2>&1
ck "$?" "1" "missing config.json -> non-zero"
echo 'not json' > "$GPU_CONFIG_FILE_PATH"
gpu_device_profile_map >/dev/null 2>&1
ck "$?" "1" "unparseable config.json -> non-zero"

# --- 7. single-card accessor ---------------------------------------------------
echo "[$A2000,$BLACK]" > "$GPU_CONFIG_FILE_PATH"
MOCK_NAMES="rtx_a2000_1"
ck "$(gpu_device_profile_get GPU-a)" "rtx_a2000_1" "get: existing"
ck "$(gpu_device_profile_get GPU-b)" "" "get: profile missing -> empty"
ck "$(gpu_device_profile_get GPU-nope)" "" "get: unknown card -> empty"
gpu_device_profile_get "" >/dev/null 2>&1
ck "$?" "1" "get: empty id -> non-zero"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
