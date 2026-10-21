#!/bin/bash
#
# Unit test for the dirty-object guard in ../modules/sdk_ceph.sh (#1436):
#   ceph_recreate_cache_pool must not delete a cache pool that still holds a
#   dirty object, and the refusal must reach the caller of `cache switch on`
#   instead of being swallowed by Quiet -n on the way up.
#
# Switch-off leaves objects a client watches in the cache pool (flushed, but
# evict returns EBUSY), so the next switch-on's `osd tier add` always fails and
# always lands in the recreate path. Clean leftovers must still be deleted --
# that is the normal path -- only a dirty one must stop it.
#
# Self-contained: extracts just those functions, stubs ceph and the helpers
# they call, so it needs no cluster.
#   Run: bash test_ceph_recreate_cache_pool_guard.sh
#   SRC=<other sdk_ceph.sh> runs the same cases against another revision.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_ceph.sh}"
for f in _ceph_pool_dirty_objects ceph_recreate_cache_pool ceph_osd_enable_cache \
         ceph_osd_create_cache ceph_device_tier_names _ceph_device_tier_registry \
         _ceph_device_tier_is_registered ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

BUILTIN_BACKPOOL=cinder-volumes
BUILTIN_CACHEPOOL=cachepool

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SETTINGS_TXT="$TMP/settings.txt"
echo 'cinder.enabled = true' > "$SETTINGS_TXT"

# Same semantics as Quiet in hex scripts/functions: output only on failure, and
# -n turns any failure into success with no output at all.
Quiet() {
    local ign=0 st=0 out=$TMP/quiet.$RANDOM
    [ "$1" = -n ] && { ign=1; shift; }
    eval "$*" >$out 2>&1 || st=$?
    [ $ign -eq 0 ] || st=0
    [ $st -eq 0 ] || cat $out >&2
    rm -f $out
    return $st
}

# ceph stub. $PGLS is what `pg ls-by-pool` prints (FAIL: exits non-zero);
# $TIERADD is how many `osd tier add` calls fail before one succeeds.
fake_ceph() {
    case "$*" in
        'pg ls-by-pool '*)
            [ "$PGLS" = FAIL ] && return 2
            printf '%s\n' "$PGLS" ;;
        'osd tier add '*)
            echo "OTHER $*" >> "$TRACE"
            [ "$(cat "$TMP/tieradd")" -gt 0 ] || return 0
            echo $(( $(cat "$TMP/tieradd") - 1 )) > "$TMP/tieradd"
            echo "Error ENOTEMPTY: tier pool '$4' is not empty; --force-nonempty to force"
            return 39 ;;
        'osd pool get '*' size')      echo "size: 3" ;;
        'osd pool get '*' pg_num -f json') echo '{"pool":"x","pg_num":32}' ;;
        'osd pool get '*' crush_rule') echo "crush_rule: replicated_rule" ;;
        'osd pool get '*' erasure_code_profile') return 1 ;;
        'osd pool ls')                printf '%s\n' cinder-volumes cachepool cephfs_metadata ;;
        'osd crush rule list'|'osd crush rule ls') printf '%s\n' replicated_rule rule-ssd rule-hdd ;;
        'osd crush class ls')         echo '["hdd","ssd"]' ;;
        '-s')                         echo "health: HEALTH_OK" ;;
        *)
            echo "OTHER $*" >> "$TRACE" ;;
    esac
    return 0
}
CEPH=fake_ceph
ceph_get_cache_by_backpool() { [ "${1:-$BUILTIN_BACKPOOL}" = "$BUILTIN_BACKPOOL" ] && echo "$BUILTIN_CACHEPOOL"; }
ceph_backpool_cache_list() { :; }
ceph_create_pool() { echo "OTHER create_pool $*" >> "$TRACE"; }
ceph_adjust_pool_size() { :; }
ceph_osd_cache_profile_set() { :; }
ceph_adjust_cache_flush_bytes() { :; }

pgls() { # one PG per argument, each with that many dirty objects
    local s='' d
    for d in "$@" ; do s="$s${s:+,}{\"pgid\":\"16.0\",\"stat_sum\":{\"num_objects\":83,\"num_objects_dirty\":$d}}" ; done
    echo "{\"pg_ready\":true,\"pg_stats\":[$s]}"
}

