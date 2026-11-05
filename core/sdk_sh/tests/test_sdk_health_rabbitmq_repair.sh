#!/bin/bash
#
# Unit test for health_rabbitmq_repair (../modules/sdk_health.sh): a node whose own broker
# does not answer takes a peer's view of the cluster before it decides there is no healthy
# core (#2164). A 3.12 broker that refuses a flag the 3.11 peers left disabled stays down,
# and the live-migration gate's repair on that node read its empty view as "0 running" and
# wiped mnesia on every control node, the peers it had kept included. Partition recovery
# also uses the majority view and restarts only brokers outside it (#2261). Self-contained, mocks
# $HEX_CFG, remote_run and remote_systemd_stop. Run: bash test_sdk_health_rabbitmq_repair.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
for f in health_rabbitmq_repair _health_rabbitmq_majority_view _health_rabbitmq_rejoin _health_rabbitmq_auto_repair ; do
    eval "$(extract "$DIR/../modules/sdk_health.sh" "$f")"
    type "$f" >/dev/null 2>&1 || { echo "FAIL: $f not extracted"; exit 1; }
done

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
HOSTNAME=cc1 HEX_STATE_DIR=/etc/appliance/state HEX_CFG=hexcfg
sleep(){ :; }
# each broker's cluster_status in $T/view/<host>, none when it is down; $T/nossh/<host> fails ssh
hexcfg(){ [ "$1" = status_rabbitmq ] && cat $T/view/$HOSTNAME 2>/dev/null; }
remote_run(){ local h=$1 seed stats; shift; echo "rr $h $*" >> $T/calls
    [ -e $T/nossh/$h ] && return 1
    case "$*" in
        *status_rabbitmq) cat $T/view/$h 2>/dev/null ;;
        "systemctl restart rabbitmq-server")
            if [ -e $T/heals/$h ] ; then
                seed=$(cat $T/heals/$h)
                stats=$(jq --arg node "rabbit@$h" '.running_nodes += [$node] | .partitions = {}' $T/view/$seed)
                echo "$stats" > $T/view/$seed
            fi ;;
    esac; }
remote_systemd_stop(){ echo "stop $1 $2" >> $T/calls; }
reset(){ rm -rf $T/view $T/nossh $T/heals $T/calls; mkdir -p $T/view $T/nossh $T/heals; touch $T/calls; HOSTNAME=cc1; }
pview(){ local h=$1 partitions=$2 n out=; shift 2
    for n in "$@" ; do out+="${out:+,}\"rabbit@$n\"" ; done
    echo "{\"running_nodes\":[$out],\"partitions\":$partitions}" > $T/view/$h; }
view(){ local h=$1; shift; pview "$h" '[]' "$@"; }
calls(){ grep -c "$1" $T/calls; }

# cc1 refuses on its first 3.2.0 boot; cc2 and cc3 still run 3.1.20 together
reset; view cc2 cc2 cc3; view cc3 cc2 cc3
health_rabbitmq_repair
chk "refusing node: no broker stopped" "$(calls '^stop ')" 0
chk "refusing node: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0
chk "refusing node: first answering peer's view taken" "$(calls '^rr cc3 .*status_rabbitmq')" 0
chk "refusing node: answering peer asked" "$([ "$(calls '^rr cc2 .*status_rabbitmq')" -ge 1 ] && echo yes)" yes
chk "refusing node: only it is restarted" "$(grep 'restart rabbitmq-server' $T/calls | cut -d' ' -f2 | paste -sd' ' -)" "cc1"
chk "refusing node: only it rejoins, at a peer" "$(awk '{for (i = 1; i < NF; i++) if ($i == "join_cluster") print $2, $(i+1)}' $T/calls)" "cc1 rabbit@cc2"

# a peer that cannot be reached is skipped
reset; touch $T/nossh/cc2; view cc3 cc2 cc3
health_rabbitmq_repair
chk "unreachable peer: next peer asked" "$([ "$(calls '^rr cc3 hexcfg status_rabbitmq')" -ge 1 ] && echo yes)" yes
chk "unreachable peer: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0

# this node's broker answers: the peers are not asked
reset; view cc1 cc1 cc2 cc3
health_rabbitmq_repair
chk "healthy: no peer asked" "$(calls 'status_rabbitmq')" 0
chk "healthy: nothing done" "$(wc -l < $T/calls | tr -d ' ')" 0

