#!/bin/bash
#
# Unit test for app_kubeconfig in ../modules/sdk_app.sh -- fetches the app
# framework's kubeconfig from rancher and prints its path.
#
# This function exists because the helpers beside it used to read a fixed path,
# /opt/appfw/kubeconfig, that nothing on a control node ever creates: both were
# gated on a file that never existed, so they answered "no framework" on a
# perfectly healthy cluster and the discovery they feed never ran. The cases
# below are the ones that silence mattered for -- no rancher, no framework, a
# rancher that returns nothing -- plus the two that must work: a framework
# named by the caller, and one read back from rancher.
#
# Self-contained: extracts only the function under test and runs it against a
# fake rancher and a fake sudo on PATH, so this needs no cluster.
# Run:  bash test_sdk_app_kubeconfig.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_app.sh"

for f in app_kubeconfig ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()    { pass=$((pass+1)); }
bad()   { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

mkdir -p "$WORK/bin"
# sudo that just runs what it was given: the real one is not available to a
# test, and what is under test is the rancher call, not the escalation.
cat > "$WORK/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
# Fake rancher: `cluster ls` prints $MOCK_CLUSTERS, `cluster kf <name>` prints
# $MOCK_KF and records the name it was asked for.
cat > "$WORK/bin/rancher" <<'EOF'
#!/bin/bash
case "$1 $2" in
    "cluster ls") printf '%s' "$MOCK_CLUSTERS" ;;
    "cluster kf") echo "$3" > "$MOCK_KF_ARG_FILE"; printf '%s' "$MOCK_KF" ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/sudo" "$WORK/bin/rancher"
PATH="$WORK/bin:$PATH"

APPFW_RANCHER="$WORK/bin/rancher"
MOCK_KF_ARG_FILE="$WORK/kf-arg"
export MOCK_CLUSTERS MOCK_KF MOCK_KF_ARG_FILE

# --- no rancher CLI: quiet refusal, not an error on stderr ---------------
APPFW_RANCHER="$WORK/bin/does-not-exist"
out=$(app_kubeconfig 2>"$WORK/err"); rc=$?
check "no rancher: exit non-zero" "$rc" "1"
check "no rancher: prints nothing" "$out" ""
check "no rancher: says nothing on stderr" "$(cat "$WORK/err")" ""
APPFW_RANCHER="$WORK/bin/rancher"

# --- rancher knows only its own "local" cluster: no framework -----------
MOCK_CLUSTERS=$'local\n'
MOCK_KF="apiVersion: v1"
out=$(app_kubeconfig 2>/dev/null); rc=$?
check "only local: exit non-zero" "$rc" "1"
check "only local: prints nothing" "$out" ""

# --- a framework is present: its name is read back, not assumed ----------
# Deliberately not "app-framework": the installer chooses the name, and the
# driver's installs are named "appfw".
MOCK_CLUSTERS=$'appfw\nlocal\n'
MOCK_KF=$'apiVersion: v1\nkind: Config\n'
out=$(app_kubeconfig 2>/dev/null); rc=$?
check "framework found: exit zero" "$rc" "0"
if [ -n "$out" ] && [ -s "$out" ] ; then ok ; else bad "framework found: no kubeconfig at '$out'"; fi
check "framework found: asked rancher for that name" "$(cat "$MOCK_KF_ARG_FILE")" "appfw"
check "framework found: file holds what rancher printed" "$(head -1 "$out")" "apiVersion: v1"
check "framework found: kubeconfig is not world-readable" "$(stat -c %a "$out")" "600"
rm -f "$out"

# --- an explicit name wins over what rancher lists first -----------------
MOCK_CLUSTERS=$'appfw\nlocal\n'
out=$(app_kubeconfig other-fw 2>/dev/null); rc=$?
check "explicit name: exit zero" "$rc" "0"
check "explicit name: asked rancher for it" "$(cat "$MOCK_KF_ARG_FILE")" "other-fw"
rm -f "$out"

# --- rancher authenticates but returns nothing --------------------------
# An empty kubeconfig is worse than none: kubectl reports it as a parse error
# rather than "no framework", so this must refuse and leave no file behind.
MOCK_CLUSTERS=$'appfw\nlocal\n'
MOCK_KF=""
before=$(ls "${TMPDIR:-/tmp}" | grep -c '^appfw-kubeconfig\.' || true)
out=$(app_kubeconfig 2>/dev/null); rc=$?
after=$(ls "${TMPDIR:-/tmp}" | grep -c '^appfw-kubeconfig\.' || true)
check "empty kubeconfig: exit non-zero" "$rc" "1"
check "empty kubeconfig: prints nothing" "$out" ""
check "empty kubeconfig: leaves no file behind" "$after" "$before"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
