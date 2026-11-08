#!/bin/bash
#
# Unit test for advisor_enroll_peers in ../modules/sdk_advisor.sh.
#
# Node tokens are single-use, so each peer must get its own. Non-control peers
# are skipped (advisor_enroll refuses them), and a peer's failure must reach
# the exit status.
#
# Self-contained: stubs remote_run and curl.
# Run:  bash test_sdk_advisor_enroll_peers.sh   (exit 0 = pass)
#
# shellcheck disable=SC2034  # read by the eval-ed functions
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_node_token advisor_enroll_peers ; do
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
HEX_SDK=hex_sdk
HOSTNAME=n1
mkdir -p "$ADVISOR_IDENTITY_DIR"
: > "$ADVISOR_AGENT_CERT" ; : > "$ADVISOR_AGENT_KEY"
: > "$ADVISOR_IDENTITY_DIR/enrollment-ca.crt"
echo "advisor.example:8443" > "$ADVISOR_IDENTITY_DIR/server"

MINTED="$WORK/minted" DELIVERED="$WORK/delivered" ENROLLED="$WORK/enrolled"
# Nodes that are control nodes, enrolled already, and whose enrolment fails.
CONTROL="n1 n2 n3" HAVE_ID="" FAIL_ON=""

curl() {
    local n
    n=$(( $(wc -l < "$MINTED") + 1 ))
    echo "tok$n" >> "$MINTED"
    printf '{"token":"tok%s"}' "$n"
}

# Mirrors the real remote_run: ssh's stderr is dropped.
remote_run() {
    local node=$1 ; shift
    case "$*" in
        "hex_sdk is_control_node") [[ " $CONTROL " == *" $node "* ]] ;;
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
reset() { : > "$MINTED" ; : > "$DELIVERED" ; : > "$ENROLLED" ; }

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

exit 0
