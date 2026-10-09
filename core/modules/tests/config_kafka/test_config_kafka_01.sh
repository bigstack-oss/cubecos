#
# TEST - config_kafka gives each kafka/zookeeper log exactly one rotator (#1767)
#   1. the logrotate.d files name only the systemd-captured stdout logs, no *.log glob
#   2. the commit prunes the *.backup orphans the old glob left behind, and nothing else
#   3. a forced logrotate run leaves the log4j generations alone and makes no *.backup
#      (and the old *.log glob, run the same way, does -- so the check is not vacuous)
#
# Role compute keeps kafka disabled, so Commit neither waits on a zookeeper port nor
# touches topics; WriteLogRotateConf and the prune run for every role.
#

fail() { echo "FAIL: $1"; exit 1; }

KLOG=/var/log/kafka
ZLOG=/var/log/zookeeper

# what a 3.2.0 node carries: log4j generations, a JVM GC generation, systemd stdout,
# and the orphans of earlier collisions
seed() {
    rm -rf $KLOG/* $ZLOG/*
    echo "server live"      > $KLOG/server.log
    echo "server log4j .1"  > $KLOG/server.log.1
    echo "gc live"          > $KLOG/kafkaServer-gc.log
    echo "gc jvm .1"        > $KLOG/kafkaServer-gc.log.1
    echo "kafka stdout"     > $KLOG/kafka.log
    echo "orphan"           > $KLOG/server.log.1-2026100700.backup
    echo "orphan"           > $KLOG/kafkaServer-gc.log.1-2026100700.backup
    echo "zk server live"   > $ZLOG/server.log
    echo "zk server .1"     > $ZLOG/server.log.1
    echo "zk gc live"       > $ZLOG/zookeeper-gc.log
    echo "zk stdout"        > $ZLOG/zookeeper.log
    echo "orphan"           > $ZLOG/zookeeper-gc.log.1-2026100700.backup
}

seed
# reset committed settings: CommitCheck short-circuits when nothing changed
: > /etc/settings.txt
cat >/tmp/settings.txt <<SETTINGS
cubesys.role=compute
net.hostname=node4
SETTINGS
# non-zero exit is not a failure here: only the module under test is linked
./hex_config -vvve commit /tmp/settings.txt >/tmp/commit_kafka.log 2>&1 || true

# ---- 1. one rotator: logrotate names only the stdout logs ----
[ "$(head -1 /etc/logrotate.d/kafka)" = "$KLOG/kafka.log {" ] \
    || fail "kafka logrotate target is '$(head -1 /etc/logrotate.d/kafka)'"
[ "$(head -1 /etc/logrotate.d/zookeeper)" = "$ZLOG/zookeeper.log {" ] \
    || fail "zookeeper logrotate target is '$(head -1 /etc/logrotate.d/zookeeper)'"
grep -q copytruncate /etc/logrotate.d/kafka || fail "kafka: copytruncate dropped"
echo "  ok  logrotate.d names kafka.log / zookeeper.log only"

# ---- 2. prune: orphans gone, live logs and app generations kept ----
[ -z "$(find $KLOG $ZLOG -name '*.backup')" ] \
    || fail "commit left *.backup: $(find $KLOG $ZLOG -name '*.backup' | xargs)"
for f in $KLOG/server.log $KLOG/server.log.1 $KLOG/kafkaServer-gc.log.1 $KLOG/kafka.log \
         $ZLOG/server.log.1 $ZLOG/zookeeper.log; do
    [ -f $f ] || fail "prune removed $f"
done
echo "  ok  commit pruned *.backup and nothing else"

# ---- 3. a forced rotation makes no *.backup ----
if ! command -v logrotate >/dev/null 2>&1; then
    echo "  skip logrotate not installed"
else
    seed
    rm -f $KLOG/*.backup $ZLOG/*.backup
    # the node's /etc/logrotate.conf supplies "rotate 14"; without it rotate is 0 and
    # logrotate keeps no generation at all
    { echo "rotate 14"; cat /etc/logrotate.d/kafka /etc/logrotate.d/zookeeper; } \
        > /tmp/logrotate_kafka.conf
    logrotate -f -s /tmp/logrotate_kafka.state /tmp/logrotate_kafka.conf \
        >/tmp/logrotate_kafka.log 2>&1
    grep -q "already exists" /tmp/logrotate_kafka.log \
        && fail "logrotate collided: $(grep 'already exists' /tmp/logrotate_kafka.log)"
    [ -z "$(find $KLOG $ZLOG -name '*.backup')" ] || fail "forced rotation made *.backup"
    [ "$(cat $KLOG/server.log.1)" = "server log4j .1" ] || fail "log4j's server.log.1 was moved"
    [ "$(cat $KLOG/server.log)" = "server live" ] || fail "server.log was truncated by logrotate"
    [ -f $KLOG/kafka.log.1.gz ] || fail "kafka.log was not rotated"
    [ -f $ZLOG/zookeeper.log.1.gz ] || fail "zookeeper.log was not rotated"
    echo "  ok  forced rotation: stdout rotated, log4j/JVM files untouched, no *.backup"

    # negative control: the pre-#1767 glob over the same files does collide
    seed
    rm -f $KLOG/*.backup
    { echo "rotate 14"; sed "1s|.*|$KLOG/*.log {|" /etc/logrotate.d/kafka; } > /tmp/logrotate_kafka.old
    logrotate -f -s /tmp/logrotate_kafka.state2 /tmp/logrotate_kafka.old >/dev/null 2>&1
    [ -n "$(find $KLOG -name 'server.log.1-*.backup')" ] \
        || fail "control: the old *.log glob made no *.backup -- this test proves nothing"
    echo "  ok  control: the old *.log glob still collides"
fi

echo "config_kafka: all cases passed"
