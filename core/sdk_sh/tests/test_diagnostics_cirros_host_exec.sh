#!/bin/bash
#
# Unit test for ../modules/sdk_diagnostics.sh (cubecos#1727):
#   diagnostics_cirros_host_exec -- run a command inside every _diagnostics VM on this host
#   diagnostics_cirros_exec      -- its per-VM half, guarded on the VM being in `virsh list`
#   diagnostics_network          -- `diagnostics testground construct`
#
# The regression that matters: host_exec read the libvirt name with `jq -r .instance_name`.
# That bare key was an alias the 3.1.0 client (osc 5.8.1 / sdk 0.62.0) added to
# `server show`; osc 6.6.1 and 7.5.1 print only the API's OS-EXT-SRV-ATTR:instance_name.
# jq then printed "null", `virsh list | grep -q null` missed, the per-VM half returned 0
# before its console session, and every result block read "Outputs from null (null)" over
# an empty body while the command still succeeded.
#
# Self-contained: sources the module (it defines functions only; the awk extraction the
# other tests use stops at the first column-0 brace, and the expect script inside
# diagnostics_cirros_exec has one) and stubs openstack, hex_sdk, virsh, expect and the
# testground helpers, so it needs no cluster.
#   Run: bash test_diagnostics_cirros_host_exec.sh   (exit 0 = pass)
#   SRC=<other sdk_diagnostics.sh> runs the same assertions against another version, e.g.
#   origin/develop before #1727, where the cases marked [#1727] must fail.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_diagnostics.sh}"

PROG=test source "$SRC" || { echo "FAIL: cannot source $SRC"; exit 1; }
for f in diagnostics_cirros_host_exec diagnostics_cirros_exec diagnostics_network ; do
    [ "$(type -t $f)" = function ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
done

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2', want '$3'"; fi; }
has()   { if grep -qF -- "$3" "$2"; then ok; else bad "$1: no line matching '$3'"; fi; }
hasnt() { if grep -qF -- "$3" "$2"; then bad "$1: unexpected line matching '$3'"; else ok; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS=$TMP/calls
OUT=$TMP/out

# ---- stubs ---------------------------------------------------------------
HOSTNAME=cmp1
OPENSTACK=fake_openstack
HEX_SDK=fake_hex_sdk

# SERVERS: "<id>:<instance hostname>:<libvirt name>" for each _diagnostics VM on cmp1.
# `server show` answers the way osc 6.6.1 and 7.5.1 do: only the OS-EXT-SRV-ATTR keys.
fake_openstack() {
    echo "openstack $*" >> "$CALLS"
    local s id
    case "$*" in
        "server list --project _diagnostics --host cmp1 --long -f json")
            printf '['
            local sep=
            for s in $SERVERS ; do printf '%s{"ID": "%s", "Host": "cmp1"}' "$sep" "${s%%:*}" ; sep=', ' ; done
            printf ']\n'
            ;;
        "server show "*" -f json")
            id=$3
            for s in $SERVERS ; do
                [ "${s%%:*}" = "$id" ] || continue
                IFS=: read -r _ h i <<<"$s"
                printf '{"id": "%s", "OS-EXT-SRV-ATTR:host": "cmp1", "OS-EXT-SRV-ATTR:hostname": "%s", "OS-EXT-SRV-ATTR:instance_name": "%s"}\n' "$id" "$h" "$i"
            done
            ;;
    esac
}
# FAIL_INS: libvirt names whose in-guest run fails
fake_hex_sdk() {
    local fn=$1 ins=$2
    shift 2
    echo "hex_sdk $fn $ins $*" >> "$CALLS"
    echo "ran '$*' in $ins"
    case " $FAIL_INS " in *" $ins "*) return 1 ;; esac
    return 0
}
# RUNNING: libvirt names in `virsh list`
virsh() {
    echo " Id   Name                State"
    echo "------------------------------------"
    local n=1 i
    for i in $RUNNING ; do echo " $n    $i   running" ; n=$((n+1)) ; done
}
expect() { echo "expect" >> "$CALLS" ; echo "console session" ; }

# The functions under test run with set +u, as hex_sdk runs them.
# run_host_exec: host_exec with the testground's DNS command, as _diagnostics_instance_dns runs it
run_host_exec() {
    : > "$CALLS"
    ( set +u ; diagnostics_cirros_host_exec "nslookup www.google.com 8.8.8.8 ; ping 8.8.8.8 -c 3" ) >"$OUT" 2>&1
    RC=$?
}

# ---- 1. [#1727] the VM is found under its API key and the command runs in it ----
SERVERS="s1:vm-a:instance-00000001" FAIL_INS=
run_host_exec
check "1 rc" "$RC" 0
has   "1 [#1727] command sent to the libvirt domain" "$CALLS" "hex_sdk diagnostics_cirros_exec instance-00000001 nslookup www.google.com 8.8.8.8 ; ping 8.8.8.8 -c 3"
has   "1 [#1727] block names the VM" "$OUT" "---- Outputs from vm-a (instance-00000001) on cmp1----"
has   "1 [#1727] block carries the in-guest output" "$OUT" "ran 'nslookup www.google.com 8.8.8.8 ; ping 8.8.8.8 -c 3' in instance-00000001"
hasnt "1 [#1727] no null label" "$OUT" "null"

