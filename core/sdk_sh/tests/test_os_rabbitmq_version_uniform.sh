#!/bin/bash
#
# Unit test for os_rabbitmq_version_uniform (../modules/sdk_os.sh): uniform only when
# every control node answers with one RabbitMQ minor; a node that does not answer is
# asked again before it counts as a miss (#2164), and a "no" says why in the log.
# Self-contained, mocks everything. Run: bash test_os_rabbitmq_version_uniform.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
eval "$(extract "$DIR/../modules/sdk_os.sh" os_rabbitmq_version_uniform)"
type os_rabbitmq_version_uniform >/dev/null 2>&1 || { echo "FAIL: not extracted"; exit 1; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cubectl(){ echo '[{"hostname":"c1"},{"hostname":"c2"},{"hostname":"c3"}]'; }
sleep(){ echo "sleep $1" >> $T/calls; }
log_info(){ echo "$1" >> $T/log; }
# per-host answer in $T/ver/<host>; $T/silent/<host> holds how many asks get no answer
remote_run(){ echo "rr $1" >> $T/calls
    local n; n=$(cat $T/silent/$1 2>/dev/null || echo 0)
    if [ "$n" -gt 0 ] ; then echo $((n - 1)) > $T/silent/$1 ; return 1 ; fi
    cat $T/ver/$1 2>/dev/null; }
reset(){ rm -rf $T/ver $T/silent $T/calls $T/log; mkdir -p $T/ver $T/silent; touch $T/calls $T/log
    for h in c1 c2 c3 ; do echo "${1:-3.11.28}" > $T/ver/$h ; done; }
asks(){ grep -c "^rr $1$" $T/calls; }

reset
os_rabbitmq_version_uniform; chk "uniform" "$?" 0
chk "uniform: one ask each" "$(asks c1)$(asks c2)$(asks c3)" 111
chk "uniform: no sleep" "$(grep -c sleep $T/calls)" 0
chk "uniform: nothing logged" "$(wc -l < $T/log)" 0

reset; echo 3.12.14 > $T/ver/c1
os_rabbitmq_version_uniform; chk "mixed" "$?" 1
chk "mixed: answering nodes not asked again" "$(asks c1)$(asks c2)$(asks c3)" 111
chk "mixed: log names each version" "$(cat $T/log)" "rabbitmq version: not uniform: c1=3.12 c2=3.11 c3=3.11"

# the cube42 case: one peer slow to accept a connection at the last node's commit
reset; echo 1 > $T/silent/c2
os_rabbitmq_version_uniform; chk "slow peer answers the 2nd ask: uniform" "$?" 0
chk "slow peer: asked twice" "$(asks c2)" 2
chk "slow peer: one 5 s wait" "$(grep -c 'sleep 5' $T/calls)" 1

reset; echo 2 > $T/silent/c1
os_rabbitmq_version_uniform; chk "3rd ask answers: uniform" "$?" 0
chk "3rd ask: two waits" "$(grep -c 'sleep 5' $T/calls)" 2

reset; echo 9 > $T/silent/c2
os_rabbitmq_version_uniform; chk "dead peer: not uniform" "$?" 1
chk "dead peer: asked 3 times" "$(asks c2)" 3
chk "dead peer: two waits, none after the last ask" "$(grep -c 'sleep 5' $T/calls)" 2
chk "dead peer: stops there" "$(asks c3)" 0
chk "dead peer: log names it" "$(cat $T/log)" "rabbitmq version: c2 did not answer, so not uniform"

reset
cubectl(){ :; }
os_rabbitmq_version_uniform; chk "no control list: not uniform" "$?" 1

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
