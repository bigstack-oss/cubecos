# Advisor release public keys

The trust anchor for the Cube AI Advisor agent is compiled into `hex_config`
at build time (see `advisor_key.h` in `core/modules/Makefile`) and used to
verify the signatures over an agent release manifest before anything from that
release is installed or executed.

It is a **hybrid** anchor: two keys, and a release must carry a valid signature
from both.

| Key | Signature file | Build path |
|---|---|---|
| ECDSA P-384 (SHA-384) | `manifest.txt.sig` | `/etc/ssl/advisor-release.pub.pem` (`ADVISOR_PUB_PEM=`) |
| ML-DSA-87 (FIPS 204, pure, empty context) | `manifest.txt.mldsa87.sig` | `/etc/ssl/advisor-release-mldsa87.pub.pem` (`ADVISOR_MLDSA_PUB_PEM=`) |

ML-DSA-87 protects against a future quantum attacker; ECDSA protects against a
flaw in the much younger ML-DSA. A forger has to break both. `hex_config`
also checks each embedded key's kind, so a misprovisioned build cannot quietly
fall back to one algorithm or a weaker curve.

## Where the key comes from

The build environment provides them at the paths above — the same
provisioning model as the licence key at `/etc/ssl/public.pem`
(`hex/src/hex_sdk_library/license/`):

- **Production** injects the real public keys at those paths before the build
  (triangle's `cube_build.groovy` copies them from Jenkins credentials). The
  private halves are held for release signing (ADR 0003) and never appear on
  a build machine.
- **A build without an injected key** — any dev build — mints a throwaway
  keypair for each missing slot on the spot, leaving the private half beside
  the public one. That
  makes the whole signing chain testable end to end: sign a manifest with the
  private half, watch `advisor_verify_release` accept it, and watch it refuse
  everyone else's.

A dev image therefore trusts only its own throwaway key. That is a feature,
not a gap: an image built outside the production pipeline cannot verify — and
so will not install — anything the real release pipeline signs, and vice
versa. Which key any given image trusts is auditable on the image itself:

```sh
hex_config advisor_pubkey            # both, ECDSA first
hex_config advisor_pubkey ecdsa
hex_config advisor_pubkey mldsa87
```

## Why it is not read from disk at runtime

A key file on a node can be replaced by any root process, which would defeat
verification silently — the check would still report success, against the
attacker's key. Compiled in, an attacker must replace `hex_config` itself.

## Why the check is compiled in too

`hex_config advisor_verify_release` does the whole check — signature, then
digests — rather than handing the key to a shell script. Key and check belong
together: `/usr/lib/hex_sdk/modules/sdk_advisor.sh` is an ordinary file that
root can edit, so a shell verifier could have its check deleted while this key
stayed perfectly safe. That protects the wrong half. It is the same reasoning,
and the same mechanism, as licence verification in
`hex/src/hex_sdk_library/license/`.

Verifying our releases without trusting our binary stays possible, because the
manifest is in `sha256sum`'s own format and `advisor_pubkey` will print the
anchor (OpenSSL 3.5 or later, for ML-DSA):

```sh
hex_config advisor_pubkey ecdsa   > release.pub
hex_config advisor_pubkey mldsa87 > release-mldsa87.pub
openssl dgst -sha384 -verify release.pub -signature manifest.txt.sig manifest.txt
openssl pkeyutl -verify -rawin -pubin -inkey release-mldsa87.pub \
    -in manifest.txt -sigfile manifest.txt.mldsa87.sig
sha256sum -c manifest.txt
```

That independent path is a property of the published format, not of what our
verifier happens to be written in.

## Why it is not the licence key

The licence keypair (`hex/make/devtools_definitions.mk`) belongs to whoever
issues licences; this one belongs to the release pipeline that signs agent
artifacts. Sharing them would mean a compromise of either could mint the other:
a licence-signing key that can also sign binaries a node will execute, or the
reverse. Same provisioning model, separate keys.

## Rotation

Rotating means injecting the new public keys into the production build and
rebuilding the image; nodes running an older image continue to trust the older
keys, so the release pipeline must keep signing with both generations until
those nodes are updated. Image-baked keys make rotation a release, so treat the key as
long-lived and protect the private half accordingly.
