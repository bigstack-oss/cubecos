#!/bin/bash
#
# Unit test for ceph_adjust_pool_pg / ceph_adjust_pgs in ../modules/sdk_ceph.sh:
# a pool with the autoscaler off gets pg_num/pgp_num set to the power of two
# nearest 200 * up OSDs * data_pct / (size * 1000), held within the pool's own
# pg_num_min/pg_num_max, and a value ceph cannot take, or a pg_num ceph
# rejects, is reported instead of passing as success.
#
# Self-contained: extracts the two functions and fakes ceph, so it needs no
# cluster; Quiet mirrors hex_sdk's (-n forces rc 0 and hides the output).
#   Run: bash test_ceph_adjust_pool_pg.sh
#
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ceph.sh"
for f in ceph_adjust_pool_pg ceph_adjust_pgs ; do
    eval "$(awk -v n="^$f\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ "$(type -t "$f")" = function ] || { echo "FAIL: $f not extracted"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS=$TMP/calls
BUILTIN_CACHEPOOL=cachepool
BUILTIN_BACKPOOL=cinder-volumes

Quiet() {
    local ign=0 out=$TMP/quiet st=0
    [ "$1" = "-n" ] && { ign=1; shift; }
    eval $* >$out 2>&1 || st=$?
    [ $ign -eq 0 ] || st=0
    [ $st -eq 0 ] || cat $out >&2
    return $st
}
ceph_adjust_cache_flush_bytes() { :; }

# fake cluster: UP osds, SIZE of every pool, MODES "<pool>:<autoscale mode> ..."
# (default off), MINS / MAXS "<pool>:<n> ..." (default unset), REJECT a pool
# flagged nopgchange, so its pg_num set fails with EPERM
UP=2 SIZE=1 POOLS="seki-t" REJECT= MODES= MINS= MAXS=
lookup() { local m; for m in $1 ; do [ "${m%%:*}" = "$2" ] && { echo "${m#*:}"; return; }; done; }
mode_of() { local m=$(lookup "$MODES" $1); echo ${m:-off}; }
CEPH=fake_ceph
fake_ceph() {
    case "$*" in
        "osd pool ls") printf '%s\n' $POOLS ;;
        "osd stat") [ -n "$UP" ] && echo "$UP osds: $UP up (since 2h), $UP in (since 3h); epoch: e234" ;;
        "osd pool get "*" pg_autoscale_mode") echo "pg_autoscale_mode: $(mode_of $4)" ;;
        "osd pool get "*" all -f json")
            local mn=$(lookup "$MINS" $4) mx=$(lookup "$MAXS" $4)
            echo "{\"pool\":\"$4\"${SIZE:+,\"size\":$SIZE},\"pg_num\":8${mn:+,\"pg_num_min\":$mn}${mx:+,\"pg_num_max\":$mx}}"
            ;;
        "osd pool set "*)
            echo "$4 $5 $6" >> $CALLS
            [ -n "$6" ] || { echo "Error EINVAL: error parsing integer value ''" >&2; return 22; }
            [ "$5" = pg_num ] && [ "$4" = "$REJECT" ] && { echo "Error EPERM: pool pg_num change is disabled; you must unset nopgchange flag for the pool first" >&2; return 1; }
            echo "set pool 26 $5 to $6"
            ;;
        *) echo "unexpected: $*" >&2; return 1 ;;
    esac
}

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-52s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-52s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}
# run <args...>: ceph_adjust_pool_pg with fresh call log; sets OUT ERR RC
run() {
    : > $CALLS
    "$@" >$TMP/out 2>$TMP/err; RC=$?
    OUT=$(cat $TMP/out) ERR=$(cat $TMP/err)
}
calls() { tr '\n' ';' < $CALLS; }

# --- the computed target reaches ceph ---
run ceph_adjust_pool_pg seki-t 400                  # 200*2*400/1000=160 -> 128
chk "2 up, size 1, 400: pg_num and pgp_num set"       "$(calls)" "seki-t pg_num 128;seki-t pgp_num 128;"
chk "  ...rc 0"                                       "$RC" "0"
chk "  ...the message names the number"               "$OUT" "set pool 'seki-t' pg number to 128"
chk "  ...nothing on stderr"                          "$ERR" ""
run ceph_adjust_pool_pg seki-t 1                    # 0 -> falls back to up OSDs (2)
chk "data_pct 1 falls back to the up OSD count"       "$(calls)" "seki-t pg_num 2;seki-t pgp_num 2;"
UP=3 SIZE=3
run ceph_adjust_pool_pg seki-t 400                  # 200*3*400/3000=80 -> 64
chk "3 up, size 3, 400: rounds 80 down to 64"         "$(calls)" "seki-t pg_num 64;seki-t pgp_num 64;"
UP=12 SIZE=3
run ceph_adjust_pool_pg seki-t 400                  # 320 -> log2 8.32 -> 256
chk "12 up, size 3, 400: 320 -> 256"                  "$(calls)" "seki-t pg_num 256;seki-t pgp_num 256;"
run ceph_adjust_pool_pg seki-t 100                  # 80 -> 64
chk "12 up, size 3, 100: 80 -> 64"                    "$(calls)" "seki-t pg_num 64;seki-t pgp_num 64;"
UP=2 SIZE=1

