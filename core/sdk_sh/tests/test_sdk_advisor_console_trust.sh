#!/bin/bash
#
# Unit test for advisor_console_trust in ../modules/sdk_advisor.sh -- makes this
# node accept console certificates the Advisor mints.
#
# A console session is piped to the node's own sshd, so sshd decides whether a
# certificate is good; the Advisor only signs one. Until this existed nothing
# wrote the CA or the drop-in at all, so a console authenticated nobody on
# every cluster — the two paths were in config_advisor.cpp's migrate list with
# no code creating them.
#
# The cases that matter are the ones that fail badly rather than visibly: a
# private key or a certificate installs cleanly and then refuses every login,
# and a drop-in sshd cannot parse takes sshd down at its next restart, which is
# far worse than a console that does not work.
#
# Run:  bash test_sdk_advisor_console_trust.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in advisor_console_trust ; do
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

ADVISOR_CONSOLE_CA="$WORK/etc/ssh/console-ca/cube-advisor.pub"
ADVISOR_SSHD_DROPIN="$WORK/etc/ssh/sshd_config.d/60-cube-advisor-console.conf"
ADVISOR_CONSOLE_ACCOUNT=advisor
mkdir -p "$WORK/bin" "$(dirname "$ADVISOR_SSHD_DROPIN")"
PATH="$WORK/bin:$PATH"

# sshd -t is the gate that stops a broken drop-in reaching a restart.
cat > "$WORK/bin/sshd" <<'EOF'
#!/bin/bash
exit ${MOCK_SSHD_RC:-0}
EOF
# systemctl reload must not actually touch this machine's sshd.
cat > "$WORK/bin/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$WORK/bin/sshd" "$WORK/bin/systemctl"
export MOCK_SSHD_RC=0

ssh-keygen -q -t ed25519 -N "" -f "$WORK/ca" >/dev/null 2>&1

# --- no file, or an unreadable one --------------------------------------
out=$(advisor_console_trust "" 2>&1); rc=$?
check "no argument: exit non-zero" "$rc" "1"
out=$(advisor_console_trust "$WORK/nope.pub" 2>&1); rc=$?
check "missing file: exit non-zero" "$rc" "1"
case "$out" in *"cannot read"*) ok ;; *) bad "missing file: unhelpful message: $out" ;; esac

# --- a private key, which is the dangerous mistake ----------------------
# It is a real key, so a naive check passes it; sshd would then refuse every
# login, and the operator would have no reason to look here.
out=$(advisor_console_trust "$WORK/ca" 2>&1); rc=$?
check "private key: exit non-zero" "$rc" "1"
if [ -e "$ADVISOR_CONSOLE_CA" ] ; then bad "private key: installed it anyway"; else ok; fi

# --- junk ---------------------------------------------------------------
echo "not a key" > "$WORK/junk.pub"
out=$(advisor_console_trust "$WORK/junk.pub" 2>&1); rc=$?
check "junk: exit non-zero" "$rc" "1"

# --- the happy path ------------------------------------------------------
out=$(advisor_console_trust "$WORK/ca.pub" 2>&1); rc=$?
check "public key: exit zero" "$rc" "0"
if cmp -s "$WORK/ca.pub" "$ADVISOR_CONSOLE_CA" ; then ok ; else bad "the CA was not installed verbatim" ; fi
check "CA is world-readable, as sshd needs" "$(stat -c %a "$ADVISOR_CONSOLE_CA")" "644"
if grep -q "TrustedUserCAKeys $ADVISOR_CONSOLE_CA" "$ADVISOR_SSHD_DROPIN" ; then ok ; else bad "the drop-in does not trust the CA" ; fi
# Scoped to one account: a certificate must not be presentable as any user.
if grep -q "Match User advisor" "$ADVISOR_SSHD_DROPIN" ; then ok ; else bad "the drop-in is not scoped to the console account" ; fi

# --- re-running replaces rather than appends -----------------------------
advisor_console_trust "$WORK/ca.pub" >/dev/null 2>&1
check "re-run leaves one TrustedUserCAKeys line" "$(grep -c TrustedUserCAKeys "$ADVISOR_SSHD_DROPIN")" "1"

# --- sshd refuses the configuration --------------------------------------
# Leaving the drop-in behind would take sshd down at its next restart.
rm -f "$ADVISOR_SSHD_DROPIN"
export MOCK_SSHD_RC=1
out=$(advisor_console_trust "$WORK/ca.pub" 2>&1); rc=$?
check "sshd rejects it: exit non-zero" "$rc" "1"
if [ -e "$ADVISOR_SSHD_DROPIN" ] ; then bad "sshd rejected it and the drop-in was left in place"; else ok; fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
