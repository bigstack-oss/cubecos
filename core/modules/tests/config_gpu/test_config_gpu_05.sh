#
# TEST - the MIG-backed capacity rule budgets in nominal sizes (#1794)
#
#   1. a request above the card's nominal MIG-backed capacity is still refused,
#      and the message names that capacity: DC-4-96Q x1 + DC-1-24C x1 is
#      122880 MiB against 98304, each type within its own vmCountLimit
#   2. the card's own full-size profile at count 1 - DC-4-96Q, 98304 MiB - is
#      not refused by this rule. It was, against nvidia-smi's memory.total of
#      97887, although the driver lists the type as fitting once.
#
# Case 2 cannot run to success here (the apply path needs real hardware), so it
# asserts the next rule refuses it instead: the GPU-instance rule, which fails
# closed on the silent nvidia-smi mock. That shows the request got past the
# capacity rule, and that the rule no longer asks nvidia-smi for memory.total.
#
# Two ./hex_config invocations only - see test_config_gpu_01.sh.
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

fail() { echo "FAIL: $1"; exit 1; }

install -m 755 "$DIR/mock/nvidia-smi/silent" /usr/bin/nvidia-smi
install -m 755 "$DIR/mock/hex_sdk/gpu_mig" /usr/sbin/hex_sdk

GPU=GPU-1794-test

# runtests runs a test under `set -e`, so each refusal sits on the left of `||`.

# ---- 1. above the nominal capacity -> refused, capacity named ----
rc=0
./hex_config -vvve gpu_resource_set "$GPU" migBackedVgpu '[{"id":1585,"count":1},{"id":1563,"count":1}]' \
    >/tmp/gpu_mig_case1.log 2>&1 || rc=$?
[ "$rc" != "0" ] \
    || fail "case 1: a request above the nominal capacity was accepted"
grep -q "requested 122880 MiB of MIG-backed vGPU memory exceeds the 98304 MiB of MIG-backed vGPU capacity" /tmp/gpu_mig_case1.log \
    || fail "case 1: refusal did not name the nominal capacity -- $(tail -2 /tmp/gpu_mig_case1.log)"
echo "  ok  122880 MiB against 98304         -> refused, capacity named"

# ---- 2. the full-size profile at count 1 -> past the capacity rule ----
rc=0
./hex_config -vvve gpu_resource_set "$GPU" migBackedVgpu '[{"id":1585,"count":1}]' \
    >/tmp/gpu_mig_case2.log 2>&1 || rc=$?
! grep -q "MiB of MIG-backed vGPU memory exceeds" /tmp/gpu_mig_case2.log \
    || fail "case 2: DC-4-96Q x1 was refused by the capacity rule -- $(tail -2 /tmp/gpu_mig_case2.log)"
! grep -q "could not read the MIG-backed vGPU capacity" /tmp/gpu_mig_case2.log \
    || fail "case 2: the capacity rule could not read the profile list -- $(tail -2 /tmp/gpu_mig_case2.log)"
grep -q "could not read the MIG-backed vGPU types of GPU $GPU" /tmp/gpu_mig_case2.log \
    || fail "case 2: expected the GPU-instance rule to be the one refusing -- $(tail -2 /tmp/gpu_mig_case2.log)"
echo "  ok  DC-4-96Q x1 (98304 MiB)          -> passes the capacity rule"

rm -f /tmp/gpu_mig_case1.log /tmp/gpu_mig_case2.log
echo "config_gpu: MIG-backed nominal capacity rule passed"
