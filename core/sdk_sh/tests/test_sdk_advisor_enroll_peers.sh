#!/bin/bash
#
# Unit test for advisor_enroll_peers in ../modules/sdk_advisor.sh.
#
# Node tokens are single-use, so each peer must get its own. Non-control peers
# are skipped (advisor_enroll refuses them), and a peer's failure must reach
# the exit status. Peers get this node's egress proxy file, and every call to
# the Advisor goes through it.
#
# Self-contained: stubs remote_run and curl.
# Run:  bash test_sdk_advisor_enroll_peers.sh   (exit 0 = pass)
#
# shellcheck disable=SC2034  # read by the eval-ed functions
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_proxy _advisor_curl _advisor_node_token advisor_enroll_peers ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ADVISOR_IDENTITY_DIR="$WORK/id"
ADVISOR_AGENT_CERT="$ADVISOR_IDENTITY_DIR/agent.crt"
ADVISOR_AGENT_KEY="$ADVISOR_IDENTITY_DIR/agent.key"
ADVISOR_CONSOLE_CA="$WORK/console-ca.pub"
ADVISOR_PROXY_FILE="$ADVISOR_IDENTITY_DIR/proxy"
HEX_SDK=hex_sdk
HOSTNAME=n1
mkdir -p "$ADVISOR_IDENTITY_DIR"
: > "$ADVISOR_AGENT_CERT" ; : > "$ADVISOR_AGENT_KEY"
: > "$ADVISOR_IDENTITY_DIR/enrollment-ca.crt"
echo "advisor.example:8443" > "$ADVISOR_IDENTITY_DIR/server"

MINTED="$WORK/minted" DELIVERED="$WORK/delivered" ENROLLED="$WORK/enrolled"
CURLARGS="$WORK/curlargs" COPIED="$WORK/copied"
# Nodes that are control nodes, enrolled already, hold a proxy file, and whose
# enrolment fails.
CONTROL="n1 n2 n3" HAVE_ID="" HAVE_PROXY="" FAIL_ON=""

curl() {
    local n
    echo "$*" >> "$CURLARGS"
    n=$(( $(wc -l < "$MINTED") + 1 ))
    echo "tok$n" >> "$MINTED"
    printf '{"token":"tok%s"}' "$n"
}

# Mirrors the real remote_run: ssh's stderr is dropped.
remote_run() {
    local node=$1 ; shift
    case "$*" in
        "hex_sdk is_control_node") [[ " $CONTROL " == *" $node "* ]] ;;
        "stat $ADVISOR_PROXY_FILE") [[ " $HAVE_PROXY " == *" $node "* ]] ;;
        *"cat > $ADVISOR_PROXY_FILE") echo "$node $(cat)" >> "$COPIED" ;;
        "stat "*) [[ " $HAVE_ID " == *" $node "* ]] ;;
        *"cat > /run/advisor-peer/token") echo "$node $(cat)" >> "$DELIVERED" ;;
        *advisor_enroll_token*)
            echo "$node" >> "$ENROLLED"
            echo "fingerprint of $node"
            [[ " $FAIL_ON " == *" $node "* ]] && return 4
            return 0 ;;
        *) echo "unexpected remote_run $node $*" >&2 ; return 99 ;;
    esac
}

fail() { echo "FAIL: $1"; exit 1; }
reset() { : > "$MINTED" ; : > "$DELIVERED" ; : > "$ENROLLED" ; : > "$CURLARGS" ; : > "$COPIED" ; }

# ---- each peer gets its own token ----
reset
CUBE_NODE_LIST_HOSTNAMES=(n1 n2 n3)
out=$(advisor_enroll_peers 2>&1) || fail "fan-out failed: $out"
[ "$(wc -l < "$MINTED")" -eq 2 ] || fail "want 2 tokens minted, got: $(cat "$MINTED")"
[ "$(cat "$DELIVERED")" = "n2 tok1
n3 tok2" ] || fail "tokens not one per peer: $(cat "$DELIVERED")"

# ---- non-control peers are skipped, not failed ----
reset
CUBE_NODE_LIST_HOSTNAMES=(n1 n2 n3 c4)
out=$(advisor_enroll_peers 2>&1) || fail "a compute peer failed the fan-out: $out"
grep -q c4 "$ENROLLED" && fail "a non-control peer was enrolled"
echo "$out" | grep -q "not control nodes): c4" || fail "skipped peer not named: $out"

# ---- an enrolled peer is left alone ----
reset
HAVE_ID="n2"
advisor_enroll_peers >/dev/null 2>&1 || fail "fan-out failed"
[ "$(cat "$ENROLLED")" = "n3" ] || fail "want only n3 enrolled, got: $(cat "$ENROLLED")"
HAVE_ID=""

# ---- a peer's failure reaches the exit status ----
reset
FAIL_ON="n2"
advisor_enroll_peers >/dev/null 2>&1 && fail "a failed peer still returned 0"
[ "$(cat "$ENROLLED")" = "n2
n3" ] || fail "a failed peer stopped the others: $(cat "$ENROLLED")"

FAIL_ON=""

# ---- no proxy file: curl as before, nothing copied ----
reset
CUBE_NODE_LIST_HOSTNAMES=(n1 n2 n3)
advisor_enroll_peers >/dev/null 2>&1 || fail "fan-out failed"
grep -q -- --proxy "$CURLARGS" && fail "curl got a proxy with no proxy file"
[ -s "$COPIED" ] && fail "a proxy file was copied that does not exist: $(cat "$COPIED")"

# ---- proxy file: the Advisor calls use it and peers without one get it ----
reset
echo " proxy.example:3128 " > "$ADVISOR_PROXY_FILE"
HAVE_PROXY="n3"
advisor_enroll_peers >/dev/null 2>&1 || fail "fan-out through a proxy failed"
[ "$(grep -c -- '--proxy http://proxy.example:3128 ' "$CURLARGS")" -eq 2 ] ||
    fail "node-token calls not sent through the proxy: $(cat "$CURLARGS")"
[ "$(cat "$COPIED")" = "n2  proxy.example:3128 " ] ||
    fail "want the proxy file copied to n2 only, got: $(cat "$COPIED")"
HAVE_PROXY=""

# ---- what the proxy file may hold, as the agent reads it ----
echo "https://p.example:8443" > "$ADVISOR_PROXY_FILE"
[ "$(_advisor_proxy)" = "https://p.example:8443" ] || fail "https proxy not read"
printf '\n' > "$ADVISOR_PROXY_FILE"
[ -z "$(_advisor_proxy)" ] || fail "an empty file named a proxy"
echo "ftp://p.example:21" > "$ADVISOR_PROXY_FILE"
out=$(_advisor_proxy 2>&1 >/dev/null)
[ -z "$(_advisor_proxy 2>/dev/null)" ] || fail "an ftp proxy was used"
echo "$out" | grep -q "ignoring" || fail "a bad proxy file was not reported: $out"
rm -f "$ADVISOR_PROXY_FILE"

exit 0
