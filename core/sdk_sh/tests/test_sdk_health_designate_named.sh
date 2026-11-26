#!/bin/bash
#
# Unit test for _health_named_rndc(), health_designate_check() and
# _health_designate_auto_repair() in ../modules/sdk_health.sh, covering #2271:
# a named that ran out of sockets kept running, refused rndc and answered SERVFAIL
# to everything it had to forward, and the check passed because it only asked
# whether the unit was running. Also covers #2394: a named that answers rndc but
# cannot reach its forwarders, found by a lookup at named compared with one at the
# node's upstream nameservers (health_named_forward_probe, _health_named_forward).
#
# Self-contained: extracts the functions, stubs the cluster calls, and puts a fake
# rndc, dig and ssh on PATH (run through the real timeout), so it needs no cluster.
#
# Sections 20 and 21 are negative controls against the check before each fix
# (437a9055, ac8c4aa5). Each is skipped when its git object is not available.
#
#   Run: bash test_sdk_health_designate_named.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_health.sh"

extract() { awk -v fn="^$1\\\\(\\\\)" '$0 ~ fn {f=1} f{print} f&&/^}/{exit}' "$2"; }

load() { # load <file> <function>...
    local src=$1 fn
    shift
    for fn in "$@"; do
        eval "$(extract "$fn" "$src")"
        [ "$(type -t "$fn")" = function ] || { echo "FAIL: $fn not extracted from $src"; exit 1; }
    done
}
load "$SRC" _health_named_rndc _health_named_forward health_designate_check _health_designate_auto_repair

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# #2394: the forward probe runs on each control over ssh. A fake ssh on PATH (so the real timeout
# can run it) runs the probe from this file, with /etc/resolv.conf pointed at $T/resolv.<node> and
# `hostname -I` at the node's management address; $T/ssh.<node> = down makes the ssh fail.
{ extract _health_dig_status "$SRC" ; extract health_named_forward_probe "$SRC" ; } \
    | sed "s|/etc/resolv.conf|$T/resolv.\$PROBE_NODE|" > "$T/probe.sh"
grep -q "^health_named_forward_probe()" "$T/probe.sh" || { echo "FAIL: probe not extracted"; exit 1; }

# fake rndc: answers per server address from $T/rndc.<addr> (ok | reset | badkey | hang) and logs its argv
mkdir -p "$T/bin"
cat > "$T/bin/rndc" <<'EOF'
#!/bin/bash
echo "$*" >> "$RNDC_T/rndc.log"
srv=
while [ $# -gt 0 ] ; do [ "$1" = "-s" ] && srv=$2 ; shift ; done
case "$(cat "$RNDC_T/rndc.$srv" 2>/dev/null || echo refused)" in
    ok)    printf 'version: BIND 9.20.30\nserver is up and running\n' ;;
    reset) echo "rndc: recv failed: connection reset" >&2 ; exit 1 ;;
    badkey) printf '%s\n' 'rndc: connection to remote host closed.' '* This may indicate that the' \
                '* remote server is using an older' '* or the key is invalid.' >&2 ; exit 1 ;;
    hang)  sleep 5 ;;
    *)     echo "rndc: connect failed: $srv#953: connection refused" >&2 ; exit 1 ;;
esac
EOF
chmod +x "$T/bin/rndc"

# fake dig: answers per server from $T/dig.<server>, one line per lookup, the last line repeats
# (NOERROR | NXDOMAIN | SERVFAIL | timeout; default NOERROR), in dig +noall +comments' shape,
# and logs "<server> <name>"
cat > "$T/bin/dig" <<'EOF'
#!/bin/bash
srv= name=
for a in "$@" ; do case "$a" in @*) srv=${a#@} ;; +*|A) ;; *) name=$a ;; esac ; done
echo "$srv $name" >> "$RNDC_T/dig.log"
f=$RNDC_T/dig.$srv st=NOERROR
if [ -s "$f" ] ; then
    st=$(head -n 1 "$f")
    [ "$(wc -l < "$f")" -gt 1 ] && sed -i.bak '1d' "$f"
fi
if [ "$st" = timeout ] ; then
    echo ";; communications error to $srv#53: timed out"
    exit 9
fi
echo ";; Got answer:"
echo ";; ->>HEADER<<- opcode: QUERY, status: $st, id: 4242"
echo ";; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1"
EOF
cat > "$T/bin/ssh" <<'EOF'
#!/bin/bash
echo "ssh $*" >> "$RNDC_T/ssh.log"
node=
while [ $# -gt 0 ] ; do case "$1" in -n) ;; root@*) node=${1#root@} ; shift ; break ;; esac ; shift ; done
case "$(cat "$RNDC_T/ssh.$node" 2>/dev/null)" in
    down) exit 255 ;;
    old)  echo "$2: unknown command" ; exit 1 ;;
