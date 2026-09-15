#!/bin/bash
#
# Unit test for advisor_trust_ca in ../modules/sdk_advisor.sh -- installs the
# Advisor's CA into the node's system trust store before enrolment touches the
# network.
#
# It exists because enrolment fetches the release with curl and then runs the
# agent, which uses Go's TLS: both read the system store, neither takes a CA
# path, and an Advisor serving its own certificate (the normal case offline) is
# unreachable to both. The cases below are the ones where getting it wrong is
# silent -- a file that is not a certificate, a trust store that fails to
# rebuild -- plus the one that must stay free: no CA given at all.
#
# Self-contained: extracts only the function under test and points it at a
# temporary anchor path with a fake update-ca-trust on PATH.
# Run:  bash test_sdk_advisor_trust_ca.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in advisor_trust_ca ; do
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

ADVISOR_TRUST_ANCHOR="$WORK/anchors/cube-advisor.crt"
mkdir -p "$WORK/anchors" "$WORK/bin"

cat > "$WORK/bin/update-ca-trust" <<'EOF'
#!/bin/bash
exit ${MOCK_UPDATE_RC:-0}
EOF
chmod +x "$WORK/bin/update-ca-trust"
PATH="$WORK/bin:$PATH"
export MOCK_UPDATE_RC=0

# A real certificate to install.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=test-advisor" \
  -keyout "$WORK/ca.key" -out "$WORK/ca.crt" 2>/dev/null

# --- no CA given: a no-op success, not a refusal ----------------------
# Enrolment against an Advisor whose certificate already verifies must not
# require this argument at all.
out=$(advisor_trust_ca "" 2>&1); rc=$?
check "no CA: exit zero" "$rc" "0"
if [ -e "$ADVISOR_TRUST_ANCHOR" ] ; then bad "no CA: installed an anchor anyway"; else ok; fi

# --- unreadable path --------------------------------------------------
out=$(advisor_trust_ca "$WORK/nope.crt" 2>&1); rc=$?
check "missing file: exit non-zero" "$rc" "1"
case "$out" in *"cannot read"*) ok ;; *) bad "missing file: unhelpful message: $out" ;; esac

# --- a file that is not a certificate ---------------------------------
# Installs cleanly and then fails every handshake with nothing pointing back
# here, so it has to be caught at the door.
echo "this is not a certificate" > "$WORK/junk.pem"
out=$(advisor_trust_ca "$WORK/junk.pem" 2>&1); rc=$?
check "not a certificate: exit non-zero" "$rc" "1"
case "$out" in *"not a PEM certificate"*) ok ;; *) bad "not a certificate: unhelpful message: $out" ;; esac
if [ -e "$ADVISOR_TRUST_ANCHOR" ] ; then bad "not a certificate: installed it anyway"; else ok; fi

# --- the happy path ----------------------------------------------------
out=$(advisor_trust_ca "$WORK/ca.crt" 2>&1); rc=$?
check "valid CA: exit zero" "$rc" "0"
if [ -s "$ADVISOR_TRUST_ANCHOR" ] ; then ok ; else bad "valid CA: no anchor installed" ; fi
check "valid CA: anchor is world-readable" "$(stat -c %a "$ADVISOR_TRUST_ANCHOR")" "644"
if cmp -s "$WORK/ca.crt" "$ADVISOR_TRUST_ANCHOR" ; then ok ; else bad "valid CA: anchor differs from the source" ; fi

# --- re-running with a different CA replaces, not appends --------------
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=other-advisor" \
  -keyout "$WORK/other.key" -out "$WORK/other.crt" 2>/dev/null
advisor_trust_ca "$WORK/other.crt" >/dev/null 2>&1
if cmp -s "$WORK/other.crt" "$ADVISOR_TRUST_ANCHOR" ; then ok ; else bad "re-run: anchor was not replaced" ; fi

# --- the trust store refuses to rebuild --------------------------------
# Leaving the anchor behind would claim a trust that is not in effect.
rm -f "$ADVISOR_TRUST_ANCHOR"
export MOCK_UPDATE_RC=1
out=$(advisor_trust_ca "$WORK/ca.crt" 2>&1); rc=$?
check "rebuild fails: exit non-zero" "$rc" "1"
if [ -e "$ADVISOR_TRUST_ANCHOR" ] ; then bad "rebuild fails: left the anchor in place"; else ok; fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