# ---- 2. [#1727] two VMs on one host: each block is labelled with its own VM ----
SERVERS="s1:vm-a:instance-00000001 s2:vm-b:instance-00000002" FAIL_INS=
run_host_exec
check "2 rc" "$RC" 0
has   "2 [#1727] first block" "$OUT" "---- Outputs from vm-a (instance-00000001) on cmp1----"
has   "2 [#1727] second block has the second VM's name" "$OUT" "---- Outputs from vm-b (instance-00000002) on cmp1----"
has   "2 second VM's output" "$OUT" "in instance-00000002"

# ---- 3. [#1727] a VM whose run fails fails the host and says so -----------
SERVERS="s1:vm-a:instance-00000001 s2:vm-b:instance-00000002" FAIL_INS=instance-00000002
run_host_exec
if [ "$RC" != 0 ] ; then ok ; else bad "3 [#1727] a failed VM must fail the host, got rc=0" ; fi
has   "3 [#1727] failure named" "$OUT" "Failed to run in-guest checks in vm-b (instance-00000002) on cmp1"
hasnt "3 the VM that passed is not reported" "$OUT" "Failed to run in-guest checks in vm-a"
has   "3 the passing VM's output is still printed" "$OUT" "in instance-00000001"

# ---- 4. [#1727] no _diagnostics VM on this host is a failure, not an empty pass ----
SERVERS= FAIL_INS=
run_host_exec
if [ "$RC" != 0 ] ; then ok ; else bad "4 [#1727] no VM on the host must fail, got rc=0" ; fi
has   "4 [#1727] says nothing was found" "$OUT" "Failed to find any _diagnostics instance on cmp1"
hasnt "4 nothing sent" "$CALLS" "hex_sdk diagnostics_cirros_exec"

# ---- 5. [#1727] cirros_exec: a VM missing from virsh list fails before the console ----
run_exec() {
    : > "$CALLS"
    ( set +u ; diagnostics_cirros_exec "$@" ) >"$OUT" 2>&1
    RC=$?
}
RUNNING="instance-00000001"
run_exec instance-00000002 echo hi
if [ "$RC" != 0 ] ; then ok ; else bad "5 [#1727] a VM not running here must fail, got rc=0" ; fi
has   "5 [#1727] says why" "$OUT" "instance instance-00000002 is not running on cmp1"
hasnt "5 no console session" "$CALLS" "expect"

run_exec null echo hi
if [ "$RC" != 0 ] ; then ok ; else bad "5 [#1727] the literal null must fail, got rc=0" ; fi
hasnt "5 null: no console session" "$CALLS" "expect"

# the guard matches the whole name, not a prefix of a longer one
RUNNING="instance-000000011"
run_exec instance-00000001 echo hi
if [ "$RC" != 0 ] ; then ok ; else bad "5 a longer name must not satisfy the guard, got rc=0" ; fi

RUNNING="instance-00000001"
run_exec instance-00000001 echo hi
check "5 running VM rc" "$RC" 0
has   "5 running VM gets its console session" "$CALLS" "expect"

# ---- 6. [#1727] diagnostics_network fails when an in-guest round fails ----
_diagProjCreate() { : ; }
_diagNetCreate() { : ; }
_diagFlvrCreate() { : ; }
_diagQuotaUnlimit() { : ; }
_diagSrvCreate() { echo "create $*" >> "$CALLS" ; }
_diagSrvDelete() { echo "delete" >> "$CALLS" ; }
_diagSrvShiftHost() { echo "shift" >> "$CALLS" ; }
cubectl() { echo "cmp1" ; }   # one compute node: no migration rounds
# DNS_RC: exit status of each _diagnostics_instance_dns round, in order
_diagnostics_instance_dns() {
    echo "dns $*" >> "$CALLS"
    local r=${DNS_RC%% *}
    DNS_RC=${DNS_RC#* }
    return $r
}
run_network() {
    : > "$CALLS"
    ( set +u ; diagnostics_network public www.google.com 8.8.8.8 ) >"$OUT" 2>&1
    RC=$?
}

DNS_RC="0 0 "
run_network
check "6 every round passes" "$RC" 0
check "6 two rounds ran" "$(grep -c '^dns ' "$CALLS")" 2

DNS_RC="1 0 "
run_network
if [ "$RC" != 0 ] ; then ok ; else bad "6 [#1727] a failed first round must fail the run, got rc=0" ; fi
check "6 a failure does not stop the second round" "$(grep -c '^dns ' "$CALLS")" 2

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
