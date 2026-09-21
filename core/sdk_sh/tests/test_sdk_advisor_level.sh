#!/bin/bash
#
# Unit test for the action-level and consent helpers in
# ../modules/sdk_advisor.sh: advisor_level_set, advisor_consent_set,
# advisor_level_show. These write the files the agent reads as authoritative
# (ADR 0011/0017), so what matters is that a valid word is written verbatim, an
# invalid one is refused and nothing is written, and an absent file reads back
# as the fail-closed default rather than a blank.
#
# Self-contained: extracts only the functions under test, and stubs the agent
# restart, so it needs none of sdk_advisor.sh's runtime prerequisites.
# Run:  bash test_sdk_advisor_level.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_advisor.sh"

for f in _advisor_write_file advisor_level_set advisor_consent_set advisor_level_show ; do
    fn="$(awk -v want="^$f\\\\(\\\\)" '$0 ~ want {f=1} f{print} f&&/^}/{exit}' "$SRC")"
    [ -n "$fn" ] || { echo "FAIL: $f not found in $SRC"; exit 1; }
    eval "$fn"
done

# The agent is not running in a unit test; the reload is a no-op we assert never
# breaks a write.
_advisor_agent_reload_setting() { return 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ] ; then ok ; else bad "$1: got '$2', want '$3'" ; fi ; }

ADVISOR_LEVEL_FILE="$WORK/etc/action-level"
ADVISOR_CONSENT_FILE="$WORK/etc/consent"

# --- absent files read back as the fail-closed defaults ---------------------
check "level unset shows observe" "$(advisor_level_show | sed -n 's/^level //p')" "unset (observe)"
check "consent unset shows always" "$(advisor_level_show | sed -n 's/^consent //p')" "unset (always)"

# --- each valid level is written verbatim -----------------------------------
for v in observe operate internal ; do
    advisor_level_set "$v" >/dev/null 2>&1
    check "level_set $v writes the word" "$(cat "$ADVISOR_LEVEL_FILE")" "$v"
    check "level_set $v shows through" "$(advisor_level_show | sed -n 's/^level //p')" "$v"
done

# --- each valid consent value is written verbatim ---------------------------
for v in always destructive never ; do
    advisor_consent_set "$v" >/dev/null 2>&1
    check "consent_set $v writes the word" "$(cat "$ADVISOR_CONSENT_FILE")" "$v"
done

# --- an invalid value is refused and changes nothing ------------------------
advisor_level_set internal >/dev/null 2>&1
advisor_level_set administer >/dev/null 2>&1
rc=$?
check "an invalid level is refused" "$rc" "1"
check "a refused level leaves the last good value" "$(cat "$ADVISOR_LEVEL_FILE")" "internal"

advisor_consent_set never >/dev/null 2>&1
advisor_consent_set sometimes >/dev/null 2>&1
rc=$?
check "an invalid consent is refused" "$rc" "1"
check "a refused consent leaves the last good value" "$(cat "$ADVISOR_CONSENT_FILE")" "never"

# --- the file the agent reads is a bare word, one line, mode 0644 -----------
advisor_level_set operate >/dev/null 2>&1
check "level file is exactly the word plus newline" "$(wc -l < "$ADVISOR_LEVEL_FILE")" "1"
check "level file is mode 0644" "$(stat -c '%a' "$ADVISOR_LEVEL_FILE")" "644"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
