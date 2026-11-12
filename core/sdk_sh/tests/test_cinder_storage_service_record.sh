#!/bin/bash
#
# Unit test for the cinder-volume service record of an external storage
# (#2314): cinder_delete_storage removes <name>@<name>, and cinder_put_storage
# creating a storage drops a disabled <name>@<name> an earlier one left.
#
# A delete killed between disabling and removing the record left it disabled;
# a re-create under the same name reused it and was never scheduled.
#
# The suite runs the real json helpers and service-record helpers; openstack,
# apply and everything past the record check in cinder_put_storage are stubbed.
# Part C runs the same assertions against the functions as they were before
# the fix: the re-create checks (P1, P5) fail there because the disabled record
# stays; the delete checks fail only because the old code passed the bare name.
#
#   Run: bash test_cinder_storage_service_record.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

# The commit the functions looked like before the fix. Pinned to an object, not
# to a branch, so the negative control cannot turn green against itself.
BASE_REF=881cd84e

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

for f in cinder_delete_storage cinder_put_storage cinder_remove_volume_service \
         cinder_is_volume_service_disabled cinder_get_storage_name ; do
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
# ROWS: the cinder-volume records, "<host>:<enabled|disabled>" separated by spaces
OPENSTACK=openstack_stub
openstack_stub() {
    local r out=""
    case "$*" in
        "volume service list --service cinder-volume -f value -c Host")
            for r in $ROWS ; do echo "${r%:*}" ; done ;;
        "volume service list --service cinder-volume -f json")
            for r in $ROWS ; do
                out+="${out:+,}{\"Host\":\"${r%:*}\",\"Status\":\"${r##*:}\",\"State\":\"down\"}"
            done
            echo "[$out]" ;;
    esac
}
# every node-changing call goes through here; record it, fail cinder-manage on demand
_hex_function_ret() {
    LOG+="$*;"
    [[ "$*" == *cinder-manage* ]] && return "$REMOVE_RC"
    return 0
}
is_control_node() { [ "$CTRL" = yes ]; }
log_warning() { LOG+="warn:$1;"; }
cinder_is_volume_type_in_use() { return 1; }
cinder_is_storage_manila_free() { return 0; }
cinder_apply_storage_deletion() { LOG+="apply;"; return 0; }
cinder_get_storage_nfs_mount_hashes() { :; }
cinder_read_storage_extra_configs_ownership() { echo '{"extraConfigFiles":[]}'; }
# the first step past the record check in cinder_put_storage; stop there
cinder_marshal_storage_external_backend_conf() { return "$ERROR_JSON_INVALID_JSON"; }

reset() {
    rm -rf "${WORK:?}"/*
    mkdir -p "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY"
    LOG="" ROWS="" CTRL=yes REMOVE_RC=0
}
existing() { echo "[$1]" > "$CINDER_USER_INPUT_STORAGE_CONF_DIRECTORY/ext_storage_$1.conf"; }
put_input() {
    printf '{"name":"%s","driver":"nfs","storage":{"service":{"extraConfigFiles":[]}}}' "$1"
}
run() {  # <function> <input> -> OUT; in this shell, so LOG survives
    "$1" "$2" >"$WORK/.out" 2>/dev/null
    OUT="$(cat "$WORK/.out")"
}
has() { [[ "$LOG" == *"$1"* ]] && echo yes || echo no; }
nremove() { grep -c "cinder-manage" <<< "${LOG//;/$'\n'}"; }

suite() {  # <label> <delete function> <put function>
    local L="$1" del="$2" put="$3"

    # D1. the record is there: removed by its full host
    reset; existing nfs1; ROWS="nfs1@nfs1:enabled cube@ceph:enabled"
    run "$del" '{"name":"nfs1"}'
    chk "$L D1 deleted" "$OUT" '{"message":"storage nfs1 deleted"}'
    chk "$L D1 disabled by full host" "$(has "volume service set --disable nfs1@nfs1 cinder-volume")" "yes"
    chk "$L D1 removed by full host" "$(has "/usr/bin/cinder-manage service remove cinder-volume nfs1@nfs1")" "yes"
    chk "$L D1 after apply" "$(has "apply;openstack_stub volume service set --disable nfs1@nfs1")" "yes"

    # D2. remove fails: still deleted, and said so in the log
    reset; existing nfs1; ROWS="nfs1@nfs1:disabled"; REMOVE_RC=2
    run "$del" '{"name":"nfs1"}'
    chk "$L D2 still deleted" "$OUT" '{"message":"storage nfs1 deleted"}'
    chk "$L D2 failure logged" "$(has "warn:cinder-volume service nfs1@nfs1 of deleted storage nfs1 not removed")" "yes"

    # P1. new storage, a disabled record of the same name: dropped before the backend starts
    reset; ROWS="nfs1@nfs1:disabled"
    run "$put" "$(put_input nfs1)"
    chk "$L P1 disabled record removed" "$(has "/usr/bin/cinder-manage service remove cinder-volume nfs1@nfs1")" "yes"

    # P2. new storage, an enabled record: kept (it comes up when reused)
    reset; ROWS="nfs1@nfs1:enabled"
    run "$put" "$(put_input nfs1)"
    chk "$L P2 enabled record kept" "$(nremove)" "0"

    # P3. updating a storage whose record an admin disabled: kept
    reset; existing nfs1; ROWS="nfs1@nfs1:disabled"
    run "$put" "$(put_input nfs1)"
    chk "$L P3 existing storage untouched" "$(nremove)" "0"

    # P4. another storage's disabled record: kept
    reset; ROWS="nfs10@nfs10:disabled nfs@nfs:disabled"
    run "$put" "$(put_input nfs1)"
    chk "$L P4 other records untouched" "$(nremove)" "0"

    # P5. a dotted name is stored with dashes, and so is its record
    reset; ROWS="a-b@a-b:disabled"
    run "$put" "$(put_input a.b)"
    chk "$L P5 dotted name" "$(has "/usr/bin/cinder-manage service remove cinder-volume a-b@a-b")" "yes"

    # P6. not a control node: left to the controls
    reset; ROWS="nfs1@nfs1:disabled"; CTRL=no
    run "$put" "$(put_input nfs1)"
    chk "$L P6 non-control untouched" "$(nremove)" "0"
}

# --- Part A: the functions as they are now ---------------------------------
suite "A" cinder_delete_storage cinder_put_storage

# --- Part C: negative control, the pre-fix functions must fail Part A ------
if old="$(git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_cinder.sh" 2>/dev/null)"; then
    tmp="$(mktemp)"; printf '%s\n' "$old" > "$tmp"
    extract "$tmp" cinder_delete_storage cinder_delete_storage_prefix || { echo "FAIL: pre-fix delete not extracted"; exit 1; }
    extract "$tmp" cinder_put_storage cinder_put_storage_prefix || { echo "FAIL: pre-fix put not extracted"; exit 1; }
    rm -f "$tmp"
    p0=$pass f0=$fail
    suite "C" cinder_delete_storage_prefix cinder_put_storage_prefix >/dev/null
    cfail=$((fail - f0))
    pass=$p0 fail=$f0
    if [ "$cfail" -gt 0 ]; then
        pass=$((pass+1)); echo "negative control: pre-fix functions fail $cfail check(s)"
    else
        fail=$((fail+1)); echo "FAIL: negative control: pre-fix functions pass every check"
    fi
else
    echo "SKIP: negative control ($BASE_REF not in this clone)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
