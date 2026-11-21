#!/bin/bash
#
# ceph_mirror_image_enable: a clone is flattened before snapshot mirroring is enabled, a failed
# flatten enables nothing, and journal mode and non-clones are unchanged.
#
#   Run: bash test_ceph_mirror_enable_flatten.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=${SRC:-$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh}
sed -n "/^ceph_mirror_image_enable()/,/^}/p" "$SRC" > "$T/fn.sh"
source "$T/fn.sh"

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-52s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-52s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

BUILTIN_BACKPOOL=cinder-volumes
OPENSTACK=fake_openstack
HEX_SDK=fake_sdk
fake_openstack(){ echo '[]' ; }
fake_sdk(){ return 0 ; }
ceph_mirror_peer_vip(){ echo 192.0.2.2 ; }
cubectl(){ return 0 ; }
Quiet(){ [ "$1" = -n ] && shift ; eval "$*" >/dev/null 2>&1 ; return 0 ; }
ssh(){ echo "ssh $*" >> "$T/calls" ; }
rbd(){
    echo "rbd $*" >> "$T/calls"
    case "$1 $2" in
        "info "*)
            [ -e "$T/img/${2#*/}" ] || return 1
            [ "$3" = --format ] && cat "$T/img/${2#*/}"
            return 0 ;;
        "--no-progress flatten")
            [ -e "$T/flatten-fails" ] && { echo "rbd: flatten error: (16) Device or resource busy" >&2 ; return 1 ; }
            jq -c 'del(.parent)' "$T/img/${3#*/}" > "$T/tmp" && mv "$T/tmp" "$T/img/${3#*/}"
            return 0 ;;
    esac
    return 0
}
img(){ # name state mode primary parent(yes|no)
    local p=''
    [ "$5" = yes ] && p=',"parent":{"pool":"glance-images","image":"g1"}'
    echo "{\"mirroring\":{\"state\":\"$2\",\"mode\":\"$3\",\"primary\":$4}$p}" > "$T/img/$1"
}
setup(){ rm -rf "$T/img" ; mkdir -p "$T/img" ; : > "$T/calls" ; rm -f "$T/flatten-fails" ; }
run(){ ceph_mirror_image_enable "$@" > "$T/out" 2>&1 ; }
# line number of the first call matching $1 (0 if none)
at(){ grep -n -m1 -- "$1" "$T/calls" | cut -d: -f1 | grep . || echo 0 ; }
count(){ grep -c -- "$1" "$T/calls" ; }

# a clone in snapshot mode: flattened first, then mirrored
setup ; img volume-a disabled none false yes ; img g1 enabled snapshot true no
run snapshot 5m a
f=$(at 'flatten cinder-volumes/volume-a') ; e=$(at 'mirror image enable cinder-volumes/volume-a')
chk "snapshot clone: flattened"                         "$([ "$f" -gt 0 ] && echo yes || echo no)" yes
chk "snapshot clone: flatten before enable"             "$([ "$f" -gt 0 ] && [ "$f" -lt "$e" ] && echo yes || echo no)" yes
chk "snapshot clone: flatten before removing peer copy" "$([ "$f" -gt 0 ] && [ "$f" -lt "$(at 'rbd remove cinder-volumes')" ] && echo yes || echo no)" yes
chk "snapshot clone: reports flattened"                 "$(grep -c 'volume-a flattened' "$T/out")" 1
chk "snapshot clone: enabled"                           "$(grep -c 'volume-a enabled in snapshot mode' "$T/out")" 1

# flatten fails: nothing is enabled on either site
setup ; img volume-a disabled none false yes ; img g1 disabled none false no ; touch "$T/flatten-fails"
run snapshot 5m a
chk "flatten fails: image not enabled"                  "$(count 'mirror image enable cinder-volumes/volume-a')" 0
chk "flatten fails: parent not enabled"                 "$(count 'mirror image enable glance-images/g1')" 0
chk "flatten fails: peer copy not removed"              "$(count 'rbd remove cinder-volumes')" 0
chk "flatten fails: reports the error"                  "$(grep -c 'volume-a failed to flatten, not enabled: rbd: flatten error' "$T/out")" 1

# not a clone: no flatten
setup ; img volume-b disabled none false no
run snapshot 5m b
chk "snapshot non-clone: not flattened"                 "$(count flatten)" 0
chk "snapshot non-clone: enabled"                       "$(grep -c 'volume-b enabled in snapshot mode' "$T/out")" 1

# journal mode clone: unchanged, no flatten
setup ; img volume-a disabled none false yes ; img g1 enabled journal true no
run journal a
chk "journal clone: not flattened"                      "$(count flatten)" 0
chk "journal clone: enabled"                            "$(grep -c 'volume-a enabled in journal mode' "$T/out")" 1

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
