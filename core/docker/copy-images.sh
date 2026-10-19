#!/bin/bash

set -o errexit

IMGS="$@"
if [ -z $REGISTRY ]
then
    REGISTRY="localhost:5080"
fi

# A copy costs 2-3 s of registry round trips whatever the image's size (a 1 MB
# busybox takes as long as a 100 MB one), so copying one at a time is mostly
# waiting: 37 images take 146 s, 34 s eight at a time. COPY_JOBS copies run at
# once. A line naming an image another line already names (docker.io/goharbor/x
# and goharbor/x) is copied once. Any failed copy still fails the script: xargs
# exits non-zero, and it is the last command of the pipeline.
COPY_JOBS=${COPY_JOBS:-8}

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

    echo "$src docker://$REGISTRY/$nametag"
done | sort -u | xargs -r -n 2 -P "$COPY_JOBS" \
    skopeo copy --dest-tls-verify=false --preserve-digests --retry-times 3
