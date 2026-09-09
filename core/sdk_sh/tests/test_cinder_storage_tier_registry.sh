#!/bin/bash
#
# Unit test for the write end of the device tier registry in
# ../modules/sdk_cinder.sh (#840 WP-5):
#   cinder_apply_storage_tier_creation -- puts a name into the tiers: sequence
#                                         the Cinder backend is generated from,
#                                         exactly once, and applies only when
#                                         something changed
#   cinder_apply_storage_tier_deletion -- takes it out, keeps the blank child
#                                         the yml parser needs when the list
#                                         empties, and leaves the policy alone
#                                         when the name was never there
#
# Why the "only when something changed" half is a property and not a nicety:
# $HEX_CFG apply restarts Cinder. A create that is a no-op, or a delete of a
# tier that was never registered, must not bounce volume service.
#
# WHAT THIS DOES NOT COVER: yq itself. The stub below stores the policy as
# JSON and answers the expression shapes these two functions use, so what is
# under test is their decisions -- which index gets written, whether apply is
# reached, what happens when a read fails -- not YAML round-tripping.
#
# One consequence is worth naming, because it cost a deploy cycle: the reason
# the deletion path edits in place instead of round-tripping the document
# through JSON (the way cinder_apply_storage_deletion does for backends) is
# that the round trip rewrites unrelated keys. Measured on the 1cc, not here:
# `version: 1.0` came back as `version: 1`, and the blank placeholder
# `- name:` came back as `- name: null`, which HexYmlParseString reads as the
# string "null" -- putting a backend called null into enabled_backends. A jq
# stub cannot show that; only real yq can. What the suite CAN hold is the
# weaker property that neither function writes to a key it was not asked to
# touch (2b, 2h).
#   Run: bash test_cinder_storage_tier_registry.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"
for f in cinder_apply_storage_tier_creation cinder_apply_storage_tier_deletion ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done
# the two capture helpers from core/main/proj_functions, taken from the tree
# rather than reimplemented: both paths lean on _hex_function keeping a
# command's own exit status, which a naive stub would flatten
PROG=test_cinder_storage_tier_registry
for f in _hex_function _hex_function_ret ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$DIR/../../main/proj_functions")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
POLICY_DIR="$TMP/policies"
ERROR_CINDER_APPLY_EXT_STORAGE_FAILED=6
POLICY="$POLICY_DIR/external_storage/external_storage1_0.yml"

MakeTempDir() { mktemp -d "$TMP/work.XXXXXX" ; }

# yq stood in with jq, over a policy stored as JSON. Only the five shapes the
# functions under test use are answered; anything else is a loud failure rather
# than a quiet empty string, because a stub that silently answers nothing is
# how a suite passes without running the code.
yq() {
    local inplace=0 args=()
    while [ $# -gt 0 ] ; do
        case "$1" in
            -i)        inplace=1 ;;
            -r|-e)     ;;
            -p=*|-o=*) ;;
            *)         args+=("$1") ;;
        esac
        shift
    done
    local expr="${args[0]}" file="${args[1]:-}"
    if [ -z "$file" ] ; then
        # `yq -p=yaml -o=json FILE` and `yq -p=json -o=yaml FILE`: one argument,
        # and with the policy stored as JSON both are a copy
        cat "$expr"
        return $?
    fi
    if [ "$inplace" = 1 ] ; then
        jq "$expr" "$file" > "$file.new" || return 1
        mv "$file.new" "$file"
        return 0
    fi
    case "$expr" in
        '.tiers | length'|'.tiers['*'].name')
            jq -r "$expr" "$file" ;;
        *)
            echo "yq stub: unhandled expression '$expr'" >&2 ; return 3 ;;
    esac
}

