#!/bin/bash
#
# Unit test for app_helm_release_deployed in ../modules/sdk_app.sh -- true
# when a named Helm release is deployed on the app framework cluster.
#
# This is how the Advisor's discovery answers "is this installed", so what
# matters is that it is exact (a release with another name, or one that is not
# deployed, is a no) and that every way it can come back empty -- no
# kubeconfig, no helm, a helm that errors -- is a clean no, never a hang or
# stderr spew: its caller is on an installer's path and must not fail.
#
# Self-contained: extracts only the function under test and runs it against a
# fake helm on PATH, so this needs no app framework and no cluster.
# Run:  bash test_sdk_app_helm_release.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_app.sh"

for f in app_helm_release_deployed ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }

yes_it_is() { if app_helm_release_deployed "$1" 2>"$WORK/err" ; then ok ; else bad "$2" ; fi ; }
no_it_is_not() { if app_helm_release_deployed "$1" 2>"$WORK/err" ; then bad "$2" ; else ok ; fi ; }
quiet() { [ -s "$WORK/err" ] && bad "$1: wrote to stderr: $(cat "$WORK/err")" || ok ; }

REAL_PATH=$PATH
mkdir -p "$WORK/bin"
# Fake helm: prints $MOCK_HELM_OUT and exits $MOCK_HELM_RC, whatever the real
# args were -- this is testing the function's own logic, not helm's.
cat > "$WORK/bin/helm" <<'EOF'
#!/bin/bash
printf '%s' "${MOCK_HELM_OUT:-}"
exit "${MOCK_HELM_RC:-0}"
EOF
chmod +x "$WORK/bin/helm"

KUBECONFIG_FILE="$WORK/kubeconfig"
APPFW_KUBECONFIG="$KUBECONFIG_FILE"
: > "$KUBECONFIG_FILE"
PATH="$WORK/bin:$REAL_PATH"

# --- a cluster with the app framework and CMP on it -------------------------
export MOCK_HELM_RC=0
export MOCK_HELM_OUT='[{"name":"keycloak","namespace":"app-fw","status":"deployed"},
                       {"name":"cube-portal","namespace":"cmp","status":"deployed"}]'
yes_it_is keycloak    "keycloak deployed was not recognised"
yes_it_is cube-portal "cube-portal deployed was not recognised"
no_it_is_not cube-cmp "a release that is not on the cluster was reported as deployed"
quiet "a normal lookup"

# --- the app framework only: CMP's release is simply not there --------------
# The state this exists to tell apart from the one above; the ingress address
# is identical in both.
export MOCK_HELM_OUT='[{"name":"keycloak","namespace":"app-fw","status":"deployed"}]'
yes_it_is keycloak       "keycloak was not recognised with CMP absent"
no_it_is_not cube-portal "cube-portal was reported deployed with only the framework installed"

# --- a release that is there but not deployed -------------------------------
# A failed or half-removed install must not count as installed.
export MOCK_HELM_OUT='[{"name":"cube-portal","namespace":"cmp","status":"pending-install"}]'
no_it_is_not cube-portal "a pending-install release was reported as deployed"
export MOCK_HELM_OUT='[{"name":"cube-portal","namespace":"cmp","status":"failed"}]'
no_it_is_not cube-portal "a failed release was reported as deployed"

# --- nothing installed at all -----------------------------------------------
export MOCK_HELM_OUT='[]'
no_it_is_not keycloak "an empty release list was read as deployed"

# --- an empty name ----------------------------------------------------------
export MOCK_HELM_OUT='[{"name":"keycloak","namespace":"app-fw","status":"deployed"}]'
no_it_is_not "" "an empty release name was accepted"

# --- helm fails or answers with something that is not JSON ------------------
export MOCK_HELM_RC=1 MOCK_HELM_OUT=''
no_it_is_not keycloak "a helm failure was read as deployed"
quiet "a helm failure"
export MOCK_HELM_RC=0 MOCK_HELM_OUT='Error: Kubernetes cluster unreachable'
no_it_is_not keycloak "output that is not JSON was read as deployed"
quiet "output that is not JSON"

# --- no helm on PATH: a clean no, silently ----------------------------------
export MOCK_HELM_RC=0
export MOCK_HELM_OUT='[{"name":"keycloak","namespace":"app-fw","status":"deployed"}]'
PATH="/usr/bin:/bin"
no_it_is_not keycloak "a node with no helm reported a release as deployed"
quiet "a node with no helm"
PATH="$WORK/bin:$REAL_PATH"

# --- no kubeconfig: the normal answer on most nodes, so also silent ---------
rm -f "$KUBECONFIG_FILE"
no_it_is_not keycloak "a node with no kubeconfig reported a release as deployed"
quiet "a node with no kubeconfig"

# --- the variable never set at all: still clean under set -u ----------------
unset APPFW_KUBECONFIG
no_it_is_not keycloak "an unset kubeconfig path reported a release as deployed"
quiet "an unset kubeconfig path"

PATH=$REAL_PATH

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
