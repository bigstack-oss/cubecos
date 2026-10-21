#!/bin/bash
#
# Unit test for the device tier guard in ../modules/sdk_ceph.sh:
#   ceph_osd_disable_cache / ceph_osd_create_cache -- the two symmetric sweeps
#   that rewrite crush_rule on every pool they do not recognize must leave a
#   device tier pool alone (#840): one named in the cinder.storage.tier.%d.name
#   registry, or one that has a device class and a CRUSH rule of its own name
#   whether or not this node's registry lists it (#2080).
#
# Without the guard a device tier pool -- whose name the operator chooses, so it
# matches none of the *-pool / *-cache / *-ssd suffixes in the skip list -- gets
# pinned to rule-hdd by `cache switch on` and reset to replicated_rule by
# `cache switch off`, both silently, which permanently destroys its placement.
#
# Self-contained: extracts just those functions plus ceph_device_tier_names and
# its two registry helpers, stubs ceph / rados / Quiet, so it needs no cluster.
#   Run: bash test_ceph_cache_switch_device_tier.sh
#   SRC=<other sdk_ceph.sh> runs the same cases against another revision.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_ceph.sh}"
for f in ceph_osd_disable_cache ceph_osd_create_cache ceph_device_tier_names \
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
# to the get that follows it, which is what both sweeps branch on. $FAIL_ON names
# one read that fails the way an unreachable mon does: no output, non-zero.
# $FAIL_SKIP lets that many of those reads through first, for a function that
# makes the same read earlier for another reason.
fake_ceph() {
    if [ "$*" = "$FAIL_ON" ] ; then
        local left
        left=$(cat "$TMP/failskip")
        [ "$left" -gt 0 ] || return 1
        echo $((left - 1)) > "$TMP/failskip"
    fi
    case "$*" in
        '-s')
            echo "health: HEALTH_OK" ;;
        'osd crush class ls')
            printf '%s\n' "$CLASSES" | jq -R . | jq -s -c . ;;
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
FAIL_ON=
# gold is a whole device tier on the Ceph side: a pool, a rule and a device
# class all called gold. Cases that need it to be only a pool and a rule take
# gold out of CLASSES.
CLASSES_ALL='hdd
ssd
gold'
CLASSES=$CLASSES_ALL
RULES='replicated_rule
rule-ssd
rule-hdd
gold'

# The rest of what the two functions reach for. None of it is under test here --
# these cases are about which pools the sweeps touch.
Quiet() { [ "${1:-}" = -n ] && shift; "$@"; }
rados() { echo "OTHER rados $*" >> "$TRACE"; return 0; }
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

