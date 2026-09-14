#
# TEST - what the advisor module says about an upgrade, when it runs the
#        agent, and how a node with no allowlist gets one.
#
# Three things, and they are the whole module's behaviour outside verification.
# The migrate registrations are what an upgrade carries onto the new partition:
# everything a node was given at enrolment, and nothing that would make systemd
# a second owner of the service. The commit hook is the only thing that starts
# or stops the agent, and it decides from the identity alone.
#
# The third is the seeding. The agent runs on every node and reads its own
# allowlist, but only the node someone enrolled on ever ran the seeding -- so
# every other node refused every target. Commit runs everywhere, so it seeds
# there. Seeding is not reconciling: an existing file must come out of a commit
# byte-for-byte unchanged, including one an operator has removed an entry from,
# or "advisor target_unset" would be undone by the next commit. That case is
# the one below that matters most.
#
# This compiles the real config_advisor.cpp against the stub hex/*.h and
# cube/*.h headers (the technique test_config_advisor_02.sh uses), with its path
# prefix aimed at a scratch tree and a fake systemctl on PATH -- so the code
# under test really runs, and what it decided is read back from the stub's own
# logs rather than from a mock's expectations.
#

fail() { echo "FAIL: $1"; exit 1; }

command -v g++     >/dev/null 2>&1 || { echo "SKIP: g++ not available";     exit 0; }
command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl not available"; exit 0; }

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SRC="$DIR/../../config_advisor.cpp"
[ -f "$SRC" ] || fail "cannot find config_advisor.cpp at $SRC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The stub driver logs to a fixed filename in the current directory, so the
# binary under test always runs from this scratch directory.
cd "$WORK" || fail "cannot cd to scratch directory"

# config_advisor.cpp embeds a release key; this test never verifies anything,
# so any well-formed key will do.
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/release.key" 2>/dev/null
openssl ec -in "$WORK/release.key" -pubout -out "$WORK/release.pub" 2>/dev/null
{ printf '#define ADVISOR_RELEASE_PUBLIC_KEY "'
  awk '{printf "%s\\n", $0}' "$WORK/release.pub"
  printf '"\n'
} > "$WORK/advisor_key.h"

ROOT="$WORK/root"

# Two logs, kept apart so each assertion is about one thing: what systemctl was
# asked to do directly (nothing, ever), and what the module decided the service
# should do. The stub driver writes the commit log to a fixed name in the
# directory the binary is run from, i.e. $WORK (see the cd above).
SYSTEMCTL_LOG="$WORK/systemctl.log"
COMMIT_LOG="$WORK/systemd_commit.log"
export SYSTEMCTL_LOG

# systemctl is called by name, so PATH is enough to catch it -- and catching it
# is the whole point: nothing in this module may call it.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$SYSTEMCTL_LOG"
exit 0
EOF
chmod +x "$WORK/bin/systemctl"
PATH="$WORK/bin:$PATH"
export PATH

# A stand-in for hex_sdk. It records the argv the module handed it, then runs
# the real allowlist helpers straight out of sdk_advisor.sh with their two file
# paths aimed at the scratch tree -- so what a commit triggers here is the code
# that ships, not a second implementation of it that could drift from it.
ADVISOR_SDK="$DIR/../../../sdk_sh/modules/sdk_advisor.sh"
[ -f "$ADVISOR_SDK" ] || fail "cannot find sdk_advisor.sh at $ADVISOR_SDK"

FAKE_SDK="$WORK/fake_hex_sdk"
SDK_CALL_LOG="$WORK/hex_sdk.log"
export SDK_CALL_LOG

cat > "$FAKE_SDK" <<EOF
#!/bin/bash
set -u
SRC="$ADVISOR_SDK"
ADVISOR_TARGETS_FILE="$ROOT/etc/cube-advisor-agent/web-targets.json"
ADVISOR_INGRESS_FILE="$ROOT/etc/cube-advisor-agent/ingress"
EOF
cat >> "$FAKE_SDK" <<'EOF'
echo "$*" >> "$SDK_CALL_LOG"
for f in _advisor_write_file _advisor_targets_write advisor_ingress_address \
         advisor_targets_init ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "missing $f in $SRC" >&2 ; exit 1 ; }
    eval "$fn"
done
"$@"
EOF
chmod +x "$FAKE_SDK"