# $HEX_CFG apply <dir> commits the edited policy into POLICY_DIR and restarts
# the services that read it. Copying it back is what makes a second call see
# the first one's result, which is the only way an idempotence claim can be
# tested at all.
HEX_CFG=fake_cfg
APPLY_RC=0
fake_cfg() {
    echo "apply $2" >> "$TMP/calls"
    cp -f "$2/external_storage/external_storage1_0.yml" "$TMP/applied.json"
    [ "$APPLY_RC" = 0 ] || return "$APPLY_RC"
    cp -f "$TMP/applied.json" "$POLICY"
    return 0
}

reset_policy() {
    mkdir -p "$POLICY_DIR/external_storage"
    cat > "$POLICY" <<'JSON'
{"name":"external_storage","version":"1.0","volumeType":{"default":"CubeStorage"},
 "backends":[{"name":"extbk"}],"tiers":[{"name":"gold"}],
 "image":{"multipath":{"use":true,"enforce":true}}}
JSON
    : > "$TMP/calls"
    rm -f "$TMP/applied.json"
    APPLY_RC=0
}

applied() { jq -c "$1" "$TMP/applied.json" 2>/dev/null ; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# ==== creation ============================================================

# ---- 1a. a new name is appended, and applied ----
reset_policy
cinder_apply_storage_tier_creation silver ; ck "$?" 0 "1a a new tier is registered"
ck "$(grep -c '^apply ' "$TMP/calls")" 1 "1a the policy was applied once"
ck "$(applied '.tiers')" '[{"name":"gold"},{"name":"silver"}]' "1a appended after the existing tier"
ck "$(applied '.backends')" '[{"name":"extbk"}]' "1a the backends are untouched"
ck "$(applied '.volumeType.default')" '"CubeStorage"' "1a the default volume type is untouched"

# ---- 1b. an empty list writes into the blank child, not after it ----
# policy_ext_storage.cpp keeps one nameless entry when the vector is empty,
# because the yml parser needs at least one child. Appending after it would
# leave a stray empty entry in the settings array for good.
reset_policy
jq -c '.tiers = [{"name":null}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_tier_creation silver ; ck "$?" 0 "1b registering into an empty list succeeds"
ck "$(applied '.tiers')" '[{"name":"silver"}]' "1b the blank child was reused"

# ---- 1c. re-registering the same name changes nothing and applies nothing ----
# Run as a sequence, against the policy the first call actually committed:
# checking the source file after a single no-op call would pass even if the
# name had been appended, because the edit happens on a copy.
reset_policy
cinder_apply_storage_tier_creation silver ; ck "$?" 0 "1c the first registration succeeds"
ck "$(jq -c '.tiers' "$POLICY")" '[{"name":"gold"},{"name":"silver"}]' "1c and is committed"
: > "$TMP/calls"
cinder_apply_storage_tier_creation silver ; ck "$?" 0 "1c re-registering it succeeds"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "1c Cinder was not restarted to change nothing"
ck "$(jq -c '.tiers' "$POLICY")" '[{"name":"gold"},{"name":"silver"}]' "1c no second copy was added"
cinder_apply_storage_tier_creation gold ; ck "$?" 0 "1c the tier that was there all along too"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "1c still nothing applied"

# ---- 1d. an empty name is refused ----
reset_policy
cinder_apply_storage_tier_creation "" ; ck "$?" 6 "1d an empty tier name is refused"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "1d nothing was applied"

# ---- 1e. an unreadable policy is not "no tiers yet" ----
# Reading a failed length as zero would write over index 0 and drop the tier
# already there, taking its Cinder backend with it.
reset_policy
jq -c 'del(.tiers)' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
printf 'this is not json\n' > "$POLICY"
cinder_apply_storage_tier_creation silver ; ck "$?" 6 "1e an unparseable policy is refused"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "1e nothing was applied"

# ---- 1f. a missing policy file is refused ----
reset_policy
rm -f "$POLICY"
# cp's own complaint on stderr is the expected behaviour, not a test failure
cinder_apply_storage_tier_creation silver 2>/dev/null ; ck "$?" 6 "1f a missing policy file is refused"

# ---- 1g. a failed apply is reported ----
reset_policy
APPLY_RC=1
cinder_apply_storage_tier_creation silver ; ck "$?" 6 "1g a failed apply returns non-zero"

# ==== deletion ============================================================

# ---- 2a. the name comes out, and it is applied ----
reset_policy
jq -c '.tiers = [{"name":"gold"},{"name":"silver"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_tier_deletion gold ; ck "$?" 0 "2a a registered tier is removed"
ck "$(applied '.tiers')" '[{"name":"silver"}]' "2a only that entry went"
ck "$(grep -c '^apply ' "$TMP/calls")" 1 "2a the policy was applied once"

# ---- 2b. emptying the list leaves the blank child ----
reset_policy
cinder_apply_storage_tier_deletion gold ; ck "$?" 0 "2b removing the last tier succeeds"
ck "$(applied '.tiers')" '[{"name":""}]' "2b the blank child the yml parser needs is kept"
ck "$(applied '.backends')" '[{"name":"extbk"}]' "2b the backends are untouched"
ck "$(applied '.version')" '"1.0"' "2b the version is untouched"
ck "$(applied '.volumeType')" '{"default":"CubeStorage"}' "2b the default volume type is untouched"
ck "$(applied '.image')" '{"multipath":{"use":true,"enforce":true}}' "2b the image settings are untouched"

# ---- 2c. a name that is not registered is a no-op, not an error ----
# ceph_device_tier_delete calls this unconditionally, including for a tier that
# never got as far as step 6, and that must not restart Cinder either.
reset_policy
cinder_apply_storage_tier_deletion bronze ; ck "$?" 0 "2c an unregistered name succeeds"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "2c nothing was applied"
ck "$(jq -c '.tiers' "$POLICY")" '[{"name":"gold"}]' "2c the policy is unchanged"

# ---- 2d. an empty name is refused ----
reset_policy
cinder_apply_storage_tier_deletion "" ; ck "$?" 1 "2d an empty tier name is refused"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "2d nothing was applied"

# ---- 2e. a name with a quote in it is data, not filter syntax ----
# Every other writer of this array -- the policy chain and `hex_config commit
# <settings>` -- writes it without passing through the CLI's name guard, so an
# entry can hold any byte at all. Spliced into a jq filter, this one would
# rewrite the filter that is meant to be matching it.
reset_policy
jq -c '.tiers = [{"name":"gold"},{"name":"a\"b"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_tier_deletion 'a"b' ; ck "$?" 0 "2e a quoted name is removed"
ck "$(applied '.tiers')" '[{"name":"gold"}]' "2e and only it"

# ---- 2f. an unreadable policy is refused ----
reset_policy
printf 'this is not json\n' > "$POLICY"
cinder_apply_storage_tier_deletion gold ; ck "$?" 1 "2f an unparseable policy is refused"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "2f nothing was applied"

# ---- 2g. a failed apply is reported ----
reset_policy
APPLY_RC=1
cinder_apply_storage_tier_deletion gold ; ck "$?" 1 "2g a failed apply returns non-zero"

# ---- 2h. a blank placeholder alongside a real entry survives the deletion ----
# The registry can hold the empty-list placeholder and a real tier at the same
# time (policy_ext_storage.cpp only drops the blank one when it rewrites), and
# the entry that is not being removed -- blank or not -- must come out the
# other side unchanged.
reset_policy
jq -c '.tiers = [{"name":""},{"name":"gold"},{"name":"silver"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_tier_deletion gold ; ck "$?" 0 "2h removing the middle entry succeeds"
ck "$(applied '.tiers')" '[{"name":""},{"name":"silver"}]' "2h only that entry went"
ck "$(applied '.backends')" '[{"name":"extbk"}]' "2h nothing else was rewritten"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: cinder storage tier registry writes"; exit 0; } || exit 1
