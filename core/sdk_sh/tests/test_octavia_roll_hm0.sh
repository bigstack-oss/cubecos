#!/bin/bash
# Restart roll: per-node o-hm0 bring-up + the pre-drain health-manager gate.
T=$(mktemp -d)
D=$(dirname $0)/..
for f in os_octavia_roll_node_up os_octavia_boot_node_up os_octavia_hm_peer_ready ; do
    sed -n "/^$f()/,/^}/p" $D/modules/sdk_os.sh >> $T/fn.sh
done
# the real fast path, renamed (the roll_node_up cases stub it), /run paths moved
for f in os_octavia_node_fast_up os_octavia_hm_gated ; do
    sed -n "/^$f()/,/^}/p" $D/modules/sdk_os.sh
done | sed -e "s|^os_octavia_node_fast_up()|real_fast_up()|" -e "s|/run/|$T/run/|g" >> $T/fn.sh
for f in _power_roll_octavia_ready _power_roll_octavia_hm_host ; do
    sed -n "/^$f()/,/^}/p" $D/modules/sdk_power.sh >> $T/fn.sh
done
# the real gate, with this node as master (no peer to ask), /run paths moved
sed -n "/^cube_failover_gate_open()/,/^}/p" $D/../main/proj_functions | sed "s|/run/|$T/run/|g" >> $T/fn.sh
cube_master_control(){ hostname; }
source $T/fn.sh
fail=0
chk(){ printf '%-48s -> %-12s (want %s)\n' "$1" "$2" "$3"; [ "$2" = "$3" ] || fail=1; }

# --- os_octavia_roll_node_up ---
ROLL=1 FIRST3=1 FAST=0 CALLS=$T/calls
is_rolling_restart_boot(){ [ $ROLL = 1 ]; }
is_first_three_compute_node(){ [ $FIRST3 = 1 ]; }
os_octavia_node_fast_up(){ echo fast >> $CALLS; [ $FAST = 1 ]; }
Quiet(){ shift; "$@"; }
HEX_CFG=cfg; cfg(){ echo "cfg $*" >> $CALLS; }
run(){ : > $CALLS; os_octavia_roll_node_up; tr '\n' ';' < $CALLS; }

ROLL=0;                chk "not a restart-roll boot" "$(run)" ""
ROLL=1 FIRST3=0;       chk "not a health-manager node" "$(run)" ""
FIRST3=1 FAST=1;       chk "fast path ok" "$(run)" "fast;"
FAST=0;                chk "fast path fails -> reinit" "$(run)" "fast;cfg reinit_octavia;"

# --- os_octavia_node_fast_up: a gate-held health-manager is not a failure ---
mkdir -p $T/run; touch $T/run/cube_commit_done
PLANNED_MAINT_MARKER=$T/maint HM_ACTIVE=0
os_octavia_cfg_ids_ok(){ :; }
os_octavia_hm0_up(){ :; }
/sbin/ip(){ echo "inet 172.16.0.11/16"; }
/usr/sbin/route(){ echo "172.16.0.0 0.0.0.0 255.255.0.0 U 0 0 0 octavia-hm0"; }
systemctl(){
    case "$2 $3" in
        "-q octavia-worker") return 0 ;;
        "-q octavia-health-manager") [ $HM_ACTIVE = 1 ] ;;
        *) echo "$*" >> $CALLS; [ $HM_ACTIVE = 1 ] ;;
    esac
}
fast(){ : > $CALLS; real_fast_up && echo ok || echo fail; }

rm -f $T/maint $T/run/cube_bootup_status
chk "boot not done: gate holds hm -> ok" "$(fast)" "ok"
chk "  start still requested" "$(tr '\n' ';' < $CALLS)" "start octavia-health-manager;"
echo "done 1" > $T/run/cube_bootup_status
chk "boot done, hm fails to start -> fail" "$(fast)" "fail"
touch $T/maint
chk "planned maintenance holds hm -> ok" "$(fast)" "ok"
rm -f $T/maint; HM_ACTIVE=1
chk "boot done, hm active -> ok" "$(fast)" "ok"
rm -f $T/run/cube_commit_done
chk "not committed -> fail" "$(fast)" "fail"
unset -f systemctl /sbin/ip /usr/sbin/route

# --- os_octavia_hm_peer_ready ---
NODES="n1 n2 n3 n4" UP=""
cubectl(){ [ -n "$NODES" ] || { echo "[]"; return; }; printf '{"h":"%s"}\n' $NODES | jq -s '[.[]|{hostname:.h}]'; }
remote_run(){ case " $UP " in *" $1 "*) return 0 ;; esac; return 1; }
ok(){ os_octavia_hm_peer_ready "$1" && echo yes || echo no; }

UP="";       chk "no hm0 anywhere" "$(ok n1)" "no"
UP="n1";     chk "only the node to drain has hm0" "$(ok n1)" "no"
UP="n2";     chk "another hm node has hm0" "$(ok n1)" "yes"
UP="n4";     chk "4th compute is not a hm node" "$(ok n1)" "no"
NODES="n1";  UP=""; chk "single hm node (nothing to ask)" "$(ok n1)" "yes"
NODES="";    chk "no compute nodes" "$(ok n1)" "yes"

# --- _power_roll_octavia_ready (bounded wait) ---
HEX_SDK=sdk; ROLLING_OCTAVIA_HM_POLL=0
sdk(){ shift; [ -e $T/up ]; }
ROLLING_OCTAVIA_HM_TIMEOUT=1; rm -f $T/up
s=$(date +%s); _power_roll_octavia_ready n1; r=$?
chk "never up -> times out" "$r" "1"
chk "  bounded by timeout" "$(( $(date +%s) - s <= 3 ))" "1"
touch $T/up
_power_roll_octavia_ready n1; chk "up -> proceeds" "$?" "0"

# --- _power_roll_octavia_hm_host (gate only hm nodes of a live octavia) ---
ENABLED="" HM="10.0.0.1,10.0.0.2,10.0.0.3" INIT=1
mkdir -p $T/bin; echo 'T_octavia_enabled=$ENABLED' > $T/bin/hex_tuning; PATH=$T/bin:$PATH
sdk(){ [ "$1" = os_octavia_hm_nodes ] && echo "$HM"; }
remote_run(){ [ $INIT = 1 ]; }
hm(){ _power_roll_octavia_hm_host "$1" master && echo yes || echo no; }

chk "hm node, octavia enabled + initialised" "$(hm 10.0.0.2)" "yes"
chk "not a hm node" "$(hm 10.0.0.4)" "no"
chk "  partial ip does not match" "$(hm 10.0.0)" "no"
ENABLED=false; chk "octavia disabled" "$(hm 10.0.0.2)" "no"
ENABLED=true INIT=0; chk "octavia not initialised" "$(hm 10.0.0.2)" "no"
INIT=1 HM=""; chk "no hm nodes" "$(hm 10.0.0.2)" "no"

rm -rf $T
exit $fail
