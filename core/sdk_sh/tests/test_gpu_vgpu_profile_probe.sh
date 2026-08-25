#!/bin/bash
#
# Unit test for the nvidia-smi probe handling in ../modules/sdk_gpu.sh:
#   gpu_vgpu_profile_list -- must not report empty profile lists with exit 0
#                            when its `nvidia-smi vgpu -s -v` probe failed
#                            (#1247), while still honouring the vfio-pci
#                            fallback to the static vGPU type table (#1282).
#
# Self-contained: extracts just that function, stubs nvidia-smi, log_error and
# the XML table reader, so it needs no GPU and no NVIDIA driver.
#   Run: bash test_gpu_vgpu_profile_probe.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_gpu.sh"
eval "$(awk '/^gpu_vgpu_profile_list\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
eval "$(awk '/^gpu_probe_diagnosis\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t gpu_vgpu_profile_list)" = function ] || { echo "FAIL: function not extracted"; exit 1; }
[ "$(type -t gpu_probe_diagnosis)" = function ] || { echo "FAIL: gpu_probe_diagnosis not extracted"; exit 1; }

# constants the extracted function reads, copied from the top of sdk_gpu.sh
SRIOV_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+[A-Za-z]+$"
MIG_PROFILE_NAME_REGEX="^[A-Za-z0-9]+-[0-9]+-[0-9]+[A-Za-z]+$"
VGPU_CONFIG_XML="/nonexistent/vgpuConfig.xml"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GPU_CONFIG_FILE_PATH="$TMP/config.json"
cat > "$GPU_CONFIG_FILE_PATH" <<'EOF'
[{"id":"GPU-aaaa","name":"NVIDIA RTX PRO 6000","pciAddress":"00000000:42:00.0","type":"sriovVgpu",
  "profiles":[{"id":1561,"count":2,"alias":"vgpu-DC-12Q"}]}]
EOF

# nvidia-smi stub: prints $MOCK_OUT on stdout, $MOCK_ERR on stderr, exits $MOCK_RC
NVIDIA_SMI="$TMP/nvidia-smi"
cat > "$NVIDIA_SMI" <<'EOF'
#!/bin/bash
[ -n "${MOCK_ERR:-}" ] && printf '%s\n' "$MOCK_ERR" >&2
printf '%s' "${MOCK_OUT:-}"
exit "${MOCK_RC:-0}"
EOF
chmod +x "$NVIDIA_SMI"
export MOCK_OUT="" MOCK_ERR="" MOCK_RC=0

# log_error stub: records what the function would have sent to the journal.
# Through a file, not a variable - the function under test runs in a command
# substitution, so a variable it sets would not survive back to the caller.
LOGFILE="$TMP/log"
DEBUGFILE="$TMP/debug"
: > "$LOGFILE"; : > "$DEBUGFILE"
log_error() { printf '%s\n' "$1" >> "$LOGFILE"; }
log_debug() { printf '%s\n' "$1" >> "$DEBUGFILE"; }

