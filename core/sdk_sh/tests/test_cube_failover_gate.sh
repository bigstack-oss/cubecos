#!/bin/bash
#
# Unit test for cube_failover_gate_open in ../../main/proj_functions: the failover
# monitors wait until this node, the master, the controls and every host running
# instances finished booting; a down host does not hold them; hosts without
# instances are not waited for; if this node has no DB every compute is checked;
# hosts are checked in parallel; 15 min after this node is done the gate opens
# anyway. Fakes ssh, the DB, cubectl and the /run records; needs no cluster.
#   Run: bash test_cube_failover_gate.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
grep '^CUBE_BOOT_DONE_TEST=' $D/../../main/proj_functions | sed "s|/run/|$T/run/|g" > $T/fn.sh
for f in cube_failover_gate_open cube_nodes_booted_or_down ; do
    sed -n "/^$f()/,/^}/p" $D/../../main/proj_functions
done | sed -e "s|/run/|$T/run/|g" -e "/source \/usr\/sbin\/hex_tuning/d" >> $T/fn.sh
source $T/fn.sh
mkdir -p $T/run $T/st
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }
hostname() { echo c1; }
T_cubesys_control_hosts="c1,c2,c3"
COMPUTES=$(seq -f "cmp%02g" 1 60)
# nodes: controls, 60 computes, storage-only s1; -r compute lists the computes
cubectl() { local l="c1 c2 c3 $COMPUTES s1"; [[ " $* " == *" -r compute "* ]] && l="c1 c2 c3 $COMPUTES"
            printf '[%s]' "$(for n in $l ; do printf '{"hostname":"%s"},' $n ; done | sed 's/,$//')"; }
# nova: every compute runs instances, controls too
DB=up; db() { [ $DB = up ] || return 1; printf '%s\n' c1 c2 c3 $COMPUTES; }; MYSQL=db
MASTER=c1; cube_master_control() { echo $MASTER; }
is_sshable() { [ "$(cat $T/st/$1 2>/dev/null)" != down ]; }
# per-host state in $T/st/<host>: done (default) | booting | down
ssh() { for a ; do case $a in root@*) h=${a#root@} ;; esac ; done
        [ -n "$SLOW" ] && sleep $SLOW
        case $(cat $T/st/$h 2>/dev/null || echo done) in done) return 0 ;; booting) return 1 ;; down) return 255 ;; esac ; }
timeout() { shift; "$@"; }
gate() { cube_failover_gate_open >/dev/null 2>&1 && echo open || echo held; }
done_ago() { echo "done $(( $(date +%s) - $1 ))" > $T/run/cube_bootup_status; }
reset() { rm -f $T/st/*; DB=up; MASTER=c1; SLOW=; }

echo "boot 1" > $T/run/cube_bootup_status
check "this node still booting" "$(gate)" held
done_ago 10; reset
check "every host done" "$(gate)" open
echo booting > $T/st/c3
check "a control still booting" "$(gate)" held
reset; echo booting > $T/st/cmp42
check "one of 60 computes still booting" "$(gate)" held
reset; echo down > $T/st/cmp42
check "booting compute is down: not waited for" "$(gate)" open
reset; echo booting > $T/st/s1
check "storage node without instances: not waited for" "$(gate)" open
DB=down
check "no DB: storage node still not waited for" "$(gate)" open
echo booting > $T/st/cmp13
check "no DB: a booting compute holds" "$(gate)" held
reset; MASTER=c2; echo booting > $T/st/c2
check "remote master still booting" "$(gate)" held
echo down > $T/st/c2
check "remote master down" "$(gate)" open
reset; echo booting > $T/st/cmp07; done_ago 1000
check "compute stuck booting, this node done >15 min" "$(gate)" open
done_ago 10; reset; SLOW=1; S=$SECONDS; r=$(gate)
check "62 hosts at 1 s each checked in parallel" "$r/$([ $((SECONDS-S)) -lt 10 ] && echo fast || echo slow)" open/fast

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
