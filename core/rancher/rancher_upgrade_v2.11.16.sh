#!/bin/bash
#
# Upgrade the CubeOS Rancher server + CLI in place.
#
# 2.11.16 fixes CVE-2026-44945 (GHSA-v584-7w32-jwpq, critical 9.1): a
# confused-deputy in Rancher's impersonation middleware lets any authenticated
# user with the default `user` role escalate to system:masters on the local
# cluster.  Affected: >=2.11.0,<2.11.16 -- so the 2.11.2 CubeOS ships is exposed.
#
# NOTE: Rancher 2.11.4 and later are published as Prime releases -- the chart
# lives at charts.rancher.com/server-charts/prime and the image at
# registry.rancher.com instead of Docker Hub (which stops at v2.11.3 on this
# line).  Both are pullable anonymously; no subscription is needed.  A bare
# `curl https://registry.rancher.com/v2/` answering 401 is just the bearer-token
# challenge, not a paywall -- skopeo/containerd follow it and pull fine.
# PRIME_USER / PRIME_PASSWORD stay available for a registry that does require
# credentials.
#
# Usage:
#   PRIME_USER=... PRIME_PASSWORD=... ./rancher_upgrade_v2.11.16.sh
#
#   # community build (no subscription; 2.11.3 is the last one published there)
#   VERSION=2.11.3 \
#   CHART_REPO_URL=https://releases.rancher.com/server-charts/stable \
#   IMAGE_REPO=docker.io/rancher/rancher \
#     ./rancher_upgrade_v2.11.16.sh
#
#   # air-gapped: mirror the images into the on-cluster registry and deploy
#   # from there.  Seeds rancher + rancher-agent only; the bundled system
#   # charts (rancher-webhook, fleet, ...) still need core/rancher/images.txt
#   # refreshed and baked -- see cubecos#1230.
#   SEED_OFFLINE=1 ./rancher_upgrade_v2.11.16.sh
#
set -euo pipefail

VERSION=${VERSION:-${1:-2.11.16}}
CHART_REPO_URL=${CHART_REPO_URL:-https://charts.rancher.com/server-charts/prime}
# Offline sites have no route to a chart repo, and CubeOS keeps the packaged
# chart on disk anyway.  Point CHART_FILE at it (or at the one shipped in the
# upgrade bundle) to skip the repo entirely.
CHART_FILE=${CHART_FILE:-}
IMAGE_REPO=${IMAGE_REPO:-registry.rancher.com/rancher/rancher}
OFFLINE_REGISTRY=${OFFLINE_REGISTRY:-localhost:5080}
SEED_OFFLINE=${SEED_OFFLINE:-0}
CLI_VERSION=${CLI_VERSION:-$VERSION}

# The on-cluster registry speaks plain HTTP, and skopeo -- unlike docker -- does
# not treat localhost as insecure, so the preflight below would die with
# "server gave HTTP response to HTTPS client" and abort the upgrade before it
# started.  Default TLS off when the image comes from that registry, on
# otherwise; override with IMAGE_TLS_VERIFY if a site differs.
case "${IMAGE_REPO%%/*}" in
    localhost:*|127.0.0.1:*|"${OFFLINE_REGISTRY%%/*}"|*:"${OFFLINE_REGISTRY##*:}")
        IMAGE_TLS_DEFAULT=false ;;
    *)  IMAGE_TLS_DEFAULT=true  ;;
esac
IMAGE_TLS_VERIFY=${IMAGE_TLS_VERIFY:-$IMAGE_TLS_DEFAULT}

NAMESPACE=cattle-system
RELEASE=rancher
KUBECONFIG_FILE=/etc/rancher/k3s/k3s.yaml
PULL_SECRET=rancher-upgrade-registry
REPO_NAME=rancher-upgrade-src

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

