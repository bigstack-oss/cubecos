#!/usr/bin/env bash
#
# Build the Rancher server image from upstream source instead of pulling a
# prebuilt one.
#
# From 2.11.4 on, Rancher publishes prebuilt server images only through the
# Prime channel (registry.rancher.com).  Those carry SUSE's Prime branding and
# subscription terms, so we can neither rebrand them for CubeOS nor redistribute
# them inside a cube-portal package.  The source stays Apache-2.0 and the only
# base images the build needs are SUSE's freely redistributable BCI line, so we
# build the tag ourselves and get an image we own.
#
# Mirrors upstream dev-scripts/quick (their Dapper-less server build): the build
# args all come from the checkout -- build.yaml, go.mod, package/Dockerfile --
# so they stay correct for whatever tag is requested rather than being pinned
# here.
#
# The server chart is built from the same checkout for the same reason: the
# packaged chart on the Prime repo is this Apache-2.0 source built with
# REGISTRY=registry.rancher.com, which is what bakes the Prime image path into
# its rancherImage default.  Building it ourselves leaves that default at the
# community `rancher/rancher`, and our own values override it anyway.
#
# Outputs:
#   localhost/bigstack/rancher-upstream:v<version>  -- buildah-image.sh then
#                                                      overlays the Bigstack UI
#                                                      assets onto this
#   localhost/rancher/rancher-agent:v<version>      -- the agent, which is
#                                                      Prime-gated too; keeping
#                                                      the rancher/ prefix means
#                                                      the name Rancher hands to
#                                                      downstream clusters
#                                                      resolves through the
#                                                      offline registry mirror
#   <outdir>/rancher-<version>.tgz                  -- the server chart
#
# Usage:  ./build-from-source.sh v2.11.16 [outdir]
#
set -euo pipefail

