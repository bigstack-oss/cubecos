#
# TEST - config_grafana binds to loopback and sets a per-cluster admin password
#   1. fresh node, no saltkey    -> loopback bind, basic auth off, default password in the ini
#   2. saltkey on, seed A        -> the password is salted with the seed
#   3. commit again              -> the same password
#   4. saltkey on, seed B        -> another cluster, another password
#   5. grafana.admin.password    -> the tuning is the input
#   6. tuning too short          -> rejected, nothing rewritten
#   7. existing database         -> reset is run, the password never reaches the log
#
# Each case starts from an empty /etc/settings.txt, so the role change alone makes the
# module commit.
#

CONF=/etc/grafana/grafana.ini
DB=/var/lib/grafana/grafana.db

# GetSaltKey(true, "4z8VFo5Sj2h0WU8B", seed): the first 16 base64 characters of
# sha1(key seed), with + / = replaced by p S e
DEFAULT=4z8VFo5Sj2h0WU8B
SALTED_A=eBrT96VxYRzeM3Nj
SALTED_B=u7SMneix79dH3yXk

fail() { echo "FAIL: $1"; exit 1; }

BASE="cubesys.role=control
net.hostname=node1"

# $1 = case name, $2.. = extra settings lines
run_case() {
    local name=$1 ; shift
    : > /etc/settings.txt
    { printf '%s\n' "$BASE" ; [ $# -gt 0 ] && printf '%s\n' "$@" ; } > /tmp/settings.txt
    # non-zero exit is not a failure here: only the module under test is linked
    ./hex_config -vvve commit /tmp/settings.txt >"/tmp/commit_$name.log" 2>&1 || true
}

# $1 = case name, $2 = expected password
check_pass() {
    [ "$(grep -c '^admin_password = ' $CONF)" = "1" ] || fail "$1: not one admin_password line"
    grep -qx "admin_password = $2" $CONF || fail "$1: admin_password is not $2"
}

# ---- 1. fresh node ----
run_case fresh
[ -f $CONF ] || fail "fresh: $CONF was not written"
grep -qx "http_addr = 127.0.0.1" $CONF || fail "fresh: http_addr is not loopback"
grep -qx "root_url = http://10.99.99.99/grafana" $CONF || fail "fresh: root_url is not on SHARED_ID"
grep -A1 -x "\[auth.basic\]" $CONF | grep -qx "enabled = false" || fail "fresh: basic auth is not off"
grep -A1 -x "\[auth.anonymous\]" $CONF | grep -qx "enabled = true" || fail "fresh: anonymous access was turned off"
grep -q "^org_role" $CONF && fail "fresh: anonymous org_role is set"
[ "$(stat -c %a $CONF)" = "640" ] || fail "fresh: $CONF mode is $(stat -c %a $CONF)"
check_pass fresh $DEFAULT
echo "  ok  fresh              -> loopback, basic auth off, default password"

# ---- 2. salted with the cluster seed ----
run_case salted "cubesys.saltkey=true" "cubesys.seed=TestSeed1"
check_pass salted $SALTED_A
echo "  ok  salted             -> seed-salted password"

# ---- 3. commit again: the password stays ----
run_case again "cubesys.saltkey=true" "cubesys.seed=TestSeed1"
check_pass again $SALTED_A
echo "  ok  again              -> same password"

# ---- 4. another seed, another password ----
run_case seed2 "cubesys.saltkey=true" "cubesys.seed=TestSeed2"
check_pass seed2 $SALTED_B
echo "  ok  seed2              -> different password"

# ---- 5. the tuning is the input ----
run_case tuned "grafana.admin.password=Tuned.pass-123"
check_pass tuned "Tuned.pass-123"
echo "  ok  tuned              -> tuning applied"

# ---- 6. a tuning that fails validation changes nothing ----
cp -f $CONF /tmp/grafana.ini.before
run_case invalid "grafana.admin.password=short"
cmp -s $CONF /tmp/grafana.ini.before || fail "invalid: $CONF rewritten"
rm -f /tmp/grafana.ini.before
echo "  ok  invalid            -> rejected"

# ---- 7. an existing database is reset, without the password on the command line ----
touch $DB
run_case reset "cubesys.saltkey=true" "cubesys.seed=TestSeed1"
check_pass reset $SALTED_A
grep -q "reset-admin-password --password-from-stdin < /run/grafana-admin\." /tmp/commit_reset.log \
    || fail "reset: reset was not run from a /run file"
grep -qF "$SALTED_A" /tmp/commit_reset.log && fail "reset: password shows up in the log"
ls /run/grafana-admin.* >/dev/null 2>&1 && fail "reset: the password file was left in /run"
rm -f $DB
echo "  ok  reset              -> reset run, password not logged or left behind"

echo "config_grafana: all cases passed"
