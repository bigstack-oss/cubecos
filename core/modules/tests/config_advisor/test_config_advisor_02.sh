#
# TEST - the verification logic itself: what advisor_verify_release accepts as
#        well as what it refuses.
#
# The hex_config binary in this directory embeds the product's release public
# key, and the matching private key is not in this repository -- so that binary
# can never be handed a signature it accepts, and test_config_advisor_01.sh can
# only assert refusals. A verifier that refused everything would pass it.
#
# So this compiles the same source against a throwaway keypair generated here,
# which makes the accept path reachable. The stubs under stub/ replace hex/log.h
# and hex/config_module.h only; the code under test is byte-for-byte the code
# that ships.
#
# openssl and sha256sum are used to build the fixtures rather than to do the
# checking -- the point is that an independently produced signature is one this
# verifier agrees with, which is also what a customer checking our work does.
#

fail() { echo "FAIL: $1"; exit 1; }

command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl not available"; exit 0; }
command -v g++     >/dev/null 2>&1 || { echo "SKIP: g++ not available";     exit 0; }

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SRC="$DIR/../../config_advisor.cpp"
[ -f "$SRC" ] || fail "cannot find config_advisor.cpp at $SRC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A throwaway release keypair, generated per run so no key is committed, and a
# second one standing in for an attacker.
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/release.key" 2>/dev/null
openssl ec -in "$WORK/release.key" -pubout -out "$WORK/release.pub" 2>/dev/null
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/attacker.key" 2>/dev/null

# Embed it exactly the way core/modules/Makefile embeds the real one.
{ printf '#define ADVISOR_RELEASE_PUBLIC_KEY "'
  awk '{printf "%s\\n", $0}' "$WORK/release.pub"
  printf '"\n'
} > "$WORK/advisor_key.h"

g++ -Wall -Werror -Wno-unused-result -I"$WORK" -I"$DIR/stub" \
    -o "$WORK/advisorctl" "$SRC" "$DIR/stub/driver.cpp" -lcrypto \
    || fail "config_advisor.cpp did not compile against a test key"

V="$WORK/advisorctl"

# make_release <dir> [signing key]
make_release() {
    local dir=$1 key=${2:-$WORK/release.key}
    rm -rf "$dir" ; mkdir -p "$dir"
    printf 'amd64 agent\n' > "$dir/cube-advisor-agent_linux_amd64"
    printf 'arm64 agent\n' > "$dir/cube-advisor-agent_linux_arm64"
    {
        echo "# cube-advisor-agent release manifest"
        echo "# version: 0.2.0"
        echo "# commit: abc1234"
        echo "# protocol: 1"
        ( cd "$dir" && sha256sum cube-advisor-agent_linux_amd64 cube-advisor-agent_linux_arm64 )
    } > "$dir/manifest.txt"
    openssl dgst -sha256 -sign "$key" -out "$dir/manifest.txt.sig" "$dir/manifest.txt"
}

# resign <dir> -- re-sign whatever the manifest now says, with the real release
# key. Used to test the parser on input that has already passed the signature
# check, which is the only way those paths are reachable.
resign() {
    openssl dgst -sha256 -sign "$WORK/release.key" -out "$1/manifest.txt.sig" "$1/manifest.txt"
}

REL="$WORK/rel"

# ---- accept ----
make_release "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    || fail "refused a genuine release"
$V advisor_verify_release "$REL" cube-advisor-agent_linux_amd64 >/dev/null 2>&1 \
    || fail "refused an artifact the signed manifest lists"

# The published two-command check has to agree with us, or the format's promise
# that a customer can verify our releases without our binary is not true.
$V advisor_pubkey > "$WORK/extracted.pub" 2>/dev/null \
    || fail "advisor_pubkey exited non-zero"
openssl dgst -sha256 -verify "$WORK/extracted.pub" \
    -signature "$REL/manifest.txt.sig" "$REL/manifest.txt" >/dev/null 2>&1 \
    || fail "openssl rejects a manifest this verifier accepts"
( cd "$REL" && sha256sum -c manifest.txt >/dev/null 2>&1 ) \
    || fail "sha256sum -c rejects a manifest this verifier accepts"

# A file that is merely present is not verified.
printf 'squatter\n' > "$REL/extra-binary"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    || fail "an unlisted extra file broke verification of the listed ones"
$V advisor_verify_release "$REL" extra-binary >/dev/null 2>&1 \
    && fail "approved a binary the signed manifest does not list"

# ---- refuse: tampering ----
make_release "$REL" ; printf 'evil\n' > "$REL/cube-advisor-agent_linux_amd64"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a swapped artifact"

