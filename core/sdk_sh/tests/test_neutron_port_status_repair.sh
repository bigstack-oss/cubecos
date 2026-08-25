#!/bin/bash
#
# Unit test for the neutron ERR_CODE 7 (port status stale vs OVN) repair paths:
#   os_neutron_ovn_port_status_stale  -- ../modules/sdk_os.sh
#   _health_neutron_auto_repair       -- ../modules/sdk_health.sh (auto path)
#   health_neutron_repair             -- ../modules/sdk_health.sh (operator path)
#
# The regression that matters: the repair's first action toggles admin_state_up,
# which refreshes the port's updated_at -- so a re-check that keeps the detector's
# 90s grace period reports a still-stale port as healthy and the neutron-server
# restart never escalates. Observed on QA 10.32.36.10: toggle ran, no restart
# followed, ports stayed DOWN until neutron-server was bounced by hand.
#
# Self-contained: extracts only the functions under test and stubs openstack,
# ovn-nbctl, hex_sdk, remote_systemd_restart and sleep, so it needs no cluster.
#   Run: bash test_neutron_port_status_repair.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_SRC="$DIR/../modules/sdk_os.sh"
HEALTH_SRC="$DIR/../modules/sdk_health.sh"

extract() {
    local name=$1 src=$2 fn
    fn="$(awk -v n="^$name\\\\(\\\\)" '$0 ~ n {f=1} f{print} f&&/^}/{exit}' "$src")"
    [ -n "$fn" ] || { echo "FAIL: $name not found in $src"; exit 1; }
    eval "$fn"
}

extract os_neutron_ovn_port_status_stale "$OS_SRC"
extract _health_neutron_auto_repair "$HEALTH_SRC"
extract health_neutron_repair "$HEALTH_SRC"

pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got '$2', want '$3'"; fi; }

# ---- fixture -------------------------------------------------------------
# PORT_STATUS[p]=DOWN|ACTIVE   PORT_UP[p]=true|false   PORT_AGE[p]=seconds
declare -A PORT_STATUS PORT_UP PORT_AGE
RESTARTS=""      # "<node>:<service>" per remote_systemd_restart
TOGGLED=""       # ports passed to the resync helper
CALLS=""         # other hex_sdk calls

reset_fixture() {
    PORT_STATUS=([p1]=DOWN [p2]=DOWN [p3]=ACTIVE)
    PORT_UP=([p1]=true [p2]=true [p3]=true)
    PORT_AGE=([p1]=300 [p2]=300 [p3]=300)
    RESTARTS=""; TOGGLED=""; CALLS=""
    unset OVN_PORT_STALE_MIN_AGE || true
}

# openstack stub: only the three forms the code under test uses
openstack_stub() {
    case "$*" in
        "port list --device-owner compute:nova -f json")
            local p first=1
            echo -n "["
            for p in "${!PORT_STATUS[@]}"; do
                [ $first -eq 1 ] || echo -n ","
                first=0
                echo -n "{\"ID\": \"$p\", \"Status\": \"${PORT_STATUS[$p]}\"}"
            done
            echo "]" ;;
        "port show "*" -f value -c status")
            local p=$(echo "$*" | awk '{print $3}')
            echo "${PORT_STATUS[$p]:-}" ;;
        "port show "*" -f value -c updated_at")
            local p=$(echo "$*" | awk '{print $3}')
            # updated_at rendered from the fixture age
            date -u -d "@$(( $(date -u +%s) - ${PORT_AGE[$p]:-0} ))" +%Y-%m-%dT%H:%M:%SZ ;;
        "network agent list -f value -c Alive") echo "True" ;;
        "network agent list -f json -c ID -c Alive") echo "[]" ;;
        "subnet list") : ;;
        *) : ;;
    esac
}
OPENSTACK=openstack_stub

ovn-nbctl() {  # --timeout=5 get logical_switch_port <p> up
    local p=$4
    echo "${PORT_UP[$p]:-false}"
}

# hex_sdk stub: dispatch to the real detector, record everything else
hex_sdk_stub() {
    case "$1" in
        os_neutron_ovn_port_status_stale)
            shift; os_neutron_ovn_port_status_stale "$@" ;;
        os_neutron_ovn_port_status_resync)
            shift; TOGGLED="$*"
            # the toggle writes to the port -- updated_at is refreshed. This is
            # the whole point of the regression: it does NOT fix a real desync.
            local p; for p in "$@"; do PORT_AGE[$p]=0; done ;;
        *) CALLS+="$* " ;;
    esac
}
HEX_SDK=hex_sdk_stub
HEX_CFG=:

remote_systemd_restart() {
    RESTARTS+="$1:$2 "
    # a neutron-server bounce re-derives status: model it as the fix
    if [ "$2" = "neutron-server" ]; then
        local p; for p in "${!PORT_STATUS[@]}"; do PORT_STATUS[$p]=ACTIVE; done
    fi
}