g++ -Wall -Werror -Wno-unused-result -I"$WORK" -I"$DIR/stub" \
    -DADVISOR_TEST_TREE="\"$ROOT\"" -DHEX_SDK="\"$FAKE_SDK\"" \
    -o "$WORK/advisorctl" "$SRC" "$DIR/stub/driver.cpp" -lcrypto \
    || fail "config_advisor.cpp did not compile against the stub headers"

V="$WORK/advisorctl"

IDENTITY_DIR="$ROOT/etc/cube/advisor-agent"
TARGETS_FILE="$ROOT/etc/cube-advisor-agent/web-targets.json"
INGRESS_FILE="$ROOT/etc/cube-advisor-agent/ingress"

# reset [enrolled] -- a node with or without the identity an upgrade carries
# across.
reset() {
    rm -rf "$ROOT" "$SYSTEMCTL_LOG" "$COMMIT_LOG" "$SDK_CALL_LOG"
    mkdir -p "$IDENTITY_DIR"
    if [ "$1" = enrolled ] ; then
        printf 'cert\n' > "$IDENTITY_DIR/agent.crt"
        printf 'key\n'  > "$IDENTITY_DIR/agent.key"
    fi
    return 0
}

commits() { [ -f "$COMMIT_LOG" ] && cat "$COMMIT_LOG" ; }

# ---- what an upgrade carries across ----
# This list is the module's entire answer to an upgrade, so it is asserted
# exactly: every path an enrolled node was given, and nothing else. The agent
# binary is on it -- it lives on the same root filesystem as the identity, so
# carrying it is no weaker than carrying that. The unit's enable symlink is not
# and must never be: hex_config decides when the service runs, and a symlink
# would make systemd a second owner of it on the new partition.
expected="$ROOT/etc/cube/advisor-agent
$ROOT/usr/local/bin/cube-advisor-agent
$ROOT/etc/cube-advisor-agent/web-targets.json
$ROOT/etc/ssh/console-ca/cube-advisor.pub
$ROOT/etc/ssh/sshd_config.d/60-cube-advisor-console.conf"

got=$("$V" migrate_paths) || fail "could not read the registered migrate paths"
[ "$got" = "$expected" ] || fail "the migrate set changed:
got:
$got
expected:
$expected"

case "$got" in
    *multi-user.target.wants*)
        fail "the unit's enable symlink is migrated; hex_config owns the service" ;;
esac

# ---- commit: the guards ----
# hex_config's commit pass is the only thing that starts or stops the agent.
# Two guards run before that decision, and they are not about the Advisor: a
# node whose role is not known yet is not configured at all, and a full dry run
# decides nothing. HEX_BOOTSTRAP puts the stub commit in the pass that runs on
# every boot, which is the one that matters here.
export HEX_BOOTSTRAP=1

# No role: an unconfigured node. The module must not touch the service.
reset enrolled
"$V" commit >/dev/null 2>&1 || fail "commit failed on a node with no role yet"
[ -s "$COMMIT_LOG" ] \
    && fail "the service was committed before the node had a role: [$(commits)]"

# A full dry run decides nothing either.
reset enrolled
"$V" commit control-converged 2 >/dev/null 2>&1 || fail "commit failed on a dry run"
[ -s "$COMMIT_LOG" ] && fail "a dry run committed the service: [$(commits)]"

# ---- commit: the service runs exactly when this node has an identity ----
# hex_config owns the service. The module's only job is to answer "should the
# agent be running here", and the answer is the identity -- not the binary, not
# the role. A node whose binary will not run has an identity all the same; the
# start then fails and says so in the journal, which is the signal that belongs
# there.
reset enrolled
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed on an enrolled node"
[ "$(commits)" = "start cube-advisor-agent" ] \
    || fail "an enrolled node did not commit the service as running: [$(commits)]"

reset
"$V" commit control-converged >/dev/null 2>&1 \
    || fail "commit failed on a node that was never enrolled"
[ "$(commits)" = "stop cube-advisor-agent" ] \
    || fail "an un-enrolled node did not commit the service as stopped: [$(commits)]"

# The role is not part of the answer. Every module this one is modelled on
# gates "enabled" on IsControl(); the Advisor deliberately does not, because a
# node holds an identity only because someone enrolled it -- and any node may
# be enrolled. A compute or storage node with an identity runs the agent.
for role in compute storage network edge-core moderator ; do
    reset enrolled
    "$V" commit "$role" >/dev/null 2>&1 || fail "commit failed on a $role node"
    [ "$(commits)" = "start cube-advisor-agent" ] \
        || fail "an enrolled $role node was not committed as running: [$(commits)]"
done

