#!/bin/bash
#
# Unit test for health_rabbitmq_repair (../modules/sdk_health.sh): a node whose own broker
# does not answer takes a peer's view of the cluster before it decides there is no healthy
# core (#2164). A 3.12 broker that refuses a flag the 3.11 peers left disabled stays down,
# and the live-migration gate's repair on that node read its empty view as "0 running" and
# wiped mnesia on every control node, the peers it had kept included. Self-contained, mocks
# $HEX_CFG, remote_run and remote_systemd_stop. Run: bash test_sdk_health_rabbitmq_repair.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
eval "$(extract "$DIR/../modules/sdk_health.sh" health_rabbitmq_repair)"
type health_rabbitmq_repair >/dev/null 2>&1 || { echo "FAIL: not extracted"; exit 1; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
HOSTNAME=cc1 HEX_STATE_DIR=/etc/appliance/state HEX_CFG=hexcfg
sleep(){ :; }
# each broker's cluster_status in $T/view/<host>, none when it is down; $T/nossh/<host> fails ssh
hexcfg(){ [ "$1" = status_rabbitmq ] && cat $T/view/$HOSTNAME 2>/dev/null; }
remote_run(){ local h=$1; shift; echo "rr $h $*" >> $T/calls
    [ -e $T/nossh/$h ] && return 1
    case "$*" in *status_rabbitmq) cat $T/view/$h 2>/dev/null ;; esac; }
remote_systemd_stop(){ echo "stop $1 $2" >> $T/calls; }
reset(){ rm -rf $T/view $T/nossh $T/calls; mkdir -p $T/view $T/nossh; touch $T/calls; }
view(){ local h=$1 n out=; shift
    for n in "$@" ; do out+="${out:+,}\"rabbit@$n\"" ; done
    echo "{\"running_nodes\":[$out],\"partitions\":[]}" > $T/view/$h; }
calls(){ grep -c "$1" $T/calls; }

# cc1 refuses on its first 3.2.0 boot; cc2 and cc3 still run 3.1.20 together
reset; view cc2 cc2 cc3; view cc3 cc2 cc3
health_rabbitmq_repair
chk "refusing node: no broker stopped" "$(calls '^stop ')" 0
chk "refusing node: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0
chk "refusing node: first answering peer's view taken" "$(calls 'status_rabbitmq')" 2
chk "refusing node: only it is restarted" "$(grep 'restart rabbitmq-server' $T/calls | cut -d' ' -f2 | paste -sd' ')" "cc1"
chk "refusing node: only it rejoins, at a peer" "$(awk '{for (i = 1; i < NF; i++) if ($i == "join_cluster") print $2, $(i+1)}' $T/calls)" "cc1 rabbit@cc2"

# a peer that cannot be reached is skipped
reset; touch $T/nossh/cc2; view cc3 cc2 cc3
health_rabbitmq_repair
chk "unreachable peer: next peer asked" "$(calls '^rr cc3 hexcfg status_rabbitmq')" 1
chk "unreachable peer: no mnesia wiped" "$(calls 'rm -rf /var/lib/rabbitmq/mnesia')" 0

# this node's broker answers: the peers are not asked
reset; view cc1 cc1 cc2 cc3
health_rabbitmq_repair
chk "healthy: no peer asked" "$(calls 'status_rabbitmq')" 0
chk "healthy: nothing done" "$(wc -l < $T/calls)" 0

# every broker down: every view is empty, and the full rebuild runs as before
reset
health_rabbitmq_repair
chk "all down: every broker stopped" "$(calls '^stop ')" 3
chk "all down: every mnesia wiped" "$(grep 'rm -rf /var/lib/rabbitmq/mnesia' $T/calls | cut -d' ' -f2 | paste -sd' ')" "cc1 cc2 cc3"
chk "all down: every broker restarted" "$(calls 'restart_rabbitmq')" 3

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
