#!/bin/bash
#
# Unit test for os_manila_image_import in ../modules/sdk_os.sh (#2364).
# An in-use image cannot be deleted. Import must tag each new image and retire
# surviving old images by name and tag, so Manila finds only the new image.
# Self-contained: extract only the function under test and simulate Glance in
# files; no cluster or network is needed. Compatible with bash 3.2 and bash 5.
#   Run: bash test_os_manila_image_import.sh (exit 0 = pass)
#   SRC=<other sdk_os.sh> tests another version; develop must fail cases 3-7.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../modules/sdk_os.sh}"

extract() {
    local name=$1 fn
    fn="$(awk -v n="$name" '$0 == n "()" {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || return 1
    eval "$fn"
}
extract os_manila_image_import || { echo "FAIL: os_manila_image_import not found in $SRC"; exit 1; }

pass=0 fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2', want '$3'"; fi; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
TABLE=$TMP/images
CALLS=$TMP/calls
IN_USE=$TMP/in-use
OPENSTACK=fake_openstack
ACTIVE=manila-service-image
RETIRED=manila-service-image-retired
OLD=99f40393-6c80-4e42-8de7-f982cbb873a1
OTHER=18cc2f62-4d27-49fa-9d6b-5ad0e39e4d2a

add_image() { printf '%s|%s\n' "$2" "$3" > "$TABLE/$1"; }
fake_openstack() {
    echo "$*" >> "$CALLS"
    [ "$#" -ge 2 ] && [ "$1" = image ] || return 2
    local action=$2 id name tags filter value path rc=0 new_name='' tag='' unset_tag=0
    shift 2
    case "$action" in
        list)
            [ "$#" = 6 ] && [ "$1" = -f ] && [ "$2" = value ] &&
                [ "$5" = -c ] && [ "$6" = ID ] || return 2
            filter=$3 value=$4
            case "$filter" in
                --property) case "$value" in name=*) value=${value#name=} ;; *) return 2 ;; esac ;;
                --tag) ;;
                *) return 2 ;;
            esac
            for path in "$TABLE"/* ; do
                [ -f "$path" ] || continue
                IFS='|' read -r name tags < "$path"
                if [ "$filter" = --property ]; then
                    [ "$name" != "$value" ] || echo "${path##*/}"
                else
                    case " $tags " in *" $value "*) echo "${path##*/}" ;; esac
                fi
            done
            ;;
        delete)
            [ "$#" -gt 0 ] || return 2
            for id in "$@" ; do
                if grep -qxF "$id" "$IN_USE"; then
                    echo "Image $id is in use" >&2
                    rc=1
                elif [ -f "$TABLE/$id" ]; then
                    rm "$TABLE/$id"
                else
                    rc=1
                fi
            done
            return "$rc"
            ;;
        set|unset)
            [ "$action" != unset ] || unset_tag=1
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --name) [ "$#" -ge 2 ] && [ "$action" = set ] || return 2
                        new_name=$2; shift 2 ;;
                    --tag) [ "$#" -ge 2 ] || return 2
                        tag=$2; shift 2 ;;
                    --*) return 2 ;;
                    *) break ;;
                esac
            done
            # Validate before mutation: the real CLI rejects multiple image IDs.
            if [ "$#" != 1 ]; then
                echo "unrecognized arguments: $*" >&2
                return 2
            fi
            id=$1
            [ -f "$TABLE/$id" ] || return 1
            IFS='|' read -r name tags < "$TABLE/$id"
            [ -z "$new_name" ] || name=$new_name
            if [ -n "$tag" ]; then
                if [ "$unset_tag" = 1 ]; then
                    local kept='' t
                    for t in $tags; do
                        [ "$t" = "$tag" ] || kept="${kept:+$kept }$t"
                    done
                    tags=$kept
                else
                    case " $tags " in *" $tag "*) ;; *) tags="${tags:+$tags }$tag" ;; esac
                fi
            fi
            add_image "$id" "$name" "$tags"
            ;;
        *) return 2 ;;
    esac
}

os_image_import() {
    echo "import $*" >> "$CALLS"
    [ "$#" = 4 ] && [ "$1" = "$TMP" ] && [ "$2" = image.qcow2 ] &&
        [ "$3" = "$ACTIVE" ] && [ "$4" = '--visibility private' ] || return 2
    [ "$IMPORT_FAIL" = 0 ] || return 1
    NEXT=$((NEXT+1))
    printf -v NEW 'aabbccdd-1234-4abc-8def-%012d' "$NEXT"
    add_image "$NEW" "$3" ''
}