# every broker down: every view is empty, and the full rebuild runs as before
reset
health_rabbitmq_repair
chk "all down: every broker stopped" "$(calls '^stop ')" 3
chk "all down: every mnesia wiped" "$(grep 'rm -rf /var/lib/rabbitmq/mnesia' $T/calls | cut -d' ' -f2 | paste -sd' ' -)" "cc1 cc2 cc3"
chk "all down: every broker restarted" "$(calls 'restart_rabbitmq')" 3

# cc1 is cut off; cc2 and cc3 retain the majority, with partition maps on both sides
split_view(){
    pview cc1 '{"rabbit@cc1":["rabbit@cc2","rabbit@cc3"]}' cc1
    pview cc2 '{"rabbit@cc2":["rabbit@cc1"]}' cc2 cc3
    pview cc3 '{"rabbit@cc3":["rabbit@cc1"]}' cc2 cc3
}
rejoined(){ local name=$1
    chk "$name: no broker stopped" "$(calls '^stop ')" 0
    chk "$name: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0
    chk "$name: only cc1 restarted" "$(grep 'restart rabbitmq-server' $T/calls | cut -d' ' -f2 | paste -sd' ' -)" cc1
    chk "$name: no reset" "$(calls 'rabbitmqctl reset')" 0
    chk "$name: no join" "$(calls 'join_cluster')" 0
}

reset; split_view; HOSTNAME=cc2; echo cc2 > $T/heals/cc1
health_rabbitmq_repair
rejoined "winner restart heals"

reset; split_view; echo cc2 > $T/heals/cc1
health_rabbitmq_repair
rejoined "loser restart heals"
chk "loser: majority peer asked" "$([ "$(calls '^rr cc2 .*status_rabbitmq')" -ge 1 ] && echo yes)" yes

reset; split_view; HOSTNAME=cc2
health_rabbitmq_repair
chk "restart does not heal: cc1 reset and joins seed" "$(calls '^rr cc1 rabbitmqctl stop_app ; rabbitmqctl reset ; rabbitmqctl join_cluster rabbit@cc2 ; rabbitmqctl start_app$')" 1
chk "restart does not heal: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0

# the seed does not answer after the restart: that is no word the node is still out
reset; split_view; HOSTNAME=cc2; touch $T/nossh/cc2
health_rabbitmq_repair
chk "seed silent: cc1 restarted" "$(grep 'restart rabbitmq-server' $T/calls | cut -d' ' -f2 | paste -sd' ' -)" cc1
chk "seed silent: no reset" "$(calls 'rabbitmqctl reset')" 0

reset; view cc1 cc1; view cc2 cc2; view cc3 cc3
ERR_CODE=3 _health_rabbitmq_auto_repair
chk "auto no majority: no broker stopped" "$(calls '^stop ')" 0
chk "auto no majority: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0
chk "auto no majority: no restart" "$(calls 'restart')" 0

reset; view cc2 cc2 cc3; view cc3 cc2 cc3; HOSTNAME=cc2
ERR_CODE=2 _health_rabbitmq_auto_repair
chk "auto code 2: nothing done" "$(wc -l < $T/calls | tr -d ' ')" 0

reset; split_view; HOSTNAME=cc2; echo cc2 > $T/heals/cc1
ERR_CODE=3 _health_rabbitmq_auto_repair
rejoined "auto partition restart heals"

# unattended, a restart that does not bring the node back is left there: no reset
reset; split_view; HOSTNAME=cc2
ERR_CODE=3 _health_rabbitmq_auto_repair
rejoined "auto restart does not heal"

# A partition without missing nodes still requires the manual full rebuild.
reset; HOSTNAME=cc2
pview cc2 '{"rabbit@cc2":["rabbit@cc1"]}' cc1 cc2 cc3
health_rabbitmq_repair
chk "partial partition: every broker stopped" "$(calls '^stop ')" 3
chk "partial partition: every mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 3

reset; HOSTNAME=cc2
pview cc2 '{"rabbit@cc2":["rabbit@cc1"]}' cc1 cc2 cc3
ERR_CODE=3 _health_rabbitmq_auto_repair
chk "auto partial partition: nothing done" "$(wc -l < $T/calls | tr -d ' ')" 0

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
