#!/bin/bash
#
# Unit test for deleting an external storage Manila still uses (#2329):
# cinder_delete_storage refuses while the storage's share type has shares or
# its backend (<host>@<name>) has share servers, naming them, and when either
# list cannot be read. Once the backend is gone those can never be removed.
#
# The suite runs the real cinder_delete_storage, cinder_is_storage_manila_free
# and json helpers; openstack, hex_tuning and the steps past the checks are
# stubbed. Part C runs the same assertions against cinder_delete_storage as it
# was before the fix, which deletes the storage in every case.
#
#   Run: bash test_cinder_is_storage_manila_free.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

# The commit cinder_delete_storage looked like before the fix. Pinned to an
# object, not to a branch, so the negative control cannot turn green against itself.
BASE_REF=02cf633a

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

for f in cinder_delete_storage cinder_is_storage_manila_free ; do
    extract "$SRC" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../../main/proj_functions" _hex_function || { echo "FAIL: _hex_function not extracted"; exit 1; }
for f in json_get_value json_get_compact_value json_is_array ; do
    extract "$DIR/../modules.pre/sdk_json.sh" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_is.sh" is_valid_json || { echo "FAIL: is_valid_json not extracted"; exit 1; }
eval "$(grep -E '^ERROR_JSON_[A-Z_]+=' "$DIR/../modules.pre/sdk_json.sh")"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY="$WORK/backends"
CINDER_STORAGE_EXTRA_CONFIGS_DIRECTORY="$WORK/extra"
CINDER_STORAGE_EXTRA_CONFIGS_OWNERSHIP_DIRECTORY="$WORK/ownership"
CUBE_NODE_CONTROL_HOSTNAMES=(cc1)
HOSTNAME=cc1

# --- stubs: everything that would touch the node ---------------------------
# manila.enabled as settings.txt has it; empty = the line is absent (default on)
SETTINGS_TXT="$WORK/settings.txt"
HEX_TUN="$WORK/hex_tuning"
echo 'T_manila_enabled="$MANILA_ENABLED"' > "$HEX_TUN"
# SHARES / SERVERS: what `share list` / `share server list` print, *_RC their exit
OPENSTACK=openstack_stub
openstack_stub() {  # runs in $(...) too, so it records to a file
    echo "$*" >> "$WORK/.os"
    case "$*" in
        "share list --all-projects -f json") printf '%s' "$SHARES" ; return "$SHARES_RC" ;;
        "share server list -f json") printf '%s' "$SERVERS" ; return "$SERVERS_RC" ;;
    esac
    return 0
}
# real for the json helpers' jq; everything else changes the node and is recorded
_hex_function_ret() {
    [ "$1" = jq ] && { "$@" >/dev/null 2>&1 ; return ; }
    LOG+="$*;"
    return 0
}
is_control_node() { return 1; }
cinder_is_volume_type_in_use() { return 1; }
cinder_apply_storage_deletion() { LOG+="apply;"; return 0; }
cinder_get_storage_nfs_mount_hashes() { :; }
cinder_read_storage_extra_configs_ownership() { echo '{"extraConfigFiles":[]}'; }

reset() {
    rm -rf "${WORK:?}"/backends
    mkdir -p "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY"
    echo "[nfs1]" > "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY/ext_storage_nfs1.conf"
    : > "$WORK/.os"
    LOG="" MANILA_ENABLED="" SHARES="[]" SERVERS="[]" SHARES_RC=0 SERVERS_RC=0
    unset T_manila_enabled
}
share() { printf '{"ID":"%s","Name":"","Status":"%s","Share Type Name":"%s","Host":"cc1@%s#%s"}' "$1" "$2" "$3" "$3" "$3"; }
server() { printf '{"ID":"%s","Host":"%s","Status":"%s","Share Network ID":"n1","Project ID":"p1"}' "$1" "$2" "$3"; }
run() {  # <function> -> OUT, ERR (the stderr message); in this shell, so LOG survives
    "$1" '{"name":"nfs1"}' >"$WORK/.out" 2>"$WORK/.err"
    OUT="$(cat "$WORK/.out")"
    ERR="$(jq -r '.message // empty' "$WORK/.err" 2>/dev/null)"
}
has() { [[ "$LOG$(cat "$WORK/.os")" == *"$1"* ]] && echo yes || echo no; }
DELETED='{"message":"storage nfs1 deleted"}'