step() { printf '\n\033[1m=== %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

h()  { helm --kubeconfig "$KUBECONFIG_FILE" "$@"; }
kc() { k3s kubectl "$@"; }

# ---------------------------------------------------------------- preflight ---
step "Preflight"

kc get ns "$NAMESPACE" >/dev/null 2>&1 || die "namespace $NAMESPACE not found -- is this a control node?"
h status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || die "helm release $RELEASE not found in $NAMESPACE"

FROM=$(kc -n "$NAMESPACE" get deploy "$RELEASE" \
         -o jsonpath='{.spec.template.spec.containers[0].image}')
REPLICAS=$(kc get nodes -o go-template='{{len .items}}')
echo "current image  : $FROM"
echo "target version : v$VERSION"
echo "replicas       : $REPLICAS (one per node)"

# Stay on the 2.11 line unless someone has done the migration work.  Two things
# break otherwise: the chart renamed the image values (2.13+ takes
# image.repository / image.tag, so the --set rancherImage below silently does
# nothing), and 2.14.0 removed the embedded rancher-provisioning-capi that CMP's
# cluster lifecycle is built on -- the worker and the portal both drive
# /v1/provisioning.cattle.io.clusters and
# /v1/rke-machine-config.cattle.io.openstackconfigs.  2.12+ also requires every
# managed cluster to be k8s >=1.31, and 2.14 drops k8s 1.32, which is what CMP
# provisions today.
case "$VERSION" in
    2.11.*) ;;
    *) [ "${ALLOW_MINOR_JUMP:-0}" = "1" ] \
         || die "target $VERSION leaves the 2.11 line.  CMP needs the embedded
  CAPI that 2.14 removed, and this script sets the 2.11-era image values.  Set
  ALLOW_MINOR_JUMP=1 only after porting CMP to Rancher Turtles." ;;
esac

# CubeOS runs one rancher replica per node with `antiAffinity: required`, and
# the chart rolls with maxSurge=1/maxUnavailable=0.  Because replicas equals the
# node count and the anti-affinity topologyKey is the hostname, the surge pod
# has nowhere to land: it sits Pending indefinitely while the old pod keeps
# serving, so the upgrade silently never completes.  A fresh install never hits
# this -- there is no incumbent pod to conflict with.
#
# Relaxing antiAffinity to `preferred` does NOT fix it.  The scheduler also
# honours the *running* pod's term, which is still `required` at that point
# ("didn't satisfy existing pods anti-affinity rules"), so the replacement is
# still unplaceable.  The incumbent has to go first.  Hence the surge-free
# strategy patched in after the upgrade below: replicas are replaced in place,
# one at a time.  On multi-node controllers the remaining replicas keep serving;
# on a single-node controller the API is briefly unavailable while the pod
# restarts, which is unavoidable when the only replica is the one being changed.

[ "$FROM" = "${IMAGE_REPO}:v${VERSION}" ] && { echo "already on the target image; nothing to do"; exit 0; }

# Values are read back from the live release rather than restated here, so a
# field an operator set through Rancher's Apps UI is not silently reverted to
# the chart default (see the reuse-values footgun in cubecos deploys).
h get values "$RELEASE" -n "$NAMESPACE" --output yaml > "$WORKDIR/values.yaml"
grep -q '[^[:space:]]' "$WORKDIR/values.yaml" || die "live release reported no user values -- refusing to guess"
echo "--- values carried forward"
cat "$WORKDIR/values.yaml"

# ------------------------------------------------------------------- source ---
if [ -n "$CHART_FILE" ]; then
    step "Use chart file $CHART_FILE"
    [ -f "$CHART_FILE" ] || die "CHART_FILE $CHART_FILE does not exist"
    CHART=$CHART_FILE
else
    step "Resolve chart $VERSION from $CHART_REPO_URL"
    h repo add "$REPO_NAME" "$CHART_REPO_URL" --force-update >/dev/null
    h repo update "$REPO_NAME" >/dev/null
    h pull "$REPO_NAME/rancher" --version "$VERSION" -d "$WORKDIR" >/dev/null \
      || die "chart rancher-$VERSION is not in $CHART_REPO_URL"
    CHART="$WORKDIR/rancher-$VERSION.tgz"
fi
CHART_APPVER=$(tar xzOf "$CHART" rancher/Chart.yaml | awk '/^appVersion:/{print $2}')
[ "$CHART_APPVER" = "v$VERSION" ] \
  || die "chart appVersion ($CHART_APPVER) does not match target v$VERSION"
echo "chart: $CHART (appVersion $CHART_APPVER)"

