#!/bin/bash
#
# cinder_volume_image_name maps a volume id to the RBD image backing it. A
# volume that has been migrated keeps its original image name on the record as
# os-vol-mig-status-attr:name_id, so the mapping has to read that attribute --
# and reading it has to actually work, which is why the second half of this
# suite exercises the real _civ_name_id rather than a stub of it.
#
#   Run: bash test_cinder_volume_image_name.sh
#
set -u
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_volume_image_name()/,/^}/p' $SRC > $T/fn.sh
sed -n '/^_civ_name_id()/p' $SRC >> $T/fn.sh       # one-liner
source $T/fn.sh
[ "$(type -t _civ_name_id)" = function ] || { echo "FAIL: _civ_name_id not extracted"; exit 1; }

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# ==== 1. the mapping, over a stubbed name_id ==============================
_civ_name_id_real=$(declare -f _civ_name_id)
_civ_name_id() { cat $T/name_id; }

echo "" > $T/name_id
chk "never migrated" "$(cinder_volume_image_name aaa)" "volume-aaa"
echo "None" > $T/name_id
chk "name_id literal None" "$(cinder_volume_image_name aaa)" "volume-aaa"
echo "null" > $T/name_id
chk "name_id literal null" "$(cinder_volume_image_name aaa)" "volume-aaa"
echo "bbb" > $T/name_id
chk "migrated volume" "$(cinder_volume_image_name aaa)" "volume-bbb"

# ==== 2. the real _civ_name_id ============================================
# The stub above is why cubecos#1490's review found _civ_name_id calling an
# undefined $CINDER -- expanding to the bare word `show`, so the lookup always
# came back empty and every migrated volume resolved to volume-<vol_id>.
unset -f _civ_name_id
eval "$_civ_name_id_real"

mkdir -p $T/bin
# `cinder show` as the client actually prints it: a pretty table
cat > $T/bin/cinder <<'STUB'
#!/bin/bash
[ "$1" = show ] || exit 1
cat <<TABLE
+---------------------------------------+--------------------------------------+
| Property                              | Value                                |
+---------------------------------------+--------------------------------------+
| id                                    | $2                                   |
| os-vol-mig-status-attr:migstat        | success                              |
| os-vol-mig-status-attr:name_id        | $(cat "$NAME_ID_FILE")               |
| status                                | in-use                               |
+---------------------------------------+--------------------------------------+
TABLE
STUB
chmod +x $T/bin/cinder
# a stub for the word the broken version degenerated to; if it is ever run,
# the command word was empty
cat > $T/bin/show <<STUB
#!/bin/bash
touch "$T/show_was_invoked"
STUB
chmod +x $T/bin/show
export PATH="$T/bin:$PATH"
export NAME_ID_FILE=$T/name_id

echo "bbb" > $T/name_id
CINDER=$T/bin/cinder
chk "real lookup: name_id present" "$(_civ_name_id aaa)" "bbb"
chk "real lookup: through the mapping" "$(cinder_volume_image_name aaa)" "volume-bbb"
echo "None" > $T/name_id
chk "real lookup: name_id None" "$(_civ_name_id aaa)" "None"
chk "real lookup: None maps to the volume id" "$(cinder_volume_image_name aaa)" "volume-aaa"

# The command word must be the cinder binary, not an empty expansion that
# leaves `show <id>` as the command. Run with CINDER unset, the way hex_sdk
# runs it on a node, and assert nothing named `show` was executed.
echo "bbb" > $T/name_id
rm -f $T/show_was_invoked
( set +u ; unset CINDER ; _civ_name_id aaa >/dev/null 2>&1 )
chk "unset CINDER does not run bare 'show'" "$([ -e $T/show_was_invoked ] && echo invoked || echo no)" "no"

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: cinder_volume_image_name"
exit 0