run() { # $1 = create|disable ; sets TRACE contents in $OUT, output in $MSG, rc in $RC
    TRACE="$TMP/trace"; : > "$TRACE"
    echo "${FAIL_SKIP:-0}" > "$TMP/failskip"
    rm -f "$TMP"/rule.*
    local p
    while read -r p ; do [ -n "$p" ] && echo "$INITIAL_RULE" > "$TMP/rule.$p" ; done <<< "$POOLS"
    echo gold > "$TMP/rule.gold"          # the tier pool is bound to its own rule
    rm -f "$TMP"/overlay.*
    touch "$TMP/overlay.$BUILTIN_BACKPOOL" "$TMP/overlay.grp1-pool"
    # in a subshell: ceph_osd_disable_cache exits, not returns, when it cannot
    # list the pools, and that must not end this script
    if [ "$1" = create ] ; then
        MSG=$( ( ceph_osd_create_cache "$BUILTIN_BACKPOOL" ) 2>&1 )
    else
        MSG=$( ( ceph_osd_disable_cache "$BUILTIN_BACKPOOL" ) 2>&1 )
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

# A registered tier is skipped on the registry's word alone, whatever Ceph has
# left of it -- here no device class.
CLASSES='hdd
ssd'
for case in create disable ; do
    run $case
    ck "$(grep -c '^SET gold ' <<< "$OUT")" 0 "$case: registered, no device class: still skipped"
done
CLASSES=$CLASSES_ALL

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

# ---- 3. a tier this node never registered is still a tier (#2080) ----
# The registry is each control's own settings.txt, and a control can be missing
# a tier another one made. The Ceph side reads the same from every node, so a
# pool with a device class and a rule of its own name is skipped either way.
registry ''
run create
ck "$RC" 0 "empty registry: switch on rc 0"
ck "$(grep -c '^SET gold ' <<< "$OUT")" 0 "empty registry: switch on leaves a tier-shaped pool alone"
ck "$(grep -c '^SET glance-images -> rule-hdd' <<< "$OUT")" 1 "empty registry: switch on still pins an ordinary pool"
: > "$SETTINGS_TXT"
run disable
ck "$RC" 0 "no registry key at all: switch off rc 0"
ck "$(grep -c '^SET gold ' <<< "$OUT")" 0 "no registry key at all: switch off leaves a tier-shaped pool alone"

# ---- 3b. only the whole shape counts ----
# A pool and a rule of the same name with no device class behind them is not a
# device tier, and an unregistered one is swept as it always was.
CLASSES='hdd
ssd'
registry ''
run create
ck "$(grep -c '^SET gold -> rule-hdd' <<< "$OUT")" 1 "unregistered, no device class: switch on sweeps it"
run disable
ck "$(grep -c '^SET gold -> replicated_rule' <<< "$OUT")" 1 "unregistered, no device class: switch off sweeps it"
CLASSES=$CLASSES_ALL

# ---- 4. an unreadable registry stops before the first mutation ----
# "cannot tell" is not "there are none": acting on the wrong one is what
# destroys a tier, and neither function can be resumed from the middle.
# The trace has to be empty, not just free of SETs: switch off takes the
# overlay down before it sweeps, and those calls are mutations too. The message
# shows it was this read that stopped it, not an earlier check.
rm -f "$SETTINGS_TXT"
for case in create disable ; do
    run $case
    ck "$RC" 1 "$case: unreadable registry returns non-zero"
    ck "$OUT" "" "$case: unreadable registry mutates nothing"
    ck "$(grep -c 'cannot read the device tiers' <<< "$MSG")" 1 "$case: unreadable registry says why"
done

# The same holds for every Ceph list the shape is read from. Switch off lists
# the pools twice to check its own two exist before it reads the tiers, so the
# pool list has to fail on the third call to reach the read under test.
registry gold
for FAIL_ON in '-s' 'osd crush class ls' 'osd crush rule ls' 'osd pool ls' ; do
    for case in create disable ; do
        FAIL_SKIP=0
        [ "$case|$FAIL_ON" = "disable|osd pool ls" ] && FAIL_SKIP=2
        run $case
        ck "$RC" 1 "$case: '$FAIL_ON' fails: returns non-zero"
        ck "$OUT" "" "$case: '$FAIL_ON' fails: mutates nothing"
        ck "$(grep -c 'cannot read the device tiers' <<< "$MSG")" 1 "$case: '$FAIL_ON' fails: says why"
    done
done
FAIL_ON=
FAIL_SKIP=0

# ---- 5. a registry entry is matched literally, never as a shell pattern ----
# config_cinder.cpp vets these names, but the policy chain and
# `hex_config commit <settings>` write the array without going through the CLI,
# so a "*" reaching here must skip nothing rather than every pool.
# gold has no device class here, so nothing but the registry could skip it.
CLASSES='hdd
ssd'
registry '*'
run create
ck "$(grep -c '^SET glance-images -> rule-hdd' <<< "$OUT")" 1 "a '*' entry does not skip every pool"
ck "$(grep -c '^SET gold -> rule-hdd' <<< "$OUT")" 1 "a '*' entry does not skip the tier pool either"
CLASSES=$CLASSES_ALL

# A registry name can hold any byte, "|" included, and ceph_device_tier_names
# prints "state|name": only the first "|" separates them.
POOLS_ALL=$POOLS
POOLS="$POOLS
a|b"
INITIAL_RULE=elsewhere
registry 'a|b'
for case in create disable ; do
    run $case
    ck "$(grep -cF 'SET a|b ' <<< "$OUT")" 0 "$case: a registered name holding '|' is still skipped"
done
POOLS=$POOLS_ALL INITIAL_RULE=replicated_rule

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
