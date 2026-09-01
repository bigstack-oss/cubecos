#!/bin/bash
#
# Unit test for the Advisor helpers in ../modules/sdk_advisor.sh.
#
# Verification itself is NOT here any more -- it moved into hex_config, for the
# same reason licence verification lives there: the key and the check belong in
# one place, and this file lives under /usr/lib/hex_sdk where root can edit it.
# The crypto is covered by core/modules/tests/config_advisor/.
#
# What is left in shell is a contract, and that is what this tests: which
# arguments reach hex_config, that nothing is installed unless it said yes, and
# that the surrounding helpers refuse rather than guess. hex_config is stubbed
# so a refusal can be simulated without needing the release private key.
#
# Self-contained: extracts only the functions under test, so it needs none of
# sdk_advisor.sh's runtime prerequisites (PROG / SDK_DIR / errcodes).
# Run:  bash test_sdk_advisor_verify.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in advisor_verify_release advisor_release_version advisor_install_release advisor_agent_arch advisor_enroll advisor_cluster_id ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

ADVISOR_MANIFEST_NAME=manifest.txt
ADVISOR_SIGNATURE_NAME=manifest.txt.sig

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A stand-in hex_config: records the arguments it was called with and exits with
# whatever STUB_RC says. Recording the arguments is the point -- a wrapper that
# quietly dropped the artifact name would still "work", and would stop checking
# that the file being installed is one the signature covers.
cat > "$WORK/hex_config" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
exit "${STUB_RC:-0}"
STUB
chmod +x "$WORK/hex_config"
HEX_CFG="$WORK/hex_config"
export STUB_LOG="$WORK/calls"
export STUB_RC=0

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

reset() { : > "$STUB_LOG" ; STUB_RC=0 ; }
lastcall() { tail -1 "$STUB_LOG" 2>/dev/null ; }

REL="$WORK/rel"
mkdir -p "$REL"
printf 'amd64 agent\n' > "$REL/cube-advisor-agent_linux_amd64"
{
    echo "# cube-advisor-agent release manifest"
    echo "# version: 0.2.0"
    echo "# commit: abc1234"
    echo "# protocol: 1"
    ( cd "$REL" && sha256sum cube-advisor-agent_linux_amd64 )
} > "$REL/$ADVISOR_MANIFEST_NAME"
: > "$REL/$ADVISOR_SIGNATURE_NAME"

# --- what reaches hex_config -----------------------------------------------
reset
advisor_verify_release "$REL" >/dev/null 2>&1
check "verify delegates the directory" "$(lastcall)" "advisor_verify_release $REL"

reset
advisor_verify_release "$REL" cube-advisor-agent_linux_amd64 >/dev/null 2>&1
check "verify passes the artifact through" "$(lastcall)" \
      "advisor_verify_release $REL cube-advisor-agent_linux_amd64"

# An empty artifact must not become an empty second argument.
reset
advisor_verify_release "$REL" "" >/dev/null 2>&1
check "an empty artifact is not passed as an argument" "$(lastcall)" \
      "advisor_verify_release $REL"

# --- refusals do not reach hex_config at all --------------------------------
reset
if advisor_verify_release "" >/dev/null 2>&1 ; then
    bad "verify accepted an empty release directory"
else
    ok
fi
[ -s "$STUB_LOG" ] && bad "verify called hex_config with no directory to check"

# --- the verifier's verdict is the install gate ------------------------------
reset ; STUB_RC=1
if advisor_install_release "$REL" cube-advisor-agent_linux_amd64 "$WORK/installed" >/dev/null 2>&1 ; then
    bad "installed although verification refused"
else
    ok
fi
[ -e "$WORK/installed" ] && bad "a refused install still wrote its destination"

# The install path must ask about the artifact, not just the directory: a file
# that happens to sit in a verified directory is not itself verified.
check "install asks about the specific artifact" "$(lastcall)" \
      "advisor_verify_release $REL cube-advisor-agent_linux_amd64"

reset ; STUB_RC=0
if advisor_install_release "$REL" cube-advisor-agent_linux_amd64 "$WORK/installed" >/dev/null 2>&1 \
   && [ -x "$WORK/installed" ] ; then
    ok
else
    bad "a verified artifact did not install"
fi

reset
if advisor_install_release "$REL" "" "$WORK/nowhere" >/dev/null 2>&1 ; then
    bad "install ran with no artifact named"
else
    ok
fi

# --- version comes off the manifest ------------------------------------------
check "version is read from the manifest" "$(advisor_release_version "$REL")" "0.2.0"

# --- arch mapping refuses to guess -------------------------------------------
# Installing the wrong binary fails later and less clearly than not installing
# one, so an unknown machine is a refusal.
uname() { echo "$FAKE_UNAME"; }
FAKE_UNAME=x86_64  ; check "x86_64 maps to amd64"  "$(advisor_agent_arch)" "amd64"
FAKE_UNAME=aarch64 ; check "aarch64 maps to arm64" "$(advisor_agent_arch)" "arm64"
FAKE_UNAME=riscv64
if advisor_agent_arch >/dev/null 2>&1 ; then
    bad "an unknown architecture was mapped instead of refused"
else
    ok
fi
unset -f uname

# --- enroll validates its inputs before touching the network -----------------
if advisor_enroll "" "" "" >/dev/null 2>&1 ; then
    bad "advisor_enroll ran with no arguments"
else
    ok
fi
if advisor_enroll https://example "$WORK/no-such-token" 0.2.0 >/dev/null 2>&1 ; then
    bad "advisor_enroll ran with an unreadable token file"
else
    ok
fi


# --- the cluster id matches what the Advisor will store ----------------------
#
# cubesys.controller is declared with ValidateRegex/DFT_REGEX_STR ("^.*$"), so
# CubeCOS constrains it not at all -- the Advisor must accept what CubeCOS
# produces. It folds to lowercase and stores the folded form; these cases pin
# that the local check folds the same way and refuses only what genuinely
# breaks a CN, a path segment or /etc/hosts.
idcheck() {
    local want="$1" id="$2" env="$WORK/phone-home-agent.env"
    printf 'CUBE_CLUSTER_ID=%s\n' "$id" > "$env"
    local got
    if got=$(CLUSTER_ENV="$env" advisor_cluster_id 2>/dev/null) ; then
        check "cluster id '$id'" "accept:$got" "$want"
    else
        check "cluster id '$id'" "reject" "$want"
    fi
}
idcheck "accept:ky3haclust01" ky3haclust01
idcheck "accept:sky-140"      sky-140
idcheck "accept:cube.lab.01"  cube.lab.01
idcheck "accept:foo_bar"      foo_bar
# Folded, not refused: the Advisor stores the lowercase form, so a controller
# named in caps must enrol -- as the id the Advisor will actually hold.
idcheck "accept:controller01" Controller01
idcheck "accept:acme-prod-01" ACME-PROD-01
# Refused: each of these breaks a CN, a path segment, or /etc/hosts.
idcheck "reject" "a/b"
idcheck "reject" "has space"
idcheck "reject" _leading
idcheck "reject" trailing_
idcheck "reject" -leading
idcheck "reject" .dot
idcheck "reject" "$(printf 'x%.0s' $(seq 1 65))"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
