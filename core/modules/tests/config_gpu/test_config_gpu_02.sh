#
# TEST - gpu_resource_set settles a card's pre-conditions before it touches the
#        card
#
# Regression cover for the cn13 finding of 2026-09-22. gpu_resource_set_check
# answers "is an instance attached to this pgpu" out of libvirt's live domain
# XML. gpu_unbind_vfio_pci pulls the PF out from under the running guest, at
# which point libvirt drops the <hostdev> and that answer becomes "no". Running
# the release first therefore made the guard pass for precisely the card it
# exists to protect - and left the instance ACTIVE with no GPU in it.
#
# So the property under test is an ordering, not a return value: with the check
# refusing, gpu_unbind_vfio_pci must never have been called.
#
# One ./hex_config invocation only. See the note in test_config_gpu_01.sh: the
# third invocation of a run spins in userspace.
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

fail() { echo "FAIL: $1"; exit 1; }

install -m 755 "$DIR/mock/hex_sdk/gpu_order" /usr/sbin/hex_sdk

ORDER=/tmp/gpu-order.log
: > "$ORDER"

# runtests runs a test under `set -e`, and a refusal is what this case is for,
# so the invocation has to sit on the left of `||` - a bare call followed by
# `rc=$?` never reaches the assertions. test_config_gpu_01.sh gets away with it
# only because its calls are inside a `[ ... ] || fail` condition, where errexit
# is suppressed.
rc=0
./hex_config -vvve gpu_resource_set GPU-order-test sriovVgpu '[{"id":1519,"count":1}]' \
    >/tmp/gpu_order_case.log 2>&1 || rc=$?

[ "$rc" != "0" ] \
    || fail "a card whose pre-condition check refuses was accepted"

grep -q "gpu_resource_set_check" "$ORDER" \
    || fail "the pre-condition check was never run -- $(tr '\n' ' ' < "$ORDER")"

! grep -q "gpu_unbind_vfio_pci" "$ORDER" \
    || fail "the card was released from vfio-pci before the refusal -- $(tr '\n' ' ' < "$ORDER")"

! grep -q "gpu_unset_current_type" "$ORDER" \
    || fail "the card's current carve was torn down before the refusal -- $(tr '\n' ' ' < "$ORDER")"

echo "  ok  refused pgpu request             -> card never left vfio-pci"

rm -f "$ORDER" /tmp/gpu_order_case.log
echo "config_gpu: pre-condition ordering passed"
