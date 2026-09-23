#!/bin/bash
#
# Unit test for the external storage backend registry writes in
# ../modules/sdk_cinder.sh (#1454):
#   cinder_apply_storage_deletion -- takes a backend out of the backends:
#                                    sequence its Cinder backend is generated
#                                    from, WITHOUT rewriting the rest of the
#                                    policy document
#   cinder_apply_storage_creation -- puts one in, reusing the nameless
#                                    placeholder instead of appending after it
#
# What #1454 was: the deletion path edited the policy by round-tripping the
# whole document through `yq -p=yaml -o=json` -> jq -> `yq -p=json -o=yaml`.
# That re-serialises every node, so keys the function was never asked to touch
# came back changed -- `version: 1.0` as `version: 1`, the `---` header and the
# file's comment gone, and the empty-list placeholder `- name:` as
# `- name: null`. HexYmlParseString has no notion of null, so that arrived as
# the four-character string "null" and a backend called null went into
# enabled_backends, permanently down. Since #840 the same document carries
# tiers: too, whose placeholder had no rescue path at all.
#
# THE SUITE IS IN THREE PARTS, because no single vantage can hold all of it:
#
#   Part A  jq standing in for yq, policy stored as JSON. Holds the DECISIONS:
#           which entry is removed, whether apply is reached, what happens when
#           a read fails, whether a name is data or filter syntax. Runs
#           anywhere. Cannot see YAML fidelity at all -- in JSON there is no
#           `version: 1.0` to flatten and no comment to lose.
#   Part B  real yq over a real YAML policy. Holds the FIDELITY claims that are
#           the whole point of #1454. SKIPPED, loudly, when yq is absent (it is
#           absent on macOS; the 1cc has v4.45.1).
#   Part C  negative control: the pre-fix functions run against these same
#           assertions, to prove the suite fails on the old code. They come from
#           a pinned git object, or from OLD_SDK_CINDER=<path> where there is no
#           repo -- which is the appliance, i.e. the only host with a real yq
#           and so the only one where C2 means anything. C1 (creation) is a pure
#           decision difference and runs under the Part A stub; C2 (deletion) is
#           invisible in JSON -- both old and new leave one null there -- so it
#           needs real yq and skips with Part B.
#
#   Run: bash test_cinder_storage_backend_registry.sh
#   On an appliance, with the pre-fix file copied alongside:
#        OLD_SDK_CINDER=/tmp/sdk_cinder.pre1454 bash test_..._registry.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

# The commit these functions looked like before the fix. Pinned to an object,
# not to a branch: origin/develop moves on and will one day carry the fix,
# which would quietly turn the negative control green against itself.
BASE_REF=ae93e66bd279a62176ddb8fd2b5ac6f8d10c0222
# ...or point OLD_SDK_CINDER at a copy of that file, for hosts with no git repo
# (an appliance, where the real yq lives). Same thing, different transport.

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

for f in cinder_apply_storage_deletion cinder_apply_storage_creation ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done

# Helpers taken from the tree rather than reimplemented. The two capture
# helpers because both paths lean on _hex_function keeping a command's own exit
# status, which a naive stub would flatten; the json/filesystem ones because
# the PRE-FIX deletion path in Part C needs them and a hand-written version
# would be testing the wrong thing.
PROG=test_cinder_storage_backend_registry
for f in _hex_function _hex_function_ret ; do
    extract "$DIR/../../main/proj_functions" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
for f in json_get_compact_value json_is_array ; do
    extract "$DIR/../modules.pre/sdk_json.sh" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_filesystem.sh" filesystem_write_file \
    || { echo "FAIL: filesystem_write_file not extracted"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
POLICY_DIR="$TMP/policies"
ERROR_CINDER_APPLY_EXT_STORAGE_FAILED=6
POLICY="$POLICY_DIR/external_storage/external_storage1_0.yml"

MakeTempDir() { mktemp -d "$TMP/work.XXXXXX" ; }

pass=0 fail=0 skip=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }
skipped() { skip=$((skip+1)); echo "SKIP: $1"; }

# ==== Part A: decisions, with jq standing in for yq =======================

