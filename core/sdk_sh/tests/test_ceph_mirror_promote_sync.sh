#!/bin/bash
#
# ceph_mirror_promote_site / ceph_mirror_promote_image, normal mode: a
# snapshot-mode image is promoted only once its local copy holds, complete, the
# demotion snapshot the peer just took; a journal-mode image keeps retrying the
# promote, which Ceph refuses until the demotion is replayed, up to the same
# deadline. A timeout or a failed promote is reported, the image is promoted
# back on the peer, and the call returns non-zero. Force mode does not wait.
#
#   Run: bash test_ceph_mirror_promote_sync.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh
for fn in ceph_mirror_peer_check ceph_mirror_demote_synced_wait ceph_mirror_image_promote_retry ceph_mirror_peer_demoted_check ceph_mirror_peer_repromote ceph_mirror_promote_image ceph_mirror_promote_site ; do
    sed -n "/^$fn()/,/^}/p" $SRC >> $T/fn.sh
done
source $T/fn.sh
eval "$(declare -f ceph_mirror_peer_repromote | sed "s|/var/lib/ceph/rbd-mirror|$T/srv|")"

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-58s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-58s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# --- cluster model, one directory per image under $T/img/<name> ---
# mode     : snapshot | journal
# primary  : true | false (local)
# peer     : peer's `rbd snap ls --all --format json`
# local.N  : local `rbd snap ls --all --format json` from the N-th poll on
#            (the highest N not above the poll count wins)
# promote_fail : promote always fails
# promote_ok_after : promote fails until this many tries were made
# peer_primary : the peer's image is still primary (it did not demote)
# back_fail    : promoting it back on the peer fails
# shellcheck disable=SC2034  # read by the sourced functions
BUILTIN_BACKPOOL=cinder-volumes
HEX_SDK=hex_sdk
# like hex's Quiet: eval re-parses the words, so a remote command passed
# through it loses its quoting
# shellcheck disable=SC2048  # the unquoted $* is what is being modelled
Quiet(){ [ "$1" = -n ] && shift ; eval $* >/dev/null 2>&1 ; }
timeout(){ echo "timeout $1 ${*: -1}" >> $T/calls ; shift ; "$@" ; }
sleep(){ SECONDS=$(( SECONDS + $1 )) ; }
ceph_mirror_peer_vip(){ echo 10.0.0.2 ; }

mirror_snap(){ # id state complete [primary_snap_id]
    if [ -n "$4" ] ; then
        echo "{\"id\":$1,\"name\":\".mirror.non_primary.x.$1\",\"size\":21474836480,\"protected\":\"false\",\"timestamp\":\"Wed Nov 18 10:00:00 2026\",\"namespace\":{\"type\":\"mirror\",\"state\":\"$2\",\"mirror_peer_uuids\":[],\"complete\":$3,\"primary_mirror_uuid\":\"peer-uuid\",\"primary_snap_id\":$4,\"last_copied_object_number\":5120}}"
    else
        echo "{\"id\":$1,\"name\":\".mirror.primary.x.$1\",\"size\":21474836480,\"protected\":\"false\",\"timestamp\":\"Wed Nov 18 10:00:00 2026\",\"namespace\":{\"type\":\"mirror\",\"state\":\"$2\",\"mirror_peer_uuids\":[\"local-peer\"],\"complete\":$3}}"
    fi
}
user_snap(){ echo "{\"id\":$1,\"name\":\"snap\",\"size\":1,\"protected\":\"true\",\"timestamp\":\"Wed Nov 18 10:00:00 2026\",\"namespace\":{\"type\":\"user\"}}" ; }

img(){ # name mode
    mkdir -p $T/img/$1 ; echo $2 > $T/img/$1/mode ; echo false > $T/img/$1/primary ; echo 0 > $T/img/$1/polls
    # the peer just demoted: newest mirror snapshot is its primary-demoted one, id 57
    echo "[$(user_snap 3),$(mirror_snap 40 primary true),$(mirror_snap 57 demoted true)]" > $T/img/$1/peer
}
local_at(){ echo "[$3]" > $T/img/$1/local.$2 ; } # name poll json

