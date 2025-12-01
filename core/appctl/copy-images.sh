#!/bin/bash

registry="localhost:5080"
if [ -n "$REGISTRY" ]
then
    registry=$REGISTRY
fi

imagesDir=$1
cd $imagesDir

for f in $(find * -type f)
do
    file=${f%.*}
    skopeo copy docker-archive:$f docker://$registry/${file/@/:} --dest-tls-verify=false
done