# Only the expression shapes these functions actually use are answered;
# anything else is a loud failure rather than a quiet empty string, because a
# stub that silently answers nothing is how a suite passes without running the
# code under test.
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
        # `yq -p=yaml -o=json FILE` / `yq -p=json -o=yaml FILE`: one argument,
        # and with the policy stored as JSON both are a copy. This is the shape
        # the pre-fix deletion path in Part C uses.
        cat "$expr"
        return $?
    fi
    if [ "$inplace" = 1 ] ; then
        jq "$expr" "$file" > "$file.new" || return 1
        mv "$file.new" "$file"
        return 0
    fi
    case "$expr" in
        '.backends | tag')
            # A YAML tag, which JSON has no notion of. Mapped from jq's type so
            # the stub answers the same shapes the real yq does -- measured on
            # the 1cc (v4.45.1): a sequence !!seq, a mapping !!map, a string
            # !!str, a missing key !!null.
            jq -r '.backends | type
                   | if   . == "array"  then "!!seq"
                     elif . == "object" then "!!map"
                     elif . == "string" then "!!str"
                     elif . == "null"   then "!!null"
                     elif . == "number" then "!!int"
                     else "!!" + . end' "$file" ;;
        '.backends | length'|'.backends['*'].name'|'.volumeType.default')
            jq -r "$expr" "$file" ;;
        *)
            echo "yq stub: unhandled expression '$expr'" >&2 ; return 3 ;;
    esac
}

# $HEX_CFG apply <dir> commits the edited policy into POLICY_DIR and restarts
# the services that read it. Copying it back is what makes a second call see
# the first one's result.
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

# ---- A1. the named backend comes out, and only it ----
reset_policy
jq -c '.backends = [{"name":"extbk"},{"name":"nfs1"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_deletion extbk ; ck "$?" 0 "A1 a registered backend is removed"
ck "$(applied '.backends')" '[{"name":"nfs1"}]' "A1 only that entry went"
ck "$(grep -c '^apply ' "$TMP/calls")" 1 "A1 the policy was applied once"

# ---- A2. nothing outside .backends is rewritten ----
# This is #1454 stated as far as JSON can state it: the round trip this
# replaced rebuilt every key on the way past.
reset_policy
cinder_apply_storage_deletion extbk ; ck "$?" 0 "A2 removing the last backend succeeds"
ck "$(applied '.tiers')" '[{"name":"gold"}]' "A2 the tiers are untouched"
ck "$(applied '.version')" '"1.0"' "A2 the version is untouched"
ck "$(applied '.image')" '{"multipath":{"use":true,"enforce":true}}' "A2 the image settings are untouched"
ck "$(applied '.name')" '"external_storage"' "A2 the policy name is untouched"

# ---- A3. emptying the list leaves the blank child the yml parser needs ----
ck "$(applied '.backends')" '[{"name":""}]' "A3 the blank child is kept"

# ---- A4. the default volume type falls back only when it was the one deleted --
reset_policy
cinder_apply_storage_deletion extbk >/dev/null
ck "$(applied '.volumeType.default')" '"CubeStorage"' "A4 an unrelated default is left alone"
reset_policy
jq -c '.volumeType.default = "extbk"' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_deletion extbk >/dev/null
ck "$(applied '.volumeType.default')" '"CubeStorage"' "A4 deleting the default falls back to CubeStorage"

# ---- A5. every entry carrying the name goes, not just the first ----
# The CLI cannot create a duplicate (:1656 guards it), but `hex_config commit
# <settings>` writes this array without passing through the CLI at all. The jq
# filter this replaced removed them all; removing only the first would leave a
# backend the operator asked to delete still generating.
reset_policy
jq -c '.backends = [{"name":"dup"},{"name":"keep"},{"name":"dup"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_deletion dup ; ck "$?" 0 "A5 a duplicated name is removed"
ck "$(applied '.backends')" '[{"name":"keep"}]' "A5 both copies went, and only they"

# ---- A6. a name with a quote in it is data, not filter syntax ----
reset_policy
jq -c '.backends = [{"name":"keep"},{"name":"a\"b"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_deletion 'a"b' ; ck "$?" 0 "A6 a quoted name is removed"
ck "$(applied '.backends')" '[{"name":"keep"}]' "A6 and only it"

# ---- A7. a name that is not registered changes nothing ----
reset_policy
cinder_apply_storage_deletion nosuch ; ck "$?" 0 "A7 an unregistered name succeeds"
ck "$(applied '.backends')" '[{"name":"extbk"}]' "A7 the backends are unchanged"

