#
# TEST - the SR-IOV driver-ceiling rule of gpu_resource_set's validation (#1583)
#
#   1. a request above the card's vGPU ceiling - the largest Max Instances among
#      its SR-IOV types, not the PF's sriov_totalvfs - is refused, and the
#      message names the ceiling
#   2. a ceiling that cannot be read is a refusal too - the rule fails closed
# Both refuse from inside the rule itself, ahead of the sriov_totalvfs rule, so
# neither reads sysfs.
#
# A request at or under the ceiling cannot be covered here: it goes on to the
# sriov_totalvfs check and the apply path, which need real VFs under
# /sys/bus/pci/devices (see test_config_gpu_01.sh). It is covered on hardware.
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

fail() { echo "FAIL: $1"; exit 1; }

install -m 755 "$DIR/mock/nvidia-smi/max_instances" /usr/bin/nvidia-smi
install -m 755 "$DIR/mock/hex_sdk/gpu" /usr/sbin/hex_sdk

GPU=GPU-1316-test
OVER='[{"id":1519,"count":33}]'    # single size, so the heterogeneity rule stays out of the way

# non-zero exit is expected throughout: every case here is meant to be refused
run() {
    ./hex_config -vvve gpu_resource_set "$GPU" sriovVgpu "$1" >"/tmp/gpu_max_$2.log" 2>&1
    echo $?
}

# ---- 1. above the ceiling ----
echo 32 > /tmp/mock-max-instances
[ "$(run "$OVER" case1)" != "0" ] \
    || fail "case 1: a request above the driver's vGPU ceiling was accepted"
grep -q "requested 33 vGPU(s) exceeds the 32 vGPU(s) the driver can host" /tmp/gpu_max_case1.log \
    || fail "case 1: refusal did not name the ceiling of 32 -- $(tail -2 /tmp/gpu_max_case1.log)"
echo "  ok  33 vGPUs, ceiling 32              -> refused, ceiling named"

# ---- 2. ceiling unreadable -> fails closed ----
: > /tmp/mock-max-instances
[ "$(run "$OVER" case2)" != "0" ] \
    || fail "case 2: an unreadable ceiling must be a refusal, not a pass"
grep -q "could not read how many vGPUs GPU $GPU can host" /tmp/gpu_max_case2.log \
    || fail "case 2: refused, but not by the ceiling rule -- $(tail -2 /tmp/gpu_max_case2.log)"
echo "  ok  ceiling unreadable                -> refused (fails closed)"
