#!/bin/bash
#
# Unit test for advisor_targets_discover in ../modules/sdk_advisor.sh -- the
# helper that adds the cube-cmp and app-fw-idp targets behind the app
# framework's ingress, so an operator does not have to type them in by hand.
#
# What matters here: a cluster that never enrolled must gain no file at all,
# a cluster with no ingress address must gain no entries, repeat runs must be
# harmless, and an operator-removed entry must come back on the next
# discover -- that last one is the documented, deliberate exception to the
# never-repair rule (see the comment on advisor_targets_discover itself).
#
# Self-contained: extracts only the functions under test, and stubs
# $HEX_SDK so this needs no app framework and no kubectl.
# Run:  bash test_sdk_advisor_discover.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_target_name_valid _advisor_targets_write \
         advisor_targets_init advisor_targets_list advisor_targets_set \
         advisor_targets_unset advisor_targets_discover ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

# Stand-in for $HEX_SDK: a real cluster would exec `hex_sdk app_ingress_address`
# in another module; this just answers from a variable so no app framework
# and no kubectl are needed.
MOCK_INGRESS_ADDR=""
mock_hex_sdk()
{
    case "$1" in
        app_ingress_address)
            [ -n "$MOCK_INGRESS_ADDR" ] || return 1
            echo "$MOCK_INGRESS_ADDR"
            ;;
        *) return 1 ;;
    esac
}
HEX_SDK=mock_hex_sdk

# --- no allowlist file: discover must do nothing, and create no file -------
ADVISOR_TARGETS_FILE="$WORK/never-enrolled.json"
MOCK_INGRESS_ADDR="10.32.1.101"
advisor_targets_discover
if [ -e "$ADVISOR_TARGETS_FILE" ] ; then
    bad "discover created the allowlist file although none existed"
else
    ok
fi

# --- allowlist present + an ingress address: both names get added ----------
ADVISOR_TARGETS_FILE="$WORK/web-targets.json"
advisor_targets_init >/dev/null
MOCK_INGRESS_ADDR="10.32.1.101"
advisor_targets_discover
check "discover adds cube-cmp" "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "10.32.1.101:443"
check "discover adds app-fw-idp" "$(advisor_targets_list | sed -n 's/^app-fw-idp //p')" "10.32.1.101:443"
check "discover leaves dashboard alone" "$(advisor_targets_list | sed -n 's/^dashboard //p')" "127.0.0.1:8080"
check "discover added exactly two entries beyond dashboard" "$(advisor_targets_list | grep -c .)" "3"

# --- no ingress address: nothing added, existing entries untouched ---------
ADVISOR_TARGETS_FILE="$WORK/no-ingress.json"
advisor_targets_init >/dev/null
before="$(cat "$ADVISOR_TARGETS_FILE")"
MOCK_INGRESS_ADDR=""
advisor_targets_discover
check "no ingress address: file is untouched" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"
check "no ingress address: no cube-cmp entry" "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"

# --- running discover twice is idempotent -----------------------------------
ADVISOR_TARGETS_FILE="$WORK/idempotent.json"
advisor_targets_init >/dev/null
MOCK_INGRESS_ADDR="10.32.1.101"
advisor_targets_discover
first="$(advisor_targets_list | sort)"
advisor_targets_discover
second="$(advisor_targets_list | sort)"
check "a second discover changes nothing" "$second" "$first"
check "a second discover still leaves exactly one cube-cmp entry" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "1"

# --- an operator-removed entry comes back after discover --------------------
# Deliberate: this is an install/enrolment event declaring the endpoint
# again, not a startup silently repairing a deleted file.
advisor_targets_unset cube-cmp
check "cube-cmp is gone after an operator unset" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"
advisor_targets_discover
check "cube-cmp comes back after the next discover" \
      "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "10.32.1.101:443"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