# The image is the half that a Prime subscription gates, so prove it is
# reachable *before* helm touches the release -- a failed pull otherwise leaves
# the deployment mid-rollout with the old pod already terminating.
step "Verify $IMAGE_REPO:v$VERSION is pullable (tls-verify=$IMAGE_TLS_VERIFY)"

SKOPEO_CREDS=()
if [ -n "${PRIME_USER:-}" ]; then
    SKOPEO_CREDS=(--creds "${PRIME_USER}:${PRIME_PASSWORD:-}")
fi
skopeo inspect --tls-verify="$IMAGE_TLS_VERIFY" "${SKOPEO_CREDS[@]}" \
  "docker://${IMAGE_REPO}:v${VERSION}" >/dev/null \
  || die "cannot pull ${IMAGE_REPO}:v${VERSION}.
  Patches after 2.11.3 ship only through the Prime channel, so the image is at
  registry.rancher.com, not Docker Hub (which stops at v2.11.3 on this line).
  Check IMAGE_REPO/VERSION agree with the channel, and set
  PRIME_USER/PRIME_PASSWORD if the registry is one that wants credentials."
echo "ok"

DEPLOY_IMAGE=$IMAGE_REPO
if [ "$SEED_OFFLINE" = "1" ]; then
    step "Mirror images into $OFFLINE_REGISTRY"
    for img in rancher rancher-agent; do
        echo "  $img:v$VERSION"
        skopeo copy "${SKOPEO_CREDS[@]}" --dest-tls-verify=false --retry-times 3 \
          "docker://${IMAGE_REPO%/*}/${img}:v${VERSION}" \
          "docker://${OFFLINE_REGISTRY}/rancher/${img}:v${VERSION}"
    done
    DEPLOY_IMAGE="${OFFLINE_REGISTRY}/rancher/rancher"
fi

if [ -n "${PRIME_USER:-}" ] && [ "$SEED_OFFLINE" != "1" ]; then
    step "Create pull secret $PULL_SECRET"
    kc -n "$NAMESPACE" create secret docker-registry "$PULL_SECRET" \
      --docker-server="${IMAGE_REPO%%/*}" \
      --docker-username="$PRIME_USER" \
      --docker-password="${PRIME_PASSWORD:-}" \
      --dry-run=client -o yaml | kc apply -f -
    set -- --set "imagePullSecrets[0].name=$PULL_SECRET"
else
    set --
fi

# ------------------------------------------------------------------ upgrade ---
step "helm upgrade $RELEASE -> $VERSION"

h upgrade "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values "$WORKDIR/values.yaml" \
  --set "rancherImage=$DEPLOY_IMAGE" \
  --set "rancherImageTag=v$VERSION" \
  --set "replicas=$REPLICAS" \
  "$@"

# The chart re-asserts maxSurge=1/maxUnavailable=0 on every upgrade, so this
# has to be re-applied here rather than set once out of band.
step "Switch to a surge-free rollout"
kc -n "$NAMESPACE" patch "deploy/$RELEASE" --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'

step "Wait for rollout"
if ! kc -n "$NAMESPACE" rollout status "deployment/$RELEASE" --timeout=10m; then
    kc -n "$NAMESPACE" get pods -l app="$RELEASE" -o wide
    kc -n "$NAMESPACE" get events --field-selector reason=FailedScheduling | tail -5
    die "rollout did not converge -- see the pod state above"
fi

# ---------------------------------------------------------------------- cli ---
step "Upgrade the rancher CLI to v$CLI_VERSION on every control node"

if wget -qO- --no-check-certificate \
     "https://releases.rancher.com/cli2/v${CLI_VERSION}/rancher-linux-amd64-v${CLI_VERSION}.tar.gz" \
     | tar -xz --strip-components=2 -C /usr/local/bin/; then
    cubectl node rsync -r control /usr/local/bin/rancher
    echo "cli: $(rancher --version)"
else
    echo "WARN: CLI v${CLI_VERSION} not published on releases.rancher.com; leaving $(rancher --version) in place" >&2
fi

# --------------------------------------------------------------------- done ---
step "Result"
kc -n "$NAMESPACE" get deploy "$RELEASE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
h list -n "$NAMESPACE"
kc get clusters.management.cattle.io \
  -o custom-columns=NAME:.metadata.name,DISPLAY:.spec.displayName,K8S:.status.version.gitVersion
