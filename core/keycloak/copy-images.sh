#!/bin/bash

set -o errexit

IMGS="$@"
if [ -z $REGISTRY ]
then
    REGISTRY="localhost:5080"
fi

for i in $IMGS; do
    src=$i
    nametag=$(echo $i | cut -d/ -f2-)

    if [[ $i =~ ^[a-zA-Z0-9\\-]+\.[a-zA-Z0-9\\-\\.]+/ ]]; then
        src="docker://$i"
        nametag=$(echo $i | cut -d/ -f2-)
    elif ! [[ $i =~ ^containers-storage: ]]; then
        src="docker://docker.io/$i"
        nametag=$i
    fi

    skopeo copy $src docker://$REGISTRY/$nametag --dest-tls-verify=false
done
