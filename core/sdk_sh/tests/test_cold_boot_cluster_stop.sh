#!/bin/bash
# cubecos#1805: one slow peer must not read as "no node ready", and a roll
# must never trigger the boot-time cluster stop.
T=$(mktemp -d)
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
sed -n '/^health_bootstrap_check()/,/^}/p' $ROOT/core/sdk_sh/modules/sdk_health.sh > $T/fn.sh
sed -n '/^ColdBootClusterStop()/,/^}/p' $ROOT/core/main/bootstrap_cube_config >> $T/fn.sh
sed -n '/^remote_run()/,/^}/p' $ROOT/core/sdk_sh/modules.pre/sdk_remote.sh >> $T/fn.sh
sed -n '/^cube_cluster_peer_up()/,/^}/p' $ROOT/core/main/proj_functions >> $T/fn.sh
source $T/fn.sh
FAIL=0
chk(){ printf '%-46s -> %-10s (want %s)\n' "$1" "$2" "$3"; [ "$2" = "$3" ] || FAIL=1; }

CUBE_DONE=/run/cube_commit_done
Error(){ exit 1; }                          # the sdk's Error exits
_health_fail_log(){ echo -e "$ERR_MSG"; }   # VERBOSE=1 output
journalctl(){ :; }
SLOW=""                                     # node whose ssh probe times out
is_sshable(){ [ "$1" != "$SLOW" ]; }
ssh(){ [ "$1" != "root@c1" ]; }             # c1 = this node, booting, not done yet
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3 p4 p5)

# 1. health check: a slow peer is n/a, the others are still probed
SLOW=c2
out=$( (health_bootstrap_check) )
chk "slow c2: ready count" "$(echo "$out" | grep -c ready)" "3"
chk "slow c2: reported n/a" "$(echo "$out" | grep -c 'c2 services ... \[n/a\]')" "1"

# 2. guard, with hex_sdk stubbed
ROLLING=1
hex_sdk(){
    case "$1" in
        is_cluster_rolling) [ "$ROLLING" = "1" ] ;;
        cube_cluster_peer_up) [ "$PEER_UP" = "1" ] ;;
        -v) (health_bootstrap_check) ;;
        cube_cluster_boot_stop) echo stopped >> $T/stop ;;
    esac
}
CLUSTER_SIZE=5; PEER_UP=0
run(){ rm -f $T/stop; ColdBootClusterStop >/dev/null; [ -e $T/stop ] && echo stop || echo no-stop; }

ROLLING=1; SLOW=c2
chk "roll in progress" "$(run)" "no-stop"
ROLLING=0; SLOW=c2
chk "no roll, slow c2, peers ready" "$(run)" "no-stop"
ROLLING=0; SLOW=""; ssh(){ return 1; }
chk "no roll, no node ready (cold boot)" "$(run)" "stop"
ROLLING=0; ssh(){ return 0; }; CLUSTER_SIZE=0
chk "no roll, empty node list" "$(run)" "stop"

# 3. cube4510: c1 rejoins after a host-failure test, c2 slow ssh, c3 up
CLUSTER_SIZE=3; CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
ROLLING=0; SLOW=c2; ssh(){ [ "$1" != "root@c1" ]; }; PEER_UP=1
chk "cube4510: c3 ready, c2 slow" "$(run)" "no-stop"
ssh(){ return 1; }
chk "cube4510: no peer ready by ssh, peer up" "$(run)" "no-stop"
PEER_UP=0
chk "no peer ready, no peer up (cold boot)" "$(run)" "stop"

# 4. cube_cluster_peer_up: galera/rabbitmq port on a peer, or a peer-held VIP
mkdir -p $T/bin
cat > $T/bin/hex_tuning <<'EOT'
T_cubesys_control_addrs=10.0.0.1,10.0.0.2,10.0.0.3
T_cubesys_control_vip=10.0.0.10
EOT
PATH=$T/bin:$PATH
HOSTNAME=c1
hostname(){ echo "10.0.0.1 $LOCALVIP"; }
cubectl(){ echo '[{"ip":{"management":"10.0.0.1"}},{"ip":{"management":"10.0.0.2"}},{"ip":{"management":"10.0.0.3"}}]'; }
OPEN=""                                     # "ip/port" pairs that accept
timeout(){ local a; for a in $OPEN ; do [[ "$4" == *"/dev/tcp/$a"* ]] && return 0; done; return 1; }
VIPUP=0; ping(){ [ "$VIPUP" = "1" ]; }
LOCALVIP=""
pu(){ cube_cluster_peer_up >/dev/null && echo up || echo down; }
chk "peer_up: nothing listening, no VIP" "$(pu)" "down"
OPEN="10.0.0.3/4567"
chk "peer_up: galera on c3" "$(pu)" "up"
OPEN="10.0.0.2/5672"
chk "peer_up: rabbitmq on c2" "$(pu)" "up"
OPEN="10.0.0.1/4567 10.0.0.1/5672"
chk "peer_up: own ports ignored" "$(pu)" "down"
OPEN=""; VIPUP=1
chk "peer_up: VIP held by a peer" "$(pu)" "up"
LOCALVIP=10.0.0.10
chk "peer_up: VIP held locally ignored" "$(pu)" "down"

rm -rf $T
exit $FAIL
