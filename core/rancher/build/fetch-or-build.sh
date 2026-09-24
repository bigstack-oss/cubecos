#!/usr/bin/env bash
#
# Produce the Rancher server image, agent image and server chart -- from a cache if one is
# configured and holds this exact version, otherwise by building them from upstream source.
#
# Why a cache at all: build-from-source.sh runs two podman builds of the upstream tree and took
# 3982 s (66 min) in cubecos prod #750. It reruns on *every* build, not just a distclean, because
# the jail container is recreated each time and podman's storage goes with it -- so the same bytes
# are rebuilt for a version that only moves on a deliberate bump (cubecos#1350).
#
# RANCHER_CACHE is EMPTY BY DEFAULT and that is deliberate: a clean checkout builds from upstream
# source exactly as it always has. Nobody outside our CI needs access to anything of ours to build
# this repo, and nothing here fails if the cache is unreachable -- it falls back to the source
# build, which is the behaviour it replaced.
#
#   RANCHER_CACHE=<host>/<repo> ./fetch-or-build.sh v2.11.16 [outdir]
#
# Populate the cache with the cube_publish_artifacts job in triangle; see
# triangle/artifact_keeper/README.md.
set -uo pipefail

TAG=${1:?usage: fetch-or-build.sh v<version> [outdir]}
OUTDIR=${2:-$PWD}
VERSION=${TAG#v}
HERE=$(cd "$(dirname "$0")" && pwd)

CACHE=${RANCHER_CACHE:-}
SERVER_IMAGE=${IMAGE:-localhost/bigstack/rancher-upstream:$TAG}
AGENT_IMAGE=${AGENT_IMAGE:-localhost/rancher/rancher-agent:$TAG}
CHART="$OUTDIR/rancher-${VERSION}.tgz"

build_from_source() {
    echo "==> building Rancher $TAG from upstream source"
    exec sh "$HERE/build-from-source.sh" "$TAG" "$OUTDIR"
}

[ -n "$CACHE" ] || { echo "RANCHER_CACHE not set -- building from source"; build_from_source; }

echo "==> checking cache $CACHE for Rancher $TAG"

# All three or nothing. A partially populated cache must not leave a half-built tree that then
# fails much later in copy-image with an image nothing produced.
if ! skopeo inspect --retry-times 2 "docker://$CACHE/bigstack/rancher-upstream:$TAG" >/dev/null 2>&1 \
   || ! skopeo inspect --retry-times 2 "docker://$CACHE/rancher/rancher-agent:$TAG" >/dev/null 2>&1 ; then
    echo "    cache miss (images) -- building from source"
    build_from_source
fi

echo "==> pulling server image from cache"
if ! skopeo copy --retry-times 3 --preserve-digests \
        "docker://$CACHE/bigstack/rancher-upstream:$TAG" \
        "containers-storage:$SERVER_IMAGE" ; then
    echo "    pull failed -- building from source"
    build_from_source
fi

echo "==> pulling agent image from cache"
if ! skopeo copy --retry-times 3 --preserve-digests \
        "docker://$CACHE/rancher/rancher-agent:$TAG" \
        "containers-storage:$AGENT_IMAGE" ; then
    echo "    pull failed -- building from source"
    build_from_source
fi

echo "==> pulling server chart from cache"
rm -f "$CHART"
if ! ( cd "$OUTDIR" && helm pull "oci://$CACHE/rancher" --version "$VERSION" >/dev/null 2>&1 ) \
   || [ ! -s "$CHART" ] ; then
    echo "    cache miss (chart) -- building from source"
    build_from_source
fi

# The chart's rancherImage default is the one thing a wrongly-packaged chart gets silently wrong:
# a chart built with REGISTRY=registry.rancher.com bakes in the Prime image path, which we cannot
# redistribute. Fail here rather than ship it -- this is the one case where a configured cache can
# make the build fail instead of falling back, and that is deliberate: a cache serving an
# unredistributable chart is a problem to fix, not to paper over with a silent source build.
#
# Remove it first. $(CHART) is a bare file target with no prerequisites and the tree sets no
# .DELETE_ON_ERROR, so a rejected chart left on disk is reported up to date by the next
# incremental make, and install: would ship the very chart this check just refused.
if ! tar xzOf "$CHART" rancher/values.yaml | grep -qE '^rancherImage: *rancher/rancher$' ; then
    echo "ERROR: cached chart's rancherImage is not the community rancher/rancher:" >&2
    tar xzOf "$CHART" rancher/values.yaml | grep -E '^rancherImage:' >&2 || true
    rm -f "$CHART"
    exit 1
fi

echo "==> cache hit: Rancher $TAG restored without a source build"
podman image inspect "$SERVER_IMAGE" --format 'server: {{.Id}} {{.Size}} bytes'
podman image inspect "$AGENT_IMAGE"  --format 'agent : {{.Id}} {{.Size}} bytes'
echo "chart: $CHART"
