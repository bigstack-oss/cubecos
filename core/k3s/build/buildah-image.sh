#!/usr/bin/env bash

set -o errexit

TAG=$1
if [ -z $SRCDIR ] ; then
    SRCDIR="/root/workspace/cube/core/k3s/"
fi

ctr=$(buildah from alpine:latest)

buildah run $ctr apk update
buildah run $ctr apk add --no-cache bash curl jq openssh-client sshpass
buildah run $ctr mkdir -p /var/alert_resp

buildah config --entrypoint '["/bin/sh","-c","trap : TERM INT; sleep infinity & wait"]' $ctr

buildah commit $ctr localhost/bigstack/shell:latest
buildah rm $ctr