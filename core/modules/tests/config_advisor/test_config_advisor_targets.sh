#
# TEST - the CLI layer added over the sdk_advisor.sh web-targets helpers:
#         targets / target_set / target_unset / status.
#
# cli_advisor.cpp is a thin HexSpawn wrapper around hex_sdk's
# advisor_targets_list/set/unset -- it must not re-validate, reformat, or
# swallow what the helper says. That is easiest to prove by actually running
# it: this compiles the real cli_advisor.cpp against stub hex/*.h headers (the
# same technique test_config_advisor_02.sh uses for config_advisor.cpp) with
# HEX_SDK pointed at a fake helper script this test controls, so HexSpawn
# really forks and execs it and the CLI's stdout is really the fake helper's
# stdout.
#
# The stubs under stub/ replace hex/cli_module.h, hex/cli_util.h,
# hex/process.h and hex/strict.h only; cli_driver.cpp supplies real
# implementations of the handful of calls those headers declare. The code
# under test is byte-for-byte the code that ships.
#

fail() { echo "FAIL: $1"; exit 1; }

command -v g++ >/dev/null 2>&1 || { echo "SKIP: g++ not available"; exit 0; }

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SRC="$DIR/../../cli_advisor.cpp"
[ -f "$SRC" ] || fail "cannot find cli_advisor.cpp at $SRC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAKE_SDK="$WORK/fake_hex_sdk"
CALL_LOG="$WORK/calls.log"
export CALL_LOG

# A stand-in for hex_sdk: records every invocation ("$*") verbatim so a test
# can assert exactly what argv it received, and answers the two commands the
# CLI calls the way the real advisor_targets_list/set/unset would.
cat > "$FAKE_SDK" <<'EOF'
#!/bin/bash
echo "$*" >> "$CALL_LOG"
case "$1" in
    advisor_targets_list)
        printf 'dashboard 127.0.0.1:8080\nconsole 10.0.0.5:9090\n'
        exit 0
        ;;
    advisor_targets_set|advisor_targets_unset)
        exit 0
        ;;
    *)
        exit 9
        ;;
esac
EOF
chmod +x "$FAKE_SDK"

g++ -Wall -Werror -Wno-unused-parameter -I"$DIR/stub" \
    -DHEX_SDK="\"$FAKE_SDK\"" \
    -o "$WORK/advisorctl" "$SRC" "$DIR/stub/cli_driver.cpp" \
    || fail "cli_advisor.cpp did not compile against the stub CLI headers"

V="$WORK/advisorctl"

# CLI_SUCCESS=0, CLI_INVALID_ARGS=1, CLI_FAILURE=3 (hex/cli_impl.h)

# ---- targets: prints exactly what the helper prints ----
out=$("$V" targets) || fail "targets exited non-zero on a helper that succeeded"
expected=$'dashboard 127.0.0.1:8080\nconsole 10.0.0.5:9090'
[ "$out" = "$expected" ] || fail "targets did not pass the helper's output through unchanged: got [$out]"

# ---- target_set: wrong arity is refused before the helper is ever called ----
rm -f "$CALL_LOG"
"$V" target_set onlyname >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] || fail "target_set with one argument did not return CLI_INVALID_ARGS (got $rc)"
[ -e "$CALL_LOG" ] && fail "target_set with the wrong arity still invoked the helper"

# ---- target_set: both arguments reach the helper unchanged ----
rm -f "$CALL_LOG"
"$V" target_set my-name 10.0.0.5:9090 >/dev/null \
    || fail "target_set refused a call the helper accepted"
[ "$(cat "$CALL_LOG")" = "advisor_targets_set my-name 10.0.0.5:9090" ] \
    || fail "target_set did not pass name and host:port through unchanged: $(cat "$CALL_LOG")"

# ---- target_unset: wrong arity is refused before the helper is called ----
rm -f "$CALL_LOG"
"$V" target_unset >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] || fail "target_unset with no argument did not return CLI_INVALID_ARGS (got $rc)"
[ -e "$CALL_LOG" ] && fail "target_unset with the wrong arity still invoked the helper"

# ---- target_unset: the name reaches the helper unchanged ----
rm -f "$CALL_LOG"
"$V" target_unset my-name >/dev/null \
    || fail "target_unset refused a call the helper accepted"
[ "$(cat "$CALL_LOG")" = "advisor_targets_unset my-name" ] \
    || fail "target_unset did not pass the name through unchanged: $(cat "$CALL_LOG")"

# ---- status: names the target count, and succeeds with no agent installed ----
# The real agent binary is an absolute path cli_advisor.cpp hardcodes
# (/usr/local/bin/cube-advisor-agent); this build/test host has no such
# binary, which is exactly the case being covered.
out=$("$V" status)
rc=$?
[ "$rc" -eq 0 ] || fail "status failed when the Advisor agent is not installed (got $rc)"
case "$out" in
    *"2 web target"*) ;;
    *) fail "status did not report the target count: [$out]" ;;
esac
case "$out" in
    *"not installed"*) ;;
    *) fail "status did not say the agent is not installed: [$out]" ;;
esac

exit 0
