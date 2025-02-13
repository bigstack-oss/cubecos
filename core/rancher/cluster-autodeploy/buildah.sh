#!/usr/bin/env bash

function cleanup()
{
    buildah rm $ctr || true
}
trap cleanup EXIT ERR

set -o errexit

IMG=$1
if [ -z $SRCDIR ] ; then
    SRCDIR="/root/workspace/cube/core/rancher/cluster-autodeploy"
fi

ctr=$(buildah from docker.io/alpine:latest)

buildah run $ctr -- \
    apk add gcompat

buildah config --workingdir /opt/prometheus-am-executor $ctr
buildah copy $ctr $SRCDIR/executor.yml $SRCDIR/cluster_kubectl.sh ./prometheus-am-executor/prometheus-am-executor /opt/prometheus-am-executor

buildah run $ctr -- \
    sh -c "wget -qO- --no-check-certificate https://github.com/rancher/cli/releases/download/v2.6.0/rancher-linux-amd64-v2.6.0.tar.xz | tar -xJ --strip-components=2 -C /usr/local/bin/"
buildah run $ctr -- \
    wget https://dl.k8s.io/release/v1.23.0/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl
buildah run $ctr -- \
    chmod +x /usr/local/bin/kubectl

buildah config --cmd '[]' $ctr
buildah config --entrypoint '[ "./prometheus-am-executor", "-f", "executor.yml" ]' $ctr
#buildah config --entrypoint "./prometheus-am-executor -f executor.yml" $ctr

buildah commit $ctr $IMG
