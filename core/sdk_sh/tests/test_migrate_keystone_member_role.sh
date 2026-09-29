#!/bin/bash
#
# Unit test for the keystone implied-role chain repair:
#   migrate_keystone_member_role         -- ../modules/sdk_migrate.sh
#   os_keystone_legacy_member_role_setup -- ../modules/sdk_os.sh
#
# The regression that matters: the chain repair's only caller ran on a first install
# alone, so cube36 came through the 3.1.10 -> 3.1.20 roll with no member, no manager and
# an empty implied_role table, and every caracal default keyed on role:member denied admin
# (#631/#632/#635/#645). The migration must repair that state, create the missing default
# roles immutable (keystone-status upgrade check fails a mutable admin/member/reader), and
# write its marker only once all four edges read back -- an unreachable keystone retries.
#
# Self-contained: extracts the two functions and stubs openstack, hex_sdk and
# is_control_node, so it needs no cluster.  Run: bash test_migrate_keystone_member_role.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract() {
    local name=$1 src=$2 fn
    fn="$(awk -v n="^$name\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$src")"
    [ -n "$fn" ] || { echo "FAIL: $name not found in $src"; exit 1; }
    eval "$fn"
}

extract migrate_keystone_member_role "$DIR/../modules/sdk_migrate.sh"
extract os_keystone_legacy_member_role_setup "$DIR/../modules/sdk_os.sh"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture: a keystone with ROLES and EDGES ("prior implied") ----------
# The migration runs the setup in a $(...) subshell, so what the stubs do is logged to a
# file rather than kept in variables.
declare -A ROLES
EDGES="" DOWN=0 ROLE=control
STATE_DIR=$(mktemp -d)
LOG=$(mktemp)

reset() {
    ROLES=() ; EDGES="" ; DOWN=0 ; ROLE=control
    : > "$LOG"
    rm -f "$STATE_DIR/keystone_member_role_migrated"
    local r ; for r in $1 ; do ROLES[$r]=1 ; done
    EDGES="$2"
}

openstack_stub() {
    [ $DOWN -eq 1 ] && return 1
    case "$*" in
        "role show "*)
            [ -n "${ROLES[$3]:-}" ] ;;
        "role create --immutable "*)
            ROLES[$4]=1 ; echo "role:$4" >> "$LOG" ;;
        "role create "*)
            ROLES[$3]=1 ; echo "mutable:$3" >> "$LOG" ;;
        "implied role list -f value")
            local e
            while read -r e ; do
                [ -n "$e" ] && echo "id-${e% *} ${e% *} id-${e#* } ${e#* }"
            done <<< "$EDGES" ;;
        "implied role create "*" --implied-role "*)
            [ -n "${ROLES[$4]:-}" ] && [ -n "${ROLES[$6]:-}" ] || return 1
            EDGES="$EDGES"$'\n'"$4 $6" ; echo "edge:$4>$6" >> "$LOG" ;;
        *) echo "unexpected openstack $*" >&2 ; return 1 ;;
    esac
}
OPENSTACK=openstack_stub
Quiet() { [ "$1" = "-n" ] && shift ; "$@" >/dev/null 2>&1 ; }
hex_sdk_stub() { echo "hex_sdk:$1" >> "$LOG" ; "$@" ; }
HEX_SDK=hex_sdk_stub
is_control_node() { [ "$ROLE" = control ] ; }
log_error() { : ; }
marked() { [ -f "$STATE_DIR/keystone_member_role_migrated" ] && echo y || echo n ; }
creates() { grep -v '^hex_sdk:' "$LOG" | tr '\n' ' ' ; }
setups() { grep -c '^hex_sdk:os_keystone_legacy_member_role_setup$' "$LOG" ; }

run() { migrate_keystone_member_role ; rc=$? ; }

# 1. cube36 after the roll: yoga-era roles, member deleted, no manager, no edges
reset "_member_ admin reader service" ""
run
chk "1 rc"          "$rc"        "0"
chk "1 marked"      "$(marked)"  "y"
chk "1 creates"     "$(creates)" "role:manager role:member edge:admin>manager edge:manager>member edge:member>reader edge:_member_>member "
run
chk "1 no re-run"   "$(setups)"  "1"

# 2. fresh install: bootstrap's chain is there, only the bridge is missing
reset "_member_ admin manager member reader service" \
      "admin manager"$'\n'"manager member"$'\n'"member reader"
run
chk "2 marked"      "$(marked)"  "y"
chk "2 creates"     "$(creates)" "edge:_member_>member "

# 3. keystone unreachable: nothing marked, the next commit retries and completes
reset "_member_ admin reader service" ""
DOWN=1
run
chk "3 rc"          "$rc"        "1"
chk "3 not marked"  "$(marked)"  "n"
DOWN=0
run
chk "3 retried"     "$(setups)"  "2"
chk "3 marked"      "$(marked)"  "y"

# 4. one edge cannot be created (no _member_ role): the chain is incomplete, not marked
reset "admin reader service" ""
run
chk "4 rc"          "$rc"        "1"
chk "4 not marked"  "$(marked)"  "n"

# 5. compute node: never touches keystone
reset "_member_ admin reader service" ""
ROLE=compute
run
chk "5 rc"          "$rc"        "0"
chk "5 no setup"    "$(setups)"  "0"
chk "5 not marked"  "$(marked)"  "n"

rm -rf "$STATE_DIR" "$LOG"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: migrate_keystone_member_role" ; exit 0 ; } || exit 1
