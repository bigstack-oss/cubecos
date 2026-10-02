#!/bin/bash
#
# Unit test for cinder_put_storage (../modules/sdk_cinder.sh) when writing an
# extra config file fails (#1531).
#
# Each extra config file of an external storage (an NFS backend's shares file,
# a Fujitsu backend's XML) is written by cinder_write_storage_extra_config_file
# inside a loop. The loop tested $ret without capturing the call's status into
# it, so $ret still held the 0 of the ownership write before the loop: a failed
# write went unnoticed, the backend was applied without the file its driver
# section points at, and the caller was told "storage <name> created".
#
# The suite runs the real capture helpers (_hex_function keeps a command's own
# exit status, which a stub would flatten) and the real json helpers; every
# function that touches the node is stubbed. Part C runs the same assertions
# against the function as it was before the fix, to prove they catch it.
#
#   Run: bash test_cinder_put_storage_extra_config.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_cinder.sh"

# The commit the function looked like before the fix. Pinned to an object, not
# to a branch, so the negative control cannot turn green against itself.
BASE_REF=ebda9261937a7099d994dc4c21dcbbe3d0ee95bf

extract() {  # <file> <function> [rename-to]
    local body
    body="$(awk -v n="^$2\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$1")"
    [ -n "$body" ] || return 1
    [ -z "${3:-}" ] || body="${body/#$2()/$3()}"
    eval "$body"
    [ "$(type -t "${3:-$2}")" = function ]
}

extract "$SRC" cinder_put_storage || { echo "FAIL: cinder_put_storage not extracted"; exit 1; }
PROG=test_cinder_put_storage_extra_config
for f in _hex_function _hex_function_ret ; do
    extract "$DIR/../../main/proj_functions" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
for f in json_get_value json_get_compact_value json_is_array ; do
    extract "$DIR/../modules.pre/sdk_json.sh" "$f" || { echo "FAIL: $f not extracted"; exit 1; }
done
extract "$DIR/../modules.pre/sdk_is.sh" is_valid_json || { echo "FAIL: is_valid_json not extracted"; exit 1; }
eval "$(grep -E '^ERROR_(CINDER|JSON)_[A-Z_]+=' "$SRC" "$DIR/../modules.pre/sdk_json.sh" | cut -d: -f2-)"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# --- stubs: everything that would touch the node ---------------------------
WRITE_EXTRA_RC=0
APPLIED=""
cinder_get_storage_name() { echo -n "$1"; }
cinder_marshal_storage_external_backend_conf() { echo "[$2]"; }
cinder_write_storage_external_backend_conf() { return 0; }
cinder_marshal_storage_extra_configs_ownership() { echo '{}'; }
cinder_write_storage_extra_configs_ownership() { return 0; }
cinder_get_storage_extra_config_file_unique_name() { echo -n "${1}_${2}"; }
cinder_write_storage_extra_config_file() { return "$WRITE_EXTRA_RC"; }
cinder_apply_storage_creation() { APPLIED="$1"; return 0; }
cinder_set_volume_type_properties() { return 0; }

INPUT='{"name":"nfs01","driver":"cinder.volume.drivers.nfs.NfsDriver","isDefault":false,
"storage":{"service":{"driverSection":[],"extraSettings":[],
"extraConfigFiles":[{"name":"nfs_shares","content":"MTAuMC4wLjE6L2V4cG9ydAo="}]},
"volumeType":{"settings":[]},"image":{"useMultipath":true,"forceMultipath":true}}}'

run() {  # <function> -> sets RC, ERR, APPLIED
    local fn="$1" errf
    APPLIED=""
    errf="$(mktemp)"
    "$fn" "$INPUT" >/dev/null 2>"$errf"
    RC=$?
    ERR="$(cat "$errf")"
    rm -f "$errf"
}

suite() {  # <label> <function>
    WRITE_EXTRA_RC=1
    run "$2"
    chk "$1 failed write: return code" "$RC" "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_FAILED"
    chk "$1 failed write: stderr" "$ERR" '{"message":"failed to write the storage extra config files"}'
    chk "$1 failed write: backend not applied" "$APPLIED" ""

    WRITE_EXTRA_RC=0
    run "$2"
    chk "$1 good write: return code" "$RC" "0"
    chk "$1 good write: backend applied" "$APPLIED" "nfs01"
}

# --- Part A: the function as it is now -------------------------------------
suite "A" cinder_put_storage

# --- Part C: negative control, the pre-fix function must fail Part A -------
if old="$(git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_cinder.sh" 2>/dev/null)"; then
    tmp="$(mktemp)"; printf '%s\n' "$old" > "$tmp"
    extract "$tmp" cinder_put_storage cinder_put_storage_prefix || { echo "FAIL: pre-fix function not extracted"; exit 1; }
    rm -f "$tmp"
    p0=$pass f0=$fail
    suite "C" cinder_put_storage_prefix >/dev/null
    if [ $((fail - f0)) -gt 0 ]; then
        pass=$((p0 + 1)); fail=$f0
    else
        pass=$p0; fail=$((f0 + 1)); echo "FAIL: C: the pre-fix function passed; the suite does not catch the bug"
    fi
else
    echo "SKIP: C: $BASE_REF not reachable (no git repo here)"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
