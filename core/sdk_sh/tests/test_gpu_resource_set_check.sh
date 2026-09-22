#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh:
#   gpu_pci_addr_hostdev_pattern -- builds libvirt's own spelling of a host PCI
#                                   address, all four fields
#   gpu_pgpu_holding_domain      -- which active domain holds a pgpu card
#   gpu_resource_set_check       -- the guard in front of gpu_resource_set; it
#                                   must refuse on every answer it cannot read,
#                                   not only on the ones it recognises
#
# Regression cover for the cn13 finding of 2026-09-22: a pgpu card attached to a
# running instance was re-carved to sriovVgpu. Two separate faults made that
# possible and both are pinned here.
#
# Self-contained: extracts the functions under test, stubs virsh and
# gpu_device_list, and needs no GPU, no libvirt and no Openstack.
#   Run: bash test_gpu_resource_set_check.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"
for fn in gpu_pci_addr_hostdev_pattern gpu_pgpu_holding_domain gpu_resource_set_check ; do
    eval "$(awk -v f="^$fn\\\\(\\\\)" '$0 ~ f{p=1} p{print} p&&/^}/{exit}' "$GPU_SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1. gpu_pci_addr_hostdev_pattern
# ---------------------------------------------------------------------------
HOST='<address domain=\x270x0000\x27 bus=\x270x8c\x27 slot=\x270x00\x27 function=\x270x0\x27'
ck "$(gpu_pci_addr_hostdev_pattern 00000000:8C:00.0)" \
   "$(printf "$HOST")" "8-digit domain, upper case bus"
ck "$(gpu_pci_addr_hostdev_pattern 0000:8c:00.0)" \
   "$(printf "$HOST")" "4-digit domain spells the same pattern"
ck "$(gpu_pci_addr_hostdev_pattern 00000001:04:00.0)" \
   "$(printf '<address domain=\x270x0001\x27 bus=\x270x04\x27 slot=\x270x00\x27 function=\x270x0\x27')" \
   "PCI domain 1 is carried into the pattern"

gpu_pci_addr_hostdev_pattern "" >/dev/null 2>&1; ck "$?" "1" "empty address -> cannot answer"
gpu_pci_addr_hostdev_pattern "No devices were found" >/dev/null 2>&1; ck "$?" "1" "nvidia-smi error sentence -> cannot answer"
gpu_pci_addr_hostdev_pattern "0000:04:00" >/dev/null 2>&1; ck "$?" "1" "address with no function -> cannot answer"

# ---------------------------------------------------------------------------
# 2. gpu_pgpu_holding_domain
# ---------------------------------------------------------------------------
# Real libvirt output. The hostdev <source> address carries no type=, every
# guest-side address does -- that is what tells the two apart.
cat > "$TMP/holder.xml" <<'X'
<domain type='kvm'>
  <devices>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x8c' slot='0x00' function='0x0'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </hostdev>
  </devices>
</domain>
X
# Same bus and slot, different PCI domain: a *different* card.
sed "s/domain='0x0000' bus='0x8c'/domain='0x0001' bus='0x04'/" "$TMP/holder.xml" > "$TMP/otherdomain.xml"
# No GPU at all, but its own root port sits at bus 0x04 slot 0x00.
cat > "$TMP/plain.xml" <<'X'
<domain type='kvm'>
  <devices>
    <interface type='bridge'>
      <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
    </interface>
  </devices>
</domain>
X

VIRSH_LIST="" VIRSH_LIST_RC=0
virsh() {
    case "$1" in
        list)    [ "$VIRSH_LIST_RC" = 0 ] || return "$VIRSH_LIST_RC"; printf '%s\n' $VIRSH_LIST ;;
        dumpxml) cat "$TMP/$2.xml" 2>/dev/null ;;
    esac
}

VIRSH_LIST="holder"
ck "$(gpu_pgpu_holding_domain 00000000:8C:00.0)" "holder" "the domain that holds the card is named"

VIRSH_LIST="otherdomain"
ck "$(gpu_pgpu_holding_domain 00000000:8C:00.0)" "" "a card in another PCI domain is not this card"
ck "$(gpu_pgpu_holding_domain 00000001:04:00.0)" "otherdomain" "...and that other card is still found by its own address"

