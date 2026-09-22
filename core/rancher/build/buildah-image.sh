#!/usr/bin/env bash

set -o errexit

TAG=$1
if [ -z $SRCDIR ] ; then
    SRCDIR="/root/workspace/cube/core/rancher/"
fi

# Base on the image build-from-source.sh produced.  This used to pull
# docker.io/rancher/rancher:$TAG, but Docker Hub carries no tag past v2.11.3 on
# the 2.11 line -- everything newer is Prime-only, and a Prime base would defeat
# the whole point of this overlay (it ships SUSE's branding, and its terms
# forbid us redistributing it in a CubeOS package).
BASE_IMAGE=${BASE_IMAGE:-localhost/bigstack/rancher-upstream:$TAG}

ctr=$(buildah from $BASE_IMAGE)

buildah copy $ctr $SRCDIR/build/ui/assets/images/logos/ /usr/share/rancher/ui/assets/images/logos/
buildah copy $ctr $SRCDIR/build/ui-dashboard/dashboard/_nuxt/static/* /usr/share/rancher/ui-dashboard/dashboard/

buildah commit $ctr localhost/bigstack/rancher:$TAG
buildah rm $ctr
