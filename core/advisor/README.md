# Advisor release public key

The trust anchor for the Cube AI Advisor agent is compiled into `hex_config`
at build time (see `advisor_key.h` in `core/modules/Makefile`) and used to
verify the signature over an agent release manifest before anything from that
release is installed or executed.

## Where the key comes from

The build environment provides it at `/etc/ssl/advisor-release.pub.pem`
(override with `ADVISOR_PUB_PEM=`) — the same provisioning model as the
licence key at `/etc/ssl/public.pem` (`hex/src/hex_sdk_library/license/`):

- **Production** injects the real public key at that path before the build.
  The private half lives in the `cube-ai-advisor` release CI (ADR 0003) and
  never appears on a build machine.
- **A build without an injected key** — any dev build — mints a throwaway
  keypair on the spot, leaving the private half beside the public one. That
  makes the whole signing chain testable end to end: sign a manifest with the
  private half, watch `advisor_verify_release` accept it, and watch it refuse
  everyone else's.

A dev image therefore trusts only its own throwaway key. That is a feature,
not a gap: an image built outside the production pipeline cannot verify — and
so will not install — anything the real release pipeline signs, and vice
versa. Which key any given image trusts is auditable on the image itself:

```sh
hex_config advisor_pubkey
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
anchor:

```sh
hex_config advisor_pubkey > release.pub
openssl dgst -sha256 -verify release.pub -signature manifest.txt.sig manifest.txt
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

Rotating means injecting the new public key into the production build and
rebuilding the image; nodes running an older image continue to trust the older
key, so the release pipeline must keep signing with both until those nodes are
updated. Image-baked keys make rotation a release, so treat the key as
long-lived and protect the private half accordingly.
