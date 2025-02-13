#!/bin/bash

registry="localhost:5080"
if [ -n "$REGISTRY" ]
then
    registry=$REGISTRY
fi

push() {
    imagesDir=$1
    (cd $imagesDir && \
        for f in $(find * -type f)
        do
            # local path=$(echo $f | cut -d~ -f1)
            # local tag=$(basename $(echo $f | cut -d~ -f2) .tar)
            local file=${f%.*}
            skopeo copy docker-archive:$f docker://$registry/${file/@/:} --dest-tls-verify=false
        done
    )
}

pull() {
    images=$(cat "$1")
    dir=$(basename "$1" .txt)
    for img in $images
    do
        # local path=$(echo $i | cut -d: -f1)
        # local tag=$(echo $i | cut -d: -f2)
        mkdir -p ./${dir}/$(dirname "$img")
        #skopeo copy docker://$img docker-archive:./${dir}/${path}~${tag}.tar:${path}:${tag}
        skopeo copy docker://$img docker-archive:${dir}/${img/:/@}.tar:${img}
    done
}

if [ "$1" == "push" ]
then
    shift
    push "$@"
elif [ "$1" == "pull" ]
then
    shift
    pull "$@"
fi