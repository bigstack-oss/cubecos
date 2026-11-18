#!/bin/bash
#
# Test Manila backend share type pruning preserves admin-created types (#2362),
# configured types and types with shares, and deletes nothing on bad list output.
# Part C runs the same suite against the pre-fix function as a negative control.
#
#   Run: bash test_manila_backend_types_prune.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_os.sh"

# Pinned before the fix so the negative control cannot turn green against itself.
BASE_REF=06753991

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

extract "$SRC" os_manila_backend_types_init || { echo "FAIL: function not extracted"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- stubs: everything that would touch the node ---------------------------
is_control_node() { return 0; }
OPENSTACK=openstack_stub
openstack_stub() {  # records to a file because callers use $(...)
    echo "$*" >> "$WORK/.os"
    case "$*" in
        "share type list -f json") printf '%s' "$TYPES_JSON"; return "$TYPES_RC" ;;
        "share type list -f value -c Name")
            if [ "$TYPES_JSON" = garbage ]; then
                printf '%s' "$TYPES_JSON"
            elif [ -n "$TYPES_JSON" ]; then
                printf '%s' "$TYPES_JSON" | jq -r '.[].Name'
            fi
            return "$TYPES_RC" ;;
        "share list --all-projects --share-type "*" -f value -c ID")
            case " $IN_USE " in *" $5 "*) echo share-id ;; esac ;;
    esac
    return 0
}
manila() { echo "manila $*" >> "$WORK/.manila"; }

stype() {  # <name> <share_backend_name or empty>
    jq -cn --arg name "$1" --arg backend "$2" '{
        "ID": $name, "Name": $name, "Visibility": "public", "Is Default": false,
        "Required Extra Specs": {"driver_handles_share_servers": "True"},
        "Optional Extra Specs": (if $backend == "" then {} else {"share_backend_name": $backend} end)
    }'
}
reset() {
    : > "$WORK/.os"
    : > "$WORK/.manila"
    TYPES_JSON='[]' TYPES_RC=0 IN_USE=""
}
run() {  # <function> -> OUT
    "$1" 'nfs1 ' > "$WORK/.out" 2> "$WORK/.err"
    OUT="$(cat "$WORK/.out")"
}
deleted() { grep -qxF "manila type-delete $1" "$WORK/.manila" && echo yes || echo no; }
any_deleted() { grep -q '^manila type-delete ' "$WORK/.manila" && echo yes || echo no; }

suite() {  # <label> <function>
    local L="$1" init="$2"

    reset
    TYPES_JSON="[$(stype qa-keep-me GENERIC),$(stype plain ''),$(stype nfs2 nfs2),$(stype nfs3 nfs3),$(stype tenant_share_type GENERIC),$(stype nfs1 nfs1),$(stype foo nfs1)]"
    IN_USE=nfs3
    run "$init"
    chk "$L admin backend kept" "$(deleted qa-keep-me)" no
    chk "$L admin without backend kept" "$(deleted plain)" no
    chk "$L obsolete own type deleted" "$(deleted nfs2)" yes
    chk "$L in-use own type kept" "$(deleted nfs3)" no
    chk "$L in-use message" "$OUT" "skip delete: share type nfs3 still has shares"
    chk "$L tenant type kept" "$(deleted tenant_share_type)" no
    chk "$L configured type kept" "$(deleted nfs1)" no
    chk "$L another type's backend kept" "$(deleted foo)" no

    reset; TYPES_RC=1 TYPES_JSON=""
    run "$init"
    chk "$L failed list deletes nothing" "$(any_deleted)" no

    # list fails after printing a usable list
    reset; TYPES_RC=1 TYPES_JSON="[$(stype nfs2 nfs2)]"
    run "$init"
    chk "$L failed list with output deletes nothing" "$(any_deleted)" no

    # jq prints nfs2, then fails on the next type
    reset; TYPES_JSON="[$(stype nfs2 nfs2),{\"Name\":\"bad\",\"Required Extra Specs\":\"x\"}]"
    run "$init"
    chk "$L partly unreadable list deletes nothing" "$(any_deleted)" no

    # an object, not a list: .[] would walk its values
    reset; TYPES_JSON="{\"nfs2\":$(stype nfs2 nfs2)}"
    run "$init"
    chk "$L object instead of list deletes nothing" "$(any_deleted)" no

    reset; TYPES_JSON=garbage
    run "$init"
    chk "$L garbage deletes nothing" "$(any_deleted)" no
}

# --- Part A: the function as it is now -------------------------------------
suite "A" os_manila_backend_types_init

# --- Part C: negative control, the pre-fix function must fail Part A --------
if old="$(git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_os.sh" 2>/dev/null)"; then
    tmp="$WORK/prefix.sh"; printf '%s\n' "$old" > "$tmp"
    extract "$tmp" os_manila_backend_types_init os_manila_backend_types_init_prefix || { echo "FAIL: pre-fix function not extracted"; exit 1; }
    rm -f "$tmp"
    p0=$pass f0=$fail
    suite "C" os_manila_backend_types_init_prefix >/dev/null 2>&1
    cfail=$((fail - f0))
    pass=$p0 fail=$f0
    if [ "$cfail" -gt 0 ]; then
        pass=$((pass+1)); echo "negative control: pre-fix function fails $cfail check(s)"
    else
        fail=$((fail+1)); echo "FAIL: negative control: pre-fix function passes every check"
    fi
else
    echo "SKIP: negative control ($BASE_REF not in this clone)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
