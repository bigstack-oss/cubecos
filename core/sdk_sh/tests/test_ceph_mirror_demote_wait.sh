#!/bin/bash
#
# #2414: wait for SHUTOFF before demote, reset-state retry, stuck VM handling,
# shared attachments, and remote demote failure propagation on promote.
#
#   Run: bash test_ceph_mirror_demote_wait.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=${SRC:-$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh}
for fn in _ceph_mirror_server_wait_shutoff _ceph_mirror_server_stop ceph_mirror_demote_image ceph_mirror_demote_site ceph_mirror_peer_check ceph_mirror_promote_site ceph_mirror_promote_image ceph_mirror_demote_synced_wait ceph_mirror_image_promote_retry ; do
    sed -n "/^$fn()/,/^}/p" "$SRC" >> "$T/fn.sh"
done
source "$T/fn.sh"

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-58s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-58s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

OPENSTACK=fake_openstack
BUILTIN_BACKPOOL=cinder-volumes
HEX_SDK=fake_sdk
CEPH_MIRROR_STOP_WAIT=15
CEPH_MIRROR_STOP_RETRY_WAIT=15
export T
# The develop version, run as a negative control (SRC=...), stops servers
# through xargs, which needs openstack as a command, not a function.
mkdir -p "$T/bin"
printf '#!/bin/bash\nfake_openstack "$@"\n' > "$T/bin/fake_openstack"
chmod +x "$T/bin/fake_openstack"
PATH=$T/bin:$PATH
fake_openstack(){
    local id=$3 dir=$T/vm/$3 remaining stops status
    case "$1 $2" in
        'volume show')
            echo "openstack $*" >> "$T/calls"
            jq -Rn '[inputs | select(length > 0) | {server_id: .}] | {attachments: .}' < "$T/volume/$id"
            ;;
        'server show')
            # a slow API: real time, because this runs in a $(...) subshell
            [ -e "$dir/slow" ] && command sleep "$(cat "$dir/slow")"
            remaining=$(cat "$dir/remaining")
            if [ "$remaining" -gt 0 ] ; then
                remaining=$((remaining-1))
                echo "$remaining" > "$dir/remaining"
                if [ "$remaining" -eq 0 ] ; then
                    echo SHUTOFF > "$dir/status"
                    echo None > "$dir/task_state"
                fi
            fi
            status=$(cat "$dir/status")
            echo "openstack $* => $status" >> "$T/calls"
            echo "$status"
            ;;
        'server stop')
            echo "openstack $*" >> "$T/calls"
            stops=$(cat "$dir/stops")
            echo $((stops+1)) > "$dir/stops"
            # Retry scenarios reject stop while a task is still pending.
            if [ "$(cat "$dir/behavior")" = retry ] && [ "$(cat "$dir/task_state")" = powering-off ] ; then
                echo '409 pending task' >&2
                return 1
            fi
            echo powering-off > "$dir/task_state"
            case "$(cat "$dir/behavior")" in
                delayed|retry) cat "$dir/delay" > "$dir/remaining" ;;
            esac
            ;;
        'server set')
            dir=$T/vm/${*: -1}
            echo "openstack $*" >> "$T/calls"
            echo ACTIVE > "$dir/status"
            echo None > "$dir/task_state"
            ;;
        *) echo "unexpected openstack $*" >&2; return 1 ;;
    esac
}
export -f fake_openstack
rbd(){
    echo "rbd $*" >> "$T/calls"
    case "$1 $2 $3" in
        'mirror pool status') cat "$T/images" ;;
        info*) printf '{"mirroring":{"primary":%s}}\n' "$PRIMARY" ;;
    esac
    return 0
}
# no real sleep: move bash's own clock forward so the wait deadline still applies
sleep(){ echo "sleep $*" >> "$T/sleeps"; SECONDS=$(( SECONDS + $1 )); }
Quiet(){
    local output rc
    if [ "$1" = -n ] ; then
        shift
        eval "$*" >/dev/null 2>&1
        return 0
    fi
    output=$("$@" 2>&1)
    rc=$?
    [ "$rc" -eq 0 ] || printf '%s\n' "$output" >&2
    return "$rc"
}
ceph_mirror_daemon_restart(){ echo restart >> "$T/calls"; }
ceph_mirror_peer_vip(){ echo 192.0.2.2; }
ssh(){
    case "${*: -1}" in
        'exit 0') return 0 ;;
        *) echo 'VM remote-vm did not stop (cinder-volumes/volume-a)'; return "$REMOTE_RC" ;;
    esac
}
# The develop version uses GNU xargs -i; BSD xargs only has -I.
xargs(){
    if [ "$1" = -i ] ; then
        shift
        command xargs -I '{}' "$@"
    else
        command xargs "$@"
    fi
}
timeout(){ shift; "$@"; }
find(){ echo /etc/ceph/local-site.conf; }

