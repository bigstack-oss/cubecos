#!/bin/bash
#
# Unit test for cinder_wait_for_backends_ready (../modules/sdk_cinder.sh), the
# check config_cinder.cpp fails a commit on when a backend it added is not up
# (#2099). A backend counts only when its cinder-volume service is listed and
# up and it reports a pool (its driver initialized); the bound is wall clock.
# Part B shows the old wait, cinder_wait_for_services_up, passing the same
# broken backends. openstack and the clock are faked; needs no cluster.
#   Run: bash test_cinder_wait_for_backends_ready.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

extract() {  # <file> <function>
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    eval "$body"
    [ "$(type -t "$2")" = function ]
}
for f in cinder_wait_for_backends_ready cinder_wait_for_backends_gone cinder_wait_for_services_up cinder_are_services_up cinder_is_all_true ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
for f in _hex_function _hex_function_ret ; do
    extract "$DIR/../../main/proj_functions" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_is.sh" is_valid_json || { echo "FAIL: is_valid_json not extracted"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# each pass costs the sleep plus ~3s of openstack calls
sleep() { SECONDS=$((SECONDS + $1 + 3)); }
svc() { printf '{"Binary":"%s","Host":"%s","State":"%s"}' "$1" "$2" "$3"; }
BASE="$(svc cinder-scheduler cc1 up),$(svc cinder-backup cc1 up),$(svc cinder-volume cube@ceph up)"
services() { echo "[$BASE]"; }
pools() { echo "cube@ceph#cinder-volumes"; }
fake_os() {
    case "$*" in
        "volume service list"*) services ;;
        "volume backend pool list"*) pools ;;
        *) return 1 ;;
    esac
}
OPENSTACK=fake_os

# ==== A: cinder_wait_for_backends_ready ====

# A1: up and reporting a pool -> 0 at once, prints nothing
services() { echo "[$BASE,$(svc cinder-volume ext1@ext1 up)]"; }
pools() { printf 'cube@ceph#cinder-volumes\next1@ext1#ext1\n'; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 60)"; RC=$?
chk "A1 ready" "$RC" 0
chk "A1 prints nothing" "$OUT" ""

# A2: never registered (config only on a node not running cinder-volume)
services() { echo "[$BASE]"; }
pools() { echo "cube@ceph#cinder-volumes"; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready cube@qatier 60; echo " rc=$? t=$SECONDS")"
chk "A2 names the backend, fails" "${OUT% t=*}" "cube@qatier rc=1"
T=${OUT##*t=}
chk "A2 waits out ~60s of wall clock" "$([ "$T" -ge 60 ] && [ "$T" -lt 70 ] && echo yes || echo "no ($T)")" yes

# A3: service up but no pool (driver init failed, e.g. a missing rbd_pool)
services() { echo "[$BASE,$(svc cinder-volume ext1@ext1 up)]"; }
pools() { echo "cube@ceph#cinder-volumes"; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 60)"; RC=$?
chk "A3 no pool fails" "$RC" 1
chk "A3 names it" "$OUT" "ext1@ext1"

# A4: service listed but down
services() { echo "[$BASE,$(svc cinder-volume ext1@ext1 down)]"; }
pools() { printf 'ext1@ext1#ext1\n'; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 30)"; RC=$?
chk "A4 down fails" "$RC" 1

# A5: comes up after ~20s -> returns then, not at the deadline
services() { [ $SECONDS -ge 20 ] && echo "[$BASE,$(svc cinder-volume ext1@ext1 up)]" || echo "[$BASE]"; }
pools() { [ $SECONDS -ge 20 ] && echo "ext1@ext1#p" ; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 60; echo " rc=$? t=$SECONDS")"
chk "A5 late backend succeeds" "${OUT% t=*}" " rc=0"
T=${OUT##*t=}
chk "A5 returns when ready" "$([ "$T" -ge 20 ] && [ "$T" -lt 30 ] && echo yes || echo "no ($T)")" yes

# A6: two added, one good -> only the bad one is named
services() { echo "[$BASE,$(svc cinder-volume ext1@ext1 up),$(svc cinder-volume cube@gold up)]"; }
pools() { printf 'ext1@ext1#ext1\n'; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1,cube@gold 10)"; RC=$?
chk "A6 fails" "$RC" 1
chk "A6 names only the bad one" "$OUT" "cube@gold"

# A7: a pool of a backend whose name is a prefix does not count
services() { echo "[$BASE,$(svc cinder-volume cube@gold up)]"; }
pools() { printf 'cube@gold2#gold2\n'; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready cube@gold 10)"; RC=$?
chk "A7 prefix pool is not a match" "$RC" 1

# A8: openstack unreachable -> fails, names everything
fake_os() { return 1; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 10)"; RC=$?
chk "A8 unreachable fails" "$RC" 1
chk "A8 names it" "$OUT" "ext1@ext1"

# A9: the service list unreadable while pools answer -> not up
fake_os() { case "$*" in "volume backend pool list"*) echo "ext1@ext1#ext1" ;; *) return 1 ;; esac; }
SECONDS=0
OUT="$(cinder_wait_for_backends_ready ext1@ext1 10)"; RC=$?
chk "A9 unreadable service list fails" "$RC" 1

