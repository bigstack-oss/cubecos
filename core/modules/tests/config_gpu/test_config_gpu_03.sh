#
# TEST - gpu_resource_set refuses a type the card does not support, by name,
#        before it touches the card (#1538)
#
#   1. a pgpu card that supports pgpu and sriovVgpu, asked for migBackedVgpu:
#      refused with "does not support 'migBackedVgpu'", and the card is never
#      released from vfio-pci to find that out
#   2. a card that reports no supportTypes at all is a refusal too - the rule
#      fails closed
#
# Without this rule both requests are refused only by ValidateVgpuProfiles, as
# "profile id N is not a valid ... profile", and a pgpu is first unbound from
# vfio-pci and then bound again. So the properties under test are the message
# and that gpu_unbind_vfio_pci is never called.
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

fail() { echo "FAIL: $1"; exit 1; }

install -m 755 "$DIR/mock/hex_sdk/gpu_capability" /usr/sbin/hex_sdk

CALLS=/tmp/gpu-capability.log

# runtests runs a test under `set -e`, so each refusal sits on the left of `||`.

# ---- 1. unsupported type -> refused by name, card untouched ----
echo ',"supportTypes":["pgpu","sriovVgpu"]' > /tmp/mock-support-types
: > "$CALLS"
rc=0
./hex_config -vvve gpu_resource_set GPU-cap-test migBackedVgpu '[{"id":1,"count":1}]' \
    >/tmp/gpu_cap_case1.log 2>&1 || rc=$?

[ "$rc" != "0" ] \
    || fail "case 1: a type the card does not support was accepted"
grep -q "does not support 'migBackedVgpu' resource type (supported: pgpu, sriovVgpu)" /tmp/gpu_cap_case1.log \
    || fail "case 1: refusal did not name the type and what the card supports -- $(tail -2 /tmp/gpu_cap_case1.log)"
grep -q "gpu_resource_set_check" "$CALLS" \
    || fail "case 1: the pre-condition check was never run -- $(tr '\n' ' ' < "$CALLS")"
! grep -q "gpu_unbind_vfio_pci" "$CALLS" \
    || fail "case 1: the card was released from vfio-pci before the refusal -- $(tr '\n' ' ' < "$CALLS")"
echo "  ok  unsupported type                 -> refused by name, card never left vfio-pci"

# ---- 2. no supportTypes -> fails closed ----
: > /tmp/mock-support-types
: > "$CALLS"
rc=0
./hex_config -vvve gpu_resource_set GPU-cap-test sriovVgpu '[{"id":1,"count":1}]' \
    >/tmp/gpu_cap_case2.log 2>&1 || rc=$?

[ "$rc" != "0" ] \
    || fail "case 2: a card with no supportTypes must be a refusal, not a pass"
grep -q "does not support 'sriovVgpu' resource type (supported: unknown)" /tmp/gpu_cap_case2.log \
    || fail "case 2: refused, but not by the supportTypes rule -- $(tail -2 /tmp/gpu_cap_case2.log)"
! grep -q "gpu_unbind_vfio_pci" "$CALLS" \
    || fail "case 2: the card was released from vfio-pci before the refusal -- $(tr '\n' ' ' < "$CALLS")"
echo "  ok  no supportTypes                  -> refused, card never left vfio-pci"

rm -f "$CALLS" /tmp/mock-support-types /tmp/gpu_cap_case1.log /tmp/gpu_cap_case2.log
echo "config_gpu: supportTypes gate passed"
