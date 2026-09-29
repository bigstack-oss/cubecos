#!/bin/bash
#
# Unit test for migrate_masakari_db in ../modules/sdk_migrate.sh.
# The marker must record a db sync that succeeded, never one that failed: on the
# 3.1.10 -> 3.1.20 roll masakari 17.0.0's sync died on "Table 'failover_segments'
# already exists" and the marker was touched anyway on every control node, so the
# failure was never retried or seen. A failed sync must leave no marker (the next
# Commit() retries it) and still return 0 (one service's migration must not fail
# config_masakari's Commit() or the modules after it). Compute nodes never sync.
#
# Self-contained: extracts just this function and mocks su/is_control_node, so it
# needs no cluster and no database.  Run: bash test_migrate_masakari_db_marker.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_migrate.sh"

body="$(awk '/^migrate_masakari_db\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: migrate_masakari_db not extracted"; exit 1; }
eval "$body"

LOG=$(mktemp)
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
syncs(){ grep -c 'masakari-manage db sync' "$LOG" ; }
marked(){ [ -f "$STATE_DIR/masakari_db_migrated" ] && echo y || echo n; }

# --- mocks: record every sync attempt; its exit code is set per case.
ROLE=control SYNC_RC=0
is_control_node(){ [ "$ROLE" = control ] ; }
su(){ echo "su $*" >> "$LOG" ; return "$SYNC_RC" ; }
STATE_DIR=$(mktemp -d)

reset(){ : > "$LOG" ; rm -f "$STATE_DIR/masakari_db_migrated" ; ROLE=$1 SYNC_RC=$2 ; }

# 1. control node, sync succeeds: marked, and the next call does not sync again
reset control 0
migrate_masakari_db ; rc=$?
chk "1 rc"                 "$rc"       "0"
chk "1 synced once"        "$(syncs)"  "1"
chk "1 marked"             "$(marked)" "y"
migrate_masakari_db
chk "1 no re-sync"         "$(syncs)"  "1"

# 2. control node, sync fails: not marked, still rc 0, and the next call retries
reset control 1
migrate_masakari_db ; rc=$?
chk "2 rc"                 "$rc"       "0"
chk "2 not marked"         "$(marked)" "n"
migrate_masakari_db
chk "2 retried"            "$(syncs)"  "2"
SYNC_RC=0
migrate_masakari_db
chk "2 marked once it succeeds" "$(marked)" "y"

# 3. compute node: marked without ever syncing, even if a sync would fail
reset compute 1
migrate_masakari_db ; rc=$?
chk "3 rc"                 "$rc"       "0"
chk "3 no sync"            "$(syncs)"  "0"
chk "3 marked"             "$(marked)" "y"

rm -rf "$LOG" "$STATE_DIR" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: migrate_masakari_db marker" ; exit 0 ; } || exit 1