# ---- A8. an empty name is a no-op, and an unreadable policy is refused ----
reset_policy
cinder_apply_storage_deletion "" ; ck "$?" 0 "A8 an empty name returns 0"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "A8 and applies nothing"
reset_policy
printf 'this is not json\n' > "$POLICY"
cinder_apply_storage_deletion extbk ; ck "$?" 1 "A8 an unparseable policy is refused"
ck "$(grep -c '^apply ' "$TMP/calls")" 0 "A8 nothing was applied"
reset_policy
rm -f "$POLICY"
cinder_apply_storage_deletion extbk 2>/dev/null ; ck "$?" 1 "A8 a missing policy file is refused"

# ---- A8b. a backends: that is not a sequence is refused ----
# The round trip this function replaced checked with json_is_array. Measured on
# the 1cc, `.backends | length` answers a mapping with its key count, a string
# with its character count and a missing key with 0 -- all rc 0 -- so a
# digits-only test would walk past all three, delete nothing, and still apply.
#
# Only the MISSING-KEY case has teeth here. Verified by re-running this suite
# against a copy with the tag check removed: `backends` absent came back 0 and
# applied, while the mapping and the string still came back 1 -- because jq
# errors out on `.backends[0]` over an object, which real yq does not do (it
# answers null, rc 0). Those two are refused by the tag check alone on a real
# appliance, so their real assertion is B4, not this loop.
for shape in '{"a":1}' '"hello"' 'null' ; do
    reset_policy
    if [ "$shape" = null ] ; then
        jq -c 'del(.backends)' "$POLICY" > "$TMP/x"
    else
        jq -c --argjson v "$shape" '.backends = $v' "$POLICY" > "$TMP/x"
    fi
    mv "$TMP/x" "$POLICY"
    cinder_apply_storage_deletion extbk ; ck "$?" 1 "A8b backends=$shape is refused"
    ck "$(grep -c '^apply ' "$TMP/calls")" 0 "A8b backends=$shape applied nothing"
done

# ---- A9. a failed apply is reported ----
reset_policy
APPLY_RC=1
cinder_apply_storage_deletion extbk ; ck "$?" 1 "A9 a failed apply returns non-zero"

# ---- A10. creation reuses the nameless placeholder instead of appending ----
# A policy polluted by the old deletion path carries an EXPLICIT `- name: null`,
# and yq reads that back as the four-character string "null" rather than as
# blank -- so without the guard that slot is never reused and never dropped,
# and a backend called null keeps being generated from it.
#
# Only the explicit null behaves that way. Measured on the 1cc (yq v4.45.1):
# an empty scalar `- name:` and an empty string `- name: ""` both already read
# as blank, so a clean node never had this problem.
reset_policy
jq -c '.backends = [{"name":null}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_creation nfs1 false true true ; ck "$?" 0 "A10 registering into an empty list succeeds"
ck "$(applied '.backends')" '[{"name":"nfs1"}]' "A10 the placeholder was reused, not appended after"

# ---- A11. creation still appends when there is no placeholder ----
reset_policy
cinder_apply_storage_creation nfs1 false true true ; ck "$?" 0 "A11 registering alongside a backend succeeds"
ck "$(applied '.backends')" '[{"name":"extbk"},{"name":"nfs1"}]' "A11 appended after the existing one"
ck "$(applied '.tiers')" '[{"name":"gold"}]' "A11 the tiers are untouched"

# ---- A12. creation drops a stale null placeholder even when appending ----
reset_policy
jq -c '.backends = [{"name":null},{"name":"extbk"}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
cinder_apply_storage_creation nfs1 false true true ; ck "$?" 0 "A12 registering succeeds"
ck "$(applied '.backends')" '[{"name":"extbk"},{"name":"nfs1"}]' "A12 the stale null placeholder is gone"

# ==== Part B: fidelity, over real YAML with real yq =======================

# type -P, not command -v: at this point yq is a shell FUNCTION (the Part A
# stub), and command -v would happily report that as "yq available" and run the
# fidelity checks against the stub -- which cannot fail them and cannot prove
# them either. Only a real executable on PATH counts here.
YQ_BIN="$(type -P yq || true)"

yaml_policy() {
    mkdir -p "$POLICY_DIR/external_storage"
    cat > "$POLICY" <<'YAML'
---
# external_storage/external_storage1_0.yml
name: external_storage
version: 1.0

volumeType:
  default: CubeStorage
backends:
  - name: extbk
tiers:
  - name:
image:
  multipath:
    use: true
    enforce: true
YAML
    : > "$TMP/calls"
    rm -f "$TMP/applied.yml"
    APPLY_RC=0
}