setup(){
    rm -rf "$T/vm" "$T/volume"
    mkdir -p "$T/vm" "$T/volume"
    : > "$T/calls"; : > "$T/sleeps"
    echo '{"images":[{"name":"volume-a"}]}' > "$T/images"
    echo vm-a > "$T/volume/a"
    PRIMARY=true REMOTE_RC=0
}
vm(){ # id behavior delay [initial status]
    local dir=$T/vm/$1
    mkdir -p "$dir"
    echo "${4:-ACTIVE}" > "$dir/status"
    echo "$2" > "$dir/behavior"
    echo "$3" > "$dir/delay"
    echo 0 > "$dir/remaining"
    echo 0 > "$dir/stops"
    if [ "$2" = retry ] ; then echo powering-off; else echo None; fi > "$dir/task_state"
}
two_images(){
    echo '{"images":[{"name":"volume-a"},{"name":"volume-b"}]}' > "$T/images"
    echo vm-b > "$T/volume/b"
}
run(){ "$@" > "$T/output" 2>&1; rc=$?; }
count(){ grep -cF "$1" "$T/calls"; }
before(){ # ordered matching call-log entries
    awk -v first="$1" -v second="$2" '
        index($0, first) && !a {a=NR}
        index($0, second) && !b {b=NR}
        END {print (a && b && a < b) ? "yes" : "no"}' "$T/calls"
}
stopped_before_demote(){
    before "openstack server show $1 -f value -c status => SHUTOFF" "rbd mirror image demote cinder-volumes/volume-$2"
}

# a normal asynchronous stop needs three status polls.
setup; vm vm-a delayed 3
run ceph_mirror_demote_site force
chk 'delayed stop: delayed stop returns success' "$rc" 0
chk 'delayed stop: SHUTOFF precedes demote' "$(stopped_before_demote vm-a a)" yes
chk 'delayed stop: no reset-state' "$(count 'server set')" 0
chk 'delayed stop: two sleeps before third poll, no final sleep' "$(wc -l < "$T/sleeps" | tr -d ' ')" 2

# no stop or reset for an already stopped guest.
setup; vm vm-a never 0 SHUTOFF
run ceph_mirror_demote_site force
chk 'already off: already SHUTOFF succeeds' "$rc" 0
chk 'already off: no stop' "$(count 'server stop')" 0
chk 'already off: no reset' "$(count 'server set')" 0
chk 'already off: demote runs' "$(count 'rbd mirror image demote')" 1
chk 'already off: no sleep' "$(wc -l < "$T/sleeps" | tr -d ' ')" 0

# stop is rejected until reset-state clears powering-off.
setup; vm vm-a retry 2
run ceph_mirror_demote_site force
chk 'stuck stop: retry succeeds' "$rc" 0
chk 'stuck stop: stop then reset then stop' "$(awk '/^openstack server (stop|set)/ {print}' "$T/calls" | paste -sd'|' -)" \
    'openstack server stop vm-a|openstack server set --state active vm-a|openstack server stop vm-a'
chk 'stuck stop: SHUTOFF precedes demote' "$(stopped_before_demote vm-a a)" yes

# a stuck guest does not block another image; mode controls its own image.
for mode in force normal ; do
    setup; two_images; vm vm-a never 0; vm vm-b delayed 2
    run ceph_mirror_demote_site "$mode"
    chk "stuck VM, $mode stuck guest fails" "$rc" 1
    chk "stuck VM, $mode diagnostic identifies VM and image" "$(grep -c 'VM vm-a did not stop.*cinder-volumes/volume-a' "$T/output")" 1
    chk "stuck VM, $mode healthy image demoted after SHUTOFF" "$(stopped_before_demote vm-b b)" yes
    chk "stuck VM, $mode restarts daemon before returning" "$(tail -n 1 "$T/calls")" restart
    if [ "$mode" = force ] ; then
        chk 'stuck VM, force force demotes both images' "$(count 'rbd mirror image demote')" 2
        chk 'stuck VM, force force resyncs both images' "$(count 'rbd mirror image resync')" 2
    else
        chk 'stuck VM, normal normal skips stuck image' "$(count 'rbd mirror image demote cinder-volumes/volume-a')" 0
        chk 'stuck VM, normal reports left primary' "$(grep -c 'cinder-volumes/volume-a left primary' "$T/output")" 1
        chk 'stuck VM, normal skipped image has no background config job' "$(count 'rbd config image set cinder-volumes/volume-a')" 0
        chk 'stuck VM, normal healthy image completes background demote' "$(count 'rbd mirror image demote cinder-volumes/volume-b')" 1
    fi
    chk "stuck VM, $mode collects all attachments before stopping" "$(before 'openstack volume show b' 'openstack server stop')" yes
    chk "stuck VM, $mode stops healthy guest before reset retry" "$(before 'openstack server stop vm-b' 'openstack server set')" yes
    # each 15 s wait polls at 0, 5, 10 and 15 s, then gives up
    chk "stuck VM, $mode two bounded waits" "$(wc -l < "$T/sleeps" | tr -d ' ')" 6
