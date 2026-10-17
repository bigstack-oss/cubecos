#!/bin/bash
#
# health_neutron_check creates and deletes a dummy port on every check. Passing
# `--project admin` makes the client GET /v3/projects/admin first, which keystone
# answers 404 and logs as ProjectNotFound -- once per check per control
# (cubecos#2065). The admin-openrc token is already scoped to admin, so the port
# is created without --project.
#
#   Run: bash test_health_neutron_diag_port.sh
#
set -u
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_health.sh
fn="$(awk '/^health_neutron_check\(\)/ {f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: health_neutron_check not found in $SRC"; exit 1; }
eval "$fn"

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-40s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-40s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# a healthy cluster, so the check reaches the dummy port
stale_api_check_repair(){ : ; }
influx_event_health(){ : ; }
_ovn_metadata_stuck_hosts(){ return 1 ; }
_health_fail_log(){ : ; }
HEX_SDK=hex_sdk_stub
hex_sdk_stub(){ : ; }
# BSD wc pads its count, which the check compares as a string
wc(){ command wc "$@" | tr -d ' ' ; }
openstack_stub(){
    case "$1 $2" in
        "network agent")
            printf '%s\n' "neutron-ovn-metadata-agent True c1" \
                          "neutron-ovn-vpn-agent True c1" \
                          "ovn-controller True c1" ;;
        "subnet list")
            echo "| 1111 | lb-mgmt-subnet | net-lbmgmt | 172.16.0.0/16 |" ;;
        "port create")
            echo "$*" > $T/create
            echo "port-1" ;;
        "port delete")
            echo "$3" > $T/delete ;;
    esac
}
OPENSTACK=openstack_stub
HOSTNAME=c1 ERR_CODE=0 ERR_MSG="" ERR_LOGSIZE=1

health_neutron_check
chk "port created" "$(test -s $T/create && echo yes)" "yes"
chk "port create has no --project" "$(grep -c -- --project $T/create)" "0"
chk "port created on lb-mgmt network" "$(grep -o -- '--network [^ ]*' $T/create)" "--network net-lbmgmt"
chk "created port deleted" "$(cat $T/delete 2>/dev/null)" "port-1"
chk "check passes" "$ERR_CODE" "0"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
