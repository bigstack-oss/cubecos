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

# Throwaway hybrid release keypairs (ECDSA P-384 + ML-DSA-87), generated per
# run so no key is committed, and a second set standing in for an attacker.
genkeys() {
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$WORK/$1.key" 2>/dev/null
    openssl pkey -in "$WORK/$1.key" -pubout -out "$WORK/$1.pub" 2>/dev/null
    openssl genpkey -algorithm ML-DSA-87 -out "$WORK/$1-mldsa.key" 2>/dev/null
    openssl pkey -in "$WORK/$1-mldsa.key" -pubout -out "$WORK/$1-mldsa.pub" 2>/dev/null
}
genkeys release
genkeys attacker

# Embed them exactly the way core/modules/Makefile embeds the real ones.
# keyheader <out> <ecdsa pub> <mldsa pub>
keyheader() {
    { printf '#define ADVISOR_RELEASE_PUBLIC_KEY "'
      awk '{printf "%s\\n", $0}' "$2"
      printf '"\n#define ADVISOR_RELEASE_MLDSA_PUBLIC_KEY "'
      awk '{printf "%s\\n", $0}' "$3"
      printf '"\n'
    } > "$1"
}
keyheader "$WORK/advisor_key.h" "$WORK/release.pub" "$WORK/release-mldsa.pub"

g++ -Wall -Werror -Wno-unused-result -I"$WORK" -I"$DIR/stub" \
    -o "$WORK/advisorctl" "$SRC" "$DIR/stub/driver.cpp" -lcrypto \
    || fail "config_advisor.cpp did not compile against a test key"

V="$WORK/advisorctl"

# sign_ecdsa / sign_mldsa <dir> <key> -- the two halves of a release signature.
sign_ecdsa() { openssl dgst -sha384 -sign "$2" -out "$1/manifest.txt.sig" "$1/manifest.txt"; }
sign_mldsa() {
    openssl pkeyutl -sign -rawin -inkey "$2" -in "$1/manifest.txt" -out "$1/manifest.txt.mldsa87.sig"
}

# make_release <dir> [key prefix] -- signed with both <prefix>.key and <prefix>-mldsa.key.
make_release() {
    local dir=$1 key=${2:-$WORK/release}
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
    sign_ecdsa "$dir" "$key.key"
    sign_mldsa "$dir" "$key-mldsa.key"
}

# resign <dir> -- re-sign whatever the manifest now says, with the real release
# key. Used to test the parser on input that has already passed the signature
# check, which is the only way those paths are reachable.
resign() {
    sign_ecdsa "$1" "$WORK/release.key"
    sign_mldsa "$1" "$WORK/release-mldsa.key"
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
$V advisor_pubkey ecdsa > "$WORK/extracted.pub" 2>/dev/null \
    || fail "advisor_pubkey ecdsa exited non-zero"
$V advisor_pubkey mldsa87 > "$WORK/extracted-mldsa.pub" 2>/dev/null \
    || fail "advisor_pubkey mldsa87 exited non-zero"
openssl dgst -sha384 -verify "$WORK/extracted.pub" \
    -signature "$REL/manifest.txt.sig" "$REL/manifest.txt" >/dev/null 2>&1 \
    || fail "openssl rejects an ECDSA signature this verifier accepts"
openssl pkeyutl -verify -rawin -pubin -inkey "$WORK/extracted-mldsa.pub" \
    -in "$REL/manifest.txt" -sigfile "$REL/manifest.txt.mldsa87.sig" >/dev/null 2>&1 \
    || fail "openssl rejects an ML-DSA-87 signature this verifier accepts"
[ "$($V advisor_pubkey)" = "$(cat "$WORK/extracted.pub" "$WORK/extracted-mldsa.pub")" ] \
    || fail "advisor_pubkey with no argument does not print both keys, ECDSA first"
$V advisor_pubkey rsa >/dev/null 2>&1 && fail "advisor_pubkey accepted an unknown key name"
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

make_release "$REL" "$WORK/attacker"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a manifest signed by other keys"

# ---- refuse: hybrid -- one genuine half is not enough ----
make_release "$REL" ; sign_mldsa "$REL" "$WORK/attacker-mldsa.key"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a genuine ECDSA signature with a foreign ML-DSA one"

make_release "$REL" ; sign_ecdsa "$REL" "$WORK/attacker.key"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a genuine ML-DSA signature with a foreign ECDSA one"

make_release "$REL" ; rm -f "$REL/manifest.txt.mldsa87.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a missing ML-DSA signature"

make_release "$REL" ; : > "$REL/manifest.txt.mldsa87.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted an empty ML-DSA signature"

# ECDSA must be over SHA-384, not whatever digest the signer picked.
make_release "$REL"
openssl dgst -sha256 -sign "$WORK/release.key" -out "$REL/manifest.txt.sig" "$REL/manifest.txt"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted an ECDSA signature over SHA-256"

# ---- refuse: a misprovisioned anchor ----
# Each slot accepts only its own key kind.
# Assert the reason: a wrong-kind key would also fail on the signature.
# wrongkind <ecdsa pub> <mldsa pub> [ecdsa signing key]
wrongkind() {
    keyheader "$WORK/wrong/advisor_key.h" "$1" "$2"
    g++ -Wall -Werror -Wno-unused-result -I"$WORK/wrong" -I"$DIR/stub" \
        -o "$WORK/wrong/advisorctl" "$SRC" "$DIR/stub/driver.cpp" -lcrypto \
        || fail "config_advisor.cpp did not compile against a test key"
    make_release "$REL"
    [ -z "$3" ] || sign_ecdsa "$REL" "$3"
    "$WORK/wrong/advisorctl" advisor_verify_release "$REL" 2>&1 >/dev/null
}
mkdir -p "$WORK/wrong"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$WORK/p256.key" 2>/dev/null
openssl pkey -in "$WORK/p256.key" -pubout -out "$WORK/p256.pub" 2>/dev/null
case $(wrongkind "$WORK/release.pub" "$WORK/release.pub") in
    *"ML-DSA-87 release public key is unusable"*) ;;
    *) fail "accepted an EC key in the ML-DSA slot" ;;
esac
case $(wrongkind "$WORK/release-mldsa.pub" "$WORK/release-mldsa.pub") in
    *"ECDSA P-384 release public key is unusable"*) ;;
    *) fail "accepted an ML-DSA key in the ECDSA slot" ;;
esac
case $(wrongkind "$WORK/p256.pub" "$WORK/release-mldsa.pub" "$WORK/p256.key") in
    *"ECDSA P-384 release public key is unusable"*) ;;
    *) fail "accepted a P-256 key in the P-384 slot" ;;
esac

# ---- refuse: missing ----
make_release "$REL" ; rm -f "$REL/manifest.txt.sig"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a missing ECDSA signature"
make_release "$REL" ; rm -f "$REL/manifest.txt"
$V advisor_verify_release "$REL" >/dev/null 2>&1 && fail "accepted a missing manifest"
make_release "$REL" ; rm -f "$REL/cube-advisor-agent_linux_arm64"
$V advisor_verify_release "$REL" >/dev/null 2>&1 \
    && fail "accepted a manifest listing an artifact that is not there"

# ---- targeted install: only the artifact being installed need be present ----
# advisor_enroll fetches the manifest, the signatures and ONLY this node's arch,
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
