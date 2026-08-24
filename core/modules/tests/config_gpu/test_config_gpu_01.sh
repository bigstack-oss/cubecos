#
# TEST - the framebuffer-size rule of gpu_resource_set's validation (#1316)
#
#   1. a request mixing sizes on a card that does not advertise the capability is
#      refused, and the message names both the mix and the capability
#   2. a capability that cannot be read is a refusal too - the rule fails closed
# Both refuse from inside the rule itself, so neither reads sysfs.
#
# Two cases were tried and removed, for two different reasons worth recording:
#
#   - "the rule stays out of the way of a single-size request" cannot live here.
#     A request that passes the rule goes on to the sriov_totalvfs check and then
#     the apply path, both of which need real VFs under /sys/bus/pci/devices.
#     PCI_DEVICES_DIR is a compile-time constant, so a build container cannot
#     supply them.
#   - a third case of any kind cannot live here either. Measured in the jail
#     container: the *third* ./hex_config invocation of a run spins in userspace
#     (STAT=R, no children) regardless of its arguments, while the first two
#     complete normally. A hanging case would wedge `make test`, so the file
#     stops at two. This is likely the same unreliability that put config_etcd in
#     EXCLUDE_DIRS in ../Makefile.
#
# So two things are covered on hardware instead of here: the single-size path,
# and the vgpu_type tag BuildNovaGpuConfContent emits on each alias/device_spec
# entry (its input comes from GetPciVfs reading virtfnN symlinks).
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

fail() { echo "FAIL: $1"; exit 1; }

install -m 755 "$DIR/mock/nvidia-smi/capability_driven" /usr/bin/nvidia-smi
install -m 755 "$DIR/mock/hex_sdk/gpu" /usr/sbin/hex_sdk

GPU=GPU-1316-test
MIXED='[{"id":1519,"count":1},{"id":1523,"count":1}]'    # 3072 + 6144
NO_VRAM='[{"id":1519,"count":1},{"id":1599,"count":1}]'  # 3072 + size not reported

# non-zero exit is expected throughout: every case here is meant to be refused
run() {
    ./hex_config -vvve gpu_resource_set "$GPU" sriovVgpu "$1" >"/tmp/gpu_$2.log" 2>&1
    echo $?
}

# ---- 1. mixed sizes, card says no ----
echo "Not Supported" > /tmp/mock-hetero-capability
[ "$(run "$MIXED" case1)" != "0" ] \
    || fail "case 1: a mixed-size request on an unsupported card was accepted"
grep -q "mixes 2 vGPU framebuffer sizes" /tmp/gpu_case1.log \
    || fail "case 1: refusal did not name the mix -- $(tail -2 /tmp/gpu_case1.log)"
grep -q "Heterogenous Multi-vGPU" /tmp/gpu_case1.log \
    || fail "case 1: refusal did not name the capability it needs"
echo "  ok  mixed sizes + unsupported        -> refused, reason named"

# ---- 2. capability unreadable -> fails closed ----
: > /tmp/mock-hetero-capability
[ "$(run "$MIXED" case2)" != "0" ] \
    || fail "case 2: an unreadable capability must be a refusal, not a pass"
grep -q "mixes 2 vGPU framebuffer sizes" /tmp/gpu_case2.log \
    || fail "case 2: refused, but not by the size rule -- $(tail -2 /tmp/gpu_case2.log)"
echo "  ok  mixed sizes + unreadable         -> refused (fails closed)"

rm -f /tmp/gpu_case1.log /tmp/gpu_case2.log
echo "config_gpu: framebuffer-size rule passed all cases"