yaml_cfg() {
    echo "apply $2" >> "$TMP/calls"
    cp -f "$2/external_storage/external_storage1_0.yml" "$TMP/applied.yml"
    [ "$APPLY_RC" = 0 ] || return "$APPLY_RC"
    cp -f "$TMP/applied.yml" "$POLICY"
    return 0
}

run_part_b() {
    unset -f yq            # from here on, the real one
    HEX_CFG=yaml_cfg

    # ---- B1. deleting the only backend does not disturb the document ----
    yaml_policy
    cinder_apply_storage_deletion extbk ; ck "$?" 0 "B1 the backend is removed"
    ck "$(grep -c 'name: null' "$TMP/applied.yml")" 0 "B1 no null name anywhere -- the bug in one line"
    ck "$(grep -c '^version: 1\.0$' "$TMP/applied.yml")" 1 "B1 version: 1.0 did not become 1"
    ck "$(head -1 "$TMP/applied.yml")" '---' "B1 the document header survived"
    ck "$(grep -c '^# external_storage/' "$TMP/applied.yml")" 1 "B1 the file's comment survived"
    ck "$(grep -A1 '^tiers:' "$TMP/applied.yml" | tail -1)" '  - name:' "B1 the tiers placeholder is untouched"
    ck "$(grep -c 'extbk' "$TMP/applied.yml")" 0 "B1 the deleted backend is gone"

    # ---- B2. the emptied backends list keeps a child the yml parser accepts --
    ck "$(grep -A1 '^backends:' "$TMP/applied.yml" | tail -1)" '  - name: ""' "B2 the blank child is an empty string, not null"

    # ---- B3. one of two backends goes, the other is intact ----
    yaml_policy
    "$YQ_BIN" -i '.backends += [{"name":"nfs1"}]' "$POLICY"
    cinder_apply_storage_deletion extbk ; ck "$?" 0 "B3 one of two backends is removed"
    ck "$(grep -c 'name: nfs1' "$TMP/applied.yml")" 1 "B3 the other backend is still there"
    ck "$(grep -c 'name: null' "$TMP/applied.yml")" 0 "B3 still no null name"
    ck "$(grep -c '^version: 1\.0$' "$TMP/applied.yml")" 1 "B3 version: 1.0 still intact"

    # ---- B4. a backends: that is not a sequence is refused ----
    # Part A cannot hold this one. There, jq refuses `.backends[0]` over an
    # object and the function fails for that reason instead. Real yq answers
    # it with null and rc 0 -- measured, v4.45.1 -- so the shape walks straight
    # through a length-is-a-number test, deletes nothing, and would still reach
    # $HEX_CFG apply. The tag check is the only thing standing here.
    yaml_policy
    "$YQ_BIN" -i '.backends = {"a": 1}' "$POLICY"
    cinder_apply_storage_deletion extbk ; ck "$?" 1 "B4 a mapping backends is refused"
    ck "$(grep -c '^apply ' "$TMP/calls")" 0 "B4 a mapping applied nothing"
    yaml_policy
    "$YQ_BIN" -i '.backends = "hello"' "$POLICY"
    cinder_apply_storage_deletion extbk ; ck "$?" 1 "B4 a string backends is refused"
    ck "$(grep -c '^apply ' "$TMP/calls")" 0 "B4 a string applied nothing"
}

# ==== Part C: negative control against the pre-fix code ===================

# C1 runs under the Part A stub (pure decision difference); C2 needs real yq
# because in JSON the old and the new deletion path both leave one null behind
# -- the difference only exists in the YAML the old one rewrote.
extract_old() {  # <function> <rename-to>
    local f="$TMP/old_sdk_cinder.sh"
    if [ ! -s "$f" ] ; then
        # Two ways to get the pre-fix code, because the one that works on a
        # developer's checkout does not work where it matters most. Deployed on
        # an appliance this file sits in /usr/lib/hex_sdk/tests with no git repo
        # anywhere near it -- and that is exactly the host that HAS a real yq,
        # so leaving it git-only means C2 (the deletion path's negative control)
        # can never run on the only machine able to run it.
        if [ -n "${OLD_SDK_CINDER:-}" ] ; then
            [ -s "$OLD_SDK_CINDER" ] || return 1
            cp "$OLD_SDK_CINDER" "$f" || return 1
        else
            git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_cinder.sh" > "$f" 2>/dev/null || return 1
        fi
        # The pre-fix functions read the policy from a hard-coded /etc/policies,
        # which is the other half of what this commit changes -- and it is NOT
        # the behaviour under test. Left alone, the old function dies at a cp
        # that has nothing to copy (its return value was discarded) and the
        # control comes out green because NOTHING RAN, which is the failure mode
        # a negative control exists to catch in the first place.
        sed -i.bak 's|"/etc/policies/|"$POLICY_DIR/|g' "$f" || return 1
        rm -f "$f.bak"
    fi
    extract "$f" "$1" "$2"
}