rbd(){
    case "$1 $2" in
        "mirror pool")
            echo "{\"images\":[$(ls $T/img | sed 's/.*/{"name":"&"}/' | paste -sd, -)]}" ;;
        "info "*)
            local i=$T/img/${2#*/}
            echo "{\"mirroring\":{\"mode\":\"$(cat $i/mode)\",\"state\":\"enabled\",\"primary\":$(cat $i/primary)}}" ;;
        "snap ls")
            local i=$T/img/${6#*/} n
            echo snapls ${6#*/} >> $T/calls
            n=$(( $(cat $i/polls) + 1 )) ; echo $n > $i/polls
            local f
            f=$(for l in $i/local.* ; do [ -e "$l" ] && echo ${l##*.} ; done | sort -n | awk -v n=$n '$1 <= n' | tail -1)
            [ -n "$f" ] && cat $i/local.$f || echo "[]" ;;
        "mirror image")
            # mirror image promote [--force] <pool>/<img>
            local spec=${*: -1} flag=
            [ "$4" = "--force" ] && flag=--force
            local i=$T/img/${spec#*/}
            echo "promote ${spec#*/} $flag" >> $T/calls
            echo $(( $(cat $i/tries 2>/dev/null || echo 0) + 1 )) > $i/tries
            if [ -e $i/promote_fail ] || { [ -e $i/promote_ok_after ] && [ "$(cat $i/tries)" -le "$(cat $i/promote_ok_after)" ] ; } ; then
                echo "rbd: error promoting image to primary" >&2
                echo "2026-11-18T10:00:00.000+0000 7f librbd::mirror::PromoteRequest: 0x5 handle_get_info: image is primary within a remote cluster or demotion is not propagated yet" >&2
                return 16
            fi
            echo true > $i/primary
            echo "Image promoted to primary" ;;
    esac
}
ssh(){ # ssh -o .. -o .. root@<vip> <remote command words>: joined, as ssh does
    while [ $# -gt 0 ] && [ "${1#root@}" = "$1" ] ; do shift ; done
    shift
    local c="$*"
    case "$c" in
        "exit 0") [ ! -e $T/peer_down ] ;;
        "rbd snap ls --all --format json "*) echo peer-snapls >> $T/calls ; cat $T/img/${c##*/}/peer ;;
        "rbd info "*) # rbd info <pool>/<img> --format json
            local i ; i=$T/img/$(echo "$c" | awk '{print $3}' | cut -d/ -f2)
            echo peer-info >> $T/calls
            if [ -e $i/peer_primary ] ; then echo '{"mirroring":{"primary":true}}' ; else echo '{"mirroring":{"primary":false}}' ; fi ;;
        "if [ "*) # promote back on the peer: prints kept / promoted / nothing
            local b
            b=$(echo "$c" | grep -o 'cinder-volumes/volume-[a-z0-9]*' | head -1 | cut -d/ -f2)
            echo "back $b" >> $T/calls
            if [ -e $T/img/$b/peer_primary ] ; then echo kept
            elif [ ! -e $T/img/$b/back_fail ] ; then echo promoted
            fi ;;
        "$HEX_SDK ceph_mirror_demote_"*) echo "peer: $c" >> $T/calls ;;
    esac
}

reset(){ rm -rf $T/img $T/calls $T/peer_down $T/srv ; mkdir -p $T/img $T/srv ; : > $T/calls ; SECONDS=0 ; }
vm(){ # name volume-id..: a server record as the peer synced it
    local n=$1 ids
    shift
    ids=$(printf '{"id":"%s"},' "$@")
    echo "{\"name\":\"$n\",\"volumes_attached\":[${ids%,}]}" > $T/srv/$n
}
site(){ # run promote_site; prints "rc|promoted images|stderr"
    ceph_mirror_promote_site "$@" > $T/out 2> $T/err ; local rc=$?
    echo "$rc|$(grep '^promote' $T/calls | awk '{print $2 $3}' | sort | paste -sd, -)|$(tr '\n' ' ' < $T/err)"
}
calls(){ grep -c "$1" $T/calls ; }
# shellcheck disable=SC2034  # read by the sourced functions
CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=60