esac
shift    # $HEX_SDK
PROBE_NODE=$node
hostname() { cat "$RNDC_T/addr.$PROBE_NODE" ; }
. "$RNDC_T/probe.sh"
"$@"
EOF
chmod +x "$T/bin/dig" "$T/bin/ssh"
export RNDC_T=$T PATH="$T/bin:$PATH"
HEX_SDK=hex_sdk
shared_id() { echo 10.9.9.9 ; }
timeout() { echo "timeout $1 $2" >> "$T/timeout.log" ; command timeout "$@" ; }

SRVSTO=1
ERR_LOGSIZE=200
stale_api_check_repair() { :; }
API_OK=1
_health_api_reachable() { [ "$API_OK" = "1" ]; }
SVC_LIST=""
fake_openstack() { [ -n "$SVC_LIST" ] && printf '%b' "$SVC_LIST"; return 0; }
OPENSTACK=fake_openstack

# STOPPED holds "<node>:<service>" entries that is_remote_running reports down.
STOPPED=""
is_remote_running() { case " $STOPPED " in *" $1:$2 "*) return 1 ;; esac; return 0; }
RESTARTED="" RAN=""
remote_systemd_restart() { RESTARTED+="$1:$2 "; }
remote_run() { RAN+="$1:${*:2} "; }
cubectl() { echo "$CUBE_NODE_CONTROL_JSON"; }
_health_fail_log() { SEEN_CODE=$ERR_CODE; SEEN_LOG=$ERR_LOG; SEEN_MSG=$ERR_MSG; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

controls() { # controls <host>=<mgmt ip>...: sets the hostnames, the node JSON and every named to "ok"
    local h j="" n=""
    rm -f "$T"/rndc.* "$T"/dig.* "$T"/resolv.* "$T"/ssh.* "$T"/addr.*
    CUBE_NODE_CONTROL_HOSTNAMES=()
    for h in "$@" ; do
        CUBE_NODE_CONTROL_HOSTNAMES+=("${h%%=*}")
        j+="${j:+,}{\"hostname\":\"${h%%=*}\",\"role\":\"control-converged\",\"ip\":{\"management\":\"${h#*=}\"}}"
        n+="${h%%=*} api up\n${h%%=*} central up\n${h%%=*} worker up\n${h%%=*} producer up\n${h%%=*} mdns up\n"
        echo ok > "$T/rndc.${h#*=}"
        echo "${h#*=}" > "$T/addr.${h%%=*}"
    done
    CUBE_NODE_CONTROL_JSON="[$j]"
    SVC_LIST="$n"
}
named_rndc() { echo "$2" > "$T/rndc.$1"; }   # named_rndc <mgmt ip> ok|reset|hang

check() { # check <stopped entries...>: runs the check, then the repair it gates
    STOPPED="$*" ERR_CODE=0 ERR_LOG="" ERR_MSG="" SEEN_CODE="" SEEN_LOG="" SEEN_MSG="" RESTARTED="" RAN=""
    rm -f "$T/rndc.log" "$T/dig.log" "$T/ssh.log" "$T/timeout.log"
    touch "$T/dig.log" "$T/ssh.log" "$T/timeout.log"
    health_designate_check
    [ "$SEEN_CODE" = "0" ] || _health_designate_auto_repair
}
msg_has() { echo -e "$SEEN_MSG" | grep -cF -- "$1"; }

# ---- 1cc ----
controls cc1=10.1.0.1

# 1. healthy: rndc goes to the management address with designate's key, nothing restarts
check
ck "$SEEN_CODE" 0 "1cc healthy: ERR_CODE"
ck "$(cat "$T/rndc.log")" "-k /etc/designate/rndc.key -s 10.1.0.1 status" "1cc healthy: rndc to the mgmt address, designate's key"
ck "$RESTARTED" "" "1cc healthy: no restart"

# 2. named running but refusing rndc (#2271)
named_rndc 10.1.0.1 reset
check
ck "$SEEN_CODE" 14 "1cc rndc reset: ERR_CODE 14"
ck "$SEEN_LOG" "journalctl -n 200 -u named" "1cc rndc reset: ERR_LOG is named's journal"
ck "$(msg_has 'cc1 named refuses rndc: rndc: recv failed: connection reset')" 1 "1cc rndc reset: ERR_MSG names the node and rndc's error"
ck "$RAN" "cc1:timeout 1 /usr/local/bin/cubectl node rsync -r control /etc/designate/rndc.key " "1cc rndc reset: repair re-syncs the key"
ck "$RESTARTED" "cc1:named " "1cc rndc reset: repair restarts named"

# 2b. a key mismatch: rndc explains over several lines, the detail keeps the first
named_rndc 10.1.0.1 badkey
check
ck "$SEEN_CODE" 14 "1cc bad key: ERR_CODE 14"
ck "$(msg_has 'cc1 named refuses rndc: rndc: connection to remote host closed.')" 1 "1cc bad key: ERR_MSG keeps rndc's first line"
ck "$(msg_has 'key is invalid')" 0 "1cc bad key: and not the explanation"
ck "$RESTARTED" "cc1:named " "1cc bad key: repair restarts named"

# 3. rndc gets no answer: bounded by SRVSTO
named_rndc 10.1.0.1 hang
s=$(date +%s)
check
ck "$SEEN_CODE" 14 "1cc rndc hang: ERR_CODE 14"
ck "$(msg_has 'cc1 named refuses rndc: no answer in 1s')" 1 "1cc rndc hang: ERR_MSG says it timed out"
ck "$(( $(date +%s) - s <= 4 ))" 1 "1cc rndc hang: check and repair probes each end at SRVSTO"

# 4. named stopped: still code 8, and rndc is not asked
named_rndc 10.1.0.1 ok
check cc1:named
ck "$SEEN_CODE" 8 "1cc named stopped: ERR_CODE 8"
ck "$(msg_has 'refuses rndc')" 0 "1cc named stopped: no rndc message"
ck "$RESTARTED" "cc1:named " "1cc named stopped: repair restarts named once"

# 5. a designate service down outranks named, as before
check cc1:designate-worker
ck "$SEEN_CODE" 5 "1cc worker stopped: ERR_CODE 5"

# ---- 3cc ----
controls cc1=10.0.0.1 cc2=10.0.0.2 cc3=10.0.0.3

# 6. healthy: every control's named is asked once
check
ck "$SEEN_CODE" 0 "3cc healthy: ERR_CODE"
ck "$(cut -d' ' -f4 "$T/rndc.log" | paste -sd' ')" "10.0.0.1 10.0.0.2 10.0.0.3" "3cc healthy: one rndc per control"

# 7. only cc2's named refuses rndc: named and restarted there only
named_rndc 10.0.0.2 reset
check
ck "$SEEN_CODE" 14 "3cc cc2 rndc reset: ERR_CODE 14"
ck "$(msg_has 'refuses rndc')" 1 "3cc cc2 rndc reset: one rndc message"
ck "$(msg_has 'cc2 named refuses rndc')" 1 "3cc cc2 rndc reset: the message names cc2"
ck "$RESTARTED" "cc2:named " "3cc cc2 rndc reset: repair restarts cc2's named only"

# 8. a hostname missing from the node list: falls back to the name itself
CUBE_NODE_CONTROL_JSON="[]"
out=$(_health_named_rndc cc9); rc=$?
ck "$rc" 1 "unknown host: probe fails"
ck "$(tail -1 "$T/rndc.log" | cut -d' ' -f4)" "cc9" "unknown host: rndc is pointed at the name"

# ---- #2394: named runs and answers rndc, but cannot resolve a name it has to forward ----
dig_as() { printf '%s\n' "${@:2}" > "$T/dig.$1"; }   # dig_as <server> <status per lookup>...
resolv() { local h=$1 ; shift ; printf 'nameserver %s\n' "$@" > "$T/resolv.$h"; }
refs() { grep -vc '^10\.1\.0\.1 \|^10\.0\.0\.[123] ' "$T/dig.log"; }   # lookups not sent to a named

controls cc1=10.1.0.1
resolv cc1 8.8.8.8 10.1.0.1

# 9. named answers NOERROR: one lookup, at the management address, of a fresh example.com name
check
ck "$SEEN_CODE" 0 "fwd ok: ERR_CODE"
ck "$(wc -l < "$T/dig.log" | tr -d ' ')" 1 "fwd ok: one lookup"
ck "$(grep -c '^10\.1\.0\.1 cos-health-.*-1\.example\.com$' "$T/dig.log")" 1 "fwd ok: asked named at the mgmt address"
ck "$(grep -c "root@cc1 hex_sdk health_named_forward_probe 10.1.0.1 10.1.0.1 10.9.9.9" "$T/ssh.log")" 1 "fwd ok: probe on cc1, controls and shared id excluded"
ck "$(grep -c "^timeout 11 ssh$" "$T/timeout.log")" 1 "fwd ok: ssh bounded at SRVSTO (1) + 10"
ck "$(grep -c 'ssh -n root@cc1' "$T/ssh.log")" 1 "fwd ok: ssh -n keeps stdin"

# 10. NXDOMAIN is an answer too
dig_as 10.1.0.1 NXDOMAIN
check
ck "$SEEN_CODE" 0 "fwd nxdomain: ERR_CODE"
ck "$(refs)" 0 "fwd nxdomain: no reference lookup"

# 11. the #2394 case: named times out, an upstream in resolv.conf answers -> 15, naming the node
dig_as 10.1.0.1 timeout
dig_as 8.8.8.8 NXDOMAIN
check
ck "$SEEN_CODE" 15 "fwd broken: ERR_CODE 15"
ck "$(msg_has 'cc1 named cannot resolve outside names: timeout from named, NXDOMAIN from 8.8.8.8')" 1 "fwd broken: ERR_MSG names the node, both answers"
ck "$SEEN_LOG" "journalctl -n 200 -u named" "fwd broken: ERR_LOG is named's journal"
ck "$(grep -c '^10\.1\.0\.1 ' "$T/dig.log")" 2 "fwd broken: named asked twice"
ck "$(grep -c '^8\.8\.8\.8 cos-health-.*-r\.example\.com$' "$T/dig.log")" 1 "fwd broken: one reference lookup"
ck "$(cut -d' ' -f2 "$T/dig.log" | sort -u | wc -l | tr -d ' ')" 3 "fwd broken: a different name each lookup"
ck "$RESTARTED$RAN" "" "fwd broken: repair restarts nothing"

# 12. SERVFAIL from named and from the upstream: upstream down anyway, not named's fault
dig_as 10.1.0.1 SERVFAIL
dig_as 8.8.8.8 SERVFAIL
check
ck "$SEEN_CODE" 0 "upstream down too: ERR_CODE"

# 13. no forwarders: resolv.conf holds only the cluster's own named -> nothing to compare, ok
resolv cc1 127.0.0.1 10.1.0.1 10.9.9.9
dig_as 10.1.0.1 timeout
check
ck "$SEEN_CODE" 0 "no upstream: ERR_CODE"
ck "$(refs)" 0 "no upstream: no reference lookup"
ck "$(grep -c '^10\.9\.9\.9 \|^127\.0\.0\.1 ' "$T/dig.log")" 0 "no upstream: shared id and loopback not asked"

# 14. named misses once, then answers
resolv cc1 8.8.8.8
dig_as 10.1.0.1 timeout NOERROR
check
ck "$SEEN_CODE" 0 "fwd flaky: ERR_CODE"
ck "$(refs)" 0 "fwd flaky: no reference lookup"

# 15. the first upstream does not answer, the second does; and at most three upstreams are asked
resolv cc1 192.0.2.10 8.8.4.4
dig_as 10.1.0.1 SERVFAIL
dig_as 192.0.2.10 timeout
dig_as 8.8.4.4 NOERROR
check
ck "$SEEN_CODE" 15 "second upstream: ERR_CODE 15"
ck "$(msg_has 'cc1 named cannot resolve outside names: SERVFAIL from named, NOERROR from 8.8.4.4')" 1 "second upstream: ERR_MSG names it"
resolv cc1 192.0.2.11 192.0.2.12 192.0.2.13 192.0.2.14
for a in 11 12 13 14 ; do dig_as 192.0.2.$a timeout ; done
check
ck "$SEEN_CODE" 0 "four dead upstreams: ERR_CODE"
ck "$(refs)" 3 "four dead upstreams: three asked"

# 16. the probe cannot run (ssh fails, or the node's hex_sdk lacks it): not a fault
resolv cc1 8.8.8.8
dig_as 8.8.8.8 NOERROR
echo down > "$T/ssh.cc1"
check
ck "$SEEN_CODE" 0 "ssh down: ERR_CODE"
echo old > "$T/ssh.cc1"
check
ck "$SEEN_CODE" 0 "hex_sdk without the probe: ERR_CODE"
rm -f "$T/ssh.cc1"

# 17. rndc refused still wins, and the probe is not run
named_rndc 10.1.0.1 reset
check
ck "$SEEN_CODE" 14 "rndc refused: ERR_CODE 14"
ck "$(wc -l < "$T/ssh.log" | tr -d ' ')" 0 "rndc refused: no forward probe"

# 18. 3cc: only cc2's named cannot forward
controls cc1=10.0.0.1 cc2=10.0.0.2 cc3=10.0.0.3
for h in cc1 cc2 cc3 ; do resolv $h 8.8.8.8 10.9.9.9 ; done
dig_as 10.0.0.2 timeout
check
ck "$SEEN_CODE" 15 "3cc cc2 fwd broken: ERR_CODE 15"
ck "$(msg_has 'named cannot resolve outside names')" 1 "3cc cc2 fwd broken: one message"
ck "$(msg_has 'cc2 named cannot resolve outside names')" 1 "3cc cc2 fwd broken: the message names cc2"
ck "$(grep -c 'probe 10.0.0.2 10.0.0.1 10.0.0.2 10.0.0.3 10.9.9.9$' "$T/ssh.log")" 1 "3cc: every control and the shared id excluded"

# ---- 19. the error code has a description ----
ck "$(PROG=test; . "$DIR/../modules/errcodes"; echo "${ERR_CODE[designate,14]}")" "named refuses rndc" "errcodes: designate 14"
ck "$(PROG=test; . "$DIR/../modules/errcodes"; echo "${ERR_CODE[designate,15]}")" "named cannot resolve outside names" "errcodes: designate 15"

# ---- 20. negative control: the check before the fix passes a named that refuses rndc ----
BASE_SRC=$T/base.sh
BASE_REF=437a9055
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" health_designate_check _health_designate_auto_repair
    controls cc1=10.1.0.1
    named_rndc 10.1.0.1 reset
    check
    ck "$SEEN_CODE" 0 "negative control: unfixed check passes a named that refuses rndc"
    ck "$RESTARTED" "" "negative control: unfixed repair restarts nothing"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

# ---- 21. negative control: develop before #2394 passes a named that cannot forward ----
BASE_REF=ac8c4aa5
if git -C "$DIR" show "$BASE_REF:core/sdk_sh/modules/sdk_health.sh" > "$BASE_SRC" 2>/dev/null; then
    load "$BASE_SRC" _health_named_rndc health_designate_check
    controls cc1=10.1.0.1
    resolv cc1 8.8.8.8 10.1.0.1
    dig_as 10.1.0.1 timeout
    dig_as 8.8.8.8 NXDOMAIN
    check
    ck "$SEEN_CODE" 0 "negative control: develop's check passes a named that cannot forward"
else
    echo "SKIP: negative control needs git object $BASE_REF"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
