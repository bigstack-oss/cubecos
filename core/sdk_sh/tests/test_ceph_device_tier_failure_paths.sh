#!/bin/bash
#
# Unit test for the failure reporting in ../modules/sdk_ceph.sh:
#   ceph_device_tier_delete -- must not report a clean delete when the CRUSH
#                              rule removal or any device class removal did not
#                              actually happen (#840 R6)
#   ceph_device_tier_update -- must not report success when ceph_adjust_pool_size
#                              set size but left min_size at its old value,
#                              which is the half that decides whether the pool
#                              still accepts writes with a host down (#840 R7)
#
# Both functions drive Ceph through commands that swallow their own failures, so
# the property under test is that each step is checked and then confirmed by
# reading the result back -- not that the happy path works.
#
# Self-contained: extracts just those two functions and their helpers, stubs
# ceph / openstack / hex_sdk / Quiet, so it needs no cluster.
#   Run: bash test_ceph_device_tier_failure_paths.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_device_tier_delete ceph_device_tier_update \
         _ceph_device_tier_has_rule _ceph_device_tier_has_class \
         _ceph_device_tier_rule_state \
         _ceph_device_tier_rule_users _ceph_device_tier_class_of_osd ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The real Quiet (hex/scripts/functions) returns the command's status, EXCEPT
# with -n, which forces 0. Reproducing that exactly is the point: a check
# written as `Quiet -n cmd || handler` is dead code, and this suite would not
# notice if the module regressed to it.
Quiet() {
    if [ "${1:-}" = -n ] ; then shift; "$@" >/dev/null 2>&1; return 0; fi
    "$@" >/dev/null 2>&1
}

# ---- cluster model -------------------------------------------------------
# CLASSES  : "<osd id>:<class>" per line, the authority for both class queries
# RULES    : one rule name per line
# POOLS    : one pool name per line
# FAIL_PAT : a regex; any ceph command matching it fails and changes nothing
# CEPH_DEAD: 1 makes every read fail, standing in for an unreachable cluster
# RULE_LS_DEAD_AFTER_RM: 1 makes `osd crush rule ls` fail from the moment a
#            rule rm has been attempted. Failing it outright would abort the
#            delete at its own up-front read instead of at the readback, and
#            counting calls would break the moment the module reads the list
#            one more time -- arming it on the rm names the state under test
#            ("the readback is unavailable") rather than a call index.
# RM_LIES  : 1 makes `osd crush rule rm` remove the rule and still return
#            non-zero, the one shape a readback alone cannot object to
# LSOSD_DEAD: 1 makes `osd crush class ls-osd` fail, standing in for a
#            membership query that cannot be answered
# CLASS_LS_GARBAGE: 1 makes `osd crush class ls` exit 0 with output jq cannot
#            parse -- a read that succeeded and still answered nothing
# SETCLASS_LIES: 1 makes `osd crush set-device-class` return 0 without moving
#            the OSD, the shape only a membership readback can object to
reset_cluster() {
    printf '2:gold\n6:gold\n10:gold\n' > "$TMP/classes"
    printf 'replicated_rule\ngold\n' > "$TMP/rules"
    printf 'cinder-volumes\ngold\n' > "$TMP/pools"
    printf 'gold:3:2\ncinder-volumes:3:2\n' > "$TMP/poolattr"   # name:size:min_size
    printf 'gold\nCubeStorage\n' > "$TMP/vtypes"
    printf 'cinder-volumes:replicated_rule\ngold:gold\n' > "$TMP/poolrule"
    FAIL_PAT='^$'
    CEPH_DEAD=0
    RULE_LS_DEAD_AFTER_RM=0
    RM_LIES=0
    RM_ATTEMPTED=0
    LSOSD_DEAD=0
    CLASS_LS_GARBAGE=0
    SETCLASS_LIES=0
}

classes_json() { awk -F: '{print $2}' "$TMP/classes" | sort -u | jq -R . | jq -s .; }