# 1. already synced: newest local mirror snapshot is the complete copy of peer snapshot 57
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 20 non-primary true 40),$(mirror_snap 21 demoted true 57)"
r=$(site normal)
chk "synced: promoted, rc 0"                                   "${r%|*}" "0|volume-a"

# 2. syncs after two polls: promoted only once complete
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 20 non-primary true 40),$(mirror_snap 21 demoted false 57)"
local_at volume-a 3 "$(mirror_snap 20 non-primary true 40),$(mirror_snap 21 demoted true 57)"
r=$(site normal)
chk "syncs later: promoted, rc 0"                              "${r%|*}" "0|volume-a"
chk "syncs later: polled until complete"                       "$(calls 'snapls volume-a')" "3"
chk "syncs later: promote after the last poll"                 "$(grep -n . $T/calls | grep -E 'snapls|promote' | tail -1 | cut -d: -f2)" "promote volume-a "
chk "syncs later: peer read has a time limit"                  "$(grep -c '^timeout 60 rbd snap ls --all --format json cinder-volumes/volume-a$' $T/calls)" "1"
chk "syncs later: each local read has a time limit"            "$(grep -c '^timeout 30 cinder-volumes/volume-a$' $T/calls)" "3"

# 3. never syncs: not promoted, error, stops at the deadline
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 20 non-primary true 40),$(mirror_snap 21 demoted false 57)"
r=$(site normal)
chk "never synced: not promoted, rc 1"                         "${r%%|*}|$(calls '^promote')" "1|0"
chk "never synced: error names the demotion snapshot"          "$(grep -c "volume-a has not copied the peer's demotion snapshot 57 (local: demoted complete=false primary_snap_id=57)" $T/err)" "1"
chk "never synced: waited about the timeout"                   "$(calls 'snapls volume-a')" "13"

# 4. newest local is a complete demoted copy of an OLDER peer demotion
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 20 demoted true 33)"
r=$(site normal)
chk "stale demoted copy: not promoted, rc 1"                   "${r%%|*}|$(calls '^promote')" "1|0"

# 5. newest local is its own primary-demoted snapshot from the last switchover
#    (Ceph allows a non-forced promote here)
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 20 primary true),$(mirror_snap 21 demoted true)"
r=$(site normal)
chk "own old demotion: not promoted, rc 1"                     "${r%%|*}|$(calls '^promote')" "1|0"

# 6. peer did not demote: fail at once, no waiting
reset ; img volume-a snapshot
echo "[$(mirror_snap 40 primary true),$(mirror_snap 58 primary true)]" > $T/img/volume-a/peer
local_at volume-a 1 "$(mirror_snap 20 non-primary true 40)"
r=$(site normal)
chk "peer not demoted: not promoted, rc 1"                     "${r%%|*}|$(calls '^promote')" "1|0"
chk "peer not demoted: error says so"                          "$(grep -c 'cannot confirm cinder-volumes/volume-a is demoted on the peer site' $T/err)" "1"
chk "peer not demoted: no local polling"                       "$(calls 'snapls volume-a')" "0"

# 7. promote keeps failing: rbd's own error is shown, rc 1
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 21 demoted true 57)"
touch $T/img/volume-a/promote_fail
r=$(site normal)
chk "promote fails: rc 1, tried 10 times"                      "${r%%|*}|$(calls '^promote')" "1|10"
chk "promote fails: rbd error reported"                        "$(grep -c 'failed to promote cinder-volumes/volume-a: rbd: error promoting image to primary' $T/err)" "1"

# 8. journal image: no snapshot polling, promoted
reset ; img volume-j journal
r=$(site normal)
chk "journal: promoted without polling, rc 0"                  "${r%|*}|$(calls snapls)" "0|volume-j|0"

# 9. mixed site: the journal image still goes, the unsynced snapshot image does not
reset ; img volume-a snapshot ; img volume-j journal
local_at volume-a 1 "$(mirror_snap 21 demoted false 57)"
r=$(site normal)
chk "mixed: journal promoted, snapshot held, rc 1"             "${r%|*}" "1|volume-j"

