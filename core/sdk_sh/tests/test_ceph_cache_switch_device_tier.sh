#!/bin/bash
#
# Unit test for the device tier guard in ../modules/sdk_ceph.sh:
#   ceph_osd_disable_cache / ceph_osd_create_cache -- the two symmetric sweeps
#   that rewrite crush_rule on every pool they do not recognize must leave a
#   pool named in the cinder.storage.tier.%d.name registry alone (#840).
#
# Without the guard a device tier pool -- whose name the operator chooses, so it
# matches none of the *-pool / *-cache / *-ssd suffixes in the skip list -- gets
# pinned to rule-hdd by `cache switch on` and reset to replicated_rule by
# `cache switch off`, both silently, which permanently destroys its placement.
#
# Self-contained: extracts just those functions plus their two registry helpers,
# stubs ceph / rados / Quiet, so it needs no cluster.
#   Run: bash test_ceph_cache_switch_device_tier.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_osd_disable_cache ceph_osd_create_cache \
         _ceph_device_tier_registry _ceph_device_tier_is_registered ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

# constants the extracted functions read, copied from the top of sdk_ceph.sh /
# modules.pre/sdk_01-var-static.sh
BUILTIN_BACKPOOL=cinder-volumes
BUILTIN_CACHEPOOL=cachepool

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SETTINGS_TXT="$TMP/settings.txt"

# The pool set every case runs against: one device tier (gold), one legacy node
# group triplet, the built-in cache path, an EC pool, and cephfs_metadata.
POOLS='cinder-volumes
cachepool
cephfs_metadata
glance-images
gold
grp1-pool
grp1-cache
grp1-ssd
default.rgw.buckets.data.ec'

# ceph stub. Records every mutating call in $TRACE and answers the reads the two
# functions make. crush_rule state lives in $TMP/rule.<pool> so a set is visible
# to the get that follows it, which is what both sweeps branch on.
fake_ceph() {
    case "$*" in
        'osd pool ls')
            printf '%s\n' "$POOLS" ;;
        'osd crush rule list'|'osd crush rule ls')
            printf '%s\n' "$RULES" ;;
        'osd pool get '*' erasure_code_profile')
            # only the EC pool has one; everything else is replicated, and the
            # sweeps read a non-zero here as "replicated, carry on"
            [ "$4" = default.rgw.buckets.data.ec ] || return 1
            echo "erasure_code_profile: default" ;;
        'osd pool get '*' crush_rule')
            echo "crush_rule: $(cat "$TMP/rule.$4" 2>/dev/null || echo replicated_rule)" ;;
        'osd pool set '*' crush_rule '*)
            echo "SET $4 -> $6" >> "$TRACE"
            echo "$6" > "$TMP/rule.$4" ;;
        'osd tier remove '*)
            rm -f "$TMP/overlay.$4"
            echo "OTHER $*" >> "$TRACE" ;;
        *)
            echo "OTHER $*" >> "$TRACE" ;;
    esac
    return 0
}
CEPH=fake_ceph
RULES='replicated_rule rule-ssd rule-hdd gold'

# The rest of what the two functions reach for. None of it is under test here --
# these cases are about which pools the sweeps touch.
Quiet() { [ "${1:-}" = -n ] && shift; "$@"; }
rados() { return 0; }
ceph_get_cache_by_backpool() {
    case "${1:-$BUILTIN_BACKPOOL}" in
        "$BUILTIN_BACKPOOL") echo "$BUILTIN_CACHEPOOL" ;;
        grp1-pool)           echo grp1-cache ;;
    esac
}
# "on" only for a pool that still has its overlay -- which is what decides
# whether the switch-off sweep rewrites a pool's crush_rule, and which the
# `osd tier remove` above clears part way through ceph_osd_disable_cache.
ceph_osd_test_cache() {
    local b=${1:-$BUILTIN_BACKPOOL}
    [ -n "$(ceph_get_cache_by_backpool "$b")" ] || { echo -n off; return 1; }
    [ -f "$TMP/overlay.$b" ] && echo -n on || echo -n off
}
ceph_osd_enable_cache() { echo "OTHER enable_cache $*" >> "$TRACE"; return 0; }

registry() { # write the given names into the registry as hex_translate would
    : > "$SETTINGS_TXT"
    echo 'cinder.enabled = true' >> "$SETTINGS_TXT"
    local i=0
    for n in "$@" ; do
        echo "cinder.storage.tier.$i.name = $n" >> "$SETTINGS_TXT"
        i=$((i+1))
    done
}

