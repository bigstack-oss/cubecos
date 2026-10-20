#!/bin/bash
#
# Unit test for ceph_restful_bind in ../modules/sdk_ceph.sh.
#
# The restful module reads server_addr from the config db, scoped per mgr, and only
# rebinds when it restarts. The function must pin mgr.<host> to the given address, drop the
# config-key pair older releases wrote, and restart the module only when this node is
# listening on something other than <addr>:<port> -- never on a standby (no listener) or
# on a node that is already right. A failed config set must stop before anything else.
#
# Self-contained: extracts only the function and stubs ceph, ss and Quiet, so it needs no
# cluster.  Run: bash test_ceph_restful_bind.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_CEPH_SRC:-$DIR/../modules/sdk_ceph.sh}"

fn="$(awk '/^ceph_restful_bind\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: ceph_restful_bind not extracted"; exit 1; }
eval "$fn"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# LISTEN is the local address ss reports for the port ("" = no listener); SET_RC is what
# `ceph config set` returns. Every ceph and ss invocation is logged to $LOG.
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
LISTEN="" SET_RC=0

ceph_stub() {
    echo "ceph $*" >> "$LOG"
    [ "$1 $2" = "config set" ] && return $SET_RC
    return 0
}
# shellcheck disable=SC2034  # read by the eval'd function
CEPH=ceph_stub
ss() {
    echo "ss $*" >> "$LOG"
    [ -n "$LISTEN" ] && echo "LISTEN 0      5      $LISTEN      *:*"
    return 0
}
Quiet() { [ "$1" = "-n" ] && shift ; "$@" >/dev/null 2>&1 ; return 0 ; }

run() { : > "$LOG" ; ceph_restful_bind "$@" ; RC=$? ; }
has() { grep -cxF "$1" "$LOG" ; }

# 1. active mgr still on the wildcard -> pinned, old keys dropped, restarted
LISTEN="*:8003" SET_RC=0
run 10.0.0.1 h1
chk "1 rc" "$RC" 0
chk "1 set" "$(has 'ceph config set mgr.h1 mgr/restful/server_addr 10.0.0.1')" 1
chk "1 rm addr" "$(has 'ceph config-key rm mgr/restful/server_addr')" 1
chk "1 rm port" "$(has 'ceph config-key rm mgr/restful/server_port')" 1
chk "1 restart" "$(has 'ceph restful restart')" 1

# 2. already bound to the address -> no restart
LISTEN="10.0.0.1:8003"
run 10.0.0.1 h1
chk "2 rc" "$RC" 0
chk "2 set" "$(has 'ceph config set mgr.h1 mgr/restful/server_addr 10.0.0.1')" 1
chk "2 restart" "$(has 'ceph restful restart')" 0

# 3. standby, nothing listening -> pinned, no restart
LISTEN=""
run 10.0.0.2 h2
chk "3 rc" "$RC" 0
chk "3 set" "$(has 'ceph config set mgr.h2 mgr/restful/server_addr 10.0.0.2')" 1
chk "3 rm addr" "$(has 'ceph config-key rm mgr/restful/server_addr')" 1
chk "3 restart" "$(has 'ceph restful restart')" 0

# 4. bound to another address (management address changed) -> restart
LISTEN="10.0.0.9:8003"
run 10.0.0.1 h1
chk "4 restart" "$(has 'ceph restful restart')" 1

# 5. config set fails -> nonzero, nothing else touched
LISTEN="*:8003" SET_RC=1
run 10.0.0.1 h1
chk "5 rc" "$RC" 1
chk "5 rm" "$(grep -c 'config-key rm' "$LOG")" 0
chk "5 restart" "$(has 'ceph restful restart')" 0
chk "5 ss" "$(grep -c '^ss ' "$LOG")" 0
SET_RC=0

# 6. custom port -> ss asks about that port, and a match on it means no restart
LISTEN="10.0.0.1:9003"
run 10.0.0.1 h1 9003
chk "6 ss port" "$(grep -c 'sport = :9003' "$LOG")" 1
chk "6 restart" "$(has 'ceph restful restart')" 0

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
