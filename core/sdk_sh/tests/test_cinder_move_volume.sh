#!/bin/bash
#
# cinder_move_volume: the dispatch end of a tier change. It runs the preflight
# itself, passes a refusal through untouched without ever reaching cinder, and
# otherwise invokes `cinder retype --migration-policy on-demand` -- on-demand
# because it is the only policy that copies the data; a migrate would repoint
# the volume at another cluster instead.
#
#   Run: bash test_cinder_move_volume.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_move_volume()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^cinder_move_preflight()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_cinder_preflight_json()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_pf_block()/p' $SRC >> $T/fn.sh
# Extract error constants needed by cinder_move_volume / the preflight
sed -n '/^readonly ERROR_CINDER_MOVE_DISPATCH_FAILED=/p' $SRC >> $T/fn.sh
sed -n '/^readonly ERROR_CINDER_MOVE_BACKEND_UNRESOLVED=/p' $SRC >> $T/fn.sh
source $T/fn.sh

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-50s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-50s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# Stubs for preflight dependencies
_pf_volume()      { cat $T/vol.json; }
_pf_snapshots()   { cat $T/snaps; }
_pf_type_exists() { grep -qx "$1" $T/types; }
_pf_vm_state()    { cat $T/vmstate; }
_pf_qos_differs() { return 1; }
_pf_domain_probe(){ return 1; }
_pf_type_multiattach(){ return 1; }
_pf_type_encrypted()  { return 1; }
# every volume type here is named after its own cinder.conf section
_pf_type_backend_section() { echo "$1"; }
_pf_backend_fsid_pool() {
    case "$1" in
        ceph) echo "c6e64c49:cinder-volumes" ;;
        tier-nvme) echo "deadbeef:cinder-volumes" ;;
        fail-retype) echo "deadbeef:cinder-volumes" ;;
        *) return 1 ;;
    esac
}

# Set up the CINDER command stub
CINDER_CALL_LOG=$T/cinder_call_log
: > $CINDER_CALL_LOG

# Mock cinder command
cinder() {
    echo "cinder $@" >> $CINDER_CALL_LOG
    # Fail if destination is "fail-retype" (the last positional argument)
    if [ "$5" = "fail-retype" ] ; then
        return 1
    fi
    return 0
}
export -f cinder
CINDER=cinder

# Set up type and vm state
echo 'ACTIVE' > $T/vmstate
: > $T/snaps

mkvol() { # status attachments type
  printf '{"status":"%s","attachments":%s,"volume_type":"%s","size":2,"replication_status":"None","group_id":null}\n' \
    "$1" "$2" "$3" > $T/vol.json
}
one='[{"server_id":"vm-1"}]'

# Test 1: preflight refuses -> JSON passed through, retype never called
printf 'ceph\n' > $T/types  # only allows ceph (not nope)
mkvol in-use "$one" ceph
: > $CINDER_CALL_LOG
cinder_move_volume v1 nope >$T/o 2>&1
chk "preflight refuses: rc" "$?" "1"
got_code=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o | head -1)
chk "preflight refuses: the refusal is passed through" "$got_code" "E_NO_SUCH_TYPE"
chk "preflight refuses: retype NOT invoked" "$(grep -c 'retype' $CINDER_CALL_LOG)" "0"

# Test 2: preflight passes -> retype IS invoked with correct args AND success JSON contains code:OK
printf 'ceph\ntier-nvme\n' > $T/types
mkvol available "[]" ceph
: > $CINDER_CALL_LOG
cinder_move_volume v1 tier-nvme >$T/o 2>&1
chk "preflight passes: rc" "$?" "0"
chk "preflight passes: code" "$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o | head -1)" "OK"
chk "preflight passes: ok"   "$(sed -n 's/.*"ok":\([^,}]*\).*/\1/p' $T/o | head -1)" "true"
chk "preflight passes: dispatched" "$(sed -n 's/.*"dispatched":\([^,}]*\).*/\1/p' $T/o | head -1)" "true"
chk "preflight passes: retype on-demand invoked" \
    "$(grep -c '^cinder retype --migration-policy on-demand v1 tier-nvme$' $CINDER_CALL_LOG)" "1"
# never a migrate: it can repoint a volume at another ceph cluster without
# copying the data
chk "preflight passes: no migrate invoked" "$(grep -c 'migrate' $CINDER_CALL_LOG)" "0"

# Test 3: retype fails -> E_DISPATCH_FAILED
printf 'ceph\nfail-retype\n' > $T/types
mkvol available "[]" ceph
: > $CINDER_CALL_LOG
cinder_move_volume v1 fail-retype >$T/o 2>&1
chk "retype fails: rc" "$?" "1"
chk "retype fails: code" "$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o | head -1)" "E_DISPATCH_FAILED"
chk "retype fails: ok"   "$(sed -n 's/.*"ok":\([^,}]*\).*/\1/p' $T/o | head -1)" "false"
# the reason is the module's own constant, which the API pins byte for byte
chk "retype fails: reason" "$(sed -n 's/.*"reason":"\([^"]*\)".*/\1/p' $T/o | head -1)" \
    "$ERROR_CINDER_MOVE_DISPATCH_FAILED"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: cinder_move_volume"
exit 0
