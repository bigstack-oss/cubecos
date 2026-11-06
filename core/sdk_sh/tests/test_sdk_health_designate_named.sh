#!/bin/bash
#
# Unit test for _health_named_rndc(), health_designate_check() and
# _health_designate_auto_repair() in ../modules/sdk_health.sh, covering #2271:
# a named that ran out of sockets kept running, refused rndc and answered SERVFAIL
# to everything it had to forward, and the check passed because it only asked
# whether the unit was running.
#
# Self-contained: extracts the three functions, stubs the cluster calls, and puts
# a fake rndc on PATH (run through the real timeout), so it needs no cluster.
#
# The last section is a negative control against the check at 437a9055, before
# the fix. It is skipped when that git object is not available.
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
load "$SRC" _health_named_rndc health_designate_check _health_designate_auto_repair

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

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
export RNDC_T=$T PATH="$T/bin:$PATH"

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
    rm -f "$T"/rndc.*
    CUBE_NODE_CONTROL_HOSTNAMES=()
    for h in "$@" ; do
        CUBE_NODE_CONTROL_HOSTNAMES+=("${h%%=*}")
        j+="${j:+,}{\"hostname\":\"${h%%=*}\",\"role\":\"control-converged\",\"ip\":{\"management\":\"${h#*=}\"}}"
        n+="${h%%=*} api up\n${h%%=*} central up\n${h%%=*} worker up\n${h%%=*} producer up\n${h%%=*} mdns up\n"
        echo ok > "$T/rndc.${h#*=}"
    done
    CUBE_NODE_CONTROL_JSON="[$j]"
    SVC_LIST="$n"
}
named_rndc() { echo "$2" > "$T/rndc.$1"; }   # named_rndc <mgmt ip> ok|reset|hang

check() { # check <stopped entries...>: runs the check, then the repair it gates
    STOPPED="$*" ERR_CODE=0 ERR_LOG="" ERR_MSG="" SEEN_CODE="" SEEN_LOG="" SEEN_MSG="" RESTARTED="" RAN=""
    rm -f "$T/rndc.log"
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

# ---- 9. the error code has a description ----
ck "$(PROG=test; . "$DIR/../modules/errcodes"; echo "${ERR_CODE[designate,14]}")" "named refuses rndc" "errcodes: designate 14"

# ---- 10. negative control: the check before the fix passes a named that refuses rndc ----
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

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
