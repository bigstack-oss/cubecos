#!/bin/bash
#
# Unit test for advisor_targets_discover in ../modules/sdk_advisor.sh -- the
# helper that publishes the app framework's ingress address to the cluster.
#
# The agent runs on every node and dials from every node, but only a node
# holding the app framework's kubeconfig can look the address up. So what
# matters here is the fan-out: every node in CUBE_NODE_LIST_HOSTNAMES must be
# given the address, not just the one this ran on -- that asymmetry is the bug
# this replaced. Only the address crosses a node boundary; no node writes
# another node's allowlist.
#
# Also: a cluster with no ingress address must gain nothing, a cluster that
# never enrolled must not have its local allowlist created as a side effect,
# repeat runs must be harmless, and a locally unset entry must come back on
# the next discover -- that last one is the documented, deliberate exception
# to the never-repair rule (see the comment on advisor_targets_discover).
#
# Self-contained: extracts only the functions under test, and stubs $HEX_SDK
# and remote_run so this needs no app framework, no kubectl and no SSH.
# Run:  bash test_sdk_advisor_discover.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_target_name_valid _advisor_write_file _advisor_targets_write \
         advisor_ingress_set advisor_ingress_address \
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

# Stand-in for remote_run: records "<node> <command...>" instead of ssh'ing,
# so the test can assert exactly which nodes were written to and what with.
REMOTE_LOG=""
REMOTE_RC=0
remote_run()
{
    local node=$1 ; shift
    REMOTE_LOG+="$node|$*"$'\n'
    return $REMOTE_RC
}

nodes_written() { printf '%s' "$REMOTE_LOG" | cut -d'|' -f1 | sort | tr '\n' ' ' ; }

ADVISOR_INGRESS_FILE="$WORK/unused-ingress"

# --- the fan-out: every node in the cluster is given the address -----------
CUBE_NODE_LIST_HOSTNAMES=(sky141 sky142 sky143)
ADVISOR_TARGETS_FILE="$WORK/web-targets.json"
advisor_targets_init >/dev/null
MOCK_INGRESS_ADDR="10.32.1.101"
REMOTE_LOG=""
advisor_targets_discover
check "every node in the cluster was written to" "$(nodes_written)" "sky141 sky142 sky143 "
check "each node was given the address through hex_sdk" \
      "$(printf '%s' "$REMOTE_LOG" | grep -c 'advisor_ingress_set 10\.32\.1\.101$')" "3"
check "no node was handed an allowlist" \
      "$(printf '%s' "$REMOTE_LOG" | grep -c 'web-targets')" "0"

# A single-node cluster is the same code path, one node long.
CUBE_NODE_LIST_HOSTNAMES=(cube1)
REMOTE_LOG=""
advisor_targets_discover
check "a single-node cluster is written to as well" "$(nodes_written)" "cube1 "

# A node that cannot be reached is a warning, not a failure: it picks the
# address up at its next commit.
CUBE_NODE_LIST_HOSTNAMES=(sky141 sky142 sky143)
REMOTE_RC=1
REMOTE_LOG=""
advisor_targets_discover 2>/dev/null
check "an unreachable node does not stop the rest of the fan-out" \
      "$(nodes_written)" "sky141 sky142 sky143 "
REMOTE_RC=0

# --- no ingress address: nothing is published, nothing is added ------------
ADVISOR_TARGETS_FILE="$WORK/no-ingress.json"
advisor_targets_init >/dev/null
before="$(cat "$ADVISOR_TARGETS_FILE")"
MOCK_INGRESS_ADDR=""
REMOTE_LOG=""
advisor_targets_discover
check "no ingress address: no node is written to" "$(nodes_written)" ""
check "no ingress address: the local file is untouched" "$(cat "$ADVISOR_TARGETS_FILE")" "$before"
check "no ingress address: no cube-cmp entry" "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"

# --- the local allowlist: added to when it exists --------------------------
ADVISOR_TARGETS_FILE="$WORK/web-targets.json"
MOCK_INGRESS_ADDR="10.32.1.101"
advisor_targets_discover
check "discover adds cube-cmp" "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "10.32.1.101:443"
check "discover adds app-fw-idp" "$(advisor_targets_list | sed -n 's/^app-fw-idp //p')" "10.32.1.101:443"
check "discover leaves cube-cos alone" "$(advisor_targets_list | sed -n 's/^cube-cos //p')" "127.0.0.1:8080"
check "discover added exactly two entries beyond cube-cos" "$(advisor_targets_list | grep -c .)" "3"

# --- never enrolled: no allowlist is created as a side effect --------------
ADVISOR_TARGETS_FILE="$WORK/never-enrolled.json"
REMOTE_LOG=""
advisor_targets_discover
if [ -e "$ADVISOR_TARGETS_FILE" ] ; then
    bad "discover created the allowlist file although none existed"
else
    ok
fi
check "the address is published even so" "$(nodes_written)" "sky141 sky142 sky143 "

# --- running discover twice is idempotent -----------------------------------
ADVISOR_TARGETS_FILE="$WORK/idempotent.json"
advisor_targets_init >/dev/null
advisor_targets_discover
first="$(advisor_targets_list | sort)"
advisor_targets_discover
second="$(advisor_targets_list | sort)"
check "a second discover changes nothing" "$second" "$first"
check "a second discover still leaves exactly one cube-cmp entry" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "1"

# --- a locally unset entry comes back after discover ------------------------
# Deliberate: this is an install/enrolment event declaring the endpoint
# again, not a startup or a commit silently repairing a file.
advisor_targets_unset cube-cmp
check "cube-cmp is gone after an operator unset" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"
advisor_targets_discover
check "cube-cmp comes back after the next discover" \
      "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "10.32.1.101:443"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