run() { # $1 = create|disable ; sets TRACE contents in $OUT and rc in $RC
    TRACE="$TMP/trace"; : > "$TRACE"
    rm -f "$TMP"/rule.*
    local p
    while read -r p ; do [ -n "$p" ] && echo "$INITIAL_RULE" > "$TMP/rule.$p" ; done <<< "$POOLS"
    echo gold > "$TMP/rule.gold"          # the tier pool is bound to its own rule
    rm -f "$TMP"/overlay.*
    touch "$TMP/overlay.$BUILTIN_BACKPOOL" "$TMP/overlay.grp1-pool"
    if [ "$1" = create ] ; then
        ceph_osd_create_cache "$BUILTIN_BACKPOOL" >/dev/null 2>&1
    else
        ceph_osd_disable_cache "$BUILTIN_BACKPOOL" >/dev/null 2>&1
    fi
    RC=$?
    OUT=$(cat "$TRACE")
}
INITIAL_RULE=replicated_rule

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# ---- 1. registry with a device tier: both sweeps skip it ----
registry gold
run create
ck "$RC" 0 "switch on: rc 0"
ck "$(grep -c '^SET gold ' <<< "$OUT")" 0 "switch on leaves the device tier pool alone"
ck "$(cat "$TMP/rule.gold")" gold "switch on: gold still bound to rule gold"
ck "$(grep -c '^SET glance-images -> rule-hdd' <<< "$OUT")" 1 "switch on still pins an ordinary pool"

run disable
ck "$RC" 0 "switch off: rc 0"
ck "$(grep -c '^SET gold ' <<< "$OUT")" 0 "switch off leaves the device tier pool alone"
ck "$(cat "$TMP/rule.gold")" gold "switch off: gold still bound to rule gold"

# ---- 2. the legacy skip list is untouched (regression) ----
# Every pool the sweeps skipped before must still be skipped, and the EC arm
# must still hold -- ak-coscp51p has a real EC pool behind it.
for case in create disable ; do
    run $case
    ck "$(grep -c '^SET grp1-pool ' <<< "$OUT")" 0 "$case: *-pool skipped"
    ck "$(grep -c '^SET grp1-cache ' <<< "$OUT")" 0 "$case: *-cache skipped"
    ck "$(grep -c '^SET grp1-ssd ' <<< "$OUT")" 0 "$case: *-ssd skipped"
    ck "$(grep -c '^SET default.rgw.buckets.data.ec ' <<< "$OUT")" 0 "$case: EC pool skipped"
done
run create
ck "$(grep -c '^SET cephfs_metadata -> rule-hdd' <<< "$OUT")" 0 "switch on: cephfs_metadata not swept to rule-hdd"
ck "$(grep -c '^SET cachepool -> rule-hdd' <<< "$OUT")" 0 "switch on: \$BUILTIN_CACHEPOOL not swept to rule-hdd"

# ---- 3. an empty registry behaves exactly as before the guard existed ----
# The device tier pool is meant to be swept when nobody registered it: that is
# the pre-#840 behaviour and the guard must not widen it.
registry ''
run create
ck "$RC" 0 "empty registry: switch on rc 0"
ck "$(grep -c '^SET gold -> rule-hdd' <<< "$OUT")" 1 "empty registry: an unregistered pool is still swept"
: > "$SETTINGS_TXT"
run disable
ck "$(grep -c '^SET gold -> replicated_rule' <<< "$OUT")" 1 "no registry key at all: reads as zero device tiers, sweep unchanged"

# ---- 4. an unreadable registry stops before the first mutation ----
# "cannot tell" is not "there are none": acting on the wrong one is what
# destroys a tier, and neither function can be resumed from the middle.
rm -f "$SETTINGS_TXT"
for case in create disable ; do
    run $case
    ck "$RC" 1 "$case: unreadable registry returns non-zero"
    ck "$(grep -c '^SET ' <<< "$OUT")" 0 "$case: unreadable registry mutates nothing"
    ck "$(grep -c 'enable_cache' <<< "$OUT")" 0 "$case: unreadable registry does not even enable the cache"
done

# ---- 5. a registry entry is matched literally, never as a shell pattern ----
# config_cinder.cpp vets these names, but the policy chain and
# `hex_config commit <settings>` write the array without going through the CLI,
# so a "*" reaching here must skip nothing rather than every pool.
registry '*'
run create
ck "$(grep -c '^SET glance-images -> rule-hdd' <<< "$OUT")" 1 "a '*' entry does not skip every pool"
ck "$(grep -c '^SET gold -> rule-hdd' <<< "$OUT")" 1 "a '*' entry does not skip the tier pool either"

# ---- 6. registry parsing ----
registry gold silver
ck "$(_ceph_device_tier_registry | tr '\n' ',')" "gold,silver," "both entries, in index order"
printf 'cinder.storage.tier.0.name =  gold  \ncinder.storage.tier.1.name =\n' > "$SETTINGS_TXT"
ck "$(_ceph_device_tier_registry | tr '\n' ',')" "gold," "surrounding blanks trimmed, empty entry dropped"
printf 'cinder.storage.backend.0.name = ext1\ncinder.storage.tier.10.name = t10\n' > "$SETTINGS_TXT"
ck "$(_ceph_device_tier_registry | tr '\n' ',')" "t10," "the backend array is a different key; index is not one digit"
_ceph_device_tier_registry >/dev/null ; ck "$?" 0 "a readable registry returns 0"
rm -f "$SETTINGS_TXT"
_ceph_device_tier_registry >/dev/null 2>&1 ; ck "$?" 1 "a missing registry returns non-zero"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: cache switch device tier guard"; exit 0; } || exit 1
