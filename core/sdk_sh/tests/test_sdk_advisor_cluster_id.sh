#!/bin/bash
#
# Unit test for advisor_cluster_id in ../modules/sdk_advisor.sh -- names the
# cluster this node belongs to.
#
# The certificate fallback exists because both earlier sources can be absent at
# once on a real node: phone-home-agent.env is written at deployment and does
# not survive a firmware upgrade, and cubesys.controller is not set on a
# converged single-node cluster. Observed on the 1cc r630 after an upgrade --
# an enrolled node, still running its agent, could not say which cluster it
# was, so re-enrolment failed before it started.
#
# Ordering is the part worth pinning: the certificate records what this node
# enrolled as *once*, while the other two describe what it belongs to *now*,
# so it must be consulted last and never override them.
#
# Run:  bash test_sdk_advisor_cluster_id.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in advisor_cluster_id ; do
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

# A certificate carrying OU=<cluster>, CN=<node>, exactly as enrolment issues.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj "/OU=cert-cluster/CN=cube-combined" \
  -keyout "$WORK/agent.key" -out "$WORK/agent.crt" 2>/dev/null
ADVISOR_AGENT_CERT="$WORK/agent.crt"

# advisor_cluster_id reads these two paths directly, so point them at fixtures
# by overriding the readers the function uses.
export PATH="$WORK/bin:$PATH"
mkdir -p "$WORK/bin"

# --- the certificate answers when nothing else can ---------------------
# Both earlier sources absent: no phone-home env (the path below does not
# exist) and hex_tuning yields no controller.
cat > "$WORK/bin/hex_tuning" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$WORK/bin/hex_tuning"

out=$( (
  # shadow the absolute paths the function reads by running in a subshell where
  # they cannot exist; only the certificate is reachable.
  advisor_cluster_id 2>&1
) )
rc=$?
check "cert fallback: exit zero" "$rc" "0"
check "cert fallback: reads OU from the certificate" "$out" "cert-cluster"

# --- an unreadable certificate is not a crash --------------------------
ADVISOR_AGENT_CERT="$WORK/nope.crt"
out=$(advisor_cluster_id 2>&1); rc=$?
check "no sources at all: exit non-zero" "$rc" "1"
case "$out" in *"no enrolled identity"*) ok ;; *) bad "no sources: message does not mention the identity: $out" ;; esac

# --- a file that is not a certificate is not an id ---------------------
echo "not a certificate" > "$WORK/junk.crt"
ADVISOR_AGENT_CERT="$WORK/junk.crt"
out=$(advisor_cluster_id 2>&1); rc=$?
check "junk certificate: exit non-zero" "$rc" "1"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
