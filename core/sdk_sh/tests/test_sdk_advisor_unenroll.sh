#!/bin/bash
#
# Unit test for advisor_unenroll / advisor_unenroll_node in
# ../modules/sdk_advisor.sh -- the cluster's kill switch.
#
# Run from a control node only. Every enrolled node is stopped and loses its identity, whether or not the
# Advisor can be told; an unreachable peer is named and fails the run; a
# cluster that is not enrolled is left alone. Also: an enrolment token that
# still carries level/consent is accepted and neither is written.
#
# Self-contained: stubs remote_run, is_sshable, is_control_node, systemctl, timeout and the
# agent binary; each node is a directory.
# Run:  bash test_sdk_advisor_unenroll.sh   (exit 0 = pass)
#
# shellcheck disable=SC2034  # read by the eval-ed functions
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_token_decode advisor_unenroll_node advisor_unenroll ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ADVISOR_AGENT_UNIT_NAME=cube-advisor-agent.service
HEX_SDK=hex_sdk
HOSTNAME=n1
LOG="$WORK/log"
# Unreachable nodes, how the agent's unenroll ends, nodes whose unit will not
# stop, and this node's role.
DOWN="" AGENT_RC=0 STUCK="" ROLE=control

# Points every path at one node's directory.
use_node() {
    N="$WORK/$1"
    ADVISOR_IDENTITY_DIR="$N/id"
    ADVISOR_AGENT_CERT="$ADVISOR_IDENTITY_DIR/agent.crt"
    ADVISOR_AGENT_KEY="$ADVISOR_IDENTITY_DIR/agent.key"
    ADVISOR_PROXY_FILE="$ADVISOR_IDENTITY_DIR/proxy"
    ADVISOR_AGENT_BIN="$N/agent"
    ADVISOR_CONSOLE_CA="$N/console-ca.pub"
    ADVISOR_SSHD_DROPIN="$N/sshd-dropin.conf"
    ADVISOR_TRUST_ANCHOR="$N/anchor.crt"
    ADVISOR_TARGETS_FILE="$N/web-targets.json"
}

# make_node <node> [enrolled]
make_node() {
    use_node "$1"
    rm -rf "$N" ; mkdir -p "$ADVISOR_IDENTITY_DIR"
    printf '#!/bin/bash\necho "%s $*" >> "%s"\nexit $(cat "%s")\n' "$1" "$LOG" "$WORK/agent_rc" > "$ADVISOR_AGENT_BIN"
    chmod +x "$ADVISOR_AGENT_BIN"
    echo '{}' > "$ADVISOR_TARGETS_FILE"
    if [ "${2:-}" = enrolled ] ; then
        : > "$ADVISOR_AGENT_CERT" ; : > "$ADVISOR_AGENT_KEY"
        : > "$ADVISOR_IDENTITY_DIR/enrollment-ca.crt"
        echo "advisor.example:8443" > "$ADVISOR_IDENTITY_DIR/server"
        echo observe > "$ADVISOR_IDENTITY_DIR/action-level"
        : > "$ADVISOR_CONSOLE_CA" ; : > "$ADVISOR_SSHD_DROPIN" ; : > "$ADVISOR_TRUST_ANCHOR"
        : > "$N/active"
    fi
}

cluster() {  # cluster <enrolled nodes...>; three nodes, the named ones enrolled
    local n
    : > "$LOG"
    echo "$AGENT_RC" > "$WORK/agent_rc"
    for n in n1 n2 n3 ; do
        if [[ " $* " == *" $n "* ]] ; then make_node "$n" enrolled ; else make_node "$n" ; fi
    done
    use_node n1
}

