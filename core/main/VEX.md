# VEX

`cubecos.openvex.json` is an [OpenVEX](https://github.com/openvex/spec) document listing
scanner findings that have been triaged as not affecting CubeCOS. The Makefile passes it to
grype through `PROJ_VEX`, so every statement in it moves the matching findings from `matches`
to `ignoredMatches` in the release's `*_vuln.json`. Once a finding no longer appears in
`matches`, the next production scan closes the issue it filed for it.

## Adding a statement

- Anyone may propose a statement, through a pull request like any other change here; the
  code owners review it, and it needs the verdict in the tracking issue to be approved.
- Use `"status": "not_affected"` only, with one of the OpenVEX `justification` values.
- Add a statement only after the finding has been re-checked in a tracking issue, and point
  `impact_statement` at that issue. Keep the reasoning in the issue, not here: this repository
  is public.
- `vulnerability.name` must be the id grype reports for the match (`vulnerability.id` in
  `*_vuln.json`), e.g. the GHSA id for Go and Python packages. Put the CVE id in `aliases`.
- `products[].@id` is the package purl from the match's `artifact.purl`, without the version,
  so the statement keeps applying across rebuilds. Do not use the SBOM itself as the product:
  grype does not match that form.
- When a finding matches several packages, cover only the packages that were triaged. The
  others stay in `matches` and may keep the issue open.
- A package from the distro feed (`pkg:rpm/...`) is covered the same way, by its unversioned
  purl, e.g. `pkg:rpm/centos/podman`. Name the id grype reports for that match, which for
  the distro feed is usually the CVE itself.
- Bump `version` and `timestamp` whenever the document changes.

## Removing a statement

Remove it when either of these happens:

- the package is upgraded or replaced and the finding no longer matches;
- the reason in the tracking issue stops holding, e.g. the vulnerable code becomes reachable,
  a disabled component is enabled, or the input becomes attacker controlled.

When you remove a statement, re-check the finding and make sure its tracking issue is open.
