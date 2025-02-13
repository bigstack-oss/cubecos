#!/usr/bin/env bash

set -o errexit

TAG=$1
if [ -z $SRCDIR ] ; then
    SRCDIR="/root/workspace/cube/core/keycloak/"
fi

ctr=$(buildah from quay.io/keycloak/keycloak:$TAG)

# buildah run $ctr cp -rf /opt/jboss/keycloak/themes/keycloak/ /opt/jboss/keycloak/themes/cube/
buildah copy $ctr $SRCDIR/build/themes/ /opt/jboss/keycloak/themes/

buildah commit $ctr localhost:5080/bigstack/keycloak:$TAG
buildah rm $ctr
