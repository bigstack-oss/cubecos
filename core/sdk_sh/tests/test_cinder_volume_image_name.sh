#!/bin/bash
T=$(mktemp -d)
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_cinder.sh
sed -n '/^cinder_volume_image_name()/,/^}/p' $SRC > $T/fn.sh; source $T/fn.sh
chk(){ printf '%-40s -> %-46s (want %s)\n' "$1" "$2" "$3"; }
_civ_name_id() { cat $T/name_id; }

echo "" > $T/name_id
chk "never migrated" "$(cinder_volume_image_name aaa)" "volume-aaa"
echo "None" > $T/name_id
chk "name_id literal None" "$(cinder_volume_image_name aaa)" "volume-aaa"
echo "bbb" > $T/name_id
chk "migrated volume" "$(cinder_volume_image_name aaa)" "volume-bbb"

rm -rf $T
