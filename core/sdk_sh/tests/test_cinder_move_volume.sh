#!/bin/bash
T=$(mktemp -d)
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_move_volume()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^cinder_move_preflight()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_cinder_preflight_json()/,/^}/p' $SRC >> $T/fn.sh
sed -n '/^_pf_block()/p' $SRC >> $T/fn.sh
source $T/fn.sh

chk(){ printf '%-50s -> %-20s (want %s)\n' "$1" "$2" "$3"; }

# Stubs for preflight dependencies
_pf_volume()      { cat $T/vol.json; }
_pf_snapshots()   { cat $T/snaps; }
_pf_type_exists() { grep -qx "$1" $T/types; }
_pf_vm_state()    { cat $T/vmstate; }
_pf_qos_differs() { return 1; }
_pf_domain_probe(){ return 1; }
_pf_type_multiattach(){ return 1; }
_pf_type_encrypted()  { return 1; }
_pf_backend_fsid_pool() {
    case "$1" in
        ceph) echo "c6e64c49:cinder-volumes" ;;
        tier-nvme) echo "deadbeef:cinder-volumes" ;;
        fail-retype) echo "deadbeef:cinder-volumes" ;;
        *) echo "unknown:pool" ;;
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
ret=$?
got_code=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o | head -1)
if grep -q "cinder retype" $CINDER_CALL_LOG ; then
    chk "preflight refuses: retype NOT invoked"     "FAIL(retype WAS called)" "retype never called"
else
    chk "preflight refuses: retype NOT invoked"     "PASS (code=$got_code)" "retype never called"
fi

# Test 2: preflight passes -> retype IS invoked with correct args
printf 'ceph\ntier-nvme\n' > $T/types
mkvol available "[]" ceph
: > $CINDER_CALL_LOG
cinder_move_volume v1 tier-nvme >$T/o 2>&1
ret=$?
if grep -q "cinder retype --migration-policy on-demand v1 tier-nvme" $CINDER_CALL_LOG ; then
    chk "preflight passes: retype invoked"          "PASS (ret=$ret)" "0"
else
    got=$(cat $CINDER_CALL_LOG)
    if [ -z "$got" ] ; then
        chk "preflight passes: retype invoked"      "FAIL(no call)" "called with correct args"
    else
        chk "preflight passes: retype invoked"      "FAIL($got)" "called with correct args"
    fi
fi

# Test 3: retype fails -> E_DISPATCH_FAILED
printf 'ceph\nfail-retype\n' > $T/types
mkvol available "[]" ceph
: > $CINDER_CALL_LOG
cinder_move_volume v1 fail-retype >$T/o 2>&1
ret=$?
got_code=$(sed -n 's/.*"code":"\([^"]*\)".*/\1/p' $T/o | head -1)
got_ok=$(sed -n 's/.*"ok":\([^,}]*\).*/\1/p' $T/o | head -1)
if [ "$got_code" = "E_DISPATCH_FAILED" ] && [ "$got_ok" = "false" ] ; then
    chk "retype fails: E_DISPATCH_FAILED returned"  "PASS" "ok:false, code:E_DISPATCH_FAILED"
else
    chk "retype fails: E_DISPATCH_FAILED returned"  "FAIL(code=$got_code,ok=$got_ok)" "ok:false, code:E_DISPATCH_FAILED"
fi

rm -rf $T
