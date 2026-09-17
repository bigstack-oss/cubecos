#!/bin/bash
#
# ceph_fsid_resolve: which fsid a node ends up with, and -- the part that
# matters -- that an existing cluster's own fsid always outranks a new one.
#
#   Run: bash test_ceph_fsid.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh
for fn in _ceph_fsid_is_uuid ceph_fsid_current ceph_fsid_record ceph_fsid_resolve ; do
    sed -n "/^$fn()/,/^}/p" $SRC >> $T/fn.sh
done
CEPH_FSID_FILE=$T/fsid
CONF=$T/ceph.conf
MAPFILE=$T/monmap

source $T/fn.sh

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# stubs for the two sources, each switched off by default
export T
ceph_mon_map_create(){ :; }
monmaptool(){ [ -s $T/monmap_fsid ] || return 1; echo "fsid $(cat $T/monmap_fsid)"; }

OLD=c6e64c49-09cf-463b-9d1c-b6645b4b3b85
reset_all(){ rm -f $T/fsid $T/ceph.conf $T/monmap_fsid; }

# --- a fresh bootstrap node mints one, and only when allowed to ---
reset_all
out=$(ceph_fsid_resolve 0); rc=$?
chk "joining node with no cluster yet fails"  "$rc" "1"
chk "  ...and records nothing"                "$(cat $T/fsid 2>/dev/null)" ""

reset_all
out=$(ceph_fsid_resolve 1)
chk "bootstrap node mints a uuid"             "$(_ceph_fsid_is_uuid "$out" && echo yes)" "yes"
chk "  ...and records it"                     "$(cat $T/fsid)" "$out"

# minting is once: the recorded value wins on every later call
again=$(ceph_fsid_resolve 1)
chk "second call returns the same fsid"       "$again" "$out"

# --- an existing cluster's fsid outranks a new one: the upgrade case ---
reset_all
printf '[global]\n  fsid = %s\n' "$OLD" > $T/ceph.conf
out=$(ceph_fsid_resolve 1)
chk "ceph.conf's fsid is adopted"             "$out" "$OLD"
chk "  ...and recorded, not regenerated"      "$(cat $T/fsid)" "$OLD"

reset_all
echo "$OLD" > $T/monmap_fsid
out=$(ceph_fsid_resolve 1)
chk "mon store answers with ceph down"        "$out" "$OLD"

# --- a recorded fsid is never overwritten, whatever the cluster says ---
reset_all
echo "$OLD" > $T/fsid
echo "11111111-2222-3333-4444-555555555555" > $T/monmap_fsid
out=$(ceph_fsid_resolve 1)
chk "recorded fsid outranks the cluster's"    "$out" "$OLD"
ceph_fsid_record "11111111-2222-3333-4444-555555555555"
chk "  ...and record refuses to overwrite"    "$(cat $T/fsid)" "$OLD"

# --- garbage in is never garbage out ---
reset_all
echo "not-a-uuid" > $T/fsid
out=$(ceph_fsid_resolve 1); rc=$?
chk "a corrupt record fails loudly"           "$rc" "1"
chk "  ...and prints nothing"                 "$out" ""

reset_all
echo "1" > $T/monmap_fsid         # the sdk's own failure sentinel
out=$(ceph_fsid_resolve 0); rc=$?
chk "sentinel from a failed probe is refused" "$rc" "1"

reset_all
ceph_fsid_record "" ; rc=$?
chk "record refuses an empty fsid"            "$rc" "1"
chk "  ...writing no file"                    "$(ls $T/fsid 2>/dev/null)" ""

echo "----"
echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ] || exit 1
echo "OK: ceph_fsid_resolve"