suite() {  # <label> <delete function>
    local L="$1" del="$2"

    # M1. Manila disabled: not asked, deleted
    reset; MANILA_ENABLED=false; SHARES_RC=1
    run "$del"
    chk "$L M1 deleted" "$OUT" "$DELETED"
    chk "$L M1 Manila not asked" "$(has "share list")" "no"

    # M2. manila.enabled absent (default on), nothing on Manila: deleted
    reset
    run "$del"
    chk "$L M2 deleted" "$OUT" "$DELETED"
    chk "$L M2 Manila asked" "$(has "share server list")" "yes"

    # M3. a share of its type, in error: refused and named, nothing deleted
    reset; SHARES="[$(share s1 error nfs1)]"
    run "$del"
    chk "$L M3 refused" "$ERR" "storage nfs1 is still used by Manila, delete these first: shares s1 (error)"
    chk "$L M3 nothing changed" "$LOG" ""
    chk "$L M3 config kept" "$(ls "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY")" "ext_storage_nfs1.conf"

    # M4. only share servers left on its backend, any host: refused and named
    reset; SERVERS="[$(server v1 cc2@nfs1 error),$(server v2 cc1@nfs1 error)]"
    run "$del"
    chk "$L M4 refused" "$ERR" "storage nfs1 is still used by Manila, delete these first: share servers v1 (error), v2 (error)"
    chk "$L M4 nothing changed" "$LOG" ""

    # M5. both: refused, both named
    reset; SHARES="[$(share s1 deleting nfs1)]"; SERVERS="[$(server v1 cc2@nfs1 error)]"
    run "$del"
    chk "$L M5 refused" "$ERR" "storage nfs1 is still used by Manila, delete these first: shares s1 (deleting); share servers v1 (error)"
    chk "$L M5 nothing changed" "$LOG" ""

    # M6. other storages' shares and servers (nfs10, the default backend): deleted
    reset
    SHARES="[$(share s2 available nfs10),$(share s3 available tenant_share_type)]"
    SERVERS="[$(server v3 cc1@nfs10 active),$(server v4 cc1@generic active)]"
    run "$del"
    chk "$L M6 deleted" "$OUT" "$DELETED"

    # M7. share list fails: refused
    reset; SHARES="" SHARES_RC=1
    run "$del"
    chk "$L M7 refused" "$ERR" "Manila shares or share servers of storage nfs1 could not be read"
    chk "$L M7 nothing changed" "$LOG" ""

    # M8. share server list prints nothing, exit 0: refused
    reset; SERVERS=""
    run "$del"
    chk "$L M8 refused" "$ERR" "Manila shares or share servers of storage nfs1 could not be read"
    chk "$L M8 nothing changed" "$LOG" ""

    # M9. share list is not a list: refused
    reset; SHARES='{"error":"x"}'
    run "$del"
    chk "$L M9 refused" "$ERR" "Manila shares or share servers of storage nfs1 could not be read"
    chk "$L M9 nothing changed" "$LOG" ""
}

# --- Part A: the functions as they are now ---------------------------------
suite "A" cinder_delete_storage

# --- Part C: negative control, the pre-fix function must fail Part A -------
if old="$(git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_cinder.sh" 2>/dev/null)"; then
    tmp="$(mktemp)"; printf '%s\n' "$old" > "$tmp"
    extract "$tmp" cinder_delete_storage cinder_delete_storage_prefix || { echo "FAIL: pre-fix delete not extracted"; exit 1; }
    rm -f "$tmp"
    p0=$pass f0=$fail
    suite "C" cinder_delete_storage_prefix >/dev/null
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