run_c1() {
    extract_old cinder_apply_storage_creation old_creation \
        || { skipped "C1 pre-fix creation not available (no git repo here? set OLD_SDK_CINDER=<path to the pre-fix sdk_cinder.sh>)"; return; }
    HEX_CFG=fake_cfg
    reset_policy
    jq -c '.backends = [{"name":null}]' "$POLICY" > "$TMP/x" ; mv "$TMP/x" "$POLICY"
    old_creation nfs1 false true true >/dev/null 2>&1
    # Did it even run? A control that is green because the old function bailed
    # out early is worth nothing, so this is checked before the difference is.
    if [ "$(grep -c '^apply ' "$TMP/calls")" -eq 0 ] ; then
        fail=$((fail+1))
        echo "FAIL: C1 the pre-fix creation never reached apply -> the control did not exercise it"
        return
    fi
    # The assertion A10 makes, against the old code. It has to FAIL there, or
    # A10 is not testing the guard that was added.
    local got ; got="$(applied '.backends')"
    if [ "$got" = '[{"name":"nfs1"}]' ] ; then
        fail=$((fail+1))
        echo "FAIL: C1 the pre-fix creation already reused the placeholder -> A10 proves nothing"
    else
        pass=$((pass+1))
        echo "note: C1 pre-fix creation ran and left '$got' -- the placeholder was not reused"
    fi
}

run_c2() {
    extract_old cinder_apply_storage_deletion old_deletion \
        || { skipped "C2 pre-fix deletion not available (no git repo here? set OLD_SDK_CINDER=<path to the pre-fix sdk_cinder.sh>)"; return; }
    unset -f yq
    HEX_CFG=yaml_cfg
    yaml_policy
    old_deletion extbk >/dev/null 2>&1
    if [ ! -s "$TMP/applied.yml" ] ; then
        fail=$((fail+1))
        echo "FAIL: C2 the pre-fix deletion never reached apply -> the control did not exercise it"
        return
    fi
    # NOT `$(grep -c ... || echo 0)`: grep -c prints its count AND exits 1 when
    # the count is zero, so the fallback fires on top of a perfectly good "0"
    # and the variable becomes two lines. `[ "0\n0" -eq 0 ]` is then an
    # "integer expression expected" error, and a control that did reproduce the
    # bug reports itself as broken.
    local nulls ver
    nulls=$(grep -c 'name: null' "$TMP/applied.yml" 2>/dev/null) || true
    ver=$(grep -c '^version: 1\.0$' "$TMP/applied.yml" 2>/dev/null) || true
    nulls=${nulls:-0} ; ver=${ver:-0}
    if [ "$nulls" -gt 0 ] && [ "$ver" -eq 0 ] ; then
        pass=$((pass+1))
        echo "note: C2 pre-fix deletion produced $nulls null name(s) and flattened version -- B1 has teeth"
    else
        fail=$((fail+1))
        echo "FAIL: C2 the pre-fix deletion did not reproduce #1454 (nulls=$nulls version_1_0=$ver) -> B1 proves nothing"
    fi
}

# ==== run ================================================================

run_c1

if [ -n "$YQ_BIN" ] ; then
    run_part_b
    run_c2
else
    skipped "Part B (YAML fidelity) -- no yq on this host; run this on a node that has it"
    skipped "C2 (negative control for the deletion path) -- needs the same yq"
fi

echo "----"; echo "PASS=$pass FAIL=$fail SKIP=$skip"
if [ "$fail" -eq 0 ] ; then
    [ "$skip" -eq 0 ] || echo "NOTE: $skip check group(s) skipped -- this run did NOT verify YAML fidelity"
    echo "OK: cinder storage backend registry writes"
    exit 0
fi
exit 1
