#!/bin/bash
#
# Unit test for health_dns_check in ../modules/sdk_health.sh (cubecos#1595).
#
# The check times `arp -a`, which reverse-resolves every ARP neighbour, on each node. It
# used to bound only the local ssh, so on a mux connection the remote arp ran to completion
# (~18 min on QA 10.32.36.10, no PTR for its subnets) and the master held the caller's
# stdio until then. Its status came from `$(... | grep real | awk ...)`, which takes awk's
# status, so a timed-out lookup was reported as "took  sec" and the check never failed.
#
# The check must run the timeout on the remote side, keep the caller's stdin off the
# connection (-n), and report a timed-out, failed or unreachable lookup as ERR_CODE 1 for
# that node alone, naming the nameservers on a timeout, while a healthy node still reads
# "took N sec".
#
# Self-contained: extracts only the function and stubs timeout, ssh and _health_fail_log,
# so it needs no cluster.  Run: bash test_health_dns_check.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

fn="$(awk '/^health_dns_check\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: health_dns_check not extracted"; exit 1; }
eval "$fn"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# REPLY[node] is what the remote command prints ("<rc> <ms>"); an unset node is
# unreachable. Every ssh invocation is logged to $LOG.
declare -A REPLY
LOG=$(mktemp)
SRVSTO=10

timeout() { shift ; "$@" ; }
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
    [ -n "${REPLY[$node]+set}" ] || return 255
    echo "${REPLY[$node]}"
}
_health_fail_log() { : ; }

run() { ERR_CODE=0 ; ERR_MSG="" ; : > "$LOG" ; health_dns_check ; }
msg() { echo -e "$ERR_MSG" | grep "^$1 " ; }

CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)

# 1. every node answers fast -> ok, a duration per node
REPLY=([c1]="0 12" [c2]="0 1503" [c3]="0 0")
run
chk "1 code" "$ERR_CODE" 0
chk "1 c1" "$(msg c1)" "c1 DNS lookup took 0.012 sec"
chk "1 c2" "$(msg c2)" "c2 DNS lookup took 1.503 sec"
chk "1 c3" "$(msg c3)" "c3 DNS lookup took 0.000 sec"

# 2. the bound is on the remote side, and the caller's stdin stays off the connection
chk "2 remote timeout" "$(grep -c "timeout $SRVSTO arp -a" "$LOG")" 3
chk "2 -n" "$(grep -c ' n=1 ' "$LOG")" 3

# 3. one node's reverse DNS times out -> code 1, and only that node says so
REPLY=([c1]="0 12 10.0.0.53" [c2]="124 10004 8.8.8.8,10.32.36.10" [c3]="0 9 10.0.0.53")
run
chk "3 code" "$ERR_CODE" 1
chk "3 c2" "$(msg c2)" "c2 dns lookup timed out after 10s (nameservers: 8.8.8.8,10.32.36.10)"
chk "3 c3 still ok" "$(msg c3)" "c3 DNS lookup took 0.009 sec"

# 3b. no nameserver configured at all -> said so
REPLY=([c1]="124 10002" [c2]="0 5" [c3]="0 5")
run
chk "3b c1" "$(msg c1)" "c1 dns lookup timed out after 10s (nameservers: none)"

# 4. a node that cannot be reached -> code 1, not a blank "took  sec"
REPLY=([c1]="0 12" [c3]="0 9")
run
chk "4 code" "$ERR_CODE" 1
chk "4 c2" "$(msg c2)" "c2 dns lookup could not be run"

# 5. arp -a itself fails -> code 1 with its status
REPLY=([c1]="1 3" [c2]="0 5" [c3]="0 5")
run
chk "5 code" "$ERR_CODE" 1
chk "5 c1" "$(msg c1)" "c1 dns lookup failed (arp -a rc 1)"

# 6. a half reply (no duration) is not mistaken for success
REPLY=([c1]="0" [c2]="0 5" [c3]="0 5")
run
chk "6 code" "$ERR_CODE" 1
chk "6 c1" "$(msg c1)" "c1 dns lookup could not be run"

rm -f "$LOG"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_dns_check" ; exit 0 ; } || exit 1
