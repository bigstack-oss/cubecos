#!/bin/bash
#
# Unit test for os_rabbitmq_peer_running (../modules/sdk_os.sh): the master's
# boot commit treats it as a cold start only when no peer control's broker is up.
# Self-contained, mocks everything. Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
eval "$(extract "$DIR/../modules/sdk_os.sh" os_rabbitmq_peer_running)"
type os_rabbitmq_peer_running >/dev/null 2>&1 || { echo "FAIL: not extracted"; exit 1; }

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
hostname(){ echo c1; }
ACTIVE="" DEAD=""
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
# remote_run exits (like Error) on an unsshable node
remote_run(){ echo "$1" >> "$LOG"; [[ " $DEAD " == *" $1 "* ]] && exit 1; [[ " $ACTIVE " == *" $1 "* ]]; }

out=$(os_rabbitmq_peer_running); rc=$?
chk "cold start: none running" "$rc:$out" "1:"
chk "never probes itself" "$(grep -c '^c1$' "$LOG")" "0"

ACTIVE="c3"
out=$(os_rabbitmq_peer_running); rc=$?
chk "rejoin: peer found" "$rc:$out" "0:c3"

ACTIVE="c3" DEAD="c2"
out=$(os_rabbitmq_peer_running); rc=$?
chk "unsshable peer skipped, next checked" "$rc:$out" "0:c3"

ACTIVE="" DEAD="c2 c3"
out=$(os_rabbitmq_peer_running); rc=$?
chk "all peers dead: none" "$rc:$out" "1:"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
