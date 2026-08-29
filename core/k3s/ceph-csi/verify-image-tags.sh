#!/bin/sh
# CUBE SDK
#
# The ceph-csi charts are fetched from upstream at build time and decide which
# sidecar images kubelet requests at run time. The tags bundled into the
# offline image set are separate constants, in this directory's Makefile and in
# cubectl's csi-drivers.go. A tag that drifts from the chart is invisible until
# an air-gapped install reaches ImagePullBackOff with no upstream to fall back
# to, so the build refuses to package a mismatch.
#
# usage: verify-image-tags.sh <go-file> <chart.tgz>... -- <repo:tag>...

set -e

GO_FILE=$1
shift

CHARTS=""
while [ $# -gt 0 ] && [ "$1" != "--" ] ; do
    CHARTS="$CHARTS $1"
    shift
done
[ "$1" = "--" ] && shift
BUNDLED=$@

# Every distinct image the charts ask for, as repository:tag.
REQUIRED=$(for chart in $CHARTS ; do
    tar -xzOf "$chart" '*/values.yaml' | awk '
        /repository:/ { repo = $2 ; next }
        /tag:/        { if (repo != "") { print repo ":" $2 ; repo = "" } }
    '
done | sort -u)

RC=0
for image in $REQUIRED ; do
    case " $BUNDLED " in
        *" $image "*) ;;
        *)
            echo "ceph-csi: chart requires $image, which the offline bundle does not contain" >&2
            RC=1
            ;;
    esac

    # cubectl loads the bundle and pushes it into the cluster registry under
    # its own constants; a tag that is bundled but not loaded is equally fatal.
    tag=${image##*:}
    name=${image%:*}
    name=${name#*/}
    if ! grep -q "\"$name\"" "$GO_FILE" ; then
        echo "ceph-csi: $name is not in $GO_FILE" >&2
        RC=1
    elif ! grep -A1 "\"$name\"" "$GO_FILE" | grep -q "\"$tag\"" ; then
        loaded=$(grep -A1 "\"$name\"" "$GO_FILE" | sed -n 's/.*Tag: *"\(.*\)".*/\1/p')
        echo "ceph-csi: $GO_FILE loads $name:$loaded but the chart requests $tag" >&2
        RC=1
    fi
done

[ $RC -eq 0 ] || echo "ceph-csi: refusing to build an offline bundle the charts cannot use" >&2
exit $RC