fake_ceph() {
    [ "$CEPH_DEAD" = 1 ] && return 1
    local all="$*"
    case "$all" in
        'osd crush class ls')
            [ "$CLASS_LS_GARBAGE" = 1 ] && { printf 'Error EPERM: mon down\n'; return 0; }
            classes_json ;;
        'osd crush class ls-osd '*)
            [ "$LSOSD_DEAD" = 1 ] && return 1
            local c=${all##* }
            grep ":$c\$" "$TMP/classes" >/dev/null || return 1
            awk -F: -v c="$c" '$2==c{print $1}' "$TMP/classes" ;;
        'osd crush rule ls')
            [ "$RULE_LS_DEAD_AFTER_RM" = 1 ] && [ "$RM_ATTEMPTED" = 1 ] && return 1
            cat "$TMP/rules" ;;
        'osd pool ls')             cat "$TMP/pools" ;;
        'osd crush rule rm '*)
            RM_ATTEMPTED=1
            echo "$all" | grep -qE "$FAIL_PAT" && return 1
            local r=${all##* }; grep -vx "$r" "$TMP/rules" > "$TMP/x"; mv "$TMP/x" "$TMP/rules"
            [ "$RM_LIES" = 1 ] && return 1 ;;
        'osd crush rm-device-class '*)
            echo "$all" | grep -qE "$FAIL_PAT" && return 1
            local o=${all##*osd.}; grep -v "^$o:" "$TMP/classes" > "$TMP/x"; mv "$TMP/x" "$TMP/classes" ;;
        'osd crush set-device-class '*)
            # $4 = class, $5 = osd.N. A no-op stub here would make every
            # membership readback assert nothing: the model would never show the
            # OSD arriving, so the check could not tell a working set-device-class
            # from one that silently did nothing.
            [ "$SETCLASS_LIES" = 1 ] && return 0
            local nc=$4 no=${5#osd.}
            grep -v "^$no:" "$TMP/classes" > "$TMP/x"; mv "$TMP/x" "$TMP/classes"
            echo "$no:$nc" >> "$TMP/classes" ;;
        'osd pool delete '*)
            grep -vx "$4" "$TMP/pools" > "$TMP/x"; mv "$TMP/x" "$TMP/pools"
            grep -v "^$4:" "$TMP/poolrule" > "$TMP/x"; mv "$TMP/x" "$TMP/poolrule" ;;
        'osd crush rule dump '*)
            local rid=$(grep -nx "$5" "$TMP/rules" | cut -d: -f1)
            [ -n "$rid" ] || return 1
            echo "{\"rule_id\": $((rid - 1))}" ;;
        'osd pool ls detail -f json')
            awk -F: -v R="$TMP/rules" '
              BEGIN{ n=0; while((getline l < R)>0){ id[l]=n; n++ }; printf "[" }
              { printf "%s{\"pool_name\":\"%s\",\"crush_rule\":%d}", (c++?",":""), $1, id[$2] }
              END{ printf "]\n" }' "$TMP/poolrule" ;;
        'osd pool get '*' size -f json')
            awk -F: -v p="$(echo "$all" | awk '{print $4}')" '$1==p{printf "{\"size\":%s}\n",$2}' "$TMP/poolattr" ;;
        'osd pool get '*' min_size -f json')
            awk -F: -v p="$(echo "$all" | awk '{print $4}')" '$1==p{printf "{\"min_size\":%s}\n",$3}' "$TMP/poolattr" ;;
        'osd out '*|'osd in '*|'-s') : ;;
        *) : ;;
    esac
    return 0
}
CEPH=fake_ceph

