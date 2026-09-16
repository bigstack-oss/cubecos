#!/bin/bash
#
# ceph_fsid_resolve / ceph_fsid_migrate: seed-derived on a fresh install, an
# existing cluster's own fsid on an upgrade, and never overwritten once recorded.
#
#   Run: bash test_ceph_fsid.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh
grep -E '^(CEPH_FSID_FILE|CEPH_LEGACY_FSID)=' $SRC > $T/fn.sh
for fn in _ceph_fsid_is_uuid ceph_fsid_current ceph_fsid_derive ceph_fsid_record ceph_fsid_resolve ceph_fsid_migrate ; do
    sed -n "/^$fn()/,/^}/p" $SRC >> $T/fn.sh
done
CEPH_FSID_FILE=$T/fsid
MAPFILE=$T/monmap
source $T/fn.sh
# ceph_fsid_current reads the real ceph.conf path; point it at the sandbox
eval "$(declare -f ceph_fsid_current | sed "s|/etc/ceph/ceph.conf|$T/ceph.conf|")"

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# stubs: the mon store answers only when $T/monmap_fsid exists
Warning(){ :; }
ceph_mon_map_create(){ [ -s $T/monmap_fsid ] && cp $T/monmap_fsid $MAPFILE; }
monmaptool(){ [ -s $MAPFILE ] || return 1; echo "fsid $(cat $MAPFILE)"; }

OLD=$CEPH_LEGACY_FSID
OTHER=11111111-2222-3333-4444-555555555555
reset_all(){ rm -rf $T/fsid $T/ceph.conf $T/monmap $T/monmap_fsid $T/prev; }

# --- fresh install: derived from the seed, same on every node ---
reset_all
a=$(ceph_fsid_resolve seed-a)
chk "fresh node derives a uuid"               "$(_ceph_fsid_is_uuid "$a" && echo yes)" "yes"
chk "  ...and records it"                     "$(cat $T/fsid)" "$a"
reset_all
chk "another node, same seed, same fsid"      "$(ceph_fsid_resolve seed-a)" "$a"
reset_all
b=$(ceph_fsid_resolve seed-b)
chk "a different seed, a different fsid"      "$([ "$a" != "$b" ] && echo yes)" "yes"
chk "not the rbd secret uuid for that seed"   "$([ "$b" != "$(uuidgen --sha1 --namespace @dns --name seed-b.localhost)" ] && echo yes)" "yes"
reset_all
chk "empty seed falls back to the legacy fsid" "$(ceph_fsid_resolve "")" "$OLD"

# --- once recorded, a seed change does not move it ---
reset_all
a=$(ceph_fsid_resolve seed-a)
chk "seed change keeps the recorded fsid"     "$(ceph_fsid_resolve seed-b)" "$a"
ceph_fsid_record "$OTHER"
chk "  ...and record refuses to overwrite"    "$(cat $T/fsid)" "$a"

# --- an existing cluster's fsid outranks the seed ---
reset_all
printf '[global]\n  fsid = %s\n' "$OLD" > $T/ceph.conf
chk "ceph.conf's fsid is adopted"             "$(ceph_fsid_resolve seed-a)" "$OLD"
reset_all
echo "$OLD" > $T/monmap_fsid
chk "mon store answers with ceph down"        "$(ceph_fsid_resolve seed-a)" "$OLD"
reset_all
echo "$OTHER" > $T/monmap
chk "a stale monmap file is not read"         "$(ceph_fsid_resolve seed-a)" "$(ceph_fsid_derive seed-a)"

# --- upgrade: the post-migrate hook records what the old root carried ---
reset_all
mkdir -p $T/prev/etc/ceph
printf '[global]\nfsid=%s\n' "$OTHER" > $T/prev/etc/ceph/ceph.conf
ceph_fsid_migrate $T/prev
chk "migrate takes the old root's ceph.conf"  "$(cat $T/fsid)" "$OTHER"
chk "  ...and resolve then ignores the seed"  "$(ceph_fsid_resolve seed-a)" "$OTHER"
reset_all
mkdir -p $T/prev
ceph_fsid_migrate $T/prev
chk "migrate with no old conf -> legacy"      "$(cat $T/fsid)" "$OLD"
reset_all
echo "$OTHER" > $T/fsid
ceph_fsid_migrate $T/prev
chk "migrate keeps an existing record"        "$(cat $T/fsid)" "$OTHER"

# --- garbage in is never garbage out ---
reset_all
echo "not-a-uuid" > $T/fsid
out=$(ceph_fsid_resolve seed-a); rc=$?
chk "a corrupt record fails loudly"           "$rc" "1"
chk "  ...and prints nothing"                 "$out" ""
reset_all
ceph_fsid_record "" ; rc=$?
chk "record refuses an empty fsid"            "$rc" "1"
chk "  ...writing no file"                    "$(ls $T/fsid 2>/dev/null)" ""

echo "----"
echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ] || exit 1
echo "OK: ceph_fsid"
