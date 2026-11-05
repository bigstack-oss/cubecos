#!/bin/bash
#
# Unit test for health_link_check in ../modules/sdk_health.sh (cubecos#2257).
#
# A hung bnxt_en firmware command channel (HWRM) leaves the data path forwarding, so
# the pings pass and the check used to report ok. The check must count only the
# driver's "Error (timeout: N)" lines in each node's last 10 minutes of kernel log, per
# PCI device and interface, and report code 2 naming them; a ping failure stays code 1.
# A node whose log cannot be read must not alarm.
#
# Self-contained: extracts only the function and stubs timeout, ping, ssh and
# _health_fail_log. The remote pipeline runs against fixture journalctl output.
# Requires bash >= 4. Run: bash test_health_link_check.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

fn="$(awk '/^health_link_check\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: health_link_check not extracted"; exit 1; }
eval "$fn"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# FIXTURE[node] supplies the kernel log. Each ssh and journalctl invocation is
# logged; failure maps allow partial output from unsuccessful reads to be tested.
declare -A FIXTURE SSH_FAIL JOURNAL_FAIL
LOG=$(mktemp)
JOURNAL_LOG=$(mktemp)
trap 'rm -f "$LOG" "$JOURNAL_LOG"' EXIT
export JOURNAL_LOG
SRVSTO=10
ERR_LOGSIZE=100
PING_FAIL=""

timeout() { shift ; "$@" ; }
ping() { [ "${*: -1}" != "$PING_FAIL" ] ; }
journalctl() {
    echo "$*" >> "$JOURNAL_LOG"
    printf '%s\n' "$KERNEL_LOG"
    return "$JOURNAL_RC"
}
export -f journalctl
ssh() {
    local n=0 node="" cmd="" a
    for a in "$@" ; do
        case "$a" in
            -n) n=1 ;;
            root@*) node=${a#root@} ;;
            *) cmd=$a ;;
        esac
    done
    echo "node=$node n=$n cmd=$cmd" >> "$LOG"
    [ "${SSH_FAIL[$node]:-0}" = 0 ] || return 255
    KERNEL_LOG=${FIXTURE[$node]:-} JOURNAL_RC=${JOURNAL_FAIL[$node]:-0} bash -c "$cmd"
}
_health_fail_log() { : ; }

run() { ERR_CODE=0 ; ERR_MSG="" ; ERR_LOG="" ; : > "$LOG" ; : > "$JOURNAL_LOG" ; health_link_check ; }
msg() { printf '%b' "$ERR_MSG" | grep "^$1 " ; }

CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)
CUBE_NODE_LIST_IPS=(10.0.0.1 10.0.0.2 10.0.0.3)
timeout_eth0='Nov 05 kernel: bnxt_en 0000:c8:00.0 eth0: Error (timeout: 3000015) msg {0x23 0x66b8} len:0'
timeout_eth2='Nov 05 kernel: bnxt_en 0000:c8:00.2 eth2: Error (timeout: 3000020) msg {0x24 0x66b9} len:0'
noise='Nov 05 kernel: bnxt_en 0000:c8:00.3 eth3: hwrm req_type 0x51 seq id 0x670d error 0x1
Nov 05 kernel: bnxt_re 0000:c8:00.0: Failed to remove GID: 0xfffffffb
Nov 05 kernel: other_driver 0000:c8:00.0 eth0: Error (timeout: 3000015)
Nov 05 kernel: unrelated kernel message'

# 1. every node clean -> ok, with the existing ping output intact
FIXTURE=()
run
chk "1 code" "$ERR_CODE" 0
chk "1 messages" "$(printf '%b' "$ERR_MSG")" "$(printf 'Ping 10.0.0.1 ... OK\nPing 10.0.0.2 ... OK\nPing 10.0.0.3 ... OK\n')"
chk "1 log" "$ERR_LOG" ""

# 2. count real timeout lines per device; ignore noise and clean nodes
FIXTURE=([c2]="$(printf '%s\n' "$timeout_eth0" "$timeout_eth0" "$timeout_eth0" "$timeout_eth2" "$noise")")
run
chk "2 code" "$ERR_CODE" 2
chk "2 eth0 count" "$(msg c2 | grep ' eth0:')" 'c2 0000:c8:00.0 eth0: 3 firmware command timeouts in the last 10 min'
chk "2 eth2 count" "$(msg c2 | grep ' eth2:')" 'c2 0000:c8:00.2 eth2: 1 firmware command timeouts in the last 10 min'
chk "2 device count" "$(msg c2 | wc -l | tr -d ' ')" 2
chk "2 c1 clean" "$(msg c1)" ""
chk "2 c3 clean" "$(msg c3)" ""
chk "2 log" "$ERR_LOG" 'journalctl -k -q --no-pager --since=-10min | grep bnxt_en | tail -n 100'

# 3. the command and journalctl invocation use the kernel's 10-minute window
chk "3 remote window" "$(grep -c -- '--since=-10min' "$LOG")" 3
chk "3 remote kernel" "$(grep -c -- 'journalctl -k ' "$LOG")" 3
chk "3 stdin detached" "$(grep -c ' n=1 ' "$LOG")" 3
chk "3 journal args" "$(grep -c -- '^-k -q --no-pager --since=-10min$' "$JOURNAL_LOG")" 3

# 4. only non-timeout errors -> ok
FIXTURE=([c1]="$noise" [c2]="$noise" [c3]="$noise")
run
chk "4 code" "$ERR_CODE" 0
chk "4 NIC messages" "$(printf '%b' "$ERR_MSG" | grep 'firmware command timeouts')" ""

# 5. ssh failure -> no NIC alarm
FIXTURE=([c2]="$timeout_eth0")
SSH_FAIL=([c2]=255)
run
chk "5 code" "$ERR_CODE" 0
chk "5 c2" "$(msg c2)" ""
SSH_FAIL=()

# 6. preserve ping failure code and log, but still include NIC timeouts elsewhere
PING_FAIL=10.0.0.1
run
chk "6 code" "$ERR_CODE" 1
chk "6 NIC" "$(msg c2)" 'c2 0000:c8:00.0 eth0: 1 firmware command timeouts in the last 10 min'
chk "6 log" "$ERR_LOG" /var/log/messages
PING_FAIL=""

# 7. a netdev not yet registered has a multiword interface name
FIXTURE=([c3]='Nov 05 kernel: bnxt_en 0000:c8:00.0 (unnamed net_device) (uninitialized): Error (timeout: 3000015) msg {0x23 0x66b8} len:0')
run
chk "7 code" "$ERR_CODE" 2
chk "7 iface" "$(msg c3)" 'c3 0000:c8:00.0 (unnamed net_device) (uninitialized): 1 firmware command timeouts in the last 10 min'

# 8. journalctl failure, including partial timeout output -> no NIC alarm
FIXTURE=([c2]="$timeout_eth0")
JOURNAL_FAIL=([c2]=1)
run
chk "8 code" "$ERR_CODE" 0
chk "8 c2" "$(msg c2)" ""
JOURNAL_FAIL=()

# 9. retain an existing diagnostic command when firmware is the first failure
ERR_CODE=0 ERR_MSG="" ERR_LOG='existing diagnostic'
health_link_check
chk "9 code" "$ERR_CODE" 2
chk "9 log" "$ERR_LOG" 'existing diagnostic'

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
