#!/bin/bash
#
# Unit test for health_dns_check in ../modules/sdk_health.sh.
#
# The check asks each node, over one ssh -n that it bounds at SRVSTO + 5 s, to send a reverse
# lookup of a random 10.x address to each nameserver in the node's /etc/resolv.conf, 1 s per try,
# in up to 4 rounds with a new name each try, and to stop at the first reply that carries a
# status. Per node it reports "took N sec", "no nameserver answered (nameservers: ...)",
# "dns lookup failed (rc N)" or "could not be run"; all but the first set ERR_CODE 1. It
# replaced #1595's bounded `arp -a` timing in 3e986171.
#
# Any status counts as an answer, SERVFAIL included: the check measures whether a node's own
# lookups come back. Whether the cluster's named resolves is health_designate_check's (#2271).
#
# Self-contained: extracts only the function and stubs timeout, ssh and _health_fail_log, so it
# needs no cluster. Sections 1-5 feed the check canned replies from the node; section 6 runs the
# check's own remote command against a fixture resolv.conf and a fake dig.
#   Run: bash test_health_dns_check.sh   (exit 0 = pass)
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
# REPLY[node] is what the remote command prints ("<rc> <ms> <nameservers>"); an unset node is
# unreachable. With REAL=1, ssh runs the remote command itself instead, with /etc/resolv.conf
# pointed at $T/resolv.conf and a fake dig on PATH. Every timeout and ssh call is logged to $LOG.
declare -A REPLY
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
LOG=$T/log
SRVSTO=10
REAL=0

timeout() { echo "timeout $1" >> "$LOG" ; shift ; "$@" ; }
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
    if [ "$REAL" = 1 ] ; then
        PATH="$T/bin:$PATH" bash -c "${cmd//\/etc\/resolv.conf/$T/resolv.conf}"
        return
    fi
    [ -n "${REPLY[$node]+set}" ] || return 255
    echo "${REPLY[$node]}"
}
_health_fail_log() { : ; }

run() { ERR_CODE=0 ; ERR_MSG="" ; : > "$LOG" ; : > "$T/dig.log" ; health_dns_check ; }
msg() { echo -e "$ERR_MSG" | grep "^$1 " ; }

CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3)

# 1. every node answers fast -> ok, a duration per node
REPLY=([c1]="0 12 10.0.0.53" [c2]="0 1503 10.0.0.53" [c3]="0 0 10.0.0.53")
run
chk "1 code" "$ERR_CODE" 0
chk "1 c1" "$(msg c1)" "c1 DNS lookup took 0.012 sec"
chk "1 c2" "$(msg c2)" "c2 DNS lookup took 1.503 sec"
chk "1 c3" "$(msg c3)" "c3 DNS lookup took 0.000 sec"

# 2. one bound per node, SRVSTO + 5 s around the ssh, and the caller's stdin stays off the connection
chk "2 ssh bound" "$(grep -c "^timeout $((SRVSTO + 5))$" "$LOG")" 3
chk "2 -n" "$(grep -c ' n=1 ' "$LOG")" 3
chk "2 dig bounded per try" "$(grep -c 'dig +time=1 +tries=1 ' "$LOG")" 3

# 3. one node's nameservers all fail to answer -> code 1, and only that node says so, naming them
REPLY=([c1]="0 12 10.0.0.53" [c2]="124 8004 8.8.8.8,10.0.0.53" [c3]="0 9 10.0.0.53")
run
chk "3 code" "$ERR_CODE" 1
chk "3 c2" "$(msg c2)" "c2 no nameserver answered (nameservers: 8.8.8.8,10.0.0.53)"
chk "3 c3 still ok" "$(msg c3)" "c3 DNS lookup took 0.009 sec"

# 4. a node that cannot be reached -> code 1, not a blank "took  sec"
REPLY=([c1]="0 12 10.0.0.53" [c3]="0 9 10.0.0.53")
run
chk "4 code" "$ERR_CODE" 1
chk "4 c2" "$(msg c2)" "c2 dns lookup could not be run"