run() { # $1 = function, $2 = failing tier adds; sets OUT (trace), MSG (stdout+stderr), RC
    TRACE="$TMP/trace"; : > "$TRACE"
    echo "$2" > "$TMP/tieradd"
    MSG=$("$1" "$BUILTIN_BACKPOOL" 2>&1)
    RC=$?
    OUT=$(cat "$TRACE")
}

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
has() { grep -qF -- "$2" <<< "$1" && echo yes || echo no; }

# ---- 1. recreate: a dirty object anywhere in the pool stops the delete ----
PGLS=$(pgls 0 0 2 0)
run ceph_recreate_cache_pool 0
ck "$RC" 1 "recreate with 2 dirty: rc"
ck "$(has "$OUT" 'osd pool delete')" no "recreate with 2 dirty: no delete"
ck "$(has "$OUT" 'create_pool')" no "recreate with 2 dirty: no create"
ck "$(has "$MSG" '2 dirty object')" yes "recreate with 2 dirty: says why"

# ---- 2. recreate: an unreadable count fails closed ----
PGLS=FAIL
run ceph_recreate_cache_pool 0
ck "$RC" 1 "recreate, pg ls fails: rc"
ck "$(has "$OUT" 'osd pool delete')" no "recreate, pg ls fails: no delete"
PGLS='{"pg_ready":true}'
run ceph_recreate_cache_pool 0
ck "$RC" 1 "recreate, no pg_stats: rc"
ck "$(has "$OUT" 'osd pool delete')" no "recreate, no pg_stats: no delete"
PGLS='not json'
run ceph_recreate_cache_pool 0
ck "$(has "$OUT" 'osd pool delete')" no "recreate, garbage: no delete"

# ---- 3. recreate: clean leftovers (the normal switch-on path) still recreate ----
PGLS=$(pgls 0 0 0 0)
run ceph_recreate_cache_pool 0
ck "$RC" 0 "recreate, all clean: rc"
ck "$(has "$OUT" 'osd pool delete cachepool cachepool')" yes "recreate, all clean: deletes"
ck "$(has "$OUT" 'create_pool cachepool rbd')" yes "recreate, all clean: creates"

# ---- 4. enable_cache: refusal stops before the overlay goes on ----
PGLS=$(pgls 1)
run ceph_osd_enable_cache 1
ck "$RC" 1 "enable, dirty: rc"
ck "$(has "$OUT" 'osd pool delete')" no "enable, dirty: no delete"
ck "$(has "$OUT" 'set-overlay')" no "enable, dirty: no overlay"
ck "$(has "$MSG" 'dirty object')" yes "enable, dirty: refusal reaches the caller"

# ---- 5. enable_cache: tier add succeeding first time never looks at dirty ----
PGLS=FAIL
run ceph_osd_enable_cache 0
ck "$RC" 0 "enable, empty pool: rc"
ck "$(has "$OUT" 'osd pool delete')" no "enable, empty pool: no delete"
ck "$(has "$OUT" 'set-overlay cinder-volumes cachepool')" yes "enable, empty pool: overlay"

# ---- 6. enable_cache: clean leftovers recreate and carry on ----
PGLS=$(pgls 0 0)
run ceph_osd_enable_cache 1
ck "$RC" 0 "enable, clean leftovers: rc"
ck "$(has "$OUT" 'osd pool delete cachepool cachepool')" yes "enable, clean leftovers: deletes"
ck "$(has "$OUT" 'set-overlay cinder-volumes cachepool')" yes "enable, clean leftovers: overlay"

# ---- 7. create_cache (what `cache switch on` calls): failure reaches the CLI ----
PGLS=$(pgls 1)
run ceph_osd_create_cache 1
ck "$RC" 1 "create, dirty: rc"
ck "$(has "$OUT" 'osd pool delete')" no "create, dirty: no delete"
ck "$(has "$OUT" 'osd pool set')" no "create, dirty: stops before touching any pool"
ck "$(has "$MSG" 'dirty object')" yes "create, dirty: refusal printed"
PGLS=$(pgls 0)
run ceph_osd_create_cache 1
ck "$RC" 0 "create, clean leftovers: rc"
ck "$(has "$OUT" 'set-overlay cinder-volumes cachepool')" yes "create, clean leftovers: overlay"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