# 10. promote volume, normal
reset ; img volume-a snapshot ; img volume-b snapshot
local_at volume-a 1 "$(mirror_snap 21 demoted true 57)"
ceph_mirror_promote_image a normal > $T/out 2> $T/err ; rc=$?
chk "volume synced: only it promoted, rc 0"                    "$rc|$(grep '^promote' $T/calls | awk '{print $2}' | paste -sd, -)" "0|volume-a"
chk "volume synced: only its peer image demoted"               "$(grep -c 'peer: hex_sdk ceph_mirror_demote_image a normal' $T/calls)" "1"
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 21 demoted false 57)"
ceph_mirror_promote_image a normal > $T/out 2> $T/err ; rc=$?
chk "volume never synced: not promoted, rc 1"                  "$rc|$(calls '^promote')" "1|0"

# 11. peer unreachable in normal mode: refused before anything is promoted or polled
reset ; img volume-a snapshot ; touch $T/peer_down
r=$(site normal)
chk "normal, peer down: refused, nothing promoted or polled"   "${r%|*}|$(calls snapls)" "1||0"

# 12. force mode is unchanged: --force, no polling
reset ; img volume-a snapshot
local_at volume-a 1 "$(mirror_snap 21 demoted false 57)"
r=$(site force)
chk "force: --force without polling"                           "$(echo "$r" | cut -d'|' -f2)|$(calls snapls)" "volume-a--force|0"

# 13. site wait budget: time spent promoting earlier images does not count
#     (each image completes on its 2nd poll; promotes sleep 10 s each)
reset ; img volume-a snapshot ; img volume-b snapshot ; img volume-c snapshot
for v in a b c ; do
    local_at volume-$v 1 "$(mirror_snap 21 demoted false 57)"
    local_at volume-$v 2 "$(mirror_snap 21 demoted true 57)"
done
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=20 site normal)
chk "budget: promote time not counted, all promoted, rc 0"     "${r%|*}" "0|volume-a,volume-b,volume-c"

# 14. site wait budget is shared: once one image has used it up, the next
#     stuck image gets a single poll
reset ; img volume-a snapshot ; img volume-b snapshot
local_at volume-a 1 "$(mirror_snap 21 demoted false 57)"
local_at volume-b 1 "$(mirror_snap 21 demoted false 57)"
r=$(site normal)
chk "budget shared: neither promoted, rc 1"                    "${r%%|*}|$(calls '^promote')" "1|0"
chk "budget shared: second image polled once"                  "$(calls 'snapls volume-b')" "1"

# 15. promote volume: peer unreachable is refused, nothing promoted or polled
reset ; img volume-a snapshot ; touch $T/peer_down
ceph_mirror_promote_image a normal > $T/out 2> $T/err ; rc=$?
chk "volume, peer down: refused, nothing promoted or polled"   "$rc|$(grep '^promote' $T/calls | awk '{print $2 $3}')|$(calls snapls)" "1||0"

# 16. promote volume, journal image: no polling, promoted
reset ; img volume-j journal
ceph_mirror_promote_image j normal > $T/out 2> $T/err ; rc=$?
chk "volume journal: promoted without polling, rc 0"           "$rc|$(grep '^promote' $T/calls | awk '{print $2}')|$(calls snapls)" "0|volume-j|0"

# 17. journal image replays slowly: promote is refused 15 times, then succeeds
#     within the deadline (the fixed 10 tries gave up here, #2443)
reset ; img volume-j journal ; echo 15 > $T/img/volume-j/promote_ok_after
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=600 site normal)
chk "journal slow: promoted, rc 0"                             "${r%%|*}|$(cat $T/img/volume-j/primary)" "0|true"
chk "journal slow: tried until accepted"                       "$(calls '^promote volume-j')" "16"
chk "journal slow: nothing promoted back"                      "$(calls '^back')" "0"
chk "journal slow: peer demotion checked once"                 "$(calls peer-info)" "1"
chk "journal slow: checked before the first promote"           "$(grep -E '^(peer-info|promote)' $T/calls | head -1)" "peer-info"