TAG=${1:?usage: build-from-source.sh v<version> [outdir]}
OUTDIR=${2:-$PWD}
REPO=${REPO:-rancher}
ARCH=${ARCH:-amd64}
IMAGE=${IMAGE:-localhost/bigstack/rancher-upstream:$TAG}
AGENT_IMAGE=${AGENT_IMAGE:-localhost/rancher/rancher-agent:$TAG}
SRC_REPO=${SRC_REPO:-https://github.com/rancher/rancher.git}
WORKDIR=${WORKDIR:-$(mktemp -d)}
KEEP_WORKDIR=${KEEP_WORKDIR:-0}

[ "$KEEP_WORKDIR" = "1" ] || trap 'rm -rf "$WORKDIR"' EXIT

step() { printf '\n\033[1m=== %s\033[0m\n' "$*"; }

if [ -d "$WORKDIR/rancher/.git" ]; then
    step "Reuse checkout at $WORKDIR/rancher"
else
    step "Clone $SRC_REPO at $TAG"
    git clone --depth 1 --branch "$TAG" "$SRC_REPO" "$WORKDIR/rancher"
fi
cd "$WORKDIR/rancher"

# Every value below is read out of the checkout, the same way upstream's
# dev-scripts/quick does it -- do not hardcode them, they move per tag.
step "Derive build args from the checkout"
COMMIT=$(git rev-parse --short HEAD)
CATTLE_KDM_BRANCH=$(grep -m1 'ARG CATTLE_KDM_BRANCH=' package/Dockerfile | cut -d= -f2)
RKE_VERSION=$(grep -m1 'github.com/rancher/rke' go.mod | awk '{print $2}')
[ -n "$RKE_VERSION" ] || RKE_VERSION=$(grep -m1 'github.com/rancher/rke' go.mod | awk '{print $4}')

by() { grep -m1 "$1" build.yaml | cut -d' ' -f2; }
CATTLE_RANCHER_WEBHOOK_VERSION=$(by webhookVersion)
CATTLE_REMOTEDIALER_PROXY_VERSION=$(by remoteDialerProxyVersion)
CATTLE_CSP_ADAPTER_MIN_VERSION=$(by cspAdapterMinVersion)
CATTLE_RANCHER_PROVISIONING_CAPI_VERSION=$(by provisioningCAPIVersion)
CATTLE_FLEET_VERSION=$(by fleetVersion)
CATTLE_DEFAULT_SHELL_VERSION=$(by defaultShellVersion)

cat <<EOF
  commit        : $COMMIT
  kdm branch    : $CATTLE_KDM_BRANCH
  rke           : $RKE_VERSION
  webhook       : $CATTLE_RANCHER_WEBHOOK_VERSION
  rd-proxy      : $CATTLE_REMOTEDIALER_PROXY_VERSION
  csp-adapter   : $CATTLE_CSP_ADAPTER_MIN_VERSION
  capi          : $CATTLE_RANCHER_PROVISIONING_CAPI_VERSION
  fleet         : $CATTLE_FLEET_VERSION
  default shell : $CATTLE_DEFAULT_SHELL_VERSION
EOF

# Upstream drops this into the build context before building; the kdm stage
# expects it there.
step "Fetch kontainer-driver-metadata ($CATTLE_KDM_BRANCH)"
curl -sSLf "https://releases.rancher.com/kontainer-driver-metadata/${CATTLE_KDM_BRANCH}/data.json" -o ./data.json
echo "  data.json: $(wc -c < ./data.json) bytes"

# `COPY --from=<image>` on an image that is not a build stage: buildkit pulls it
# implicitly, buildah does not, and podman here runs short-name-mode=enforcing,
# so an unqualified ref fails outright ("no stage or image found with that
# name").  Pull each such image fully qualified and tag it under the bare name
# the Dockerfile uses.  Derived by diffing --from= targets against the declared
# stage names, so it keeps working when upstream changes the reference.
step "Pre-pull images referenced by COPY --from"
stages=$(grep -oE '^FROM .* AS [A-Za-z0-9_-]+' package/Dockerfile | awk '{print $NF}' | sort -u)
externals=$(grep -ohE -- '--from=[A-Za-z0-9._/:-]+' package/Dockerfile \
              | sed 's/--from=//' | sort -u \
              | grep -vxF "$stages" || true)
if [ -z "$externals" ]; then
    echo "  none"
else
    for ref in $externals; do
        echo "  $ref"
        podman pull "docker.io/$ref"
        podman tag "docker.io/$ref" "$ref"
    done
fi

step "Build $IMAGE (target: server)"
podman build \
  --target server \
  --file ./package/Dockerfile \
  --platform "linux/${ARCH}" \
  --build-arg "VERSION=$TAG" \
  --build-arg "ARCH=$ARCH" \
  --build-arg "IMAGE_REPO=$REPO" \
  --build-arg "COMMIT=$COMMIT" \
  --build-arg "RKE_VERSION=$RKE_VERSION" \
  --build-arg "RANCHER_TAG=$TAG" \
  --build-arg "RANCHER_REPO=$REPO" \
  --build-arg "CATTLE_RANCHER_WEBHOOK_VERSION=$CATTLE_RANCHER_WEBHOOK_VERSION" \
  --build-arg "CATTLE_REMOTEDIALER_PROXY_VERSION=$CATTLE_REMOTEDIALER_PROXY_VERSION" \
  --build-arg "CATTLE_RANCHER_PROVISIONING_CAPI_VERSION=$CATTLE_RANCHER_PROVISIONING_CAPI_VERSION" \
  --build-arg "CATTLE_CSP_ADAPTER_MIN_VERSION=$CATTLE_CSP_ADAPTER_MIN_VERSION" \
  --build-arg "CATTLE_FLEET_VERSION=$CATTLE_FLEET_VERSION" \
  -t "$IMAGE" \
  .

# Downstream cluster agents pull the tag Rancher advertises, and with
# IMAGE_REPO=rancher that is `rancher/rancher-agent:$TAG` -- absent from Docker
# Hub past 2.11.3.  Build it here and let copy-images.sh seed it into the
# on-cluster registry, which containerd mirrors docker.io to.
step "Build $AGENT_IMAGE (target: agent)"
podman build \
  --target agent \
  --file ./package/Dockerfile \
  --platform "linux/${ARCH}" \
  --build-arg "VERSION=$TAG" \
  --build-arg "ARCH=$ARCH" \
  --build-arg "RANCHER_TAG=$TAG" \
  --build-arg "RANCHER_REPO=$REPO" \
  --build-arg "CATTLE_RANCHER_WEBHOOK_VERSION=$CATTLE_RANCHER_WEBHOOK_VERSION" \
  --build-arg "CATTLE_RANCHER_PROVISIONING_CAPI_VERSION=$CATTLE_RANCHER_PROVISIONING_CAPI_VERSION" \
  -t "$AGENT_IMAGE" \
  .

# chart/Chart.yaml and chart/values.yaml ship with placeholders that upstream
# substitutes at package time (scripts/chart/build).  Deliberately NOT setting
# their $REGISTRY, so rancherImage stays the community `rancher/rancher` rather
# than being rewritten to the Prime registry.
step "Package the server chart ${TAG#v}"
CHART_SRC=$WORKDIR/chart-build/rancher
rm -rf "$CHART_SRC"; mkdir -p "$(dirname "$CHART_SRC")"
cp -rf chart "$CHART_SRC"

shell_name=${CATTLE_DEFAULT_SHELL_VERSION%:*}
shell_tag=${CATTLE_DEFAULT_SHELL_VERSION##*:}
sed -i -e "s/%VERSION%/${TAG#v}/g" -e "s/%APP_VERSION%/${TAG}/g" "$CHART_SRC/Chart.yaml"
sed -i -e "s@%POST_DELETE_IMAGE_NAME%@${shell_name}@g" \
       -e "s/%POST_DELETE_IMAGE_TAG%/${shell_tag}/g" "$CHART_SRC/values.yaml"

if grep -rn '%[A-Z_]*%' "$CHART_SRC/Chart.yaml" "$CHART_SRC/values.yaml"; then
    die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
    die "unsubstituted placeholder left in the chart -- upstream added one; check scripts/chart/build at $TAG"
fi

mkdir -p "$OUTDIR"
helm package -d "$OUTDIR" "$CHART_SRC" >/dev/null
CHART_TGZ="$OUTDIR/rancher-${TAG#v}.tgz"

step "Result"
podman image inspect "$IMAGE" --format 'server: {{.Id}} {{.Size}} bytes'
podman image inspect "$AGENT_IMAGE" --format 'agent : {{.Id}} {{.Size}} bytes'
echo "chart: $CHART_TGZ"
tar xzOf "$CHART_TGZ" rancher/Chart.yaml | grep -E "^version|^appVersion" | sed "s/^/  /"
echo "  rancherImage default: $(tar xzOf "$CHART_TGZ" rancher/values.yaml | grep -E "^rancherImage:")"
echo "next: buildah-image.sh overlays the Bigstack UI assets onto $IMAGE"
