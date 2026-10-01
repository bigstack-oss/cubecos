#
# TEST - advisor_verify_release refuses everything it should, and advisor_pubkey
#        emits the keys this image was built with.
#
# This binary links the module object built for the product, so it embeds the
# keys this build was provisioned with: the real release public keys on a
# production build (whose private halves never leave release signing), or the
# throwaway dev keypairs the build minted when none were injected.
#
# The refusals below hold either way. The accept path is only reachable when
# the dev private halves are on disk (section 6); on a production build that
# section skips and test_config_advisor_02.sh covers acceptance by compiling
# the same source against a key it can sign with.
#

fail() { echo "FAIL: $1"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl not available"; exit 0; }

# ---- 1. the embedded keys are real and are what the image ships ----
./hex_config advisor_pubkey ecdsa > "$WORK/embedded.pub" \
    || fail "advisor_pubkey ecdsa exited non-zero"
./hex_config advisor_pubkey mldsa87 > "$WORK/embedded-mldsa.pub" \
    || fail "advisor_pubkey mldsa87 exited non-zero"
openssl pkey -pubin -in "$WORK/embedded.pub" -noout -text 2>/dev/null | grep -q "NIST CURVE: P-384" \
    || fail "the embedded ECDSA public key is not P-384"
openssl pkey -pubin -in "$WORK/embedded-mldsa.pub" -noout -text 2>/dev/null | grep -q "ML-DSA-87" \
    || fail "the embedded ML-DSA public key is not ML-DSA-87"

# The trust anchors are compiled in, so they must match the PEMs the build was
# provisioned with -- injected in production, minted for dev. If these
# diverge, the image is verifying against something nobody provided.
PUBPEM="${ADVISOR_PUB_PEM:-/etc/ssl/advisor-release.pub.pem}"
MLDSA_PUBPEM="${ADVISOR_MLDSA_PUB_PEM:-/etc/ssl/advisor-release-mldsa87.pub.pem}"
for pair in "$WORK/embedded.pub:$PUBPEM" "$WORK/embedded-mldsa.pub:$MLDSA_PUBPEM"; do
    [ -f "${pair#*:}" ] || continue
    diff -q <(openssl pkey -pubin -in "${pair%%:*}" -outform PEM) \
            <(openssl pkey -pubin -in "${pair#*:}" -outform PEM) >/dev/null \
        || fail "the compiled-in key is not ${pair#*:}"
done

# ---- 2. a release signed by anyone else is refused ----
# mkrelease <dir> <ecdsa key> <mldsa key>
mkrelease() {
    local d=$1 key=$2 mldsakey=$3
    rm -rf "$d" ; mkdir -p "$d"
    printf 'agent\n' > "$d/cube-advisor-agent_linux_amd64"
    {
        echo "# cube-advisor-agent release manifest"
        echo "# version: 0.0.0-test"
        ( cd "$d" && sha256sum cube-advisor-agent_linux_amd64 )
    } > "$d/manifest.txt"
    openssl dgst -sha384 -sign "$key" -out "$d/manifest.txt.sig" "$d/manifest.txt"
    openssl pkeyutl -sign -rawin -inkey "$mldsakey" -in "$d/manifest.txt" \
        -out "$d/manifest.txt.mldsa87.sig"
}

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$WORK/attacker.key" 2>/dev/null
openssl genpkey -algorithm ML-DSA-87 -out "$WORK/attacker-mldsa.key" 2>/dev/null
ATTACKER="$WORK/attacker.key $WORK/attacker-mldsa.key"
mkrelease "$WORK/rel" $ATTACKER
./hex_config advisor_verify_release "$WORK/rel" >/dev/null 2>&1 \
    && fail "accepted a release signed by a key that is not the image's"

# ---- 3. missing pieces are refusals, not warnings ----
rm -f "$WORK/rel/manifest.txt.sig" "$WORK/rel/manifest.txt.mldsa87.sig"
./hex_config advisor_verify_release "$WORK/rel" >/dev/null 2>&1 \
    && fail "accepted a release with no signature"

mkrelease "$WORK/rel" $ATTACKER
rm -f "$WORK/rel/manifest.txt"
./hex_config advisor_verify_release "$WORK/rel" >/dev/null 2>&1 \
    && fail "accepted a release with no manifest"

./hex_config advisor_verify_release "$WORK/nonexistent" >/dev/null 2>&1 \
    && fail "accepted a directory that does not exist"

# ---- 4. usage ----
./hex_config advisor_verify_release >/dev/null 2>&1 \
    && fail "accepted a call with no release directory"
./hex_config advisor_verify_release a b c >/dev/null 2>&1 \
    && fail "accepted a call with too many arguments"
./hex_config advisor_pubkey extra >/dev/null 2>&1 \
    && fail "advisor_pubkey accepted an unknown key name"
./hex_config advisor_pubkey ecdsa mldsa87 >/dev/null 2>&1 \
    && fail "advisor_pubkey accepted two arguments"

# ---- 5. an artifact name that escapes the release directory ----
mkrelease "$WORK/rel" $ATTACKER
./hex_config advisor_verify_release "$WORK/rel" ../../etc/passwd >/dev/null 2>&1 \
    && fail "accepted an artifact name containing a path"
./hex_config advisor_verify_release "$WORK/rel" /etc/passwd >/dev/null 2>&1 \
    && fail "accepted an absolute artifact name"

# ---- 5b. the release directory itself ----
# It comes from the caller and hex_config opens it as root, so a relative path
# (resolved against the caller's cwd) and traversal are refused BEFORE the open.
# The refusal reason is asserted, not just the exit status: every release in this
# test is refused anyway for its signature, so an exit code alone would pass
# whether the check exists or not.
HERE=$(pwd)
out=$( (cd "$WORK" && "$HERE/hex_config" advisor_verify_release rel) 2>&1 ) || true
case $out in
    *"absolute path"*) ;;
    *) fail "a relative release directory was not refused as a path: $out" ;;
esac
out=$(./hex_config advisor_verify_release "$WORK/../$(basename "$WORK")/rel" 2>&1) || true
case $out in
    *"absolute path"*) ;;
    *) fail "a release directory containing .. was not refused as a path: $out" ;;
esac

# ---- 6. a dev build proves the accept path against the shipped binary ----
# Only when the build minted dev keypairs: their private halves are on disk
# and match the embedded keys, so a signature they make must verify. A
# production build has no private halves here and skips this.
PRIVPEM="${ADVISOR_PRIV_PEM:-/etc/ssl/advisor-release.priv.pem}"
MLDSA_PRIVPEM="${ADVISOR_MLDSA_PRIV_PEM:-/etc/ssl/advisor-release-mldsa87.priv.pem}"
if [ -f "$PRIVPEM" ] && [ -f "$MLDSA_PRIVPEM" ] \
   && diff -q <(openssl pkey -pubin -in "$WORK/embedded.pub" -outform PEM) \
              <(openssl pkey -in "$PRIVPEM" -pubout 2>/dev/null) >/dev/null 2>&1 \
   && diff -q <(openssl pkey -pubin -in "$WORK/embedded-mldsa.pub" -outform PEM) \
              <(openssl pkey -in "$MLDSA_PRIVPEM" -pubout 2>/dev/null) >/dev/null 2>&1; then
    mkrelease "$WORK/goodrel" "$PRIVPEM" "$MLDSA_PRIVPEM"
    ./hex_config advisor_verify_release "$WORK/goodrel" >/dev/null 2>&1 \
        || fail "refused a release signed with this image's own keys"
fi

exit 0