VIRSH_LIST="plain"
ck "$(gpu_pgpu_holding_domain 00000001:04:00.0)" "" "a guest's own root port at 04:00.0 is not a hostdev"

# virsh lists every *active* domain, whatever its state: a paused guest still
# holds its vfio device. The stub answers `list` with no state filter at all,
# so this case only stands up if the caller asked without one.
VIRSH_LIST="plain holder"
ck "$(gpu_pgpu_holding_domain 00000000:8C:00.0)" "holder" "holder found behind a non-holder in the list"

VIRSH_LIST_RC=1
gpu_pgpu_holding_domain 00000000:8C:00.0 >/dev/null 2>&1
ck "$?" "1" "virsh failing is 'cannot tell', not 'nothing holds it'"
VIRSH_LIST_RC=0

gpu_pgpu_holding_domain "" >/dev/null 2>&1
ck "$?" "1" "unusable address is 'cannot tell'"

# A node with no libvirt at all cannot be running a guest, so that is an answer
# rather than a failure to get one. Only a virsh that exists and then fails is
# "cannot tell".
mkdir -p "$TMP/bin"
for t in awk tr grep ; do ln -sf "$(command -v $t)" "$TMP/bin/$t" ; done
( unset -f virsh
  PATH="$TMP/bin"
  command -v virsh >/dev/null 2>&1 && exit 99   # the sandbox itself has to be virsh-free
  gpu_pgpu_holding_domain 00000000:8C:00.0 >/dev/null 2>&1 )
ck "$?" "0" "no virsh on the node is 'nothing holds it', not 'cannot tell'"

# ---------------------------------------------------------------------------
# 3. gpu_resource_set_check
# ---------------------------------------------------------------------------
HOLDER="" HOLDER_RC=0
gpu_pgpu_holding_domain() { [ "$HOLDER_RC" = 0 ] || return "$HOLDER_RC"; printf '%s' "$HOLDER"; }

run() { gpu_resource_set_check "GPU-a" sriovVgpu '[{"id":1,"count":1}]' >/dev/null 2>&1; echo $?; }
list() { eval "gpu_device_list() { $1 }"; }

list 'echo "[{\"id\":\"GPU-a\",\"type\":\"sriovVgpu\",\"pciAddress\":\"00000000:8C:00.0\",\"status\":\"idle\"}]";'
ck "$(run)" "0" "idle card is accepted"

list 'echo "[{\"id\":\"GPU-a\",\"type\":\"sriovVgpu\",\"pciAddress\":\"00000000:8C:00.0\",\"status\":\"inUse\"}]";'
ck "$(run)" "1" "inUse card is refused"

list 'echo "[]";'
ck "$(run)" "1" "card absent from the list is refused"

list 'echo "malformed" >&2; return 1;'
ck "$(run)" "1" "gpu_device_list exiting non-zero is refused"

list ':;'
ck "$(run)" "1" "gpu_device_list printing nothing is refused"

list 'echo "[{\"id\":\"GPU-a\",\"type\":\"sriovVgpu\",\"pciAddress\":\"00000000:8C:00.0\"}]";'
ck "$(run)" "1" "a card with no status field is refused"

list 'echo "[{\"id\":\"GPU-a\",\"type\":\"sriovVgpu\",\"pciAddress\":\"00000000:8C:00.0\",\"status\":\"busyish\"}]";'
ck "$(run)" "1" "a status nobody defined is refused"

# The pgpu re-ask: the listing says idle because libvirt could not be reached,
# the guard asks again and is allowed to call that a refusal.
list 'echo "[{\"id\":\"GPU-a\",\"type\":\"pgpu\",\"pciAddress\":\"00000000:8C:00.0\",\"status\":\"idle\"}]";'
HOLDER="" HOLDER_RC=0
ck "$(run)" "0" "pgpu with no holder is accepted"
HOLDER="instance-1" HOLDER_RC=0
ck "$(run)" "1" "pgpu whose card a domain holds is refused even when the listing said idle"
HOLDER="" HOLDER_RC=1
ck "$(run)" "1" "pgpu whose holder cannot be determined is refused"

# ---------------------------------------------------------------------------
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
