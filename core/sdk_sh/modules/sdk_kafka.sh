# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

kafka_stats()
{
    /opt/kafka/bin/kafka-topics.sh --describe --bootstrap-server $HOSTNAME:9095 2>/dev/null
}

# Target replication factor for this cluster: one replica per control node, capped at 3.
# Mirrors TargetRF() in config_kafka.cpp, so a topic created by either route lands the
# same way. Capped rather than fixed at 3 because a 2-control-node HA is expressible and
# asking for more replicas than brokers fails outright.
kafka_target_rf()
{
    local n=$(cubectl node list -r control 2>/dev/null | wc -l)
    [ "${n:-1}" -gt 3 ] && n=3
    echo ${n:-1}
}

# Raise the replication factor of every existing topic to kafka_target_rf.
#
# The broker settings bind only at topic-creation time, so on their own they fix new
# clusters and nothing else. Any cluster that has already run -- including every one
# upgrading from 3.1.10 or older -- keeps whatever RF its topics were born with, because
# `kafka-topics.sh --create --if-not-exists` is a no-op on an existing topic and `--alter`
# changes the partition count only. Raising RF in place is a partition reassignment.
#
# Idempotent: partitions already at the target are skipped, so the second and third
# control node to call this find nothing to do.
kafka_topic_rf_reconcile()
{
    is_control_node || return 0

    local bs=${1:-$HOSTNAME:9095}
    local rf=$(kafka_target_rf)
    [ "$rf" -lt 2 ] && return 0

    # A reassignment that names an offline broker never completes, and while it is
    # pending no other reassignment can start. Only run with the whole cluster present.
    local want=$(cubectl node list -r control 2>/dev/null | wc -l)
    local live=$(/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server $bs 2>/dev/null | grep -c "id:")
    if [ "$live" -lt "$want" ] ; then
        log_warning "kafka_topic_rf_reconcile: $live/$want brokers online, deferring"
        return 0
    fi

    local plan=$(mktemp /tmp/kafka-rf-XXXXXX.json)
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server $bs --describe 2>/dev/null | \
      RF=$rf python3 -c '
import json, os, re, sys
from collections import Counter

rf = int(os.environ["RF"])
brokers, parts = set(), []
for line in sys.stdin:
    m = re.search(r"Topic:\s*(\S+)\s+Partition:\s*(\d+)\s+Leader:\s*(\S+)\s+Replicas:\s*([0-9,]*)", line)
    if not m:
        continue
    reps = [int(x) for x in m.group(4).split(",") if x != ""]
    brokers.update(reps)
    parts.append((m.group(1), int(m.group(2)), reps))

# every broker holding a replica anywhere is a placement candidate
ids = sorted(brokers)
load = Counter()
for _, _, reps in parts:
    load.update(reps)
for b in ids:
    load.setdefault(b, 0)

out = []
for topic, pid, reps in parts:
    if len(reps) >= rf:
        continue
    # keep the current replicas -- the leader stays first, so no leadership churn --
    # and fill from the least-loaded broker not already holding this partition, which
    # keeps the new followers spread instead of piling onto one broker
    new = list(reps)
    while len(new) < rf:
        cand = min((b for b in ids if b not in new), key=lambda b: (load[b], b))
        new.append(cand)
        load[cand] += 1
    out.append({"topic": topic, "partition": pid, "replicas": new})

json.dump({"version": 1, "partitions": out}, sys.stdout)
' > $plan 2>/dev/null

    local n=$(python3 -c "import json;print(len(json.load(open('$plan'))['partitions']))" 2>/dev/null || echo 0)
    if [ "${n:-0}" -eq 0 ] ; then
        rm -f $plan
        return 0
    fi

    log_info "kafka_topic_rf_reconcile: raising $n partition(s) to RF $rf"
    if ! Quiet /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $bs \
            --reassignment-json-file $plan --execute ; then
        # a peer control node got there first, or one is still running
        log_warning "kafka_topic_rf_reconcile: reassignment not accepted, leaving it to the peer"
        rm -f $plan
        return 0
    fi

    local i
    for i in $(seq 1 60) ; do
        /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $bs \
          --reassignment-json-file $plan --verify 2>/dev/null | grep -q "is still in progress" || break
        sleep 5
    done
    if /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $bs \
         --reassignment-json-file $plan --verify 2>/dev/null | grep -q "is still in progress" ; then
        log_warning "kafka_topic_rf_reconcile: still in progress after 300s, will retry next run"
    else
        log_info "kafka_topic_rf_reconcile: done, $n partition(s) now at RF $rf"
    fi
    rm -f $plan
    return 0
}
