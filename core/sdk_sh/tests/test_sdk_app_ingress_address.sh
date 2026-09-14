#!/bin/bash
#
# Unit test for app_ingress_address in ../modules/sdk_app.sh -- prints the
# app framework's ingress LoadBalancer address, or nothing (non-zero) if
# there is none.
#
# What matters here is that every way this can come back empty -- no
# kubeconfig, no kubectl, no Service, an empty address -- comes back clean,
# never a hang or stderr spew, since this is on the path of two callers that
# must not fail (advisor_enroll, app_framework_install).
#
# Self-contained: extracts only the function under test and runs it against
# a fake kubectl on PATH, so this needs no app framework and no cluster.
# Run:  bash test_sdk_app_ingress_address.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_app.sh"

for f in app_ingress_address ; do
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

REAL_PATH=$PATH

mkdir -p "$WORK/bin"
# Fake kubectl: prints $MOCK_KUBECTL_OUT and exits $MOCK_KUBECTL_RC, whatever
# the real args were -- this is testing app_ingress_address's own logic
# (kubeconfig/kubectl presence, empty-address handling), not kubectl's.
cat > "$WORK/bin/kubectl" <<'EOF'
#!/bin/bash
printf '%s' "${MOCK_KUBECTL_OUT:-}"
exit "${MOCK_KUBECTL_RC:-0}"
EOF
chmod +x "$WORK/bin/kubectl"

KUBECONFIG_FILE="$WORK/kubeconfig"
APPFW_KUBECONFIG="$KUBECONFIG_FILE"

# --- no kubeconfig at all: clean refusal, no output -------------------------
# Only one node of a cluster holds the kubeconfig, so this is the normal
# answer on most nodes, not a fault -- it must stay silent.
rm -f "$KUBECONFIG_FILE"
PATH="$WORK/bin:$REAL_PATH"
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "no kubeconfig: prints nothing" "$out" ""
[ $rc -ne 0 ] && ok || bad "no kubeconfig: exit was 0"
check "no kubeconfig: nothing on stderr" "$(cat "$WORK/err")" ""

# --- the variable never set at all: still a clean refusal under set -u ------
# Callers run under set -u, and a node with no app framework never sources a
# path for one; an unbound-variable error here would be noise on every node.
unset APPFW_KUBECONFIG
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "unset kubeconfig path: prints nothing" "$out" ""
[ $rc -ne 0 ] && ok || bad "unset kubeconfig path: exit was 0"
check "unset kubeconfig path: nothing on stderr" "$(cat "$WORK/err")" ""
APPFW_KUBECONFIG="$KUBECONFIG_FILE"

# --- kubeconfig present, kubectl absent from PATH: clean refusal -----------
: > "$KUBECONFIG_FILE"
PATH="/usr/bin:/bin"
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "kubectl absent: prints nothing" "$out" ""
[ $rc -ne 0 ] && ok || bad "kubectl absent: exit was 0"
check "kubectl absent: nothing on stderr" "$(cat "$WORK/err")" ""

# --- kubeconfig + kubectl present, Service found: prints the address -------
: > "$KUBECONFIG_FILE"
PATH="$WORK/bin:$REAL_PATH"
export MOCK_KUBECTL_OUT="10.32.1.101" MOCK_KUBECTL_RC=0
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "address found: prints it" "$out" "10.32.1.101"
[ $rc -eq 0 ] && ok || bad "address found: exit was non-zero"

# --- kubectl present but the Service does not exist: empty jsonpath --------
export MOCK_KUBECTL_OUT="" MOCK_KUBECTL_RC=0
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "no ingress-lb Service: prints nothing" "$out" ""
[ $rc -ne 0 ] && ok || bad "no ingress-lb Service: exit was 0"

# --- kubectl errors out (e.g. unreachable API server): clean refusal -------
export MOCK_KUBECTL_OUT="" MOCK_KUBECTL_RC=1
out="$(app_ingress_address 2>"$WORK/err")"; rc=$?
check "kubectl failure: prints nothing" "$out" ""
[ $rc -ne 0 ] && ok || bad "kubectl failure: exit was 0"
check "kubectl failure: nothing on stderr" "$(cat "$WORK/err")" ""

PATH=$REAL_PATH

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
