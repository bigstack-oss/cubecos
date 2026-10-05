#!/bin/bash
#
# Unit test for migrate_keystone_duplicate_services in ../modules/sdk_migrate.sh.
#
# keystone accepts any number of services with the same name and type, and SetupService
# re-runs whenever a module's gate reads its database as missing. cube36 collected three
# image, volumev2, volumev3, share and sharev2 entries and two load-balancer ones, each
# group with exactly one entry carrying endpoints. From the second entry on, lookups by
# type are ambiguous: os_endpoint_update fails, and cinder takes an empty image entry from
# the catalog and rejects every volume-from-image (cubecos#1638).
#
# It must delete the endpoint-less entries of a duplicated name and type, keep the one
# with endpoints, leave a group where several carry endpoints for an operator, and write
# its marker only once nothing is left.
#
# Self-contained: extracts the function and stubs openstack; jq is real, so it needs no
# cluster.  Run: bash test_migrate_keystone_duplicate_services.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract() {
    local name=$1 src=$2 fn
    fn="$(awk -v n="^$name\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$src")"
    [ -n "$fn" ] || { echo "FAIL: $name not found in $src"; exit 1; }
    eval "$fn"
}

extract migrate_keystone_duplicate_services "$DIR/../modules/sdk_migrate.sh"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# $DB holds one "id type name endpoints" line per service; the stub reads and edits it,
# so state survives the $(...) subshells the functions use. Every create and delete is
# logged to $LOG.
DB=$(mktemp) LOG=$(mktemp)
STATE_DIR=$(mktemp -d)
LIST_FAIL=0 EP_FAIL=0 DEL_FAIL=0 GARBAGE=0 ROLE=control

openstack_stub() {
    case "$*" in
        "service list -f json")
            [ $LIST_FAIL -eq 1 ] && return 1
            [ $GARBAGE -eq 1 ] && { echo "not json" ; return 0 ; }
            awk 'BEGIN{printf "["} {printf "%s{\"ID\": \"%s\", \"Name\": \"%s\", \"Type\": \"%s\"}", (NR>1?", ":""), $1, $3, $2} END{print "]"}' "$DB" ;;
        "service create --name "*" --description "*)
            local id="new$((RANDOM))"
            echo "$id $7 $4 0" >> "$DB" ; echo "create:$4/$7" >> "$LOG" ;;
        "endpoint list --service "*" -f value -c ID")
            [ $EP_FAIL -eq 1 ] && return 1
            local n=$(awk -v i="$4" '$1 == i {print $4}' "$DB")
            local k ; for k in $(seq 1 ${n:-0}) ; do echo "ep-$4-$k" ; done ;;
        "service delete "*)
            [ $DEL_FAIL -eq 1 ] && return 1
            awk -v i="$3" '$1 != i' "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB" ; echo "delete:$3" >> "$LOG" ;;
        *) echo "unexpected openstack $*" >&2 ; return 1 ;;
    esac
}
OPENSTACK=openstack_stub
is_control_node() { [ "$ROLE" = control ] ; }
log_info() { : ; }
log_warning() { : ; }
log_error() { echo "error:$*" >> "$LOG" ; }

reset() {
    printf '%s\n' "$@" | grep -v '^$' > "$DB"
    : > "$LOG"
    rm -f "$STATE_DIR/keystone_duplicate_services_removed"
    LIST_FAIL=0 EP_FAIL=0 DEL_FAIL=0 GARBAGE=0 ROLE=control
}
acts() { grep -E '^(create|delete):' "$LOG" | sort | tr '\n' ' ' ; }
count() { awk -v t="$1" -v n="$2" '$2 == t && $3 == n' "$DB" | wc -l | tr -d ' ' ; }
marked() { [ -f "$STATE_DIR/keystone_duplicate_services_removed" ] && echo y || echo n ; }

CUBE36=(
    "img1 image glance 3" "img2 image glance 0" "img3 image glance 0"
    "lb1 load-balancer octavia 3" "lb2 load-balancer octavia 0"
    "nova1 compute nova 3"
)

# ---- migrate_keystone_duplicate_services ------------------------------------
# 7. cube36's shape: keep the entry with endpoints, delete the empty ones, mark
reset "${CUBE36[@]}"
migrate_keystone_duplicate_services
chk "7 deletes" "$(acts)" "delete:img2 delete:img3 delete:lb2 "
chk "7 image left" "$(awk '$2 == "image" {print $1}' "$DB")" "img1"
chk "7 lb left" "$(awk '$2 == "load-balancer" {print $1}' "$DB")" "lb1"
chk "7 nova untouched" "$(count compute nova)" 1
chk "7 marked" "$(marked)" y

# 8. marked -> nothing listed, nothing deleted
: > "$LOG" ; echo "img9 image glance 0" >> "$DB"
migrate_keystone_duplicate_services
chk "8 nothing" "$(acts)" ""

# 9. no duplicates -> nothing deleted, marked
reset "img1 image glance 3" "nova1 compute nova 3"
migrate_keystone_duplicate_services
chk "9 nothing" "$(acts)" ""
chk "9 marked" "$(marked)" y

# 10. no entry of the group has endpoints -> keep the first, delete the rest
reset "img1 image glance 0" "img2 image glance 0" "img3 image glance 0"
migrate_keystone_duplicate_services
chk "10 deletes" "$(acts)" "delete:img2 delete:img3 "
chk "10 one left" "$(count image glance)" 1
chk "10 marked" "$(marked)" y

# 11. two entries carry endpoints -> that group is left for an operator, no marker;
#     the other groups are still cleaned
reset "img1 image glance 3" "img2 image glance 2" "img3 image glance 0" "lb1 load-balancer octavia 3" "lb2 load-balancer octavia 0"
migrate_keystone_duplicate_services
chk "11 deletes" "$(acts)" "delete:lb2 "
chk "11 image kept" "$(count image glance)" 3
chk "11 operator told" "$(grep -c '^error:.*image glance' "$LOG")" 1
chk "11 not marked" "$(marked)" n

# 12. keystone cannot be listed -> nothing, no marker
reset "${CUBE36[@]}" ; LIST_FAIL=1
migrate_keystone_duplicate_services ; rc=$?
chk "12 rc" "$rc" 0
chk "12 nothing" "$(acts)" ""
chk "12 not marked" "$(marked)" n

# 13. endpoints cannot be listed -> nothing deleted (an unknown count is not zero), no marker
reset "${CUBE36[@]}" ; EP_FAIL=1
migrate_keystone_duplicate_services
chk "13 nothing" "$(acts)" ""
chk "13 not marked" "$(marked)" n

# 14. a delete fails -> no marker, so the next commit retries
reset "${CUBE36[@]}" ; DEL_FAIL=1
migrate_keystone_duplicate_services
chk "14 not marked" "$(marked)" n

# 15. not a control node -> nothing
reset "${CUBE36[@]}" ; ROLE=compute
migrate_keystone_duplicate_services
chk "15 nothing" "$(acts)" ""
chk "15 not marked" "$(marked)" n

rm -rf "$DB" "$LOG" "$STATE_DIR"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: migrate keystone duplicate services" ; exit 0 ; } || exit 1
