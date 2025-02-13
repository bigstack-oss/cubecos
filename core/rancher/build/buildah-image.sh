#!/usr/bin/env bash

set -o errexit

TAG=$1
if [ -z $SRCDIR ] ; then
    SRCDIR="/root/workspace/cube/core/rancher/"
fi

ctr=$(buildah from docker.io/rancher/rancher:$TAG)

buildah copy $ctr $SRCDIR/build/ui/assets/images/logos/ /usr/share/rancher/ui/assets/images/logos/
buildah copy $ctr $SRCDIR/build/ui-dashboard/dashboard/_nuxt/static/* /usr/share/rancher/ui-dashboard/dashboard/

buildah commit $ctr localhost/bigstack/rancher:$TAG
buildah rm $ctr