make_release "$REL" ; sed -i 's/^# version: 0.2.0/# version: 9.9.9/' "$REL/manifest.txt"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a manifest edited after signing"

# The case signature-first exists for: the attacker rewrites the binary AND the
# digest list, and only the signature is stale. Checking digests first would
# call this consistent.
make_release "$REL" ; printf 'evil\n' > "$REL/cube-advisor-agent_linux_amd64"
{ echo "# v" ; ( cd "$REL" && sha256sum cube-advisor-agent_linux_amd64 ) ; } > "$REL/manifest.txt"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted an attacker-authored manifest carrying a stale signature"

make_release "$REL" "$WORK/attacker.key"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a manifest signed by another key"

make_release "$REL" ; head -c 100 /dev/urandom > "$REL/manifest.txt.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a random signature"

make_release "$REL" ; : > "$REL/manifest.txt.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted an empty signature"

# ---- refuse: missing ----
make_release "$REL" ; rm -f "$REL/manifest.txt.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a missing signature"
make_release "$REL" ; rm -f "$REL/manifest.txt"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a missing manifest"
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_arm64"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a manifest listing an artifact that is not there"

# ---- targeted install: only the artifact being installed need be present ----
# advisor_enroll fetches the manifest, the signature and ONLY this node's arch,
# so a release signed for several architectures leaves the others absent.
# Naming an artifact asks "is this one genuine"; naming none asks "is this whole
# release intact", which stays strict -- the case just above.
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_arm64"
$V advisor_verify_release "$REL" cube-advisor-agent_linux_amd64 >/dev/null 2>&1 \
    || fail "refused the arch it was asked about because another arch was not fetched"

# Either direction -- there is nothing special about amd64.
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_amd64"
$V advisor_verify_release "$REL" cube-advisor-agent_linux_arm64 >/dev/null 2>&1 \
    || fail "refused the arch that is present"

# Skipping the absent entries must not skip the one that matters: listed is not
# verified, and this is the artifact about to be installed and executed.
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_amd64"
$V advisor_verify_release "$REL" cube-advisor-agent_linux_amd64 >/dev/null 2>&1 \
    && fail "accepted an artifact that the manifest lists but nobody fetched"

# Nor may a partially fetched release become a way to smuggle a swapped binary.
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_arm64"
printf 'evil\n' > "$REL/cube-advisor-agent_linux_amd64"
$V advisor_verify_release "$REL" cube-advisor-agent_linux_amd64 >/dev/null 2>&1 \
    && fail "accepted a swapped artifact in a partially fetched release"

# ---- refuse: the parser, on input that already passed the signature check ----
make_release "$REL" ; printf '# only comments\n' > "$REL/manifest.txt" ; resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a manifest listing nothing"

make_release "$REL" ; printf '# v\nZZZZ  x\n' > "$REL/manifest.txt" ; resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a line that is not a digest"

make_release "$REL" ; sed -i 's/^\([0-9a-f]\{64\}\)  /\1 /' "$REL/manifest.txt" ; resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a single-space separator"

make_release "$REL" ; sed -i 's/^\([0-9a-f]\{64\}\)/\U\1/' "$REL/manifest.txt" ; resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted uppercase digests"

# A name that escapes the release directory, in a manifest we ourselves signed.
# Signing is not supposed to be the only thing standing between a manifest and
# an arbitrary path, so the target here EXISTS -- otherwise the refusal would
# come from the open failing and would prove nothing.
printf 'SECRET\n' > "$WORK/secret.txt"
make_release "$REL"
printf '# v\n%s  ../secret.txt\n' "$(sha256sum "$WORK/secret.txt" | cut -d' ' -f1)" > "$REL/manifest.txt"
resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "verified a file outside the release directory"

make_release "$REL"
printf '# v\n%s  /etc/passwd\n' "$(sha256sum /etc/passwd | cut -d' ' -f1)" > "$REL/manifest.txt"
resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "verified an absolute path named by a signed manifest"

# A bare name is a legal artifact name, so rejecting names is not enough on its
# own: the entry itself can be a symlink out of the directory. Reading through
# it would mean every check below describes a file somewhere else.
make_release "$REL"
ln -sf "$WORK/secret.txt" "$REL/cube-advisor-agent_linux_amd64"
{
    echo "# v"
    printf '%s  cube-advisor-agent_linux_amd64\n' "$(sha256sum "$WORK/secret.txt" | cut -d' ' -f1)"
} > "$REL/manifest.txt"
resign "$REL"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "followed a symlink out of the release directory"

exit 0