# --- the pool's own bounds win over the share ---
MINS="seki-t:16"
run ceph_adjust_pool_pg seki-t 10                   # cephfs_metadata: 4, pg_num_min 16
chk "below pg_num_min: raised to it"                  "$(calls)" "seki-t pg_num 16;seki-t pgp_num 16;"
run ceph_adjust_pool_pg seki-t 400
chk "above pg_num_min: untouched"                     "$(calls)" "seki-t pg_num 128;seki-t pgp_num 128;"
MINS= MAXS="seki-t:32"
run ceph_adjust_pool_pg seki-t 400                  # 128, pg_num_max 32
chk "above pg_num_max: capped to it"                  "$(calls)" "seki-t pg_num 32;seki-t pgp_num 32;"
run ceph_adjust_pool_pg seki-t 1
chk "below pg_num_max: untouched"                     "$(calls)" "seki-t pg_num 2;seki-t pgp_num 2;"
MAXS=

# --- the autoscaler owns the pool: hands off ---
MODES="seki-t:on"
run ceph_adjust_pool_pg seki-t 400
chk "autoscale on: nothing set"                       "$(calls)" ""
chk "  ...rc 0"                                       "$RC" "0"
MODES="seki-t:warn"
run ceph_adjust_pool_pg seki-t 400
chk "autoscale warn is not on: adjusted"              "$(calls)" "seki-t pg_num 128;seki-t pgp_num 128;"
MODES=

# --- an unreadable input never becomes an empty pg_num ---
UP=
run ceph_adjust_pool_pg seki-t 400
chk "osd stat unreadable: nothing set"                "$(calls)" ""
chk "  ...rc 1"                                       "$RC" "1"
chk "  ...says why"                                   "$ERR" "Error: cannot size pool 'seki-t' (up OSDs '?', size '1')"
UP=0
run ceph_adjust_pool_pg seki-t 400
chk "no OSD up: nothing set, rc 1"                    "$(calls)/$RC" "/1"
UP=2 SIZE=
run ceph_adjust_pool_pg seki-t 400
chk "pool size unreadable: nothing set, rc 1"         "$(calls)/$RC" "/1"
SIZE=1

# --- a pg_num ceph rejects is reported, not swallowed ---
REJECT=seki-t
run ceph_adjust_pool_pg seki-t 400
chk "rejected pg_num: rc 1"                           "$RC" "1"
chk "  ...ceph's error reaches stderr"                "$ERR" "Error EPERM: pool pg_num change is disabled; you must unset nopgchange flag for the pool first"
chk "  ...pgp_num is not attempted"                   "$(calls)" "seki-t pg_num 128;"
REJECT=

# --- ceph_adjust_pgs: per-pool shares, and one failure does not stop the rest ---
POOLS="cinder-volumes glance-images default.rgw.log"
run ceph_adjust_pgs
chk "all pools adjusted by share"                     "$(calls)" "cinder-volumes pg_num 128;cinder-volumes pgp_num 128;glance-images pg_num 32;glance-images pgp_num 32;default.rgw.log pg_num 2;default.rgw.log pgp_num 2;"
chk "  ...rc 0"                                       "$RC" "0"
REJECT=cinder-volumes
run ceph_adjust_pgs
chk "first pool rejected: the rest still adjusted"    "$(calls)" "cinder-volumes pg_num 128;glance-images pg_num 32;glance-images pgp_num 32;default.rgw.log pg_num 2;default.rgw.log pgp_num 2;"
chk "  ...rc 1"                                       "$RC" "1"
REJECT=
MODES="cinder-volumes:on glance-images:on default.rgw.log:on"
run ceph_adjust_pgs
chk "every pool autoscaled: nothing set, rc 0"        "$(calls)/$RC" "/0"

echo "== $pass passed, $fail failed"
[ $fail -eq 0 ]