# gpu_vgpu_types_from_xml stub: emits "$MOCK_XML" (id<TAB>name<TAB>vramMiB rows)
MOCK_XML=""
gpu_vgpu_types_from_xml() { printf '%s' "$MOCK_XML"; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

run() { # sets OUT / RC / LOGGED / DEBUGGED for the current MOCK_* state
    : > "$LOGFILE"; : > "$DEBUGFILE"
    OUT=$(gpu_vgpu_profile_list "${1-}" 2>/dev/null); RC=$?
    LOGGED=$(cat "$LOGFILE"); DEBUGGED=$(cat "$DEBUGFILE")
}

SMI_OK='    vGPU Type ID                      : 0x619
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-12Q
        FB Memory                         : 12288 MiB
    vGPU Type ID                      : 0x61a
        Name                              : NVIDIA RTX Pro 6000 Blackwell DC-1-24Q
        FB Memory                         : 24576 MiB
        Max Instances                     : 4'

# ---- 1. healthy probe: exit 0, both lists built, config count/alias merged ----
MOCK_RC=0 MOCK_OUT="$SMI_OK" MOCK_ERR="" MOCK_XML=""
run GPU-aaaa
ck "$RC" 0 "healthy probe exits 0"
ck "$(echo "$OUT" | jq -r '.sriov[0].name')" "DC-12Q"  "healthy probe: sriov type parsed"
ck "$(echo "$OUT" | jq -r '.migBacked[0].name')" "DC-1-24Q" "healthy probe: mig type parsed"
ck "$(echo "$OUT" | jq -r '.sriov[0].count')" "2"      "healthy probe: count merged from config (0x619 = 1561)"
ck "$LOGGED" "" "healthy probe logs no error"

# ---- 2. failed probe with nothing else to answer: exit non-zero + logged ----
# Shaped like the real thing: nvidia-smi puts "No devices were found" on
# stdout and leaves stderr empty (cn13: nonexistent GPU -> exit 6, no stderr),
# so a message built from stderr alone would say nothing.
MOCK_RC=6 MOCK_OUT="No devices were found" MOCK_ERR="" MOCK_XML=""
run GPU-does-not-exist
ck "$([ "$RC" -ne 0 ] && echo nonzero || echo zero)" nonzero "failed probe exits non-zero"
ck "$(echo "$LOGGED" | grep -c 'exited 6')" "1" "failed probe logs the exit status"
ck "$(echo "$LOGGED" | grep -c 'No devices were found')" "1" "failed probe logs the diagnosis, taken from stdout"
ck "$(echo "$LOGGED" | grep -c 'refusing to report empty profile lists')" "1" "failed probe says why it refused"

# stderr wins when nvidia-smi does use it
MOCK_RC=6 MOCK_OUT="" MOCK_ERR="Unable to find device" MOCK_XML=""
run GPU-does-not-exist
ck "$(echo "$LOGGED" | grep -c 'Unable to find device')" "1" "failed probe prefers stderr when present"

# ---- 3. failed probe but the static table answers (pgpu on vfio-pci) ----
# Same exit 6 as case 2 - the fallback, not the exit status, decides.
MOCK_RC=6 MOCK_OUT="No devices were found" MOCK_ERR="Unable to find device" \
    MOCK_XML=$'1561\tDC-12Q\t12288\n1585\tDC-1-24Q\t24576'
run GPU-aaaa
ck "$RC" 0 "vfio-pci fallback still exits 0"
ck "$(echo "$OUT" | jq -r '.sriov[0].name')" "DC-12Q" "vfio-pci fallback: sriov from XML table"
ck "$(echo "$OUT" | jq -r '.migBacked[0].name')" "DC-1-24Q" "vfio-pci fallback: mig from XML table"
ck "$(echo "$OUT" | jq -r '.sriov[0].count')" "2" "vfio-pci fallback: count merged from config"
ck "$(echo "$OUT" | jq -r '.sriov[0].alias')" "vgpu-DC-12Q" "vfio-pci fallback: alias merged from config"
ck "$LOGGED" "" "vfio-pci fallback logs no error - a healthy pgpu is polled constantly"
ck "$(echo "$DEBUGGED" | grep -c 'exited 6')" "1" "vfio-pci fallback still records the failed probe at debug level"

# ---- 4. healthy probe on a card that genuinely has no vGPU types ----
# Empty lists with exit 0 must stay reachable, otherwise the caller can no
# longer trust exit 0 to mean anything.
MOCK_RC=0 MOCK_OUT="" MOCK_ERR="" MOCK_XML=""
run GPU-aaaa
ck "$RC" 0 "no vGPU types: exits 0"
ck "$(echo "$OUT" | jq -c '[.sriov, .migBacked]')" "[[],[]]" "no vGPU types: empty lists"

# ---- 5. missing argument ----
MOCK_RC=0 MOCK_OUT="$SMI_OK" MOCK_ERR="" MOCK_XML=""
run ""
ck "$RC" 1 "missing gpuId exits 1"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: gpu_vgpu_profile_list probe handling"; exit 0; } || exit 1
