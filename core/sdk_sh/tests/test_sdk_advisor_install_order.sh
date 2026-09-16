#!/bin/bash
#
# Unit test for the order a real cluster actually does these things in:
# app framework first, CMP second, enrolment whenever the operator gets to it
# -- usually long after both.
#
# Each half is covered elsewhere (test_sdk_advisor_discover.sh for publishing,
# test_sdk_advisor_targets.sh for seeding). Nothing pinned the sequence, and
# the sequence is where this can silently go wrong: discovery runs while there
# is no allowlist to add to, so the only thing that carries cube-cmp to
# enrolment is the discovered-set file being written *before* discover returns
# at the "this cluster never enrolled" guard. Put that write below the guard
# and every assertion after enrolment here fails.
#
# Three nodes, because that is where it broke before: only one node holds the
# kubeconfig, so the other two can only ever learn what is installed from what
# that node published to them.
#
# Self-contained: extracts only the functions under test, and stubs $HEX_SDK
# and remote_run. remote_run is not a recorder here -- it runs the real
# advisor_discovered_set against the target node's own file, so the fan-out
# leaves the files a real cluster would be left holding.
# Run:  bash test_sdk_advisor_install_order.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_target_name_valid _advisor_target_address_valid \
         _advisor_write_file _advisor_targets_write \
         advisor_discovered_set advisor_discovered_list \
         advisor_targets_init advisor_targets_list advisor_targets_set \
         advisor_targets_unset advisor_targets_discover \
         _advisor_discard_kubeconfig ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

# The dashboard address comes from this node's settings, which a unit test has
# none of. Stubbed to a fixed value: what these cases check is what gets seeded,
# not how the address is discovered.
advisor_dashboard_address() { echo "10.0.0.1:443"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

CUBE_NODE_LIST_HOSTNAMES=(sky141 sky142 sky143)
INGRESS=10.32.1.101

# Which node's files the extracted helpers are looking at. A real cluster has
# one set of paths per node; this test moves between three of them.
on_node()
{
    ADVISOR_DISCOVERED_FILE="$WORK/$1/discovered-targets"
    ADVISOR_TARGETS_FILE="$WORK/$1/web-targets.json"
}

MOCK_RELEASES=""
mock_hex_sdk()
{
    case "$1" in
        app_kubeconfig)
            # The real one fetches from rancher; the test only needs a path
            # that exists, since the helpers it feeds are stubbed here too.
            MOCK_KUBECONFIG="$WORK/kubeconfig.$$"
            : > "$MOCK_KUBECONFIG"
            echo "$MOCK_KUBECONFIG"
            ;;
        app_ingress_address) echo "$INGRESS" ;;
        app_helm_release_deployed)
            case " $MOCK_RELEASES " in
                *" $2 "*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}
HEX_SDK=mock_hex_sdk

# Runs the published command on the named node, against that node's own file,
# the way ssh would. The command is a string: the $HEX_SDK the caller put in
# front of it, then the helper and its arguments.
remote_run()
{
    local node=$1 here=$ADVISOR_DISCOVERED_FILE rc
    shift
    set -- $*
    shift
    ADVISOR_DISCOVERED_FILE="$WORK/$node/discovered-targets"
    "$@"
    rc=$?
    ADVISOR_DISCOVERED_FILE=$here
    return $rc
}

# The installers, as far as the Advisor is concerned: each one installs
# something and then declares whatever is installed by then. Both run on the
# node holding the kubeconfig.
app_framework_install()
{
    MOCK_RELEASES="keycloak"
    on_node sky141
    advisor_targets_discover
}

app_import_cmp()
{
    MOCK_RELEASES="keycloak cube-portal"
    on_node sky141
    advisor_targets_discover
}

# ---- the install order: framework, then CMP, with nobody enrolled ----------
app_framework_install
app_import_cmp

# Nothing may have gained an allowlist: this cluster has never enrolled, and
# an install is not an enrolment.
for node in sky141 sky142 sky143 ; do
    if [ -e "$WORK/$node/web-targets.json" ] ; then
        bad "$node gained an allowlist from an install alone"
    else
        ok
    fi
done

# ... but every node must be holding the discovered set, or enrolment later
# has nothing to seed cube-cmp from.
for node in sky141 sky142 sky143 ; do
    on_node "$node"
    check "$node holds the discovered set after both installs" \
          "$(advisor_discovered_list | sort | tr '\n' ' ')" \
          "app-fw-idp $INGRESS:443 cube-cmp $INGRESS:443 "
done

# ---- enrolment, afterwards ------------------------------------------------
# advisor_enroll seeds the node it ran on; every other node seeds itself at
# its next hex_config commit. Both are advisor_targets_init.
on_node sky141
advisor_targets_init
for node in sky142 sky143 ; do
    on_node "$node"
    advisor_targets_init
done

for node in sky141 sky142 sky143 ; do
    on_node "$node"
    check "$node allows cube-cos" "$(advisor_targets_list | sed -n 's/^cube-cos //p')" "10.0.0.1:443"
    check "$node allows cube-cmp" "$(advisor_targets_list | sed -n 's/^cube-cmp //p')" "$INGRESS:443"
    check "$node allows app-fw-idp" "$(advisor_targets_list | sed -n 's/^app-fw-idp //p')" "$INGRESS:443"
    check "$node allows exactly those three" "$(advisor_targets_list | grep -c .)" "3"
done

# ---- and the operator still has the last word ------------------------------
# Enrolment is over; from here a removed target stays removed, however many
# commits run.
on_node sky143
advisor_targets_unset cube-cmp
advisor_targets_init
check "a target the operator unset after enrolment stays unset" \
      "$(advisor_targets_list | grep -c '^cube-cmp ')" "0"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
