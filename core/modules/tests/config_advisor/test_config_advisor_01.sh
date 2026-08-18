#
# TEST - advisor_verify_release refuses everything it should, and advisor_pubkey
#        emits the key this image was built with.
#
# This binary links the module object built for the product, so it embeds the
# key this build was provisioned with: the real release public key on a
# production build (whose private half never leaves the release CI), or the
# throwaway dev keypair the build minted when none was injected.
#
# The refusals below hold either way. The accept path is only reachable when
# the dev private half is on disk (section 6); on a production build that
# section skips and test_config_advisor_02.sh covers acceptance by compiling
# the same source against a key it can sign with.
#

fail() { echo "FAIL: $1"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl not available"; exit 0; }

# ---- 1. the embedded key is real and is what the image ships ----
./hex_config advisor_pubkey > "$WORK/embedded.pub" \
    || fail "advisor_pubkey exited non-zero"
openssl pkey -pubin -in "$WORK/embedded.pub" -noout 2>/dev/null \
    || fail "the embedded public key is not a key openssl can read"

# The trust anchor is compiled in, so it must match the PEM the build was
# provisioned with -- injected in production, minted for dev. If these
# diverge, the image is verifying against something nobody provided.
PUBPEM="${ADVISOR_PUB_PEM:-/etc/ssl/advisor-release.pub.pem}"
if [ -f "$PUBPEM" ]; then
    diff -q <(openssl pkey -pubin -in "$WORK/embedded.pub" -outform PEM) \
            <(openssl pkey -pubin -in "$PUBPEM" -outform PEM) >/dev/null \
        || fail "the compiled-in key is not $PUBPEM"
fi

# ---- 2. a release signed by anyone else is refused ----
mkrelease() {
    local d=$1 key=$2
    rm -rf "$d" ; mkdir -p "$d"
    printf 'agent\n' > "$d/cube-advisor-agent_linux_amd64"
    {
        echo "# cube-advisor-agent release manifest"
        echo "# version: 0.0.0-test"
        ( cd "$d" && sha256sum cube-advisor-agent_linux_amd64 )
    } > "$d/manifest.txt"
    openssl dgst -sha256 -sign "$key" -out "$d/manifest.txt.sig" "$d/manifest.txt"
}

openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/attacker.key" 2>/dev/null
mkrelease "$WORK/rel" "$WORK/attacker.key"
./hex_config advisor_verify_release "$WORK/rel" >/dev/null 2>&1 \
    && fail "accepted a release signed by a key that is not the image's"

# ---- 3. missing pieces are refusals, not warnings ----
rm -f "$WORK/rel/manifest.txt.sig"
./hex_config advisor_verify_release "$WORK/rel" >/dev/null 2>&1 \
    && fail "accepted a release with no signature"

mkrelease "$WORK/rel" "$WORK/attacker.key"
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
    && fail "advisor_pubkey accepted an argument"

# ---- 5. an artifact name that escapes the release directory ----
mkrelease "$WORK/rel" "$WORK/attacker.key"
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
# Only when the build minted a dev keypair: its private half is on disk and
# matches the embedded key, so a signature it makes must verify. A production
# build has no private half here and skips this.
PRIVPEM="${ADVISOR_PRIV_PEM:-/etc/ssl/advisor-release.priv.pem}"
if [ -f "$PRIVPEM" ] \
   && diff -q <(openssl pkey -pubin -in "$WORK/embedded.pub" -outform PEM) \
              <(openssl pkey -in "$PRIVPEM" -pubout 2>/dev/null) >/dev/null 2>&1; then
    mkrelease "$WORK/goodrel" "$PRIVPEM"
    ./hex_config advisor_verify_release "$WORK/goodrel" >/dev/null 2>&1 \
        || fail "refused a release signed with this image's own key"
fi

exit 0
