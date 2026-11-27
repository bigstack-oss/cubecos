#!/bin/bash
#
# Volume type races: Cinder can accept simultaneous creates of the same name.
# Run: bash test_os_volume_type_race.sh (or SRC=/path/to/sdk_os.sh bash ...).
# Fake API calls are atomic; create's check/insert gap deliberately is not.
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC=${SRC:-$D/../modules/sdk_os.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for f in _os_volume_type_rows _os_volume_type_gone os_volume_type_create os_volume_type_clear ; do
    sed -n "/^$f()/,/^}/p" "$SRC"
done > "$T/fn.sh"
source "$T/fn.sh"
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
OPENSTACK=fake_os
STATE=$T/state
lock(){ until mkdir "$STATE/lock" 2>/dev/null; do sleep 0.005; done; }
unlock(){ rmdir "$STATE/lock"; }
reset(){ rm -rf "$STATE"; mkdir "$STATE"; }
inject(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$STATE/$1.type"; }
# Resolve an ID first, otherwise an exact name; called under the API lock.
resolve(){
    local file id name backend found=
    if [ -f "$STATE/$1.type" ]; then echo "$1"; return 0; fi
    for file in "$STATE"/*.type; do
        [ -f "$file" ] || continue
        IFS=$'\t' read -r id name backend < "$file"
        if [ "$name" = "$1" ]; then
            if [ -n "$found" ]; then
                echo "More than one volumetype exists with the name '$1'." >&2
                return 1
            fi
            found=$id
        fi
    done
    if [ -z "$found" ]; then
        echo "No volumetype with a name or ID of '$1' exists." >&2
        return 1
    fi
    echo "$found"
}
fake_os(){
    local action=$3 name= backend= target= format= prop= arg id file n rc=0
    shift 3
    while [ "$#" -gt 0 ]; do
        arg=$1; shift
        case "$arg" in
            --property) prop=$1; backend=${prop#volume_backend_name=}; shift ;;
            -f|--format) format=$1; shift ;;
            -c) shift ;;
            --long) : ;;
            *) target=$arg ;;
        esac
    done
    lock
    case "$action" in
        list)
            if [ -f "$STATE/list-fails" ]; then
                echo 'list failed' >&2; unlock; return 1
            fi
            if [ "$format" = json ]; then
                for file in "$STATE"/*.type; do
                    [ -f "$file" ] && cat "$file"
                done | jq -Rn '[inputs | split("\t") | {ID: .[0], Name: .[1], Properties: (if .[2] == "" then {} else {volume_backend_name: .[2]} end)}]'
            else
                for file in "$STATE"/*.type; do
                    [ -f "$file" ] || continue
                    IFS=$'\t' read -r id name backend < "$file"
                    echo "$name"
                done
            fi ;;
        create)
            for file in "$STATE"/*.type; do
                [ -f "$file" ] || continue
                IFS=$'\t' read -r id name prop < "$file"
                if [ "$name" = "$target" ]; then
                    echo "Volume Type $target already exists. (HTTP 409)" >&2
                    unlock; return 1
                fi
            done
            unlock
            sleep 0.2
            lock
            # random, like Cinder's UUIDs: a later create may get the lower ID
            printf -v id 'id-%04x%04x' "$RANDOM" "$RANDOM"
            inject "$id" "$target" "$backend"
            ;;
        set|delete|show)
            if [ -f "$STATE/$target.flaky" ] && [ "$action" != set ]; then
                echo 'Service Unavailable (HTTP 503)' >&2; rc=1
            elif id=$(resolve "$target"); then
                case "$action" in
                    set)
                        IFS=$'\t' read -r id name prop < "$STATE/$id.type"
                        inject "$id" "$name" "$backend" ;;
                    delete)
                        if [ -f "$STATE/$id.inuse" ]; then
                            echo 'Target volume type is still in use. (HTTP 400)' >&2; rc=1
                        else
                            rm "$STATE/$id.type"
                        fi ;;
                    show) cat "$STATE/$id.type" ;;
                esac
            else rc=1; fi ;;
        *) echo "unknown fake action: $action" >&2; rc=1 ;;
    esac
    unlock
    return "$rc"
}
rows(){
    local file
    for file in "$STATE"/*.type; do [ ! -f "$file" ] || cat "$file"; done
}
count(){ rows | awk -F '\t' -v n="$1" '$2 == n {c++} END {print c+0}'; }
backend(){ rows | awk -F '\t' -v n="$1" '$2 == n {print $3}'; }
names(){ rows | cut -f2 | LC_ALL=C sort | paste -sd, -; }
run_create(){ os_volume_type_create "$@" > "$T/out" 2> "$T/err"; }
run_clear(){ os_volume_type_clear "$@" > "$T/out" 2> "$T/err"; }

reset
run_create X ceph; chk '1 rc' "$?" 0
chk '1 count' "$(count X)" 1
chk '1 tagged' "$(backend X)" ceph

reset; inject id-001 X ceph
run_create X other; chk '2 rc' "$?" 0
chk '2 count' "$(count X)" 1
chk '2 property unchanged' "$(backend X)" ceph

parallel_create(){
    local case_no=$1 callers=$2 rounds=$3 round i pid pids
    for ((round=1; round<=rounds; round++)); do
        reset; pids=
        for ((i=1; i<=callers; i++)); do
            os_volume_type_create X ceph > "$T/out.$i" 2> "$T/err.$i" &
            pids="$pids $!"
        done
        i=0
        for pid in $pids; do
            wait "$pid"; chk "$case_no round $round caller $((i+=1)) rc" "$?" 0
        done
        chk "$case_no round $round count" "$(count X)" 1
        chk "$case_no round $round tagged" "$(backend X)" ceph
    done
}
parallel_create 3 2 10
parallel_create 4 4 5

reset; inject id-002 X ''; inject id-001 X ''
run_create X ceph; chk '5 rc' "$?" 0
chk '5 count' "$(count X)" 1
chk '5 lowest ID and tagged' "$(rows)" $'id-001\tX\tceph'

reset; inject id-001 X ''; inject id-002 X ''; touch "$STATE/id-002.inuse"
run_create X ceph; rc=$?
chk '6 nonzero rc' "$((rc != 0))" 1
chk '6 loud' "$(grep -c 'Error:' "$T/err")" 1
chk '6 in-use survives' "$(test -f "$STATE/id-002.type" && echo yes)" yes

reset; inject id-001 foo-ssd ceph
run_create foo ceph; chk '7 rc' "$?" 0
chk '7 exact name created' "$(count foo)" 1
chk '7 tagged' "$(backend foo)" ceph

clear_state(){
    reset
    inject id-001 CubeStorage ceph; inject id-002 __DEFAULT__ ''
    inject id-003 a ceph; inject id-004 b ceph
    inject id-005 c ceph; inject id-006 c ceph
}
clear_state
run_clear CubeStorage,a; chk '8 rc' "$?" 0
chk '8 kept names' "$(names)" CubeStorage,__DEFAULT__,a

reset; inject id-001 CubeStorage ceph; inject id-002 Cube ceph
run_clear CubeStorage; chk '9 rc' "$?" 0
chk '9 exact keep' "$(names)" CubeStorage

clear_state; touch "$STATE/id-004.inuse"
run_clear CubeStorage,a; rc=$?
chk '10 nonzero rc' "$((rc != 0))" 1
chk '10 loud' "$(grep -c 'Error:' "$T/err")" 1
chk '10 continues deleting' "$(names)" CubeStorage,__DEFAULT__,a,b

clear_state
os_volume_type_clear CubeStorage,a > "$T/clear1.out" 2> "$T/clear1.err" & p1=$!
os_volume_type_clear CubeStorage,a > "$T/clear2.out" 2> "$T/clear2.err" & p2=$!
wait "$p1"; chk '11 first rc' "$?" 0
wait "$p2"; chk '11 second rc' "$?" 0
chk '11 kept names' "$(names)" CubeStorage,__DEFAULT__,a
chk '11 no errors' "$(cat "$T/clear1.err" "$T/clear2.err" | grep -c 'Error:')" 0

# Also cover the default keep list and failures before mutations.
clear_state
run_clear; chk '12 default rc' "$?" 0
chk '12 default keep' "$(names)" CubeStorage,__DEFAULT__
reset; touch "$STATE/list-fails"
run_create X ceph; rc=$?
chk '13 create list failure rc' "$((rc != 0))" 1
chk '13 create list failure loud' "$(grep -c 'Error:' "$T/err")" 1
run_clear; rc=$?
chk '13 clear list failure rc' "$((rc != 0))" 1
chk '13 clear list failure loud' "$(grep -c 'Error:' "$T/err")" 1

# a delete that fails while the API is down is not taken for "already gone"
clear_state; touch "$STATE/id-004.flaky"
run_clear CubeStorage,a; rc=$?
chk '14 clear api error rc' "$((rc != 0))" 1
chk '14 clear api error loud' "$(grep -c 'Error:' "$T/err")" 1
chk '14 clear api error others deleted' "$(names)" CubeStorage,__DEFAULT__,a,b
reset; inject id-001 X ''; inject id-002 X ''; touch "$STATE/id-002.flaky"
run_create X ceph; rc=$?
chk '14 create api error rc' "$((rc != 0))" 1
chk '14 create api error loud' "$(grep -c 'Error: cannot delete duplicate volume type X (id-002)' "$T/err")" 1

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