# ==== B: the old wait passes the same broken backends ====
fake_os() {
    case "$*" in
        "volume service list"*) services ;;
        "volume backend pool list"*) pools ;;
        *) return 1 ;;
    esac
}
services() { echo "[$BASE]"; }
SECONDS=0
cinder_wait_for_services_up "cube@ceph,cube@qatier" 10 ; RC=$?
chk "B1 old wait: a never-registered backend counts as up" "$RC" 0
services() { echo "[$BASE,$(svc cinder-volume ext1@ext1 up)]"; }
pools() { echo "cube@ceph#cinder-volumes"; }
cinder_wait_for_services_up "cube@ceph,ext1@ext1" 10 ; RC=$?
chk "B2 old wait: an uninitialized driver counts as up" "$RC" 0

# ==== C: cinder_wait_for_backends_gone ====
OPENSTACK=fake_os

# C1: pool gone -> 0 at once
pools() { echo "cube@ceph#cinder-volumes"; }
SECONDS=0
OUT="$(cinder_wait_for_backends_gone ext1@ext1 60)"; RC=$?
chk "C1 gone" "$RC" 0
chk "C1 prints nothing" "$OUT" ""

# C2: pool goes after ~10 s -> waited for
pools() { [ $SECONDS -ge 10 ] && echo "cube@ceph#cinder-volumes" || printf 'cube@ceph#cinder-volumes\next1@ext1#ext1\n'; }
SECONDS=0
cinder_wait_for_backends_gone ext1@ext1 60 >/dev/null; RC=$?
chk "C2 gone after a wait" "$RC" 0
chk "C2 under the bound" "$([ $SECONDS -lt 60 ] && echo yes)" yes

# C3: still pooled -> bounded by wall clock, named; a prefix name is not a match
pools() { printf 'cube@ceph#cinder-volumes\next1@ext1#ext1\next10@ext10#ext10\n'; }
SECONDS=0
cinder_wait_for_backends_gone ext1@ext1,ext10@ext1 30 > "${TMPDIR:-/tmp}/gone.$$"; RC=$?
OUT="$(cat "${TMPDIR:-/tmp}/gone.$$")"; \rm -f "${TMPDIR:-/tmp}/gone.$$"
chk "C3 rc" "$RC" 1
chk "C3 names the pooled one only" "$OUT" "ext1@ext1"
chk "C3 bounded" "$([ $SECONDS -ge 30 ] && [ $SECONDS -lt 40 ] && echo yes)" yes

# C4: pools unreadable -> not taken as gone
fail_os() { return 1; }
OPENSTACK=fail_os
SECONDS=0
OUT="$(cinder_wait_for_backends_gone ext1@ext1 10)"; RC=$?
chk "C4 unreadable is not gone" "$RC/$OUT" "1/ext1@ext1"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
