#!/bin/bash

registry="localhost:5080"
if [ -n "$REGISTRY" ]
then
    registry=$REGISTRY
fi

imagesDir=$1
cd $imagesDir
skopeo copy docker-archive:postgresql-11.11.0-debian-10-r31.tar docker://$registry/bitnami/postgresql:11.11.0-debian-10-r31 --dest-tls-verify=false
