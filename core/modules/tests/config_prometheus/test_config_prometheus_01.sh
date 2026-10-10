#
# TEST - config_prometheus applies its own retention tunings
#   1. role change + rp tunings  -> the tunings reach prometheus.yml (parse)
#   2. rp tunings alone          -> the commit is not skipped (CommitCheck)
#   3. rp.size = 0               -> no size line, time still written
#
# Each case seeds /etc/settings.txt as the committed side, so the diff hex_config
# sees is exactly the one the case names.
#

CONF=/etc/prometheus/prometheus.yml

fail() { echo "FAIL: $1"; exit 1; }

BASE="cubesys.role=control
cubesys.control.addrs=10.99.99.1
cubesys.ha=false
net.hostname=node1"

# $1 = case name, $2 = committed settings, $3 = new settings
run_case() {
    rm -f $CONF
    printf '%s\n' "$2" > /etc/settings.txt
    printf '%s\n' "$3" > /tmp/settings.txt
    # non-zero exit is not a failure here: only the module under test is linked
    ./hex_config -vvve commit /tmp/settings.txt >/tmp/commit_$1.log 2>&1 || true
}

# ---- 1. role change carries the tunings: they must be parsed, not defaulted ----
run_case parse "" "$BASE
prometheus.rp.duration=20
prometheus.rp.size=4"
[ -f $CONF ] || fail "parse: $CONF was not written"
grep -q "^      time: 20d$" $CONF || fail "parse: retention time is not 20d ($(grep 'time:' $CONF))"
grep -q "^      size: 4GB$" $CONF || fail "parse: retention size is not 4GB ($(grep 'size:' $CONF))"
echo "  ok  parse              -> time 20d, size 4GB"

# ---- 2. only prometheus.* changes: the module must still commit ----
run_case tunings-only "$BASE" "$BASE
prometheus.rp.duration=20
prometheus.rp.size=4"
[ -f $CONF ] || fail "tunings-only: commit skipped, $CONF not written"
grep -q "^      time: 20d$" $CONF || fail "tunings-only: retention time is not 20d"
grep -q "^      size: 4GB$" $CONF || fail "tunings-only: retention size is not 4GB"
echo "  ok  tunings-only       -> committed, time 20d, size 4GB"

# ---- 3. size 0 disables the cap ----
run_case size-zero "$BASE" "$BASE
prometheus.rp.duration=7
prometheus.rp.size=0"
[ -f $CONF ] || fail "size-zero: $CONF not written"
grep -q "^      time: 7d$" $CONF || fail "size-zero: retention time is not 7d"
grep -q "^      size:" $CONF && fail "size-zero: size line written for rp.size=0"
echo "  ok  size-zero          -> time 7d, no size cap"

echo "config_prometheus: all retention cases passed"