# openstack: a stateful volume type catalog with no volumes on it. The delete
# path polls the catalog for the type to disappear, so a stub that always
# answers the same thing would make every run take the full 15 s timeout and
# then fail for the wrong reason.
fake_openstack() {
    case "$*" in
        *'volume type delete'*)
            # $4, not ${*##* }: on "$*" the ## operator applies to each
            # positional parameter, so it hands back the whole command line
            grep -vx "$4" "$TMP/vtypes" > "$TMP/x"; mv "$TMP/x" "$TMP/vtypes" ;;
        *'volume type list'*) cat "$TMP/vtypes" ;;
        *'volume list'*)      echo '[]' ;;
    esac
    return 0
}
OPENSTACK=fake_openstack
# hex_sdk cinder_is_volume_type_in_use: non-zero == not in use
fake_sdk() { return 1; }
HEX_SDK=fake_sdk

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
ckhas() { case "$1" in *"$2"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: $3 -> output lacks '$2'";; esac; }

# ==== R6 =================================================================

# ---- 6a. happy path: everything goes, clean delete reported ----
reset_cluster
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 0 "6a delete succeeds when every step takes effect"
ckhas "$OUT" "left with no device class" "6a reports the clean delete"
ck "$(wc -l < "$TMP/classes" | tr -d ' ')" 0 "6a every OSD lost the class"
ck "$(grep -cx gold "$TMP/rules")" 0 "6a the rule is gone"

# ---- 6b. the rule removal fails: the class must survive ----
# Stripping the class while the rule stands leaves that rule selecting nothing,
# and every pool bound to it goes dark -- the exact outage the module refuses
# elsewhere, reachable here only because the rm was unchecked.
reset_cluster
FAIL_PAT='rule rm'
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6b rule rm failure returns non-zero"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "6b every OSD kept the class"
ck "$(grep -cx gold "$TMP/rules")" 1 "6b the rule is still there"
ckhas "$OUT" "did not take effect" "6b says why the class was kept"
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6b must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6c. one of the three class removals fails ----
reset_cluster
FAIL_PAT='rm-device-class osd\.6$'
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6c partial class removal returns non-zero"
ckhas "$OUT" "osd.6" "6c names the OSD that kept the class"
ck "$(cat "$TMP/classes")" "6:gold" "6c only the failed OSD kept it"
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6c must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6d. the rule is still used by another pool: unchanged behaviour ----
# The real helper is driven through the model here rather than overridden, so
# this also covers the query it makes.
reset_cluster
printf 'cinder-volumes\ngold\nsomeone-else\n' > "$TMP/pools"
printf 'gold:3:2\ncinder-volumes:3:2\nsomeone-else:3:2\n' > "$TMP/poolattr"
printf 'cinder-volumes:replicated_rule\ngold:gold\nsomeone-else:gold\n' > "$TMP/poolrule"
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6d a shared rule still returns non-zero"
ckhas "$OUT" "still selects through that rule" "6d keeps the pre-existing reason"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "6d the class survives with the rule"
ck "$(grep -cx gold "$TMP/rules")" 1 "6d the shared rule is not removed"

# ---- 6e. the rule removal fails AND the readback is unavailable ----
# The pair is the point. An existence check written as a pipeline answers
# non-zero to "not there" and to "the mon did not answer" alike, so a delete
# that trusts it strips every device class exactly when it knows least.
reset_cluster
FAIL_PAT='rule rm'
RULE_LS_DEAD_AFTER_RM=1
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6e unreadable readback after a failed rm returns non-zero"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "6e every OSD kept the class"
ck "$(grep -cx gold "$TMP/rules")" 1 "6e the rule is still there"
ckhas "$OUT" "cannot be confirmed that the rule went" "6e reports unknown, not removed"
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6e must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6f. the rule removal returns 0 AND the readback is unavailable ----
# Same unknown, reached the other way: nothing here proves the rm took effect,
# so the class that makes the rule work has to stay until something does.
reset_cluster
RULE_LS_DEAD_AFTER_RM=1
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6f unreadable readback after a clean rm returns non-zero"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "6f every OSD kept the class"
ckhas "$OUT" "cannot be confirmed that the rule went" "6f reports unknown, not removed"
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6f must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6g. the rm removes the rule and still reports failure ----
# The readback alone cannot object to this one -- the rule really is gone --
# but an rm whose status disagrees with its effect is not understood, and the
# device class is the half that can still be put back by hand. The report has
# to stay accurate: the rule did NOT keep the class here.
reset_cluster
RM_LIES=1
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6g a failing rm that took effect still returns non-zero"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "6g every OSD kept the class"
ck "$(grep -cx gold "$TMP/rules")" 0 "6g the rule really did go"
ckhas "$OUT" "reported a failure" "6g says the rm disagreed with itself"
case "$OUT" in *"the CRUSH rule and osd"*) fail=$((fail+1)); echo "FAIL: 6g must not claim the rule kept the class";; *) pass=$((pass+1));; esac
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6g must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6i. the class list reads back as exit 0 with unparseable output ----
# The rc half of this read is already fail-closed; the parse half is the other
# half of the same answer. `ceph` exiting 0 with something jq cannot read is an
# answer nobody got, and letting it fall through the grep reports a clean delete
# on the strength of it.
reset_cluster
CLASS_LS_GARBAGE=1
OUT=$(ceph_device_tier_delete gold 2>&1); RC=$?
ck "$RC" 1 "6i unparseable class list returns non-zero"
ckhas "$OUT" "could not be read" "6i reports unknown, not gone"
case "$OUT" in *"left with no device class"*) fail=$((fail+1)); echo "FAIL: 6i must not claim a clean delete";; *) pass=$((pass+1));; esac

# ---- 6h. the tri-state helper itself ----
# present / absent / unreadable have to be three answers, not two: this is the
# distinction the whole of 6e and 6f rests on.
reset_cluster
_ceph_device_tier_rule_state gold          ; ck "$?" 0 "6h present -> 0"
_ceph_device_tier_rule_state no-such-rule  ; ck "$?" 1 "6h read and absent -> 1"
CEPH_DEAD=1
_ceph_device_tier_rule_state gold          ; ck "$?" 2 "6h unreadable -> 2"
_ceph_device_tier_rule_state no-such-rule  ; ck "$?" 2 "6h unreadable is never absent"
reset_cluster