# 5. any other status -> code 1 with it; a half reply (no duration) is not mistaken for success
REPLY=([c1]="1 3 10.0.0.53" [c2]="0 5 10.0.0.53" [c3]="0 5 10.0.0.53")
run
chk "5 code" "$ERR_CODE" 1
chk "5 c1" "$(msg c1)" "c1 dns lookup failed (rc 1)"
REPLY=([c1]="0" [c2]="0 5" [c3]="0 5")
run
chk "5b code" "$ERR_CODE" 1
chk "5b c1" "$(msg c1)" "c1 dns lookup could not be run"

# ---- 6. the remote command itself ------------------------------------------
# The fake dig answers per server from ANSWER[server]: a status (NOERROR, NXDOMAIN, SERVFAIL...)
# or "timeout", printed the way `dig +noall +comments` does. It logs "<server> <name>" per call.
mkdir -p "$T/bin"
cat > "$T/bin/dig" <<'EOF'
#!/bin/bash
srv= name= prev=
for a in "$@" ; do
    case "$a" in @*) srv=${a#@} ;; esac
    [ "$prev" = "-x" ] && name=$a
    prev=$a
done
echo "$srv $name" >> "$DIG_T/dig.log"
ans=$(grep "^$srv " "$DIG_T/answers" | cut -d' ' -f2)
if [ "${ans:-timeout}" = timeout ] ; then
    echo ";; communications error to $srv#53: timed out"
    echo ";; no servers could be reached"
    exit 9
fi
echo ";; Got answer:"
echo ";; ->>HEADER<<- opcode: QUERY, status: $ans, id: 4242"
EOF
chmod +x "$T/bin/dig"
export DIG_T=$T
REAL=1
CUBE_NODE_LIST_HOSTNAMES=(c1)
resolv() { printf 'nameserver %s\n' "$@" > "$T/resolv.conf" ; echo "search cube.local" >> "$T/resolv.conf" ; }
answers() { printf '%s\n' "$@" > "$T/answers" ; }   # answers "<server> <status|timeout>"...
digs() { cut -d' ' -f1 "$T/dig.log" | paste -sd' ' - ; }
took() { msg c1 | grep -c '^c1 DNS lookup took [0-9]*\.[0-9][0-9][0-9] sec$' ; }

# 6a. the first nameserver answers: one reverse lookup of a 10.x name, sent to it alone
resolv 8.8.8.8 10.0.0.53 ; answers "8.8.8.8 NXDOMAIN" "10.0.0.53 NXDOMAIN"
run
chk "6a code" "$ERR_CODE" 0
chk "6a took" "$(took)" 1
chk "6a asked" "$(digs)" "8.8.8.8"
chk "6a name" "$(cut -d' ' -f2 "$T/dig.log" | grep -cE '^10\.[0-9]+\.[0-9]+\.[0-9]+$')" 1

# 6b. the first nameserver does not answer: the next one is asked in the same round
answers "8.8.8.8 timeout" "10.0.0.53 NOERROR"
run
chk "6b code" "$ERR_CODE" 0
chk "6b asked" "$(digs)" "8.8.8.8 10.0.0.53"

# 6c. no nameserver answers: 4 rounds over both, a new name each try, then code 1 naming them
answers "8.8.8.8 timeout" "10.0.0.53 timeout"
run
chk "6c code" "$ERR_CODE" 1
chk "6c c1" "$(msg c1)" "c1 no nameserver answered (nameservers: 8.8.8.8,10.0.0.53)"
chk "6c asked" "$(digs)" "8.8.8.8 10.0.0.53 8.8.8.8 10.0.0.53 8.8.8.8 10.0.0.53 8.8.8.8 10.0.0.53"
chk "6c names" "$(cut -d' ' -f2 "$T/dig.log" | sort -u | wc -l)" 8

# 6d. SERVFAIL is an answer: the node's lookups came back (#2271 leaves named to health_designate_check)
answers "8.8.8.8 SERVFAIL" "10.0.0.53 NXDOMAIN"
run
chk "6d code" "$ERR_CODE" 0
chk "6d took" "$(took)" 1
chk "6d asked" "$(digs)" "8.8.8.8"

# 6e. resolv.conf names no nameserver: nothing is asked, and the node reads ok
printf 'search cube.local\n' > "$T/resolv.conf"
run
chk "6e code" "$ERR_CODE" 0
chk "6e took" "$(took)" 1
chk "6e asked" "$(digs)" ""

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_dns_check" ; exit 0 ; } || exit 1