done

# a guest attached to two images is stopped only once.
setup; two_images; echo vm-a > "$T/volume/b"; vm vm-a delayed 2
run ceph_mirror_demote_site force
chk 'shared VM: shared guest succeeds' "$rc" 0
chk 'shared VM: shared guest stopped once' "$(count 'server stop vm-a')" 1
chk 'shared VM: both images demoted' "$(count 'rbd mirror image demote')" 2

# the single-image path follows the same force/normal policy.
for mode in force normal ; do
    setup; vm vm-a never 0
    run ceph_mirror_demote_image a "$mode"
    chk "one image, $mode single image fails" "$rc" 1
    chk "one image, $mode reports VM and image" "$(grep -c 'VM vm-a did not stop.*cinder-volumes/volume-a' "$T/output")" 1
    chk "one image, $mode restarts daemon" "$(tail -n 1 "$T/calls")" restart
    if [ "$mode" = force ] ; then
        chk 'one image, force demotes' "$(count 'rbd mirror image demote')" 1
        chk 'one image, force resyncs' "$(count 'rbd mirror image resync')" 1
    else
        chk 'one image, normal skips' "$(count 'rbd mirror image demote')" 0
        chk 'one image, normal reports left primary' "$(grep -c 'left primary' "$T/output")" 1
    fi
done

# remote failure is visible, success is quiet; normal still promotes.
for mode in force normal ; do
    for remote_rc in 1 0 ; do
        setup; PRIMARY=false; REMOTE_RC=$remote_rc
        run ceph_mirror_promote_site "$mode"
        chk "promote_site $mode remote rc=$remote_rc propagated" "$rc" "$remote_rc"
        chk "promote_site $mode remote rc=$remote_rc diagnostic" "$(grep -c 'VM remote-vm did not stop' "$T/output")" "$remote_rc"
        chk "promote_site $mode continues local promote" "$(count 'rbd mirror image promote')" 1
    done
done

# The same propagation applies to both promote_image branches.
for mode in force normal ; do
    setup; PRIMARY=false; REMOTE_RC=1
    run ceph_mirror_promote_image a "$mode"
    chk "promote_image $mode propagates failure" "$rc" 1
    chk "promote_image $mode prints remote diagnostic" "$(grep -c 'VM remote-vm did not stop' "$T/output")" 1
done

# Only an ACTIVE or ERROR server is reset; one in another task (here MIGRATING)
# is stopped again but left alone, and reported.
setup; vm vm-a never 0 MIGRATING
run ceph_mirror_demote_site force
chk 'MIGRATING server fails' "$rc" 1
chk 'MIGRATING server is not reset' "$(count 'server set')" 0
chk 'MIGRATING server is stopped twice' "$(count 'server stop vm-a')" 2
chk 'MIGRATING server reported' "$(grep -c 'VM vm-a did not stop' "$T/output")" 1

# An ERROR server is reset like a stuck ACTIVE one.
setup; vm vm-a retry 2 ERROR
run ceph_mirror_demote_site force
chk 'ERROR server succeeds after reset' "$rc" 0
chk 'ERROR server is reset' "$(count 'server set --state active vm-a')" 1

# Empty sites must not sleep; a short wait still polls once.
setup; echo '{"images":[]}' > "$T/images"
run ceph_mirror_demote_site normal
chk 'empty site succeeds' "$rc" 0
chk 'empty site does not sleep' "$(wc -l < "$T/sleeps" | tr -d ' ')" 0
if declare -F _ceph_mirror_server_wait_shutoff >/dev/null ; then
    setup; vm vm-a never 0
    run _ceph_mirror_server_wait_shutoff 0 vm-a
    chk 'zero wait polls once' "$(count 'server show vm-a')" 1
    chk 'wait prints remaining id' "$(cat "$T/output")" vm-a
    chk 'zero wait does not sleep' "$(wc -l < "$T/sleeps" | tr -d ' ')" 0
    # the time spent querying counts toward the wait
    setup; vm vm-a never 0; echo 11 > "$T/vm/vm-a/slow"
    run _ceph_mirror_server_wait_shutoff 10 vm-a
    chk 'slow query past the wait polls once' "$(count 'server show vm-a')" 1
    chk 'slow query past the wait does not sleep' "$(wc -l < "$T/sleeps" | tr -d ' ')" 0
else
    chk 'wait helper exists' missing present
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