sleep() { :; }

# Quiet/cmd are wrappers, not sinks: strip their flags and run what they wrap,
# or the repair's own actions never happen and every assertion below is vacuous.
Quiet() {
    while [ $# -gt 0 ] && case "$1" in -*|--) true ;; *) false ;; esac; do shift; done
    [ $# -gt 0 ] || return 0
    "$@"
}
cmd() {
    while [ $# -gt 0 ] && case "$1" in -*|--) true ;; *) false ;; esac; do shift; done
    [ $# -gt 0 ] || return 0
    # only shell functions (our stubs) are safe to run in a unit test
    if declare -F "$1" >/dev/null 2>&1; then "$@"; else CALLS+="$* "; fi
}
jq() { echo ""; }
log_info() { :; }
_ovn_metadata_wait_caught_up() { :; }
CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
OVN_META_STUCK=""
CEPH=:

# ---- the detector --------------------------------------------------------
reset_fixture
check "stale ports, default grace" "$(os_neutron_ovn_port_status_stale | sort | tr '\n' ' ')" "p1 p2 "

reset_fixture
PORT_AGE=([p1]=10 [p2]=10 [p3]=300)
check "inside the plug window: not stale" "$(os_neutron_ovn_port_status_stale)" ""
check "same ports with no grace period" \
    "$(OVN_PORT_STALE_MIN_AGE=0 os_neutron_ovn_port_status_stale | sort | tr '\n' ' ')" "p1 p2 "

reset_fixture
check "named port restricts the scan" "$(os_neutron_ovn_port_status_stale p2)" "p2"
check "an ACTIVE named port is not stale" "$(os_neutron_ovn_port_status_stale p3)" ""

reset_fixture
PORT_UP=([p1]=false [p2]=false [p3]=true)
check "DOWN in both neutron and OVN is not a desync" "$(os_neutron_ovn_port_status_stale)" ""

reset_fixture
os_neutron_ovn_port_status_stale >/dev/null; check "rc 0 when stale" "$?" "0"
PORT_STATUS=([p1]=ACTIVE [p2]=ACTIVE [p3]=ACTIVE)
os_neutron_ovn_port_status_stale >/dev/null; check "rc 1 when clean" "$?" "1"

# ---- auto path (ERR_CODE 7) ---------------------------------------------
# The toggle runs first; because it refreshes updated_at, the fallback must
# re-check without the grace period or it never escalates (the QA symptom).
reset_fixture
ERR_CODE=7 ERR_MSG="" OVN_STALE_PORTS="p1 p2"
_health_neutron_auto_repair
check "auto path toggles the stale ports" "$TOGGLED" "p1 p2"
check "auto path escalates to a neutron-server bounce" "$RESTARTS" "c1:neutron-server "

# toggle actually works (ports come back ACTIVE): no restart at all
reset_fixture
hex_sdk_stub() {
    case "$1" in
        os_neutron_ovn_port_status_stale) shift; os_neutron_ovn_port_status_stale "$@" ;;
        os_neutron_ovn_port_status_resync)
            shift; TOGGLED="$*"
            local p; for p in "$@"; do PORT_STATUS[$p]=ACTIVE; PORT_AGE[$p]=0; done ;;
        *) CALLS+="$* " ;;
    esac
}
ERR_CODE=7 ERR_MSG="" OVN_STALE_PORTS="p1 p2"
_health_neutron_auto_repair
check "toggle sufficed: no restart" "$RESTARTS" ""

# restore the realistic stub
hex_sdk_stub() {
    case "$1" in
        os_neutron_ovn_port_status_stale) shift; os_neutron_ovn_port_status_stale "$@" ;;
        os_neutron_ovn_port_status_resync)
            shift; TOGGLED="$*"
            local p; for p in "$@"; do PORT_AGE[$p]=0; done ;;
        *) CALLS+="$* " ;;
    esac
}

# ---- operator path (check_repair) ---------------------------------------
reset_fixture
health_neutron_repair
check "operator path bounces neutron-server" "$RESTARTS" "c1:neutron-server "
check "operator path does not toggle first" "$TOGGLED" ""

reset_fixture
PORT_STATUS=([p1]=ACTIVE [p2]=ACTIVE [p3]=ACTIVE)
health_neutron_repair
check "no stale ports: no restart" "$RESTARTS" ""

# a node whose restart does not clear it moves on to the next node
reset_fixture
remote_systemd_restart() { RESTARTS+="$1:$2 "; }   # never clears
health_neutron_repair
check "escalates across every control node" "$RESTARTS" \
    "c1:neutron-server c2:neutron-server c3:neutron-server "

echo "----"
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ] || exit 1
exit 0
