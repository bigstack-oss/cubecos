#!/bin/bash
#
# Unit test for os_service_create in ../modules/sdk_os.sh.
#
# keystone accepts any number of services with the same name and type, and SetupService
# re-runs whenever a module's gate reads its database as missing. cube36 collected three
# image, volumev2, volumev3, share and sharev2 entries and two load-balancer ones, each
# group with exactly one entry carrying endpoints. From the second entry on, lookups by
# type are ambiguous: os_endpoint_update fails, and cinder takes an empty image entry from
# the catalog and rejects every volume-from-image (cubecos#1638).
#
# It must create a service only when none with that name and type exists, and create
# nothing when keystone cannot be listed or the list does not parse.
#
# Self-contained: extracts the function and stubs openstack; jq is real, so it needs no
# cluster.  Run: bash test_os_service_create.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract() {
    local name=$1 src=$2 fn
    fn="$(awk -v n="^$name\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$src")"
    [ -n "$fn" ] || { echo "FAIL: $name not found in $src"; exit 1; }
    eval "$fn"
}

extract os_service_create "$DIR/../modules/sdk_os.sh"

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

# ---- os_service_create ------------------------------------------------------
# 1. a fresh install: nothing there -> created once
reset "nova1 compute nova 3"
os_service_create glance image "OpenStack Image" >/dev/null ; rc=$?
chk "1 rc" "$rc" 0
chk "1 created" "$(acts)" "create:glance/image "

# 2. a re-run SetupService: already there -> nothing created
reset "img1 image glance 3"
os_service_create glance image "OpenStack Image" >/dev/null ; rc=$?
chk "2 rc" "$rc" 0
chk "2 nothing" "$(acts)" ""

# 3. a re-run against a cluster that already has duplicates -> still nothing created
reset "${CUBE36[@]}"
os_service_create glance image "OpenStack Image" >/dev/null
chk "3 nothing" "$(acts)" ""
chk "3 still three" "$(count image glance)" 3

# 4. same name, other type, and same type, other name: each is its own service
reset "img1 image glance 3"
os_service_create glance image2 "x" >/dev/null
os_service_create glance2 image "x" >/dev/null
chk "4 both created" "$(acts)" "create:glance/image2 create:glance2/image "

# 5. keystone cannot be listed -> create nothing, fail
reset "nova1 compute nova 3" ; LIST_FAIL=1
os_service_create glance image "OpenStack Image" >/dev/null ; rc=$?
chk "5 rc" "$rc" 1
chk "5 nothing" "$(acts)" ""

# 6. the list does not parse -> create nothing, fail
reset "nova1 compute nova 3" ; GARBAGE=1
os_service_create glance image "OpenStack Image" >/dev/null ; rc=$?
chk "6 rc" "$rc" 1
chk "6 nothing" "$(acts)" ""

rm -rf "$DB" "$LOG" "$STATE_DIR"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: os_service_create" ; exit 0 ; } || exit 1