timeout() { echo "timeout $1 $2 $3" >> "$LOG" ; shift 3 ; "$@" ; }
update-ca-trust() { : ; }
advisor_sso_reported_set() { echo "sso_withdrawn $(basename "$N")" >> "$LOG" ; }
advisor_sso_apply() { : ; }
systemctl() {
    local node ; node=$(basename "$N")
    case "$*" in
        "disable --now $ADVISOR_AGENT_UNIT_NAME"|"stop $ADVISOR_AGENT_UNIT_NAME")
            echo "systemctl $node $1" >> "$LOG"
            [[ " $STUCK " == *" $node "* ]] && return 1
            rm -f "$N/active" ;;
        "is-active --quiet $ADVISOR_AGENT_UNIT_NAME") [ -e "$N/active" ] ;;
        "reload sshd") echo "sshd_reload $node" >> "$LOG" ;;
        *) echo "unexpected systemctl $*" >&2 ; return 99 ;;
    esac
}
is_control_node() { [ "$ROLE" = control ] ; }
is_sshable() { [[ " $DOWN " != *" $1 "* ]] ; }
# Mirrors the real remote_run: the node's own state, ssh's stderr dropped.
remote_run() {
    local node=$1 ; shift
    case "$*" in
        "stat "*) ( use_node "$node" ; [ -e "$ADVISOR_AGENT_CERT" ] ) ;;
        "hex_sdk advisor_unenroll_node 2>&1") ( use_node "$node" ; advisor_unenroll_node 2>&1 ) ;;
        *) echo "unexpected remote_run $node $*" >&2 ; return 99 ;;
    esac
}

fail() { echo "FAIL: $1"; exit 1; }
# cut_off <node>: stopped, no identity, re-enrol settings kept.
cut_off() {
    [ -e "$WORK/$1/active" ] && fail "$1: the agent is still running"
    [ -z "$(find "$WORK/$1/id" -mindepth 1 ! -name proxy)" ] || fail "$1: identity files left: $(ls "$WORK/$1/id")"
    [ -e "$WORK/$1/console-ca.pub" ] || [ -e "$WORK/$1/sshd-dropin.conf" ] && fail "$1: console trust left"
    [ -e "$WORK/$1/anchor.crt" ] && fail "$1: the Advisor's CA is still trusted"
    [ -e "$WORK/$1/web-targets.json" ] || fail "$1: the web allowlist was deleted"
    return 0
}

CUBE_NODE_LIST_HOSTNAMES=(n1 n2 n3)

# ---- every enrolled node is told, stopped and loses its identity ----
cluster n1 n2 n3
echo "proxy.example:3128" > "$WORK/n2/id/proxy"
out=$(advisor_unenroll 2>&1) || fail "unenroll failed: $out"
for n in n1 n2 n3 ; do
    cut_off $n
    grep -q "^$n unenroll$" "$LOG" || fail "$n: the Advisor was not told"
    grep -q "^systemctl $n disable$" "$LOG" || fail "$n: the unit was not disabled"
    grep -q "^sshd_reload $n$" "$LOG" || fail "$n: sshd not reloaded"
    grep -q "^sso_withdrawn $n$" "$LOG" || fail "$n: console origins not withdrawn"
done
[ "$(grep -c '^timeout -k 5 15$' "$LOG")" -eq 3 ] || fail "the agent call has no time limit: $(cat "$LOG")"
[ -e "$WORK/n2/id/proxy" ] || fail "the proxy file was deleted"
[ "$(echo "$out" | grep -c "Told the Advisor")" -eq 3 ] || fail "no told line per node: $out"
echo "$out" | grep -q "cut off from the Advisor" || fail "no closing line: $out"

# ---- a second run is a no-op ----
: > "$LOG"
out=$(advisor_unenroll 2>&1) || fail "a not-enrolled cluster failed: $out"
echo "$out" | grep -q "not enrolled" || fail "not-enrolled not said: $out"
[ -s "$LOG" ] && fail "a not-enrolled cluster was touched: $(cat "$LOG")"