reset() {
    rm -rf "$TABLE"
    mkdir "$TABLE"
    : > "$CALLS"
    : > "$IN_USE"
    NEXT=0 NEW='' IMPORT_FAIL=0
}
run_import() {
    : > "$CALLS"
    os_manila_image_import "$TMP" image.qcow2 > "$TMP/output" 2>&1
    RC=$?
}
check_image() {
    local label=$1 id=$2 name tags
    if [ ! -f "$TABLE/$id" ]; then bad "$label: missing image $id"; return; fi
    IFS='|' read -r name tags < "$TABLE/$id"
    check "$label name" "$name" "$3"
    check "$label tags" "$tags" "$4"
}
check_gone() {
    if [ -f "$TABLE/$2" ]; then bad "$1: image still exists"; else ok; fi
}
check_current() {
    check "$1 rc" "$RC" 0
    check "$1 unique current image" "$(fake_openstack image list -f value --property name="$ACTIVE" -c ID)" "$NEW"
    check_image "$1 new image" "$NEW" "$ACTIVE" "$ACTIVE"
}
check_retired() { check_image "$1" "$OLD" "$ACTIVE-${OLD:0:8}" "$RETIRED"; }

# 1. First import, including the empty-olds grep split.
reset
run_import
check_current '1 first import'
check '1 no delete call' "$(grep -c '^image delete' "$CALLS")" 0

# 2. An unused old image is deleted.
reset
add_image "$OLD" "$ACTIVE" "$ACTIVE"
run_import
check_current '2 unused old'
check_gone '2 old deleted' "$OLD"

# 3. An in-use old image survives, renamed and retired.
reset
add_image "$OLD" "$ACTIVE" "$ACTIVE"
echo "$OLD" > "$IN_USE"
run_import
check_current '3 in-use old'
check_retired '3 survivor'
FIRST=$NEW

# 4. Import again while the original old image remains in use.
run_import
check_current '4 repeated import'
check_retired '4 survivor'
check_gone '4 previous import deleted' "$FIRST"
check '4 one delete call for current and retired' "$(grep '^image delete' "$CALLS")" "image delete $FIRST $OLD"

# 5. Retire an image, release it, then import again to collect it.
reset
add_image "$OLD" "$ACTIVE" "$ACTIVE"
echo "$OLD" > "$IN_USE"
run_import
check_retired '5 setup retired image'
FIRST=$NEW
: > "$IN_USE"
run_import
check_current '5 released retired'
check_gone '5 retired deleted' "$OLD"
check_gone '5 previous import deleted' "$FIRST"

# 6. Multiple old images: partial delete success and per-ID tagging.
reset
add_image "$OLD" "$ACTIVE" "$ACTIVE"
add_image "$OTHER" "$ACTIVE" "$ACTIVE"
echo "$OLD" > "$IN_USE"
run_import
check '6 one delete call for both old images' "$(grep '^image delete' "$CALLS")" "image delete $OTHER $OLD"
check_current '6 mixed old images'
check_retired '6 in-use survivor'
check_gone '6 unused old deleted' "$OTHER"

# 7. No new image: fail without renaming or changing tags on the survivor.
reset
add_image "$OLD" "$ACTIVE" "$ACTIVE"
echo "$OLD" > "$IN_USE"
IMPORT_FAIL=1
run_import
if [ "$RC" != 0 ]; then ok; else bad '7 empty import must fail'; fi
check_image '7 unchanged survivor' "$OLD" "$ACTIVE" "$ACTIVE"
check '7 no set/unset calls' "$(grep -Ec '^image (set|unset) ' "$CALLS")" 0
check '7 only the old image remains' "$(ls "$TABLE")" "$OLD"

# 8. A matching name prefix without a retired tag belongs to someone else.
reset
add_image "$OTHER" "$ACTIVE-custom" 'customer-tag'
run_import
check_current '8 unrelated image'
check_image '8 untouched custom image' "$OTHER" "$ACTIVE-custom" 'customer-tag'

if [ "$fail" = 0 ]; then
    echo "PASS ($pass checks)"
    exit 0
fi
echo "FAIL ($fail failures, $pass checks passed)"
exit 1
