#!/bin/bash
#
# ceph_mirror_unpair: ceph_mirror_disable deletes the peer's volume for every mirrored
# image, so unpair refuses on a site where a mirrored image is non-primary (the live
# copy is on the peer) and goes ahead where every image is primary.
#
#   Run: bash test_ceph_mirror_unpair.sh       (needs jq)
#   SRC=<other sdk_ceph.sh> bash test_ceph_mirror_unpair.sh   runs it against another copy
#

SRC=${SRC:-$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh}
if ! command -v jq >/dev/null 2>&1 ; then
    echo "SKIP: jq is not installed"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

sed -n "/^ceph_mirror_unpair()/,/^}/p" "$SRC" > "$T/fn.sh"
# shellcheck disable=SC1091
source "$T/fn.sh"

# shellcheck disable=SC2034 # used by the sourced function
BUILTIN_BACKPOOL=cinder-volumes HEX_SDK=hex_sdk
PEER_VIP=10.0.0.2
# image name -> "true"/"false" (primary on this site)
declare -A PRIMARY
ceph_mirror_peer_vip(){ echo "$PEER_VIP"; }
ceph_mirror_disable(){ echo local-disable >> "$T/calls"; }
ceph_mirror_tuning_clear(){ :; }
Quiet(){ [ "$1" = -n ] && shift; "$@"; }
cmd(){ :; }
find(){ :; }
ssh(){ echo "ssh ${*: -1}" >> "$T/calls"; }
timeout(){ shift; "$@"; }
rbd(){
    case "$1 $2" in
        "mirror pool")
            if [ "$3" = status ] && [ "$4" = cinder-volumes ] && [ "$5" = --verbose ] ; then
                [ "${STATUS_RC:-0}" -eq 0 ] || return "$STATUS_RC"
                local n out=""
                for n in "${!PRIMARY[@]}" ; do out="$out{\"name\":\"$n\"},"; done
                echo "{\"images\":[${out%,}]}"
            fi
            ;;
        "info cinder-volumes/"*)
            # an empty entry stands for rbd info failing
            [ -n "${PRIMARY[${2#cinder-volumes/}]}" ] || return 2
            echo "{\"mirroring\":{\"primary\":${PRIMARY[${2#cinder-volumes/}]}}}"
            ;;
    esac
}

run(){ : > "$T/calls"; ceph_mirror_unpair > "$T/out" 2> "$T/err"; echo $?; }

PRIMARY=([volume-a]=false [volume-b]=true)
chk "non-primary image: refused" "$(run)" 1
chk "non-primary image: nothing disabled" "$(grep -c disable "$T/calls")" 0
chk "non-primary image: names the image and peer" "$(head -1 "$T/err")" \
    "Error: not unpairing: these volumes are primary on 10.0.0.2 and unpair here would delete them there: volume-a"

PRIMARY=([volume-a]=true [volume-b]=true)
chk "all primary: unpairs" "$(run)" 0
chk "all primary: local and peer disable" "$(grep -c disable "$T/calls")" 2

PRIMARY=()
chk "no mirrored image: unpairs" "$(run)" 0
chk "no mirrored image: local disable runs" "$(grep -c local-disable "$T/calls")" 1

PRIMARY=([volume-a]=true [volume-b]='')
chk "rbd info fails: refused" "$(run)" 1
chk "rbd info fails: nothing disabled" "$(grep -c disable "$T/calls")" 0

PRIMARY=([volume-a]=true)
STATUS_RC=124
chk "listing times out: refused" "$(run)" 1
chk "listing times out: nothing disabled" "$(grep -c disable "$T/calls")" 0
chk "listing times out: says so" "$(head -1 "$T/err")" \
    "Error: not unpairing: cannot list the mirrored volumes (rbd exit 124), try again"
STATUS_RC=22
chk "mirroring not enabled: unpairs" "$(run)" 0
STATUS_RC=0

# no peer config: nothing to delete over there, keep the old "already unpaired" path
PEER_VIP=''
PRIMARY=([volume-a]=false)
chk "no peer: not refused" "$( (ceph_mirror_unpair) > "$T/out" 2> "$T/err"; echo $?)" 0
chk "no peer: already unpaired" "$(cat "$T/out")" 'already unpaired'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
