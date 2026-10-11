#!/bin/bash
#
# Guard: boot must not run a cluster-wide stop (#1805). Cold-start decisions
# live in the modules' boot commits; cube_cluster_stop stays operator-only
# (cluster stop/poweroff/powercycle) and still arms the galera/rabbitmq reset.
# Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$DIR/../../main"
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

chk "bootstrap runs no cluster stop" "$(grep -cE 'cube_cluster_(boot_)?stop' "$MAIN/bootstrap_cube_config")" "0"
chk "boot stop helper removed" "$(grep -c '^cube_cluster_boot_stop()' "$MAIN/proj_functions")" "0"

extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
body=$(extract "$MAIN/proj_functions" cube_cluster_stop)
chk "operator stop kept" "$([ -n "$body" ] && echo y)" "y"
chk "operator stop arms galera bootstrap" "$(grep -c 'touch /etc/appliance/state/mysql_new_cluster' <<<"$body")" "1"
chk "operator stop resets rabbitmq" "$(grep -c 'rm -f /etc/appliance/state/rabbitmq_cluster_done' <<<"$body")" "1"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