# ---- the Advisor cannot be reached: still cut off ----
AGENT_RC=7
cluster n1 n2 n3
out=$(advisor_unenroll 2>&1) || fail "an unreachable Advisor failed the run: $out"
for n in n1 n2 n3 ; do cut_off $n ; done
[ "$(echo "$out" | grep -c "the Advisor could not be told; carrying on")" -eq 3 ] || fail "no note per node: $out"

# ---- an agent without the subcommand: same ----
AGENT_RC=2
cluster n1 n2
out=$(advisor_unenroll 2>&1) || fail "an older agent failed the run: $out"
cut_off n1 ; cut_off n2
[ "$(echo "$out" | grep -c "this agent cannot tell the Advisor; carrying on")" -eq 2 ] || fail "no note per node: $out"
AGENT_RC=0

# ---- refused on a compute or storage node, nothing touched ----
cluster n1 n2 n3
ROLE=compute T_cubesys_role=compute
out=$(advisor_unenroll 2>&1) && fail "a compute node ran the kill switch"
echo "$out" | grep -q "on a control node" || fail "no pointer to a control node: $out"
[ -s "$LOG" ] && fail "a refused run touched the cluster: $(cat "$LOG")"
[ -e "$WORK/n2/id/agent.crt" ] || fail "a refused run deleted an identity"
ROLE=control

# ---- no agent binary at all ----
cluster n1
rm -f "$WORK/n1/agent"
out=$(advisor_unenroll 2>&1) || fail "a missing agent binary failed the run: $out"
cut_off n1

# ---- only a peer is enrolled ----
cluster n3
out=$(advisor_unenroll 2>&1) || fail "unenroll from a node without an identity failed: $out"
cut_off n3

# ---- an interrupted run (key gone, certificate left) is finished ----
cluster n1 n2
rm -f "$WORK/n2/id/agent.key"
out=$(advisor_unenroll 2>&1) || fail "finishing an interrupted run failed: $out"
cut_off n1 ; cut_off n2

# ---- an unreachable peer is named and fails the run; the rest are done ----
cluster n1 n2 n3
DOWN="n3"
out=$(advisor_unenroll 2>&1) && fail "an unreachable peer still returned 0"
cut_off n1 ; cut_off n2
[ -e "$WORK/n3/id/agent.crt" ] || fail "an unreachable peer was touched"
echo "$out" | grep -q "could not reach: n3. Run 'advisor unenroll'" || fail "unreachable peer not named: $out"
echo "$out" | grep -q "This cluster is cut off" && fail "claimed the whole cluster is cut off: $out"

# ---- nothing reachable is enrolled, but a peer is unreachable: not a clean no-op ----
cluster
out=$(advisor_unenroll 2>&1) && fail "an unreachable peer was assumed not enrolled"
echo "$out" | grep -q "could not reach: n3" || fail "unreachable peer not named: $out"
DOWN=""

# ---- a unit that will not stop fails the run, identity still deleted ----
cluster n1 n2
STUCK="n2"
out=$(advisor_unenroll 2>&1) && fail "a running agent still returned 0"
[ -e "$WORK/n2/id/agent.crt" ] || [ -e "$WORK/n2/id/agent.key" ] && fail "n2 kept its identity"
echo "$out" | grep -q "did not complete on: n2" || fail "failed node not named: $out"
STUCK=""

# ---- a token still carrying level and consent is accepted, neither written ----
tok="cubeadv1.$(python3 -c '
import base64, gzip, json
print(base64.urlsafe_b64encode(gzip.compress(json.dumps(
    {"url": "https://advisor.example", "s": "secret", "level": "operate", "consent": "never"}
).encode())).decode().rstrip("="))')"
mkdir "$WORK/tok"
_advisor_token_decode "$tok" "$WORK/tok" || fail "a token with level/consent was refused"
[ "$(cat "$WORK/tok/url")" = "https://advisor.example" ] || fail "token url not decoded"
[ -e "$WORK/tok/level" ] || [ -e "$WORK/tok/consent" ] && fail "level/consent were taken from the token"

exit 0
