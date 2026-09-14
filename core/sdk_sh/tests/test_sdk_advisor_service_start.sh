#!/bin/bash
#
# Unit test for advisor_agent_service_start in ../modules/sdk_advisor.sh.
#
# In cubecos hex_config owns when a service runs: the advisor module's Commit
# calls SystemdCommitService, which stops and starts the unit and never enables
# it. So enrolment may start the agent -- the operator expects it up at once --
# but must not enable it, or systemd becomes a second owner that starts the
# agent at multi-user.target on a node hex_config decided should not run it.
# Nothing in the tree enables this unit any more, so nothing needs to disable
# it either.
#
# Self-contained: extracts only the function under test and stubs systemctl,
# so it needs none of sdk_advisor.sh's runtime prerequisites.
# Run:  bash test_sdk_advisor_service_start.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

fn="$(awk '/^advisor_agent_service_start\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: advisor_agent_service_start not found in $SRC"; exit 1; }
eval "$fn"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ADVISOR_AGENT_UNIT_NAME=cube-advisor-agent.service
ADVISOR_AGENT_UNIT="$WORK/$ADVISOR_AGENT_UNIT_NAME"
CALLS="$WORK/calls"

# Records what it was asked to do, so the assertions are about real argv.
systemctl() {
    echo "systemctl $*" >> "$CALLS"
    return 0
}

fail() { echo "FAIL: $1"; exit 1; }

printf '[Unit]\n' > "$ADVISOR_AGENT_UNIT"

# ---- enrolment: start it, and touch nothing else ----
: > "$CALLS"
advisor_agent_service_start >/dev/null 2>&1 || fail "start returned non-zero"
grep -q -- "systemctl start $ADVISOR_AGENT_UNIT_NAME" "$CALLS" \
    || fail "the unit was not started: $(cat "$CALLS")"

# The assertion this file exists for: enabling would hand systemd a second
# opinion about when the agent runs, which is hex_config's alone.
grep -q -- "systemctl enable" "$CALLS" \
    && fail "enrolment enabled the unit; hex_config owns that: $(cat "$CALLS")"
grep -q -- "--now" "$CALLS" \
    && fail "enrolment used an enabling form of start: $(cat "$CALLS")"

# And nothing disables it: nothing enables it in the first place, so a disable
# would be a systemctl call on every enrolment that can never do anything.
grep -q -- "systemctl disable" "$CALLS" \
    && fail "enrolment disabled a unit nothing ever enables: $(cat "$CALLS")"
grep -q -- "systemctl is-enabled" "$CALLS" \
    && fail "enrolment asked whether a unit nothing enables is enabled: $(cat "$CALLS")"

# ---- no unit installed ----
# Enrolment has already succeeded by the time this is called, so a missing unit
# is a warning, not a failure.
rm -f "$ADVISOR_AGENT_UNIT"
: > "$CALLS"
advisor_agent_service_start >/dev/null 2>&1 \
    || fail "a missing unit file was turned into a failure"
[ -s "$CALLS" ] && fail "a missing unit file still ran systemctl: $(cat "$CALLS")"

exit 0