# ==== R7 =================================================================
# ceph_adjust_pool_size sets the pair (size, min_size = max(1, size - 1)) and
# swallows its own failures, so a pool that took one and not the other is the
# case that has to be caught.
# The membership asked for has to differ from what the model holds: an update
# that changes nothing short-circuits with "already consists of" and never
# reaches the resize, so a test that passes the current members would assert
# nothing at all.
run_update() {  # $1 = size in the model, $2 = min_size in the model
    # The membership is reset too, not just the pool attributes: set-device-class
    # really moves the OSD in the model, so without this the second call onwards
    # would find nothing to do, short-circuit on "already consists of", and never
    # reach the resize the assertion is about -- the trap named just above.
    printf '2:gold\n6:gold\n10:gold\n' > "$TMP/classes"
    printf 'gold:%s:%s\ncinder-volumes:3:2\n' "$1" "$2" > "$TMP/poolattr"
    UOUT=$(ceph_device_tier_update gold 2 6 10 3 2>&1); URC=$?
}
reset_cluster
_ceph_device_tier_target_pool_size() { echo 3; }
_ceph_device_tier_wait_recovery() { return 0; }
_ceph_device_tier_health_ok() { return 0; }
_ceph_device_tier_osd_ids() { for a in "$@" ; do echo "${a#osd.}" ; done ; }
_ceph_device_tier_class_of_osd() { echo gold; }
ceph_adjust_pool_size() { return 0; }

run_update 3 2
ck "$URC" 0 "7a both halves at target -> success"

run_update 3 1
ck "$URC" 1 "7b size right, min_size stale -> non-zero"
ckhas "$UOUT" "min_size is 1, expected 2" "7b prints actual and expected"

run_update 2 2
ck "$URC" 1 "7c size wrong -> non-zero (unchanged behaviour)"
ckhas "$UOUT" "size is 2, expected 3" "7c prints actual and expected"

# min_size floors at 1, so a single-replica tier must not demand 0
_ceph_device_tier_target_pool_size() { echo 1; }
run_update 1 1
ck "$URC" 0 "7d size 1 expects min_size 1, not 0"
run_update 1 2
ck "$URC" 1 "7d' size 1 with min_size 2 is still caught"

# ---- 7e. the membership query cannot be answered ----
# An empty `have` is not an empty tier: every requested OSD becomes an addition,
# so members already in the tier get taken out and re-added (which moves data),
# every existing member missing from the request stays in, and the success line
# is a statement about a set nobody read.
reset_cluster
LSOSD_DEAD=1
UOUT=$(ceph_device_tier_update gold 2 6 10 3 2>&1); URC=$?
ck "$URC" 1 "7e unreadable membership returns non-zero"
ckhas "$UOUT" "cannot read the members" "7e says why it refused"
ck "$(sort "$TMP/classes" | tr '\n' ',')" "10:gold,2:gold,6:gold," "7e nothing was changed"
case "$UOUT" in *"now consists of"*) fail=$((fail+1)); echo "FAIL: 7e must not claim the membership changed";; *) pass=$((pass+1));; esac

# ---- 7f. set-device-class returns 0 without moving the OSD ----
# Every step returned 0, so only reading the membership back can object.
reset_cluster
_ceph_device_tier_target_pool_size() { echo 3; }
SETCLASS_LIES=1
UOUT=$(ceph_device_tier_update gold 2 6 10 3 2>&1); URC=$?
ck "$URC" 1 "7f a silent set-device-class is caught by the readback"
ckhas "$UOUT" "not the requested" "7f prints actual and requested"
case "$UOUT" in *"now consists of 2 6 10 3"*) fail=$((fail+1)); echo "FAIL: 7f must not claim success";; *) pass=$((pass+1));; esac

# ---- 7g. the readback itself cannot be answered ----
reset_cluster
_ceph_device_tier_target_pool_size() { echo 3; }
_ceph_device_tier_wait_recovery() { LSOSD_DEAD=1 ; return 0 ; }
UOUT=$(ceph_device_tier_update gold 2 6 10 3 2>&1); URC=$?
ck "$URC" 1 "7g unreadable readback returns non-zero"
ckhas "$UOUT" "could not be" "7g reports unknown"
_ceph_device_tier_wait_recovery() { return 0; }

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: device tier delete/update failure reporting"; exit 0; } || exit 1
