#!/bin/bash
#
# Unit test for the audit point _hex_exec (../../main/proj_functions) writes on every hex_sdk
# call: the per-call values (pid, ppid, gpid, the ssh peer's port) are fields, so calls from
# the same caller share one series instead of adding one each.
#   Run: bash test_hex_exec_audit_point.sh
#
set -u
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
b="$(sed -n '/^_hex_exec()/,/^}/p' $D/../../main/proj_functions)"
[ -n "$b" ] || { echo "FAIL: _hex_exec not extracted"; exit 1; }
eval "$b"
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got [$2] want [$3]" ; FAILS=$((FAILS+1)) ; fi ; }

HOSTNAME=n1
PCMD="" GCMD="" GPID="" PEER="" GPEER=""
# os_nova_list appends to a global "fields"; it runs inside _hex_exec
audit_probe() { printf '%s' "${fields-}" > $T/callee_fields; }
influx_event() { printf '%s\n' "$*" > $T/point; }
ps() {
    case "$*" in
        "-o user= -p $$"|"-o user= -p $PPID") echo root ;;
        "-o comm= $PPID") echo "$PCMD" ;;
        "-o ppid= -p $PPID") echo "$GPID" ;;
        "-o comm= $GPID") [ -n "$GPID" ] && echo "$GCMD" ;;
        "-o user= -p $GPID") [ -n "$GPID" ] && echo admin ;;
        "-p "*) return 0 ;;
    esac
}
# _hex_exec asks ss for the parent's peer first, then the grandparent's
ss() {
    local n=$(cat $T/ssn 2>/dev/null || echo 0)
    echo $((n + 1)) > $T/ssn
    if [ "$n" = 0 ] ; then
        echo "tcp ESTAB 0 0 10.32.42.3:22 $PEER users:((\"sshd-session\",pid=$PPID,fd=4))"
    else
        echo "tcp ESTAB 0 0 10.32.42.3:22 $GPEER users:((\"sshd-session\",pid=$GPID,fd=4))"
    fi
}
run() { rm -f $T/point $T/ssn ; _hex_exec audit_probe ; P=$(sed 's/^insert //' $T/point) ; TAGS=${P%% *} ; FIELDS=${P#* } ; }
has() { case ",$1," in *",$2,"*) echo yes ;; *) echo no ;; esac ; }

PCMD=bash GCMD=sudo GPID=4242
run
check "tags hold no per-call value" "$TAGS" "audit,node=n1,gusr=admin,gcmd=sudo,pusr=root,pcmd=bash,usr=root"
check "cmd field" "$(has "$FIELDS" 'cmd="audit_probe"')" yes
check "pid field" "$(has "$FIELDS" "pid=$$i")" yes
check "ppid field" "$(has "$FIELDS" "ppid=${PPID}i")" yes
check "gpid field" "$(has "$FIELDS" "gpid=4242i")" yes
check "no peer field outside ssh" "$(echo "$FIELDS" | grep -c _peer)" 0
check "the command does not inherit a fields variable" "$(cat $T/callee_fields)" ""

GPID=
run
check "no grandparent: no empty gpid field" "$(echo "$P" | grep -c gpid)" 0

PCMD=sshd-session GCMD=sshd-session GPID=4242 PEER=10.32.42.2:51848 GPEER=10.32.42.2:51848
run
check "ssh v4: tags keep the peer address, not its port" "$TAGS" "audit,node=n1,gusr=admin,gcmd=sshd-session(10.32.42.2),pusr=root,pcmd=sshd-session(10.32.42.2),usr=root"
check "ssh v4: pcmd_peer field" "$(has "$FIELDS" 'pcmd_peer="10.32.42.2:51848"')" yes
check "ssh v4: gcmd_peer field" "$(has "$FIELDS" 'gcmd_peer="10.32.42.2:51848"')" yes

PEER="[::1]:51848" GPEER="[::1]:51848"
run
check "ssh v6: tags keep the bracketed address" "$TAGS" "audit,node=n1,gusr=admin,gcmd=sshd-session([::1]),pusr=root,pcmd=sshd-session([::1]),usr=root"
check "ssh v6: pcmd_peer field" "$(has "$FIELDS" 'pcmd_peer="[::1]:51848"')" yes

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS failed"; exit 1; }