# 18. journal image never replays: retried until the deadline, then promoted
#     back on the peer and reported
reset ; img volume-j journal ; touch $T/img/volume-j/promote_fail
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=200 site normal)
chk "journal stuck: not promoted, rc 1"                        "${r%%|*}" "1"
chk "journal stuck: retried until the deadline"                "$(calls '^promote volume-j')" "20"
chk "journal stuck: promoted back on the peer"                 "$(grep -c '^back volume-j$' $T/calls)" "1"
chk "journal stuck: says it was promoted back"                 "$(grep -c 'volume-j was not promoted on local site, promoted it back on peer site 10.0.0.2' $T/err)" "1"

# 19. journal image the peer did not demote (its VM did not stop): no promote,
#     no waiting; promoting back finds it primary already
reset ; img volume-j journal ; touch $T/img/volume-j/peer_primary
r=$(site normal)
chk "journal peer primary: not promoted, rc 1"                 "${r%%|*}|$(calls '^promote')" "1|0"
chk "journal peer primary: error says so"                      "$(grep -c 'cannot confirm cinder-volumes/volume-j is demoted on the peer site' $T/err)" "1"
chk "journal peer primary: promote back still asked"           "$(calls '^back')" "1"
chk "journal peer primary: says the peer kept it"              "$(grep -c 'volume-j was not promoted on local site, peer site 10.0.0.2 did not demote it' $T/err)" "1"

# 20. promoting back fails too: says the image is primary on neither site
reset ; img volume-j journal ; touch $T/img/volume-j/promote_fail $T/img/volume-j/back_fail
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=100 site normal)
chk "back fails: rc 1"                                         "${r%%|*}" "1"
chk "back fails: primary on neither site, how to recover"      "$(grep -c "volume-j is primary on neither site, run 'rbd mirror image promote cinder-volumes/volume-j' on peer site 10.0.0.2" $T/err)" "1"

# 21. mixed site, the snapshot image never syncs: only it is promoted back,
#     the journal image stays promoted here
reset ; img volume-a snapshot ; img volume-j journal
local_at volume-a 1 "$(mirror_snap 21 demoted false 57)"
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=60 site normal)
chk "mixed: only the unsynced image promoted back"             "$(grep '^back' $T/calls | paste -sd, -)" "back volume-a"

# 22. promote volume, journal image replays slowly / never
reset ; img volume-j journal ; echo 15 > $T/img/volume-j/promote_ok_after
CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=600 ceph_mirror_promote_image j normal > $T/out 2> $T/err ; rc=$?
chk "volume journal slow: promoted, rc 0"                      "$rc|$(calls '^promote volume-j')|$(calls '^back')" "0|16|0"
reset ; img volume-j journal ; touch $T/img/volume-j/promote_fail
CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=200 ceph_mirror_promote_image j normal > $T/out 2> $T/err ; rc=$?
chk "volume journal stuck: rc 1, promoted back"                "$rc|$(calls '^promote volume-j')|$(calls '^back volume-j')" "1|20|1"

# 23. VMs of the failed image: one with only that volume stays on the peer;
#     one whose other volume was promoted here can start on neither site
reset ; img volume-a snapshot ; img volume-j journal ; img volume-k journal
local_at volume-a 1 "$(mirror_snap 21 demoted true 57)"
touch $T/img/volume-j/promote_fail
vm vm-split a j ; vm vm-one j ; vm vm-other k
r=$(CEPH_MIRROR_PROMOTE_SYNC_TIMEOUT=100 site normal)
chk "vms: split VM named once, with the volume to move back"   "$(grep -c "VM vm-split can start on neither site: run 'hex_cli -c storage -c mirror -c promote -c normal -c volume' on peer site 10.0.0.2 for volume-a, then start it there" $T/err)" "1"
chk "vms: single-volume VM stays on the peer"                  "$(grep -c 'VM vm-one stays on peer site 10.0.0.2, start it there if it is stopped' $T/err)" "1"
chk "vms: unaffected VM not named"                             "$(grep -c 'vm-other' $T/err)" "0"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
