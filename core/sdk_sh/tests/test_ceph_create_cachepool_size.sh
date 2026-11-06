#!/bin/bash
#
# Offline regression test for cache pool replica sizes (#883).
# Extracts the real creation and size adjustment functions; no cluster needed.
#   Run: bash test_ceph_create_cachepool_size.sh
#   SRC=<other sdk_ceph.sh> runs the same cases against another revision.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_ceph.sh}"
for f in ceph_create_cachepool ceph_create_pool ceph_adjust_pool_size ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

BUILTIN_BACKPOOL=cinder-volumes
BUILTIN_CACHEPOOL=cachepool
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TRACE="$TMP/trace"

# Quiet -n suppresses failures and output, as it does in the SDK.
Quiet() {
    local ign=0 st=0 out="$TMP/quiet.$RANDOM"
    [ "$1" = -n ] && { ign=1; shift; }
    "$@" > "$out" 2>&1 || st=$?
    [ "$ign" -eq 0 ] || st=0
    [ "$st" -eq 0 ] || cat "$out" >&2
    rm -f "$out"
    return "$st"
}
sleep() { :; }
log_error() { echo "$*" >&2; }

# Trace even calls whose output the real functions redirect. State is kept in
# files so changes made in command substitutions remain visible to later reads.
fake_ceph() {
    echo "$*" >> "$TRACE"
    case "$*" in
        'osd pool get ephemeral-vms size -f json')
            [ "$SIZE_FAIL" = no ] || return 1
            printf '{"size":%s}\n' "$BACK_SIZE" ;;
        'osd df ephemeral-vms')
            local n
            for ((n=0; n<OSDS; n++)) ; do echo "$n up"; done ;;
        'osd pool ls detail') printf '%s\n' "$DETAIL" ;;
        'osd pool create ephemeral-vms-cache 1') touch "$TMP/created" ;;
        'osd pool ls')
            echo ephemeral-vms
            [ ! -f "$TMP/created" ] || echo ephemeral-vms-cache ;;
        '-s') echo 'health: HEALTH_OK' ;;
        'osd crush ls ephemeral-vms') printf '%s\n' host1 host2 host3 ;;
        'config set global mon_allow_pool_size_one true') touch "$TMP/allow-one" ;;
        'config set global mon_allow_pool_size_one false'|'config rm global mon_allow_pool_size_one')
            rm -f "$TMP/allow-one" ;;
        'osd pool set ephemeral-vms-cache size '*)
            if [ "$6" = 1 ] && [ ! -f "$TMP/allow-one" ] ; then return 1; fi
            echo "$6" > "$TMP/size" ;;
        'osd pool set ephemeral-vms-cache min_size '*) echo "$6" > "$TMP/min-size" ;;
        'osd pool get ephemeral-vms-cache min_size -f json')
            printf '{"min_size":%s}\n' "$(cat "$TMP/min-size")" ;;
        'osd pool get ephemeral-vms pg_num -f json') echo '{"pg_num":32}' ;;
        'osd pool application enable '*|'osd pool set ephemeral-vms-cache pg_num '*|'osd pool set ephemeral-vms-cache pgp_num '*) : ;;
        *) echo "Unexpected ceph call: $*" >&2; return 1 ;;
    esac
    return 0
}
CEPH=fake_ceph

run() {
    : > "$TRACE"
    rm -f "$TMP/created" "$TMP/allow-one" "$TMP/size" "$TMP/min-size"
    MSG=$(ceph_create_cachepool ephemeral-vms 2>&1)
    RC=$?
    OUT=$(cat "$TRACE")
    LAST_SIZE=$(awk '$1=="osd" && $2=="pool" && $3=="set" && $4=="ephemeral-vms-cache" && $5=="size" {n=$6} END {print n}' "$TRACE")
    APPS=$(awk '$1=="osd" && $2=="pool" && $3=="application" && $4=="enable" {print $5, $6, $7}' "$TRACE")
}

pass=0 fail=0
ck() {
    if [ "$1" = yes ] ; then
        pass=$((pass+1)); echo "PASS: $2"
    else
        fail=$((fail+1)); echo "FAIL: $2 (rc=$RC, last size=$LAST_SIZE)"
        printf '%s\n' "$MSG" "$OUT"
    fi
}
final_size_is() {
    [ "$RC" -eq 0 ] && [ "$LAST_SIZE" = "$1" ] &&
        [ "$(cat "$TMP/size" 2>/dev/null)" = "$1" ]
}

SIZE_FAIL=no BACK_SIZE=1 OSDS=1
DETAIL="pool 1 'ephemeral-vms' replicated size 1 application rbd"
run
ok=no
if final_size_is 1 && [ "$APPS" = 'ephemeral-vms-cache rbd ' ] &&
    [ "$(cat "$TMP/min-size" 2>/dev/null)" = 1 ] ; then ok=yes; fi
ck "$ok" 'a. one-host pool keeps size 1 and min_size 1'

SIZE_FAIL=yes
run
ok=no
if [ "$RC" -ne 0 ] && ! grep -q '^osd pool create ' "$TRACE" &&
    ! grep -q '^osd pool set .* size 3' "$TRACE" &&
    grep -qF 'Error: cannot read the replica size of ephemeral-vms, not creating ephemeral-vms-cache' <<< "$MSG" ; then ok=yes; fi
ck "$ok" 'b. unreadable size refuses creation'
# cli_ceph.cpp reads this function's stdout as the cache pool name
ok=no
[ -z "$(ceph_create_cachepool ephemeral-vms 2>/dev/null)" ] && ok=yes
ck "$ok" 'b. the error stays off stdout'

SIZE_FAIL=no
DETAIL="$DETAIL
pool 2 'ephemeral-vms-ssd' replicated size 3 application cephfs"
run
ok=no
if final_size_is 1 && [ "$APPS" = 'ephemeral-vms-cache rbd ' ] ; then ok=yes; fi
ck "$ok" 'c. similar pool name does not change the application or size'

BACK_SIZE=3 OSDS=3
DETAIL="pool 1 'ephemeral-vms' replicated size 3 application rbd"
run
ok=no
if final_size_is 3 ; then ok=yes; fi
ck "$ok" 'd. three OSDs keep size 3'

OSDS=101
run
ok=no
if final_size_is 2 ; then ok=yes; fi
ck "$ok" 'e. 101 OSDs reduce size 3 to size 2'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