# "Enrolled" is one question with one answer: the identity this node was
# issued. Remove it and the service stops.
reset enrolled ; rm -f "$IDENTITY_DIR/agent.crt"
"$V" commit control-converged >/dev/null 2>&1 \
    || fail "commit failed on a node whose identity is gone"
[ "$(commits)" = "stop cube-advisor-agent" ] \
    || fail "a node with no identity was committed as running: [$(commits)]"

# The module never enables anything: SystemdCommitService stops and starts, and
# nothing here reaches for systemctl on its own.
reset enrolled
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed on the re-run"
[ -s "$SYSTEMCTL_LOG" ] && fail "commit called systemctl directly: $(cat "$SYSTEMCTL_LOG")"
case "$(commits)" in
    *enable*) fail "the module asked for the unit to be enabled: $(commits)" ;;
esac

# ---- commit: a node with no allowlist gets one ----
# This is the bug the seeding exists for: only the node someone enrolled on
# ever ran advisor_targets_init, so every other node in the cluster had no
# allowlist at all and refused every web target.
reset enrolled
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed on an enrolled node"
[ -s "$TARGETS_FILE" ] || fail "commit left the node with no allowlist"
grep -q '"cube-cos":"127.0.0.1:8080"' "$TARGETS_FILE" \
    || fail "the seeded allowlist does not name cube-cos: [$(cat "$TARGETS_FILE")]"
grep -q advisor_targets_init "$SDK_CALL_LOG" \
    || fail "commit did not seed through hex_sdk: [$(cat "$SDK_CALL_LOG" 2>/dev/null)]"

# ---- commit: with an ingress address, the CMP names are seeded too ----
# The address is all a node is given (advisor_ingress_set writes it); turning
# it into entries is this node's own job, here.
reset enrolled
mkdir -p "$(dirname "$INGRESS_FILE")"
printf '10.32.1.101\n' > "$INGRESS_FILE"
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed with an ingress address present"
grep -q '"cube-cmp":"10.32.1.101:443"' "$TARGETS_FILE" \
    || fail "cube-cmp was not seeded at the ingress address: [$(cat "$TARGETS_FILE")]"
grep -q '"app-fw-idp":"10.32.1.101:443"' "$TARGETS_FILE" \
    || fail "app-fw-idp was not seeded at the ingress address: [$(cat "$TARGETS_FILE")]"

# ---- commit: an existing allowlist is never touched ----
# The one that matters. Seeding means "a node with no allowlist gets one", not
# "every node is reconciled to a canonical set". An operator who ran
# "advisor target_unset cube-cmp" removed it deliberately; a commit that put it
# back would make target_unset useless.
reset enrolled
mkdir -p "$(dirname "$INGRESS_FILE")"
printf '10.32.1.101\n' > "$INGRESS_FILE"
printf '{"cube-cos":"127.0.0.1:8080","app-fw-idp":"10.32.1.101:443"}\n' > "$TARGETS_FILE"
before=$(cat "$TARGETS_FILE")
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed on a node that already has an allowlist"
[ "$(cat "$TARGETS_FILE")" = "$before" ] \
    || fail "commit changed an existing allowlist: [$(cat "$TARGETS_FILE")] was [$before]"
grep -q cube-cmp "$TARGETS_FILE" \
    && fail "commit restored a target the operator had unset: [$(cat "$TARGETS_FILE")]"

# The same holds for an allowlist that has nothing this module would recognise:
# it is the operator's file, and a commit only ever adds one that is not there.
reset enrolled
mkdir -p "$(dirname "$TARGETS_FILE")"
printf '{"my-own":"10.0.0.9:8443"}\n' > "$TARGETS_FILE"
before=$(cat "$TARGETS_FILE")
"$V" commit control-converged >/dev/null 2>&1 || fail "commit failed on a hand-written allowlist"
[ "$(cat "$TARGETS_FILE")" = "$before" ] \
    || fail "commit rewrote a hand-written allowlist: [$(cat "$TARGETS_FILE")]"

# ---- commit: the guards come first for seeding too ----
# A node with no role is not configured yet, and a dry run decides nothing --
# neither may leave a file behind.
reset enrolled
"$V" commit >/dev/null 2>&1 || fail "commit failed on a node with no role yet"
[ -e "$TARGETS_FILE" ] && fail "an unconfigured node was given an allowlist"

reset enrolled
"$V" commit control-converged 2 >/dev/null 2>&1 || fail "commit failed on a dry run"
[ -e "$TARGETS_FILE" ] && fail "a dry run wrote an allowlist"

exit 0
