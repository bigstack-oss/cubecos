#!/bin/bash
#
# Unit test for migrate_skyline_db in ../modules/sdk_migrate.sh.
# config_skyline.cpp upgrades skyline's schema only when it creates the database, so an
# upgraded cluster relies on this migration to reach a new release's head. The marker
# must record an upgrade that succeeded, never one that failed: a failed upgrade leaves
# no marker (the next Commit() retries it) and still returns 0 (one service's migration
# must not fail config_skyline's Commit() or the modules after it). Compute nodes never
# upgrade.
#
# Self-contained: extracts just this function, points its venv at a mock alembic and
# mocks is_control_node, so it needs no cluster and no database.
# Run: bash test_migrate_skyline_db_marker.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_migrate.sh"

T=$(mktemp -d)
LOG=$T/log
mkdir -p $T/venv/bin
cat > $T/venv/bin/alembic <<MOCK
#!/bin/bash
echo "alembic \$*" >> $LOG
exit \$(cat $T/rc)
MOCK
chmod +x $T/venv/bin/alembic

body="$(awk '/^migrate_skyline_db\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: migrate_skyline_db not extracted"; exit 1; }
eval "${body//\/opt\/openstack-epoxy/$T/venv}"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
upgrades(){ grep -c 'upgrade head' "$LOG" ; }
marked(){ [ -f "$STATE_DIR/skyline_db_migrated" ] && echo y || echo n; }

ROLE=control
is_control_node(){ [ "$ROLE" = control ] ; }
STATE_DIR=$T/state; mkdir -p $STATE_DIR

reset(){ : > "$LOG" ; rm -f "$STATE_DIR/skyline_db_migrated" ; ROLE=$1 ; echo $2 > $T/rc ; }

# 1. control node, upgrade succeeds: marked, and the next call does not upgrade again
reset control 0
migrate_skyline_db ; rc=$?
chk "1 rc"                 "$rc"          "0"
chk "1 upgraded once"      "$(upgrades)"  "1"
chk "1 marked"             "$(marked)"    "y"
chk "1 skyline's alembic.ini" "$(grep -c -- "-c $T/venv/lib/python3.12/site-packages/skyline_apiserver/db/alembic/alembic.ini upgrade head" "$LOG")" "1"
migrate_skyline_db
chk "1 no re-upgrade"      "$(upgrades)"  "1"

# 2. control node, upgrade fails: not marked, still rc 0, and the next call retries
reset control 1
migrate_skyline_db ; rc=$?
chk "2 rc"                 "$rc"          "0"
chk "2 not marked"         "$(marked)"    "n"
migrate_skyline_db
chk "2 retried"            "$(upgrades)"  "2"
echo 0 > $T/rc
migrate_skyline_db
chk "2 marked once it succeeds" "$(marked)" "y"

# 3. compute node: marked without ever upgrading, even if an upgrade would fail
reset compute 1
migrate_skyline_db ; rc=$?
chk "3 rc"                 "$rc"          "0"
chk "3 no upgrade"         "$(upgrades)"  "0"
chk "3 marked"             "$(marked)"    "y"

rm -rf "$T" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: migrate_skyline_db marker" ; exit 0 ; } || exit 1
